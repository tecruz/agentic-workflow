# TASK-EVAL: performance-hot-path

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Approval gates

- [x] AG-1: Approved by Perf Lead on 2026-08-24

## Acceptance criteria

- AC-1: Session-lookup p99 latency stays below 5 ms.
- AC-2: Cache miss path returns fresh data without staleness.
- AC-3: No memory growth under sustained load.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | benchmark-results: before/after p99 latency for session lookup | passed |
| AC-2 | load-test-results: sustained load demonstrates no stale reads | passed |
| AC-3 | memory-profile: allocation delta under sustained load stays below 1 MB | passed |

## Context modules

- performance v1 loaded — hot-path caching added to session lookup

## Skills

- verification-triage v1 invoked — benchmark results triaged before merge

## Verification

### Baseline

- Session-lookup p99 measured at 8 ms under the current load-test suite.

### Final

- Session-lookup p99 measured at 3 ms under the same load-test suite.

## Files changed

- `src/middleware/session-cache.ts`

## Remaining risks

- None identified.
