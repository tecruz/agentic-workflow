# TASK-047 — PR #27 review follow-ups

## Status

Status: done
Updated: 2026-09-24

## Risk profile

Profile: standard

## Profile rationale

Follow-up fixes from the PR #27 self-review, confined to advisory comment
emission (CI run-step hints), filename matching semantics, and test coverage.
No escalation signals: no authentication, payments, secrets handling, data
migrations, production infrastructure changes, irreversible operations, public
API compatibility, or privacy behavior; the new `--emit-ci-hints` /
`-EmitCiHints` mode is read-only stdout and mirrors the existing
`--emit-checks` trust pattern.

## Acceptance criteria

- AC-1: The verifier's own `--detect-checks` appends the same commented CI
  run-step hints the installer emits, so both candidate writers produce
  identical hint blocks for the same project (finding: entry-point asymmetry).
- AC-2: Hint emission lives once per language — in the verifier
  (`emit_ci_step_hints` / `Get-CiStepHints`) exposed as the read-only stdout
  mode `--emit-ci-hints` / `-EmitCiHints`; the installers delegate to it
  instead of keeping a private copy (finding: single-sourcing).
- AC-3: Workflow files with uppercase extensions (`CI.YML`, `CI.YAML`) are
  matched in the bash twin as well (`nocaseglob`), restoring parity with
  PowerShell's case-insensitive `-Filter`; pinned by one test per language
  (finding: case-insensitivity).
- AC-4: A workflows directory whose steps are exclusively `uses:` emits no
  hint header; pinned by one test per language (finding: missing negative).
- AC-5: Plan mode exits before the tail message — the pointer-note concern is
  verified non-applicable; no behavior change (finding: plan-mode note).
- AC-6: The TASK-045 CHANGELOG entry continuation is reflowed to the
  surrounding fixed-column style (finding: changelog wrap).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Bats `--detect-checks appends CI run-step hints when workflows exist` + Pester twin assert header, `ci.yml:8 run: npm test`, and the multi-line marker in the verifier-written candidate; manual scratch run byte-matches the installer-written tail | passed |
| AC-2 | Installer CI-hint tests (Bats 2/2, Pester via Install suite) stay green unchanged against the delegation; one hint implementation per language (`emit_ci_step_hints` in verify.sh, `Get-CiStepHints` in verify.ps1) | passed |
| AC-3 | Bats + Pester uppercase-extension tests (`CI.YML`) pass on WSL bash and Windows pwsh | passed |
| AC-4 | Bats + Pester uses-only tests assert no hint header | passed |
| AC-5 | `install.sh:1553` plan branch exits with "Plan complete" before the tail block; plan-mode tests unchanged and green; verified non-applicable, no edit made | passed |
| AC-6 | CHANGELOG TASK-045 entry continuation reflowed | passed |

## Goal conditions

- Exit 0 when: bash -lc "bats tests/bats/verify_test.bats"
- Exit 0 when: pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0; $r = Invoke-Pester -Script 'tests/pester/Verify.Tests.ps1' -PassThru; exit $r.FailedCount"

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds verifier regression tests in both suites

## Skills

- task-decomposition v1 invoked — five findings split into emitter/entry-point unification, case-insensitive matching, uses-only coverage, false-premise verification, docs polish, dual-suite tests

## Files changed

- .agentic/scripts/verify.sh
- .agentic/scripts/verify.ps1
- install.sh
- install.ps1
- tests/bats/verify_test.bats
- tests/pester/Verify.Tests.ps1
- CHANGELOG.md
- .agentic/STATUS.md
- .agentic/tasks/TASK-047-pr27-review-followups.md (this file)

## Verification

### Baseline

- PR #27 self-review recorded five non-blocking findings.
- Finding 2 premise check: `install.sh` runs the tail message only after
  `if [ "$PLAN" -eq 1 ]; then ... exit 0; fi` at line 1553, and the plan-mode
  seed line already says "(pointer to existing ...)" — the claimed
  inconsistency cannot occur; no edit.

### Final

- Manual scratch (package.json + ci.yml with uses/single-line/block run steps
  + uppercase `UP.YML`): `--emit-ci-hints`, verifier `--detect-checks`, and
  the installer's `--detect-checks` all emit the identical hint block in each
  language; no-workflows project emits zero hint lines; `UP.YML` matched.
- Byte check: the ps1-written candidate header contains U+2014 (dash) exactly
  like the bash twin (console display transcodes; content verified).
- `bats tests/bats/verify_test.bats` → 59/59 (3 new tests included).
- `bats --filter "CI run-step hints|CI hint block" tests/bats/install_test.bats`
  → 2/2 (delegation path). Full `install_test.bats` → only the 4 known
  zip-missing env failures (95/103/104/108), unchanged.
- `Invoke-Pester tests/pester/Verify.Tests.ps1` → 42/42.
- `Invoke-Pester tests/pester/Install.Tests.ps1` → 89 passed / 0 failed /
  2 skipped (delegation path covered by the pre-existing CI-hint tests).
- Fixture harnesses (correctly invoked with the verify-path argument): green
  in both twins. An earlier 61-failure alarm was harness misinvocation
  (`$1` unbound when called without the verify path), not a regression.
- `tests/parity/run-parity.sh` pwsh legs fail with exit 64 from WSL-driven
  Windows pwsh (relative write path under an interop cwd). Reproduced 3/3 on
  the un-stashed master tree → pre-existing host-environment gap, unchanged
  by this task; all suites pass natively on Windows.
- `bash -n` (verify.sh, install.sh) + `tests/ps-syntax.ps1` → exit 0.
- `validate-handoff.{sh,ps1}` on this task file → VALID in both twins.

## Remaining risks

- Hint-block line order across multiple workflow files follows each host's
  native sort (byte order in bash vs case-insensitive name sort in pwsh) when
  file names differ by case mixture; comments only, and single-workflow
  projects (the common case) are unaffected. Tolerable parity gap; not
  asserted by any harness today.
- Pre-existing host gaps are unchanged: `bats` absent from the Windows PATH,
  WSL lacks `zip` (4 bundle tests), WSL→pwsh interop fails the parity runner
  and health-report twin-parity test (exit 64).
