# Handoff Verdict

> Copy this template into `.agentic/tasks/` alongside the task file when marking a task `done` in the HANDOFF phase. It is the single public gate that summarizes what changed, what was verified, and what remains. All three production validators (`validate-task`, `validate-context`, `validate-skills`) must pass before a handoff is accepted.

## Task Reference

- **Task file**: `.agentic/tasks/TASK-NNN.md`
- **Risk profile**: [standard / high-assurance / prototype]

## Files Changed

- [list every modified, added, or deleted file path]

## Verification

| Command | Exit Code | Result |
| --- | --- | --- |
| `./.agentic/scripts/verify.sh` | [0 / 1 / 2 / 3] | [PASS / FAIL / BLOCKED / UNSUPPORTED] |
| [additional command] | [code] | [result] |

## Pre-Existing Failures

- [failures that existed before this task — not caused by this change]

## Blockers

- [anything that prevented completion or full verification — e.g. missing tooling, environment constraints]

## Remaining Risks

- [known risks, open questions, or follow-up work]

## Commit Status

- [committed / not committed]
- [commit SHA or "none"]

## Profile Evidence

| Requirement | Met |
| --- | --- |
| [e.g. unit tests] | [yes / no — brief note] |
| [e.g. lint passes] | [yes / no — brief note] |

## Context Modules

- None selected

## Skills

- None required
