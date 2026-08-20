# TASK-133: n/a rationale is a Markdown-wrapped placeholder

## Status

Status: done
Updated: 2026-08-19
## Risk profile

Profile: standard
## Profile rationale

Standard product/maintenance work with no elevated risk signals.
## Acceptance criteria

- AC-1: The Windows adapter behavior is unchanged.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | N/A: **TBD** | n/a |
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