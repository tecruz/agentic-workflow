#!/usr/bin/env bash
# run-parity.sh — cross-language validator parity + golden expectations.
#   For every task fixture, requires the Bash validator and the PowerShell
#   validator to each match the golden expectation (exit code and message) in
#   task-expectations.tsv, then compares the two detection contracts on every
#   golden fixture. Matching the same golden file proves each validator is
#   correct against the expected classification — not merely that the two
#   implementations agree with each other. Runs once instead of per-OS
#   per-framework.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

have() { command -v "$1" >/dev/null 2>&1; }

if ! have pwsh; then
    echo "SKIP: pwsh not available"
    exit 0
fi

FAILURES=0

run_golden() {  # run_golden <lang> <validator>
    if ! bash "$REPO_ROOT/tests/parity/run-golden.sh" "$1" "$2"; then
        FAILURES=$((FAILURES + 1))
    fi
}

# ── 1. Task fixture golden expectations ──────────────────────────────────
echo "=== Task fixture golden expectations (Bash) ==="
run_golden bash "$REPO_ROOT/.agentic/scripts/validate-task.sh"

echo "=== Task fixture golden expectations (PowerShell) ==="
run_golden pwsh "$REPO_ROOT/.agentic/scripts/validate-task.ps1"

# ── 2. Detection parity ────────────────────────────────────────────────
echo "=== Detection parity ==="

GOLDEN="$REPO_ROOT/tests/fixtures/golden"
VERIFY_SH="$REPO_ROOT/.agentic/scripts/verify.sh"
VERIFY_PS="$REPO_ROOT/.agentic/scripts/verify.ps1"

for gold in "$GOLDEN"/*.tsv; do
    name="$(basename "$gold" .tsv)"
    fixture_dir="$REPO_ROOT/tests/fixtures/$name"
    [ -d "$fixture_dir" ] || continue

    # Run Bash detector
    bash_tmp="$(mktemp -d)"
    cp -r "$fixture_dir/." "$bash_tmp/"
    bash_exit=0
    ( cd "$bash_tmp" && bash "$VERIFY_SH" --detect-checks >/dev/null 2>&1 ) || bash_exit=$?
    if [ "$bash_exit" -ne 0 ]; then
        echo "  DETECTION FAILED (bash) for $name : exit $bash_exit" >&2
        FAILURES=$((FAILURES + 1))
        rm -rf "$bash_tmp"
        continue
    fi
    if [ -f "$bash_tmp/.agentic/checks.generated.tsv" ]; then
        bash_checks="$(grep -v '^#' "$bash_tmp/.agentic/checks.generated.tsv" 2>/dev/null | sort)"
    else
        bash_checks=""
    fi
    rm -rf "$bash_tmp"

    # Run PowerShell detector
    ps_tmp="$(mktemp -d)"
    cp -r "$fixture_dir/." "$ps_tmp/"
    ps_exit=0
    ( cd "$ps_tmp" && pwsh -NoProfile -File "$VERIFY_PS" -DetectChecks >/dev/null 2>&1 ) || ps_exit=$?
    if [ "$ps_exit" -ne 0 ]; then
        echo "  DETECTION FAILED (pwsh) for $name : exit $ps_exit" >&2
        FAILURES=$((FAILURES + 1))
        rm -rf "$ps_tmp"
        continue
    fi
    if [ -f "$ps_tmp/.agentic/checks.generated.tsv" ]; then
        ps_checks="$(grep -v '^#' "$ps_tmp/.agentic/checks.generated.tsv" 2>/dev/null | sort)"
    else
        ps_checks=""
    fi
    rm -rf "$ps_tmp"

    if [ "$bash_checks" != "$ps_checks" ]; then
        echo "  DETECTION MISMATCH: $name"
        diff <(printf '%s\n' "$bash_checks") <(printf '%s\n' "$ps_checks") || true
        FAILURES=$((FAILURES + 1))
    fi
done

# ── Result ──────────────────────────────────────────────────────────────
if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES parity assertion(s) failed" >&2
    exit 1
fi
echo "All parity checks passed."
exit 0
