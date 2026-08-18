# Tasks

This directory holds **one file per task** so that concurrent agents and
developers never contend for a single shared state file.

## File convention

```
TASK-NNN-short-description.md
```

Number tasks sequentially (TASK-001, TASK-002, ...). Keep the description
short and kebab-case.

## Template

Start from `.agentic/templates/task.md`. It declares the task's risk profile
(`prototype` | `standard` | `high-assurance` - see `.agentic/profiles/`), its
status, the evidence required by that profile, and its approval gates.

```markdown
# TASK-NNN - <short description>

## Status

Status: planned
Updated: YYYY-MM-DD

## Risk profile

Profile: standard

## Profile rationale
[Why this level applies and any escalation signals.]

## Acceptance criteria
- AC-1: [observable, testable condition]

## Required evidence
| AC ID | Evidence | Result |
|---|---|---|
| AC-1 | Unit test | Pending |

## Approval gates
- [ ] AG-1: Approved by <approver> on YYYY-MM-DD

## Files changed
- [modules/files]

## Verification
### Baseline
[Verification before changes began.]
### Final
[Verification after the final modification.]

## Remaining risks
[Known risks, blockers, or open questions.]
```

## Guidance

- Update the **Status** and **Updated** fields, not the whole file, as work
  progresses.
- Mark tasks `done` only after verification evidence exists and no required
  evidence remains `Pending`; `.agentic/scripts/validate-task.sh` /
  `validate-task.ps1` refuse a completed task with unresolved evidence or an
  unchecked approval gate.
- Before handoff, run the validator with `--handoff` (Bash) / `-Handoff`
  (PowerShell); it requires `Status: done`. Marking a task `done` with
  unresolved evidence or an unchecked gate makes the validator report it as
  BLOCKED (exit `2`).
- Do not delete task files; they are the project's history.
