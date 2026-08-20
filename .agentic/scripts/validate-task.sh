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
#     evidence table maps every `AC-N` exactly once with meaningful evidence
#     (at least one letter or number after trimming Markdown syntax and
#     recognized placeholders) and a recognized result value
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

# collect_canonical_ids <content> <lower-id-pattern> <outvar> — gathers
# identifiers only from canonical list rows of the form
# '- <id>: <description>' (case-insensitive) and sets the globals MULTI_IDS
# (a row declares more than one identifier) and BAD_FORM (a list row with an
# identifier that is not canonical). Identifiers mentioned in prose are not
# collected, so criteria must be declared as canonical rows.
collect_canonical_ids() {
    local content="$1" idpat="$2" outvar="$3" line lowline id n seen="" out=""
    MULTI_IDS=0
    BAD_FORM=0
    DUP_IDS=0
    UNNUMBERED=0
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s' "$line" | grep -qE '^[[:space:]]*[-*+][[:space:]]+' || continue
        lowline="$(printf '%s' "$line" | lower)"
        n="$(printf '%s' "$lowline" | grep -oE "$idpat" | wc -l | tr -d '[:space:]')"
        [ "$n" -gt 1 ] && { MULTI_IDS=1; continue; }
        [ "$n" -eq 1 ] || { UNNUMBERED=1; continue; }
        printf '%s' "$lowline" | grep -qE "^[[:space:]]*[-*+][[:space:]]*$idpat[[:space:]]*:[[:space:]]*[^[:space:]]" \
            || { BAD_FORM=1; continue; }
        id="$(printf '%s' "$lowline" | grep -oE "$idpat" | head -1)"
        case " $seen " in
            *" $id "*) DUP_IDS=1 ;;
            *) seen="$seen $id"; out="$out $id" ;;
        esac
    done <<< "$content"
    printf -v "$outvar" '%s' "$out"
}

# check_canonical_section <content> <idpat> <label> <entry-form> — every line in
# a canonical-only section that is a candidate entry or mentions an identifier
# token must be a canonical list item '- <ID>: <description>'. A candidate entry
# is a line that starts a list item (bullet, numbered, or bare '<ID>:'
# declaration); those are exactly the lines that could declare a criterion or
# requirement. Any line that contains an identifier token anywhere (for example
# 'AC-2' embedded in a paragraph) must also be a canonical entry, so a prose
# mention cannot declare an extra criterion or requirement that escapes the
# evidence contract. Bare, numbered, and prose-declared identifiers are rejected
# rather than skipped. Continuation lines and notes paragraphs that contain no
# identifier token are allowed: they belong to the preceding canonical item.
check_canonical_section() {
    local content="$1" idpat="$2" label="$3" entryform="$4" line lowline idbound
    # An identifier token is delimited by non-alphanumerics so that a prose
    # fragment such as 'R-2D2' is not mistaken for a requirement identifier.
    idbound="(^|[^a-z0-9])${idpat}($|[^a-z0-9])"
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s' "$line" | grep -q '[^[:space:]]' || continue
        lowline="$(printf '%s' "$line" | lower)"
        if printf '%s' "$lowline" | grep -qE "$idbound"; then
            printf '%s' "$lowline" | grep -qE "^[-*+][[:space:]]*$idpat[[:space:]]*:[[:space:]]*[^[:space:]]" \
                || fail_invalid "$label must contain only canonical '$entryform' list entries; identifiers may not appear in prose or non-canonical lines."
        fi
        printf '%s' "$lowline" | grep -qE '^([-*+][[:space:]]*|[0-9]+[.)][[:space:]]+|(ac|r)-[0-9]+[[:space:]]*:)' || continue
        printf '%s' "$lowline" | grep -qE "^[-*+][[:space:]]*$idpat[[:space:]]*:[[:space:]]*[^[:space:]]" \
            || fail_invalid "$label must contain only canonical '$entryform' list entries; identifiers may not appear in prose or non-canonical lines."
    done <<< "$content"
}

RESULT_ALLOWED=" passed satisfied n/a pending partial blocked missing not-run "
RESULT_UNRESOLVED=" pending partial blocked missing not-run "

# table_row_parts <trimmed-line> — splits a Markdown table row into its trimmed
# cells (leading/trailing pipe stripped, cells split on '|') and sets the
# globals CELLS (array) and CELL_COUNT.
table_row_parts() {
    local row="$1" body i
    CELLS=()
    body="$(printf '%s' "$row" | sed -E 's/^[[:space:]]*\|//; s/\|[[:space:]]*$//')"
    if [ -z "$body" ]; then
        CELL_COUNT=0
        return
    fi
    IFS='|' read -r -a CELLS <<< "$body"
    for i in "${!CELLS[@]}"; do
        CELLS[$i]="$(printf '%s' "${CELLS[$i]}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    done
    CELL_COUNT="${#CELLS[@]}"
}

