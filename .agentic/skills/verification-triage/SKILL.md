# Skill: verification-triage

## ID

verification-triage

## Version

1

## Minimum risk profile

standard

## Invoked when

- A required check in `.agentic/checks.tsv` fails or reports BLOCKED
- A verifier emits FAIL and a repair cycle is contemplated
- Flaky or order-dependent test behavior must be distinguished from real regressions

## Required context

- The failing check's command, working directory, and full output
- The pre-change baseline result for the same check
- The bounded self-healing budget (at most three evidence-based repair cycles)
- Test-integrity rule: failing tests are never weakened to go green

## Approval gates

- No extra approval beyond the task's own gates; each repair cycle must cite the evidence that motivated it

## Required evidence

- Baseline vs final verification results with exit codes
- Root-cause hypothesis per repair cycle and the diff that tested it
- Distinction between pre-existing failures and failures introduced by the change

## Prohibited shortcuts

- Do not loop past three repair cycles without reporting a blocker
- Do not weaken, delete, skip, or rewrite a failing test to obtain green
- Do not conceal environment or dependency blockers as passes
