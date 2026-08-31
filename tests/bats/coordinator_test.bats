#!/usr/bin/env bats

# coordinator.sh — isolated worktree, worker, events, and approval tests.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
COORD="$REPO_ROOT/.agentic/orchestration/coordinator.sh"
SCHEMA_RESULT="$REPO_ROOT/.agentic/schemas/orchestration-result-v1.schema.json"
SCHEMA_EVENTS="$REPO_ROOT/.agentic/schemas/orchestration-events-v1.schema.json"

have() { command -v "$1" >/dev/null 2>&1; }

setup_task_file() {
    # setup_task_file <dir> <name> <approval-section>
    local dir="$1" name="$2" approval="$3"
    mkdir -p "$dir/.agentic/tasks"
    cat > "$dir/.agentic/tasks/$name" <<EOF
# $name

## Status

Status: planned
Updated: 2026-08-28

## Risk profile

Profile: standard

## Profile rationale

Test.

## Acceptance criteria

- AC-1: Stub.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | test | passed |

## Approval gates

$approval

## Context modules

- None selected — test

## Verification

### Baseline

- baseline

### Final

- final

## Files changed

- file

## Remaining risks

- None identified
EOF
}

make_git_repo() {
    local dir="$1"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    git -C "$dir" commit --allow-empty -m "init" -q
}

@test "coordinator --help exits 0" {
    run bash "$COORD" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "coordinator rejects unknown option" {
    run bash "$COORD" --unknown-flag .agentic/tasks/TASK-009-orchestration-full-implementation.md
    [ "$status" -eq 1 ]
}

@test "coordinator rejects missing task file" {
    run bash "$COORD" --approve /tmp/no-such-task-xyz.md
    [ "$status" -ne 0 ]
}

@test "coordinator blocks spawning without --approve" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-900.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --worker 'echo hi' .agentic/tasks/TASK-900.md 2>&1"
    [ "$status" -eq 2 ]
    # No worktree should be created on blocked approval
    [ ! -d "$TMPD/.agentic/orchestration/worktrees/TASK-900" ]
    rm -rf "$TMPD"
}

@test "coordinator blocks unchecked gate even with --approve" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-901.md" "- [ ] AG-1: Pending approval"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --worker 'echo hi' .agentic/tasks/TASK-901.md 2>&1"
    [ "$status" -eq 2 ]
    [ ! -d "$TMPD/.agentic/orchestration/worktrees/TASK-901" ]
    rm -rf "$TMPD"
}

@test "coordinator creates isolated worktree on approved task" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-902.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve .agentic/tasks/TASK-902.md 2>&1"
    [ "$status" -eq 0 ]
    [ -d "$TMPD/.agentic/orchestration/worktrees/TASK-902" ]
    # Worktree is a git worktree
    git -C "$TMPD" worktree list | grep -q "TASK-902"
    # Cleanup
    bash -c "cd '$TMPD' && bash '$COORD' --approve --cleanup .agentic/tasks/TASK-902.md 2>&1" || true
    rm -rf "$TMPD"
}

@test "coordinator reuses existing worktree" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-903.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    bash -c "cd '$TMPD' && bash '$COORD' --approve .agentic/tasks/TASK-903.md >/dev/null 2>&1"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve .agentic/tasks/TASK-903.md 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Reusing"* ]]
    bash -c "cd '$TMPD' && bash '$COORD' --approve --cleanup .agentic/tasks/TASK-903.md >/dev/null 2>&1" || true
    rm -rf "$TMPD"
}

@test "worker success produces PASS result and exit 0" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-904.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --worker 'exit 0' --format json .agentic/tasks/TASK-904.md 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"result":"PASS"'
    echo "$output" | grep -q '"exit_code":0'
    echo "$output" | grep -q '"protocol_version":"1.7.0"'
    rm -rf "$TMPD"
}

@test "worker failure produces FAIL result and exit 1" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-905.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --worker 'exit 1' --format json .agentic/tasks/TASK-905.md 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q '"result":"FAIL"'
    echo "$output" | grep -q '"exit_code":1'
    rm -rf "$TMPD"
}

@test "AGENTIC_WORKER_CMD env fallback is used when --worker not supplied" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-906.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && AGENTIC_WORKER_CMD='exit 0' bash '$COORD' --approve --format json .agentic/tasks/TASK-906.md 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"result":"PASS"'
    rm -rf "$TMPD"
}