# table_row_is_separator — returns 0 when every non-empty cell of CELLS is a
# Markdown `---` (or `:---:` etc.) separator and at least one cell is non-empty.
table_row_is_separator() {
    local c
    [ "$CELL_COUNT" -eq 3 ] || return 1
    for c in "${CELLS[@]}"; do
        printf '%s' "$c" | grep -qE '^:?-{3,}:?$' || return 1
    done
    return 0
}

# validate_table <section> <id-pattern> <label> <header-label> <outvar> —
# validates a canonical `| <header-label> | Evidence | Result |` table: an
# exact header row, one separator row, then canonical data rows with exactly
# three meaningful cells. Every table-shaped row is structurally authoritative;
# malformed rows (extra or missing columns, unknown or malformed ids, a header
# whose labels do not match the expected schema, rows before the header, a
# second header/separator, and pipe-delimited lines without a leading pipe)
# are rejected rather than silently skipped. Stores the lowercased row ids
# into <outvar> and sets the globals TABLE_DUP and HAS_UNRESOLVED. Fails on
# structural problems.
validate_table() {
    local section="$1" idpat="$2" label="$3" header_label="$4" outvar="$5"
    local content line trimmed id ev res lres ev_low rationale ids="" seen="" lp hl h1 h2 h3
    local stage=0
    content="$(section_content "$section" || true)"
    lp="$(printf '%s' "$idpat" | lower)"
    hl="$(printf '%s' "$header_label" | lower)"
    idprefix="$(printf '%s' "$idpat" | sed -E 's/\[.*//' | lower)"
    TABLE_DUP=0
    HAS_UNRESOLVED=0
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s' "$line" | grep -q '[^[:space:]]' || continue
        trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        if ! printf '%s' "$trimmed" | grep -q '^|'; then
            # A pipe-delimited line that omitted its leading pipe is a table
            # row; reject it rather than silently treating it as prose.
            printf '%s' "$trimmed" | grep -qE '[^|]+\|[^|]+\|[^|]+' \
                && fail_invalid "$label table row '$trimmed' must begin with a leading pipe."
            # Also reject a row that opens with a known identifier or the
            # expected header label even when its other cells are empty or
            # missing, so a malformed duplicate cannot hide an unresolved row.
            printf '%s' "$trimmed" | grep -qiE "^($idprefix|$hl)[^|]*\|" \
                && fail_invalid "$label table row '$trimmed' must begin with a leading pipe."
            continue
        fi
        table_row_parts "$trimmed"
        id="${CELLS[0]:-}"
        if [ "$stage" -eq 0 ]; then
            if table_row_is_separator; then
                fail_invalid "$label table must have a header row before its separator."
            fi
            if printf '%s' "$id" | lower | grep -qE "^$lp\$"; then
                fail_invalid "$label table has a data row before its header."
            fi
            [ "$CELL_COUNT" -eq 3 ] || fail_invalid "$label table row has $CELL_COUNT columns (expected 3)."
            h1="$(printf '%s' "${CELLS[0]:-}" | lower)"
            h2="$(printf '%s' "${CELLS[1]:-}" | lower)"
            h3="$(printf '%s' "${CELLS[2]:-}" | lower)"
            [ "$h1" = "$hl" ] && [ "$h2" = "evidence" ] && [ "$h3" = "result" ] \
                || fail_invalid "$label table header must be '| $header_label | Evidence | Result |'."
            stage=1
            continue
        fi
        if [ "$stage" -eq 1 ]; then
            table_row_is_separator || fail_invalid "$label table is missing its separator row."
            [ "$CELL_COUNT" -eq 3 ] || fail_invalid "$label table separator has $CELL_COUNT columns (expected 3)."
            stage=2
            continue
        fi
        # Canonical data row.
        if table_row_is_separator; then
            fail_invalid "$label table must not contain a second header or separator."
        fi
        [ "$CELL_COUNT" -eq 3 ] || fail_invalid "$label table row has $CELL_COUNT columns (expected 3)."
        ev="${CELLS[1]:-}"
        res="${CELLS[2]:-}"
        printf '%s' "$id" | lower | grep -qE "^$lp\$" \
            || fail_invalid "$label row '$id' has an unrecognized identifier."
        id="$(printf '%s' "$id" | lower)"
        [ -n "$ev" ] || fail_invalid "$label row '$id' has an empty evidence description."
        if [ "$COMPLETED" -eq 1 ] && [ "$(content_class "$ev")" = "placeholder" ]; then
            fail_blocked "$label row '$id' has a placeholder evidence description."
        fi
        [ -n "$res" ] || fail_invalid "$label row '$id' has an empty result."
        lres="$(printf '%s' "$res" | lower)"
        case " $RESULT_ALLOWED " in
            *" $lres "*) ;;
            *) fail_invalid "$label row '$id' has unrecognized result '$res' (allowed: passed, satisfied, n/a, pending, partial, blocked, missing, not-run)." ;;
        esac
        if [ "$lres" = "n/a" ]; then
            # A resolved 'n/a' must carry a structured 'N/A: <reason>'
            # rationale with meaningful text after the colon.
            ev_low="$(printf '%s' "$ev" | lower)"
            printf '%s' "$ev_low" | grep -qE '^[[:space:]]*n/a[[:space:]]*:[[:space:]]*[^[:space:]]' \
                || fail_invalid "$label row '$id' uses 'n/a' without a substantive 'N/A: <reason>' rationale."
            rationale="$(printf '%s' "$ev_low" | sed -nE 's#^[[:space:]]*n/a[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$#\1#p')"
            [ "$(content_class "$rationale")" = "content" ] \
                || fail_invalid "$label row '$id' uses 'n/a' with a placeholder rationale."
        fi
        case " $seen " in
            *" $id "*) TABLE_DUP=1 ;;
            *) seen="$seen $id"; ids="$ids $id" ;;
        esac
        case " $RESULT_UNRESOLVED " in
            *" $lres "*) HAS_UNRESOLVED=1 ;;
        esac
    done <<< "$content"
    printf -v "$outvar" '%s' "$ids"
}

