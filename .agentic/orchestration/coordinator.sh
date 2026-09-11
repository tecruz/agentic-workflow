#!/usr/bin/env bash
# coordinator.sh — isolated multi-agent task coordination (ADR-0011).
#
# Provides isolated worktree creation, generic worker spawning, observable
# JSONL events and versioned result contracts, with explicit approval gates.
#
# Usage:
#   .agentic/orchestration/coordinator.sh [options] <task-file>
#
# Options:
#   --worker <cmd>        Worker command to execute inside the worktree.
#                         Falls back to AGENTIC_WORKER_CMD environment variable.
#   --approve             Approve spawning workers (required; paired with a
#                         checked AG-N gate in the task file).
#   --push                Approve remote writes (requires --approve).
#   --cleanup             Remove the worktree after successful completion.
#   --format <text|json>  Output format (default text). In json mode, stdout
#                         contains exclusively one JSON document.
#   --events <path>       JSONL event stream destination (must be under
#                         .agentic/runs/). Cannot be combined with --format json.
#   --events-force        Overwrite existing event file.
#   --sandbox <type>      Worker sandbox mode: none (default), docker, podman.
#                         Falls back to AGENTIC_WORKER_SANDBOX env var.
#   --sandbox-image <img> Custom container image for sandbox mode.
#                         Falls back to AGENTIC_WORKER_SANDBOX_IMAGE env var.
#   --review              Run task validators (validate-task/context/skills) after
#                         the worker completes; fails the run on validation errors.
#   --hooks <dir>         Directory of hook scripts invoked at lifecycle events:
#                         pre-spawn, post-worker, post-review. Each hook receives
#                         the task file path as $1 and the worktree as $2.
#   --traceparent <tp>    W3C Trace Context parent (traceparent header value).
#                         Falls back to TRACEPARENT env var. Propagated into all
#                         JSONL events as trace_id / span_id fields.
#   -h, --help            Show usage.
#
# Exit codes:
#   0  PASS — worker(s) succeeded
#   1  FAIL — worker(s) failed or invalid input
#   2  BLOCKED — approval missing, tooling unavailable, or lock contention
#
# Security:
#   Never emits raw command lines, arguments, environment, or absolute user-home
#   paths in observable events or JSON results. Working directories are
#   project-relative or basenames.

set -uo pipefail

PROTOCOL_VERSION="1.14.0"
FORMAT="text"
EVENTS_FILE=""
EVENTS_FORCE=0
APPROVE=0
PUSH=0
CLEANUP=0
WORKER_CMD=""
TASK_FILE=""
TASK_ID=""
WORKTREE_REL=""
WORKTREE_ABS=""
LOCK_FILE=""
PROJECT_ROOT=""
SANDBOX="none"
SANDBOX_IMAGE=""
REVIEW=0
HOOKS_DIR=""
TRACE_ID=""
SPAN_ID=""
TRACE_FLAGS="01"

# Event stream scratch (for atomic promotion)
EVENTS_SCRATCH=""

usage() {
    cat <<'EOF'
Usage: coordinator.sh [options] <task-file>

Isolated multi-agent task coordination (ADR-0011).

Options:
  --worker <cmd>        Worker command to run inside the worktree
                        (falls back to AGENTIC_WORKER_CMD env var)
  --approve             Approve spawning workers (requires checked AG-N gate)
  --push                Approve remote writes (requires --approve)
  --cleanup             Remove worktree after completion
  --format <text|json>  Output format (default text)
  --events <path>       JSONL event stream (must be under .agentic/runs/)
  --events-force        Overwrite existing event file
  --sandbox <type>      Worker sandbox mode: none (default), docker, podman
                        (falls back to AGENTIC_WORKER_SANDBOX env var)
  --sandbox-image <img> Custom container image for sandbox mode
                        (falls back to AGENTIC_WORKER_SANDBOX_IMAGE env var)
  --review              Run task validators after worker completes
  --hooks <dir>         Hook scripts directory (pre-spawn, post-worker, post-review)
  --traceparent <tp>    W3C Trace Context parent (falls back to TRACEPARENT env var)
  -h, --help            Show this help

Exit codes:
  0  PASS
  1  FAIL / INVALID
  2  BLOCKED (approval, tooling, lock)
EOF
}

# Helpers: logging, JSON escaping, path redaction, confinement

log() {
    if [ "$FORMAT" = "json" ]; then
        printf '%s\n' "$*" >&2
    else
        printf '%s\n' "$*"
    fi
}

now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local _sec="${EPOCHREALTIME%%.*}" _frac="${EPOCHREALTIME#*.}000"
        printf '%s%s' "$_sec" "${_frac:0:3}"
        return
    fi
    local _d
    _d="$(date +%s%3N 2>/dev/null)" || _d=""
    if [[ "$_d" =~ ^[0-9]+$ ]]; then
        printf '%s' "$_d"
        return
    fi
    printf '%d' "$((SECONDS * 1000))"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    local result="" i len ch ascii
    len="${#s}"
    for (( i = 0; i < len; i++ )); do
        ch="${s:i:1}"
        ascii=$(printf '%d' "'$ch" 2>/dev/null || echo 0)
        if ! [[ "$ascii" =~ ^[0-9]+$ ]] || [ "$ascii" -gt 255 ]; then
            result+="$ch"
        elif [ "$ascii" -lt 32 ] && [ "$ascii" -ne 9 ] && [ "$ascii" -ne 10 ] && [ "$ascii" -ne 13 ]; then
            result+="$(printf '\\u%02x' "$ascii")"
        else
            result+="$ch"
        fi
    done
    printf '%s' "${result:-$s}"
}

