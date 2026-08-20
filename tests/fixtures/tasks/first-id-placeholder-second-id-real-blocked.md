# TASK-069: Done with the first criterion still a placeholder

## Status

Status: done
Updated: 2026-08-18
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: [observable, testable condition]
- AC-2: The cache key includes the asset version.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `cache_key_test.go` | Passed |
| AC-2 | Unit test `asset_list_test.go` | Passed |
## Approval gates

- None identified
## Verification

### Baseline

- `go test ./...` → 42 passed, 0 failed.

### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/cache/key.go`
## Remaining risks

- None identified.