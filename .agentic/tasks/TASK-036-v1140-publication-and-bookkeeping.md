# TASK-036: v1.14.0 publication + bookkeeping consistency

## Status

Status: done
Updated: 2026-09-11

## Risk profile

Profile: standard

## Profile rationale

Documentation/bookkeeping consistency and recording an already-published
release. No authentication, payments, secrets handling, data migration,
production infrastructure change, irreversible operation, public-API
compatibility commitment, privacy-regulated data, or safety-critical
behavior. Escalation signals reviewed; none apply.

## Approval gates

- None identified

## Acceptance criteria

- AC-1: `.agentic/STATUS.md` `## Active Tasks` checklist lists TASK-025,
  TASK-034, and TASK-035 (no gaps or omissions).
- AC-2: `TASK-033` no longer reports the v1.14.0 tag/release as pending;
  the publication is recorded.
- AC-3: `ROADMAP.md` current-state line mentions the CI retry hardening
  (TASK-034) and the module eval-scenario expansion (TASK-035).
- AC-4: v1.14.0 publication recorded: annotated tag `v1.14.0` on HEAD
  (`2e8366c`) and the GitHub release published with 3 assets.
- AC-5: TASK-034 and TASK-035 carry a well-formed approval gate so both
  pass `validate-task --handoff`.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | status-checklist: STATUS.md Active Tasks now spans TASK-001→TASK-036 with TASK-025/034/035 present | passed |
| AC-2 | task-033-resolved: TASK-033 `### Final` bullet replaced the pending-approval wording with the published tag/release outcome | passed |
| AC-3 | roadmap-current-state: ROADMAP.md version line now cites CI retry hardening and eval-scenario coverage for all 13 modules | passed |
| AC-4 | release-publication: `git describe --tags --exact-match HEAD` → `v1.14.0`; `gh release view v1.14.0` shows 3 assets, published | passed |
| AC-5 | approval-gate-date: TASK-034/035 `AG-1` now reads "Approved by maintainers on 2026-09-10"; both handoff VALID | passed |

## Context modules

- None selected — bookkeeping and release-publication record; no specialist module triggers

## Skills

- None required — mechanical documentation edits; no new release is being produced

## Files changed

- .agentic/STATUS.md — added TASK-025/034/035/036 to the Active Tasks checklist
- .agentic/tasks/TASK-033-v1140-release-bookkeeping.md — recorded publication (removed the stale pending-approval wording)
- .agentic/tasks/034-ci-retry-hardening.md — approval gate date added
- .agentic/tasks/035-module-eval-scenarios.md — approval gate date added
- ROADMAP.md — current-state line refreshed
- .agentic/tasks/TASK-036-v1140-publication-and-bookkeeping.md (new)

## Verification

### Baseline

- STATUS.md Active Tasks listed through TASK-033, skipping TASK-025 and
  omitting TASK-034/035; TASK-033 still said "tag/release pending approval";
  ROADMAP current-state line predated TASK-034/035.

### Final

- `git describe --tags --exact-match HEAD` → `v1.14.0` (annotated tag equals HEAD `2e8366c`).
- `gh release view v1.14.0` → tag `v1.14.0`, draft=false, published 2026-09-10, 3 assets.
- STATUS.md checklist now continuous: reads lines 240—TASK-024 onward through TASK-036 with TASK-025/034/035 verified present; no skipped IDs.
- Handoff gate VALID on this task file (three legs).

## Remaining risks

- None identified.