display_path() {
    local p="$1"
    local norm="${p//\\//}"
    norm="${norm#./}"
    if [ -n "$PROJECT_ROOT" ]; then
        case "$norm" in
            "$PROJECT_ROOT") printf '.'; return ;;
            "$PROJECT_ROOT"/*) printf './%s' "${norm#"$PROJECT_ROOT"/}"; return ;;
        esac
    else
        case "$norm" in
            "$(pwd -P)") printf '.'; return ;;
            "$(pwd -P)"/*) printf './%s' "${norm#"$(pwd -P)"/}"; return ;;
        esac
    fi
    case "$norm" in
        /*|[A-Za-z]:*) printf '%s' "$(basename "$norm")"; return ;;
    esac
    printf '%s' "$norm"
}

normalize_project_rel() {
    local p="${1#./}" seg out=""
    local -a segs=()
    IFS='/' read -r -a segs <<< "$p"
    if [ "${#segs[@]}" -gt 0 ]; then
        for seg in "${segs[@]}"; do
            case "$seg" in
                ''|.) ;;
                ..) out="${out%/*}" ;;
                *) out="$out/$seg" ;;
            esac
        done
    fi
    if [ -n "$out" ]; then
        printf '%s' "./${out#/}"
    else
        printf '%s' "."
    fi
}

lexically_within_root() {
    local path="$1"
    case "$path" in
        /*) return 1 ;;
    esac
    local -a segs=()
    local -i top=0
    local seg
    while [ -n "$path" ]; do
        case "$path" in
            */*) seg="${path%%/*}"; path="${path#*/}" ;;
            *) seg="$path"; path="" ;;
        esac
        case "$seg" in
            '' | '.') ;;
            '..')
                if [ "$top" -gt 0 ]; then
                    top=$((top - 1))
                else
                    return 1
                fi ;;
            *)
                segs[$top]="$seg"
                top=$((top + 1))
                ;;
        esac
    done
    return 0
}

safe_detect_destination() {
    local leaf="$1" parent resolved resolved_root
    while [ ! -e "$leaf" ] && [ ! -L "$leaf" ]; do
        parent="$(dirname "$leaf")"
        [ "$parent" = "$leaf" ] && break
        leaf="$parent"
    done
    if [ -L "$leaf" ]; then
        return 1
    fi
    resolved="$(cd "$(dirname "$leaf")" 2>/dev/null && pwd -P)" || return 1
    resolved_root="$(pwd -P)"
    case "$resolved" in
        "$resolved_root" | "$resolved_root/"*) return 0 ;;
    esac
    return 1
}

