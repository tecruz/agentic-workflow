# TASK-153: Canonical requirement plus a prose-mentioned R identifier

## Status

Status: done
Updated: 2026-08-20
## Risk profile

Profile: high-assurance
## Profile rationale

Authentication is safety-critical: escalate to high-assurance.
## Requirements

- R-1: Credentials are stored at rest encrypted.

Operators must also satisfy R-2: audit logs are retained for 90 days.
## Risk analysis

Threat model: credential theft from disk. Mitigations: AES-GCM at rest.
## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | Security unit test `crypto_at_rest_test.go` | Passed |
## Negative-path and boundary tests

- Malformed tokens are rejected with HTTP 401.
## Integration verification

- Full login flow exercised end-to-end against a local IdP container.
## Recovery plan

- Restore from encrypted snapshot.
## Approval gates

- [x] AG-1: Approved by mallory@example.com on 2026-08-20
## Independent review

- Second engineer reviewed the crypto module.
## Acceptance criteria

- AC-1: Credentials are encrypted at rest.
## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Security unit test `crypto_at_rest_test.go` | Passed |
## Verification

### Baseline

- `go test ./...` → 55 passed, 0 failed.

### Final

- `go test ./...` → 57 passed, 0 failed.
## Files changed

- `internal/auth/crypto.go`
## Remaining risks

- None identified.