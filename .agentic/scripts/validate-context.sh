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
#
# The registry itself is validated before use: a module's declared ID must
# match `^[a-z0-9][a-z0-9-]*$`, must equal its directory name, must be unique,
# must declare a positive-integer Version and a recognized Minimum risk
# profile, must not repeat any required heading, and must carry substantive
# content under every required documentation section. A violating registry is
# rejected wholesale as unusable (BLOCKED), so task-provided text can never
# influence filesystem paths.
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
        # JSON mode: use neutral identifier and generic message to avoid leaking task content
        local json_ident="null"
        local json_msg=""
        case "$code" in
            "CONTEXT_SECTION_MISSING")
                json_msg="Task file is missing the required '## Context modules' section." ;;
            "CONTEXT_PROFILE_INVALID")
                json_msg="Task must declare exactly one recognized risk profile." ;;
            "MODULE_UNKNOWN")
                json_msg="Selected module is not in the managed registry." ;;
            "MODULE_VERSION_UNSUPPORTED")
                json_msg="Selection declares an unsupported module version." ;;
            "MODULE_RATIONALE_MISSING")
                json_msg="Selection must carry a selection rationale." ;;
            "MODULE_DUPLICATE")
                json_msg="Module is selected more than once." ;;
            "MODULE_PROFILE_TOO_LOW")
                json_msg="Task profile is below the minimum required by the selected module." ;;
            "MODULE_SELECTION_UNRESOLVED")
                json_msg="Module selection does not match the required structure." ;;
            *)
                json_msg="Structural contract violation." ;;
        esac
        output_context_json "INVALID" 1 "$json_msg" "$code" "$section" "$json_ident"
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
        # JSON mode: use neutral identifier and generic message
        local json_ident="null"
        local json_msg=""
        case "$code" in
            "CONTEXT_REGISTRY_MISSING")
                json_msg="Context module registry not found." ;;
            "CONTEXT_REGISTRY_INVALID")
                json_msg="Context module registry is unusable." ;;
            "MODULE_SELECTION_UNRESOLVED")
                json_msg="Completed task carries an unresolved selection placeholder." ;;
            *)
                json_msg="Completion gate not satisfied." ;;
        esac
        output_context_json "BLOCKED" 2 "$json_msg" "$code" "$section" "$json_ident"
        exit 2
    else
        echo "BLOCKED: $msg" >&2
        exit 2
    fi
}

if [ ! -f "$TASK_FILE" ]; then
    fail_invalid "CONTEXT_SECTION_MISSING" "" "" "Task file was not found: $(display_path "$TASK_FILE")"
fi

# ---------------------------------------------------------------------------
# Registry validation. Every module becomes one structured record:
#   REG_DIRS[i]   containing directory name
#   REG_IDS[i]    declared ID (must equal the directory name)
#   REG_VERSIONS  declared positive-integer Version
#   REG_MINS[i]   declared Minimum risk profile (recognized)
# A registry that violates any identity or metadata rule is rejected whole
# (CONTEXT_REGISTRY_INVALID, BLOCKED): an untrusted registry must never be
# partially consumed, and task-provided IDs never select filesystem paths.
# ---------------------------------------------------------------------------
REG_ID_PATTERN='^[a-z0-9][a-z0-9-]*$'

declare -a REG_DIRS=()
declare -a REG_IDS=()
declare -a REG_VERSIONS=()
declare -a REG_MINS=()

has_meaningful_char() {
    if LC_ALL=C grep -qE '[A-Za-z0-9]' <<< "$1"; then
        return 0
    fi
    [ -n "$1" ] || return 1
    if ! LC_ALL=C grep -q '[^[:print:]]' <<< "$1"; then
        return 1
    fi
    command -v perl >/dev/null 2>&1 \
        || fail_invalid "TOOLING_UNAVAILABLE" "" "" "perl is required to classify non-ASCII content; install perl or keep evidence ASCII-only."
    perl -CS -0777 -ne 'exit(/[\p{L}\p{N}]/ ? 0 : 1)' <<< "$1" 2>/dev/null
}

registry_invalid() {
    fail_blocked "CONTEXT_REGISTRY_INVALID" "registry" "${2:-}" "Context module registry is unusable: $1"
}

