# TASK-FX: goal-run-pass

## Status

Status: done
Updated: 2026-09-11
## Risk profile

Profile: standard
## Profile rationale

Standard product work with runnable goal conditions.
## Acceptance criteria

- AC-1: Asset URLs include a `v=` query parameter.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `asset_url_test.go` | Passed |
## Goal conditions

- Exit 0 when: echo goal-ok runs successfully.
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
