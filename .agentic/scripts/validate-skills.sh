#!/usr/bin/env bash
#
# validate-skills.sh — structural validator for skill invocations in
# agentic task files.
#
# Validates only structural facts about the `## Skills` section of a
# task file against the managed registry under `.agentic/skills/`:
#   - every invoked skill exists in the registry
#   - no duplicate skill IDs
#   - every invocation carries a real rationale
#   - the task's risk profile satisfies each skill's minimum profile
#   - a completed task has no unresolved invocation placeholders
#   - the `None required` sentinel never coexists with invocations
#   - invocation versions are recognized by the registry
#
# The registry itself is validated before use: a skill's declared ID must
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
#   ./validate-skills.sh [--format text|json] [--handoff] path/to/TASK-001.md
#
# Environment:
#   AGENTIC_SKILLS_REGISTRY   Override the registry directory (tests). Defaults
#                             to the `skills/` directory beside this script.

set -uo pipefail

FORMAT="text"
HANDOFF=0
TASK_FILE=""

usage() {
    cat <<'EOF'
Usage: validate-skills.sh [--format text|json] [--handoff] <task-file>

Validates the skill-invocation contract of an agentic task file.

Options:
  --format    Output format: text (default) or json.
  --handoff   Require Status: done and enforce the completion gate.
  -h, --help  Show this help.

Exit codes:
  0  VALID
  1  INVALID
  2  BLOCKED — unresolved invocation at completion, or unusable registry
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
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
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
if [ -n "${AGENTIC_SKILLS_REGISTRY:-}" ]; then
    REGISTRY="$AGENTIC_SKILLS_REGISTRY"
else
    REGISTRY="$SCRIPT_DIR/../skills"
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

output_skill_json() {
    # res_str exit_code msg [code] [section] [ident]
    local res_str="$1" exit_code="$2" msg="$3" code="${4:-SKILL_UNKNOWN}" section="${5:-null}" ident="${6:-null}"
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
    "protocol_version": "1.11.0",
    "kind": "skill_validation_result",
    "mode": mode,
    "result": res_str,
    "exit_code": exit_code,
    "task_file": task_file,
    "profile": profile_out,
    "invoked_skills": [],
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
            "SKILLS_SECTION_MISSING")
                json_msg="Task file is missing the required '## Skills' section." ;;
            "SKILLS_PROFILE_INVALID")
                json_msg="Task must declare exactly one recognized risk profile." ;;
            "SKILL_UNKNOWN")
                json_msg="Invoked skill is not in the managed registry." ;;
            "SKILL_VERSION_UNSUPPORTED")
                json_msg="Invocation declares an unsupported skill version." ;;
            "SKILL_RATIONALE_MISSING")
                json_msg="Invocation must carry an invocation rationale." ;;
            "SKILL_DUPLICATE")
                json_msg="Skill is invoked more than once." ;;
            "SKILL_PROFILE_TOO_LOW")
                json_msg="Task profile is below the minimum required by the invoked skill." ;;
            "SKILL_SELECTION_UNRESOLVED")
                json_msg="Skill invocation does not match the required structure." ;;
            *)
                json_msg="Structural contract violation." ;;
        esac
        output_skill_json "INVALID" 1 "$json_msg" "$code" "$section" "$json_ident"
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
            "SKILLS_REGISTRY_MISSING")
                json_msg="Skills registry not found." ;;
            "SKILLS_REGISTRY_INVALID")
                json_msg="Skills registry is unusable." ;;
            "SKILL_SELECTION_UNRESOLVED")
                json_msg="Completed task carries an unresolved invocation placeholder." ;;
            "TOOLING_UNAVAILABLE")
                json_msg="Tooling required to classify content is unavailable." ;;
            *)
                json_msg="Completion gate not satisfied." ;;
        esac
        output_skill_json "BLOCKED" 2 "$json_msg" "$code" "$section" "$json_ident"
        exit 2
    else
        echo "BLOCKED: $msg" >&2
        exit 2
    fi
}

