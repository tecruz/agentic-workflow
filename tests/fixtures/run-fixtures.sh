#!/usr/bin/env bash
# run-fixtures.sh — smoke harness for verify.sh.
#   exit-code assertions for the state-model fixtures,
#   --emit-checks detection assertions for the stack fixtures.
# usage: run-fixtures.sh <verify.sh>
set -u
VERIFY="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIX="$ROOT/tests/fixtures"

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
    printf '%-24s expected=%-3s actual=%s  %s\n' "$name" "$expected" "$code" "$( [ "$code" = "$expected" ] && echo OK || echo MISMATCH )"
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
    printf '%-24s emit-checks       %s\n' "$name" "$( [ "$missing" -eq 0 ] && echo OK || echo MISMATCH )"
}

# State-model exit codes (executable availability makes them environment-aware).
expect_code checks-tsv         2
if check_exe checks-tsv-pass; then expect_code checks-tsv-pass 0; else expect_code checks-tsv-pass 2; fi
if check_exe checks-tsv-fail;  then expect_code checks-tsv-fail 1; else expect_code checks-tsv-fail 2; fi
if check_exe checks-tsv-optional; then expect_code checks-tsv-optional 0; else expect_code checks-tsv-optional 2; fi
expect_code unsupported        3
if has npm; then expect_code node-npm 0; else expect_code node-npm 2; fi
if has npm; then expect_code node-npm-fail 1; else expect_code node-npm-fail 2; fi

# Stack detection via --emit-checks (deterministic).
expect_detect node-pnpm           pnpm
expect_detect python-uv           uv
expect_detect python-poetry       poetry
expect_detect dotnet-sln-only     dotnet
expect_detect dotnet-csproj-only  dotnet
expect_detect monorepo            pnpm go
expect_detect unsupported         __none__