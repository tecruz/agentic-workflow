# Standard Profile

The default for ordinary product and maintenance work. Applies whenever no
`prototype` or `high-assurance` condition holds.

## When to use

Use `standard` when:

- The task is ordinary product or maintenance work.
- No `high-assurance` escalation signal applies.
- The user has not requested a disposable prototype.

This is the default profile; a task that does not qualify for `prototype` or
`high-assurance` uses `standard`.

## Required evidence

```text
profile: standard
required_evidence:
  - acceptance_criteria
  - baseline_verification
  - final_verification
  - changed_files
  - remaining_risks
```

## Required task sections

A standard task file must include:

- **Risk profile** - the `Profile: standard` declaration.
- **Profile rationale** - why this level applies and any escalation signals.
- **Acceptance criteria** - observable, testable conditions with identifiers
  (`AC-N`).
- **Required evidence** - a table mapping each criterion to the evidence that
  satisfies it and a result token (`passed`, `satisfied`, `n/a`, `pending`,
  `partial`, `blocked`, `missing`, `not-run`).
- **Approval gates** - structured `AG-N` records
  (`- [x] AG-1: Approved by <approver> on YYYY-MM-DD`) or `None identified`.
- **Verification** - `### Baseline` and `### Final` scoped under it.
- **Files changed** - the list of files touched by the task.
- **Remaining risks** - known risks, blockers, and open questions.

## Escalation

Escalate to `high-assurance` when any escalation signal in
[`README.md`](README.md#escalation-signals) applies. Agents may escalate
automatically; they must not silently downgrade.

## Handoff

Mark the task `done` under `## Status` and run the validator with
`--handoff` (Bash) / `-Handoff` (PowerShell) as the final gate before
handing off. Handoff requires `Status: done`, resolved evidence, and checked
approval gates.