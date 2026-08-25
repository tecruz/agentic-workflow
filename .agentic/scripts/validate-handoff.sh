#!/usr/bin/env bash
#
# validate-handoff.sh — single public handoff gate for completed agentic tasks.
#
# Runs BOTH production validators against one task file and requires both to
# pass in --handoff mode:
#
#   1. validate-task.sh    --handoff   (risk profile, evidence, approvals)
#   2. validate-context.sh --handoff   (context-module selections)
#
# Both validators inspect the same file, so their results refer to the same
# task and profile by construction. The gate is satisfied only when neither
# reports an unresolved approval, evidence, or module-selection state.
#
# Exit codes:
#   0  both gates VALID
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
bash "$SCRIPT_DIR/validate-task.sh" --handoff "$TASK_FILE" >/dev/null 2>&1 || task_code=$?

context_code=0
bash "$SCRIPT_DIR/validate-context.sh" --handoff "$TASK_FILE" >/dev/null 2>&1 || context_code=$?

if [ "$task_code" -eq 0 ] && [ "$context_code" -eq 0 ]; then
    echo "VALID: handoff gate satisfied (task contract + context contract)"
    exit 0
fi

gate_code=1
if [ "$task_code" -eq 2 ] || [ "$context_code" -eq 2 ]; then
    gate_code=2
fi

case "$gate_code" in
    2) echo "BLOCKED: handoff gate failed (task=$task_code context=$context_code)" >&2 ;;
    *) echo "INVALID: handoff gate failed (task=$task_code context=$context_code)" >&2 ;;
esac
exit "$gate_code"
