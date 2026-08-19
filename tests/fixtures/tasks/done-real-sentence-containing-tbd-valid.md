# TASK-064: Done with real sentences that mention TBD as a word

## Status

Status: done
Updated: 2026-08-18
## Risk profile

Profile: standard
## Profile rationale

Standard maintenance; the TBD flag stays off for this release.
## Acceptance criteria

- AC-1: The TBD cache flag remains disabled.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `cache_key_test.go` | Passed |
## Approval gates

- None identified
## Verification

### Baseline

- `go test ./...` → 42 passed; the TBD adapter is stubbed.

### Final

- `go test ./...` → 42 passed; the TBD adapter is stubbed.
## Files changed

- `internal/cache/key.go`
## Remaining risks

- The TBD panel ships in a follow-up change.