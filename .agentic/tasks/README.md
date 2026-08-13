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

```markdown
# TASK-NNN — <short description>

- **Status**: open | in-progress | blocked | done | cancelled
- **Owner**: [person or agent]
- **Created**: [date]
- **Updated**: [date]

## Scope
[What this task covers.]

## Acceptance Criteria
- [ ] [observable, testable condition 1]
- [ ] [observable, testable condition 2]

## Affected Areas
- [modules/files]

## Verification Evidence
- Commands run and their exit codes / results (see `.agentic/scripts/verify.sh`).
- Pre-existing failures or environment blockers, if any.

## Handoff Notes
- Remaining risks, open questions, and what a future session must know.
```

## Guidance

- Update the **Status** and **Updated** fields, not the whole file, as work
  progresses.
- Mark tasks `done` only after verification evidence exists.
- Do not delete task files; they are the project's history.
