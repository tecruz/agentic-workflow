# Skill: task-decomposition

## ID

task-decomposition

## Version

1

## Minimum risk profile

standard

## Invoked when

- Breaking a user request into atomic, verifiable steps before planning
- A task file is created or re-scoped under `.agentic/tasks/`
- Acceptance criteria (AC-N) must be enumerated with evidence mappings

## Required context

- The user request and its scope boundaries
- `.agentic/WORKFLOW.md` phase definitions (PLAN before IMPLEMENT)
- The task template (`.agentic/templates/task.md`) and risk-profile evidence contract
- Existing STATUS.md rows that constrain or duplicate the work

## Approval gates

- No extra approval beyond the task's own gates; decomposition itself never authorizes destructive actions

## Required evidence

- Acceptance criteria with AC-N identifiers recorded in the task file
- Required-evidence table mapping each AC-N to its proof
- Updated STATUS.md index entry for the task

## Prohibited shortcuts

- Do not start implementing before the decomposition is recorded
- Do not merge distinct verifiable outcomes into a single AC-N
- Do not leave acceptance criteria without an evidence mapping