# sorted_unique <ids...> — prints the unique ids in sorted order regardless of
# input order. Each argument may itself be a space-separated list, so a single
# space-separated id string and a real array of ids both compare order-freely.
sorted_unique() {
    printf '%s\n' "$@" | tr '[:space:]' '\n' | sed '/^$/d' | sort -u
}

# validate_date <YYYY-MM-DD> — returns 0 when the value is a real calendar date.
validate_date() {
    local d="$1" y m day rest leap max
    printf '%s' "$d" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || return 1
    y="${d%%-*}"; rest="${d#*-}"; m="${rest%%-*}"; day="${rest#*-}"
    y=$((10#$y)); m=$((10#$m)); day=$((10#$day))
    [ "$y" -ge 1 ] || return 1
    [ "$m" -ge 1 ] && [ "$m" -le 12 ] || return 1
    [ "$day" -ge 1 ] || return 1
    leap=0
    if [ $(( y % 4 )) -eq 0 ] && { [ $(( y % 100 )) -ne 0 ] || [ $(( y % 400 )) -eq 0 ]; }; then
        leap=1
    fi
    case "$m" in
        1|3|5|7|8|10|12) max=31 ;;
        4|6|9|11) max=30 ;;
        2) max=$(( 28 + leap )) ;;
    esac
    [ "$day" -le "$max" ] || return 1
    return 0
}

# table_row_has_content <row> — returns 0 when at least one data cell is real
# (non-placeholder) content. Cells that are bracket/angle markers, bare dates,
# TBD / TODO / Pending, or blank do not count, so a table of template
# placeholders is not treated as real evidence.
table_row_has_content() {
    local line="$1" oldifs cell
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*\|//; s/\|[[:space:]]*$//')"
    oldifs="$IFS"
    IFS='|'
    for cell in $line; do
        cell="$(printf '%s' "$cell" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        if [ -n "$cell" ] && [ "$(content_class "$cell")" = "content" ]; then
            IFS="$oldifs"
            return 0
        fi
    done
    IFS="$oldifs"
    return 1
}

# has_meaningful_char <text> — returns 0 when the text contains at least one
# meaningful character: a Unicode category Letter or Number (any script), which
# includes ASCII letters and digits. Symbol-only values ('_', '()', '+++',
# '^^^'), Unicode punctuation ('—', '…'), emoji, and invisible format
# characters (zero-width space) are not Letters or Numbers and carry no real
# content. Deterministic parity with the PowerShell [\p{L}\p{N}] check: the
# ASCII fast path avoids spawning perl for the common case, and perl performs
# the Unicode-category test because neither GNU nor BSD grep exposes Unicode
# categories without PCRE support.
has_meaningful_char() {
    printf '%s' "$1" | grep -qE '[A-Za-z0-9]' && return 0
    [ -n "$1" ] || return 1
    # The Unicode-category test needs perl; if it is missing, the environment
    # cannot classify non-ASCII evidence. Fail with a clear error instead of
    # silently rejecting content the PowerShell validator would accept.
    command -v perl >/dev/null 2>&1 \
        || fail_invalid "perl is required to classify non-ASCII content; install perl or keep evidence ASCII-only."
    printf '%s' "$1" | perl -CS -ne 'exit 0 if /[\p{L}\p{N}]/; exit 1' 2>/dev/null
}

