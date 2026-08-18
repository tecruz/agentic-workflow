#!/usr/bin/env bash
#
# validate-task.sh — structural validator for agentic task files.
#
# Validates only structural facts about a task file's risk profile, evidence
# contract, status, and completion state. It never judges whether the prose is
# intellectually sufficient; that belongs to human or behavioral evaluation.
#
# Content in fenced code blocks, HTML comments, and blockquote lines is not
# authoritative and is ignored. The scanner also rejects duplicate `##`
# headings and duplicate Profile/Status declarations.
#
# Checks (all case-insensitive):
#   - exactly one recognized risk profile: prototype | standard | high-assurance
#   - exactly one recognized status: planned | in-progress | blocked | done
#   - exact required `##` sections per profile, with `### Baseline` and
#     `### Final` scoped inside `## Verification`
#   - acceptance criteria declare unique `AC-N` identifiers, and the required
#     evidence table maps every `AC-N` exactly once with nonempty evidence and
#     a recognized result value
#   - high-assurance tasks map every `R-N` through the requirement-to-evidence
#     matrix and carry nonempty risk analysis, negative-path and boundary
#     tests, integration verification, recovery plan, and independent review
#   - prototypes declare that no production deployment or irreversible
#     operation occurred and that production readiness was not established
#   - approvals use structured records: `- [x] AG-N: Approved by <x> on <date>`
#   - a task marked `done` has no unresolved evidence and no unchecked gates
#
# Result values: passed | satisfied | n/a are resolved; pending | partial |
# blocked | missing | not-run are unresolved and block a completed task. `n/a`
# requires an `n/a` rationale in the evidence description.
#
# Exit codes:
#   0  VALID
#   1  INVALID — structural contract violation
#   2  BLOCKED — completion gate not satisfied (evidence or approval missing)
#
# Usage:
#   ./.agentic/scripts/validate-task.sh [--handoff] path/to/TASK-001.md
#   --handoff  require `Status: done` and enforce the full completion gate.

set -uo pipefail

HANDOFF=0
TASK_FILE=""

usage() {
    cat <<'EOF'
Usage: validate-task.sh [--handoff] <task-file>

Validates the structural evidence contract of an agentic task file.

Options:
  --handoff   Require Status: done and enforce the completion gate.
  -h, --help  Show this help.

Exit codes:
  0  VALID
  1  INVALID
  2  BLOCKED — referenced evidence or approval is missing at completion
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --handoff) HANDOFF=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$TASK_FILE" ]; then
                echo "Error: expected a single task file." >&2
                exit 1
            fi
            TASK_FILE="$1"
            ;;
    esac
    shift
done

if [ -z "$TASK_FILE" ]; then
    usage >&2
    exit 1
fi
if [ ! -f "$TASK_FILE" ]; then
    echo "Error: task file not found: $TASK_FILE" >&2
    exit 1
fi

fail_invalid() { echo "INVALID: $*" >&2; exit 1; }
fail_blocked() { echo "BLOCKED: $*" >&2; exit 2; }

lower() { tr '[:upper:]' '[:lower:]'; }

normalize_heading() {
    printf '%s' "$1" | lower | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}

has_section() {
    local name="$1" s
    [ "${#SECTIONS[@]}" -gt 0 ] || return 1
    for s in "${SECTIONS[@]}"; do
        [ "$s" = "$name" ] && return 0
    done
    return 1
}

has_subsection_under() {
    local name="$1" section="$2" i
    [ "${#SUBSECTIONS[@]}" -gt 0 ] || return 1
    for i in "${!SUBSECTIONS[@]}"; do
        [ "${SUBSECTIONS[$i]}" = "$name" ] && [ "${SUB_SECTION[$i]}" = "$section" ] && return 0
    done
    return 1
}

