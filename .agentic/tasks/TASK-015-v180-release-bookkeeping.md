# TASK-015 — v1.8.0 release bookkeeping: deeper Android/Kotlin detection

## Status

Status: done
Updated: 2026-09-08

## Risk profile

Profile: standard

## Profile rationale

Release bookkeeping for the deeper Android/Kotlin detection feature
(PR #17, `bf8ea1f`). No authentication, payments, secrets handling, data
migration, production infrastructure, irreversible operation, public-API
compatibility commitment, privacy-regulated data, or safety-critical
behavior. Escalation signals reviewed; none apply.

## Acceptance criteria

- AC-1: ROADMAP.md item 2 checkboxes checked, version updated to 1.8.0.
- AC-2: ADR-0013 written and indexed in `docs/decisions/README.md`.
- AC-3: `.agentic/VERSION` bumped to `1.8.0`; `protocol_version` swept to
  `1.8.0` across all schemas, scripts, evals, tests.
- AC-4: CHANGELOG.md `[1.8.0]` section added.
- AC-5: Task file created and `.agentic/STATUS.md` updated with the v1.8.0
  note.
- AC-6: Tag `v1.8.0` created and the Release workflow passed.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | ROADMAP.md shows item 2 done and version line 1.8.0 (later superseded) | passed |
| AC-2 | ADR-0013 present and indexed in `docs/decisions/README.md` | passed |
| AC-3 | `.agentic/VERSION` = 1.8.0 at the v1.8.0 tag; protocol_version swept (recorded in the original task file) | passed |
| AC-4 | CHANGELOG.md `[1.8.0] - 2026-09-01` section present | passed |
| AC-5 | This task file exists; STATUS.md v1.8.0 note recorded | passed |
| AC-6 | Tag `v1.8.0` exists in the repository history | passed |

## Approval gates

- None identified

## Context modules

- None selected — historical release bookkeeping; no specialist module triggers

## Skills

- release-verification v1 invoked — VERSION/CHANGELOG/tag agreement and archive publication confirmed at the time of the v1.8.0 release

## Files changed

- `.agentic/VERSION` — bumped to `1.8.0` (at the v1.8.0 tag)
- `protocol_version` sweep to `1.8.0`: schemas, scripts, evals, tests
- `CHANGELOG.md` — `[1.8.0]` section added
- `.agentic/STATUS.md` — v1.8.0 note recorded
- Tag `v1.8.0` created; Release workflow passed

## Verification

### Baseline

- Detection contract changed (root-level version catalog + convention
  plugin; per-module split without version catalog), requiring a
  protocol_version and VERSION bump per ADR-0007 (recorded in the original
  task file).

### Final

- Recorded at the time (original task file): all 51/51 fixtures pass
  (Bash + PowerShell); 8/8 offline evals pass (both languages); CI green on
  Linux, macOS, Windows; cross-language parity maintained.
- Current state: tag `v1.8.0` exists; CHANGELOG `[1.8.0] - 2026-09-01`
  section present; v1.8.0 superseded by v1.9.0 in STATUS.md.

## Remaining risks

- This file was authored before the risk-profile task template existed; the
  rewrite aligns it with the current template for validator compliance.
  Historical fixture/eval counts reflect the state at the time of the
  v1.8.0 release, not today's larger corpus.