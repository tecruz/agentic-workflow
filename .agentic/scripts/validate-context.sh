#!/usr/bin/env bash
#
# validate-context.sh — structural validator for context-module selections in
# agentic task files.
#
# Validates only structural facts about the `## Context modules` section of a
# task file against the managed registry under `.agentic/context/`:
#   - every selected module exists in the registry
#   - no duplicate module IDs
#   - every selection carries a real rationale
#   - the task's risk profile satisfies each module's minimum profile
#   - a completed task has no unresolved selection placeholders
#   - the `None selected` sentinel never coexists with selections
#   - selection versions are recognized by the registry
#   - selection identifiers cannot escape the registry namespace
#
# Content in fenced code blocks, HTML comments, and blockquote lines is not
# authoritative and is ignored.
#
# Exit codes:
#   0  VALID
#   1  INVALID — structural contract violation
#   2  BLOCKED — completion gate not satisfied, or registry unusable
#
# Usage:
#   ./validate-context.sh [--format text|json] [--handoff] path/to/TASK-001.md
#
# Environment:
#   AGENTIC_CONTEXT_REGISTRY  Override the registry directory (tests). Defaults
#                             to the `context/` directory beside this script.

set -uo pipefail

FORMAT="text"
HANDOFF=0
TASK_FILE=""

usage() {
    cat <<'EOF'
Usage: validate-context.sh [--format text|json] [--handoff] <task-file>

Validates the context-module selection contract of an agentic task file.

Options:
  --format    Output format: text (default) or json.
  --handoff   Require Status: done and enforce the completion gate.
  -h, --help  Show this help.

Exit codes:
  0  VALID
  1  INVALID
  2  BLOCKED — unresolved selection at completion, or unusable registry
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --format)
            if [ $# -lt 2 ]; then
                echo "ERROR: --format requires a value ('text' or 'json')." >&2
                exit 1
            fi
            FORMAT="$2"; shift 2 ;;
        --format=*) FORMAT="${1#*=}"; shift ;;
        --handoff) HANDOFF=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$TASK_FILE" ]; then
                echo "Error: expected a single task file." >&2
                exit 1
            fi
            TASK_FILE="$1"
            shift
            ;;
    esac
done

case "$(printf '%s' "$FORMAT" | tr '[:upper:]' '[:lower:]')" in
    text) FORMAT="text" ;;
    json) FORMAT="json" ;;
    *)
        echo "ERROR: --format must be 'text' or 'json'." >&2
        exit 1
        ;;
esac

if [ -z "$TASK_FILE" ]; then
    usage >&2
    exit 1
fi

# Python 3 is required only for JSON serialization; text mode must work
# without any Python installation.
if [ "$FORMAT" = "json" ]; then
    command -v python3 >/dev/null 2>&1 || { echo "ERROR: Python 3 is required for --format json" >&2; exit 1; }
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${AGENTIC_CONTEXT_REGISTRY:-}" ]; then
    REGISTRY="$AGENTIC_CONTEXT_REGISTRY"
else
    REGISTRY="$SCRIPT_DIR/../context"
fi