# section_content <name> — prints the content lines between that `## ` heading
# and the next one (empty when absent or empty).
section_content() {
    local name="$1" i start end j
    [ "${#SECTIONS[@]}" -gt 0 ] || return 1
    for i in "${!SECTIONS[@]}"; do
        if [ "${SECTIONS[$i]}" = "$name" ]; then
            start=$(( SECTION_START[i] + 1 ))
            if [ $(( i + 1 )) -lt "${#SECTIONS[@]}" ]; then
                end=$(( SECTION_START[i + 1] - 1 ))
            else
                end=$(( ${#CONTENT_LINES[@]} - 1 ))
            fi
            for (( j = start; j <= end; j++ )); do
                printf '%s\n' "${CONTENT_LINES[$j]}"
            done
            return 0
        fi
    done
    return 1
}

section_has_content() {
    local content
    content="$(section_content "$1" || true)"
    printf '%s\n' "$content" | grep -q '[^[:space:]]'
}

# collect_ids <content> <pattern> <outvar> — stores the lowercased unique ids
# found in the content into <outvar> and sets the global DUP_IDS when an id
# repeats. <outvar> is written via printf -v so the result survives in the
# caller's shell (command substitution would run this in a subshell).
collect_ids() {
    local content="$1" pattern="$2" outvar="$3" line id seen="" out=""
    DUP_IDS=0
    while IFS= read -r line || [ -n "$line" ]; do
        for id in $(printf '%s\n' "$line" | grep -oiE "$pattern" | lower); do
            [ -n "$id" ] || continue
            case " $seen " in
                *" $id "*) DUP_IDS=1 ;;
                *) seen="$seen $id"; out="$out $id" ;;
            esac
        done
    done <<< "$content"
    printf -v "$outvar" '%s' "$out"
}

RESULT_ALLOWED=" passed satisfied n/a pending partial blocked missing not-run "
RESULT_UNRESOLVED=" pending partial blocked missing not-run "

# validate_table <section> <id-pattern> <label> <outvar> — validates a canonical
# `| id | evidence | result |` table. Stores the lowercased row ids into
# <outvar> and sets the globals TABLE_DUP and HAS_UNRESOLVED. Fails on
# structural problems.
validate_table() {
    local section="$1" idpat="$2" label="$3" outvar="$4" content id ev res lres ids="" seen=""
    content="$(section_content "$section" || true)"
    TABLE_DUP=0
    HAS_UNRESOLVED=0
    while IFS=$'\t' read -r id ev res || [ -n "$id" ]; do
        [ -n "$id" ] || continue
        id="$(printf '%s' "$id" | lower)"
        [ -n "$ev" ] || fail_invalid "$label row '$id' has an empty evidence description."
        [ -n "$res" ] || fail_invalid "$label row '$id' has an empty result."
        lres="$(printf '%s' "$res" | lower)"
        case " $RESULT_ALLOWED " in
            *" $lres "*) ;;
            *) fail_invalid "$label row '$id' has unrecognized result '$res' (allowed: passed, satisfied, n/a, pending, partial, blocked, missing, not-run)." ;;
        esac
        if [ "$lres" = "n/a" ]; then
            printf '%s' "$ev" | grep -qiF 'n/a' \
                || fail_invalid "$label row '$id' uses 'n/a' without an 'n/a' rationale in the evidence description."
        fi
        case " $seen " in
            *" $id "*) TABLE_DUP=1 ;;
            *) seen="$seen $id"; ids="$ids $id" ;;
        esac
        case " $RESULT_UNRESOLVED " in
            *" $lres "*) HAS_UNRESOLVED=1 ;;
        esac
    done < <(printf '%s\n' "$content" | awk -F'|' -v pat="$idpat" '
        NF == 5 {
            c = $2; e = $3; r = $4
            gsub(/^[ \t]+|[ \t]+$/, "", c)
            gsub(/^[ \t]+|[ \t]+$/, "", e)
            gsub(/^[ \t]+|[ \t]+$/, "", r)
            if (c ~ "^" pat "$") print c "\t" e "\t" r
        }
    ')
    printf -v "$outvar" '%s' "$ids"
}

sorted_unique() { printf '%s\n' "$@" | sort -u; }

# ---------------------------------------------------------------------------
# Scan: drop non-authoritative Markdown (fenced code blocks, HTML comments, and
# blockquote lines) and collect headings, declarations, and content.
# ---------------------------------------------------------------------------
CONTENT_LINES=()
SECTIONS=()
SECTION_START=()
SUBSECTIONS=()
SUB_SECTION=()
PROFILE_DECL=0
PROFILE=""
STATUS_DECL=0
STATUS=""
in_fence=0
in_comment=0
cur=""

