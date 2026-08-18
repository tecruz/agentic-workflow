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

- **Acceptance criteria** — observable, testable conditions with identifiers
  (`AC-N`).
- **Required evidence** — a table mapping each criterion to the evidence that
  satisfies it.
- **Files changed** — the list of files touched by the task.
- **Baseline verification** — the verification result before changes began.
- **Final verification** — the verification result after the final
  modification.
- **Remaining risks** — known risks, blockers, and open questions.

## Escalation

Escalate to `high-assurance` when any escalation signal in
[`README.md`](README.md#escalation-signals) applies. Agents may escalate
automatically; they must not silently downgrade.

## Handoff

```text
Profile: standard
Acceptance criteria:
Files changed:
Baseline verification:
Final verification:
Remaining risks:
```