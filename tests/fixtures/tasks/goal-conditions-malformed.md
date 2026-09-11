# TASK-FX: goal-conditions-malformed

## Status

Status: done
Updated: 2026-09-11
## Risk profile

Profile: standard
## Profile rationale

Standard product work with a malformed goal-conditions entry.
## Acceptance criteria

- AC-1: Asset URLs include a `v=` query parameter.
- AC-2: The asset list renders in under 500 ms.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `asset_url_test.go` | Passed |
| AC-2 | Bench `asset_list_bench_test.go` | Passed |
## Goal conditions

- Exit 0 when: `go test ./...` passes with no failures.
- Run the full test suite before merging.
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