while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$in_comment" -eq 1 ]; then
        case "$line" in
            *'-->'*) in_comment=0 ;;
        esac
        continue
    fi
    case "$line" in
        *'<!--'*)
            case "$line" in
                *'-->'*) continue ;;
                *) in_comment=1; continue ;;
            esac
            ;;
    esac
    if [ "$in_fence" -eq 1 ]; then
        case "$line" in
            *'```'*|*'~~~'*) in_fence=0 ;;
        esac
        continue
    fi
    case "$line" in
        *'```'*|*'~~~'*) in_fence=1; continue ;;
    esac
    if printf '%s' "$line" | grep -qE '^[[:space:]]*>'; then
        continue
    fi
    case "$line" in
        '### '*)
            h="$(normalize_heading "${line#'### '}")"
            SUBSECTIONS+=("$h")
            SUB_SECTION+=("$cur")
            CONTENT_LINES+=("$line")
            continue
            ;;
        '## '*)
            h="$(normalize_heading "${line#'## '}")"
            SECTIONS+=("$h")
            SECTION_START+=( "${#CONTENT_LINES[@]}" )
            cur="$h"
            CONTENT_LINES+=("$line")
            continue
            ;;
    esac
    if printf '%s' "$line" | grep -qiE '^[[:space:]]*Profile[[:space:]]*:'; then
        PROFILE_DECL=$(( PROFILE_DECL + 1 ))
        if [ -z "$PROFILE" ]; then
            PROFILE="$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*[Pp]rofile[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]*$//' | lower)"
        fi
    fi
    if printf '%s' "$line" | grep -qiE '^[[:space:]]*[-*]*[[:space:]]*\*?[Ss]tatus[[:space:]]*:'; then
        STATUS_DECL=$(( STATUS_DECL + 1 ))
        if [ -z "$STATUS" ]; then
            STATUS="$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*[-*]*[[:space:]]*\*?[Ss]tatus[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]*$//' | lower)"
        fi
    fi
    CONTENT_LINES+=("$line")
done < "$TASK_FILE"

# ---------------------------------------------------------------------------
# Profile and status declarations.
# ---------------------------------------------------------------------------
[ "$PROFILE_DECL" -eq 1 ] || fail_invalid "task must declare exactly one 'Profile:' (found $PROFILE_DECL)."
case "$PROFILE" in
    prototype|standard|high-assurance) ;;
    *) fail_invalid "task must declare a recognized risk profile (prototype, standard, or high-assurance)." ;;
esac
[ "$STATUS_DECL" -eq 1 ] || fail_invalid "task must declare exactly one 'Status:' (found $STATUS_DECL)."
case "$STATUS" in
    planned|in-progress|blocked|done) ;;
    *) fail_invalid "task status must be one of: planned, in-progress, blocked, done (found '$STATUS')." ;;
esac
COMPLETED=0
[ "$STATUS" = "done" ] && COMPLETED=1
if [ "$HANDOFF" -eq 1 ] && [ "$COMPLETED" -eq 0 ]; then
    fail_blocked "handoff requires 'Status: done' (found '$STATUS')."
fi

# ---------------------------------------------------------------------------
# Headings: no duplicates; exact required sections per profile; Baseline and
# Final must live inside Verification.
# ---------------------------------------------------------------------------
seen=""
if [ "${#SECTIONS[@]}" -gt 0 ]; then
    for s in "${SECTIONS[@]}"; do
        case "|$seen|" in
            *"|$s|"*) fail_invalid "duplicate section heading '## $s'." ;;
        esac
        seen="$seen|$s"
    done
fi
seen=""
if [ "${#SUBSECTIONS[@]}" -gt 0 ]; then
    for s in "${SUBSECTIONS[@]}"; do
        case "|$seen|" in
            *"|$s|"*) fail_invalid "duplicate subsection heading '### $s'." ;;
        esac
        seen="$seen|$s"
    done
