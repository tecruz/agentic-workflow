# TASK-021: README customization fix + optional-check policy resolution

## Status

Status: done
Updated: 2026-09-06

## Risk profile

Profile: standard

## Profile rationale

No code logic changes — a documentation bug fix and a policy clarification
that resolves a standing ROADMAP item. No escalation signals apply.

## Acceptance criteria

- AC-1: The README `## Customization` section is grammatically complete and
  reads as a coherent list.
- AC-2: The standing ROADMAP "Optional-check policy review" item is resolved
  with a documented decision.
- AC-3: The README optional-check description is accurate and current.
- AC-4: All locally runnable checks pass and unavailable tooling is documented.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | README Customization section restored: intro + 3 bullets (Change the protocol, Add stack-specific rules, Extend verification) | passed |
| AC-2 | ROADMAP.md updated with resolved decision + rationale (ADR-0002 invariant; no --strict-optional flag) | passed |
| AC-3 | README line 346: "`optional` checks run when their tooling is available but never fail a run" — accurate, unchanged | passed |
| AC-4 | verify.sh: 9 checks ran, sh-syntax × 7 + handoff-gate + evals-sh all passed; BLOCKED (exit 2) from missing pwsh/bats/shellcheck — pre-existing, unrelated | passed |

## Approval gates

- None identified

## Context modules

- None selected — documentation and policy clarification; no specialist module triggered

## Skills

- None required — no procedure invoked for this task

## Files changed

- `README.md` — restored dropped `## Customization` intro and missing first bullet ("Change the protocol")
- `ROADMAP.md` — resolved "Optional-check policy review" item with decision and rationale

## Verification

### Baseline

```
bash .agentic/scripts/verify.sh 2>&1; echo EXIT_CODE=$?
```
Result: VERIFICATION BLOCKED — required tooling (pwsh, bats, shellcheck)
unavailable on this host. 9 checks ran, sh-syntax + evals-sh passed.
EXIT_CODE=2.

### Final

```
bash .agentic/scripts/verify.sh 2>&1; echo EXIT_CODE=$?
```
Result: IDENTICAL to baseline — VERIFICATION BLOCKED (exit 2) from missing
pwsh/bats/shellcheck. 9 checks ran, all passed. No regressions.
EXIT_CODE=2.

```
bash .agentic/scripts/validate-task.sh .agentic/tasks/TASK-021-readme-fix-and-optional-policy.md 2>&1; echo EXIT_CODE=$?
```
Result: VALID (exit 0).

## Remaining risks

- Optional-check policy is a normative decision; adoption is voluntary.
