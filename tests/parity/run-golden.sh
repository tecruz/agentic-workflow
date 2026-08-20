#!/usr/bin/env bash
# run-golden.sh <lang> <validator> — task-fixture golden check for one validator.
#   <lang> is 'bash' or 'pwsh'. Runs <validator> over every task fixture and
#   requires its exit code and combined output to match the golden expectations
#   in task-expectations.tsv. Because both the Bash and PowerShell validators
#   are checked against the same golden file, matching the file also implies
#   the two implementations agree with each other on every task fixture.
#   This is the compact PR-gate verification: it proves each validator classifies
#   each fixture correctly, not merely that the two implementations agree.
#   usage: run-golden.sh <bash|pwsh> <validator-path>
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/tasks"
GOLDEN="$REPO_ROOT/tests/parity/task-expectations.tsv"

if [ "$#" -ne 2 ]; then
    echo "usage: run-golden.sh <bash|pwsh> <validator-path>" >&2
    exit 2
fi

LANG="$1"
VALIDATOR="$2"

case "$LANG" in
    bash|pwsh) ;;
    *) echo "run-golden.sh: unknown language '$LANG' (expected bash or pwsh)" >&2; exit 2 ;;
esac

[ -f "$VALIDATOR" ] || { echo "run-golden.sh: validator not found: $VALIDATOR" >&2; exit 2; }
[ -f "$GOLDEN" ] || { echo "run-golden.sh: golden expectations not found: $GOLDEN" >&2; exit 2; }

FAILURES=0
seen=""

run_one() {  # run_one <fixture> — sets globals code/out for the validator
    local f="$1"
    # stdin is redirected from /dev/null so the validator never inherits this
    # loop's redirected stdin (the golden file). PowerShell on Linux segfaults
    # (exit 139) when its stdin is a regular file; bash is unaffected but the
    # redirect is harmless and keeps both paths consistent.
    if [ "$LANG" = "bash" ]; then
        out="$(bash "$VALIDATOR" "$f" < /dev/null 2>&1)" && code=0 || code=$?
    else
        out="$(pwsh -NoProfile -File "$VALIDATOR" "$f" < /dev/null 2>&1)" && code=0 || code=$?
    fi
}

while IFS=$'\t' read -r name expected_code expected_msg || [ -n "$name" ]; do
    printf '%s' "$name" | grep -qE '^[[:space:]]*(#|$)' && continue
    # A fixture must have exactly one golden row: reject duplicate names so a
    # stale or conflicting expectation cannot hide behind an earlier one.
    case " $seen " in
        *" $name "*)
            echo "  DUPLICATE GOLDEN ROW: $name"
            FAILURES=$((FAILURES + 1))
            continue
            ;;
        *) seen="$seen $name" ;;
    esac
    # Exit codes are limited to the validator's contract: 0 VALID, 1 INVALID,
    # 2 BLOCKED. Anything else is a manifest error, not a fixture expectation.
    case "$expected_code" in
        0|1|2) ;;
        *)
            echo "  INVALID GOLDEN EXIT CODE: $name expected=$expected_code"
            FAILURES=$((FAILURES + 1))
            continue
            ;;
    esac
    expected_msg="${expected_msg%$'\r'}"
    if [ ! -f "$FIXTURES/$name" ]; then
        echo "  MISSING FIXTURE: $name"
        FAILURES=$((FAILURES + 1))
        continue
    fi
    run_one "$FIXTURES/$name"
    if [ "$code" -ne "$expected_code" ]; then
        echo "  CODE MISMATCH ($LANG): $name  expected=$expected_code got=$code"
        FAILURES=$((FAILURES + 1))
    elif [ "$out" != "$expected_msg" ]; then
        echo "  MESSAGE MISMATCH ($LANG): $name"
        echo "    expected: $expected_msg"
        echo "    got:      $out"
        FAILURES=$((FAILURES + 1))
    fi
done < "$GOLDEN"

# Reverse completeness check: every task fixture must be listed exactly once in
# the golden manifest. A fixture without a golden row escapes the contract, and
# a golden row for a nonexistent fixture is already reported above.
golden_names="$(awk -F '\t' '!/^[[:space:]]*(#|$)/ && NF >= 1 { print $1 }' "$GOLDEN" | sort)"
fixture_names="$(cd "$FIXTURES" && for f in *.md; do [ -f "$f" ] && printf '%s\n' "$f"; done | sort)"
diff_lines="$(comm -3 <(printf '%s\n' "$golden_names") <(printf '%s\n' "$fixture_names"))"
if [ -n "$diff_lines" ]; then
    echo "  GOLDEN/FIXTURE MISMATCH (fixtures without a golden row, or golden rows without a fixture):"
    printf '%s\n' "$diff_lines" | sed 's/^/    /'
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES golden assertion(s) failed for the $LANG validator" >&2
    exit 1
fi
echo "All golden expectations matched for the $LANG validator."
exit 0
