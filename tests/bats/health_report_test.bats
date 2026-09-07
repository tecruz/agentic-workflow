#!/usr/bin/env bats

# health-report.sh — project health summary smoke tests.
# The report is informational (always exit 0); these tests assert the
# sections render and the VERSION consistency check sees every emitter
# twin plus the eval runner.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
REPORT="$REPO_ROOT/.agentic/scripts/health-report.sh"

@test "health-report exits 0 and renders the expected sections" {
    run bash "$REPORT" 2>&1
    if [ "$status" -ne 0 ]; then
        echo "STATUS=$status"
        echo "$output"
    fi
    [ "$status" -eq 0 ]
    grep -q "Agentic Workflow Health Report" <<<"$output"
    grep -q "── Tasks" <<<"$output"
    grep -q "── Context Module Usage" <<<"$output"
    grep -q "── Skill Invocation Usage" <<<"$output"
    grep -q "── Profile Distribution" <<<"$output"
    grep -q "── VERSION Consistency" <<<"$output"
    grep -q "── Recent Task Changes" <<<"$output"
    grep -q "Report complete. All checks informational" <<<"$output"
}

@test "health-report VERSION consistency covers Bash and PowerShell emitters" {
    run bash "$REPORT" 2>&1
    if [ "$status" -ne 0 ]; then
        echo "STATUS=$status"
        echo "$output"
    fi
    [ "$status" -eq 0 ]
    grep -q "verify.sh:" <<<"$output"
    grep -q "verify.ps1:" <<<"$output"
    grep -q "coordinator.sh:" <<<"$output"
    grep -q "coordinator.ps1:" <<<"$output"
    grep -q "Status: CONSISTENT" <<<"$output"
}

@test "health-report reports the repository's own version" {
    run bash "$REPORT" 2>&1
    if [ "$status" -ne 0 ]; then
        echo "STATUS=$status"
        echo "$output"
    fi
    [ "$status" -eq 0 ]
    expected="$(cat "$REPO_ROOT/.agentic/VERSION" | tr -d '[:space:]')"
    grep -q "\.agentic/VERSION: $expected" <<<"$output"
}
