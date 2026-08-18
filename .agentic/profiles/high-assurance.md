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

- **Risk profile** - the `Profile: high-assurance` declaration.
- **Profile rationale** - why this level applies.
- **Requirements** - explicit, verifiable requirements with identifiers
  (`R-N`).
- **Risk analysis** - the threat model, blast radius, and mitigations.
- **Requirement-to-evidence** - a matrix mapping each requirement to the
  evidence that proves it.
- **Negative-path and boundary tests** - tests for failure modes, invalid
  input, and boundary conditions.
- **Integration verification** - verification against real integrations and
  dependent systems.
- **Recovery plan** - rollback or recovery steps if the change must be undone.
- **Approval gates** - explicit human approval records.
- **Independent review** - review by someone other than the implementer.
- **Acceptance criteria** - observable, testable conditions with identifiers
  (`AC-N`).
- **Required evidence** - a table mapping each criterion to evidence with a
  result token.
- **Verification** - `### Baseline` and `### Final` scoped under it.
- **Files changed** and **Remaining risks**.

## Rules

- Agents may escalate to `high-assurance` automatically.
- A user-requested lower profile does **not** override mandatory safety or
  approval constraints.
- No unresolved required check may remain at handoff.
- Required approvals must be recorded **before** the task is marked complete.
- `None identified` is not permitted in the approval gates of a high-assurance
  task; explicit `AG-N` gates are required.

## Handoff

Mark the task `done` under `## Status` and run the validator with
`--handoff` (Bash) / `-Handoff` (PowerShell) as the final gate before
handing off. Handoff requires `Status: done`, resolved evidence, and checked
approval gates.