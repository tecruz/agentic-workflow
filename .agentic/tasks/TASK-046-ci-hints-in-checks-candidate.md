# TASK-046 — CI workflow run-step hints in the checks candidate

## Status

Status: done
Updated: 2026-09-21

## Risk profile

Profile: standard

## Profile rationale

Advisory comment generation in the installer's `--generate-checks` /
`--detect-checks` candidate writer: when the adopting project has GitHub
Actions workflows, single-line `run:` steps are extracted as *commented* hint
lines appended to `.agentic/checks.generated.tsv`. Comments never parse as
checks, never auto-promote (acceptance still requires the explicit
`--accept-detected-checks` review gate), and detection output itself is
byte-unchanged (this runs in the installer, after `--emit-checks`). No
escalation signals: no authentication, payments, secrets handling, data
migrations, production infrastructure changes, irreversible operations,
public API compatibility, or privacy behavior.

## Acceptance criteria

- AC-1: `--detect-checks` on a project with `.github/workflows/ci.yml`
  produces a candidate whose tail carries `# CI workflow hints` comment lines
  naming file, line number, and single-line `run:` commands; block-scalar
  (`|` / `>`) steps degrade to an explicit "(multi-line script; review
  manually)" marker.
- AC-2: Hints are comments, so the candidate still passes
  `--validate-checks`, and promotion semantics are unchanged; a project
  without workflows yields byte-identical output to before (no hint header).
- AC-3: Bash and PowerShell installers emit the same hint format, pinned by
  one positive + one negative test per language.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Positive Bats+Pester tests assert the `# CI workflow hints` header, `#   .github/workflows/ci.yml:8 run: npm test`, and the multi-line marker; bash/ps manual scratch runs byte-identical | passed |
| AC-2 | Candidates with hints validate: `--validate-checks` exit 0 (WSL smoke + in-test assertions); negative tests confirm header absent without workflows | passed |
| AC-3 | Bats filtered 2/2; Pester Install.Tests.ps1 89 passed / 0 failed / 2 skipped (includes both new tests); full install_test.bats 109 ok with only the 4 known zip-missing env failures | passed |

## Goal conditions

- Exit 0 when: bash -lc "bats tests/bats/install_test.bats"
- Exit 0 when: pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0; $r = Invoke-Pester -Script 'tests/pester/Install.Tests.ps1' -PassThru; exit $r.FailedCount"

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds installer regression tests in both suites

## Skills

- task-decomposition v1 invoked — split into: extractor design/parity, bash leg, ps1 leg, dual-suite tests, changelog, verification

## Files changed

- install.sh
- install.ps1
- tests/bats/install_test.bats
- tests/pester/Install.Tests.ps1
- CHANGELOG.md
- .agentic/STATUS.md
- .agentic/tasks/TASK-046-ci-hints-in-checks-candidate.md (this file)

## Verification

### Baseline

- User question: a project with an existing `.github/workflows/ci.yml` gets a
  checks candidate built purely from stack auto-detection; CI knowledge the
  team already encoded is invisible to it.
- Source inspection: `write_generated_candidate` /
  `Write-GeneratedCandidate` stage header comments + raw `--emit-checks`
  lines; nothing reads `.github/workflows`.

### Final

- Manual scratch project (package.json + `.github/workflows/ci.yml` with a
  `uses:` step, a single-line `run:`, and a block `run: |`):
  both twins emitted the identical candidate tail —
  `# CI workflow hints (.github/workflows) — review-only; ...`,
  `#   .github/workflows/ci.yml:8 run: npm test`,
  `#   .github/workflows/ci.yml:9 run: (multi-line script; review manually)`.
- `verify.sh --validate-checks` on a hint-bearing candidate exits 0.
- `bats --filter "CI run-step hints|CI hint block"` → 2/2 pass.
- `Invoke-Pester -Script tests/pester/Install.Tests.ps1` → 89 passed / 0
  failed / 2 skipped (includes both new tests).
- Full `bats tests/bats/install_test.bats` → 109 ok / 4 not ok, all four the
  known zip-utility-missing bundle tests (WSL `zip` absent; pre-existing,
  unchanged by this task).
- `bash -n install.sh` / `tests/ps-syntax.ps1` → exit 0.
- Full-repo gate (`verify.ps1` legs, final tree covering TASK-044/045/046):
  pester suite 438 passed / 0 failed / 24 platform skips; evals-sh 19/19;
  evals-ps 19/19; bash -n (install.sh, verify.sh) and tests/ps-syntax.ps1
  exit 0; the `bats` leg remains BLOCKED on this host (bats lives only inside
  WSL, not on the Windows PATH) and was run manually there instead. All
  remaining failures observed during the session (4 zip-dependent bundle
  tests, 1 health-report twin-parity test) are pre-existing host
  environment gaps with untouched files.
- `validate-handoff.{sh,ps1}` on this task file → VALID in both twins.

## Remaining risks

- Extraction is intentionally line-oriented: quoted `run: "..."`, folded
  anchors, and matrix-expanded jobs surface as-is; they are comments, so the
  worst case is a noisy hint. No vercel/circle/other CI providers parsed —
  GitHub Actions only, per the user's scenario.
- On this host, the full gate still reports the `bats` leg BLOCKED (bats not
  on the Windows PATH) and the zip-missing bundle failures under WSL; both
  pre-existing environment properties.