# Display form of the task file path for JSON output: passed through when
# already relative, made project-relative when it lives under the working
# directory, degraded to its basename otherwise, so an absolute user-home
# path can never leak into machine-readable results.
display_path() {
    local p="$1"
    local norm="${p//\\//}"
    norm="${norm#./}"
    case "$norm" in
        "$PWD") printf '.' ; return ;;
        "$PWD"/*) printf './%s' "${norm#"$PWD"/}" ; return ;;
        /*|[A-Za-z]:*) printf '%s' "$(basename "$norm")" ; return ;;
    esac
    printf '%s' "$norm"
}

output_context_json() {
    # res_str exit_code msg [code] [section] [ident]
    local res_str="$1" exit_code="$2" msg="$3" code="${4:-MODULE_UNKNOWN}" section="${5:-null}" ident="${6:-null}"
    python3 -c '
import json, sys

res_str = sys.argv[1]
exit_code = int(sys.argv[2])
task_file = sys.argv[3]
profile = sys.argv[4]
diag_code = sys.argv[5]
diag_section = sys.argv[6]
diag_ident = sys.argv[7]
diag_msg = sys.argv[8]
mode = sys.argv[9]

diagnostics = []
if res_str != "VALID":
    diagnostics.append({
        "code": diag_code,
        "section": diag_section if diag_section != "null" else None,
        "identifier": diag_ident if diag_ident != "null" else None,
        "message": diag_msg
    })

profile_out = None
if profile in ("prototype", "standard", "high-assurance"):
    profile_out = profile

doc = {
    "schema_version": 1,
    "protocol_version": "1.5.0",
    "kind": "context_validation_result",
    "mode": mode,
    "result": res_str,
    "exit_code": exit_code,
    "task_file": task_file,
    "profile": profile_out,
    "selected_modules": [],
}
doc["diagnostics"] = diagnostics

print(json.dumps(doc))
' "$res_str" "$exit_code" "$(display_path "$TASK_FILE")" "${PROFILE:-}" "$code" "$section" "$ident" "$msg" "$( [ "$HANDOFF" -eq 1 ] && echo handoff || echo standard )"
    if [ $? -ne 0 ]; then
        echo "ERROR: failed to serialize JSON result." >&2
        exit 1
    fi
}

fail_invalid() {
    if [ "$#" -ne 4 ]; then
        echo "INTERNAL ERROR: fail_invalid requires <code> <section> <identifier> <message>" >&2
        exit 1
    fi
    local code="$1" section="$2" ident="$3" msg="$4"
    [ -n "$section" ] || section="null"
    [ -n "$ident" ] || ident="null"
    if [ "$FORMAT" = "json" ]; then
        output_context_json "INVALID" 1 "$msg" "$code" "$section" "$ident"
        exit 1
    else
        echo "INVALID: $msg" >&2
        exit 1
    fi
}

fail_blocked() {
    if [ "$#" -ne 4 ]; then
        echo "INTERNAL ERROR: fail_blocked requires <code> <section> <identifier> <message>" >&2
        exit 1
    fi
    local code="$1" section="$2" ident="$3" msg="$4"
    [ -n "$section" ] || section="null"
    [ -n "$ident" ] || ident="null"
    if [ "$FORMAT" = "json" ]; then
        output_context_json "BLOCKED" 2 "$msg" "$code" "$section" "$ident"
        exit 2
    else
        echo "BLOCKED: $msg" >&2
        exit 2
    fi
}

if [ ! -f "$TASK_FILE" ]; then
    if [ "$FORMAT" = "json" ]; then
        fail_invalid "CONTEXT_SECTION_MISSING" "" "" "Task file was not found: $(display_path "$TASK_FILE")"
    else
        echo "Error: task file not found: $TASK_FILE" >&2
    fi
    exit 1
fi

# ---------------------------------------------------------------------------
# Load the registry: parallel arrays MODULE_IDS / MODULE_VERSIONS holding the
# declared ID and Version of every <registry>/<id>/MODULE.md. A module whose
# declared Version is not a positive integer makes the registry unverifiable
# and blocks the run rather than guessing.
# ---------------------------------------------------------------------------
declare -a MODULE_IDS=()
declare -a MODULE_VERSIONS=()

load_registry() {
    if [ ! -d "$REGISTRY" ]; then
        fail_blocked "CONTEXT_REGISTRY_MISSING" "" "" "Context module registry not found: $(basename "$REGISTRY")"
        return
    fi
    local dir mf id ver
    for dir in "$REGISTRY"/*/ ; do
        [ -d "$dir" ] || continue
        mf="$dir/MODULE.md"
        [ -f "$mf" ] || continue
        id=""
        ver=""
        local in_id=0 in_ver=0 line
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                "## ID")    in_id=1;  in_ver=0; continue ;;
                "## Version") in_ver=1; in_id=0; continue ;;
                "##"*)      in_id=0;  in_ver=0; continue ;;
            esac
            if [ "$in_id" -eq 1 ] && [ -z "$id" ] && [ -n "${line//[[:space:]]/}" ]; then
                id="$(printf '%s' "$line" | tr -d '[:space:]')"
            elif [ "$in_ver" -eq 1 ] && [ -z "$ver" ] && [ -n "${line//[[:space:]]/}" ]; then
                ver="$(printf '%s' "$line" | tr -d '[:space:]')"
            fi
        done < "$mf"
        if ! printf '%s' "$ver" | grep -Eq '^[1-9][0-9]*$'; then
            fail_blocked "MODULE_VERSION_UNSUPPORTED" "registry" "$(basename "$dir")" "Module '$(basename "$dir")' declares an unsupported version ('$ver'); registry is unusable."
            return
        fi
        MODULE_IDS+=("$id")
        MODULE_VERSIONS+=("$ver")
    done
}

