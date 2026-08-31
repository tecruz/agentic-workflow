#!/usr/bin/env bash
# run-fixtures.sh — smoke harness for verify.sh.
#   exit-code assertions for the state-model fixtures,
#   --emit-checks detection assertions for the stack fixtures.
# usage: run-fixtures.sh <verify.sh>
set -u
VERIFY="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIX="$ROOT/tests/fixtures"
FAILURES=0

has() { command -v "$1" >/dev/null 2>&1; }

check_exe() {  # check_exe <fixture> — does the checks.tsv executable exist?
    local line exe
    line="$(grep -m1 -v '^#' "$FIX/$1/.agentic/checks.tsv")"
    exe="$(printf '%s' "$line" | cut -f4)"
    if [[ "$exe" == */* ]]; then [ -x "$FIX/$1/$exe" ]; else command -v "$exe" >/dev/null 2>&1; fi
}

expect_code() {  # expect_code <fixture> <expected>
    local name="$1" expected="$2" code
    ( cd "$FIX/$name" && bash "$VERIFY" >/dev/null 2>&1 )
    code=$?
    local status
    if [ "$code" = "$expected" ]; then
        status="OK"
    else
        status="MISMATCH"
        FAILURES=$((FAILURES + 1))
    fi
    printf '%-24s expected=%-3s actual=%s  %s\n' "$name" "$expected" "$code" "$status"
}

expect_detect() {  # expect_detect <fixture> <tool1> [tool2...]
    local name="$1"; shift
    local out missing=0 t
    out="$(cd "$FIX/$name" && bash "$VERIFY" --emit-checks 2>/dev/null)"
    if [ "${1:-}" = "__none__" ]; then
        [ -z "$out" ] || missing=1
    else
        for t in "$@"; do
            printf '%s' "$out" | grep -q "$t" || { echo "  $name: did not emit $t"; missing=1; }
        done
    fi
    local status
    if [ "$missing" -eq 0 ]; then
        status="OK"
    else
        status="MISMATCH"
        FAILURES=$((FAILURES + 1))
    fi
    printf '%-24s emit-checks       %s\n' "$name" "$status"
}

# Exact golden contract: the sorted, comment-free emitted checks must equal the
# checked-in golden file. Catches both missing checks and unexpected extras.
expect_golden() {  # expect_golden <fixture>
    local name="$1" gold actual missing=0 status
    gold="$FIX/golden/$name.tsv"
    actual="$(cd "$FIX/$name" && bash "$VERIFY" --emit-checks 2>/dev/null | grep -v '^$' | sort)"
    if [ ! -f "$gold" ]; then
        echo "  $name: golden file $gold missing"
        missing=1
    elif [ "$actual" != "$(cat "$gold")" ]; then
        echo "  $name: emitted contract differs from golden $gold"
        missing=1
    fi
    if [ "$missing" -eq 0 ]; then
        status="OK"
    else
        status="MISMATCH"
        FAILURES=$((FAILURES + 1))
    fi
    printf '%-24s golden            %s\n' "$name" "$status"
}

# State-model exit codes (executable availability makes them environment-aware).
expect_code checks-tsv         2
if check_exe checks-tsv-pass; then expect_code checks-tsv-pass 0; else expect_code checks-tsv-pass 2; fi
if check_exe checks-tsv-fail;  then expect_code checks-tsv-fail 1; else expect_code checks-tsv-fail 2; fi
if check_exe checks-tsv-optional; then expect_code checks-tsv-optional 0; else expect_code checks-tsv-optional 2; fi
if check_exe checks-tsv-nested-cwd; then expect_code checks-tsv-nested-cwd 0; else expect_code checks-tsv-nested-cwd 2; fi
expect_code unsupported        3
if has npm; then expect_code node-npm 0; else expect_code node-npm 2; fi
if has npm; then expect_code node-npm-fail 1; else expect_code node-npm-fail 2; fi

# Stack detection via --emit-checks (deterministic).
expect_detect node-bun            bun
expect_detect node-pnpm           pnpm
expect_detect python-uv           uv
expect_detect python-poetry       poetry
expect_detect dotnet-sln-only     dotnet
expect_detect dotnet-csproj-only  dotnet
expect_detect rust-cargo          cargo
expect_detect go-mod              go
expect_detect java-maven          mvn
expect_detect java-maven-wrapper  mvnw
expect_detect gradle-wrapper      gradlew
expect_detect android-gradle      gradlew android-unit
expect_detect monorepo            pnpm go
expect_detect polyglot-node-go      node-test go-test
expect_detect nested-monorepo       apps-web-node-test services-api-go-test
expect_detect pnpm-workspace        pnpm packages-foo
expect_detect npm-workspaces        npm packages-a
expect_detect yarn-workspaces-object npm packages-c
expect_detect cargo-workspace       cargo crates-foo
expect_detect maven-modules         mvn module-a
expect_detect gradle-multimodule    gradle app-gradle
expect_detect pnpm-workspace-recursive npm packages-foo
expect_detect unsupported         __none__

# Exact golden contracts for the deterministic fixtures (no platform-dependent
# wrapper selection). This is the same check the Bats/Pester suites run.
for gold in "$FIX"/golden/*.tsv; do
    expect_golden "$(basename "$gold" .tsv)"
done

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES fixture assertion(s) failed" >&2
    exit 1
fi
exit 0