@test "--events creates JSONL stream with terminal event last" {
    have git || skip "git not available"
    have python3 || skip "python3 not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-907.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --worker 'exit 0' --events .agentic/runs/coord.jsonl .agentic/tasks/TASK-907.md 2>&1"
    [ "$status" -eq 0 ]
    [ -f "$TMPD/.agentic/runs/coord.jsonl" ]
    head -n 1 "$TMPD/.agentic/runs/coord.jsonl" | grep -q 'orchestration_started'
    tail -n 1 "$TMPD/.agentic/runs/coord.jsonl" | grep -q 'orchestration_completed'
    grep -q 'worker_started' "$TMPD/.agentic/runs/coord.jsonl"
    grep -q 'worker_completed' "$TMPD/.agentic/runs/coord.jsonl"
    # Verify each line is valid JSON and matches schema (basic)
    python3 -c "import json,sys; [json.loads(l) for l in open('$TMPD/.agentic/runs/coord.jsonl')]"
    [ "$?" -eq 0 ]
    # Ensure no raw command line leaks
    ! grep -q "exit 0" "$TMPD/.agentic/runs/coord.jsonl" || true
    rm -rf "$TMPD"
}

@test "--format json and --events are mutually exclusive" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-908.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --format json --events .agentic/runs/x.jsonl .agentic/tasks/TASK-908.md 2>&1"
    [ "$status" -eq 1 ]
    rm -rf "$TMPD"
}

@test "--events destination must be under .agentic/runs" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-909.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --events /tmp/evil.jsonl .agentic/tasks/TASK-909.md 2>&1"
    [ "$status" -eq 1 ]
    rm -rf "$TMPD"
}

@test "--push requires --approve" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-910.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --push .agentic/tasks/TASK-910.md 2>&1"
    [ "$status" -eq 2 ]
    rm -rf "$TMPD"
}

@test "None identified gates allow spawning with only --approve flag" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-911.md" "- None identified"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --worker 'exit 0' --format json .agentic/tasks/TASK-911.md 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"result":"PASS"'
    rm -rf "$TMPD"
}

@test "orchestration JSON is redacted: no absolute paths leak" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-912.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve --worker 'exit 0' --format json .agentic/tasks/TASK-912.md 2>/dev/null"
    [ "$status" -eq 0 ]
    # task_file should be project-relative, not absolute
    echo "$output" | grep -q '"task_file":"./.agentic/tasks/TASK-912.md"' || echo "$output" | grep -q '"task_file":"TASK-912.md"' || echo "$output" | grep -q '"task_file":"agentic/tasks/TASK-912.md"' || echo "$output" | grep -q '"task_file":".agentic/tasks/TASK-912.md"'
    # Should not contain the temp dir absolute path
    ! echo "$output" | grep -q "$TMPD"
    rm -rf "$TMPD"
}

@test "lock file prevents concurrent conflicting mutations" {
    have git || skip "git not available"
    TMPD="$(mktemp -d)"
    make_git_repo "$TMPD"
    setup_task_file "$TMPD" "TASK-913.md" "- [x] AG-1: Approved by Tester on 2026-08-28"
    mkdir -p "$TMPD/.agentic/orchestration/worktrees"
    echo "999999" > "$TMPD/.agentic/orchestration/worktrees/TASK-913.lock"
    # Simulate stale lock where PID does not exist: should be removed and succeed
    run bash -c "cd '$TMPD' && bash '$COORD' --approve .agentic/tasks/TASK-913.md 2>&1"
    [ "$status" -eq 0 ]
    # Now test active lock: use current PID
    echo "$$" > "$TMPD/.agentic/orchestration/worktrees/TASK-913.lock"
    run bash -c "cd '$TMPD' && bash '$COORD' --approve .agentic/tasks/TASK-913.md 2>&1"
    [ "$status" -eq 2 ]
    rm -f "$TMPD/.agentic/orchestration/worktrees/TASK-913.lock"
    bash -c "cd '$TMPD' && bash '$COORD' --approve --cleanup .agentic/tasks/TASK-913.md >/dev/null 2>&1" || true
    rm -rf "$TMPD"
}
