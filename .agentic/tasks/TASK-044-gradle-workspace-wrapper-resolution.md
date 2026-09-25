# TASK-044 — Workspace-module Gradle checks resolve the root wrapper

## Status

Status: done
Updated: 2026-09-21

## Risk profile

Profile: standard

## Profile rationale

Detection plumbing in the verifier twins (`verify.ps1` / `verify.sh`) plus
fixture and regression-test additions. No authentication, payments, secrets,
data migrations, production infrastructure, irreversible operations, public
API compatibility commitments, privacy, or safety-critical behavior. The
change only alters which executable string is *emitted* for workspace-module
Gradle checks (root wrapper via a relative path instead of a bare `gradle`
fallback); it cannot break adopters who previously passed, because a module
wrapper never existed in module directories by Gradle convention — the old
branch always fell through to `gradle`. Selected context module
(testing-infrastructure) matches the fixture/test-harness scope.

## Root cause (from user report)

A `settings.gradle(.kts)` multi-module Android project with the wrapper at the
root emitted `required app-gradle-test app gradle test` and
`required app-gradle-lint app gradle check`: `Emit-PackageChecks` /
`emit_checks_for_dir` looked for `gradlew` inside the *module* directory only,
where Gradle builds never place one, so both checks fell back to a global
`gradle` install and reported `BLOCKED: executable 'gradle' was not found`
even though the root-level `android-*` checks were happily using
`.\gradlew.bat`. Check exe resolution treats separator-qualified executables
as relative to the check's working directory, so the fix emits the wrapper at
the ancestor where it is found as a relative path (`../gradlew.bat`,
`../../gradlew`, ...).

## Acceptance criteria

- AC-1: For a Gradle workspace module without its own wrapper, emitted module
  checks reference the nearest ancestor wrapper as a relative path resolvable
  from the module cwd (`../gradlew.bat` on Windows PowerShell,
  `./gradlew`-style sibling forms elsewhere; nested modules gain one `../`
  per depth level). Falls back to `gradle` only when no ancestor (up to the
  invocation root) provides a wrapper.
- AC-2: Root-level and module-local-wrapper contracts are byte-identical to
  before (`.\gradlew.bat` / `./gradlew.bat` / `./gradlew` / `gradle` shapes
  unchanged); all existing goldens pass unmodified.
- AC-3: New `gradle-wrapper-multimodule` fixture (root wrapper + `app` +
  `lib/core`) plus one Pester and one Bats regression test pin the relative
  path behaviour, including the two-level `../../gradlew` case.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `--emit-checks` on the new fixture: `app-gradle-test app ../gradlew.bat test` and `lib-core-gradle-test lib/core ../../gradlew.bat test` under PowerShell; `../gradlew` / `../../gradlew` under Bash | passed |
| AC-2 | Both fixture harnesses green with zero golden changes: run-fixtures.ps1 61 assertions OK, run-fixtures.sh all OK incl. unchanged gradle-multimodule `gradle` fallback | passed |
| AC-3 | Bats `tests/bats/verify_test.bats` 56/56; Pester `tests/pester/Verify.Tests.ps1` 39/39 — both include the new workspace-wrapper regression test | passed |

## Goal conditions

- Exit 0 when: bash tests/fixtures/run-fixtures.sh .agentic/scripts/verify.sh
- Exit 0 when: pwsh -NoProfile -File tests/fixtures/run-fixtures.ps1 .agentic/scripts/verify.ps1
- Exit 0 when: bash -lc "bats tests/bats/verify_test.bats"
- Exit 0 when: pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0; $r = Invoke-Pester -Script 'tests/pester/Verify.Tests.ps1' -PassThru; exit $r.FailedCount"

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds a detection fixture and Bats/Pester regression tests to the verification harness

## Skills

- verification-triage v1 invoked — diagnosed a BLOCKED verification report to its root cause (module-dir wrapper lookup) before repairing

## Files changed

