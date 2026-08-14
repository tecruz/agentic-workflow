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
    run_checks_in_tmp 'required	test	..	sh	-c	true'
    [ "$status" -eq 1 ]
}

@test "checks.tsv working dir through a symlink escape is rejected" {
    TMPD="$(mktemp -d)"
    mkdir -p "$TMPD/.agentic"
    outside="$(mktemp -d)"
    ln -s "$outside" "$TMPD/link"
    printf 'required\ttest\tlink\tsh\t-c\ttrue\n' > "$TMPD/.agentic/checks.tsv"
    run bash -c "cd '$TMPD' && bash '$VERIFY' >/dev/null 2>&1"
    rm -rf "$TMPD" "$outside"
    [ "$status" -eq 1 ]
}

@test "checks.tsv working dir equal to the project root is accepted" {
    run_checks_in_tmp 'required	ok	.	sh	-c	true'
    [ "$status" -eq 0 ]
}

@test "checks.tsv working dir inside the project is accepted" {
    TMPD="$(mktemp -d)"
    mkdir -p "$TMPD/.agentic" "$TMPD/nested"
    printf 'required\tok\tnested\tsh\t-c\ttrue\n' > "$TMPD/.agentic/checks.tsv"
    run bash -c "cd '$TMPD' && bash '$VERIFY' >/dev/null 2>&1"
    rm -rf "$TMPD"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Review regression tests: empty-field TSV parsing, BLOCKED semantics, and
# path-qualified executables. Each test runs in an isolated temp project so it
# never touches the framework's own .agentic/checks.tsv.
# ---------------------------------------------------------------------------

run_checks_in_tmp() {  # run_checks_in_tmp <line>...
    TMPD="$(mktemp -d)"
    mkdir -p "$TMPD/.agentic"
    printf '%s\n' "$@" > "$TMPD/.agentic/checks.tsv"
    run bash -c "cd '$TMPD' && bash '$VERIFY' >/dev/null 2>&1"
    rm -rf "$TMPD"
}

@test "malformed checks.tsv with an empty executable is a configuration failure" {
    run_checks_in_tmp 'required	unit	.		true'
    [ "$status" -eq 1 ]
}

@test "malformed checks.tsv with an empty requirement is a configuration failure" {
    run_checks_in_tmp '	unit	.	sh	-c	true'
    [ "$status" -eq 1 ]
}

@test "malformed checks.tsv with an empty check ID is a configuration failure" {
    run_checks_in_tmp 'required		.	sh	-c	true'
    [ "$status" -eq 1 ]
}

@test "malformed checks.tsv with an empty working directory is a configuration failure" {
    run_checks_in_tmp 'required	unit		sh	-c	true'
    [ "$status" -eq 1 ]
}

@test "an empty executable never runs a shifted command from the next column" {
    # The empty executable must be rejected as a configuration failure, never
    # resolved to `true` from the argument column (which would falsely PASS).
    run_checks_in_tmp 'required	unit	.		true'
    [ "$status" -eq 1 ]
}

@test "leading and indented comment lines are ignored" {
    run_checks_in_tmp '# leading comment' '  # indented comment' '	# tab-indented' 'required	ok	.	sh	-c	true'
    [ "$status" -eq 0 ]
}

@test "a missing inside-project working directory reports BLOCKED (2)" {
    run_checks_in_tmp 'required	ok	missing-dir	sh	-c	true'
    [ "$status" -eq 2 ]
}

@test "a missing path-qualified executable reports BLOCKED (2), never a PATH fallback" {
    run_checks_in_tmp 'required	lint	.	./tools/lint'
    [ "$status" -eq 2 ]
}

@test "an empty interior argument is preserved and passed to the command" {
    # sh -c <script> a '' x -> $0=a, $1='' (empty preserved), $2=x, $#=2
    run_checks_in_tmp 'required	ok	.	sh	-c	[ $# -eq 2 ] && [ "$1" = "" ] && [ "$2" = x ]	a		x'
    [ "$status" -eq 0 ]
}

@test "a check that consumes stdin does not starve subsequent checks" {
    # A check that drains its stdin (e.g. `cat`) must not consume the checks.tsv
    # stream and silently skip the checks that follow it; that would be a false
    # PASS. The probe check after the consumer must still run.
    TMPD="$(mktemp -d)"
    mkdir -p "$TMPD/.agentic"
    printf '%s\n' \
        'required	consumer	.	sh	-c	cat >/dev/null' \
        'required	probe	.	sh	-c	touch ran' \
        > "$TMPD/.agentic/checks.tsv"
    run bash -c "cd '$TMPD' && bash '$VERIFY' >/dev/null 2>&1"
    [ "$status" -eq 0 ]
    [ -f "$TMPD/ran" ]
    rm -rf "$TMPD"
}

# ---------------------------------------------------------------------------
# Candidate lifecycle regression tests (--detect-checks / --validate-checks).
# ---------------------------------------------------------------------------

@test "--detect-checks writes a candidate contract that validates" {
    TMPD="$(mktemp -d)"
    printf '{"name":"x","scripts":{"test":"true"}}\n' > "$TMPD/package.json"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --detect-checks >/dev/null 2>&1"
    [ "$status" -eq 0 ]
    [ -f "$TMPD/.agentic/checks.generated.tsv" ]
    run bash -c "cd '$TMPD' && bash '$VERIFY' --validate-checks .agentic/checks.generated.tsv >/dev/null 2>&1"
    [ "$status" -eq 0 ]
    rm -rf "$TMPD"
}

@test "--detect-checks removes a stale candidate when no stack is detected" {
    TMPD="$(mktemp -d)"
    printf '{"name":"x","scripts":{"test":"true"}}\n' > "$TMPD/package.json"
    bash -c "cd '$TMPD' && bash '$VERIFY' --detect-checks >/dev/null 2>&1"
    [ -f "$TMPD/.agentic/checks.generated.tsv" ]
    rm "$TMPD/package.json"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --detect-checks >/dev/null 2>&1"
    [ "$status" -eq 0 ]
    [ ! -f "$TMPD/.agentic/checks.generated.tsv" ]
    rm -rf "$TMPD"
}

@test "--validate-checks accepts a valid candidate" {
    TMPD="$(mktemp -d)"
    mkdir -p "$TMPD/.agentic"
    printf '%s\n' 'required	ok	.	sh	-c	true' > "$TMPD/.agentic/candidate.tsv"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --validate-checks .agentic/candidate.tsv >/dev/null 2>&1"
    [ "$status" -eq 0 ]
    rm -rf "$TMPD"
}

@test "--validate-checks rejects a malformed candidate" {
    TMPD="$(mktemp -d)"
    mkdir -p "$TMPD/.agentic"
    printf '%s\n' 'bogus-requirement	bad-id	.	sh	-c	true' > "$TMPD/.agentic/candidate.tsv"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --validate-checks .agentic/candidate.tsv >/dev/null 2>&1"
    [ "$status" -eq 1 ]
    rm -rf "$TMPD"
}

@test "--validate-checks rejects duplicate check IDs" {
    TMPD="$(mktemp -d)"
    mkdir -p "$TMPD/.agentic"
    printf '%s\n' \
        'required	test	.	sh	-c	true' \
        'required	test	.	sh	-c	true' \
        > "$TMPD/.agentic/candidate.tsv"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --validate-checks .agentic/candidate.tsv >/dev/null 2>&1"
    [ "$status" -eq 1 ]
    rm -rf "$TMPD"
}

@test "--validate-checks fails when the file does not exist" {
    TMPD="$(mktemp -d)"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --validate-checks .agentic/missing.tsv >/dev/null 2>&1"
    [ "$status" -eq 1 ]
    rm -rf "$TMPD"
}

@test "detection emits the Unix Maven wrapper when present" {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) skip "unix wrapper detection requires a POSIX shell" ;;
    esac
    TMPD="$(mktemp -d)"
    printf '<project></project>\n' > "$TMPD/pom.xml"
    printf '#!/bin/sh\n' > "$TMPD/mvnw" && chmod +x "$TMPD/mvnw"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\t\./mvnw\t'
    rm -rf "$TMPD"
}

