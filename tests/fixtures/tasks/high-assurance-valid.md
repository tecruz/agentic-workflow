# TASK-201: Rotate user session signing keys

## Risk profile

Profile: high-assurance

## Profile rationale

Involves secrets and cryptography; session forgery would compromise all accounts. Escalated to high-assurance.

## Requirements

- R-1: Session signing keys rotate without invalidating active sessions.
- R-2: The rotation procedure is fully reversible within one window.
- R-3: No plaintext key material is ever written to logs or the repository.

## Risk analysis

Threat: a compromised key lets an attacker forge sessions. Blast radius: all
authenticated accounts. Mitigations: dual-key overlap during rotation, short
signing window, key material held only in the secret store, rotation rehearsed
in staging first.

## Requirement-to-evidence

| Requirement | Evidence required | Result |
|---|---|---|
| R-1 | Rotation integration test | Passed |
| R-2 | Rollback dry run in staging | Passed |
| R-3 | Secret scan on full diff | Passed |

## Acceptance criteria

- AC-1: Rotation script updates the active signing key with overlap.
- AC-2: Rollback restores the previous key within the overlap window.

## Required evidence

| Criterion | Evidence required | Result |
|---|---|---|
| AC-1 | Rotation integration test | Passed |
| AC-2 | Rollback test | Passed |

## Negative-path and boundary tests

- Rotation with a corrupted key entry.
- Rotation when the overlap window has elapsed.
- Concurrent session issuance during rotation.

## Integration verification

Staging: rotation ran against the staging secret store, sessions remained valid
across the rotation, rollback restored the prior key. Production not touched.

## Recovery plan

If rotation fails after the new key is active, re-run the stored rollback
procedure within the overlap window; the old key remains valid until expiry.

## Approval gates

- [x] Approved by: security-owner@example.com (2026-08-14)
- [x] Signed off: change-review@example.com (2026-08-14)

## Independent review

Reviewed by a second engineer who did not author the rotation script; found no
plaintext-key or overlap-window defects.

## Files changed

- `internal/session/rotation.go`
- `internal/session/rotation_test.go`
- `scripts/rotate-session-keys.sh`

## Verification

### Baseline

`go test ./internal/session` — 31 passed, 0 failed.

### Final

`go test ./internal/session` — 35 passed, 0 failed. `git diff` secret scan clean.

## Remaining risks

- None unresolved.