registry_has() {
    local want="$1" i
    for i in "${!MODULE_IDS[@]}"; do
        if [ "${MODULE_IDS[$i]}" = "$want" ]; then
            return 0
        fi
    done
    return 1
}

registry_version_of() {
    local want="$1" i
    for i in "${!MODULE_IDS[@]}"; do
        if [ "${MODULE_IDS[$i]}" = "$want" ]; then
            printf '%s' "${MODULE_VERSIONS[$i]}"
            return 0
        fi
    done
    return 1
}

# True when the value carries at least one letter or number.
has_meaningful_char() {
    printf '%s' "$1" | grep -qE '[[:alpha:][:digit:]]'
}

# True when the value is recognized placeholder content rather than a real
# rationale: bare placeholder tokens, bracketed or angle-bracket markers,
# '<label>: TBD' forms, or placeholder-prefixed fragments.
is_placeholder_text() {
    local n
    n="$(printf '%s' "$1" | sed -e 's/^[[:space:]-]*+//' -e 's/[[:space:].!?;:,-]*$//' -e 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
    case "$n" in
        ""|tbd|todo|pending|placeholder|tbc|none|n/a) return 0 ;;
    esac
    case "$1" in
        \[*\]|\<*\>) return 0 ;;
    esac
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *tbd*|*todo*|*pending*) return 0 ;;
    esac
    return 1
}

PROFILE=""
STATUS=""
SECTION_FOUND=0

# Authoritative-line scanner: drops fenced code blocks, HTML comment blocks,
# blockquote lines, and collects Profile/Status declarations and the raw body
# of `## Context modules` (until the next `## ` heading).
declare -a SECTION_LINES=()

scan_task_file() {
    local line in_fence=0 in_comment=0 in_section=0 norm
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [ "$in_fence" -eq 1 ]; then
            case "$line" in
                '```'|'```'*) in_fence=0 ;;
            esac
            continue
        fi
        case "$line" in
            '```'|'```'*) in_fence=1; continue ;;
        esac
        if [ "$in_comment" -eq 1 ]; then
            case "$line" in
                *'-->'*) in_comment=0 ;;
            esac
            continue
        fi
        case "$line" in
            '<!--'*)
                case "$line" in
                   *'-->'*) ;;
                    *) in_comment=1 ;;
                esac
                continue ;;
            '>'*) continue ;;
        esac
        norm="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
        case "$norm" in
            "profile:"*)
                PROFILE="$(printf '%s' "$line" | sed -e 's/^[Pp][Rr][Oo][Ff][Ii][Ll][Ee]:[[:space:]]*//' | awk '{print $1}')"
                ;;
            "status:"*)
                STATUS="$(printf '%s' "$line" | sed -e 's/^[Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]*//' | awk '{print $1}')"
                ;;
            '## '*)
                if [ "$in_section" -eq 1 ]; then
                    in_section=0
                fi
                if [ "$norm" = "## context modules" ]; then
                    SECTION_FOUND=1
                    in_section=1
                fi
                continue ;;
        esac
        if [ "$in_section" -eq 1 ]; then
            SECTION_LINES+=("$line")
        fi
    done < "$TASK_FILE"
}