load_registry() {
    if [ ! -d "$REGISTRY" ]; then
        fail_blocked "CONTEXT_REGISTRY_MISSING" "" "" "Context module registry not found: $(basename "$REGISTRY")"
        return
    fi
    local dir mf dirname line current id ver min
    local id_n ver_n min_n lw_n rc_n ag_n re_n ps_n
    local lw_c rc_c ag_c re_c ps_c
    for dir in "$REGISTRY"/*/ ; do
        [ -d "$dir" ] || continue
        mf="${dir}MODULE.md"
        [ -f "$mf" ] || continue
        dirname="$(basename "$dir")"

        id="" ; ver="" ; min=""
        id_n=0 ; ver_n=0 ; min_n=0
        lw_n=0 ; rc_n=0 ; ag_n=0 ; re_n=0 ; ps_n=0
        lw_c=0 ; rc_c=0 ; ag_c=0 ; re_c=0 ; ps_c=0
        current=""

        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            norm_line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]*$//')"
            case "$norm_line" in
                "## id")                    current="id";     id_n=$((id_n + 1)); continue ;;
                "## version")               current="ver";    ver_n=$((ver_n + 1)); continue ;;
                "## minimum risk profile")  current="min";    min_n=$((min_n + 1)); continue ;;
                "## load when")             current="lw";     lw_n=$((lw_n + 1)); continue ;;
                "## required context")      current="rc";     rc_n=$((rc_n + 1)); continue ;;
                "## approval gates")        current="ag";     ag_n=$((ag_n + 1)); continue ;;
                "## required evidence")     current="re";     re_n=$((re_n + 1)); continue ;;
                "## prohibited shortcuts")  current="ps";     ps_n=$((ps_n + 1)); continue ;;
                "##"*)                      current="" ;;
            esac
            case "$current" in
                id)
                    if [ -z "$id" ] && [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ]; then
                        id="$(printf '%s' "$line" | tr -d '[:space:]')"
                    fi ;;
                ver)
                    if [ -z "$ver" ] && [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ]; then
                        ver="$(printf '%s' "$line" | tr -d '[:space:]')"
                    fi ;;
                min)
                    if [ -z "$min" ] && [ -n "${line//[[:space:]]/}" ]; then
                        min="$(printf '%s' "$line" | awk '{print $1}')"
                    fi ;;
                lw) [ "$lw_c" -eq 0 ] && has_meaningful_char "$line" && ! is_placeholder_text "$line" && lw_c=1 ;;
                rc) [ "$rc_c" -eq 0 ] && has_meaningful_char "$line" && ! is_placeholder_text "$line" && rc_c=1 ;;
                ag) [ "$ag_c" -eq 0 ] && has_meaningful_char "$line" && ! is_placeholder_text "$line" && ag_c=1 ;;
                re) [ "$re_c" -eq 0 ] && has_meaningful_char "$line" && ! is_placeholder_text "$line" && re_c=1 ;;
                ps) [ "$ps_c" -eq 0 ] && has_meaningful_char "$line" && ! is_placeholder_text "$line" && ps_c=1 ;;
            esac
        done < "$mf"

        for pair in "ID:$id_n" "Version:$ver_n" "Minimum risk profile:$min_n" \
                    "Load when:$lw_n" "Required context:$rc_n" \
                    "Approval gates:$ag_n" "Required evidence:$re_n" \
                    "Prohibited shortcuts:$ps_n"; do
            count="${pair##*:}"
            case "$count" in
                0)
                    registry_invalid "module '$dirname' is missing its '${pair%%:*}' section." "$dirname"
                    return
                    ;;
                1) ;;
                *)
                    registry_invalid "module '$dirname' declares heading '${pair%%:*}' more than once." "$dirname"
                    return
                    ;;
            esac
        done

        if ! printf '%s' "$id" | grep -Eq "$REG_ID_PATTERN"; then
            registry_invalid "module '$dirname' declares ID '$id', which does not match $REG_ID_PATTERN." "$dirname"
            return
        fi
        if [ "$id" != "$dirname" ]; then
            registry_invalid "module '$dirname' declares ID '$id' that differs from its directory name." "$dirname"
            return
        fi
        local seen
        for seen in "${REG_IDS[@]:-}"; do
            if [ "$seen" = "$id" ]; then
                registry_invalid "module ID '$id' is declared more than once." "$dirname"
                return
            fi
        done
        if ! printf '%s' "$ver" | grep -Eq '^[1-9][0-9]*$'; then
            registry_invalid "module '$dirname' declares an unsupported Version ('$ver')." "$dirname"
            return
        fi
        case "$min" in
            prototype|standard|high-assurance) ;;
            *)
                registry_invalid "module '$dirname' declares missing or unrecognized Minimum risk profile ('$min')." "$dirname"
                return
                ;;
        esac
        if [ "$lw_c" -eq 0 ] || [ "$rc_c" -eq 0 ] || [ "$ag_c" -eq 0 ] ||
           [ "$re_c" -eq 0 ] || [ "$ps_c" -eq 0 ]; then
            registry_invalid "module '$dirname' is missing substantive content under one of: Load when, Required context, Approval gates, Required evidence, Prohibited shortcuts." "$dirname"
            return
        fi

        REG_DIRS+=("$dirname")
        REG_IDS+=("$id")
        REG_VERSIONS+=("$ver")
        REG_MINS+=("$min")
    done
}

registry_index_of() {
    local want="$1" i
    for i in "${!REG_IDS[@]}"; do
        if [ "${REG_IDS[$i]}" = "$want" ]; then
            printf '%s' "$i"
            return 0
        fi
    done
    return 1
}

# True when the value carries at least one letter or number.
# (Placeholder detection shares the meaningful-char predicate.)
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
PROFILE_COUNT=0
STATUS=""
SECTION_FOUND=0

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
                PROFILE_COUNT=$((PROFILE_COUNT + 1))
                PROFILE="$(printf '%s' "$line" | sed -e 's/^[Pp][Rr][Oo][Ff][Ii][Ll][Ee]:[[:space:]]*//' | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
                ;;
            "status:"*)
                STATUS="$(printf '%s' "$line" | sed -e 's/^[Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]*//' | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
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

