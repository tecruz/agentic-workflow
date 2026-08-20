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

@test "a bun.lock project is detected as bun (modern lockfile)" {
    run bash -c "cd '$FIX/node-bun' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tbun\t'
}

@test "a bun.lockb project is detected as bun (legacy lockfile)" {
    TMPD="$(mktemp -d)"
    printf '{"name":"x","scripts":{"test":"true","lint":"true"}}\n' > "$TMPD/package.json"
    touch "$TMPD/bun.lockb"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tbun\t'
    rm -rf "$TMPD"
}

@test "a pnpm project without a lint script does not emit a lint check" {
    TMPD="$(mktemp -d)"
    printf '{"name":"x","scripts":{"test":"true"}}\n' > "$TMPD/package.json"
    touch "$TMPD/pnpm-lock.yaml"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tpnpm\ttest'
    ! printf '%s' "$output" | grep -q 'node-lint'
    rm -rf "$TMPD"
}

@test "a pnpm project with a lint script emits the lint check" {
    TMPD="$(mktemp -d)"
    printf '{"name":"x","scripts":{"test":"true","lint":"true"}}\n' > "$TMPD/package.json"
    touch "$TMPD/pnpm-lock.yaml"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tpnpm\tlint'
    rm -rf "$TMPD"
}

@test "a Python project without Ruff config does not emit a ruff check" {
    TMPD="$(mktemp -d)"
    printf '[project]\nname = "x"\n' > "$TMPD/pyproject.toml"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tpytest'
    ! printf '%s' "$output" | grep -q 'python-ruff'
    rm -rf "$TMPD"
}

@test "a Python project with Ruff config emits the ruff check" {
    TMPD="$(mktemp -d)"
    printf '[project]\nname = "x"\n[tool.ruff]\n' > "$TMPD/pyproject.toml"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\truff\tcheck'
    rm -rf "$TMPD"
}

@test "Maven detection emits checkstyle only when the pom configures it" {
    TMPD="$(mktemp -d)"
    printf '<project></project>\n' > "$TMPD/pom.xml"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q $'\tmvn\ttest'
    ! printf '%s' "$output" | grep -q 'maven-lint'
    rm -rf "$TMPD"
}

@test "Maven detection emits checkstyle when the pom configures the plugin" {
    TMPD="$(mktemp -d)"
    printf '%s\n' '<project>' '<build><plugins><plugin><groupId>org.apache.maven.plugins</groupId><artifactId>maven-checkstyle-plugin</artifactId></plugin></plugins></build>' '</project>' > "$TMPD/pom.xml"
    run bash -c "cd '$TMPD' && bash '$VERIFY' --emit-checks 2>/dev/null"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q 'maven-lint'
    rm -rf "$TMPD"
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

# The detected-checks contract for a fixture, sorted and comment-free. Used by
# both the golden-output tests and the Bash/PowerShell parity test.
detected_lines() {  # detected_lines <fixture-dir>
    ( cd "$1" && bash "$VERIFY" --emit-checks 2>/dev/null ) | grep -v '^$' | sort
}

@test "detection matches the golden contract for every deterministic fixture" {
    # Golden files are the exact, sorted emitted contract. A detector that
    # starts emitting unexpected checks (or silently drops a known one) fails
    # here even when its fragments still appear in the output.
    local gold f actual expected
    for gold in "$FIX"/golden/*.tsv; do
        f="$(basename "$gold" .tsv)"
        actual="$(detected_lines "$FIX/$f")"
        expected="$(cat "$gold")"
        if [ "$actual" != "$expected" ]; then
            echo "golden mismatch for fixture '$f'"
            diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
            return 1
        fi
    done
}