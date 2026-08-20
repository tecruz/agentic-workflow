# TASK-130: Done with a bold-wrapped TBD in the profile rationale

## Status

Status: done
Updated: 2026-08-19
## Risk profile

Profile: standard
## Profile rationale

**TBD**
## Acceptance criteria

- AC-1: Asset URLs include a `v=` query parameter.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `asset_url_test.go` | Passed |
## Approval gates

- None identified
## Verification

### Baseline

- `go test ./...` → 42 passed, 0 failed.

### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/assets/url.go`
## Remaining risks

- None identified.