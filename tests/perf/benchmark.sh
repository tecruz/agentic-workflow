#!/usr/bin/env bash
#
# benchmark.sh — measures verifier overhead on a synthetic large checks.tsv
# contract (default 300 checks, all no-ops). Reports contract-validation and
# full-run timings for the Bash verifier.
#
# Dev-only quality gate: this script is NOT part of .agentic/checks.tsv.
# Usage: tests/perf/benchmark.sh [N]

set -uo pipefail

N="${1:-300}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Millisecond clock: EPOCHREALTIME (bash 5+) preferred, python3 fallback.
now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local _sec="${EPOCHREALTIME%%.*}" _frac="${EPOCHREALTIME#*.}000"
        printf '%s%s' "$_sec" "${_frac:0:3}"
        return
    fi
    python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || printf '%d' "$((SECONDS * 1000))"
}

mkdir -p "$WORK/.agentic"
i=1
while [ "$i" -le "$N" ]; do
    printf 'required\tperf-%04d\t.\ttrue\n' "$i" >> "$WORK/.agentic/checks.tsv"
    i=$((i+1))
done
cp "$ROOT/.agentic/scripts/verify.sh" "$WORK/verify.sh"

t0="$(now_ms)"
(cd "$WORK" && bash verify.sh --validate-checks .agentic/checks.tsv >/dev/null) || exit 1
t1="$(now_ms)"
(cd "$WORK" && bash verify.sh >/dev/null 2>&1)
t2="$(now_ms)"
(cd "$WORK" && bash verify.sh --format json >/dev/null 2>&1)
t3="$(now_ms)"

printf 'checks\tvalidate_ms\tfull_text_ms\tfull_json_ms\n'
printf '%s\t%s\t%s\t%s\n' "$N" "$((t1 - t0))" "$((t2 - t1))" "$((t3 - t2))"