# text_is_placeholder <text> — returns 0 when <text> is template placeholder
# content: an exact placeholder token (optionally punctuated, e.g. 'TBD.' or
# 'None identified.'), a placeholder label ('<label>: TBD'), a
# placeholder-prefixed instruction ('TODO: add tests', 'TBD test reference'),
# a whole bracketed or angle-bracket marker, a bare date, or the
# profile-rationale instruction. Real sentences are not placeholders.
text_is_placeholder() {
    local t="$1" n prev
    n="$(printf '%s' "$t" | sed -E 's/^[[:space:]]*[-*+][[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]*[.!?;:,-]+$//' | lower)"
    # Stripping trailing punctuation may leave an empty value (e.g. a bare '.');
    # punctuation-only text carries no real content and is a placeholder.
    [ -n "$n" ] || return 0
    # Strip common whole-value Markdown formatting wrappers before placeholder
    # classification so that '**TBD**', '`Pending`', '~~TODO~~', 'TBD_',
    # 'TBD()', and similar wrappers are recognized as placeholders rather than
    # real content.
    prev=""
    while [ "$n" != "$prev" ]; do
        prev="$n"
        n="$(printf '%s' "$n" | sed -E 's/^\*\*([^*]+)\*\*$/\1/; s/^\*([^*]+)\*$/\1/; s/^__([^_]+)__$/\1/; s/^_([^_]+)_$/\1/; s/^`([^`]+)`$/\1/; s/^~~([^~]+)~~$/\1/')"
        # Wrapper symbols may trail a marker or token ('TBD_', 'TBD()',
        # '[label]_'); strip them so the underlying value can be classified.
        n="$(printf '%s' "$n" | sed -E 's/[[:space:]]*[_()]+$//; s/^[_()]+//')"
    done
    # After unwrapping, strip trailing punctuation again.
    n="$(printf '%s' "$n" | sed -E 's/[[:space:]]+$//; s/[[:space:]]*[.!?;:,-]+$//')"
    [ -n "$n" ] || return 0
    # A whole bracketed or angle-bracket marker (optionally with trailing
    # wrapper symbols) is a placeholder; brackets are not unwrapped to prose.
    printf '%s' "$n" | grep -qE '^\[[^]]+\][[:space:]_.()*~-]*$' && return 0
    printf '%s' "$n" | grep -qE '^<[^>]+>[[:space:]_.()*~-]*$' && return 0
    # Symbol-only text is also a placeholder even though it is not one of the
    # recognized placeholder tokens.
    has_meaningful_char "$n" || return 0
    case "$n" in
        tbd|todo|pending|none\ identified|none\ provided) return 0 ;;
        tbd:*|todo:*|pending:*|none\ identified:*|none\ provided:*) return 0 ;;
        'tbd '*|'todo '*|'pending '*) return 0 ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;;
    esac
    if printf '%s' "$n" | grep -qE '^[^:]+:[[:space:]]*(tbd|todo|pending|none[[:space:]]+identified|none[[:space:]]+provided)$'; then
        return 0
    fi
    case "$(printf '%s' "$n" | tr -cd '[:alnum:]')" in
        explainwhythislevelappliesandidentifyanyescalationsignals) return 0 ;;
    esac
    return 1
}

# content_class <content> — classifies authoritative content lines as
# "content" (real evidence), "placeholder" (lines exist but none are real),
# or "empty" (no lines at all). Headings, table separators, blank bullets,
# and placeholder text (see text_is_placeholder) do not count as content.
# A table counts only once a data row with at least one real cell follows
# its header.
content_class() {
    local line text table_header_seen saw_lines
    table_header_seen=0
    saw_lines=0
    while IFS= read -r line || [ -n "$line" ]; do
        if printf '%s' "$line" | grep -q '[^[:space:]]'; then
            :
        else
            # A blank line ends any in-progress table; reset so the header of a
            # following table is not mistaken for the prior table's data row.
            table_header_seen=0
            continue
        fi
        printf '%s' "$line" | grep -qE '^[[:space:]]*#' && continue
        case "$line" in
            *'---'*) continue ;;
        esac
        saw_lines=1
        if printf '%s' "$line" | grep -qE '^[[:space:]]*\|.*\|.*\|[[:space:]]*$'; then
            if [ "$table_header_seen" -eq 1 ]; then
                table_row_has_content "$line" && { echo content; return 0; }
                continue
            fi
            table_header_seen=1
            continue
        fi
        # A non-table line ends any in-progress table.
        table_header_seen=0
        text="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[-*+][[:space:]]+//; s/[[:space:]]+$//')"
        [ -n "$text" ] || continue
        text_is_placeholder "$text" && continue
        echo content
        return 0
    done <<< "$1"
    if [ "$saw_lines" -eq 0 ]; then
        echo empty
    else
        echo placeholder
    fi
    return 1
}

content_has_real_text() {
    [ "$(content_class "$1")" = "content" ]
}

# section_has_real_content <name> — returns 0 when the section has at least one
# authoritative content line that is not a heading, a table separator, an empty
# bullet, or a placeholder such as TBD / TODO / Pending / None provided.
section_has_real_content() {
    content_has_real_text "$(section_content "$1" || true)"
}

