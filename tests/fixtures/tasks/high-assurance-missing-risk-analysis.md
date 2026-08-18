# TASK-202: Enable two-factor authentication enforcement

## Risk profile

Profile: high-assurance

## Profile rationale

Affects authentication. Escalated to high-assurance.

## Requirements

- R-1: All administrative accounts require 2FA within 14 days.
- R-2: Users without 2FA cannot perform administrative actions.

## Acceptance criteria

- AC-1: Enforcement flag gates administrative actions on 2FA status.
- AC-2: Grace period is configurable.

## Required evidence

| Criterion | Evidence required | Result |
|---|---|---|
| AC-1 | Auth integration test | Passed |
| AC-2 | Config unit test | Passed |

## Requirement-to-evidence

| Requirement | Evidence required | Result |
|---|---|---|
| R-1 | Enforcement integration test | Passed |
| R-2 | Negative-path auth test | Passed |

## Negative-path and boundary tests

- Administrative action attempted without 2FA.
- Boundary: user exactly at the 14-day deadline.

## Integration verification

Staging: enforcement behavior verified against the staging auth service.

## Recovery plan

Disable the enforcement flag and re-enable the grace period to restore prior
behavior; feature flag is the single rollback switch.

## Approval gates

- [x] Approved by: security-owner@example.com (2026-08-15)

## Independent review

Reviewed by an engineer outside the auth team.

## Files changed

- `internal/auth/enforcement.go`
- `internal/auth/enforcement_test.go`

## Verification

### Baseline

`go test ./internal/auth` — 27 passed, 0 failed.

### Final

`go test ./internal/auth` — 30 passed, 0 failed.

## Remaining risks

- None unresolved.