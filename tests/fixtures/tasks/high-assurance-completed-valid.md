# TASK-204: Ship zero-downtime deployment gate

## Risk profile

Profile: high-assurance

## Profile rationale

Affects production infrastructure. Escalated to high-assurance.

## Requirements

- R-1: Deployments require a passing health check before cutover.
- R-2: The gate can be bypassed only with a recorded human approval.

## Risk analysis

Threat: cutover to an unhealthy deployment causes an outage. Blast radius:
all production traffic. Mitigations: mandatory health check, approval-gated
bypass, staged rollout with automatic rollback.

## Requirement-to-evidence

| Requirement | Evidence required | Result |
|---|---|---|
| R-1 | Deployment integration test | Passed |
| R-2 | Approval-record test | Passed |

## Acceptance criteria

- AC-1: Cutover is blocked when the health check fails.
- AC-2: Bypass writes an approval record to the audit log.

## Required evidence

| Criterion | Evidence required | Result |
|---|---|---|
| AC-1 | Negative-path deploy test | Passed |
| AC-2 | Audit log assertion | Passed |

## Negative-path and boundary tests

- Health check fails at cutover.
- Health check times out.
- Bypass without an approval record.

## Integration verification

Staging: deploy gate exercised against staging environment; block and bypass
paths both verified.

## Recovery plan

Re-enable the mandatory gate and redeploy the last known-good release; the
rollback task is fully automated.

## Approval gates

- [x] Approved by: infra-owner@example.com (2026-08-17)
- [x] Signed off: change-review@example.com (2026-08-17)

## Independent review

Reviewed by an engineer who did not author the gate; confirmed the health
check cannot be silently skipped.

## Files changed

- `deploy/gate.sh`
- `deploy/gate_test.sh`
- `deploy/audit.go`

## Verification

### Baseline

`deploy/gate_test.sh` — 6 passed, 0 failed.

### Final

`deploy/gate_test.sh` — 9 passed, 0 failed. Staging dry run passed.

## Remaining risks

- None unresolved.

## Status

Status: done