fi

REQUIRED_SECTIONS=()
REQUIRED_SUBSECTIONS=()
case "$PROFILE" in
    prototype)
        REQUIRED_SECTIONS=( "risk profile" "profile rationale" "task goal" "smoke verification" "known limitations" "handoff" )
        ;;
    standard)
        REQUIRED_SECTIONS=( "risk profile" "profile rationale" "acceptance criteria" "required evidence" "approval gates" "verification" "files changed" "remaining risks" )
        REQUIRED_SUBSECTIONS=( "baseline" "final" )
        ;;
    high-assurance)
        REQUIRED_SECTIONS=( "risk profile" "profile rationale" "requirements" "risk analysis" "requirement-to-evidence" "negative-path and boundary tests" "integration verification" "recovery plan" "approval gates" "independent review" "acceptance criteria" "required evidence" "verification" "files changed" "remaining risks" )
        REQUIRED_SUBSECTIONS=( "baseline" "final" )
        ;;
esac

for s in ${REQUIRED_SECTIONS[@]+"${REQUIRED_SECTIONS[@]}"}; do
    has_section "$s" || fail_invalid "missing required section '## $s' for profile '$PROFILE'."
done
for s in ${REQUIRED_SUBSECTIONS[@]+"${REQUIRED_SUBSECTIONS[@]}"}; do
    has_subsection_under "$s" "verification" \
        || fail_invalid "missing '### $s' subsection under '## Verification' for profile '$PROFILE'."
done

# ---------------------------------------------------------------------------
# Prototype contract.
# ---------------------------------------------------------------------------
if [ "$PROFILE" = "prototype" ]; then
    handoff="$(section_content "handoff" || true)"
    printf '%s\n' "$handoff" | grep -qiE 'production[[:space:]]+readiness[[:space:]]*:[[:space:]]*not[[:space:]]+established' \
        || fail_invalid "prototype handoff must state 'Production readiness: not established'."
    printf '%s\n' "$handoff" | grep -qiE 'no[[:space:]]+production[[:space:]]+deployment[[:space:]]+or[[:space:]]+irreversible[[:space:]]+operation[[:space:]]*:[[:space:]]*confirmed' \
        || fail_invalid "prototype handoff must declare 'No production deployment or irreversible operation: confirmed'."
fi

# ---------------------------------------------------------------------------
# Standard and high-assurance evidence contracts.
# ---------------------------------------------------------------------------
if [ "$PROFILE" != "prototype" ]; then
    ac_content="$(section_content "acceptance criteria" || true)"
    ac_ids=""
    collect_ids "$ac_content" 'AC-[0-9]+' ac_ids
    [ -n "$ac_ids" ] || fail_invalid "acceptance criteria must declare at least one 'AC-N' identifier."
    [ "$DUP_IDS" -eq 0 ] || fail_invalid "acceptance criteria declare duplicate 'AC-N' identifiers."

    ev_ids=""
    validate_table "required evidence" 'AC-[0-9]+' "required evidence" ev_ids
    [ -n "$ev_ids" ] || fail_invalid "required evidence must map at least one 'AC-N' to evidence."
    [ "$TABLE_DUP" -eq 0 ] || fail_invalid "required evidence maps a criterion more than once."
    if [ "$(sorted_unique "$ac_ids")" != "$(sorted_unique "$ev_ids")" ]; then
        fail_invalid "acceptance criteria and required evidence must list exactly the same 'AC-N' identifiers."
    fi
    if [ "$COMPLETED" -eq 1 ] && [ "$HAS_UNRESOLVED" -eq 1 ]; then
        fail_blocked "task is marked complete but required evidence remains unresolved (pending, partial, blocked, missing, or not-run)."
    fi

    if [ "$PROFILE" = "high-assurance" ]; then
        req_content="$(section_content "requirements" || true)"
        r_ids=""
        collect_ids "$req_content" 'R-[0-9]+' r_ids
        [ -n "$r_ids" ] || fail_invalid "high-assurance requirements must declare at least one 'R-N' identifier."
        [ "$DUP_IDS" -eq 0 ] || fail_invalid "high-assurance requirements declare duplicate 'R-N' identifiers."

        m_ids=""
        validate_table "requirement-to-evidence" 'R-[0-9]+' "requirement-to-evidence" m_ids
        [ -n "$m_ids" ] || fail_invalid "the requirement-to-evidence matrix must map at least one 'R-N' to evidence."
        [ "$TABLE_DUP" -eq 0 ] || fail_invalid "the requirement-to-evidence matrix maps a requirement more than once."
        if [ "$(sorted_unique "$r_ids")" != "$(sorted_unique "$m_ids")" ]; then
            fail_invalid "requirements and the requirement-to-evidence matrix must list exactly the same 'R-N' identifiers."
        fi
        if [ "$COMPLETED" -eq 1 ] && [ "$HAS_UNRESOLVED" -eq 1 ]; then
            fail_blocked "task is marked complete but the requirement-to-evidence matrix has unresolved rows."
        fi

        for s in "risk analysis" "negative-path and boundary tests" "integration verification" "recovery plan" "independent review"; do
            section_has_content "$s" || fail_invalid "high-assurance section '## $s' must have content."
        done
    fi
