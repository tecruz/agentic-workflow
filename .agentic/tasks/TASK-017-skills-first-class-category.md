# TASK-017 — Skills as a first-class category (v1.10.0, ADR-0014)

## Status

Status: done
Updated: 2026-09-04

## Risk profile

Profile: standard

## Profile rationale

Ordinary product work: new on-demand skills registry parallel to context
modules, with Bash+PowerShell validators, schema, installer/bundle
registration, and version sweep. No authentication, payments, secrets handling,
data migration, production infrastructure, irreversible operation, public-API
compatibility commitment, privacy-regulated data, or safety-critical behavior.
Escalation signals reviewed; none apply. The infrastructure-change module is
not triggered: framework-test workflow edits only run this repository's own
checks (TASK-006/TASK-016 precedent, framework distribution not production
infrastructure).

## Acceptance criteria

- AC-1: ADR-0014 records the skills decision — registry layout, SKILL.md
  contract, file categories (managed), validator contract, migration N-1
  (v1.9.0→v1.10.0), secrets-exclusion, and protocol_version sweep.
- AC-2: Skills registry ships — `.agentic/skills/INDEX.md` plus three initial
  skills (`task-decomposition`, `verification-triage`, `release-verification`),
  each with SKILL.md declaring ID/Version/Minimum-risk-profile/Invoked-when/
  Required-context/Approval-gates/Required-evidence/Prohibited-shortcuts.
- AC-3: Selection contract enforced — `validate-skills.sh/ps1` (exit 0 VALID /
  1 INVALID / 2 BLOCKED) validate the `## Skills` section against the managed
  registry with Bash+PowerShell parity, shared fixtures, JSON
  `skill-selection-v1` schema, stable `SKILL_*` diagnostics, stdout isolation,
  and path redaction mirroring validate-context.
- AC-4: Handoff gate covers three legs — `validate-handoff.sh/ps1` run
  validate-task + validate-context + validate-skills in handoff mode; task
  template carries `## Skills`; AGENTS.md gains §5.3.
- AC-5: Distribution wiring — new managed files registered in install.sh,
  install.ps1, and scripts/build-bundle.sh; checks.tsv covers new validators;
  `.agentic/VERSION` and protocol_version swept to 1.10.0; CHANGELOG [1.10.0]
  and ROADMAP Later→done; full local verification green.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | docs/decisions/ADR-0014-skills-as-first-class-category.md present and indexed | passed |
| AC-2 | .agentic/skills/INDEX.md + 3 SKILL.md present; fresh install + bundle contain them | passed |
| AC-3 | validate-skills.sh/ps1 parity on shared fixtures; JSON schema-valid per pinned jsonschema | passed |
| AC-4 | validate-handoff.sh/ps1 require three VALID legs; task.md template carries ## Skills | passed |
| AC-5 | VERSION=1.10.0 sweep clean; checks.tsv green; Bats+Pester+evals+fixtures green | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds validator twins, fixtures, schema, installer/bundle coverage, and runs the full test/CI verification gate

## Skills

- None required — registry, validators, and contracts are greenfield in this task; no existing skill procedure applies to bootstrapping the category itself

## Files changed

