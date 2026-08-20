# TASK-152: Canonical criterion plus a prose-mentioned AC identifier

## Status

Status: done
Updated: 2026-08-20
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: The endpoint returns the expected response.

Existing clients must also satisfy AC-2: backward compatibility is preserved.
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