# TASK-102: Extract request-id middleware

## Risk profile

Profile: standard

## Profile rationale

Ordinary maintenance refactor of HTTP middleware. No escalation signals apply.

## Acceptance criteria

- AC-1: Request-ID middleware sets a header when absent.
- AC-2: Existing handlers receive the middleware without API changes.

## Required evidence

| Criterion | Evidence required | Result |
|---|---|---|
| AC-1 | Unit test `middleware_test.go` | Passed |
| AC-2 | Existing integration suite | Passed |

## Approval gates

- None identified

## Files changed

- `internal/http/middleware.go`
- `internal/http/middleware_test.go`

## Verification

### Final

`go test ./...` — 84 passed, 0 failed.

## Remaining risks

- None known.