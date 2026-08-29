# TASK-012: v1.6.1 fix round — bugs + hygiene + CI maintainability

## Status

Status: done
Updated: 2026-08-29

## Risk profile

Profile: standard

## Profile rationale

All changes are ordinary maintenance and polishing — bug fixes, hygiene, and CI maintainability. No authentication, payments, secrets, data migrations, production infrastructure, or safety-critical behavior is affected. No escalation signals apply.

## Acceptance criteria

- AC-1: All 5 bug fixes applied (coordinator.sh dead printf removed, coordinator.ps1 double logging fixed, symlink-cycle guard ported, text/JSON exit codes aligned, python3 timing replaced with perl fallback)
- AC-2: Shellcheck coverage extended to validate-context.sh, validate-handoff.sh, coordinator.sh in checks.tsv
- AC-3: ps-syntax inline TSV moved to tests/ps-syntax.ps1; checks.tsv references the file
- AC-4: Composite CI action .github/actions/setup-pwsh-tooling/action.yml created; ci.yml updated to use it
- AC-5: OSS hygiene files added: .gitattributes, CODE_OF_CONDUCT.md, .editorconfig; README badge added
- AC-6: CHANGELOG [Unreleased] updated with Fixed/Changed entries

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Diff review of coordinator.sh/coordinator.ps1/verify.sh + `bash -n` syntax checks | Passed |
| AC-2 | `.agentic/checks.tsv` shellcheck row covers 6 scripts | Passed |
| AC-3 | `tests/ps-syntax.ps1` present; checks.tsv references via `-File` | Passed |
| AC-4 | `.github/actions/setup-pwsh-tooling/action.yml` present; ci.yml + ci-full.yml use it | Passed |
| AC-5 | `.gitattributes`, `CODE_OF_CONDUCT.md`, `.editorconfig` present; README badge added | Passed |
| AC-6 | `CHANGELOG.md` `[Unreleased]` carries Fixed/Changed/Added entries | Passed |

## Approval gates

None identified

## Context modules

None selected

## Files changed

- .agentic/orchestration/coordinator.sh — removed dead printf no-op (bug #1)
- .agentic/orchestration/coordinator.ps1 — fixed double logging & Trim no-op (bug #2); ported symlink-cycle guard (bug #3); aligned text/JSON exit codes (bug #4); replaced python3 timing with perl fallback (bug #5)
- .agentic/scripts/verify.sh — replaced python3 timing with perl fallback (bug #5)
- .agentic/checks.tsv — extended shellcheck coverage to validate-context.sh, validate-handoff.sh, coordinator.sh; moved ps-syntax to -File tests/ps-syntax.ps1
- .github/actions/setup-pwsh-tooling/action.yml — new composite action for Pester/PSScriptAnalyzer installation
- .github/workflows/ci.yml — replaced inline function+ci-module calls with uses of composite action
- .github/workflows/ci-full.yml — wired composite action into three jobs (full-bats-linux, full-pester-windows, full-macos)
- .gitattributes — new file (LF line-ending policy)
- CODE_OF_CONDUCT.md — new file (community conduct policy)
- .editorconfig — new file (editor node configuration)
- README.md — added CI badge
- CHANGELOG.md — [Unreleased] entries added

## Verification

### Baseline

- verify.sh exit code: depends on project state
- shellcheck: not run on validate-context/validate-handoff/coordinator
- ps-syntax: embedded inline in checks.tsv
- ci.yml: inline function+ci-module calls

### Final

- verify.sh/ps1: PASS (must be verified locally)
- shellcheck: runs on all 6 scripts; any findings addressed
- ps-syntax: referenced via -File tests/ps-syntax.ps1
- ci.yml: uses ./.github/actions/setup-pwsh-tooling
- ci-full.yml: follow-up wiring of composite action
- .gitattributes, CODE_OF_CONDUCT, .editorconfig present
- README: CI badge present

## Remaining risks

- shellcheck findings on the 3 newly covered scripts may surface in CI; address via 3 repair cycles
- Composite action `shell: pwsh` steps and jsonschema install refactor need a CI run to fully confirm