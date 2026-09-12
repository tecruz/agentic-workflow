# TASK-NNN: Title

## Status

Status: planned
Updated: 2026-08-18

> Copy this template into `.agentic/tasks/` when planning a task. Every task
> declares a risk profile, status, the required evidence for that profile, and its
> approval gates. Choose the profile per `.agentic/profiles/README.md`; the
> default is `standard`.

## Risk profile

Profile: standard

## Profile rationale

[Explain why this level applies and identify any escalation signals.]

## Acceptance criteria

- AC-1: [observable, testable condition]
- AC-2: [observable, testable condition]

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test | Pending |
| AC-2 | Integration test | Pending |

## Goal conditions

- Exit 0 when: [command or check that must succeed, e.g. `npm test`]
- Exit 0 when: [second verifiable end state]

<!-- Optional exit-0 definition of done (spec-pipeline goal support): one
bullet per machine-checkable end state, each phrased as "Exit 0 when: ...".
Validators enforce the canonical form and reject prose or non-canonical
lines; run 'validate-task --run-goals <file>' to execute each command and
require exit 0. Keep bullets free of AC-N / R-N / AG-N identifiers (those
belong to their canonical sections). Omit the section when goal conditions
add no signal beyond the acceptance criteria. -->

## Approval gates

- None identified

<!-- When approval is required:
- [ ] AG-1: Approval required from Security
- [x] AG-1: Approved by Alice Example on 2026-08-18
-->

## Context modules

- None selected

<!-- Inspect .agentic/context/INDEX.md during DISCOVER. For each module whose
"Load when" triggers match this task, record one bullet BEFORE planning:

- security-review v1 loaded — task changes session/authorization behavior

The line must carry: known module ID, recognized version (v<N> matching the
module), the loaded confirmation token, and a real rationale. Duplicate
modules are rejected. The task's profile must satisfy every selected module's
minimum risk profile. When no module applies use exactly:

- None selected — <optional: why no module applies>
-->

## Skills

- None required

<!-- Inspect .agentic/skills/INDEX.md during PLAN. For each skill whose
"Invoked when" triggers match this task, record one bullet BEFORE the
corresponding work begins:

- verification-triage v1 invoked — task triages a failing check before repairing

The line must carry: known skill ID, recognized version (v<N> matching the
skill), the invoked confirmation token, and a real rationale. Duplicate
skills are rejected. The task's profile must satisfy every invoked skill's
minimum risk profile. When no skill applies use exactly:

- None required — <optional: why no skill applies>
-->

## Files changed

- [paths]

## Verification

### Baseline

[Command and result before changes began.]

### Final

[Command and result after the final modification.]

## Remaining risks

- [Known risks, blockers, or open questions]