fi

# ---------------------------------------------------------------------------
# Approval gates: structured records only; no prose-based approval inference.
# ---------------------------------------------------------------------------
if [ "$PROFILE" != "prototype" ]; then
    gates="$(section_content "approval gates" || true)"
    has_none=0
    gate_count=0
    checked=0
    unchecked=0
    gate_seen=""
    while IFS= read -r gl || [ -n "$gl" ]; do
        if printf '%s' "$gl" | grep -qiE 'none[[:space:]]+identified'; then
            has_none=1
        fi
        if printf '%s' "$gl" | grep -qE '^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*AG-[0-9]+[[:space:]]*:'; then
            gate_count=$(( gate_count + 1 ))
            gid="$(printf '%s\n' "$gl" | sed -nE 's/^[[:space:]]*-[[:space:]]*\[([ xX])\][[:space:]]*(AG-[0-9]+)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\2/p' | lower)"
            gbox="$(printf '%s\n' "$gl" | sed -nE 's/^[[:space:]]*-[[:space:]]*\[([ xX])\][[:space:]]*(AG-[0-9]+)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\1/p')"
            gdet="$(printf '%s\n' "$gl" | sed -nE 's/^[[:space:]]*-[[:space:]]*\[([ xX])\][[:space:]]*(AG-[0-9]+)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\3/p' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
            case " $gate_seen " in
                *" $gid "*) fail_invalid "approval gate '$gid' is declared more than once." ;;
            esac
            gate_seen="$gate_seen $gid"
            case "$gbox" in
                [xX]) checked=$(( checked + 1 )) ;;
                *) unchecked=$(( unchecked + 1 )) ;;
            esac
            printf '%s' "$gdet" | grep -qiE '^approved[[:space:]]+by[[:space:]]+.+[[:space:]]+on[[:space:]]+[[:alnum:]@./_-]+[[:space:]]*$' \
                || fail_invalid "approval gate '$gid' must be in the form '- [x] AG-N: Approved by <approver> on <date>'."
        fi
    done <<< "$gates"

    if [ "$has_none" -eq 1 ] && [ "$gate_count" -gt 0 ]; then
        fail_invalid "approval gates cannot both declare 'None identified' and structured gates."
    fi
    if [ "$PROFILE" = "high-assurance" ]; then
        [ "$has_none" -eq 0 ] || fail_invalid "high-assurance tasks require explicit approval gates ('None identified' is not permitted)."
        [ "$gate_count" -gt 0 ] || fail_invalid "high-assurance tasks must declare at least one approval gate 'AG-N'."
    else
        [ "$has_none" -eq 1 ] || [ "$gate_count" -gt 0 ] \
            || fail_invalid "approval gates must declare structured 'AG-N' records or 'None identified'."
    fi
    if [ "$COMPLETED" -eq 1 ] && [ "$unchecked" -gt 0 ]; then
        fail_blocked "task is marked complete but an approval gate remains unchecked."
    fi
fi

echo "VALID: profile=$PROFILE"
exit 0