# subsection_content <name> <section> — prints the content lines between that
# `### ` heading and the next heading (empty when absent or empty).
subsection_content() {
    local name="$1" section="$2" i j k n
    [ "${#SUBSECTIONS[@]}" -gt 0 ] || return 1
    for i in "${!SUBSECTIONS[@]}"; do
        if [ "${SUBSECTIONS[$i]}" = "$name" ] && [ "${SUB_SECTION[$i]}" = "$section" ]; then
            j=$(( SUB_SECTION_START[i] + 1 ))
            n=${#CONTENT_LINES[@]}
            k=$j
            while [ $k -lt $n ]; do
                case "${CONTENT_LINES[$k]}" in
                    '## '*|'### '*) break ;;
                esac
                printf '%s\n' "${CONTENT_LINES[$k]}"
                k=$(( k + 1 ))
            done
            return 0
        fi
    done
    return 1
}

subsection_has_real_content() {
    content_has_real_text "$(subsection_content "$1" "$2" || true)"
}

# verify_completion_evidence <kind> <content> — a completed task must carry real
# verification evidence. Missing evidence is INVALID; placeholder-only evidence
# is BLOCKED at completion.
verify_completion_evidence() {
    local kind="$1" content="$2" cls
    cls="$(content_class "$content")"
    case "$cls" in
        content) return 0 ;;
        empty) fail_invalid "completed task must record verification evidence under '$kind'." ;;
        *) fail_blocked "completed task verification under '$kind' is still a placeholder (TBD, TODO, Pending, or similar)." ;;
    esac
}

# verify_completion_evidence_none <kind> <content> — like
# verify_completion_evidence, but accepts the exact 'None identified' sentinel
# as a resolved statement (used for Remaining risks).
verify_completion_evidence_none() {
    local kind="$1" content="$2" cls normalized
    cls="$(content_class "$content")"
    [ "$cls" = "content" ] && return 0
    if [ "$cls" = "placeholder" ]; then
        normalized="$(printf '%s' "$content" | lower | sed -E 's/^[[:space:]]*[-*+][[:space:]]+//' | tr -cd '[:alnum:]')"
        [ "$normalized" = "noneidentified" ] && return 0
    fi
    case "$cls" in
        empty) fail_invalid "completed task must record verification evidence under '$kind'." ;;
        *) fail_blocked "completed task verification under '$kind' is still a placeholder (TBD, TODO, Pending, or similar)." ;;
    esac
}

# check_completion_descriptions <content> <lower-id-pattern> <kind> — a
# completed task must give every declared identifier a real, non-placeholder
# description.
check_completion_descriptions() {
    local content="$1" idpat="$2" kind="$3" line lowline id desc
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s' "$line" | grep -qE '^[[:space:]]*[-*+][[:space:]]+' || continue
        lowline="$(printf '%s' "$line" | lower)"
        id="$(printf '%s' "$lowline" | grep -oE "$idpat" | head -1)"
        [ -n "$id" ] || continue
        desc="$(printf '%s' "$lowline" | sed -nE "s/^[[:space:]]*[-*+][[:space:]]*$idpat[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\1/p")"
        if [ -z "$desc" ] || [ "$(content_class "$desc")" = "placeholder" ]; then
            fail_blocked "$kind '$id' has a placeholder description."
        fi
    done <<< "$content"
}

# ---------------------------------------------------------------------------
# Scan: drop non-authoritative Markdown (fenced code blocks, HTML comments, and
# blockquote lines) and collect headings, declarations, and content.
# ---------------------------------------------------------------------------
CONTENT_LINES=()
SECTIONS=()
SECTION_START=()
SUBSECTIONS=()
SUB_SECTION=()
SUB_SECTION_START=()
PROFILE_DECL=0
PROFILE=""
PROFILE_IN_RISK=0
STATUS_DECL=0
STATUS=""
STATUS_IN_STATUS=0
UPDATED_COUNT=0
UPDATED=""
UPDATED_IN_STATUS=0
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
            SUB_SECTION_START+=( "${#CONTENT_LINES[@]}" )
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
    if printf '%s' "$line" | grep -qiE '^[[:space:]]*profile[[:space:]]*:'; then
        PROFILE_DECL=$(( PROFILE_DECL + 1 ))
        [ "$cur" = "risk profile" ] && PROFILE_IN_RISK=1
        if [ -z "$PROFILE" ]; then
            PROFILE="$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]*profile[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')"
        fi
    fi
    if printf '%s' "$line" | grep -qiE '^[[:space:]]*[-*]*[[:space:]]*\*?status[[:space:]]*:'; then
        STATUS_DECL=$(( STATUS_DECL + 1 ))
        [ "$cur" = "status" ] && STATUS_IN_STATUS=1
        if [ -z "$STATUS" ]; then
            STATUS="$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]*[-*]*[[:space:]]*\*?status[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')"
        fi
    fi
    if printf '%s' "$line" | grep -qiE '^[[:space:]]*updated[[:space:]]*:'; then
        UPDATED_COUNT=$(( UPDATED_COUNT + 1 ))
        [ "$cur" = "status" ] && UPDATED_IN_STATUS=1
        if [ -z "$UPDATED" ]; then
            UPDATED="$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]*updated[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')"
        fi
    fi
    CONTENT_LINES+=("$line")
done < "$TASK_FILE"

# ---------------------------------------------------------------------------
# Profile and status declarations.
# ---------------------------------------------------------------------------
[ "$PROFILE_DECL" -eq 1 ] || fail_invalid "task must declare exactly one 'Profile:' (found $PROFILE_DECL)."
[ "$PROFILE_IN_RISK" -eq 1 ] || fail_invalid "Profile: must be declared inside '## Risk profile'."
case "$PROFILE" in
    prototype|standard|high-assurance) ;;
    *) fail_invalid "task must declare a recognized risk profile (prototype, standard, or high-assurance)." ;;
