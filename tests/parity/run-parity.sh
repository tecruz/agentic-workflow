#!/usr/bin/env bash
# run-parity.sh — single cross-language parity check for validators.
#   Compares Bash and PowerShell classifiers on every task fixture,
#   and compares Bash and PowerShell detection contracts on every
#   golden fixture.  Runs once instead of per-OS per-framework.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/tasks"
GOLDEN="$REPO_ROOT/tests/fixtures/golden"
VALIDATE_SH="$REPO_ROOT/.agentic/scripts/validate-task.sh"
VALIDATE_PS="$REPO_ROOT/.agentic/scripts/validate-task.ps1"
VERIFY_SH="$REPO_ROOT/.agentic/scripts/verify.sh"
VERIFY_PS="$REPO_ROOT/.agentic/scripts/verify.ps1"

FAILURES=0

has() { command -v "$1" >/dev/null 2>&1; }

# ── 1. Task fixture parity ──────────────────────────────────────────────
echo "=== Task fixture parity ==="

have pwsh || { echo "SKIP: pwsh not available"; exit 0; }

for f in "$FIXTURES"/*.md; do
    name="$(basename "$f")"
    bash_out="$(bash "$VALIDATE_SH" "$f" 2>&1)" && bash_code=0 || bash_code=$?
    ps_out="$(pwsh -NoProfile -File "$VALIDATE_PS" "$f" 2>&1)" && ps_code=0 || ps_code=$?

    if [ "$bash_code" -ne "$ps_code" ]; then
        echo "  CODE MISMATCH: $name  bash=$bash_code ps=$ps_code"
        FAILURES=$((FAILURES + 1))
    elif [ "$bash_out" != "$ps_out" ]; then
        echo "  OUTPUT MISMATCH: $name"
        echo "    bash: $bash_out"
        echo "    ps:   $ps_out"
        FAILURES=$((FAILURES + 1))
    fi
done

# ── 2. Detection parity ────────────────────────────────────────────────
echo "=== Detection parity ==="

for gold in "$GOLDEN"/*.tsv; do
    name="$(basename "$gold" .tsv)"
    fixture_dir="$REPO_ROOT/tests/fixtures/$name"
    [ -d "$fixture_dir" ] || continue

    # Run Bash detector
    bash_tmp="$(mktemp -d)"
    cp -r "$fixture_dir/." "$bash_tmp/"
    ( cd "$bash_tmp" && bash "$VERIFY_SH" --detect-checks >/dev/null 2>&1 )
    bash_checks="$(grep -v '^#' "$bash_tmp/.agentic/checks.generated.tsv" 2>/dev/null | sort)"
    rm -rf "$bash_tmp"

    # Run PowerShell detector
    ps_tmp="$(mktemp -d)"
    cp -r "$fixture_dir/." "$ps_tmp/"
    ( cd "$ps_tmp" && pwsh -NoProfile -File "$VERIFY_PS" -DetectChecks >/dev/null 2>&1 )
    ps_checks="$(grep -v '^#' "$ps_tmp/.agentic/checks.generated.tsv" 2>/dev/null | sort)"
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