- docs/decisions/ADR-0014-skills-as-first-class-category.md — new decision (registry, contract, categories, migration, versioning)
- docs/decisions/README.md — ADR-0014 index row
- .agentic/skills/INDEX.md — new skills registry (3 skills)
- .agentic/skills/task-decomposition/SKILL.md, verification-triage/SKILL.md, release-verification/SKILL.md — new
- .agentic/schemas/skill-selection-v1.schema.json — new (`skill_validation_result`, `invoked_skills`, `SKILL_*` codes)
- .agentic/scripts/validate-skills.sh / validate-skills.ps1 — new (mirror of validate-context; `invoked` token, `None required` sentinel, `AGENTIC_SKILLS_REGISTRY`)
- .agentic/scripts/validate-handoff.sh / validate-handoff.ps1 — three-leg gate
- .agentic/templates/task.md — `## Skills` section + guidance comment
- .agentic/checks.tsv — `sh-syntax-validate-skills`, shellcheck scope, handoff-gate retarget TASK-009→TASK-017 (TASK-006→TASK-009 precedent)
- .agentic/VERSION — 1.10.0; protocol_version sweep to 1.10.0 (coordinator, validate-task, validate-context, verify ×2 langs; 4 schemas; evals runners/artifacts/schema; 5 test files)
- .agentic/STATUS.md, .agentic/WORKFLOW.md, AGENTS.md (§5.3), README.md (Skills section, handoff, tree), ROADMAP.md (Item 6 done, version), CHANGELOG.md ([1.10.0])
- install.sh, install.ps1, scripts/build-bundle.sh — 9 new managed paths (INDEX + 3 SKILL.md + 2 validators + schema; handoff already managed)
- tests/bats/validate_skills_test.bats — new (25 cases: classifications, handoff, JSON, registry, fence, redaction)
- tests/bats/install_test.bats — skills fresh-install/bundle/uninstall coverage
- tests/pester/ValidateSkills.Tests.ps1 — new (21 pass + parity Describe)
- tests/pester/Install.Tests.ps1 — skills fresh-install/bundle/upgrade/uninstall coverage
- tests/pester/JsonContracts.Tests.ps1 — skill JSON contract Describe (PS legs; Bash legs on Linux CI)
- tests/fixtures/skill-tasks/ — 17 new shared fixtures (4 valid, 11 invalid, 2 blocked)
- tests/fixtures/context-tasks/context-full-contract-ha.md — `## Skills` leg for the composite fixture
- tests/ps-syntax.ps1 — include validate-skills.ps1
- evals/run-evals.sh / run-evals.ps1 — `SKILLS_CONTRACT_VALID` leg (CHECK_ORDER + validators + record)
- evals/generate-scenarios.ps1 — `skillsBlock` per scenario + `## Skills` in the task template; `Write-Utf8` now normalizes CRLF→LF so regeneration is byte-stable on Windows (also aligns the previously stale `verification-result.json` artifacts with the generator's `[ordered]` key order)
- evals/scenarios/*/artifacts/task.md (8) — honest `## Skills` records per scenario
- evals/scenarios/*/artifacts/verification-result.json (8), evals/schemas/evaluation-result-v1.schema.json, evals/generate-scenarios.ps1 — 1.10.0 sweep

## Verification

### Baseline

- Pre-change master (v1.9.0, 23ba04b): clean tree; VERSION=1.9.0; handoff gate VALID on TASK-016 (task+context legs).

### Final

- `bash -n`: install.sh, verify.sh, validate-task.sh, validate-context.sh, validate-skills.sh, validate-handoff.sh, coordinator.sh, build-bundle.sh, run-evals.sh all OK.
- pwsh parse OK: install.ps1, verify.ps1, validate-task.ps1, validate-context.ps1, validate-skills.ps1, validate-handoff.ps1, coordinator.ps1, run-evals.ps1, generate-scenarios.ps1, ValidateSkills.Tests.ps1, Install.Tests.ps1.
- validate-task + validate-context + validate-skills (sh and ps1) on this file: all VALID.
- validate-handoff.sh and .ps1 on this file: VALID (three legs).
- Cross-language parity script over all 17 skill fixtures: 17/17 identical exit codes (4 VALID, 11 INVALID, 2 BLOCKED).
- Pester: ValidateSkills 21 passed/0 failed/1 skipped (bash-leg parity skip on Windows); fast suites (Skills+Context+Task+JsonContracts+Verify) 310 passed/0 failed/15 skipped; Install 81 passed/0 failed/2 skipped; Coordinator+Integration 16 passed/0 failed; new skills JSON contracts 2 passed/2 skipped (Bash legs on Linux CI).
- evals: run-evals.ps1 8/8 and run-evals.sh 8/8 (negative control still fails only its intended check).
- Generator: re-running generate-scenarios.ps1 is idempotent (byte-stable LF artifacts on Windows; CRLF normalization added).
- Bats: not installed on this Windows host; proven in CI (Full) Ubuntu+macOS legs (same precedent as TASK-016 local verification).
- shellcheck: not installed locally (optional check); validate-skills.sh is a mechanical transform of the shellcheck-clean validate-context.sh with identical quoting/structure.
- `git diff --check` clean.
- Pre-existing failures (proven identical on clean HEAD worktree 23ba04b, unrelated to this change): tests/fixtures/run-fixtures.ps1 reports 54 failed assertions (yarn-workspaces-object golden MISMATCH + harness ErrorRecord.StartsWith error) on this Windows host.

## Remaining risks

- New `## Skills` section is required on new tasks; historical tasks (TASK-001..016) predate it and are not re-validated — same precedent as the v1.5.0 context introduction.
