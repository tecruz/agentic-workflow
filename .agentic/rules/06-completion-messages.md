# 06 - Completion Message Rules

## Imperative Completion Rules

1. **Two-Option Completion Protocol**
   - Every completed-task report starts with exactly one canonical status line: `TASK-<ID>: done` or `TASK-<ID>: blocked - <reason>`.
   - Use `done` only when every acceptance criterion is satisfied with recorded evidence; otherwise use `blocked` and name the concrete blocker (missing approval, failing check, environment gap).
   - Never report partial success, "done except ...", or any third status.

2. **Fixed Report Shape**
   - After the status line, report fields in this fixed order: `files:`, `verify:` (one line per command), `deviations:`, `risks:`, `commit:`.
   - `files:` lists the count and paths changed (or `none`).
   - `deviations:` summarizes recorded phase-route skips and waived gates (or `none`).

3. **Exit Codes, Not Adjectives**
   - Every verification command appears as `<command> -> exit <code>`; adjectives such as "green" or "passing" without the command and its exit code are not evidence.

4. **No Emergent Deviations**
   - A deviation not recorded in the task file is a protocol violation: record skipped phases under `## Phase route`, waived expectations under `## Waived gates`, and residual exposure under `## Remaining risks` before reporting `done`.
   - Scope changes discovered mid-task go back to PLAN; they never appear for the first time in the completion message.

5. **Honest Negatives, No Placeholders**
   - `deviations: none`, `risks: none`, and `commit: none` are valid only when there is genuinely none.
   - Placeholder text (TBD, TODO, Pending, punctuation-only) in any field voids the report.

## Canonical Form

```text
TASK-048: done
files: 14 changed: .agentic/scripts/validate-task.sh, .agentic/rules/06-completion-messages.md, ...
verify: bash -n .agentic/scripts/validate-task.sh -> exit 0
verify: bats tests/bats/validate_task_test.bats -> exit 0
deviations: none
risks: behavioural norm in rules/06 is not machine-enforced (rules 01-05 precedent)
commit: none
```

Blocked example:

```text
TASK-049: blocked - validator exit 2 before any worker; approval gate AG-1 missing
files: 2 changed: .agentic/orchestration/coordinator.sh, .agentic/orchestration/coordinator.ps1
verify: bash -n .agentic/orchestration/coordinator.sh -> exit 0
deviations: phase route skips: IMPLEMENT (toolchain unavailable)
risks: skeleton checkpoint not exercised end-to-end
commit: none
```
