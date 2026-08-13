#!/usr/bin/env bats

# verify.sh — state-model tests.
# Runs against the fixture projects under tests/fixtures. Expected exit codes
# are environment-aware: fixtures whose executable is missing in the current
# environment must report BLOCKED (2), never PASS.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
VERIFY="$REPO_ROOT/.agentic/scripts/verify.sh"
FIX="$REPO_ROOT/tests/fixtures"

have() { command -v "$1" >/dev/null 2>&1; }

run_fixture() {  # run_fixture <fixture>
    run bash -c "cd '$FIX/$1' && bash '$VERIFY' >/dev/null 2>&1"
}

@test "PASS (0) when a Node/npm project's required checks all pass" {
    have npm || skip "npm not available"
    run_fixture node-npm
    [ "$status" -eq 0 ]
}

@test "FAIL (1) when a required check fails" {
    have npm || skip "npm not available"
    run_fixture node-npm-fail
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) when a required check's executable is missing" {
    run_fixture checks-tsv
    [ "$status" -eq 2 ]
}

@test "BLOCKED (2) beats PASS when one required check is blocked and another passes" {
    # checks-tsv defines one passing required check and one blocked required check.
    # PASS must be impossible because not every required check ran.
    run_fixture checks-tsv
    [ "$status" -eq 2 ]
}

@test "UNSUPPORTED (3) when no supported project or checks exist" {
    run_fixture unsupported
    [ "$status" -eq 3 ]
}

@test "PASS (0) for a checks.tsv whose required check passes" {
    have sh || skip "sh not available"
    run_fixture checks-tsv-pass
    [ "$status" -eq 0 ]
}

@test "FAIL (1) for a checks.tsv whose required check fails" {
    have sh || skip "sh not available"
    run_fixture checks-tsv-fail
    [ "$status" -eq 1 ]
}

@test "optional check failure is a warning, not a failure (PASS)" {
    have sh || skip "sh not available"
    run_fixture checks-tsv-optional
    [ "$status" -eq 0 ]
}

@test "a checks.tsv with only optional checks never reports PASS" {
    run_fixture checks-tsv-optional-only
    [ "$status" -ne 0 ]
}

@test "--emit-checks prints the detected npm checks on stdout" {
    have npm || skip "npm not available"
    run bash -c "cd '$FIX/node-npm' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    printf '%s' "$output" | grep -q $'\tnpm\t'
}

@test "--emit-checks emits nothing for an unsupported project" {
    run bash -c "cd '$FIX/unsupported' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "detection prefers the lockfile package manager (pnpm)" {
    run bash -c "cd '$FIX/node-pnpm' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tpnpm\t'
}

@test "a uv.lock project is detected as uv" {
    run bash -c "cd '$FIX/python-uv' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tuv\t'
}

@test "checks.tsv working dir escaping the project root is rejected" {
    mkdir -p .agentic
    printf 'required\ttest\t..\tsh\t-c\ttrue\n' > .agentic/checks.tsv
    run bash "$VERIFY"
    [ "$status" -eq 1 ]
}

@test "checks.tsv working dir through a symlink escape is rejected" {
    mkdir -p .agentic
    outside="$(mktemp -d)"
    ln -s "$outside" link
    printf 'required\ttest\tlink\tsh\t-c\ttrue\n' > .agentic/checks.tsv
    run bash "$VERIFY"
    [ "$status" -eq 1 ]
}

@test "checks.tsv working dir equal to the project root is accepted" {
    mkdir -p .agentic
    printf 'required\tok\t.\tsh\t-c\ttrue\n' > .agentic/checks.tsv
    run bash "$VERIFY"
    [ "$status" -eq 0 ]
}

@test "checks.tsv working dir inside the project is accepted" {
    mkdir -p .agentic nested
    printf 'required\tok\tnested\tsh\t-c\ttrue\n' > .agentic/checks.tsv
    run bash "$VERIFY"
    [ "$status" -eq 0 ]
}