if [ ! -f "$TASK_FILE" ]; then
    fail_invalid "SKILLS_SECTION_MISSING" "" "" "Task file was not found: $(display_path "$TASK_FILE")"
fi

# ---------------------------------------------------------------------------
# Registry validation. Every skill becomes one structured record:
#   REG_DIRS[i]   containing directory name
#   REG_IDS[i]    declared ID (must equal the directory name)
#   REG_VERSIONS  declared positive-integer Version
#   REG_MINS[i]   declared Minimum risk profile (recognized)
# A registry that violates any identity or metadata rule is rejected whole
# (SKILLS_REGISTRY_INVALID, BLOCKED): an untrusted registry must never be
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
        || fail_blocked "TOOLING_UNAVAILABLE" "" "" "perl is required to classify non-ASCII content; install perl or keep evidence ASCII-only."
    perl -CS -0777 -ne 'exit(/[\p{L}\p{N}]/ ? 0 : 1)' <<< "$1" 2>/dev/null
}

registry_invalid() {
    fail_blocked "SKILLS_REGISTRY_INVALID" "registry" "${2:-}" "Skills registry is unusable: $1"
}

load_registry() {
    if [ ! -d "$REGISTRY" ]; then
        fail_blocked "SKILLS_REGISTRY_MISSING" "" "" "Skills registry not found: $(basename "$REGISTRY")"
        return
    fi
    local dir mf dirname line current id ver min
    local id_n ver_n min_n lw_n rc_n ag_n re_n ps_n
    local lw_c rc_c ag_c re_c ps_c
    for dir in "$REGISTRY"/*/ ; do
        [ -d "$dir" ] || continue
        mf="${dir}SKILL.md"
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
                "## invoked when")             current="lw";     lw_n=$((lw_n + 1)); continue ;;
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
                    "Invoked when:$lw_n" "Required context:$rc_n" \
                    "Approval gates:$ag_n" "Required evidence:$re_n" \
                    "Prohibited shortcuts:$ps_n"; do
            count="${pair##*:}"
            case "$count" in
                0)
                    registry_invalid "skill '$dirname' is missing its '${pair%%:*}' section." "$dirname"
                    return
                    ;;
                1) ;;
                *)
                    registry_invalid "skill '$dirname' declares heading '${pair%%:*}' more than once." "$dirname"
                    return
                    ;;
            esac
        done

        if ! printf '%s' "$id" | grep -Eq "$REG_ID_PATTERN"; then
            registry_invalid "skill '$dirname' declares ID '$id', which does not match $REG_ID_PATTERN." "$dirname"
            return
        fi
        if [ "$id" != "$dirname" ]; then
            registry_invalid "skill '$dirname' declares ID '$id' that differs from its directory name." "$dirname"
            return
        fi
        local seen
        for seen in "${REG_IDS[@]:-}"; do
            if [ "$seen" = "$id" ]; then
                registry_invalid "skill ID '$id' is declared more than once." "$dirname"
                return
            fi
        done
        if ! printf '%s' "$ver" | grep -Eq '^[1-9][0-9]*$'; then
            registry_invalid "skill '$dirname' declares an unsupported Version ('$ver')." "$dirname"
            return
        fi
        case "$min" in
            prototype|standard|high-assurance) ;;
            *)
                registry_invalid "skill '$dirname' declares missing or unrecognized Minimum risk profile ('$min')." "$dirname"
                return
                ;;
        esac
        if [ "$lw_c" -eq 0 ] || [ "$rc_c" -eq 0 ] || [ "$ag_c" -eq 0 ] ||
           [ "$re_c" -eq 0 ] || [ "$ps_c" -eq 0 ]; then
            registry_invalid "skill '$dirname' is missing substantive content under one of: Invoked when, Required context, Approval gates, Required evidence, Prohibited shortcuts." "$dirname"
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
    n="$(printf '%s' "$1" | sed -E -e 's/^[[:space:]]*[-*+][[:space:]]+//' -e 's/[[:space:].!?;:,-]*$//' -e 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
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
                continue
                ;;
            "status:"*)
                STATUS="$(printf '%s' "$line" | sed -e 's/^[Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]*//' | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
                continue
                ;;
            '## '*)
                if [ "$in_section" -eq 1 ]; then
                    in_section=0
                fi
                if [ "$norm" = "## skills" ]; then
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