- .agentic/scripts/verify.ps1
- .agentic/scripts/verify.sh
- tests/fixtures/gradle-wrapper-multimodule/ (new: build.gradle, settings.gradle, gradlew, gradlew.bat, app/build.gradle, lib/core/build.gradle)
- tests/fixtures/run-fixtures.ps1
- tests/fixtures/run-fixtures.sh
- tests/pester/Verify.Tests.ps1
- tests/bats/verify_test.bats
- CHANGELOG.md
- .agentic/STATUS.md
- .agentic/tasks/TASK-044-gradle-workspace-wrapper-resolution.md (this file)

## Verification

### Baseline

- User report (CountryTrackerApp, Android + `settings.gradle.kts` module
  `app`): root `android-*` checks ran green via `.\gradlew.bat`, then
  `app-gradle-test` / `app-gradle-lint` reported
  `BLOCKED: executable 'gradle' was not found` → overall
  `VERIFICATION BLOCKED: 4 check(s) ran` despite a fully working Gradle
  wrapper at the project root.
- Source inspection: `Emit-PackageChecks` (verify.ps1) and
  `emit_checks_for_dir` (verify.sh) probed `$dir/gradlew*`; Gradle builds ship
  their wrapper at the workspace root, never inside modules, so the
  module-local branch was dead code and every workspace module emission used
  the bare `gradle` fallback.

### Final

- New fixture `gradle-wrapper-multimodule` emits, in both twins:
  `required app-gradle-test app ../gradlew.bat test` (PS, Windows) /
  `../gradlew` (Bash) and `required lib-core-gradle-test lib/core
  ../../gradlew.bat test` / `../../gradlew` — no bare `gradle` anywhere while
  a wrapper exists.
- `bash tests/fixtures/run-fixtures.sh .agentic/scripts/verify.sh` → all
  assertions OK (exit 0), incl. the new fixture row and all 25 goldens.
- `pwsh -NoProfile -File tests/fixtures/run-fixtures.ps1 .agentic/scripts/verify.ps1`
  → all 61 assertions OK (exit 0); existing goldens byte-identical.
- `bash -lc 'bats tests/bats/verify_test.bats'` → 56/56 pass, incl. new test
  44 (workspace modules emit the root Gradle wrapper as a relative path).
- `Invoke-Pester -Script tests/pester/Verify.Tests.ps1` → 39/39 pass,
  incl. the new workspace-wrapper regression test.
- Full gate `pwsh -NoProfile -File .agentic/scripts/verify.ps1` → exit 2
  (VERIFICATION BLOCKED): sh-syntax ×8 PASS, handoff-gate PASS, ps-syntax
  PASS, pester PASS (456 discovered / 432 passed / 0 failed / 24 platform
  skips), evals-sh PASS 19/19, evals-ps PASS 19/19; the `bats` leg is BLOCKED
  because `bats` is absent from this host's Windows PATH (it lives under Git
  Bash only). Pre-existing environment gap, unrelated to the change; the bats
  leg was therefore executed manually under Git Bash (see above).
- Pre-existing failure: `tests/bats/health_report_test.bats` test
  "health-report twins emit identical normalized output" fails on this host
  under Git Bash (pwsh child exits 64). `health-report.sh` /
  `health-report.ps1` are untouched by this diff and the Pester
  HealthReport.Tests parity leg passes — classified pre-existing/environmental.

## Remaining risks

- The Maven workspace-module branch (`mvnw` probed inside the module dir) has
  the same latent shape; intentionally untouched here to keep the diff scoped
  to the reported Gradle defect — follow-up candidate.
- The new fixture's `gradlew` is staged with mode 100755 via
  `git update-index --chmod=+x` (required so the Bash leg detects it on
  Linux/macOS checkouts). Staged only — no commit created.
- On Windows hosts without `bats` on PATH, the project's own
  `.agentic/scripts/verify.ps1` reports BLOCKED on the bats leg; use Git Bash
  (`bats tests/bats`) for the shell-test evidence, as done here.
