# TASK-048 — Post-install bootstrap task seeding and verification-wiring docs

## Status

Status: done
Updated: 2026-09-27

## Risk profile

Profile: standard

## Profile rationale

Additive installer behavior, mirroring TASK-045's profile: fresh installs seed
one additional project-owned file (`.agentic/tasks/TASK-000-bootstrap.md`,
sourced from the new managed template `.agentic/templates/bootstrap-task.md`);
existing files are never overwritten. The rest of the task is documentation
(README clarification, a dev-repo-only `docs/automating-verification.md`).
No authentication, payments, secrets, data migrations, production
infrastructure, irreversible operations, public API compatibility, privacy,
or safety-critical behavior.

## Acceptance criteria

- AC-1: Fresh install creates `.agentic/tasks/TASK-000-bootstrap.md` from the
  managed template and records it in the manifest with category `seed`; the
  template itself installs as `managed` (`.agentic/templates/bootstrap-task.md`)
  and ships in the distribution bundle via the existing `templates/*.md` glob.
- AC-2: An existing `.agentic/tasks/TASK-000-bootstrap.md` is never overwritten
  (project-owned skip path), and `--plan` stays byte-for-byte read-only.
- AC-3: Bash and PowerShell installers behave identically (same seed content,
  same skip semantics, same closing bootstrap hint on fresh installs), covered
  by new install regression tests in both suites.
- AC-4: README clarifies that the architecture seed is always template XOR
  pointer (never a duplicate), presents TASK-000 as the automated first task,
  and links the new `docs/automating-verification.md` page (OpenCode
  `session.idle` plugin + Claude Code `Stop` hook examples, plus Aider/Copilot
  pointers).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Bats + Pester: fresh install asserts TASK-000 content markers + manifest `seed` record + template `managed` record; `build-bundle.sh --no-archives` ships `.agentic/templates/bootstrap-task.md` via the existing glob | passed |
| AC-2 | Bats + Pester: pre-existing TASK-000 survives install verbatim; PS `-Plan` smoke printed the seed line and wrote nothing (`Test-Path` `$false`) | passed |
| AC-3 | Symmetric assertions pass in both suites; live scratch installs: PS seeded + hint on fresh, skip + no hint on rerun; seeded template parses as VALID (profile=standard) in both task validators | passed |
| AC-4 | README post-install section states template-XOR-pointer; `rg` confirms updated tree/FAQ links to `docs/automating-verification.md`; the new page carries OpenCode/Claude Code/Aider/Copilot/Git examples | passed |

## Goal conditions

- Exit 0 when: pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0; $r = Invoke-Pester -Script 'tests/pester/Install.Tests.ps1' -PassThru; exit $r.FailedCount"
- Exit 0 when: bash -lc "bats --filter 'bootstrap task' tests/bats/install_test.bats"

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds installer regression tests in both suites

## Skills

- task-decomposition v1 invoked — split into: template leg, bash leg, ps1 leg, dual-suite tests, docs/README/CHANGELOG, verification + handoff

## Files changed

- .agentic/templates/bootstrap-task.md (new)
- install.sh
- install.ps1
- tests/bats/install_test.bats
- tests/pester/Install.Tests.ps1
- README.md
- docs/automating-verification.md (new)
- CHANGELOG.md
- .agentic/STATUS.md
- .agentic/tasks/README.md (numbering exception for the TASK-000 seed)
- .agentic/tasks/TASK-048-bootstrap-task-seeding.md (this file)

## Verification

### Baseline

- README "What happens after install" lists four manual steps; nothing on disk
  turns them into the protocol's own loop. The architecture seed is already
  template XOR pointer (TASK-045), but the README does not say so plainly.
- Research baseline: ecosystem comparison (Claude Code lifecycle hooks,
  Copilot `copilot-setup-steps.yml`, Aider `--auto-test`, agents.md
  conventions, OpenCode plugin events) shows the contract layer is already
  strong here; the wiring layer is the gap this task addresses.

### Final

- Manual scratch installs (PS, `Temp\opencode\t048-*`): fresh install seeds
  TASK-000 with template content + prints the bootstrap hint; manifest records
  `bootstrap-task.md	managed` and `TASK-000-bootstrap.md	seed` (equal
  checksums); rerun prints `skip ... (project-owned; never overwritten)`,
  preserves edited content, no hint; `-Plan` prints the seed line and writes
  nothing.
- `bats --filter 'bootstrap task' tests/bats/install_test.bats` (WSL): 2/2 ok —
  after fixing a case-sensitivity parity trap (`grep -F` vs Pester `-Match`;
  marker aligned to the exact-case title `Post-install bootstrap`). Adjacent
  architecture-pointer filtered run: 3/3 ok.
- `Invoke-Pester -Script tests/pester/Install.Tests.ps1 -FullNameFilter
  '*bootstrap task*','*core file set*'`: 3/3 passed.
- Full `bats tests/bats/install_test.bats` (WSL): 111 ok / 4 not ok — all four
  zip-archive tests (97, 105, 106, 110); `zip` is not installed in this WSL
  environment (`zip --version`: command not found), the same pre-existing
  environmental gap documented in TASK-045; CI runners have zip.
- Full Pester `tests/pester` (9 files, 467 discovered): **443 passed / 0
  failed / 24 skipped** (platform guards), 18 min.
- Repo-gate legs on the final tree: all 8 `bash -n` sh-syntax checks OK;
  `handoff-gate` (validate-handoff.sh on TASK-019) rc=0; `ps-syntax` rc=0;
  `evals/run-evals.sh` and `evals/run-evals.ps1` both 19/19 correct.
- `bash scripts/build-bundle.sh --no-archives` (WSL): bundle contains
  `.agentic/templates/bootstrap-task.md` (existing `templates/*.md` glob; no
  build-bundle change needed); dist artifacts cleaned afterwards.
- `validate-task.sh` and `validate-task.ps1` on the seeded template:
  `VALID: profile=standard` in both twins.
- `shellcheck`: not installed on this host — optional leg skips by design.
- All touched files audited LF-only (`.gitattributes` enforces `eol=lf`).

### Review fixes (PR #28 self-review, 2026-09-27)

Self-review of the opened PR caught two doc defects and fixed them before
merge:

- The seeded template's step 2 told adopters to "copy" the reviewed
  candidate over `.agentic/checks.tsv`, bypassing the sanctioned
  `--accept-detected-checks` validation-and-promotion gate and
  contradicting the README lifecycle; it now prescribes the installer flag
  (`--accept-detected-checks` / `-AcceptDetectedChecks`).
- `.agentic/tasks/README.md` (managed, installed everywhere) said tasks
  number from TASK-001 while the installer seeds TASK-000; it now carries
  an explicit exception line.
- Nits normalized: "fresh-install-only" hint wording corrected to the real
  trigger (runs that seed the absent task, including `--update` on
  pre-TASK-048 projects) in the CHANGELOG and STATUS.md; README first-task
  phrasing now reads "hand it to your agent on its first session".
- Re-verified post-fix: `validate-task.sh|.ps1` on the template and on this
  task file VALID; `bats --filter 'bootstrap task'` 2/2 (WSL); Pester
  `*bootstrap task*` 2/2; `validate-handoff.sh|.ps1` on this task VALID.

## Remaining risks

- `docs/` is excluded from the distribution bundle by design, so the wiring
  guide is dev-repo documentation read on GitHub, not installed payload.
- On `--update` runs into already-adopted projects, TASK-000 seeds whenever
  the destination is absent; projects that already completed their bootstrap
  close the task as satisfied (seed content anticipates this).
