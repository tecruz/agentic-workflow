#!/usr/bin/env bash
#
# validate-task.sh — structural validator for agentic task files.
#
# Validates only structural facts about a task file's risk profile, evidence
# contract, and completion state. It does not judge whether the prose is
# intellectually sufficient; that belongs to human or behavioral evaluation.
#
# Checks:
#   - a recognized risk profile is declared (prototype | standard | high-assurance)
#   - required sections exist for the declared profile
#   - high-assurance tasks include risk analysis and a recovery plan
#   - acceptance criteria carry identifiers (AC-N)
#   - required evidence entries are present
#   - a task marked complete has no Pending required evidence
#   - required approvals are recorded before completion
#   - a prototype task's handoff states that production readiness was not established
#
# Exit codes:
#   0  VALID
#   1  INVALID
#   2  BLOCKED — referenced evidence or approval is missing
#
# Usage:
#   ./.agentic/scripts/validate-task.sh path/to/TASK-001.md

set -uo pipefail

usage() {
    cat <<'EOF'
Usage: validate-task.sh <task-file>

Exit codes:
  0  VALID
  1  INVALID
  2  BLOCKED — referenced evidence or approval is missing
EOF
}

[ $# -eq 1 ] || { usage >&2; exit 1; }
TASK_FILE="$1"
[ -f "$TASK_FILE" ] || { echo "Error: task file not found: $TASK_FILE" >&2; exit 1; }

lower() { tr '[:upper:]' '[:lower:]'; }

# Normalizes a Markdown heading into a comparable token: lowercase with runs of
# whitespace collapsed to single spaces and leading/trailing whitespace trimmed.
normalize_heading() {
    printf '%s' "$1" | lower | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
}

# The file's `## ` and `### ` headings, normalized into space-delimited tokens.
SECTIONS=""
SUBSECTIONS=""
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        "## "*)
            h="$(normalize_heading "${line#"## "}")"
            SECTIONS="$SECTIONS $h "
            ;;
        "### "*)
            h="$(normalize_heading "${line#"### "}")"
            SUBSECTIONS="$SUBSECTIONS $h "
            ;;
    esac
done < "$TASK_FILE"

has_section() {
    case " $SECTIONS " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

has_subsection() {
    case " $SUBSECTIONS " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# Prints the content between a `## <name>` heading and the next `## ` heading.
section_content() {
    local target="$1" want=0 line h
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "## "*)
                if [ "$want" -eq 1 ]; then return 0; fi
                h="$(normalize_heading "${line#"## "}")"
                [ "$h" = "$target" ] && want=1
                ;;
            *)
                [ "$want" -eq 1 ] && printf '%s\n' "$line"
                ;;
        esac
    done < "$TASK_FILE"
}

# Detect the declared profile from a `Profile: <name>` line.
PROFILE=""
while IFS= read -r line || [ -n "$line" ]; do
    if printf '%s' "$line" | grep -qiE '^[[:space:]]*[Pp]rofile[[:space:]]*:[[:space:]]*[A-Za-z-]+[[:space:]]*$'; then
        PROFILE="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[Pp]rofile[[:space:]]*:[[:space:]]*//; s/[[:space:]]*$//' | lower)"
        break
    fi
done < "$TASK_FILE"

case "$PROFILE" in
    prototype|standard|high-assurance) ;;
    *)
        echo "INVALID: task must declare a recognized risk profile (prototype, standard, or high-assurance)." >&2
        exit 1
        ;;
esac

# Required `## ` sections and `### ` subsections per profile.
REQUIRED_SECTIONS=""
REQUIRED_SUBSECTIONS=""
case "$PROFILE" in
    prototype)
        REQUIRED_SECTIONS=" risk profile profile rationale task goal smoke verification known limitations handoff "
        ;;
    standard)
        REQUIRED_SECTIONS=" risk profile profile rationale acceptance criteria required evidence verification files changed remaining risks "
        REQUIRED_SUBSECTIONS=" baseline final "
        ;;
    high-assurance)
        REQUIRED_SECTIONS=" risk profile profile rationale requirements risk analysis requirement-to-evidence negative-path and boundary tests integration verification recovery plan approval gates independent review acceptance criteria required evidence verification files changed remaining risks "
        REQUIRED_SUBSECTIONS=" baseline final "
        ;;
esac

missing=0
for s in $REQUIRED_SECTIONS; do
    has_section "$s" || { echo "INVALID: missing required section '## $s' for profile '$PROFILE'." >&2; missing=1; }
done
for s in $REQUIRED_SUBSECTIONS; do
    has_subsection "$s" || { echo "INVALID: missing required subsection '### $s' for profile '$PROFILE'." >&2; missing=1; }
done
[ "$missing" -eq 0 ] || exit 1

if [ "$PROFILE" != "prototype" ]; then
    # Acceptance criteria must carry identifiers (AC-N).
    if ! grep -qiE '(^|[[:space:]-])AC-[0-9]+' "$TASK_FILE"; then
        echo "INVALID: acceptance criteria must carry identifiers (e.g. 'AC-1')." >&2
        exit 1
    fi
    # The required evidence table must map at least one criterion to evidence.
    evidence="$(section_content "required evidence")"
    if ! printf '%s\n' "$evidence" | grep -qE '^\|.*AC-[0-9]+.*\|.*\|'; then
        echo "INVALID: required evidence must contain a table mapping each AC-N to evidence." >&2
        exit 1
    fi
fi

if [ "$PROFILE" = "prototype" ]; then
    # A prototype cannot claim production readiness; its handoff must state that
    # production readiness was not established.
    if ! grep -qiE 'Production readiness[[:space:]]*:[[:space:]]*not established' "$TASK_FILE"; then
        echo "INVALID: prototype task handoff must state 'Production readiness: not established'." >&2
        exit 1
    fi
fi

# Detect whether the task is marked complete (Status: done|complete|completed).
COMPLETED=0
while IFS= read -r line || [ -n "$line" ]; do
    if printf '%s' "$line" | grep -qiE '^[-*]*[[:space:]]*\*?[Ss]tatus\*?[[:space:]]*:[[:space:]]*[^|]*\b(done|complete|completed)\b'; then
        COMPLETED=1
        break
    fi
done < "$TASK_FILE"

if [ "$COMPLETED" -eq 1 ]; then
    if grep -qiE '^\|[^|]*\|[^|]*\|[[:space:]]*Pending[[:space:]]*\|' "$TASK_FILE"; then
        echo "BLOCKED: task is marked complete but required evidence remains Pending." >&2
        exit 2
    fi
    # A checked completion must not leave identified approval gates unchecked.
    gates="$(section_content "approval gates")"
    if printf '%s\n' "$gates" | grep -qE '\[[[:space:]]\]'; then
        echo "BLOCKED: task is marked complete but an approval gate is still unchecked." >&2
        exit 2
    fi
    if [ "$PROFILE" = "high-assurance" ]; then
        if ! printf '%s\n' "$gates" | grep -qiE '(approved|granted|\[x\]|signed off)'; then
            echo "BLOCKED: completed high-assurance task lacks recorded approval gates." >&2
            exit 2
        fi
    fi
fi

echo "VALID: profile=$PROFILE"
exit 0