# High-Assurance Profile

For authentication, authorization, payments, data migrations, cryptography,
production infrastructure, privacy-sensitive code, healthcare, and other
high-impact changes. These changes can cause serious harm when they fail, so
they demand explicit requirements, evidence, approvals, and independent review.

## When to use

Use `high-assurance` when the task affects:

- Authentication or authorization
- Payments or financial calculations
- Secrets, credentials, or cryptography
- Database schemas or destructive migrations
- User privacy or regulated information
- Production infrastructure or deployment
- Irreversible data operations
- Public API compatibility
- Safety-critical or healthcare behavior

## Required evidence

```text
profile: high-assurance
required_evidence:
  - explicit_requirements
  - risk_analysis
  - requirement_evidence_matrix
  - negative_path_tests
  - integration_tests
  - recovery_plan
  - approval_records
  - independent_review
  - final_verification
```

## Required task sections

A high-assurance task file must include:

- **Requirements** — explicit, verifiable requirements with identifiers
  (`R-N`).
- **Risk analysis** — the threat model, blast radius, and mitigations.
- **Requirement-to-evidence mapping** — a matrix connecting each requirement to
  the evidence that proves it.
- **Negative-path and boundary tests** — tests for failure modes, invalid
  input, and boundary conditions.
- **Integration verification** — verification against real integrations and
  dependent systems.
- **Recovery plan** — rollback or recovery steps if the change must be undone.
- **Approval gates** — explicit human approval records.
- **Independent review** — review by someone other than the implementer.
- **Baseline verification** — the verification result before changes began.
- **Final verification** — the verification result after the final
  modification, with no unresolved required check.

## Rules

- Agents may escalate to `high-assurance` automatically.
- A user-requested lower profile does **not** override mandatory safety or
  approval constraints.
- No unresolved required check may remain at handoff.
- Required approvals must be recorded **before** the task is marked complete.

## Handoff

```text
Profile: high-assurance
Requirement-to-evidence matrix:
Threat/risk findings:
Approval records:
Recovery plan:
Independent review:
Final verification:
Unresolved risks:
```