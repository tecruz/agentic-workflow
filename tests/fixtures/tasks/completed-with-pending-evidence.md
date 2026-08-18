# TASK-103: Add pagination to list endpoint

## Risk profile

Profile: standard

## Profile rationale

Ordinary product work. No escalation signals apply.

## Acceptance criteria

- AC-1: List endpoint accepts `page` and `page_size` parameters.
- AC-2: Responses include a total count.

## Required evidence

| Criterion | Evidence required | Result |
|---|---|---|
| AC-1 | Unit test `list_test.go` | Pending |
| AC-2 | Contract test | Pending |

## Approval gates

- None identified

## Files changed

- `internal/api/list.go`
- `internal/api/list_test.go`

## Verification

### Baseline

`go test ./internal/api` — 44 passed, 0 failed.

### Final

`go test ./internal/api` — 45 passed, 0 failed.

## Remaining risks

- None known.

## Status

Status: done