esac
[ "$STATUS_DECL" -eq 1 ] || fail_invalid "task must declare exactly one 'Status:' (found $STATUS_DECL)."
[ "$STATUS_IN_STATUS" -eq 1 ] || fail_invalid "Status: must be declared inside '## Status'."
case "$STATUS" in
    planned|in-progress|blocked|done) ;;
    *) fail_invalid "task status must be one of: planned, in-progress, blocked, done (found '$STATUS')." ;;
esac
[ "$UPDATED_COUNT" -eq 1 ] || fail_invalid "task must declare exactly one 'Updated:' (found $UPDATED_COUNT)."
[ "$UPDATED_IN_STATUS" -eq 1 ] || fail_invalid "Updated: must be declared inside '## Status'."
[ -n "$UPDATED" ] || fail_invalid "Updated: must have a value."
validate_date "$UPDATED" || fail_invalid "Updated: must be a valid ISO date YYYY-MM-DD (found '$UPDATED')."
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
        REQUIRED_SECTIONS=( "status" "risk profile" "profile rationale" "task goal" "smoke verification" "known limitations" "approval gates" "handoff" )
        ;;
    standard)
        REQUIRED_SECTIONS=( "status" "risk profile" "profile rationale" "acceptance criteria" "required evidence" "approval gates" "verification" "files changed" "remaining risks" )
        REQUIRED_SUBSECTIONS=( "baseline" "final" )
        ;;
    high-assurance)
        REQUIRED_SECTIONS=( "status" "risk profile" "profile rationale" "requirements" "risk analysis" "requirement-to-evidence" "negative-path and boundary tests" "integration verification" "recovery plan" "approval gates" "independent review" "acceptance criteria" "required evidence" "verification" "files changed" "remaining risks" )
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

# Completed tasks must record real evidence in every section the profile
# declares as required. Missing content is INVALID; placeholder-only content
# is BLOCKED at completion.
if [ "$COMPLETED" -eq 1 ]; then
    verify_completion_evidence "## Profile rationale" "$(section_content "profile rationale" || true)"
fi
if [ "$PROFILE" != "prototype" ] && [ "$COMPLETED" -eq 1 ]; then
    verify_completion_evidence "### Baseline" "$(subsection_content "baseline" "verification" || true)"
    verify_completion_evidence "### Final" "$(subsection_content "final" "verification" || true)"
    verify_completion_evidence "## Files changed" "$(section_content "files changed" || true)"
    verify_completion_evidence_none "## Remaining risks" "$(section_content "remaining risks" || true)"
fi

