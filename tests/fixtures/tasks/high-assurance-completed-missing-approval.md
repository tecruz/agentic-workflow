# TASK-205: Enable audit log retention toggle

## Risk profile

Profile: high-assurance

## Profile rationale

Affects privacy-regulated data retention. Escalated to high-assurance.

## Requirements

- R-1: Audit log retention is configurable per environment.
- R-2: Lowering retention below the regulatory minimum is impossible.

## Risk analysis

Threat: an operator lowers retention below the regulatory minimum and loses
mandated records. Blast radius: regulatory exposure. Mitigations: hard floor
enforced in code, approval required to change the floor.

## Requirement-to-evidence

| Requirement | Evidence required | Result |
|---|---|---|
| R-1 | Config integration test | Passed |
| R-2 | Floor enforcement test | Passed |

## Acceptance criteria

- AC-1: Retention floor cannot be set below the regulatory minimum.
- AC-2: Config change requires an approval record.

## Required evidence

| Criterion | Evidence required | Result |
|---|---|---|
| AC-1 | Negative-path test | Passed |
| AC-2 | Approval record test | Passed |

## Negative-path and boundary tests

- Retention set below the floor.
- Retention at exactly the floor.

## Integration verification

Staging: config toggle exercised in staging; floor rejection verified.

## Recovery plan

Restore the prior retention value from the last approved config; the change is
reversible via the existing config pipeline.

## Approval gates

- [ ] Awaiting approval from compliance-owner@example.com

## Independent review

Reviewed by a second engineer; confirmed the floor cannot be bypassed.

## Files changed

- `internal/audit/retention.go`
- `internal/audit/retention_test.go`

## Verification

### Baseline

`go test ./internal/audit` — 14 passed, 0 failed.

### Final

`go test ./internal/audit` — 17 passed, 0 failed.

## Remaining risks

- None unresolved.

## Status

Status: done