INVOCATION_COUNT=0
NONE_SENTINEL_SEEN=0
declare -a INVOKED_IDS=()
declare -a INVOKED_VERSIONS=()

parse_invocation_line() {
    local raw="$1"
    printf '%s' "$raw" | sed -E -e 's/^[[:space:]]*[-*+][[:space:]]+//'
}

handle_entry() {
    local entry="$1"

    if [ -z "${entry//[[:space:]]/}" ]; then
        return 0
    fi

    # Sentinel: '- None required' optionally followed by '— <why>'. A suffix
    # must be a substantive rationale: symbol-only separators are malformed,
    # and placeholder suffixes (TBD/TODO/Pending/...) block a completed task.
    # Requires word-boundary after 'required' to reject 'requiredness' etc.
    # Anchored grammar: ^none\s+required(?:\s+[—–-]\s+.+)?$
    local lowered
    lowered="$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')"
    # First check: must start with "none required" followed by end-of-string or whitespace+separator
    if ! printf '%s' "$lowered" | grep -qE '^none[[:space:]]+required($|[[:space:]]+)'; then
        # Not a sentinel line - but check if it's a malformed "none required" variant
        if printf '%s' "$lowered" | grep -qE '^none[[:space:]]+required'; then
            fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "$entry" "'None required' must be followed by end-of-line or a separator ( — / – / - ) with surrounding whitespace: $entry"
        fi
    else
        # It starts with "none required" - now validate the full grammar
        local suffix
        suffix="$(printf '%s' "$entry" | sed -E 's/^[Nn][Oo][Nn][Ee][[:space:]]+[Rr][Ee][Qq][Uu][Ii][Rr][Ee][Dd]//')"
        
        # If there's a suffix, it MUST match the separator+rationale pattern:
        # whitespace, one separator (—/–/-), whitespace, then a substantive
        # rationale (anchored grammar ^none\s+required(?:\s+[—–-]\s+.+)?$).
        if [ -n "$(printf '%s' "$suffix" | tr -d '[:space:]')" ]; then
            local rationale="" leading_ws="" after_ws="" sep="" after_sep="" sep_tail_ws=""
            # Strip the leading whitespace run with parameter expansion so the
            # separator check is locale- and byte-independent (no sed brackets
            # over multibyte UTF-8, which breaks under MSYS/C locales).
            leading_ws="${suffix%%[![:space:]]*}"
            [ -n "$leading_ws" ] || fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "None required" "'None required' must use a separator ( — / – / - ) with surrounding whitespace before rationale: $entry"
            after_ws="${suffix#"$leading_ws"}"
            local em_dash=$'\xe2\x80\x94'
            local en_dash=$'\xe2\x80\x93'
            case "$after_ws" in
                "$em_dash"*) sep="$em_dash" ;;
                "$en_dash"*) sep="$en_dash" ;;
                "-"*) sep="-" ;;
                *)
                    fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "None required" "'None required' must use a separator ( — / – / - ) with surrounding whitespace before rationale: $entry"
                    ;;
            esac
            after_sep="${after_ws#"$sep"}"
            sep_tail_ws="${after_sep%%[![:space:]]*}"
            if [ -z "$sep_tail_ws" ]; then
                fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "None required" "'None required' carries a separator but no rationale."
            fi
            rationale="${after_sep#"$sep_tail_ws"}"
            if ! has_meaningful_char "$rationale"; then
                fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "None required" "'None required' carries a separator but no rationale."
            fi
            if is_placeholder_text "$rationale" && [ "$STATUS" = "done" ]; then
                fail_blocked "SKILL_SELECTION_UNRESOLVED" "## Skills" "None required" "Completed task carries an unresolved 'None required' rationale placeholder."
            fi
        fi
        NONE_SENTINEL_SEEN=1
        return 0
    fi

    INVOCATION_COUNT=$((INVOCATION_COUNT + 1))

    # Canonical grammar (ADR-0014): <id> v<N> invoked — <rationale>
    # Requires exactly: valid id, version, lowercase 'invoked', a separator
    # (em dash / en dash / hyphen) and a substantive rationale.
    local id="" ver="" invoked_token="" rest=""
    id="$(printf '%s' "$entry" | awk '{print $1}')"
    ver="$(printf '%s' "$entry" | awk '{print $2}')"
    invoked_token="$(printf '%s' "$entry" | awk '{print $3}')"

    # Parse the separator explicitly using actual UTF-8 bytes (Bash 3.2 compatible)
    local after_invoked
    after_invoked="$(printf '%s' "$entry" | sed -E 's/^[^[:space:]]+[[:space:]]+v[1-9][0-9]*[[:space:]]+invoked[[:space:]]+//')"
    local em_dash=$'\xe2\x80\x94'
    local en_dash=$'\xe2\x80\x93'
    case "$after_invoked" in
        "$em_dash "*) rest="${after_invoked#$em_dash }" ;;
        "$en_dash "*) rest="${after_invoked#$en_dash }" ;;
        "- "*) rest="${after_invoked#- }" ;;
        *)
            fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "$entry" "Invocation entry is not in the canonical form '<skill-id> v<N> invoked — <rationale>': $entry"
            ;;
    esac

    local sep_rationale
    sep_rationale="$rest"

    if [ "$invoked_token" != "invoked" ]; then
        fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "$id" "Invocation of '$id' does not confirm the skill was invoked for this task."
    fi

    local idx
    idx="$(registry_index_of "$id" || true)"
    if [ -z "$idx" ]; then
        fail_invalid "SKILL_UNKNOWN" "## Skills" "$id" "Invoked skill '$id' is not in the managed registry."
    fi

    local reg_ver="${REG_VERSIONS[$idx]}"
    if [ "${ver#v}" != "$reg_ver" ]; then
        fail_invalid "SKILL_VERSION_UNSUPPORTED" "## Skills" "$id" "Invocation of '$id' declares version '${ver#v}' but the registry provides '$reg_ver'."
    fi

    if ! has_meaningful_char "$sep_rationale"; then
        fail_invalid "SKILL_RATIONALE_MISSING" "## Skills" "$id" "Invocation of '$id' must carry an invocation rationale."
    fi

    if is_placeholder_text "$sep_rationale"; then
        if [ "$STATUS" = "done" ]; then
            fail_blocked "SKILL_SELECTION_UNRESOLVED" "## Skills" "$id" "Completed task carries an unresolved rationale placeholder for '$id'."
        fi
    fi

    local seen
    for seen in "${INVOKED_IDS[@]:-}"; do
        if [ "$seen" = "$id" ]; then
            fail_invalid "SKILL_DUPLICATE" "## Skills" "$id" "Skill '$id' is invoked more than once."
        fi
    done

    INVOKED_IDS+=("$id")
    INVOKED_VERSIONS+=("${ver#v}")
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
    for i in "${!INVOKED_IDS[@]}"; do
        id="${INVOKED_IDS[$i]}"
        idx="$(registry_index_of "$id" || true)"
        [ -z "$idx" ] && continue
        min_profile="${REG_MINS[$idx]}"
        m_rank="$(profile_rank "$min_profile")"
        if [ "$m_rank" -ge 0 ] && [ "$p_rank" -lt "$m_rank" ]; then
            fail_invalid "SKILL_PROFILE_TOO_LOW" "## Skills" "$id" "Task profile '$PROFILE' is below the '$min_profile' minimum required by skill '$id'."
        fi
    done
}

