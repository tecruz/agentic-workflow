# TASK-029 — post-release changelog hygiene + stale-branch pruning

## Status

Status: done
Updated: 2026-09-09

## Risk profile

Profile: standard

## Profile rationale

Documentation housekeeping and merged-branch pruning only — no
authentication, payments, secrets handling, data migration, production
infrastructure, irreversible operation, public-API compatibility
commitment, privacy-regulated data, or safety-critical behavior.

## Acceptance criteria

- AC-1: `## [Unreleased]` section in `CHANGELOG.md` documents TASK-026
  (drift/parity), TASK-027 (negative-control scenario), and TASK-028
  (eval caching) using the repo's Keep a Changelog convention.
- AC-2: Nine merged remote branches and three merged local branches are
  pruned; `git ls-remote --heads` shows only `master` (plus any
  in-progress CI ref, if applicable).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | CHANGELOG.md: `## [Unreleased]` with Added/Fixed/Changed sections for TASK-026/027/028; parse-clean | passed |
| AC-2 | `git ls-remote --heads origin` returns only `master` (4e271d4) | passed |

## Approval gates

- None identified

## Context modules

- None selected — documentation housekeeping does not trigger any specialist module

## Skills

- None required — branch pruning and changelog edit are mechanical chores

## Files changed

- CHANGELOG.md — `## [Unreleased]` section
- .agentic/tasks/TASK-029-changelog-hygiene.md (new)

## Verification

### Baseline

The six post-v1.13.0 commits had no changelog record; ten stale merged
branches (3 local, 9 remote) cluttered the ref namespace.

### Final

`CHANGELOG.md` now has an `## [Unreleased]` block at the top with Added
(TASK-027), Fixed (TASK-026), and Changed (TASK-028) entries matching the
repo's Keep a Changelog convention. All merged branches pruned — only
`master` remains on the remote.

## Remaining risks

- None identified.