SELECTION_COUNT=0
NONE_SENTINEL_SEEN=0
declare -a SELECTED_IDS=()
declare -a SELECTED_VERSIONS=()

parse_selection_line() {
    local raw="$1"
    printf '%s' "$raw" | sed -e 's/^[[:space:]]*[-*+][[:space:]]*//'
}

handle_entry() {
    local entry="$1"

    if [ -z "${entry//[[:space:]]/}" ]; then
        return 0
    fi

    # Sentinel: '- None selected' optionally followed by '— <why>'. A suffix
    # must be a substantive rationale: symbol-only separators are malformed,
    # and placeholder suffixes (TBD/TODO/Pending/...) block a completed task.
    # Requires word-boundary after 'selected' to reject 'selectedness' etc.
    # Anchored grammar: ^none\s+selected(?:\s+[—–-]\s+.+)?$
    local lowered
    lowered="$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')"
    # First check: must start with "none selected" followed by end-of-string or whitespace+separator
    if ! printf '%s' "$lowered" | grep -qE '^none[[:space:]]+selected($|[[:space:]]+)'; then
        # Not a sentinel line - but check if it's a malformed "none selected" variant
        if printf '%s' "$lowered" | grep -qE '^none[[:space:]]+selected'; then
            fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "$entry" "'None selected' must be followed by end-of-line or a separator ( — / – / - ) with surrounding whitespace: $entry"
        fi
    else
        # It starts with "none selected" - now validate the full grammar
        local suffix
        suffix="$(printf '%s' "$entry" | sed -E 's/^[Nn][Oo][Nn][Ee][[:space:]]+[Ss][Ee][Ll][Ee][Cc][Tt][Ee][Dd]//')"
        
        # If there's a suffix, it MUST match the separator+rationale pattern
        if [ -n "$(printf '%s' "$suffix" | tr -d '[:space:]')" ]; then
            local rationale
            # Parse separator explicitly using actual UTF-8 bytes (Bash 3.2 compatible)
            local em_dash=$'\xe2\x80\x94'
            local en_dash=$'\xe2\x80\x93'
            case "$suffix" in
                " $em_dash "*) rationale="${suffix# $em_dash }" ;;
                " $en_dash "*) rationale="${suffix# $en_dash }" ;;
                " - "*) rationale="${suffix# - }" ;;
                "- "*) rationale="${suffix#- }" ;;
                " $em_dash"*) rationale="${suffix# $em_dash}" ;;
                " $en_dash"*) rationale="${suffix# $en_dash}" ;;
                " -"*) rationale="${suffix# -}" ;;
                "-$"*) rationale="${suffix#-}" ;;
                *)
                    fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "None selected" "'None selected' must use a separator ( — / – / - ) with surrounding whitespace before rationale: $entry"
                    ;;
            esac
            if ! has_meaningful_char "$rationale"; then
                fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "None selected" "'None selected' carries a separator but no rationale."
            fi
            if is_placeholder_text "$rationale" && [ "$STATUS" = "done" ]; then
                fail_blocked "MODULE_SELECTION_UNRESOLVED" "## Context modules" "None selected" "Completed task carries an unresolved 'None selected' rationale placeholder."
            fi
        fi
        NONE_SENTINEL_SEEN=1
        return 0
    fi

    SELECTION_COUNT=$((SELECTION_COUNT + 1))

    # Canonical grammar (ADR-0010): <id> v<N> loaded — <rationale>
    # Requires exactly: valid id, version, lowercase 'loaded', a separator
    # (em dash / en dash / hyphen) and a substantive rationale.
    local id="" ver="" loaded_token="" rest="" separator=""
    id="$(printf '%s' "$entry" | awk '{print $1}')"
    ver="$(printf '%s' "$entry" | awk '{print $2}')"
    loaded_token="$(printf '%s' "$entry" | awk '{print $3}')"

    # Parse the separator explicitly using actual UTF-8 bytes (Bash 3.2 compatible)
    local after_loaded
    after_loaded="$(printf '%s' "$entry" | sed -E 's/^[^[:space:]]+[[:space:]]+v[1-9][0-9]*[[:space:]]+loaded[[:space:]]+//')"
    local em_dash=$'\xe2\x80\x94'
    local en_dash=$'\xe2\x80\x93'
    case "$after_loaded" in
        "$em_dash "*) rest="${after_loaded#$em_dash }" ;;
        "$en_dash "*) rest="${after_loaded#$en_dash }" ;;
        "- "*) rest="${after_loaded#- }" ;;
        *)
            fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "$entry" "Selection entry is not in the canonical form '<module-id> v<N> loaded — <rationale>': $entry"
            ;;
    esac

    local sep_rationale
    sep_rationale="$rest"

    if [ "$loaded_token" != "loaded" ]; then
        fail_invalid "MODULE_SELECTION_UNRESOLVED" "## Context modules" "$id" "Selection of '$id' does not confirm the module was loaded before planning."
    fi

    local idx
    idx="$(registry_index_of "$id" || true)"
    if [ -z "$idx" ]; then
        fail_invalid "MODULE_UNKNOWN" "## Context modules" "$id" "Selected module '$id' is not in the managed registry."
    fi

    local reg_ver="${REG_VERSIONS[$idx]}"
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
        *) printf '%s' -1 ;;
    esac
}