load_registry
scan_task_file

if [ "$HANDOFF" -eq 1 ] && [ "$STATUS" != "done" ]; then
    fail_invalid "SKILLS_SECTION_MISSING" "## Status" "" "--handoff requires 'Status: done'; found '${STATUS:-<none>}'."
fi

if [ "$SECTION_FOUND" -ne 1 ]; then
    fail_invalid "SKILLS_SECTION_MISSING" "## Skills" "" "Task file has no '## Skills' section."
fi

# The minimum-profile floor is part of this validator's contract, so it can
# only be evaluated against exactly one recognized profile declaration. A
# missing, unknown, or duplicated profile is INVALID before any invocation is
# examined — JSON results are never VALID with a null profile.
if [ "$PROFILE_COUNT" -ne 1 ]; then
    fail_invalid "SKILLS_PROFILE_INVALID" "## Risk profile" "" "Task must declare exactly one risk profile (found $PROFILE_COUNT declarations)."
fi
case "$PROFILE" in
    prototype|standard|high-assurance) ;;
    *)
        fail_invalid "SKILLS_PROFILE_INVALID" "## Risk profile" "$PROFILE" "'$PROFILE' is not a recognized risk profile (prototype | standard | high-assurance)."
        ;;
esac

for raw in "${SECTION_LINES[@]}"; do
    entry="$(parse_invocation_line "$raw")"
    handle_entry "$entry"
