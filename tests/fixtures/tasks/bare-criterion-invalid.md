# TASK-157: Bare acceptance criterion outside the evidence contract

## Status

Status: done
Updated: 2026-08-19
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: The API returns the expected response.
AC-2: Existing clients remain compatible.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Integration test `api_test.go` | Passed |
## Approval gates

- None identified
## Verification

### Baseline

- `go test ./...` → 42 passed, 0 failed.

### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/api/handler.go`
## Remaining risks

- None identified.