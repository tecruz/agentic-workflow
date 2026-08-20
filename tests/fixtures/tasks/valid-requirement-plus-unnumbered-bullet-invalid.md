# TASK-086: Valid requirement plus an unnumbered bullet

## Status

Status: done
Updated: 2026-08-18
## Risk profile

Profile: high-assurance

## Profile rationale

Authentication is safety-critical: escalate to high-assurance.

## Requirements

- R-1: Authorization is checked server-side.
- Existing administrative roles must preserve access.

## Risk analysis

Threat model: privilege escalation and unauthorized access. Mitigations:
server-side authorization checks and enforced role boundaries.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | Security unit test `authz_test.go` | Passed |

## Negative-path and boundary tests

- Unauthorized roles receive HTTP 403.

## Integration verification

- Full authorization flow exercised end-to-end.

## Recovery plan

- Restore from encrypted snapshot; key rotation documented in `docs/ops.md`.

## Approval gates

- [x] AG-1: Approved by mallory@example.com on 2026-08-18

## Independent review

- Second engineer reviewed the authorization module (PR #12).

## Acceptance criteria

- AC-1: Authorization is enforced server-side.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Security unit test `authz_test.go` | Passed |

## Verification

### Baseline

- `go test ./...` → 55 passed, 0 failed.

### Final

- `go test ./...` → 57 passed, 0 failed.

## Files changed

- `internal/auth/authz.go`

## Remaining risks

- None identified.
