# TASK-030 — orphaned-file cleanup

## Status

Status: done
Updated: 2026-09-09

## Risk profile

Profile: standard

## Profile rationale

Deleting one orphaned fixture file and two untracked local artifacts —
no authentication, payments, secrets handling, data migration, production
infrastructure, irreversible operation, public-API compatibility
commitment, privacy-regulated data, or safety-critical behavior.

## Acceptance criteria

- AC-1: `tests/fixtures/node-fail/package.json` removed from the repo
  (zero references repo-wide; superseded by the actively referenced
  `node-npm-fail` fixture).
- AC-2: Untracked `tests/fixtures/bazel-workspace/pkg/bin/BUILD.bazel`
  deleted (never committed; verifier's Bazel detection is root-WORKSPACE
  only, so nested BUILD files have no test effect).
- AC-3: Local `dist/` folder (4.5 MB of old release bundles) deleted;
  regenerable via `scripts/build-bundle.sh`.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `git rm tests/fixtures/node-fail/package.json`; grep confirms 0 references before removal | passed |
| AC-2 | `rm -rf tests/fixtures/bazel-workspace/pkg/bin`; `git status --ignored` no longer lists it | passed |
| AC-3 | `rm -rf dist`; `du -sh dist` reported 4.5M before removal | passed |

## Approval gates

- None identified

## Context modules

- None selected — orphan cleanup does not trigger any specialist module

## Skills

- None required — mechanical file removal

## Files changed

- tests/fixtures/node-fail/package.json (deleted, tracked)
- tests/fixtures/bazel-workspace/pkg/bin/BUILD.bazel (deleted, untracked)
- dist/ (deleted, untracked)

## Verification

### Baseline

Full-repo orphan audit: grep for backup/temp files (none), golden↔fixture
mapping (consistent), schema sets (clean), plus three concrete candidates.

### Final

All three candidates deleted. `git status --short` shows only the tracked
removal; working tree otherwise clean. No test, fixture runner, or
installer referenced any deleted path (run-fixtures iterates only
`golden/*.tsv`).

## Remaining risks

- None identified. The deleted fixture had zero references; local-only
  removals are regenerable if ever needed.
