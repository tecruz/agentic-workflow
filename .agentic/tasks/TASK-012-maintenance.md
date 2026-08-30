# TASK-012: v1.6.1 fix round — bugs + hygiene + CI maintainability

## Status

Status: done
Updated: 2026-08-29

## Risk profile

Profile: standard

## Profile rationale

All changes are ordinary maintenance and polishing — bug fixes, hygiene, and CI maintainability. No authentication, payments, secrets, data migrations, production infrastructure, or safety-critical behavior is affected. No escalation signals apply.

## Acceptance criteria

- AC-1: All bug fixes applied (coordinator.sh dead printf removed, coordinator.ps1 double logging fixed, symlink-cycle guard ported, text/JSON exit codes aligned)
- AC-2: Shellcheck coverage extended to validate-context.sh, validate-handoff.sh, coordinator.sh in checks.tsv
- AC-3: ps-syntax inline TSV moved to tests/ps-syntax.ps1; checks.tsv references the file
- AC-4: OSS hygiene files added: .gitattributes, CODE_OF_CONDUCT.md, .editorconfig; README badge added
- AC-5: CHANGELOG [Unreleased] updated with Fixed/Changed entries

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Diff review of coordinator.sh/coordinator.ps1 + `bash -n` syntax checks | Passed |
| AC-2 | `.agentic/checks.tsv` shellcheck row covers 6 scripts | Passed |
| AC-3 | `tests/ps-syntax.ps1` present; checks.tsv references via `-File` | Passed |
| AC-4 | `.gitattributes`, `CODE_OF_CONDUCT.md`, `.editorconfig` present; README badge added | Passed |
| AC-5 | `CHANGELOG.md` `[Unreleased]` carries Fixed/Changed/Added entries | Passed |

## Approval gates

None identified

## Context modules

None selected

## Files changed

- .agentic/orchestration/coordinator.sh — removed dead printf no-op (bug #1); aligned text/JSON exit codes (bug #4)
- .agentic/orchestration/coordinator.ps1 — fixed double logging & Trim no-op (bug #2); ported symlink-cycle guard (bug #3); aligned text/JSON exit codes (bug #4)
- .agentic/checks.tsv — extended shellcheck coverage to validate-context.sh, validate-handoff.sh, coordinator.sh; moved ps-syntax to -File tests/ps-syntax.ps1
- .gitattributes — new file (LF line-ending policy)
- CODE_OF_CONDUCT.md — new file (community conduct policy)
- .editorconfig — new file (editor node configuration)
- README.md — added CI badge
- CHANGELOG.md — [Unreleased] entries added
- tests/ps-syntax.ps1 — new file (externalized ps-syntax check program)

## Verification

### Baseline

- verify.sh exit code: depends on project state
- shellcheck: not run on validate-context/validate-handoff/coordinator
- ps-syntax: embedded inline in checks.tsv

### Final

- verify.sh/ps1: PASS (must be verified locally)
- shellcheck: runs on all 6 scripts; any findings addressed
- ps-syntax: referenced via -File tests/ps-syntax.ps1
- .gitattributes, CODE_OF_CONDUCT, .editorconfig present
- README: CI badge present

## Remaining risks

- shellcheck findings on the 3 newly covered scripts may surface in CI; address via 3 repair cycles
- An attempted python3→perl timing change and a composite-action refactor caused CI regressions (fixture false-passes and Pester install failures) and were reverted; re-attempt only with dedicated testing