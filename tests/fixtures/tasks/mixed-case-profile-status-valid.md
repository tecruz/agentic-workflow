# TASK-044: Mixed case profile and status valid fixture

## Status

StAtUs: dOnE
UpDaTeD: 2026-08-18
## Risk profile

PrOfIlE: StAnDaRd
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

- [x] AG-1: Approved by alice@example.com on 2026-08-18
## Verification

### Baseline

- `go test ./...` → 42 passed, 0 failed.

### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/assets/url.go`
## Remaining risks

- None identified.