@test "detection emits the Unix Gradle/Android wrapper when present" {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) skip "unix wrapper detection requires a POSIX shell" ;;
    esac
    TMPD="$(mktemp -d)"
    printf 'plugins { id "com.android.application" }\n' > "$TMPD/build.gradle"
    printf '#!/bin/sh\n' > "$TMPD/gradlew" && chmod +x "$TMPD/gradlew"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\t\./gradlew\t'
    printf '%s' "$output" | grep -q $'android-unit'
    rm -rf "$TMPD"
}

@test "Bash and PowerShell detection produce equivalent candidates" {
    have pwsh || skip "pwsh not available"
    TMPD="$(mktemp -d)"
    printf '{"name":"x","scripts":{"test":"true"}}\n' > "$TMPD/package.json"
    ( cd "$TMPD" && bash "$VERIFY" --detect-checks >/dev/null 2>&1 )
    bash -c "cd '$TMPD' && pwsh -NoProfile -File '$REPO_ROOT/.agentic/scripts/verify.ps1' -DetectChecks >/dev/null 2>&1"
    # compare the emitted check lines (comments differ between implementations)
    local bash_checks ps_checks
    bash_checks="$(grep -v '^#' "$TMPD/.agentic/checks.generated.tsv" | sort)"
    rm -f "$TMPD/.agentic/checks.generated.tsv"
    bash -c "cd '$TMPD' && pwsh -NoProfile -File '$REPO_ROOT/.agentic/scripts/verify.ps1' -DetectChecks >/dev/null 2>&1"
    ps_checks="$(grep -v '^#' "$TMPD/.agentic/checks.generated.tsv" | sort)"
    [ "$bash_checks" = "$ps_checks" ]
    rm -rf "$TMPD"
}