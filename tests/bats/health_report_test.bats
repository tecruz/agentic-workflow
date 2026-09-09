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

@test "health-report twins emit identical normalized output (cross-language parity)" {
    if ! command -v pwsh >/dev/null 2>&1; then
        skip "pwsh not available"
    fi
    # Normalize: drop blank lines, the timestamp line (format differs between
    # `date +%Z` and Get-Date K), and the VERSION Consistency block (the twins
    # sort emitters by full path vs short name). Everything else — tasks,
    # module/skill usage, profiles, recent changes — must match byte-for-byte.
    normalize() {
        printf '%s' "$1" | sed '/^[[:space:]]*$/d; /^  [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} /d' \
            | awk '/VERSION Consistency/ { skip = 1; next } /Recent Task Changes/ { skip = 0 } !skip'
    }
    emitters() {  # sorted emitter names from the VERSION block
        printf '%s' "$1" | sed -n '/VERSION Consistency/,/Recent Task Changes/p' \
            | grep '^    .*: [0-9]' | sed 's/^ *//; s/:.*//' | sort
    }
    sh_out="$(bash "$REPORT" 2>&1)"
    ps_out="$(pwsh -NoProfile -File "$REPO_ROOT/.agentic/scripts/health-report.ps1" 2>&1)"
    sh_norm="$(normalize "$sh_out")"
    ps_norm="$(normalize "$ps_out")"
    if [ "$sh_norm" != "$ps_norm" ]; then
        echo "normalized parity mismatch:"
        diff -u <(printf '%s\n' "$sh_norm") <(printf '%s\n' "$ps_norm") || true
        return 1
    fi
    if [ "$(emitters "$sh_out")" != "$(emitters "$ps_out")" ]; then
        echo "emitter-set mismatch: bash=[$(emitters "$sh_out")] ps1=[$(emitters "$ps_out")]"
        return 1
    fi
    grep -q "Status: CONSISTENT" <<<"$ps_out"
}
