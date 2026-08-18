# TASK-049: Checked placeholder approval invalid fixture

## Status

Status: done
Updated: 2026-08-18
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: Asset URLs include a `v=` query parameter.
- AC-2: The asset list renders in under 500 ms.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `asset_url_test.go` | Passed |
| AC-2 | Bench `asset_list_bench_test.go` | Passed |
## Approval gates

- [x] AG-1: Approved by <approver> on YYYY-MM-DD
## Verification

### Baseline

- `go test ./...` → 42 passed, 0 failed.

### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/assets/url.go`
## Remaining risks

- None identified.