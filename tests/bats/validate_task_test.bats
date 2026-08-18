#!/usr/bin/env bats

# validate-task.sh — risk-profile and evidence-contract validator tests.
# Runs against the fixture task files under tests/fixtures/tasks. Expected
# classifications are deterministic and language-independent:
#   0 = VALID, 1 = INVALID, 2 = BLOCKED.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
VALIDATE="$REPO_ROOT/.agentic/scripts/validate-task.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/tasks"

have() { command -v "$1" >/dev/null 2>&1; }

classify() {  # classify <fixture>
    run bash "$VALIDATE" "$FIXTURES/$1" >/dev/null 2>&1
}

@test "VALID (0) for a complete prototype task" {
    classify prototype-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a prototype task whose handoff lacks the production-readiness warning" {
    classify prototype-missing-warning.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a complete standard task" {
    classify standard-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a standard task missing its baseline verification" {
    classify standard-missing-baseline.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a complete high-assurance task" {
    classify high-assurance-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a high-assurance task missing risk analysis" {
    classify high-assurance-missing-risk-analysis.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a high-assurance task missing a recovery plan" {
    classify high-assurance-missing-recovery-plan.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a completed task with Pending required evidence" {
    classify completed-with-pending-evidence.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) for a task declaring an unknown profile" {
    classify unknown-profile.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a completed high-assurance task with approvals recorded" {
    classify high-assurance-completed-valid.md
    [ "$status" -eq 0 ]
}

@test "BLOCKED (2) for a completed high-assurance task lacking approval records" {
    classify high-assurance-completed-missing-approval.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when the task file does not exist" {
    run bash "$VALIDATE" "$FIXTURES/does-not-exist.md" >/dev/null 2>&1
    [ "$status" -eq 1 ]
}

@test "Bash and PowerShell classifiers agree on every fixture" {
    have pwsh || skip "pwsh not available"
    local f bash_code ps_code
    for f in "$FIXTURES"/*.md; do
        run bash "$VALIDATE" "$f"
        bash_code=$status
        run pwsh -NoProfile -File "$REPO_ROOT/.agentic/scripts/validate-task.ps1" "$f"
        ps_code=$status
        if [ "$bash_code" -ne "$ps_code" ]; then
            echo "classification mismatch for '$(basename "$f")': bash=$bash_code ps=$ps_code" >&2
            return 1
        fi
    done
}

@test "INVALID (1) for a prototype task missing the no-production-deployment declaration" {
    classify prototype-missing-production-declaration.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for an in-progress standard task" {
    classify standard-in-progress.md
    [ "$status" -eq 0 ]
}

@test "BLOCKED (2) for --handoff on a task that is not done" {
    run bash "$VALIDATE" --handoff "$FIXTURES/standard-in-progress.md" >/dev/null 2>&1
    [ "$status" -eq 2 ]
}

@test "VALID (0) for --handoff on a done standard task" {
    run bash "$VALIDATE" --handoff "$FIXTURES/standard-valid.md" >/dev/null 2>&1
    [ "$status" -eq 0 ]
}

@test "BLOCKED (2) for a completed task with Partial required evidence" {
    classify completed-with-partial-evidence.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) for a completed task with a blank evidence result" {
    classify completed-with-blank-result.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when required evidence does not map every criterion" {
    classify unmapped-evidence.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when acceptance criteria repeat an identifier" {
    classify duplicate-ac.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an unrecognized status value" {
    classify unknown-status.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Status is declared more than once" {
    classify duplicate-status.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Profile is declared more than once" {
    classify duplicate-profile.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when all required words live in a single heading" {
    classify single-heading-all-words.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the profile heading is split" {
    classify split-headings.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Baseline is not scoped under Verification" {
    classify baseline-outside-verification.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when required headings are inside a fenced code block" {
    classify headings-in-fenced-code.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a completed task with an unchecked approval gate" {
    classify unchecked-gate.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when approval is negated rather than granted" {
    classify negated-approval.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when approval is recorded as not granted" {
    classify approval-not-granted.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when high-assurance evidence mapping omits a requirement" {
    classify high-assurance-unmapped-matrix.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an empty high-assurance risk analysis" {
    classify high-assurance-empty-risk-analysis.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when a high-assurance task declares None identified approvals" {
    classify high-assurance-none-identified.md
    [ "$status" -eq 1 ]
}