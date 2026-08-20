# TASK-155: Non-ASCII criterion and evidence require perl

## Status

Status: done
Updated: 2026-08-19
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: 用户身份验证正常工作
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | 集成测试通过 | Passed |
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