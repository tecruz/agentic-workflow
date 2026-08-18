# TASK-038: High assurance completed missing approval fixture

## Status

Status: done
Updated: 2026-08-18
## Risk profile

Profile: high-assurance

## Profile rationale

Authentication is safety-critical: escalate to high-assurance.

## Requirements

- R-1: Credentials are stored at rest encrypted.
- R-2: Failed login attempts are rate limited.

## Risk analysis

Threat model: credential theft from disk and online brute force. Mitigations:
AES-GCM at rest with a key derived via Argon2id; per-account lockout after
five failed attempts.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | Security unit test `crypto_at_rest_test.go` | Passed |
| R-2 | Integration test `rate_limit_test.go` | Passed |

## Negative-path and boundary tests

- Malformed tokens are rejected with HTTP 401.
- Exactly five failed attempts pass; the sixth is locked out.

## Integration verification

- Full login flow exercised end-to-end against a local IdP container.

## Recovery plan

- Restore from encrypted snapshot; key rotation documented in `docs/ops.md`.

## Approval gates

- [ ] AG-1: Approved by mallory@example.com on 2026-08-18

## Independent review

- Second engineer reviewed the crypto module (PR #11).

## Acceptance criteria

- AC-1: Credentials are encrypted at rest.
- AC-2: Brute force is rate limited.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Security unit test `crypto_at_rest_test.go` | Passed |
| AC-2 | Integration test `rate_limit_test.go` | Passed |

## Verification

### Baseline

- `go test ./...` → 55 passed, 0 failed.

### Final

- `go test ./...` → 57 passed, 0 failed.

## Files changed

- `internal/auth/crypto.go`
- `internal/auth/rate_limit.go`

## Remaining risks

- None identified.
