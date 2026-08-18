# TASK-002: Risk profiles and evidence contracts (PR #7)

## Status

Status: done
Updated: 2026-08-18

> Task file for PR #7. Profile chosen per `.agentic/profiles/README.md`;
> this work extends the installer lifecycle and protocol docs but does not
> touch authentication, payments, secrets, or production infrastructure.

## Risk profile

Profile: standard

## Profile rationale

The change adds three documented risk profiles plus a structural task-file
validator, updates the lifecycle documentation, and registers new managed
files in the installers and bundle. No escalation signals apply: no
credentials, no data migrations, no public API compatibility concern, and
no production infrastructure. Tests cover installer behavior, bundle
contents, and validator parity across Bash and PowerShell.

## Acceptance criteria

- AC-1: `.agentic/profiles/` documents the `prototype`, `standard`, and
  `high-assurance` profiles with escalation signals and the default-is-standard rule.
- AC-2: `.agentic/templates/task.md` is a risk-aware template with profile,
  rationale, acceptance criteria, evidence, approvals, and remaining risks.
- AC-3: `.agentic/scripts/validate-task.sh` and `validate-task.ps1` classify
  the same fixtures identically: 0 VALID, 1 INVALID, 2 BLOCKED.
- AC-4: The lifecycle documents `DISCOVER → CLASSIFY RISK → PLAN → IMPLEMENT → VERIFY → HANDOFF`.
- AC-5: Profiles, validators, and the template are framework-managed files
  installed by `install.sh`/`install.ps1` and carried in the bundle.
- AC-6: Fresh-install, update/upgrade, plan, prune, uninstall, and rollback
  tests stay green; adopter task files are never overwritten.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Profile docs present and reviewed | Passed |
| AC-2 | Template present and matches profile requirements | Passed |
| AC-3 | Fixture parity tests pass on both validators (56 fixtures) | Passed |
| AC-4 | WORKFLOW.md / AGENTS.md / README.md updated | Passed |
| AC-5 | Managed-file registration + bundle tests | Passed |
| AC-6 | Full bats + Pester suites green (56 fixtures validated on Bash + PS) — CI #63 | Passed |

## Approval gates

- None identified

## Context modules

- None selected

## Files changed

- `.agentic/profiles/{README,prototype,standard,high-assurance}.md`
- `.agentic/templates/task.md`
- `.agentic/scripts/validate-task.sh`, `.agentic/scripts/validate-task.ps1`
- `tests/fixtures/tasks/*.md` (56 fixtures)
- `tests/bats/validate_task_test.bats`, `tests/pester/ValidateTask.Tests.ps1`
- `tests/bats/install_test.bats`, `tests/pester/Install.Tests.ps1`
- `install.sh`, `install.ps1`, `scripts/build-bundle.sh`
- `.agentic/checks.tsv`, `.github/workflows/ci.yml`
- `.agentic/WORKFLOW.md`, `AGENTS.md`, `README.md`, `.agentic/tasks/README.md`
- `CHANGELOG.md`, `.agentic/STATUS.md`, `.agentic/VERSION`
- `docs/decisions/ADR-0008-risk-profiles-and-evidence-contracts.md`

## Verification

### Baseline

- `pwsh -NoProfile -File .agentic/scripts/verify.ps1` — pester: all green
  (pre-existing v1.2.2 state); bats unavailable locally.

### Final

- `bash -n` on `install.sh`, `.agentic/scripts/verify.sh`, `.agentic/scripts/validate-task.sh` — OK.
- PowerShell parse check on `install.ps1`, `verify.ps1`, `validate-task.ps1` — OK.
- `Invoke-Pester tests/pester` — 123 passed, 4 skipped, 1 failed. The single
  failure is the pre-existing release-to-release upgrade test, which aborts
  locally because `C:\Windows\system32\tar.exe` (bsdtar) cannot read the
  `git archive | tar -x` pipe; unrelated to this PR (blame: cd4763ee).
- `bats tests/bats` — not runnable locally (bats not installed); CI covers it.
- Fixture smoke harnesses run via CI.
- CI #63 green at `d6eb653` across Ubuntu, macOS, and Windows; the pipeline now
  also runs this task through both validators in `--handoff` mode (56 fixtures).

## Remaining risks

- Windows dev-box `tar.exe` pipe quirk makes the pre-existing upgrade Pester
  test fail locally; CI (windows-latest) uses Git's tar and is unaffected.
- Bats suite not exercised on this machine; relies on CI (`verify.sh` on
  ubuntu/macos).