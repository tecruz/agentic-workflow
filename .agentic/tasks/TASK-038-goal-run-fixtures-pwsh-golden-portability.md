# TASK-038 — Goal-run fixtures and Windows PowerShell golden-harness portability

## Status

Status: done
Updated: 2026-09-12

## Risk profile

Profile: standard

## Profile rationale

Test-only work: two structural task fixtures, two golden rows, and a
portability fix in the cross-language parity harness so the PowerShell golden
leg runs under WSL/MSYS bash on Windows. No authentication, payments, secrets
handling, data migrations, production infrastructure, irreversible operations,
public API compatibility commitments, privacy-regulated data, or safety-critical
behavior. The selected context module and invoked skills require no escalation.
No dependencies added; no files deleted.

## Acceptance criteria

- AC-1: Two new structurally valid standard-profile fixtures ship —
  `tests/fixtures/tasks/goal-run-unsafe.md` (unsafe `rm -rf /` goal command)
  and `tests/fixtures/tasks/goal-run-timeout.md` (goal command that would
  exceed the 30s run-goal budget) — each passing both task validators.
- AC-2: `tests/parity/task-expectations.tsv` carries exactly one golden row per
  new fixture (`0 VALID: profile=standard`), and the reverse completeness check
  stays green in both golden legs.
- AC-3: `tests/parity/run-golden.sh` PowerShell leg is portable on Windows:
  it resolves `pwsh.exe` when bare `pwsh` is absent (WSL/MSYS bash), translates
  POSIX `/mnt/c` or `/c` fixture paths to Windows paths for Win32 interop, and
  normalizes CRLF so Windows `pwsh.exe` output compares byte-for-byte with the
  LF golden manifest.
- AC-4: Both golden legs pass all 162 fixtures on this host; `bash -n` on the
  harness is clean.
- AC-5: Task record and `.agentic/STATUS.md` entry are updated; the handoff
  gate validates this task file.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `validate-task.sh` and `validate-task.ps1` on both new fixtures return VALID: profile=standard, exit 0 | passed |
| AC-2 | Both `run-golden.sh` legs complete with no MISSING FIXTURE / GOLDEN-FIXTURE MISMATCH lines | passed |
| AC-3 | pwsh golden leg runs to completion on this host (previously exit 127 on every fixture) | passed |
| AC-4 | `run-golden.sh bash` and `run-golden.sh pwsh` both print "All golden expectations matched" (162 fixtures each); `bash -n tests/parity/run-golden.sh` clean | passed |
| AC-5 | TASK-038 file and STATUS.md bullet present; `validate-handoff.sh` on TASK-038 VALID | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds task fixtures, golden expectations, and fixes the cross-language parity harness

## Skills

- task-decomposition v1 invoked — work decomposed into fixture authoring, golden-row updates, and harness portability before planning
- verification-triage v1 invoked — pwsh-leg exit-127 failure triaged to root cause (WSL-bash PATH and Win32 path/CRLF translation) before repairing

## Files changed

- tests/fixtures/tasks/goal-run-unsafe.md (new)
- tests/fixtures/tasks/goal-run-timeout.md (new)
- tests/parity/task-expectations.tsv
- tests/parity/run-golden.sh
- .agentic/tasks/TASK-038-goal-run-fixtures-pwsh-golden-portability.md (new)
- .agentic/STATUS.md

## Verification

### Baseline

- Bash golden leg green on the 160 pre-existing fixtures.
- PowerShell golden leg returned exit 127 for every fixture on this host:
  bare `pwsh` is not on the WSL-bash PATH, `/mnt/c` fixture paths are not
  translated for Win32 interop, and `pwsh.exe` emits CRLF.

### Final

- `bash tests/parity/run-golden.sh bash .agentic/scripts/validate-task.sh`
  -> All golden expectations matched for the bash validator. (162 fixtures)
- `bash tests/parity/run-golden.sh pwsh .agentic/scripts/validate-task.ps1`
  -> All golden expectations matched for the pwsh validator. (162 fixtures)
- `validate-task.sh` and `validate-task.ps1` on goal-run-unsafe.md and
  goal-run-timeout.md -> VALID: profile=standard, exit 0 each.
- `bash -n tests/parity/run-golden.sh` -> clean.
- `validate-handoff.sh .agentic/tasks/TASK-038-goal-run-fixtures-pwsh-golden-portability.md`
  -> VALID.

## Remaining risks

- Bats, Pester, and eval suites were not run locally on this host; the CI matrix owns those legs.
- The detection-parity section of `run-parity.sh` still cannot run under WSL-bash because Windows `pwsh.exe` cannot access WSL-only `mktemp` directories; the golden legs are exercised directly here, and CI covers detection parity on Git Bash / Linux runners.
- Release bookkeeping (CHANGELOG, VERSION, tag) is intentionally out of scope for this non-release task.