done

if [ "$INVOCATION_COUNT" -eq 0 ] && [ "$NONE_SENTINEL_SEEN" -eq 0 ]; then
    fail_invalid "SKILLS_SECTION_MISSING" "## Skills" "" "'## Skills' records neither an invocation nor the 'None required' sentinel."
fi

if [ "$NONE_SENTINEL_SEEN" -eq 1 ] && [ "$INVOCATION_COUNT" -gt 0 ]; then
    fail_invalid "SKILL_SELECTION_UNRESOLVED" "## Skills" "None required" "'None required' cannot coexist with invoked skills."
fi

check_profile_floor

if [ "$FORMAT" = "json" ]; then
    # Invoked skills travel through an environment variable so no unquoted
    # expansion ever word-splits ids or versions (ShellCheck-clean by design).
    INVOKED_PAYLOAD=""
    _i=0
    while [ "$_i" -lt "${#INVOKED_IDS[@]}" ]; do
        INVOKED_PAYLOAD="$INVOKED_PAYLOAD ${INVOKED_IDS[$_i]}:${INVOKED_VERSIONS[$_i]}"
        _i=$((_i + 1))
    done
    # The successful leg is checked exactly like the failure legs: a failed
    # serialization (closed stdout, full disk, hostile payload) must never
    # masquerade as a VALID run with no result document.
    serialized=""
    serialized="$(AGENTIC_INVOKED="$INVOKED_PAYLOAD" python3 -c '
import json, os, sys
task_file = sys.argv[1]
profile = sys.argv[2] if sys.argv[2] in ("prototype", "standard", "high-assurance") else None
mode = sys.argv[3]
invoked = []
for chunk in os.environ.get("AGENTIC_INVOKED", "").split():
    mid, _, mver = chunk.partition(":")
    invoked.append({"id": mid, "version": int(mver)})
doc = {
    "schema_version": 1,
    "protocol_version": "1.11.0",
    "kind": "skill_validation_result",
    "mode": mode,
    "result": "VALID",
    "exit_code": 0,
    "task_file": task_file,
    "profile": profile,
    "invoked_skills": invoked,
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
    echo "VALID: skill invocations ok ($( [ "$NONE_SENTINEL_SEEN" -eq 1 ] && echo 'none required' || { printf '%s' "${INVOKED_IDS[*]}"; } ))"
fi
exit 0
