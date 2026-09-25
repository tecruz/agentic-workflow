# TASK-045 — Installer seeds an architecture pointer when the project already has one

## Status

Status: done
Updated: 2026-09-21

## Risk profile

Profile: standard

## Profile rationale

Additive installer behavior: on fresh installs only, when the adopting project
already has an architecture document (`ARCHITECTURE.md` or
`docs/ARCHITECTURE.md`), the `.agentic/ARCHITECTURE.md` seed becomes a stable
pointer to it instead of the blank template. No authentication, payments,
secrets, data migrations, production infrastructure, irreversible operations,
public API compatibility, privacy, or safety-critical behavior. Seeds are
project-owned and never overwritten, so existing adopters are untouched; the
new branch only activates for files that do not yet exist.

## Acceptance criteria

- AC-1: Fresh install into a project with `ARCHITECTURE.md` (repo root) writes
  `.agentic/ARCHITECTURE.md` as a pointer naming the canonical doc, not the
  template placeholders; the manifest still records it as a seed entry.
- AC-2: Same behavior for `docs/ARCHITECTURE.md`; a project with neither gets
  the unchanged template verbatim.
- AC-3: Bash and PowerShell installers behave identically (same detection
  order, same pointer text, same skip semantics for an existing
  `.agentic/ARCHITECTURE.md`), covered by one Bats and one Pester test per
  scenario class.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Bats + Pester: install into tmp with root ARCHITECTURE.md asserts pointer text + manifest `seed` record | passed |
| AC-2 | Bats + Pester: docs/ARCHITECTURE.md pointer variant; no-doc install still seeds the template marker ("bracketed placeholders") | passed |
| AC-3 | Symmetric assertions pass in both suites: bats filtered run 5/5 (4 new + seed-preservation), Pester Install.Tests.ps1 87 passed / 0 failed / 2 platform skips | passed |

## Goal conditions

- Exit 0 when: bash -lc "bats tests/bats/install_test.bats"
- Exit 0 when: pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0; $r = Invoke-Pester -Script 'tests/pester/Install.Tests.ps1' -PassThru; exit $r.FailedCount"

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds installer regression tests in both suites

## Skills

- task-decomposition v1 invoked — split into: bash leg, ps1 leg, dual-suite tests, docs/changelog, verification

## Files changed

- install.sh
- install.ps1
- tests/bats/install_test.bats
- tests/pester/Install.Tests.ps1
- README.md
- CHANGELOG.md
- .agentic/STATUS.md
- .agentic/tasks/TASK-045-architecture-pointer-seed.md (this file)

## Verification

### Baseline

- User observation (CountryTrackerApp): the project already ships
  `ARCHITECTURE.md`, but install seeds the generic `.agentic/ARCHITECTURE.md`
  template and never references the existing doc — agents are pointed at an
  unfilled placeholder.
- Source inspection: `install_seed` copies `$SOURCE_DIR/.agentic/ARCHITECTURE.md`
  verbatim for every fresh install (install.sh:1446-1448 loop); no
  pre-existing-doc probe exists in either twin.

### Final

- Manual scratch installs verified both twins end-to-end: PS into a dir with
  root `ARCHITECTURE.md` → pointer seed + adapted final hint; Bash (WSL) into
  a dir with only `docs/ARCHITECTURE.md` → pointer seed named
  `docs/ARCHITECTURE.md`, manifest records `seed`.
- `bats --filter` over the five (4 new + 1 adjacent) install tests → 5/5 pass.
- `Invoke-Pester -Script tests/pester/Install.Tests.ps1` → 87 passed / 0
  failed / 2 skipped (platform guards), includes the 4 new tests.
- Full `bats tests/bats/install_test.bats`: 107 ok / 4 not ok, all four in the
  bundle/zip tests because `zip` is not installed in this WSL environment
  (build-bundle.sh prints "WARNING: 'zip' utility not found on Unix; skipping
  zip archive"); pre-existing environmental gap, unrelated to the installer
  change.
- `bash -n install.sh`, `bash -n .agentic/scripts/verify.sh`,
  `tests/ps-syntax.ps1` → all exit 0.
- Full-repo gate legs for the final tree (covering TASK-044/045/046) are
  recorded in TASK-046's `### Final` section: pester 438 passed / 0 failed,
  evals 19/19 in both twins, syntax checks 0; `bats` leg BLOCKED on this host
  (pre-existing; run manually under WSL).
- `validate-handoff.{sh,ps1}` on this task file → VALID in both twins.

## Remaining risks

- Pointer seed content is CRLF under PowerShell on Windows vs LF under Bash
  (matches the codebase's other generated-file convention); detection of the
  canonical doc is limited to `ARCHITECTURE.md` and `docs/ARCHITECTURE.md` by
  design.
- `tests/bats/install_test.bats` emits four zip-dependent failures on hosts
  without `zip` (this WSL environment); CI runners have zip installed.
