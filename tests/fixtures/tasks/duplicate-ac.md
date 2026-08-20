# TASK-021: Duplicate AC fixture

## Status

Status: done
Updated: 2026-08-18
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: Asset URLs include a `v=` query parameter.
- AC-1: Asset URLs cache aggressively.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `asset_url_test.go` | Passed |
## Approval gates

- [x] AG-1: Approved by alice@example.com on 2026-08-18
## Verification

### Baseline

- `go test ./...` → 42 passed, 0 failed.

### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/assets/url.go`
- `internal/assets/url_test.go`
## Remaining risks

- None identified.
