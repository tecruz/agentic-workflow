# TASK-026 — task-file validator drift + health-report cross-language parity

## Status

Status: done
Updated: 2026-09-08

## Risk profile

Profile: standard

## Profile rationale

Documentation hygiene and test coverage only — no authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply.

## Acceptance criteria

- AC-1: Every task file under `.agentic/tasks/` passes `validate-task.sh`
  (sweep shows zero failures, including the two pre-template stragglers
  TASK-015 and TASK-023).
- AC-2: TASK-015 rewritten into the current task template (Status, Risk
  profile, AC/evidence, Verification, Remaining risks) without falsifying its
  historical record; TASK-023 gains the missing `## Verification` /
  `## Remaining risks` sections.
- AC-3: health-report twins get a cross-language parity test: normalized
  output (blank lines, timestamp, VERSION block excluded) must be identical
  between `health-report.sh` and `health-report.ps1`, and both must scan the
  same emitter set.
- AC-4: Parity test ships in both suites (Bats + Pester); the Pester leg
  skips on Windows (bash-leg precedent) and runs on the Ubuntu/macOS full
  legs.
- AC-5: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Sweep of all 25 task files: 25 ok, 0 FAIL after the TASK-015/023 fixes | passed |
| AC-2 | TASK-015 diff: full template rewrite with historical facts preserved; TASK-023 diff: Verification + Remaining risks sections added | passed |
| AC-3 | Local parity check: normalized output identical (41 lines) modulo the Windows-console UTF-8 capture artifact; emitter sets match 11/11 | passed |
| AC-4 | Pester local run: 3 passed, 1 skipped (Windows), 0 failed; bats leg verified in CI Full (Ubuntu + macOS) — run 34294237398, 5/5 green after the BSD-sed→awk normalize fix | passed |
| AC-5 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — test-harness and validator-compliance changes

## Skills

- task-decomposition v1 invoked — drift sweep, template rewrite, and parity-test design decomposed into separate steps

## Files changed

- .agentic/tasks/TASK-015-v180-release-bookkeeping.md — rewritten to the current task template (historical content preserved)
- .agentic/tasks/TASK-023-v1121-release-bookkeeping.md — `## Verification` + `## Remaining risks` added
- tests/bats/health_report_test.bats — cross-language parity test added; VERSION-block normalization uses awk (BSD sed rejects the inline `{..}` range block used initially)
- tests/pester/HealthReport.Tests.ps1 — parity test twin (skips on Windows)
- .agentic/tasks/TASK-026-task-drift-and-health-parity.md (new)

## Verification

### Baseline

- Two task files failed `validate-task.sh`: TASK-015 (pre-template format, no
  `Profile:`) and TASK-023 (missing `## Verification` section). No
  health-report output-parity test existed.

### Final

- Task sweep: 25/25 ok, 0 FAIL.
- Parity check: normalized report output identical between twins
  (41 lines); emitter sets match (11 emitters, incl. run-evals.sh); both
  report CONSISTENT. Local comparison strips non-ASCII because the Windows
  console (ibm850) mangles UTF-8 capture — on Linux/macOS CI both twins emit
  identical UTF-8 bytes.
- Pester local run: HealthReport 3 passed / 1 skipped (Windows parity skip) /
  0 failed.
- bats/shellcheck not installed on this host — bats leg proven in CI Full per
  TASK-019 precedent.

## Remaining risks

- The parity test excludes the VERSION Consistency block's ordering (bash
  sorts by full path, pwsh by short name); block membership and consistency
  status are still asserted on both sides.
- Non-ASCII literals in the report render identically on Unix CI but are
  byte-dependent; the tests anchor on ASCII section names to stay robust.
- First CI pass on macOS caught a BSD-sed incompatibility (inline `{..}`
  range block rejected); fixed by moving VERSION-block exclusion into awk —
  the bats leg is green on both platforms at the final commit.