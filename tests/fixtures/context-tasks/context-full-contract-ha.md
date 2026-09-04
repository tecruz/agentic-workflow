# TASK-FX: full high-assurance contract with a context selection

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: high-assurance

## Profile rationale

Fixture exercises the composite handoff gate against a complete
high-assurance task contract that also carries a context-module selection.

## Requirements

- R-1: The change preserves every documented authorization boundary.

## Risk analysis

The touched surface is authentication-adjacent; trust boundaries are
unchanged, and the risk of regression is bounded by the boundary tests
required below.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | authorization-boundary-tests: privilege matrix covered | passed |

## Negative-path and boundary tests

Unauthorized access attempts are rejected across the changed boundary.

## Integration verification

Full verification suite runs green on the fixture repository layout.

## Recovery plan

Revert the single commit and re-run verification; no data migration exists.

## Independent review

Reviewer confirmed the boundary coverage and recovery steps suffice for the
fixture scope.

## Acceptance criteria

- AC-1: Authorization boundaries hold after the change.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | negative-path-tests: unauthorized access rejected | passed |

## Approval gates

- [x] AG-1: Approved by Security on 2026-08-24

## Context modules

- security-review v1 loaded — fixture exercises the security-review floor

## Skills

- verification-triage v1 invoked — fixture exercises the skills leg of the handoff gate

## Verification

### Baseline

Baseline verification ran before the change and recorded PASS.

### Final

Final verification ran after the change and recorded PASS.

## Files changed

- src/auth/session.ts — session handling adjustment.

## Remaining risks

- None identified