# Selection state.
SELECTION_COUNT=0
NONE_SENTINEL_SEEN=0
declare -a SELECTED_IDS=()
declare -a SELECTED_VERSIONS=()

parse_selection_line() {
    # Strips the bullet marker and returns the remainder on stdout.
    local raw="$1"
    printf '%s' "$raw" | sed -e 's/^[[:space:]]*[-*+][[:space:]]*//'
}

handle_entry() {
    local entry="$1"

    # Skip blank entries.
    if [ -z "${entry//[[:space:]]/}" ]; then
        return 0
    fi

    # Sentinel: '- None selected' optionally followed by '— <why>'
    local lowered
    lowered="$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')"
    case "$lowered" in
        none\ selected*)
            NONE_SENTINEL_SEEN=1
            return 0
            ;;
    esac

    SELECTION_COUNT=$((SELECTION_COUNT + 1))

    # Grammar: <id> v<N> loaded [-—:] <rationale>
    local id="" ver="" loaded_token="" rest=""
    id="$(printf '%s' "$entry" | awk '{print $1}')"
    ver="$(printf '%s' "$entry" | awk '{print $2}')"
    loaded_token="$(printf '%s' "$entry" | awk '{print $3}')"
    rest="$(printf '%s' "$entry" | cut -s -d' ' -f4-)"

    if ! printf '%s' "$entry" | grep -Eq '^[^[:space:]]+[[:space:]]+v[1-9][0-9]*[[:space:]]+[^[:space:]]+'; then
        fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "$entry" "Selection entry is not in the canonical form '<module-id> v<N> loaded — <rationale>': $entry"
    fi

    local sep_rationale
    sep_rationale="$(printf '%s' "$rest" | sed -e 's/^[—–-][[:space:]]*//')"

    if [ "$loaded_token" != "loaded" ]; then
        fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "$id" "Selection of '$id' does not confirm the module was loaded before planning."
    fi

    if ! registry_has "$id"; then
        fail_invalid "MODULE_UNKNOWN" "## Context modules" "$id" "Selected module '$id' is not in the managed registry."
    fi

    local reg_ver
    reg_ver="$(registry_version_of "$id")"
    if [ "${ver#v}" != "$reg_ver" ]; then
        fail_invalid "MODULE_VERSION_UNSUPPORTED" "## Context modules" "$id" "Selection of '$id' declares version '${ver#v}' but the registry provides '$reg_ver'."
    fi

    if ! has_meaningful_char "$sep_rationale"; then
        fail_invalid "MODULE_RATIONALE_MISSING" "## Context modules" "$id" "Selection of '$id' must carry a selection rationale."
    fi

    if is_placeholder_text "$sep_rationale"; then
        if [ "$STATUS" = "done" ]; then
            fail_blocked "MODULE_SELECTION_UNRESOLVED" "## Context modules" "$id" "Completed task carries an unresolved rationale placeholder for '$id'."
        fi
    fi

    local seen
    for seen in "${SELECTED_IDS[@]:-}"; do
        if [ "$seen" = "$id" ]; then
            fail_invalid "MODULE_DUPLICATE" "## Context modules" "$id" "Module '$id' is selected more than once."
        fi
    done

    SELECTED_IDS+=("$id")
    SELECTED_VERSIONS+=("${ver#v}")
    return 0
}

profile_rank() {
    case "$1" in
        prototype) printf 0 ;;
        standard) printf 1 ;;
        high-assurance) printf 2 ;;
        *) printf -1 ;;
    esac
}