# ---------------------------------------------------------------------------
# Prototype contract.
# ---------------------------------------------------------------------------
if [ "$PROFILE" = "prototype" ]; then
    # The two handoff declarations must appear as exact normalized declaration
    # lines, each exactly once. Substring matches are not enough: a line that
    # carries the phrase but adds negation or commentary ("... not established
    # — this statement is false.", "... confirmed? No.") is rejected, and a
    # phrase that appears only inside prose is not counted. Insignificant
    # casing and surrounding whitespace are ignored; a leading list marker is
    # stripped so a bulleted declaration still counts as a declaration line.
    readiness_decl=0
    no_deploy_decl=0
    handoff="$(section_content "handoff" || true)"
    while IFS= read -r dl || [ -n "$dl" ]; do
        d="$(printf '%s' "$dl" | sed -E 's/^[[:space:]]*[-*+][[:space:]]+//' | lower | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
        [ -n "$d" ] || continue
        case "$d" in
            'production readiness: not established')
                readiness_decl=$(( readiness_decl + 1 )) ;;
            'no production deployment or irreversible operation: confirmed')
                no_deploy_decl=$(( no_deploy_decl + 1 )) ;;
        esac
        if printf '%s' "$d" | grep -qE '^production[[:space:]]+readiness[[:space:]]*:' \
            && [ "$d" != 'production readiness: not established' ]; then
            fail_invalid "prototype handoff declaration 'Production readiness' must appear as the exact line 'Production readiness: not established'."
        fi
        if printf '%s' "$d" | grep -qE '^no[[:space:]]+production[[:space:]]+deployment[[:space:]]+or[[:space:]]+irreversible[[:space:]]+operation[[:space:]]*:' \
            && [ "$d" != 'no production deployment or irreversible operation: confirmed' ]; then
            fail_invalid "prototype handoff declaration 'No production deployment or irreversible operation' must appear as the exact line 'No production deployment or irreversible operation: confirmed'."
        fi
    done <<< "$handoff"
    [ "$readiness_decl" -eq 1 ] \
        || fail_invalid "prototype handoff must state 'Production readiness: not established' exactly once."
    [ "$no_deploy_decl" -eq 1 ] \
        || fail_invalid "prototype handoff must declare 'No production deployment or irreversible operation: confirmed' exactly once."
    if [ "$COMPLETED" -eq 1 ]; then
        verify_completion_evidence "## Task goal" "$(section_content "task goal" || true)"
        verify_completion_evidence "## Known limitations" "$(section_content "known limitations" || true)"
        verify_completion_evidence "## Smoke verification" "$(section_content "smoke verification" || true)"
        verify_completion_evidence "## Handoff" "$(section_content "handoff" || true)"
    fi
fi

# ---------------------------------------------------------------------------
# Standard and high-assurance evidence contracts.
# ---------------------------------------------------------------------------
if [ "$PROFILE" != "prototype" ]; then
    ac_content="$(section_content "acceptance criteria" || true)"
    ac_ids=""
    collect_canonical_ids "$ac_content" 'ac-[0-9]+' ac_ids
    [ "$MULTI_IDS" -eq 0 ] || fail_invalid "an acceptance criterion list entry declares more than one 'AC-N' identifier."
    [ "$BAD_FORM" -eq 0 ] || fail_invalid "acceptance criteria must use the form '- AC-N: <description>'."
    [ "$UNNUMBERED" -eq 0 ] || fail_invalid "every acceptance criterion list entry must begin with exactly one 'AC-N:' identifier; explanatory prose belongs in a separate Notes section."
    check_canonical_section "$ac_content" 'ac-[0-9]+' "acceptance criteria" 'AC-N: <description>'
    [ -n "$ac_ids" ] || fail_invalid "acceptance criteria must declare at least one 'AC-N' identifier."
    [ "$DUP_IDS" -eq 0 ] || fail_invalid "acceptance criteria declare duplicate 'AC-N' identifiers."
    if [ "$COMPLETED" -eq 1 ]; then
        check_completion_descriptions "$ac_content" 'ac-[0-9]+' "acceptance criterion"
    fi

    ev_ids=""
    validate_table "required evidence" 'AC-[0-9]+' "required evidence" "AC ID" ev_ids
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
        collect_canonical_ids "$req_content" 'r-[0-9]+' r_ids
        [ "$MULTI_IDS" -eq 0 ] || fail_invalid "a high-assurance requirement list entry declares more than one 'R-N' identifier."
        [ "$BAD_FORM" -eq 0 ] || fail_invalid "high-assurance requirements must use the form '- R-N: <description>'."
        [ "$UNNUMBERED" -eq 0 ] || fail_invalid "every high-assurance requirement list entry must begin with exactly one 'R-N:' identifier; explanatory prose belongs in a separate Notes section."
        check_canonical_section "$req_content" 'r-[0-9]+' "high-assurance requirements" 'R-N: <description>'
        [ -n "$r_ids" ] || fail_invalid "high-assurance requirements must declare at least one 'R-N' identifier."
        [ "$DUP_IDS" -eq 0 ] || fail_invalid "high-assurance requirements declare duplicate 'R-N' identifiers."
        if [ "$COMPLETED" -eq 1 ]; then
            check_completion_descriptions "$req_content" 'r-[0-9]+' "high-assurance requirement"
        fi

        m_ids=""
        validate_table "requirement-to-evidence" 'R-[0-9]+' "requirement-to-evidence" "Requirement ID" m_ids
        [ -n "$m_ids" ] || fail_invalid "the requirement-to-evidence matrix must map at least one 'R-N' to evidence."
        [ "$TABLE_DUP" -eq 0 ] || fail_invalid "the requirement-to-evidence matrix maps a requirement more than once."
        if [ "$(sorted_unique "$r_ids")" != "$(sorted_unique "$m_ids")" ]; then
            fail_invalid "requirements and the requirement-to-evidence matrix must list exactly the same 'R-N' identifiers."
        fi
        if [ "$COMPLETED" -eq 1 ] && [ "$HAS_UNRESOLVED" -eq 1 ]; then
            fail_blocked "task is marked complete but the requirement-to-evidence matrix has unresolved rows."
        fi

        for s in "risk analysis" "negative-path and boundary tests" "integration verification" "recovery plan" "independent review"; do
            section_has_real_content "$s" || fail_invalid "high-assurance section '## $s' must contain real content (no headings, placeholders, or separators)."
        done
    fi
