# Module: security-review

## ID

security-review

## Version

1

## Minimum risk profile

high-assurance

## Load when

- Authentication or authorization changes
- Session, token, secret, or credential handling
- Permission-boundary changes
- Cryptographic primitives, key management, or trust-boundary changes

## Required context

- Existing security model and documented trust boundaries
- Authentication and authorization tests
- Relevant architecture decision records for security-sensitive behavior
- Threat model notes, where the project maintains them

## Approval gates

- Security approval required for trust-boundary changes
- Explicit approval required before changing credential handling or storage

## Required evidence

- Negative-path tests proving rejection of unauthorized access
- Authorization-boundary tests covering the changed boundary
- Threat/risk analysis recorded in the task file

## Prohibited shortcuts

- Do not weaken security tests to make them pass
- Do not log credentials, tokens, or secrets
- Do not bypass approval gates, even when a change appears small
