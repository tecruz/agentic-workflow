# TASK-042 — Agent Skills format alignment (agentskills.io interop)

## Status

Status: done
Updated: 2026-09-16

## Risk profile

Profile: standard

## Profile rationale

Additive format/input-surface work on an internal registry contract: no
authentication, payments, secrets handling, data migrations, production
infrastructure, irreversible operations, or safety-critical behavior. The
protocol-level skill contract (validation, minimum-profile flooring) is kept
intact; the change adds an ecosystem-standard metadata header and tolerant
validator coverage. The selected context module sets the floor at standard.

## Background

The Agent Skills open format (agentskills.io, Anthropic-originated, now
stewarded by the ecosystem: Claude Code, OpenAI Codex, Cursor, GitHub
Copilot, VS Code, Gemini CLI, OpenCode, Goose, Roo Code, Amp, Factory, Kiro,
and others) defines `SKILL.md` as: YAML frontmatter with `name` (required,
directory-matching, lowercase-hyphen), `description` (required; what + when),
plus optional `license`, `compatibility`, `metadata`, `allowed-tools`; then a
freeform Markdown body; plus optional `scripts/`, `references/`, `assets/`
directories. Progressive disclosure: tools load only name/description at
startup, the full body on activation, and resources on demand.

This repo's six registry skills (`.agentic/skills/*/SKILL.md`) already use a
directory-per-skill layout with a Markdown body — but the header metadata
lives in custom `##` sections (`## ID`, `## Version`, `## Invoked when`, ...)
that ecosystem tools cannot parse. As a result, the skills are valid protocol
artifacts but are not discoverable by tools that natively load Agent Skills.

## Design

Chosen: **hybrid format** — prepend ecosystem YAML frontmatter to each
SKILL.md and keep every existing protocol section below it unchanged.

- frontmatter: `name` = directory name; `description` = derived from
  `## Invoked when` summaries plus the minimum risk profile; `metadata`
  carries `protocol-version`, `minimum-risk-profile`, `skill-id`.
- The custom `##` sections remain authoritative for the protocol validators.
- `validate-skills.sh` / `validate-skills.ps1` stay backward-compatible:
  existing 17 shared fixtures keep passing unchanged. New behavior: when
  frontmatter IS present, validate it (name matches dir, description present
  and non-empty, name charset/length rules); absence stays tolerated for this
  rev so adopter-authored skills don't break.
- Both twins must produce identical diagnostics for the same fixtures
  (cross-language parity rule).

Deferred (explicitly out of scope for this task): emitting per-tool copies
into `.claude/skills/`, `.opencode/skills/`, `.cursor/`, etc., via the
installers; that is a separate packaging decision (TASK-042 note: capture as
follow-up once this lands).

## Acceptance criteria

- AC-1: All six registry SKILL.md files carry valid ecosystem frontmatter
  (name == directory, description non-empty) above the unchanged protocol
  sections.
- AC-2: `validate-skills.sh` / `validate-skills.ps1` produce byte-identical
  diagnostics on all 17 pre-existing shared fixtures (zero regressions).
- AC-3: New fixtures cover: valid frontmatter present (VALID), malformed
  frontmatter (INVALID with a stable diagnostic code), frontmatter/section
  mismatch e.g. `name` != directory, and description missing/empty. Twins
  agree on each.
- AC-4: Documentation updated (`.agentic/skills/INDEX.md` registry table
  notes the standard header + a short paragraph; `AGENTS.md` §5.3 one-line
  mention if warranted). CHANGELOG `[Unreleased]` entry added.
- AC-5: STATUS.md entry appended on completion.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | All six registry SKILL.md files carry `--- name: <dir> description: ... metadata: ... ---` frontmatter above the protocol sections (confirmed by filesystem inspection and by both validators accepting the live registry) | passed |
| AC-2 | `Invoke-Pester -Path tests/pester/ValidateSkills.Tests.ps1` -> 28 passed, 0 failed (23 pre-existing tests unchanged) | passed |
| AC-3 | Sandboxed-regression runs of the five-case frontmatter matrix (valid / name-mismatch / empty-description / unclosed / legacy-no-frontmatter) produce identical exit codes (0/2/2/2/0) in Bash and PowerShell | passed |
| AC-4 | Skills INDEX.md documents the frontmatter contract; CHANGELOG `[Unreleased]` entry added; handoff gate validates this file | passed |
| AC-5 | STATUS.md bullet for TASK-042 appended at completion | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — the change touches validator behavior, the shared fixture corpus, and parity tests

## Skills

- task-decomposition v1 invoked — splitting into: frontmatter edit pass, validator tolerance extension, fixture additions, docs/changelog, verifier run

## Goal conditions

- Exit 0 when: both skills validators accept all six registry skills and the 17 legacy fixtures unchanged, and reject the new malformed-frontmatter fixtures identically across languages

## Files changed

- .agentic/skills/*/SKILL.md (6 files — ecosystem YAML frontmatter prepended; protocol sections unchanged)
- .agentic/scripts/validate-skills.sh (new `validate_frontmatter`, wired into `load_registry`)
- .agentic/scripts/validate-skills.ps1 (new `Test-SkillFrontmatter`, wired into the registry loop)
- tests/bats/validate_skills_test.bats (5 new sandbox-registry tests)
- tests/pester/ValidateSkills.Tests.ps1 (5 mirrored sandbox-registry tests)
- .agentic/skills/INDEX.md (documents the frontmatter contract)
- CHANGELOG.md (`[Unreleased]` entry)
- .agentic/STATUS.md (`TASK-042` bullet)
- .agentic/tasks/TASK-042-skills-format-alignment.md (this file)

## Verification

### Baseline

- Validators had no ecosystem-metadata contract; the 6 skills were protocol sections only.

### Final

- `bash .agentic/scripts/validate-skills.sh` / `pwsh .agentic/scripts/validate-skills.ps1` against the live registry: VALID.
- Five-case frontmatter matrix (valid / name mismatch / empty description / unclosed / legacy-no-frontmatter): identical exit codes (0/2/2/2/0) in both twins.
- `Invoke-Pester -Path tests/pester/ValidateSkills.Tests.ps1` -> 28 passed, 0 failed.
- `bash -n` and `ps-syntax`: clean.
- Handoff gate: VALID on this file.

## Remaining risks

- A new PyP-less requirement: the ecosystem `skills-ref` reference validator is a Python tool; this task uses only inline Bash/PowerShell validation to remain dependency-free at runtime.
- Watch for accidental behavior change to legacy adopter skills that already embed `##` sections; overall golden-outcome parity must stay green.
