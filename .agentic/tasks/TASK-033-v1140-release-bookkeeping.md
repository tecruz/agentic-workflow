# TASK-033 — v1.14.0 release bookkeeping

## Status

Status: done
Updated: 2026-09-10

## Risk profile

Profile: standard

## Profile rationale

Release bookkeeping (version bump, sweep, changelog, roadmap) — no
authentication, payments, secrets handling, data migration, production
infrastructure change, irreversible operation, public-API compatibility
commitment, privacy-regulated data, or safety-critical behavior. The tag
push and GitHub release are gated on explicit user approval and happen
after this task's verification.

## Acceptance criteria

- AC-1: `.agentic/VERSION` reads `1.14.0` and every `protocol_version`
  site covered by the CI sweep gate agrees (`1.14.0`), with no stray
  `1.13.0` in gate paths.
- AC-2: All 12 eval artifacts regenerated with the new version; both
  eval twins classify 12/12.
- AC-3: `CHANGELOG.md` `## [Unreleased]` becomes `## [1.14.0] -
  2026-09-10` with the five post-v1.13.0 changes documented.
- AC-4: `ROADMAP.md` current-state line updated to `1.14.0` with the
  post-v1.13.0 hygiene summary.
- AC-5: Version-asserting test files (4 bats + 4 pester) swept to
  `1.14.0`.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | sweep-verify script: "PASS: all protocol_version sites agree on 1.14.0" + "PASS: no stray 1.13.0 in gate paths" | passed |
| AC-2 | generate-scenarios.ps1 regenerated 12 scenarios; run-evals.sh and run-evals.ps1 each 12/12 | passed |
| AC-3 | CHANGELOG.md: `[1.14.0] - 2026-09-10` section with Added/Fixed/Changed entries | passed |
| AC-4 | ROADMAP.md current-state line: `1.14.0` + post-v1.13.0 hygiene note | passed |
| AC-5 | sed sweep over 28 files (10 emitters, 7 schemas, 3 eval scripts, 8 test files); validate-context.sh/validate-skills.sh had 2 occurrences each | passed |

## Approval gates

- None identified

## Context modules

- None selected — release bookkeeping does not trigger any specialist module

## Skills

- None required — mechanical sweep and documentation

## Files changed

- .agentic/VERSION — 1.13.0 → 1.14.0
- 10 emitters (verify, validate-task/context/skills, coordinator × 2 langs)
- 7 schemas (5 in .agentic/schemas/, 2 in evals/schemas/)
- 3 eval scripts (run-evals.sh/.ps1, generate-scenarios.ps1)
- 12 regenerated scenario verification-result.json artifacts
- 8 version-asserting test files (4 bats, 4 pester)
- CHANGELOG.md, ROADMAP.md
- .agentic/tasks/TASK-033-v1140-release-bookkeeping.md (new)

## Verification

### Baseline

`## [Unreleased]` held the post-v1.13.0 work (TASK-026 through
TASK-032); VERSION and all `protocol_version` sites read `1.13.0`.

### Final

- CI sweep-gate simulation passes: all `protocol_version` sites agree on
  `1.14.0`; zero strays.
- Both eval twins: 12/12 with regenerated artifacts.
- Handoff gate VALID on this task file (both legs).
- Tag `v1.14.0` was created on the release head and the GitHub release was
  published with 3 assets (tar.gz, zip, SHA256SUMS) — recorded in TASK-036.

## Remaining risks

- Version-asserting bats suites cannot run on this host (no bats);
  CI validates them on Linux/macOS, as for every prior release task.
