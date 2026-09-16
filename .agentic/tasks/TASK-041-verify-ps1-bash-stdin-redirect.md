# TASK-041 — verify.ps1: stdin redirect for bash-routed checks on Windows

## Status

Status: done
Updated: 2026-09-14

## Risk profile

Profile: standard

## Profile rationale

Single-target fix in the PowerShell verifier's check launcher. No authentication, payments, secrets handling, data migrations, production infrastructure, irreversible operations, public API compatibility commitments, or safety-critical behavior. The change is observable-behavior-preserving for all non-Windows hosts and for Windows checks that never read stdin; for Windows checks that do read stdin it converts an indefinite block into an immediate EOF, which is strictly better. Selected context module (testing-infrastructure) matches the CI/test-harness scope.

## Acceptance criteria

- AC-1: `verify.ps1` feeds stdin from the null device (`$null |`) whenever the resolved invocation routes through a `bash` binary on Windows — both when `Get-ExtensionlessBashLauncher` handles an extensionless script and when a check directly invokes `bash <script.sh>`.
- AC-2: Exit codes propagate exactly as before (0->PASS, nonzero->FAIL); text and `-Format Json` output are unchanged for checks that do not read stdin.
- AC-3: Two new Pester regression tests cover the blocked-stdin and exit-code-propagation paths on Windows; full `Verify.Tests.ps1` suite passes.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | verify.ps1 gained a `$stdinNull` gate in `Invoke-Check`: when the resolved Windows invocation targets a bash executable, the child is launched as dollar-null-pipe-into-call so MSYS/stdin scripts read EOF instead of blocking; direct probe of a bash `cat` returns EOF in under 1s | passed |
| AC-2 | Fixture run of a passing bash-script check through verify.ps1 exits 0 (VERIFICATION PASSED), a failing variant exits 1 (VERIFICATION FAILED), and `-Format Json` still emits one valid document | passed |
| AC-3 | Invoke-Pester over tests/pester/Verify.Tests.ps1: 38 passed, 0 failed, including the two new stdin regression tests | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task modifies the test-runner launch path in `verify.ps1` and adds regression coverage

## Skills

- verification-triage v1 invoked — diagnosed the Windows `handoff-gate` stall to stdin blocking before repairing

## Files changed

- .agentic/scripts/verify.ps1
- tests/pester/Verify.Tests.ps1
- CHANGELOG.md
- .agentic/STATUS.md
- .agentic/tasks/TASK-041-verify-ps1-bash-stdin-redirect.md (this file)

## Verification

### Baseline

- On this Windows host, `pwsh -NoProfile -File .agentic/scripts/verify.ps1` stalled at the `handoff-gate` / `sh-syntax-*` / `evals-sh` checks whenever a bash script check consumed stdin inside a non-interactive wrapper; measured verify.ps1 output stopped after the Git Bash launch line. Cross-checked that piping `$null` into a bash `cat` probe returns EOF immediately while the same script without the redirect hangs under the wrapper.

### Final

- After the change, the same fixture-style runs complete: `script.sh` (exit 0) -> VERIFICATION PASSED; `fail.sh` (exit 1) -> VERIFICATION FAILED with FAIL summary; Json check still emits a single protocol-1.15.1 document.
- `Invoke-Pester -Path tests/pester/Verify.Tests.ps1` -> 38/38 pass (includes the two new tests).

## Remaining risks

- Linux/macOS behavior is untouched; CI (Full) on the next merge will re-verify both.
- `checks.tsv` semantics unchanged; the null-stdin feed is a launcher-defense, not a contract change.
