# TASK-041: Standard reordered evidence valid fixture

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
- AC-3: Cache headers are set on asset responses.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-3 | HTTP test `asset_cache_test.go` | Passed |
| AC-1 | Unit test `asset_url_test.go` | Passed |
| AC-2 | Bench `asset_list_bench_test.go` | Passed |
## Approval gates

- [x] AG-1: Approved by alice@example.com on 2026-08-18
## Verification

### Baseline

- `go test ./...` → 43 passed, 0 failed.

### Final

- `go test ./...` → 43 passed, 0 failed.
## Files changed

- `internal/assets/url.go`
- `internal/assets/cache.go`
## Remaining risks

- None identified.