check_profile_floor() {
    local p_rank m_rank i id
    p_rank="$(profile_rank "$PROFILE")"
    [ "$p_rank" -lt 0 ] && return 0
    for i in "${!SELECTED_IDS[@]}"; do
        id="${SELECTED_IDS[$i]}"
        local min_profile=""
        local mf="$REGISTRY/$id/MODULE.md"
        local grab=0 line
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            norm_line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
            case "$norm_line" in
                "## minimum risk profile") grab=1; continue ;;
                "##"*) grab=0; continue ;;
            esac
            if [ "$grab" -eq 1 ] && [ -z "$min_profile" ] && [ -n "${line//[[:space:]]/}" ]; then
                min_profile="$(printf '%s' "$line" | awk '{print $1}')"
            fi
        done < "$mf"
        m_rank="$(profile_rank "$min_profile")"
        if [ "$m_rank" -ge 0 ] && [ "$p_rank" -lt "$m_rank" ]; then
            fail_invalid "MODULE_PROFILE_TOO_LOW" "## Context modules" "$id" "Task profile '$PROFILE' is below the '$min_profile' minimum required by module '$id'."
        fi
    done
}

load_registry
scan_task_file

if [ "$HANDOFF" -eq 1 ] && [ "$STATUS" != "done" ]; then
    fail_invalid "CONTEXT_SECTION_MISSING" "## Status" "" "--handoff requires 'Status: done'; found '${STATUS:-<none>}'."
fi

if [ "$SECTION_FOUND" -ne 1 ]; then
    fail_invalid "CONTEXT_SECTION_MISSING" "## Context modules" "" "Task file has no '## Context modules' section."
fi

for raw in "${SECTION_LINES[@]}"; do
    entry="$(parse_selection_line "$raw")"
    handle_entry "$entry"
done

if [ "$SELECTION_COUNT" -eq 0 ] && [ "$NONE_SENTINEL_SEEN" -eq 0 ]; then
    fail_invalid "CONTEXT_SECTION_MISSING" "## Context modules" "" "'## Context modules' records neither a selection nor the 'None selected' sentinel."
fi

if [ "$NONE_SENTINEL_SEEN" -eq 1 ] && [ "$SELECTION_COUNT" -gt 0 ]; then
    fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "None selected" "'None selected' cannot coexist with selected modules."
fi

check_profile_floor

if [ "$FORMAT" = "json" ]; then
    # Selected modules travel through an environment variable so no unquoted
    # expansion ever word-splits ids or versions (ShellCheck-clean by design).
    SELECTED_PAYLOAD=""
    _i=0
    while [ "$_i" -lt "${#SELECTED_IDS[@]}" ]; do
        SELECTED_PAYLOAD="$SELECTED_PAYLOAD ${SELECTED_IDS[$_i]}:${SELECTED_VERSIONS[$_i]}"
        _i=$((_i + 1))
    done
    AGENTIC_SELECTED="$SELECTED_PAYLOAD" python3 -c '
import json, os, sys
task_file = sys.argv[1]
profile = sys.argv[2] if sys.argv[2] in ("prototype", "standard", "high-assurance") else None
mode = sys.argv[3]
selected = []
for chunk in os.environ.get("AGENTIC_SELECTED", "").split():
    mid, _, mver = chunk.partition(":")
    selected.append({"id": mid, "version": int(mver)})
doc = {
    "schema_version": 1,
    "protocol_version": "1.5.0",
    "kind": "context_validation_result",
    "mode": mode,
    "result": "VALID",
    "exit_code": 0,
    "task_file": task_file,
    "profile": profile,
    "selected_modules": selected,
    "diagnostics": [],
}
print(json.dumps(doc))
' "$(display_path "$TASK_FILE")" "${PROFILE:-}" "$( [ "$HANDOFF" -eq 1 ] && echo handoff || echo standard )"
else
    echo "VALID: context selections ok ($( [ "$NONE_SENTINEL_SEEN" -eq 1 ] && echo 'none selected' || { printf '%s' "${SELECTED_IDS[*]}"; } ))"
fi
exit 0
