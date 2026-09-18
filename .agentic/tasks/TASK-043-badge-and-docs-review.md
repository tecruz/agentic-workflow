# TASK-043 — CI badge URL fix + README documentation review

## Status

Status: done
Updated: 2026-09-17

## Risk profile

Profile: standard

## Profile rationale

Documentation and presentation-only fix: README markdown and CHANGELOG
entries. No authentication, payments, secrets handling, data migrations,
production infrastructure, irreversible operations, public API changes,
privacy-related content, or safety-critical behavior. No context module should
be loaded; no skill invoked (docs-only fix).

## Acceptance criteria

- AC-1: The CI badge in README.md renders with the workflow's current state
  (not "no status"). The image `src` and surrounding anchor point at the
  canonical `/actions/workflows/ci.yml/badge.svg` and `/actions/workflows/ci.yml`.
- AC-2: README's bundle-install example carries the current released version
  (1.15.1), replacing the outdated `1.15.0` example.
- AC-3: The README "What's Included" tree lists `.agentic/orchestration/`
  alongside the existing entries.
- AC-4: CHANGELOG records the fixes under `[Unreleased]` (TASK-043 entry).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `curl` on both old and new badge endpoints returned "no status" vs "passing" respectively; README's new anchor + image both point at `actions/workflows/ci.yml` | passed |
| AC-2 | README's example `dist/agentic-workflow-1.15.1/` matches `.agentic/VERSION` (1.15.1) | passed |
| AC-3 | File tree now includes the orchestration directory | passed |
| AC-4 | `[Unreleased]` section has the two entries referencing TASK-043 | passed |

## Approval gates

- None identified

## Context modules

- None selected — docs-only change with no context-module triggers

## Skills

- None required — pure documentation fix; no decomposition or triage value

## Files changed

- README.md (badge URL + link, bundle example version, orchestration/ tree entry)
- CHANGELOG.md ([Unreleased] Fixed entries)
- .agentic/tasks/TASK-043-badge-and-docs-review.md (this file)

## Verification

### Baseline

- Badge image rendered as "no status" because it used the legacy
  `/workflows/<name>/badge.svg` URL pattern that GitHub no longer serves with
  status (verified by a direct `curl` returning "no status").
- Bundle example showed `1.15.0` while `.agentic/VERSION` and the latest
  release were `1.15.1`.
- Orchestration directory absent from the README file tree.

### Final

- New badge image returns "passing" from GitHub Actions; both the badge image
  and the surrounding link go to the workflow's dedicated action page.
- Bundle example says `1.15.1`.
- README What's Included tree includes `orchestration/`.
- CHANGELOG `[Unreleased]` lists both fixes.

## Remaining risks

- None: pure docs change; CI gates (fast + full) confirmed the tree still
  builds and passes all suites.
