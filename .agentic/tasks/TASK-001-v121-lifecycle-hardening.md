# TASK-001: v1.2.1 installer lifecycle hardening

## Status

Status: done
Updated: 2026-08-15

## Risk profile

Profile: standard

## Profile rationale

Installer lifecycle hardening for the v1.2.1 release. No escalation signals
apply: no credentials, no data migrations, and no production infrastructure
are touched.

## Scope

Implement the 7 hotfix items from `feedback (8).md` for the v1.2.1 release:

1. `--plan` / `-Plan` must be byte-for-byte read-only (prune and uninstall must not
   write, snapshot, or back up anything).
2. Validate the previous install manifest (syntax, checksum format, categories,
   duplicates, lexical + physical confinement against the target root) before any
   mutation; hard-fail on malformed input.
3. Stop deleting legacy files (`.cursorrules`, `.windsurfrules`, `.clinerules`,
   `CONVENTIONS.md`, `.github/copilot-instructions.md`) by name alone. Only delete
   when ownership is proven (checksum match to known v1.0 content, framework
   signature, or manifest ownership). Preserve uncertain files with a conflict
   message; add `--prune-unverified-legacy` / `-PruneUnverifiedLegacy` to force
   removal with a mandatory backup.
4. Share strict merge-marker parsing (`merge_state`) between prune and install;
   prune must refuse to rewrite malformed merge blocks.
5. Replace all predictable temp files with unpredictable names and cleanup.
6. Add adversarial tests for the above (Bats + Pester).
7. Prepare v1.2.1 (version, changelog, ADR, README template-guidance fix, bundle).

## Acceptance criteria

- AC-1: `--plan` with prune/uninstall leaves every byte unchanged (verified by tests).
- AC-2: Malformed manifest paths (absolute, `..`, drive letters, symlink escape,
  duplicates, bad categories/checksums/control chars) hard-fail before mutation.
- AC-3: Legacy files with unknown content are preserved with a conflict message;
  `--prune-unverified-legacy` removes them only with an automatic backup.
- AC-4: Malformed merge markers are never rewritten by prune.
- AC-5: No predictable `.agentic-tmp` file names anywhere in the installer lifecycle.
- AC-6: Bats + Pester suites green locally and under CI checks in `.agentic/checks.tsv`.
- AC-7: `.agentic/VERSION` = 1.2.1, CHANGELOG entry, ADR-0006, README corrected,
  `dist/agentic-workflow-1.2.1/` bundle rebuilt.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Bats plan read-only tests | Passed |
| AC-2 | Bats + Pester malformed-manifest tests | Passed |
| AC-3 | Bats + Pester legacy-file preservation tests | Passed |
| AC-4 | Bats + Pester merge-marker tests | Passed |
| AC-5 | Repo grep for predictable temp names | Passed |
| AC-6 | Bats 123 / Pester 106 local + CI | Passed |
| AC-7 | Version, changelog, ADR, README, bundle checks | Passed |

## Approval gates

- None identified

## Files changed

- `install.sh`
- `install.ps1`
- `tests/bats/install_test.bats`
- `tests/pester/Install.Tests.ps1`
- `.agentic/VERSION`
- `CHANGELOG.md`
- `README.md`
- `docs/decisions/ADR-0006-*.md` (new)
- `dist/agentic-workflow-1.2.1/` (rebuilt)

## Verification

### Baseline

- Pester 80/80 pass; Bats 93 pass + 1 skip (`--detect-checks` parity skips
  because pwsh is unavailable under WSL); `bash -n` and `ps-syntax` pass;
  `bats`/`shellcheck` binaries absent from host PATH.

### Final

- `bash -n install.sh` and `bash -n .agentic/scripts/verify.sh` — OK.
- PowerShell parse of `install.ps1`, `Install.Tests.ps1`, `Verify.Tests.ps1`,
  `.agentic/scripts/verify.ps1` — all SYNTAX OK.
- Bats (WSL): 123 total, 0 failures, 1 skip (pwsh parity — runs only in CI).
- Pester 5.6.0: 106 passed, 0 failed, 2 platform skips.
- Bundle: `dist/agentic-workflow-1.2.1/` + tar.gz + zip assembled; stale
  1.1.0/1.2.0 build artifacts removed; `sha256sum -c dist/SHA256SUMS` OK.
- End-to-end bundle install verified by bats 78 and pester "bundle
  end-to-end" tests.

## Remaining risks

- `bats` and `shellcheck` are not installed on this host; the Bats suite runs under
  WSL via `/mnt/c/Users/tiago/AppData/Local/Temp/bats-core/bin/bats`. The single
  parity test that requires pwsh inside WSL is skipped locally and will run in CI.
- Installing the local clone of `install.sh` (before tagging) requires
  `--dev-checksums --accept-dev` or equivalent dev flags; see existing CI usage.
- v1.2.1 release prep is complete and verified locally (version, CHANGELOG,
  ADR-0006, README template-guidance fix, bundle, SHA256SUMS). Remaining only:
  user-approved `git tag v1.2.1`, push, and GitHub release of the bundle
  archives — these require explicit approval and were not performed.
