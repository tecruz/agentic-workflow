# TASK-132: Done with an underscore-suffixed TBD in the Baseline verification

## Status

Status: done
Updated: 2026-08-19
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
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

TBD_
### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/assets/url.go`
## Remaining risks

- None identified.