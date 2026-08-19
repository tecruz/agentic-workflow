# TASK-144: Done with non-ASCII meaningful content

## Status

Status: done
Updated: 2026-08-19
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: 支付测试 stays valid under the `C` locale.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | 翻译测试 con É y 李 | Passed |
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