check_profile_floor() {
    local p_rank m_rank i idx id min_profile
    p_rank="$(profile_rank "$PROFILE")"
    [ "$p_rank" -lt 0 ] && return 0
    for i in "${!SELECTED_IDS[@]}"; do
        id="${SELECTED_IDS[$i]}"
        idx="$(registry_index_of "$id" || true)"
        [ -z "$idx" ] && continue
        min_profile="${REG_MINS[$idx]}"
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

# The minimum-profile floor is part of this validator's contract, so it can
# only be evaluated against exactly one recognized profile declaration. A
# missing, unknown, or duplicated profile is INVALID before any selection is
# examined — JSON results are never VALID with a null profile.
if [ "$PROFILE_COUNT" -ne 1 ]; then
    fail_invalid "CONTEXT_PROFILE_INVALID" "## Risk profile" "" "Task must declare exactly one risk profile (found $PROFILE_COUNT declarations)."
fi
case "$PROFILE" in
    prototype|standard|high-assurance) ;;
    *)
        fail_invalid "CONTEXT_PROFILE_INVALID" "## Risk profile" "$PROFILE" "'$PROFILE' is not a recognized risk profile (prototype | standard | high-assurance)."
        ;;
esac

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
    # The successful leg is checked exactly like the failure legs: a failed
    # serialization (closed stdout, full disk, hostile payload) must never
    # masquerade as a VALID run with no result document.
    serialized=""
    serialized="$(AGENTIC_SELECTED="$SELECTED_PAYLOAD" python3 -c '
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
' "$(display_path "$TASK_FILE")" "${PROFILE:-}" "$( [ "$HANDOFF" -eq 1 ] && echo handoff || echo standard )")" || {
        echo "ERROR: failed to serialize JSON result." >&2
        exit 1
    }
    if ! printf '%s\n' "$serialized"; then
        echo "ERROR: failed to write JSON result." >&2
        exit 1
    fi
else
    echo "VALID: context selections ok ($( [ "$NONE_SENTINEL_SEEN" -eq 1 ] && echo 'none selected' || { printf '%s' "${SELECTED_IDS[*]}"; } ))"
fi
exit 0
