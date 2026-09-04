#!/usr/bin/env bash
#
# validate-handoff.sh — single public handoff gate for completed agentic tasks.
#
# Runs ALL THREE production validators against one task file and requires all
# to pass in --handoff mode:
#
#   1. validate-task.sh    --handoff   (risk profile, evidence, approvals)
#   2. validate-context.sh --handoff   (context-module selections)
#   3. validate-skills.sh  --handoff   (skill invocations)
#
# All validators inspect the same file, so their results refer to the same
# task and profile by construction. The gate is satisfied only when none
# reports an unresolved approval, evidence, module-selection, or
# skill-invocation state.
#
# Exit codes:
#   0  all gates VALID
#   1  at least one gate INVALID (no BLOCKED)
#   2  at least one gate BLOCKED (completion state unresolved)
#
# Usage:
#   ./.agentic/scripts/validate-handoff.sh path/to/TASK-001.md

set -uo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: validate-handoff.sh <task-file>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_FILE="$1"

if [ ! -f "$TASK_FILE" ]; then
    echo "INVALID: task file not found: $TASK_FILE" >&2
    exit 1
fi

task_code=0
task_diag="$(bash "$SCRIPT_DIR/validate-task.sh" --handoff "$TASK_FILE" 2>&1 >/dev/null)" || task_code=$?

context_code=0
context_diag="$(bash "$SCRIPT_DIR/validate-context.sh" --handoff "$TASK_FILE" 2>&1 >/dev/null)" || context_code=$?

skills_code=0
skills_diag="$(bash "$SCRIPT_DIR/validate-skills.sh" --handoff "$TASK_FILE" 2>&1 >/dev/null)" || skills_code=$?

if [ "$task_code" -eq 0 ] && [ "$context_code" -eq 0 ] && [ "$skills_code" -eq 0 ]; then
    echo "VALID: handoff gate satisfied (task contract + context contract + skills contract)"
    exit 0
fi

gate_code=1
if [ "$task_code" -eq 2 ] || [ "$context_code" -eq 2 ] || [ "$skills_code" -eq 2 ]; then
    gate_code=2
fi

first_line() {
    local line
    line="$(printf '%s' "$1" | head -n 1)"
    printf '%s' "${line:-<no diagnostic>}"
}

case "$gate_code" in
    2) echo "BLOCKED: handoff gate failed (task=$task_code: $(first_line "$task_diag"); context=$context_code: $(first_line "$context_diag"); skills=$skills_code: $(first_line "$skills_diag"))" >&2 ;;
    *) echo "INVALID: handoff gate failed (task=$task_code: $(first_line "$task_diag"); context=$context_code: $(first_line "$context_diag"); skills=$skills_code: $(first_line "$skills_diag"))" >&2 ;;
esac
exit "$gate_code"