safe_events_destination() {
    local dest="$1" normalized segment
    dest="${dest//\\//}"
    case "$dest" in
        /*) return 1 ;;
    esac
    normalized="${dest#./}"
    case "$normalized" in
        .agentic/runs/*) ;;
        *) return 1 ;;
    esac
    local IFS='/'
    read -ra _segs <<< "$normalized"
    for segment in "${_segs[@]}"; do
        case "$segment" in
            ''|.|..) return 1 ;;
        esac
    done
    safe_detect_destination "$normalized"
}

safe_worktree_destination() {
    local dest="$1" normalized segment
    dest="${dest//\\//}"
    case "$dest" in
        /*) return 1 ;;
    esac
    normalized="${dest#./}"
    case "$normalized" in
        .agentic/orchestration/worktrees/*) ;;
        *) return 1 ;;
    esac
    local IFS='/'
    read -ra _segs <<< "$normalized"
    for segment in "${_segs[@]}"; do
        case "$segment" in
            ''|.|..) return 1 ;;
        esac
    done
    # Worktree path may not exist yet; check parent physically.
    safe_detect_destination "$normalized"
}

# Event emission (writes to EVENTS_FILE when set)

write_event() {
    local payload="$1"
    if [ -n "$EVENTS_FILE" ]; then
        printf '%s\n' "$payload" >> "$EVENTS_FILE" || return 1
    fi
    return 0
}

emit_orchestration_started() {
    local trace_json=""
    if [ -n "$TRACE_ID" ]; then
        trace_json=",\"trace_id\":\"$(json_escape "$TRACE_ID")\",\"span_id\":\"$(json_escape "$SPAN_ID")\""
    fi
    write_event "{\"event\":\"orchestration_started\"${trace_json}}"
}

emit_worker_started() {
    local worker_id="$1" cwd_rel="$2"
    local esc_id esc_cwd
    esc_id="$(json_escape "$worker_id")"
    esc_cwd="$(json_escape "$cwd_rel")"
    local trace_json=""
    if [ -n "$TRACE_ID" ]; then
        trace_json=",\"trace_id\":\"$(json_escape "$TRACE_ID")\",\"span_id\":\"$(json_escape "$SPAN_ID")\""
    fi
    local payload="{\"event\":\"worker_started\",\"worker_id\":\"$esc_id\",\"working_directory\":\"$esc_cwd\"${trace_json}}"
    write_event "$payload"
}

emit_worker_completed() {
    local worker_id="$1" status="$2" exit_code="$3" duration_ms="$4" cwd_rel="$5" reason_code="$6"
    local esc_id esc_cwd esc_rcode esc_ec
    esc_id="$(json_escape "$worker_id")"
    esc_cwd="$(json_escape "$cwd_rel")"
    if [ -n "$reason_code" ] && [ "$reason_code" != "null" ]; then
        esc_rcode="\"$(json_escape "$reason_code")\""
    else
        esc_rcode="null"
    fi
    if [ -n "$exit_code" ] && [ "$exit_code" != "null" ]; then
        esc_ec="$exit_code"
    else
        esc_ec="null"
    fi
    local trace_json=""
    if [ -n "$TRACE_ID" ]; then
        trace_json=",\"trace_id\":\"$(json_escape "$TRACE_ID")\",\"span_id\":\"$(json_escape "$SPAN_ID")\""
    fi
    local payload="{\"event\":\"worker_completed\",\"worker_id\":\"$esc_id\",\"status\":\"$status\",\"exit_code\":$esc_ec,\"duration_ms\":${duration_ms:-0},\"working_directory\":\"$esc_cwd\",\"reason_code\":$esc_rcode${trace_json}}"
    write_event "$payload"
}

emit_orchestration_completed() {
    local result="$1" exit_code="$2"
    local trace_json=""
    if [ -n "$TRACE_ID" ]; then
        trace_json=",\"trace_id\":\"$(json_escape "$TRACE_ID")\",\"span_id\":\"$(json_escape "$SPAN_ID")\""
    fi
    local payload="{\"event\":\"orchestration_completed\",\"result\":\"$result\",\"exit_code\":$exit_code${trace_json}}"
    write_event "$payload"
}

# Output helpers: JSON result and terminal completion

output_orchestration_json() {
    local res_str="$1" exit_code="$2" workers_json="$3" summary_json="$4"
    local task_disp worktree_disp
    task_disp="$(json_escape "$(display_path "$TASK_FILE")")"
    # worktree is project-relative
    local wt_rel
    if [ -n "$WORKTREE_REL" ]; then
        wt_rel="$WORKTREE_REL"
        case "$wt_rel" in
            ./*) : ;;
            *) wt_rel="./$wt_rel" ;;
        esac
    else
        wt_rel="."
    fi
    worktree_disp="$(json_escape "$wt_rel")"
    printf '{"schema_version":1,"protocol_version":"%s","kind":"orchestration_result","result":"%s","exit_code":%d,"task_file":"%s","worktree":"%s","workers":[%s],"summary":%s}\n' \
        "$PROTOCOL_VERSION" "$res_str" "$exit_code" "$task_disp" "$worktree_disp" "$workers_json" "$summary_json"
}

complete_orchestration() {
    local result="$1" exit_code="$2" workers_json="$3" summary_json="$4"
    if [ -n "$EVENTS_FILE" ]; then
        if ! emit_orchestration_completed "$result" "$exit_code"; then
            echo "ERROR: failed to finalize orchestration event stream." >&2
            exit 1
        fi
    fi
    if [ "$FORMAT" = "json" ]; then
        if ! output_orchestration_json "$result" "$exit_code" "$workers_json" "$summary_json"; then
            echo "ERROR: failed to write JSON orchestration result." >&2
            exit 1
        fi
    fi
    # Cleanup lock if not keeping
    exit "$exit_code"
}

fail_with_result() {
    local result="$1" exit_code="$2" msg="$3" reason_code="$4"
    # reason_code is for diagnostics, not directly in orchestration result but in summary
    # For pre-worktree failures, produce minimal workers array (empty or single BLOCKED)
    if [ "$FORMAT" = "json" ]; then
        # Before workers are known, emit empty workers with summary reflecting failure
        local workers_json=""
        local summary_json="{\"workers_defined\":0,\"workers_run\":0,\"passed\":0,\"failed\":0,\"blocked\":1}"
        if [ "$result" = "FAIL" ]; then
            summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":0,\"failed\":1,\"blocked\":0}"
            workers_json="{\"worker_id\":\"$(json_escape "$TASK_ID")\",\"status\":\"FAIL\",\"exit_code\":null,\"duration_ms\":0,\"reason_code\":\"WORKER_FAILED\"}"
        elif [ "$result" = "BLOCKED" ]; then
            summary_json="{\"workers_defined\":0,\"workers_run\":0,\"passed\":0,\"failed\":0,\"blocked\":1}"
            workers_json=""
        fi
        complete_orchestration "$result" "$exit_code" "$workers_json" "$summary_json"
    else
        echo "ERROR: $msg" >&2
        if [ -n "$EVENTS_FILE" ]; then
            emit_orchestration_completed "$result" "$exit_code" 2>/dev/null || true
        fi
        exit "$exit_code"
    fi
}

# Argument parsing

while [ $# -gt 0 ]; do
    case "$1" in
        --format)
            if [ $# -lt 2 ]; then
                echo "ERROR: --format requires a value ('text' or 'json')." >&2
                exit 1
            fi
            FORMAT="$2"
            shift 2
            ;;
        --format=*)
            FORMAT="${1#*=}"
            shift
            ;;
        --events)
            if [ $# -lt 2 ]; then
                echo "ERROR: --events requires a file path." >&2
                exit 1
            fi
            EVENTS_FILE="$2"
            shift 2
            ;;
        --events=*)
            EVENTS_FILE="${1#*=}"
            shift
            ;;
        --events-force)
            EVENTS_FORCE=1
            shift
            ;;
        --approve)
            APPROVE=1
            shift
            ;;
        --push)
            PUSH=1
            shift
            ;;
        --cleanup)
            CLEANUP=1
            shift
            ;;
        --sandbox)
            if [ $# -lt 2 ]; then
                echo "ERROR: --sandbox requires a value ('none', 'docker', or 'podman')." >&2
                exit 1
            fi
            SANDBOX="$2"
            shift 2
            ;;
        --sandbox=*)
            SANDBOX="${1#*=}"
            shift
            ;;
        --sandbox-image)
            if [ $# -lt 2 ]; then
                echo "ERROR: --sandbox-image requires an image name." >&2
                exit 1
            fi
            SANDBOX_IMAGE="$2"
            shift 2
            ;;
        --sandbox-image=*)
            SANDBOX_IMAGE="${1#*=}"
            shift
            ;;
        --review)
            REVIEW=1
            shift
            ;;
        --hooks)
            if [ $# -lt 2 ]; then
                echo "ERROR: --hooks requires a directory path." >&2
                exit 1
            fi
            HOOKS_DIR="$2"
            shift 2
            ;;
        --hooks=*)
            HOOKS_DIR="${1#*=}"
            shift
            ;;
        --traceparent)
            if [ $# -lt 2 ]; then
                echo "ERROR: --traceparent requires a W3C Trace Context value." >&2
                exit 1
            fi
            TRACE_ID="$2"
            shift 2
            ;;
        --traceparent=*)
            TRACE_ID="${1#*=}"
            shift
            ;;
        --worker)
            if [ $# -lt 2 ]; then
                echo "ERROR: --worker requires a command." >&2
                exit 1
            fi
            WORKER_CMD="$2"
            shift 2
            ;;
        --worker=*)
            WORKER_CMD="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            if [ $# -gt 0 ]; then
                if [ -n "$TASK_FILE" ]; then
                    echo "ERROR: expected a single task file." >&2
                    exit 1
                fi
                TASK_FILE="$1"
                shift
            fi
            if [ $# -gt 0 ]; then
                echo "ERROR: unexpected argument '$1' after '--'." >&2
                exit 1
            fi
            break
            ;;
        -*)
            echo "ERROR: unknown option '$1'." >&2
            usage >&2
            exit 1
            ;;
        *)
            if [ -n "$TASK_FILE" ]; then
                echo "ERROR: expected a single task file." >&2
                exit 1
            fi
            TASK_FILE="$1"
            shift
            ;;
    esac
done

# Resolve worker from env if not supplied via flag
if [ -z "$WORKER_CMD" ] && [ -n "${AGENTIC_WORKER_CMD:-}" ]; then
    WORKER_CMD="$AGENTIC_WORKER_CMD"
fi

# Resolve sandbox from env if not supplied via flag
if [ "$SANDBOX" = "none" ] && [ -n "${AGENTIC_WORKER_SANDBOX:-}" ]; then
    SANDBOX="$AGENTIC_WORKER_SANDBOX"
fi
if [ -z "$SANDBOX_IMAGE" ] && [ -n "${AGENTIC_WORKER_SANDBOX_IMAGE:-}" ]; then
    SANDBOX_IMAGE="$AGENTIC_WORKER_SANDBOX_IMAGE"
fi

# Resolve traceparent from env if not supplied via flag
if [ -z "$TRACE_ID" ] && [ -n "${TRACEPARENT:-}" ]; then
    TRACE_ID="$TRACEPARENT"
fi

# Parse W3C Trace Context: extract trace_id (bytes 2-33) and span_id (bytes 35-50)
if [ -n "$TRACE_ID" ]; then
    # Format: 00-{trace_id}-{span_id}-{flags}
    _tp="$TRACE_ID"
    case "$_tp" in
        00-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F])
            TRACE_ID="${_tp:3:32}"
            SPAN_ID="${_tp:36:16}"
            TRACE_FLAGS="${_tp:53:2}"
            ;;
        *)
            # Invalid format; clear to avoid bad data in events
            TRACE_ID=""
            SPAN_ID=""
            TRACE_FLAGS="01"
            ;;
    esac
fi

case "$(printf '%s' "$FORMAT" | tr '[:upper:]' '[:lower:]')" in
    text) FORMAT="text" ;;
    json) FORMAT="json" ;;
    *)
        echo "ERROR: --format must be 'text' or 'json'." >&2
        exit 1
        ;;
esac

if [ "$FORMAT" = "json" ] && [ -n "$EVENTS_FILE" ]; then
    echo "ERROR: --format json and --events cannot be used together." >&2
    echo "Use JSON stdout OR an event stream, not both." >&2
    exit 1
fi

if [ "$PUSH" -eq 1 ] && [ "$APPROVE" -ne 1 ]; then
    echo "ERROR: --push requires --approve." >&2
    exit 2
fi

if [ -z "$TASK_FILE" ]; then
    echo "ERROR: task file is required." >&2
    usage >&2
    exit 1
fi

PROJECT_ROOT="$(pwd -P)"

# Task-file existence (redacted display)
if [ ! -f "$TASK_FILE" ]; then
    if [ "$FORMAT" = "json" ]; then
        task_disp="$(json_escape "$(display_path "$TASK_FILE")")"
        printf '{"schema_version":1,"protocol_version":"%s","kind":"orchestration_result","result":"BLOCKED","exit_code":2,"task_file":"%s","worktree":".","workers":[],"summary":{"workers_defined":0,"workers_run":0,"passed":0,"failed":0,"blocked":1}}\n' "$PROTOCOL_VERSION" "$task_disp"
        exit 2
    else
        echo "ERROR: task file not found: $TASK_FILE" >&2
        exit 2
    fi
fi

# Derive TASK_ID from basename without extension
base="$(basename "$TASK_FILE")"
# Strip extension after last dot if present
case "$base" in
    *.*) TASK_ID="${base%.*}" ;;
    *) TASK_ID="$base" ;;
esac
if [ -z "$TASK_ID" ]; then
    echo "ERROR: could not derive task ID from '$TASK_FILE'." >&2
    exit 1
fi
# Validate task ID characters (alphanumeric, dot, dash, underscore)
if ! printf '%s' "$TASK_ID" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
    echo "ERROR: task ID '$TASK_ID' contains invalid characters." >&2
    exit 1
fi

WORKTREE_REL=".agentic/orchestration/worktrees/$TASK_ID"
WORKTREE_ABS="$PROJECT_ROOT/$WORKTREE_REL"
LOCK_FILE="$PROJECT_ROOT/.agentic/orchestration/worktrees/$TASK_ID.lock"

if ! safe_worktree_destination "$WORKTREE_REL"; then
    echo "ERROR: worktree destination is not safely inside the project root." >&2
    exit 1
fi

# Approval gates inspection
# Extract Approval gates section (authoritative, ignoring fenced/comment/blockquote like validators)
# Simplified: find "## Approval gates" heading, then collect until next "## "
approval_content=""
in_gates=0
in_fence=0
in_comment=0
while IFS= read -r line || [ -n "$line" ]; do
    line_nocr="${line%$'\r'}"
    # Handle HTML comments
    if [ "$in_comment" -eq 1 ]; then
        case "$line_nocr" in
            *'-->'*) in_comment=0 ;;
        esac
        continue
    fi
    case "$line_nocr" in
        *'<!--'*)
            case "$line_nocr" in
                *'-->'*) continue ;;
                *) in_comment=1; continue ;;
            esac
            ;;
    esac
    if [ "$in_fence" -eq 1 ]; then
        case "$line_nocr" in
            '```'*) in_fence=0 ;;
        esac
        continue
    fi
    case "$line_nocr" in
        '```'*) in_fence=1; continue ;;
    esac
    if printf '%s' "$line_nocr" | grep -qE '^[[:space:]]*>'; then
        continue
    fi
    case "$line_nocr" in
        '## '*)
            norm="$(printf '%s' "${line_nocr#'## '}" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
            if [ "$norm" = "approval gates" ]; then
                in_gates=1
            else
                if [ "$in_gates" -eq 1 ]; then
                    break
                fi
            fi
            continue
            ;;
    esac
    if [ "$in_gates" -eq 1 ]; then
        approval_content="${approval_content}${line_nocr}
"
    fi
done < "$TASK_FILE"

has_none=0
checked=0
unchecked=0
malformed=0
gate_count=0

if printf '%s' "$approval_content" | grep -qiE '^[[:space:]]*[-*+][[:space:]]*none[[:space:]]+identified'; then
    has_none=1
fi
# Count checked/unchecked AG gates
if printf '%s' "$approval_content" | grep -qE '\[x\].*AG-[0-9]+[[:space:]]*:'; then
    checked=$(printf '%s' "$approval_content" | grep -cE '\[[xX]\][[:space:]]*AG-[0-9]+[[:space:]]*:' || true)
fi
if printf '%s' "$approval_content" | grep -qE '\[ \].*AG-[0-9]+[[:space:]]*:'; then
    unchecked=$(printf '%s' "$approval_content" | grep -cE '\[[ ]\][[:space:]]*AG-[0-9]+[[:space:]]*:' || true)
fi
# gates with AG but malformed
while IFS= read -r ag_line || [ -n "$ag_line" ]; do
    [ -z "$ag_line" ] && continue
    trimmed="$(printf '%s' "$ag_line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//')"
    [ -z "$trimmed" ] && continue
    low="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"
    body_low="$(printf '%s\n' "$low" | sed -E 's/^[-*+][[:space:]]+//; s/[[:space:]]+$//')"
    if [ "$body_low" = "none identified" ]; then
        continue
    fi
    if printf '%s' "$low" | grep -qE '^[-*+][[:space:]]*\[[ xX]\]'; then
        if ! printf '%s' "$low" | grep -qE '^[-*+][[:space:]]*\[[ xX]\][[:space:]]*ag-[0-9]+[[:space:]]*:'; then
            malformed=1
        else
            gate_count=$((gate_count + 1))
        fi
    elif printf '%s' "$low" | grep -qE 'ag-[0-9]+'; then
        # Line mentions AG but not in approved checklist form
        malformed=1
    fi
done <<< "$approval_content"

# Decision: if there are gates, spawning requires --approve and all gates checked
needs_approval=0
if [ "$has_none" -eq 0 ] && [ "$gate_count" -gt 0 ]; then
    needs_approval=1
fi
if [ "$malformed" -eq 1 ]; then
    if [ "$FORMAT" = "json" ]; then
        task_disp="$(json_escape "$(display_path "$TASK_FILE")")"
        printf '{"schema_version":1,"protocol_version":"%s","kind":"orchestration_result","result":"BLOCKED","exit_code":2,"task_file":"%s","worktree":".","workers":[],"summary":{"workers_defined":0,"workers_run":0,"passed":0,"failed":0,"blocked":1}}\n' "$PROTOCOL_VERSION" "$task_disp"
        exit 2
    else
        echo "ERROR: malformed approval gates in task file." >&2
        exit 2
    fi
fi

if [ "$needs_approval" -eq 1 ] || [ "$PUSH" -eq 1 ]; then
    if [ "$APPROVE" -ne 1 ]; then
        fail_with_result "BLOCKED" 2 "spawning workers requires --approve and a checked AG-N gate." "APPROVAL_UNRESOLVED"
    fi
    if [ "$unchecked" -gt 0 ]; then
        fail_with_result "BLOCKED" 2 "task has unchecked approval gates." "APPROVAL_UNRESOLVED"
    fi
fi
if [ "$PUSH" -eq 1 ] && [ "$APPROVE" -ne 1 ]; then
    fail_with_result "BLOCKED" 2 "--push requires --approve." "APPROVAL_UNRESOLVED"
fi

# For spawning without any gate (None identified), still require --approve if worker present
if [ -n "$WORKER_CMD" ] || [ "$PUSH" -eq 1 ]; then
    if [ "$APPROVE" -ne 1 ]; then
        # If has_none, we still require the flag per design "flag is still required"
        fail_with_result "BLOCKED" 2 "spawning workers requires --approve." "APPROVAL_UNRESOLVED"
    fi
fi

# Check git availability for worktree operations
if ! command -v git >/dev/null 2>&1; then
    fail_with_result "BLOCKED" 2 "git is required for isolated worktrees." "TOOLING_UNAVAILABLE"
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail_with_result "BLOCKED" 2 "not inside a git worktree." "TOOLING_UNAVAILABLE"
fi

# Event stream initialization (after validation, before worktree mutation)
if [ -n "$EVENTS_FILE" ]; then
    if ! safe_events_destination "$EVENTS_FILE"; then
        echo "ERROR: events destination must be a relative path inside .agentic/runs/. '$EVENTS_FILE' is not allowed." >&2
        exit 1
    fi
    if [ -e "$EVENTS_FILE" ] && [ ! -f "$EVENTS_FILE" ]; then
        echo "ERROR: event destination exists and is not a regular file." >&2
        exit 1
    fi
    if [ -e "$EVENTS_FILE" ] && [ "$EVENTS_FORCE" -ne 1 ]; then
        echo "ERROR: refusing to overwrite existing event file '$EVENTS_FILE'. Use --events-force to overwrite." >&2
        exit 1
    fi
    mkdir -p "$(dirname "$EVENTS_FILE")"
    events_scratch="$(mktemp "$(dirname "$EVENTS_FILE")/.orchestration-events.XXXXXX")" || exit 1
    EVENTS_SCRATCH="$events_scratch"
    _trace_json=""
    if [ -n "$TRACE_ID" ]; then
        _trace_json=",\"trace_id\":\"$(json_escape "$TRACE_ID")\",\"span_id\":\"$(json_escape "$SPAN_ID")\""
    fi
    if ! printf '{"event":"orchestration_started"%s}\n' "$_trace_json" > "$events_scratch"; then
        echo "ERROR: failed to initialize event stream." >&2
        rm -f "$events_scratch"
        exit 1
    fi
    if [ "$EVENTS_FORCE" -eq 1 ]; then
        if ! mv -f -- "$events_scratch" "$EVENTS_FILE"; then
            echo "ERROR: failed to promote event stream (forced)." >&2
            rm -f "$events_scratch"
            exit 1
        fi
        if [ ! -f "$EVENTS_FILE" ]; then
            echo "ERROR: event promotion produced no regular file." >&2
            rm -f "$events_scratch"
            exit 1
        fi
        EVENTS_SCRATCH=""
    else
        if ! ln "$events_scratch" "$EVENTS_FILE" 2>/dev/null; then
            echo "ERROR: refusing to overwrite existing event file '$EVENTS_FILE'. Use --events-force to overwrite." >&2
            rm -f "$events_scratch"
            exit 1
        fi
        rm -f "$events_scratch"
        EVENTS_SCRATCH=""
    fi
fi

# Cleanup handler for scratch and lock
cleanup_coordinator() {
    rm -f "$EVENTS_SCRATCH" 2>/dev/null || true
}
trap cleanup_coordinator EXIT

# Lock handling (per-task explicit ownership)
mkdir -p "$(dirname "$LOCK_FILE")"
if [ -f "$LOCK_FILE" ]; then
    old_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        fail_with_result "BLOCKED" 2 "task is already locked by PID $old_pid." "WORKER_BLOCKED"
    else
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
fi
# Atomic lock creation via noclobber
if ! (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
    # Fallback: try simple write if noclobber unavailable race
    if [ -f "$LOCK_FILE" ]; then
        fail_with_result "BLOCKED" 2 "task lock contention." "WORKER_BLOCKED"
    else
        echo "$$" > "$LOCK_FILE" 2>/dev/null || {
            fail_with_result "BLOCKED" 2 "failed to acquire task lock." "WORKER_BLOCKED"
        }
    fi
fi

# Worktree creation or reuse
worktree_branch="orchestration/$TASK_ID"
worktree_exists=0
if [ -d "$WORKTREE_ABS" ]; then
    # Reuse if it looks like a worktree (has .git), otherwise treat as stale
    if [ -e "$WORKTREE_ABS/.git" ]; then
        worktree_exists=1
    else
        rm -rf "$WORKTREE_ABS" 2>/dev/null || true
        git worktree prune 2>/dev/null || true
    fi
fi

if [ "$worktree_exists" -eq 0 ]; then
    mkdir -p "$(dirname "$WORKTREE_ABS")"
    # Try to create with new branch; fallback to existing branch
    if git show-ref --verify --quiet "refs/heads/$worktree_branch" 2>/dev/null; then
        if ! git worktree add "$WORKTREE_ABS" "$worktree_branch" >>/dev/null 2>&1; then
            echo "ERROR: failed to create worktree for existing branch." >&2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            fail_with_result "BLOCKED" 2 "worktree creation failed." "TOOLING_UNAVAILABLE"
        fi
    else
        if ! git worktree add -b "$worktree_branch" "$WORKTREE_ABS" >>/dev/null 2>&1; then
            echo "ERROR: failed to create isolated worktree." >&2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            fail_with_result "BLOCKED" 2 "worktree creation failed." "TOOLING_UNAVAILABLE"
        fi
    fi
    log "Created isolated worktree: $WORKTREE_REL (branch $worktree_branch)"
else
    log "Reusing existing worktree: $WORKTREE_REL"
fi

# Determine worker to run
if [ -z "$WORKER_CMD" ]; then
    # No worker supplied: synthesize a worker for worktree creation.
    # Worker events are emitted after the optional push so the event
    # stream always matches the final result.
    worker_id="$TASK_ID"
    cwd_rel="$WORKTREE_REL"
    case "$cwd_rel" in
        ./*) : ;;
        *) cwd_rel="./$cwd_rel" ;;
    esac
    nw_status="PASS"
    nw_reason="null"
    nw_exit="0"
    nw_result="PASS"
    nw_code=0
    log "No worker command supplied; worktree ready."
    if [ "$PUSH" -eq 1 ]; then
        # Remote write gate already checked
        if ! git -C "$WORKTREE_ABS" push origin "$worktree_branch" 2>&1 | log; then
            nw_status="FAIL"
            nw_reason="WORKER_FAILED"
            nw_exit="1"
            nw_result="FAIL"
            nw_code=1
            log "Push failed for $worktree_branch"
        else
            log "Pushed branch $worktree_branch"
        fi
    fi
    if [ -n "$EVENTS_FILE" ]; then
        emit_worker_started "$worker_id" "$cwd_rel" || {
            echo "ERROR: failed to write worker_started event." >&2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            exit 1
        }
        emit_worker_completed "$worker_id" "$nw_status" "$nw_exit" "0" "$cwd_rel" "$nw_reason" || {
            echo "ERROR: failed to write worker_completed event." >&2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            exit 1
        }
    fi
    if [ "$nw_result" = "PASS" ]; then
        workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"PASS\",\"exit_code\":0,\"duration_ms\":0,\"reason_code\":null}"
        summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":1,\"failed\":0,\"blocked\":0}"
        if [ "$CLEANUP" -eq 1 ]; then
            git worktree remove --force "$WORKTREE_ABS" 2>/dev/null || rm -rf "$WORKTREE_ABS" 2>/dev/null || true
            git branch -D "$worktree_branch" 2>/dev/null || true
            log "Cleaned up worktree $WORKTREE_REL"
        fi
        rm -f "$LOCK_FILE" 2>/dev/null || true
        if [ "$FORMAT" = "json" ]; then
            complete_orchestration "PASS" 0 "$workers_json" "$summary_json"
        else
            log "Orchestration PASS: worktree ready at $WORKTREE_REL"
            complete_orchestration "PASS" 0 "$workers_json" "$summary_json"
        fi
    else
        rm -f "$LOCK_FILE" 2>/dev/null || true
        workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"FAIL\",\"exit_code\":1,\"duration_ms\":0,\"reason_code\":\"WORKER_FAILED\"}"
        summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":0,\"failed\":1,\"blocked\":0}"
        complete_orchestration "FAIL" 1 "$workers_json" "$summary_json"
    fi
fi

# Run generic worker in worktree
worker_id="$TASK_ID"
cwd_rel="$WORKTREE_REL"
case "$cwd_rel" in
    ./*) : ;;
    *) cwd_rel="./$cwd_rel" ;;
esac

# --- Pre-spawn hook ---
if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR" ] && [ -x "$HOOKS_DIR/pre-spawn" ]; then
    if ! "$HOOKS_DIR/pre-spawn" "$TASK_FILE" "$WORKTREE_ABS" 2>&1 | log; then
        echo "ERROR: pre-spawn hook failed; aborting." >&2
        workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"BLOCKED\",\"exit_code\":null,\"duration_ms\":0,\"reason_code\":\"WORKER_BLOCKED\"}"
        summary_json="{\"workers_defined\":1,\"workers_run\":0,\"passed\":0,\"failed\":0,\"blocked\":1}"
        rm -f "$LOCK_FILE" 2>/dev/null || true
        complete_orchestration "BLOCKED" 2 "$workers_json" "$summary_json"
    fi
fi

start_ms="$(now_ms)"
check_ok=0
worker_exit=0

# Execute worker — sandbox or direct
case "$SANDBOX" in
    docker|podman)
        container_runtime="$SANDBOX"
        if ! command -v "$container_runtime" >/dev/null 2>&1; then
            echo "ERROR: $container_runtime not available; requested --sandbox $container_runtime is BLOCKED." >&2
            status="BLOCKED"
            reason_code="TOOLING_UNAVAILABLE"
            workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"BLOCKED\",\"exit_code\":null,\"duration_ms\":0,\"reason_code\":\"TOOLING_UNAVAILABLE\"}"
            summary_json="{\"workers_defined\":1,\"workers_run\":0,\"passed\":0,\"failed\":0,\"blocked\":1}"
            result="BLOCKED"
            exit_code=2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            complete_orchestration "$result" "$exit_code" "$workers_json" "$summary_json"
        fi
        ;;
    none) ;;
    *)
        rm -f "$LOCK_FILE" 2>/dev/null || true
        fail_with_result "FAIL" 1 "--sandbox must be 'none', 'docker', or 'podman' (got '$SANDBOX')." "WORKER_FAILED"
        ;;
esac

# Emit worker_started only after sandbox availability is confirmed
if [ -n "$EVENTS_FILE" ]; then
    if ! emit_worker_started "$worker_id" "$cwd_rel"; then
        echo "ERROR: failed to write worker_started event." >&2
        rm -f "$LOCK_FILE" 2>/dev/null || true
        exit 1
    fi
fi

if [ "$SANDBOX" != "none" ]; then
    # Container sandbox: mount the worktree, run worker inside
    _image="${SANDBOX_IMAGE:-ubuntu:24.04}"
    _trace_arg=""
    if [ -n "$TRACE_ID" ]; then
        _trace_arg="TRACEPARENT=00-${TRACE_ID}-${SPAN_ID}-${TRACE_FLAGS}"
    fi
    if [ "$FORMAT" = "json" ]; then
        if [ -n "$_trace_arg" ]; then
            (cd "$WORKTREE_ABS" && "$container_runtime" run --rm -e "$_trace_arg" -v "$(pwd):/work" -w /work "$_image" bash -c "$WORKER_CMD") >&2 && check_ok=1
        else
            (cd "$WORKTREE_ABS" && "$container_runtime" run --rm -v "$(pwd):/work" -w /work "$_image" bash -c "$WORKER_CMD") >&2 && check_ok=1
        fi
        worker_exit=$?
    else
        if [ -n "$_trace_arg" ]; then
            (cd "$WORKTREE_ABS" && "$container_runtime" run --rm -e "$_trace_arg" -v "$(pwd):/work" -w /work "$_image" bash -c "$WORKER_CMD") && check_ok=1
        else
            (cd "$WORKTREE_ABS" && "$container_runtime" run --rm -v "$(pwd):/work" -w /work "$_image" bash -c "$WORKER_CMD") && check_ok=1
        fi
        worker_exit=$?
    fi
else
    # Direct execution in worktree (existing behavior)
    if [ "$FORMAT" = "json" ]; then
        (cd "$WORKTREE_ABS" && bash -c "$WORKER_CMD") >&2 && check_ok=1
        worker_exit=$?
    else
        (cd "$WORKTREE_ABS" && bash -c "$WORKER_CMD") && check_ok=1
        worker_exit=$?
    fi
fi

if [ "$check_ok" -eq 1 ]; then
    worker_exit=0
else
    [ "$worker_exit" -eq 0 ] && worker_exit=1
fi

end_ms="$(now_ms)"
duration_ms=$(( end_ms - start_ms ))
[ "$duration_ms" -ge 0 ] || duration_ms=0

status="PASS"
reason_code="null"
exit_code_str="0"
if [ "$check_ok" -eq 0 ]; then
    if [ "$worker_exit" -eq 127 ] || [ "$worker_exit" -eq 126 ]; then
        status="BLOCKED"
        reason_code="TOOLING_UNAVAILABLE"
        exit_code_str="null"
    else
        status="FAIL"
        reason_code="WORKER_FAILED"
        exit_code_str="$worker_exit"
    fi
fi

# --- Post-worker hook ---
# A hook failure overrides the worker outcome below; worker_completed is
# emitted once, after this hook, so the event and result always agree.
if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR" ] && [ -x "$HOOKS_DIR/post-worker" ]; then
    if ! "$HOOKS_DIR/post-worker" "$TASK_FILE" "$WORKTREE_ABS" 2>&1 | log; then
        echo "ERROR: post-worker hook failed; aborting." >&2
        status="FAIL"
        reason_code="WORKER_FAILED"
        worker_exit=1
        exit_code_str="1"
        result="FAIL"
        exit_code=1
        log "Post-worker hook failed; marking orchestration as FAIL."
    fi
fi

# Build workers JSON and summary
if [ "$status" = "PASS" ]; then
    workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"PASS\",\"exit_code\":0,\"duration_ms\":$duration_ms,\"reason_code\":null}"
    summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":1,\"failed\":0,\"blocked\":0}"
    result="PASS"
    exit_code=0
elif [ "$status" = "FAIL" ]; then
    workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"FAIL\",\"exit_code\":$worker_exit,\"duration_ms\":$duration_ms,\"reason_code\":\"WORKER_FAILED\"}"
    summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":0,\"failed\":1,\"blocked\":0}"
    result="FAIL"
    exit_code=1
else
    workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"BLOCKED\",\"exit_code\":null,\"duration_ms\":$duration_ms,\"reason_code\":\"$reason_code\"}"
    summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":0,\"failed\":0,\"blocked\":1}"
    result="BLOCKED"
    exit_code=2
fi

# --- Review stage (runs only when --review is set and worker passed) ---
review_failed=0
if [ "$REVIEW" -eq 1 ] && [ "$result" = "PASS" ]; then
    log "Running review stage (validate-task, validate-context, validate-skills)..."
    _scripts_dir="$(cd "$(dirname "$0")" && pwd)"
    # Resolve validator path relative to .agentic/scripts, not .agentic/orchestration
    if [ ! -f "$_scripts_dir/validate-task.sh" ] && [ -f "$PROJECT_ROOT/.agentic/scripts/validate-task.sh" ]; then
        _scripts_dir="$PROJECT_ROOT/.agentic/scripts"
    fi
    _task_rel="${TASK_FILE#./}"
    # Normalize absolute task paths relative to PROJECT_ROOT
    case "$_task_rel" in
        /*|/[A-Za-z]*)
            case "$_task_rel" in
                "$PROJECT_ROOT"/*) _task_rel="${_task_rel#"$PROJECT_ROOT"/}" ;;
            esac
            _task_rel="$_task_rel"
            ;;
    esac
    _task_in_worktree="$WORKTREE_ABS/$_task_rel"
    # Fallback: use basename in case task was moved
    if [ ! -f "$_task_in_worktree" ]; then
        _task_in_worktree="$WORKTREE_ABS/$(basename "$TASK_FILE")"
    fi
    _vt_exists=0
    _vc_exists=0
    _vs_exists=0
    # validate-task
    if [ -x "$_scripts_dir/validate-task.sh" ] || [ -f "$_scripts_dir/validate-task.sh" ]; then
        _vt_exists=1
        if ! bash "$_scripts_dir/validate-task.sh" --handoff "$_task_in_worktree" 2>&1 | log; then
            review_failed=1
        fi
    fi
    # validate-context
    if [ "$review_failed" -eq 0 ] && { [ -x "$_scripts_dir/validate-context.sh" ] || [ -f "$_scripts_dir/validate-context.sh" ]; }; then
        _vc_exists=1
        if ! bash "$_scripts_dir/validate-context.sh" --handoff "$_task_in_worktree" 2>&1 | log; then
            review_failed=1
        fi
    fi
    # validate-skills
    if [ "$review_failed" -eq 0 ] && { [ -x "$_scripts_dir/validate-skills.sh" ] || [ -f "$_scripts_dir/validate-skills.sh" ]; }; then
        _vs_exists=1
        if ! bash "$_scripts_dir/validate-skills.sh" --handoff "$_task_in_worktree" 2>&1 | log; then
            review_failed=1
        fi
    fi
    if [ "$_vt_exists" -eq 0 ] || [ "$_vc_exists" -eq 0 ] || [ "$_vs_exists" -eq 0 ]; then
        log "WARNING: missing validator scripts (validate-task=$_vt_exists validate-context=$_vc_exists validate-skills=$_vs_exists); review BLOCKED."
        review_failed=1
    fi
    if [ "$review_failed" -eq 1 ]; then
        status="FAIL"
        reason_code="REVIEW_FAILED"
        worker_exit=1
        exit_code_str="1"
        result="FAIL"
        exit_code=1
        workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"FAIL\",\"exit_code\":1,\"duration_ms\":$duration_ms,\"reason_code\":\"REVIEW_FAILED\"}"
        summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":0,\"failed\":1,\"blocked\":0}"
        log "Review stage failed; marking orchestration as FAIL."
    else
        log "Review stage passed."
    fi
fi

# --- Post-review hook ---
if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR" ] && [ -x "$HOOKS_DIR/post-review" ]; then
    if ! "$HOOKS_DIR/post-review" "$TASK_FILE" "$WORKTREE_ABS" 2>&1 | log; then
        echo "ERROR: post-review hook failed." >&2
        review_failed=1
        status="FAIL"
        reason_code="REVIEW_FAILED"
        worker_exit=1
        exit_code_str="1"
        result="FAIL"
        exit_code=1
        workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"FAIL\",\"exit_code\":1,\"duration_ms\":$duration_ms,\"reason_code\":\"REVIEW_FAILED\"}"
        summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":0,\"failed\":1,\"blocked\":0}"
    fi
fi

# Handle remote write if requested and worker passed
if [ "$PUSH" -eq 1 ] && [ "$result" = "PASS" ]; then
    log "Pushing branch $worktree_branch..."
    if ! git -C "$WORKTREE_ABS" push origin "$worktree_branch" 2>&1 | while IFS= read -r line; do log "$line"; done; then
        status="FAIL"
        reason_code="WORKER_FAILED"
        worker_exit=1
        exit_code_str="1"
        workers_json="{\"worker_id\":\"$(json_escape "$worker_id")\",\"status\":\"FAIL\",\"exit_code\":1,\"duration_ms\":$duration_ms,\"reason_code\":\"WORKER_FAILED\"}"
        summary_json="{\"workers_defined\":1,\"workers_run\":1,\"passed\":0,\"failed\":1,\"blocked\":0}"
        result="FAIL"
        exit_code=1
        log "Push failed for $worktree_branch"
    else
        log "Pushed $worktree_branch"
    fi
fi

# Emit worker_completed once, after all downstream stages, matching the result below.
if [ -n "$EVENTS_FILE" ]; then
    if [ "$status" = "PASS" ]; then
        emit_worker_completed "$worker_id" "$status" "$exit_code_str" "$duration_ms" "$cwd_rel" "null" || {
            echo "ERROR: failed to write worker_completed event." >&2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            exit 1
        }
    elif [ "$status" = "BLOCKED" ]; then
        emit_worker_completed "$worker_id" "$status" "null" "$duration_ms" "$cwd_rel" "$reason_code" || {
            echo "ERROR: failed to write worker_completed event." >&2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            exit 1
        }
    else
        emit_worker_completed "$worker_id" "$status" "$exit_code_str" "$duration_ms" "$cwd_rel" "$reason_code" || {
            echo "ERROR: failed to write worker_completed event." >&2
            rm -f "$LOCK_FILE" 2>/dev/null || true
            exit 1
        }
    fi
fi

# Cleanup only on success: failed/blocked worktrees are preserved for inspection.
if [ "$CLEANUP" -eq 1 ] && [ "$result" = "PASS" ]; then
    git worktree remove --force "$WORKTREE_ABS" 2>/dev/null || rm -rf "$WORKTREE_ABS" 2>/dev/null || true
    git branch -D "$worktree_branch" 2>/dev/null || true
    log "Cleaned up worktree $WORKTREE_REL"
fi

rm -f "$LOCK_FILE" 2>/dev/null || true

if [ "$FORMAT" = "json" ]; then
    complete_orchestration "$result" "$exit_code" "$workers_json" "$summary_json"
else
    if [ "$result" = "PASS" ]; then
        log "Orchestration PASS: worker succeeded in $WORKTREE_REL"
    elif [ "$result" = "FAIL" ]; then
        log "Orchestration FAIL: worker failed in $WORKTREE_REL"
    else
        log "Orchestration BLOCKED: worker blocked in $WORKTREE_REL"
    fi
    complete_orchestration "$result" "$exit_code" "$workers_json" "$summary_json"
fi