fi

# ---------------------------------------------------------------------------
# Approval gates: structured records only; no prose-based approval inference.
# Validated for every profile whenever an '## Approval gates' section exists.
# ---------------------------------------------------------------------------
if has_section "approval gates"; then
    gates="$(section_content "approval gates" || true)"
    has_none=0
    gate_count=0
    checked=0
    unchecked=0
    gate_seen=""
    while IFS= read -r gl || [ -n "$gl" ]; do
        gl="$(printf '%s' "$gl" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        [ -n "$gl" ] || continue
        gl_low="$(printf '%s' "$gl" | lower)"
        body_low="$(printf '%s\n' "$gl_low" | sed -E 's/^[-*+][[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]*[.!?;:,-]+$//')"
        if [ "$body_low" = "none identified" ]; then
            has_none=1
            continue
        fi
        if printf '%s' "$gl_low" | grep -qE '^[-*+][[:space:]]*\[[ xX]\]'; then
            printf '%s' "$gl_low" | grep -qE '^[-*+][[:space:]]*\[[ xX]\][[:space:]]*ag-[0-9]+[[:space:]]*:' \
                || fail_invalid "malformed approval entry in '## Approval gates': '$gl'."
            gate_count=$(( gate_count + 1 ))
            gid="$(printf '%s\n' "$gl_low" | sed -nE 's/^[-*+][[:space:]]*\[([ xX])\][[:space:]]*(ag-[0-9]+)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\2/p')"
            gbox="$(printf '%s\n' "$gl_low" | sed -nE 's/^[-*+][[:space:]]*\[([ xX])\][[:space:]]*(ag-[0-9]+)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\1/p')"
            gdet="$(printf '%s\n' "$gl_low" | sed -nE 's/^[-*+][[:space:]]*\[([ xX])\][[:space:]]*(ag-[0-9]+)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\3/p' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
            case " $gate_seen " in
                *" $gid "*) fail_invalid "approval gate '$gid' is declared more than once." ;;
            esac
            gate_seen="$gate_seen $gid"
            case "$gbox" in
                x)
                    checked=$(( checked + 1 ))
                    printf '%s' "$gdet" | grep -qE '^approved[[:space:]]+by[[:space:]]+.+[[:space:]]+on[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' \
                        || fail_invalid "approval gate '$gid' must be in the form '- [x] AG-N: Approved by <approver> on YYYY-MM-DD'."
                    printf '%s' "$gdet" | grep -qE '<approver>|tbd|pending|unknown|n/a|not[[:space:]]+approved|approval[[:space:]]+not[[:space:]]+granted' \
                        && fail_invalid "approval gate '$gid' must not use placeholder values."
                    adate="$(printf '%s\n' "$gdet" | sed -nE 's/^.*[[:space:]]+on[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]*$/\1/p')"
                    [ -n "$adate" ] || fail_invalid "approval gate '$gid' must record an ISO date YYYY-MM-DD."
                    validate_date "$adate" || fail_invalid "approval gate '$gid' has an invalid ISO date '$adate'."
                    approver="$(printf '%s\n' "$gdet" | awk '{ sub(/^approved[[:space:]]+by[[:space:]]+/, ""); sub(/[[:space:]]+on[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$/, ""); print }')"
                    [ -n "$approver" ] || fail_invalid "approval gate '$gid' must record an approver."
                    printf '%s' "$approver" | grep -q '[<>]' \
                        && fail_invalid "approval gate '$gid' must not use template placeholders."
                    has_meaningful_char "$approver" \
                        || fail_invalid "approval gate '$gid' must record a meaningful approver."
                    ;;
                *)
                    unchecked=$(( unchecked + 1 ))
                    [ -n "$gdet" ] || fail_invalid "approval gate '$gid' must describe the required approval."
                    printf '%s' "$gdet" | grep -qE '^approved[[:space:]]+by[[:space:]]+.+[[:space:]]+on[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' \
                        && fail_invalid "unchecked approval gate '$gid' cannot record an approval; describe the requirement instead."
                    ;;
            esac
            continue
        fi
        if printf '%s' "$gl_low" | grep -qE '\[[ xX]\]'; then
            fail_invalid "malformed approval entry in '## Approval gates': '$gl'."
        fi
        if printf '%s' "$gl_low" | grep -qE '^[-*+][[:space:]]+'; then
            fail_invalid "malformed approval entry in '## Approval gates': '$gl'."
        fi
        fail_invalid "malformed approval entry in '## Approval gates': '$gl'."
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
