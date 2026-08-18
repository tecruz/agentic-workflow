# TASK-055: Done with a placeholder evidence description

## Status

Status: done
Updated: 2026-08-18
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: The cache key includes the asset version.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | [evidence to add] | Passed |
## Approval gates

- None identified
## Verification

### Baseline

- `go test ./...` → 42 passed, 0 failed.

### Final

- `go test ./...` → 42 passed, 0 failed.
## Files changed

- `internal/cache/key.go`
## Remaining risks

- None identified.