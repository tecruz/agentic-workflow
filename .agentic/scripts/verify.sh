#!/usr/bin/env bash
#
# verify.sh — Universal project verification script.
#
# Verifies a project using an explicit state model that cannot report false
# success:
#
#   PASS        (exit 0)  At least one required check ran and all passed.
#   FAIL        (exit 1)  A required check ran and failed.
#   BLOCKED     (exit 2)  A project or check configuration was found, but the
#                         required tooling/configuration was unavailable, so no
#                         required check could complete.
#   UNSUPPORTED (exit 3)  No supported project or check configuration found.
#
# Invariant: PASS is impossible unless at least one required check actually ran.
#
# Checks are read from `.agentic/checks.tsv` (project-owned, authoritative)
# when that file defines at least one check. Otherwise the stack is
# auto-detected as a bootstrap mechanism only. Every command is executed as an
# argument array — never via `eval` or an interpolated shell string.
#
# checks.tsv format (tab-separated; lines starting with `#` are comments):
#
#   requirement<TAB>check-id<TAB>working-dir<TAB>executable<TAB>args...
#
#   required<TAB>test<TAB>.<TAB>pnpm<TAB>test
#   required<TAB>lint<TAB>.<TAB>pnpm<TAB>lint
#   optional<TAB>format<TAB>.<TAB>pnpm<TAB>format:check
#
# Usage:
#   ./.agentic/scripts/verify.sh                 # run from the project root
#   ./.agentic/scripts/verify.sh --emit-checks   # print auto-detected checks.tsv

set -uo pipefail

FORMAT="text"
EVENTS_FILE=""
EVENTS_FORCE=0
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
        *)
            break
            ;;
    esac
done

# The output format is a versioned CLI contract: unknown or missing values are
# rejected exactly like the PowerShell ValidateSet rejects them instead of
# silently degrading to text mode. Comparison is case-insensitive so Bash and
# PowerShell accept the same spellings.
case "$(printf '%s' "$FORMAT" | tr '[:upper:]' '[:lower:]')" in
    text) FORMAT="text" ;;
    json) FORMAT="json" ;;
    *)
        echo "ERROR: --format must be 'text' or 'json'." >&2
        exit 1
        ;;
esac

# v1.4.0: simultaneous JSON stdout and event stream is not supported.
# Each output is reliable independently; combined use could produce
# contradictory terminal event vs process exit. Reject at parse time.
if [ "$FORMAT" = "json" ] && [ -n "$EVENTS_FILE" ]; then
    echo "ERROR: --format json and --events cannot be used together in v1.4.0." >&2
    echo "Use JSON stdout OR an event stream, not both." >&2
    exit 1
fi

RESULTS_TMP="$(mktemp)"
EVENTS_SCRATCH=""
cleanup_verify() {
    rm -f "$RESULTS_TMP" 2>/dev/null || true
    if [ -n "$EVENTS_SCRATCH" ]; then
        rm -f "$EVENTS_SCRATCH" 2>/dev/null || true
    fi
}
trap cleanup_verify EXIT

# Project root for path redaction: working_directory values are made
# project-relative so absolute user-home paths never leak into JSON output.
PROJECT_ROOT="$(pwd -P)"

log() {
    if [ "$FORMAT" = "json" ]; then
        printf '%s\n' "$*" >&2
    else
        printf '%s\n' "$*"
    fi
}

# Emits a JSON event line to the event stream file.
# Returns 0 on success, 1 on write failure.
write_event() {
    local payload="$1"
    if [ -n "$EVENTS_FILE" ]; then
        printf '%s\n' "$payload" >> "$EVENTS_FILE" || return 1
    fi
    return 0
}

# Emits check_started event with working_directory.
# Returns 0 on success, 1 on write failure.
emit_check_started() {
    local check_id="$1" cwd_rel="$2"
    local esc_id esc_cwd
    esc_id="$(json_escape "$check_id")"
    esc_cwd="$(json_escape "$cwd_rel")"
    local payload="{\"event\":\"check_started\",\"check_id\":\"$esc_id\",\"working_directory\":\"$esc_cwd\"}"
    write_event "$payload"
}

# Emits check_completed event with all required fields including working_directory and reason_code.
# Returns 0 on success, 1 on write failure.
emit_check_completed() {
    local check_id="$1" status="$2" exit_code="$3" duration_ms="$4" cwd_rel="$5" reason_code="$6"
    local esc_id esc_cwd esc_rcode esc_ec
    esc_id="$(json_escape "$check_id")"
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
    local payload="{\"event\":\"check_completed\",\"check_id\":\"$esc_id\",\"status\":\"$status\",\"exit_code\":$esc_ec,\"duration_ms\":${duration_ms:-0},\"working_directory\":\"$esc_cwd\",\"reason_code\":$esc_rcode}"
    write_event "$payload"
}

# Emits verification_completed terminal event.
# Returns 0 on success, 1 on write failure.
emit_verification_completed() {
    local result="$1" exit_code="$2"
    local payload="{\"event\":\"verification_completed\",\"result\":\"$result\",\"exit_code\":$exit_code}"
    write_event "$payload"
}

# Outputs the JSON verification result to stdout.
# Returns 0 on success, 1 on write failure.
output_json_checked() {
    local res_str="$1" exit_code="$2"
    local source_type="checks_tsv"
    if ! checks_defined; then
        source_type="auto_detected"
    fi

    local checks_json="" summary=""
    local passed=0 failed=0 opt_failed=0 blocked=0 opt_skipped=0 checks_run=0 required_run=0 checks_defined=0

    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        local -a parts=()
        IFS=$'\t' read -ra parts <<< "$line"
        [ "${#parts[@]}" -lt 7 ] && continue

        local req="${parts[0]}"
        local cid="${parts[1]}"
        local cwd="${parts[2]}"
        local status="${parts[3]}"
        local ec="${parts[4]}"
        local dur="${parts[5]}"
        local rcode="${parts[6]}"

        checks_defined=$((checks_defined + 1))

        case "$status" in
            PASS)  passed=$((passed + 1)); checks_run=$((checks_run + 1)); [ "$req" = "required" ] && required_run=$((required_run + 1)) ;;
            FAIL)
                checks_run=$((checks_run + 1))
                if [ "$req" = "required" ]; then
                    failed=$((failed + 1))
                    required_run=$((required_run + 1))
                else
                    opt_failed=$((opt_failed + 1))
                fi
                ;;
            BLOCKED) blocked=$((blocked + 1)) ;;
            SKIPPED_OPTIONAL) opt_skipped=$((opt_skipped + 1)) ;;
        esac

        local cwd_rel
        case "$cwd" in
            .)
                cwd_rel="."
                ;;
            /*)
                if [ "$cwd" = "$PROJECT_ROOT" ]; then
                    cwd_rel="."
                elif [[ "$cwd" == "$PROJECT_ROOT/"* ]]; then
                    cwd_rel="./${cwd#"$PROJECT_ROOT"/}"
                else
                    cwd_rel="$(basename "$cwd")"
                fi
                ;;
            *)
                cwd_rel="$(normalize_project_rel "$cwd")"
                ;;
        esac
        local esc_cwd
        esc_cwd="$(json_escape "$cwd_rel")"

        local esc_rcode="null"
        if [ "$rcode" ] && [ "$rcode" != "null" ]; then
            esc_rcode="\"$(json_escape "$rcode")\""
        fi

        local esc_ec="null"
        if [ "$ec" ] && [ "$ec" != "null" ]; then
            esc_ec="$ec"
        fi

        local esc_id
        esc_id="$(json_escape "$cid")"
        local check_part="{\"id\":\"$esc_id\",\"requirement\":\"$req\",\"status\":\"$status\",\"working_directory\":\"$esc_cwd\",\"exit_code\":$esc_ec,\"duration_ms\":${dur:-0},\"reason_code\":$esc_rcode}"
        checks_json="${checks_json:+$checks_json,}$check_part"
    done < "$RESULTS_TMP"

    summary="{\"checks_defined\":$checks_defined,\"checks_run\":$checks_run,\"required_run\":$required_run,\"passed\":$passed,\"failed\":$failed,\"optional_failed\":$opt_failed,\"blocked\":$blocked,\"optional_skipped\":$opt_skipped}"

    local source_value
    if [ "$source_type" = "auto_detected" ]; then
        source_value="\"source\":\"auto_detected\""
    else
        source_value="\"source\":\"checks_tsv\""
    fi

    printf '{"schema_version":1,"protocol_version":"1.4.0","kind":"verification_result","result":"%s","exit_code":%d,%s,"summary":%s,"checks":[%s]}\n' \
        "$res_str" "$exit_code" "$source_value" "$summary" "$checks_json"
}

# Single finalization path: first appends terminal event to event stream,
# then emits JSON result (if requested), then exits with state-model code.
# This ensures the event stream is complete before the JSON document is exposed.
complete_verification() {
    local result="$1"
    local exit_code="$2"

    # First: finalize event stream if requested
    if [ -n "$EVENTS_FILE" ]; then
        if ! emit_verification_completed "$result" "$exit_code"; then
            echo "ERROR: failed to finalize verification event stream." >&2
            exit 1
        fi
    fi

    # Then: emit JSON result if requested
    if [ "$FORMAT" = "json" ]; then
        if ! output_json_checked "$result" "$exit_code"; then
            echo "ERROR: failed to write JSON verification result." >&2
            exit 1
        fi
    fi

    exit "$exit_code"
}

# Escapes a string for safe inclusion inside a JSON string literal.
# Handles: backslash, double-quote, tab, newline, carriage-return,
# and remaining C0 control characters (0x00-0x1F except the above) as \u00XX.
# UTF-8 continuation bytes (>= 0x80) pass through as valid JSON.
json_escape() {
    local s="$1"
    # Quick escape for common JSON special characters.
    # Order matters: backslashes first, then double-quotes.
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    # Escape tab, newline, carriage-return
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    # Remaining C0 control characters (0x00-0x1F) are escaped as \u00XX.
    # UTF-8 continuation bytes (>= 0x80) pass through as valid JSON.
    local result="" i len ch ascii
    len="${#s}"
    for (( i = 0; i < len; i++ )); do
        ch="${s:i:1}"
        ascii=$(printf '%d' "'$ch" 2>/dev/null || echo 0)
        # Guard against non-numeric ascii (e.g. multi-byte UTF-8 start)
        if ! [[ "$ascii" =~ ^[0-9]+$ ]] || [ "$ascii" -gt 255 ]; then
            # Pass through unknown characters as-is
            result+="$ch"
        elif [ "$ascii" -lt 32 ] && [ "$ascii" -ne 9 ] && [ "$ascii" -ne 10 ] && [ "$ascii" -ne 13 ]; then
            # Control character: escape as \u00XX
            result+="$(printf '\\u%02x' "$ascii")"
        else
            result+="$ch"
        fi
    done
    # Fallback: if result is empty for some reason, return the original string
    # minimally escaped (just backslash and quote).
    printf '%s' "${result:-$s}"
}

# Lexically normalizes an already-validated project-relative path so JSON
# working_directory labels are canonical and stable: './' prefixes collapse,
# '.' segments drop, and '..' pops the previous segment (validate_checks_tsv
# guarantees '..' can never pop above the project root). Prints '.' for an
# empty result; non-empty results are prefixed with './'. Nested labels keep
# their full shape ('apps/api' -> './apps/api'), matching PowerShell labels.
normalize_project_rel() {
    local p="${1#./}" seg out=""
    local -a segs=()
    IFS='/' read -r -a segs <<< "$p"
    # Guarded expansion: bash 3.2 (macOS) treats expanding an empty array
    # under `set -u` as an unbound variable.
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

FAILED=0
RAN=0
RAN_REQUIRED=0
BLOCKED=0
DETECTED=0

have() {
    command -v "$1" >/dev/null 2>&1 || { [ -x "$1" ]; }
}

run_check() {
    local requirement="$1" id="$2" cwd="$3" exe="$4"
    shift 4
    local -a args=("$@")

    log ""
    # `:-` guards the display-only expansion because bash 3.2 (macOS) treats
    # expanding an empty array under `set -u` as an unbound variable.
    log "==> [$id] $exe ${args[*]:-}"

    # Compute project-relative working directory for events and results
    local cwd_rel
    case "$cwd" in
        .)
            cwd_rel="."
            ;;
        /*)
            if [ "$cwd" = "$PROJECT_ROOT" ]; then
                cwd_rel="."
            elif [[ "$cwd" == "$PROJECT_ROOT/"* ]]; then
                cwd_rel="./${cwd#"$PROJECT_ROOT"/}"
            else
                cwd_rel="$(basename "$cwd")"
            fi
            ;;
        *)
            cwd_rel="$(normalize_project_rel "$cwd")"
            ;;
    esac

    if [ ! -d "$cwd" ]; then
        if [ "$requirement" = "required" ]; then
            BLOCKED=1
        fi
        log "  BLOCKED: working directory '$cwd' does not exist"
        local status="SKIPPED_OPTIONAL"
        [ "$requirement" = "required" ] && status="BLOCKED"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$requirement" "$id" "$cwd" "$status" "null" "0" "WORKING_DIR_MISSING" >> "$RESULTS_TMP"
        if [ -n "$EVENTS_FILE" ]; then
            if ! emit_check_completed "$id" "$status" "null" "0" "$cwd_rel" "WORKING_DIR_MISSING"; then
                echo "ERROR: failed to write check_completed event." >&2
                exit 1
            fi
        fi
        return
    fi

    if [[ "$exe" == */* ]]; then
        if [ ! -x "$cwd/$exe" ]; then
            if [ "$requirement" = "required" ]; then
                BLOCKED=1
                log "  BLOCKED: executable '$exe' was not found"
            else
                log "  skip (optional): executable '$exe' was not found"
            fi
            local status="SKIPPED_OPTIONAL"
            [ "$requirement" = "required" ] && status="BLOCKED"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$requirement" "$id" "$cwd" "$status" "null" "0" "EXECUTABLE_MISSING" >> "$RESULTS_TMP"
            if [ -n "$EVENTS_FILE" ]; then
                if ! emit_check_completed "$id" "$status" "null" "0" "$cwd_rel" "EXECUTABLE_MISSING"; then
                    echo "ERROR: failed to write check_completed event." >&2
                    exit 1
                fi
            fi
            return
        fi
    elif ! command -v "$exe" >/dev/null 2>&1; then
        if [ "$requirement" = "required" ]; then
            BLOCKED=1
            log "  BLOCKED: executable '$exe' was not found"
        else
            log "  skip (optional): executable '$exe' was not found"
        fi
        local status="SKIPPED_OPTIONAL"
        [ "$requirement" = "required" ] && status="BLOCKED"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$requirement" "$id" "$cwd" "$status" "null" "0" "EXECUTABLE_MISSING" >> "$RESULTS_TMP"
        if [ -n "$EVENTS_FILE" ]; then
            if ! emit_check_completed "$id" "$status" "null" "0" "$cwd_rel" "EXECUTABLE_MISSING"; then
                echo "ERROR: failed to write check_completed event." >&2
                exit 1
            fi
        fi
        return
    fi

    RAN=$((RAN + 1))
    if [ "$requirement" = "required" ]; then
        RAN_REQUIRED=1
    fi

    if [ -n "$EVENTS_FILE" ]; then
        if ! emit_check_started "$id" "$cwd_rel"; then
            echo "ERROR: failed to write check_started event." >&2
            exit 1
        fi
    fi

    local start_ms
    start_ms="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || python -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"

    # bash 3.2 (macOS) treats expanding an empty array under `set -u` as an
    # unbound variable, so branch on whether the check takes arguments.
    local check_ok=0
    if [ "$FORMAT" = "json" ]; then
        if [ "${#args[@]}" -gt 0 ]; then
            (cd "$cwd" && "$exe" "${args[@]}") >&2 && check_ok=1
        else
            (cd "$cwd" && "$exe") >&2 && check_ok=1
        fi
    else
        if [ "${#args[@]}" -gt 0 ]; then
            (cd "$cwd" && "$exe" "${args[@]}") && check_ok=1
        else
            (cd "$cwd" && "$exe") && check_ok=1
        fi
    fi
    local code=$?
    # if command succeeded via &&, code is 0; if failed, code is nonzero
    if [ "$check_ok" -eq 1 ]; then
        code=0
    else
        [ "$code" -eq 0 ] && code=1
    fi

    local end_ms
    end_ms="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || python -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
    local duration_ms=$(( end_ms - start_ms ))
    [ "$duration_ms" -ge 0 ] || duration_ms=0

    local status="PASS"
    local reason_code="null"
    if [ "$check_ok" -eq 0 ]; then
        status="FAIL"
        reason_code="CHECK_FAILED"
        if [ "$requirement" = "required" ]; then
            FAILED=1
        else
            log "  WARNING: optional check '$id' failed"
        fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$requirement" "$id" "$cwd" "$status" "$code" "$duration_ms" "$reason_code" >> "$RESULTS_TMP"
    if [ -n "$EVENTS_FILE" ]; then
        if ! emit_check_completed "$id" "$status" "$code" "$duration_ms" "$cwd_rel" "$reason_code"; then
            echo "ERROR: failed to write check_completed event." >&2
            exit 1
        fi
    fi
}

# Split a checks.tsv line into fields while preserving empty columns. Tabs are
# translated to a non-whitespace IFS character first because tab is IFS
# whitespace, which collapses consecutive tabs into one field and silently
# shifts an empty executable into the next column.
run_check_line() {
    local line="$1"
    local -a fields=()
    local -a args=()
    local requirement id cwd exe
    local safe="${line//$'\t'/$'\x1f'}"
    IFS=$'\x1f' read -r -a fields <<< "$safe"
    requirement="${fields[0]:-}"
    id="${fields[1]:-}"
    cwd="${fields[2]:-}"
    exe="${fields[3]:-}"
    if [ "${#fields[@]}" -gt 4 ]; then
        args=("${fields[@]:4}")
    fi
    # Expanding an empty array under `set -u` fails on bash 3.2 (macOS), so
    # only expand the arguments array when it actually contains fields.
    if [ "${#args[@]}" -gt 0 ]; then
        run_check "$requirement" "$id" "$cwd" "$exe" "${args[@]}"
    else
        run_check "$requirement" "$id" "$cwd" "$exe"
    fi
}

# Returns 0 when the package.json at $1 declares a script named $2. The
# scripts block is located textually, so no JSON parser is required and the
# check stays consistent across Bash and PowerShell detection.
pkg_has_script() {
    local file="$1" name="$2" block
    [ -f "$file" ] || return 1
    block="$(sed -n '/"scripts"[[:space:]]*:/,/}/p' "$file")"
    [ -n "$block" ] && printf '%s' "$block" | grep -q -E "\"$name\"[[:space:]]*:"
}

# Returns 0 when the directory $1 contains a Ruff configuration (pyproject
# `[tool.ruff]`, `ruff.toml`, or `.ruff.toml`). A Python project without one
# has not adopted Ruff, so emitting `ruff check` would only produce a false
# BLOCKED/FAIL later.
ruff_configured() {
    local dir="$1"
    [ -f "$dir/pyproject.toml" ] && grep -q '^\[tool\.ruff' "$dir/pyproject.toml" && return 0
    [ -f "$dir/ruff.toml" ] && return 0
    [ -f "$dir/.ruff.toml" ] && return 0
    return 1
}

# Returns 0 when the pom.xml at $1 configures Checkstyle; the lint check is
# only emitted for projects that actually adopted it.
maven_has_checkstyle() {
    local pom="$1"
    [ -f "$pom" ] && grep -q -i 'checkstyle' "$pom"
}

detect() {
    # Emits auto-detected checks as TSV on stdout. Human-readable detection
    # messages go to stderr so they never corrupt the TSV stream.
    local -a output_lines=()

    if [ -f package.json ]; then
        echo "Detected: Node.js project (package.json)" >&2
        if [ -f pnpm-lock.yaml ]; then
            output_lines+=("required	node-test	.	pnpm	test")
            if pkg_has_script package.json lint; then
                output_lines+=("required	node-lint	.	pnpm	lint")
            fi
        elif [ -f yarn.lock ]; then
            output_lines+=("required	node-test	.	yarn	test")
            if pkg_has_script package.json lint; then
                output_lines+=("required	node-lint	.	yarn	lint")
            fi
        elif [ -f bun.lock ] || [ -f bun.lockb ]; then
            output_lines+=("required	node-test	.	bun	test")
            if pkg_has_script package.json lint; then
                output_lines+=("required	node-lint	.	bun	run	lint")
            fi
        else
            output_lines+=("required	node-test	.	npm	test")
            output_lines+=("required	node-lint	.	npm	run	lint	--if-present")
        fi
    fi

    if [ -f Cargo.toml ]; then
        echo "Detected: Rust project (Cargo.toml)" >&2
        output_lines+=("required	rust-test	.	cargo	test")
        output_lines+=("required	rust-clippy	.	cargo	clippy	--	-D	warnings")
    fi

    if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
        echo "Detected: Python project (pyproject.toml / requirements.txt)" >&2
        if [ -f poetry.lock ]; then
            output_lines+=("required	python-test	.	poetry	run	pytest")
            if ruff_configured .; then
                output_lines+=("required	python-ruff	.	poetry	run	ruff	check	.")
            fi
        elif [ -f uv.lock ]; then
            output_lines+=("required	python-test	.	uv	run	pytest")
            if ruff_configured .; then
                output_lines+=("required	python-ruff	.	uv	run	ruff	check	.")
            fi
        else
            output_lines+=("required	python-test	.	pytest")
            if ruff_configured .; then
                output_lines+=("required	python-ruff	.	ruff	check	.")
            fi
        fi
    fi

    if [ -f go.mod ]; then
        echo "Detected: Go project (go.mod)" >&2
        output_lines+=("required	go-test	.	go	test	./...")
        output_lines+=("required	go-vet	.	go	vet	./...")
    fi

    if [ -f pom.xml ]; then
        echo "Detected: Maven project (pom.xml)" >&2
        if [ -x ./mvnw ]; then
            output_lines+=("required	maven-test	.	./mvnw	test")
            if maven_has_checkstyle pom.xml; then
                output_lines+=("required	maven-lint	.	./mvnw	checkstyle:check")
            fi
        else
            output_lines+=("required	maven-test	.	mvn	test")
            if maven_has_checkstyle pom.xml; then
                output_lines+=("required	maven-lint	.	mvn	checkstyle:check")
            fi
        fi
    elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
        local is_android=0
        if grep -q -E 'com\.android|org\.jetbrains\.kotlin\.android|AndroidManifest\.xml' build.gradle build.gradle.kts 2>/dev/null || [ -f AndroidManifest.xml ]; then
            is_android=1
        fi
        if [ "$is_android" -eq 1 ]; then
            echo "Detected: Android / Kotlin Gradle project (build.gradle)" >&2
            if [ -x ./gradlew ]; then
                output_lines+=("required	android-unit	.	./gradlew	test")
                output_lines+=("required	android-lint	.	./gradlew	lint")
                output_lines+=("required	android-build	.	./gradlew	assembleDebug")
                output_lines+=("optional	android-device	.	./gradlew	connectedCheck")
            else
                output_lines+=("required	android-unit	.	gradle	test")
                output_lines+=("required	android-lint	.	gradle	lint")
                output_lines+=("required	android-build	.	gradle	assembleDebug")
                output_lines+=("optional	android-device	.	gradle	connectedCheck")
            fi
        else
            echo "Detected: Gradle project (build.gradle)" >&2
            if [ -x ./gradlew ]; then
                output_lines+=("required	gradle-test	.	./gradlew	test")
                output_lines+=("required	gradle-lint	.	./gradlew	check")
            else
                output_lines+=("required	gradle-test	.	gradle	test")
                output_lines+=("required	gradle-lint	.	gradle	check")
            fi
        fi
    fi

    if compgen -G '*.sln' >/dev/null 2>&1 || compgen -G '*.csproj' >/dev/null 2>&1; then
        echo "Detected: .NET project (*.sln / *.csproj)" >&2
        output_lines+=("required	dotnet-test	.	dotnet	test")
        output_lines+=("required	dotnet-lint	.	dotnet	format	--verify-no-changes")
    fi

    for base in apps services packages modules; do
        if [ -d "$base" ]; then
            for sub in "$base"/*; do
                if [[ "$sub" =~ [$'\t'$'\n'$'\r'$'\x1f'[:cntrl:]] ]]; then
                    continue
                fi
                if [ -d "$sub" ] && [ "$(basename "$sub")" != "node_modules" ] && [ "$(basename "$sub")" != "target" ] && [ "$(basename "$sub")" != "build" ] && [ "$(basename "$sub")" != ".venv" ]; then
                    local prefix="${sub//\//-}"
                    prefix="${prefix//\\/-}"
                    if [ -f "$sub/package.json" ]; then
                        echo "Detected: Nested Node.js project ($sub)" >&2
                        if [ -f "$sub/pnpm-lock.yaml" ]; then
                            output_lines+=("required	${prefix}-node-test	$sub	pnpm	test")
                            if pkg_has_script "$sub/package.json" lint; then
                                output_lines+=("required	${prefix}-node-lint	$sub	pnpm	lint")
                            fi
                        elif [ -f "$sub/yarn.lock" ]; then
                            output_lines+=("required	${prefix}-node-test	$sub	yarn	test")
                            if pkg_has_script "$sub/package.json" lint; then
                                output_lines+=("required	${prefix}-node-lint	$sub	yarn	lint")
                            fi
                        elif [ -f "$sub/bun.lock" ] || [ -f "$sub/bun.lockb" ]; then
                            output_lines+=("required	${prefix}-node-test	$sub	bun	test")
                            if pkg_has_script "$sub/package.json" lint; then
                                output_lines+=("required	${prefix}-node-lint	$sub	bun	run	lint")
                            fi
                        else
                            output_lines+=("required	${prefix}-node-test	$sub	npm	test")
                            output_lines+=("required	${prefix}-node-lint	$sub	npm	run	lint	--if-present")
                        fi
                    fi
                    if [ -f "$sub/go.mod" ]; then
                        echo "Detected: Nested Go project ($sub)" >&2
                        output_lines+=("required	${prefix}-go-test	$sub	go	test	./...")
                        output_lines+=("required	${prefix}-go-vet	$sub	go	vet	./...")
                    fi
                    if [ -f "$sub/Cargo.toml" ]; then
                        echo "Detected: Nested Rust project ($sub)" >&2
                        output_lines+=("required	${prefix}-rust-test	$sub	cargo	test")
                        output_lines+=("required	${prefix}-rust-clippy	$sub	cargo	clippy	--	-D	warnings")
                    fi
                    if [ -f "$sub/pyproject.toml" ] || [ -f "$sub/requirements.txt" ]; then
                        echo "Detected: Nested Python project ($sub)" >&2
                        # Nested Python projects inherit the root-level
                        # Poetry/uv detection rather than always falling back
                        # to a bare `pytest` invocation.
                        if [ -f "$sub/poetry.lock" ]; then
                            output_lines+=("required	${prefix}-python-test	$sub	poetry	run	pytest")
                            if ruff_configured "$sub"; then
                                output_lines+=("required	${prefix}-python-ruff	$sub	poetry	run	ruff	check	.")
                            fi
                        elif [ -f "$sub/uv.lock" ]; then
                            output_lines+=("required	${prefix}-python-test	$sub	uv	run	pytest")
                            if ruff_configured "$sub"; then
                                output_lines+=("required	${prefix}-python-ruff	$sub	uv	run	ruff	check	.")
                            fi
                        else
                            output_lines+=("required	${prefix}-python-test	$sub	pytest")
                            if ruff_configured "$sub"; then
                                output_lines+=("required	${prefix}-python-ruff	$sub	ruff	check	.")
                            fi
                        fi
                    fi
                fi
            done
        fi
    done

    if [ "${#output_lines[@]}" -gt 0 ]; then
        printf '%s\n' "${output_lines[@]}"
    fi
}

checks_file() {
    echo ".agentic/checks.tsv"
}

checks_defined() {
    local f
    f="$(checks_file)"
    [ -f "$f" ] && grep -Ev '^[[:space:]]*(#|$)' "$f" | grep -q .
}

# Returns 0 when the relative path $1 stays at or beneath the project root when
# resolved textually; 1 when its `..` components pop above the root. This is a
# lexical check only: it does not require the directory to exist and does not
# follow symlinks (physical resolution happens in validate_checks_tsv for
# existing directories).
lexically_within_root() {
    local path="$1"
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
                # shellcheck disable=SC2034
                segs[$top]="$seg"
                top=$((top + 1))
                ;;
        esac
    done
    return 0
}

# Returns 0 when the nearest existing ancestor of the relative path $1 stays
# physically at or beneath the current directory. A leaf (or ancestor) that is
# a symlink to an external tree is rejected, so a candidate write can never be
# redirected outside the project root even when the leaf does not exist yet.
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

# Destination policy for the events stream: a relative path inside
# .agentic/runs/ only. Lexical checks first (absolute paths and any '.' or
# '..' segment are rejected, so traversal cannot bypass the runs-directory
# prefix), then the physical confinement shared with safe_detect_destination,
# which also rejects a symlink leaf or ancestor.
safe_events_destination() {
    local dest="$1" normalized segment
    case "$dest" in
        /*) return 1 ;;
    esac
    normalized="${dest#./}"
    case "$normalized" in
        .agentic/runs/*) ;;
        *) return 1 ;;
    esac
    local IFS='/'
    for segment in $normalized; do
        case "$segment" in
            ''|.|..) return 1 ;;
        esac
    done
    safe_detect_destination "$normalized"
}

validate_checks_tsv() {
    local file="$1"
    local line_num=0
    local line
    local seen_ids=""
    local root_dir
    root_dir="$(pwd -P)"

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        # Skip blank and comment lines, including indented comments. The regex
        # is stored in a variable so bash 3.2 (macOS) parses it at runtime.
        comment_re='^[[:space:]]*(#|$)'
        if [[ "$line" =~ $comment_re ]]; then
            continue
        fi

        local requirement id cwd exe
        local -a fields=()
        local safe="${line//$'\t'/$'\x1f'}"
        IFS=$'\x1f' read -r -a fields <<< "$safe"

        if [ "${#fields[@]}" -lt 4 ]; then
            echo "ERROR: .agentic/checks.tsv line $line_num has fewer than 4 fields." >&2
            exit 1
        fi

        requirement="${fields[0]}"
        id="${fields[1]}"
        cwd="${fields[2]}"
        exe="${fields[3]}"

        if [ "$requirement" != "required" ] && [ "$requirement" != "optional" ]; then
            echo "ERROR: .agentic/checks.tsv line $line_num has invalid requirement '$requirement' (expected 'required' or 'optional')." >&2
            exit 1
        fi

        if [ -z "$id" ] || [ -z "$cwd" ] || [ -z "$exe" ]; then
            echo "ERROR: .agentic/checks.tsv line $line_num has empty check ID, working directory, or executable." >&2
            exit 1
        fi

        case " $seen_ids " in
            *" $id "*)
                echo "ERROR: .agentic/checks.tsv line $line_num has duplicate check ID '$id'." >&2
                exit 1 ;;
        esac
        seen_ids="$seen_ids $id"

        # Lexical confinement: reject a working directory whose `..` components
        # pop above the project root without requiring the directory to exist.
        if ! lexically_within_root "$cwd"; then
            echo "ERROR: .agentic/checks.tsv line $line_num working directory '$cwd' escapes project root." >&2
            exit 1
        fi
        # Physical confinement for existing directories: a symlink inside the
        # project can point outside even when its lexical path looks like a
        # subdirectory. A missing directory is not a configuration error here;
        # run_check reports it as BLOCKED (exit 2).
        if [ -e "$cwd" ]; then
            local resolved_cwd
            resolved_cwd="$(cd "$cwd" 2>/dev/null && pwd -P || true)"
            if [ -z "$resolved_cwd" ]; then
                echo "ERROR: .agentic/checks.tsv line $line_num working directory '$cwd' cannot be resolved." >&2
                exit 1
            fi
            case "$resolved_cwd" in
                "$root_dir" | "$root_dir/"*) : ;;
                *)
                    echo "ERROR: .agentic/checks.tsv line $line_num working directory '$cwd' escapes project root." >&2
                    exit 1 ;;
            esac
        fi
    done < "$file"
}

emit_checks() {
    detect
    exit 0
}

# Reads every check line from $1 into memory before running any check. A check
# that consumes stdin (e.g. a Windows executable launched via WSL interop) must
# not be able to starve the remaining checks of the checks.tsv input stream,
# which would silently skip them and produce a false PASS.
run_checks_from_file() {
    local -a checks=()
    local line
    local comment_re='^[[:space:]]*(#|$)'
    while IFS= read -r line || [ -n "$line" ]; do
        checks+=("$line")
    done < "$1"
    # Guard the loop against bash 3.2's unbound-variable error when expanding an
    # empty array under `set -u`.
    if [ "${#checks[@]}" -eq 0 ]; then
        return
    fi
    for line in "${checks[@]}"; do
        if [[ "$line" =~ $comment_re ]]; then
            continue
        fi
        run_check_line "$line"
    done
}

explain_detection() {
    echo "=== Project Detection Explanation ==="
    detect >&2
    exit 0
}

detect_checks_file() {
    local gen_file=".agentic/checks.generated.tsv"
    if ! safe_detect_destination "$gen_file"; then
        echo "ERROR: refusing to write '$gen_file': destination is not safely inside the project root." >&2
        exit 1
    fi
    mkdir -p ".agentic"
    local checks
    checks="$(detect)" || exit 1
    if [ -z "$checks" ]; then
        rm -f "$gen_file"
        echo "No stack detected. Removed stale candidate '$gen_file'." >&2
        exit 0
    fi
    # The scratch file is created next to the candidate (same filesystem), so
    # the final `mv` is a single atomic rename instead of a cross-device
    # copy-and-delete from the system temp directory.
    local tmp
    tmp="$(mktemp "$gen_file.XXXXXX")" || exit 1
    {
        echo "# .agentic/checks.generated.tsv — candidate verification contract."
        echo "# Auto-generated by detection workflow. Review assumptions and promote to .agentic/checks.tsv"
        printf '%s\n' "$checks"
    } > "$tmp"
    if validate_checks_tsv "$tmp"; then
        mv "$tmp" "$gen_file"
        echo "Candidate contract written to $gen_file"
    else
        echo "ERROR: Generated checks failed validation." >&2
        rm -f "$tmp"
        exit 1
    fi
    exit 0
}

validate_checks_arg() {
    local target_file="$1"
    if [ ! -f "$target_file" ]; then
        echo "ERROR: file '$target_file' does not exist." >&2
        exit 1
    fi
    validate_checks_tsv "$target_file"
    echo "Checks file '$target_file' is valid."
    exit 0
}

if [ "${1:-}" = "--emit-checks" ]; then
    emit_checks
fi
if [ "${1:-}" = "--explain-detection" ]; then
    explain_detection
fi
if [ "${1:-}" = "--detect-checks" ]; then
    detect_checks_file
fi
if [ "${1:-}" = "--validate-checks" ]; then
    validate_checks_arg "${2:-}"
fi

if checks_defined; then
    # Contract validation happens before the events stream is created, so a
    # malformed project contract can never leave a started-but-unterminated
    # event file behind.
    validate_checks_tsv "$(checks_file)"
else
    if [ -f "$(checks_file)" ]; then
        log "Note: .agentic/checks.tsv defines no checks; falling back to auto-detection."
    fi
    log "Auto-detecting project stack (no checks.tsv)..."
    detected_lines="$(detect)" || exit 1
    if [ -n "$detected_lines" ]; then
        det_tmp="$(mktemp)"
        printf '%s\n' "$detected_lines" > "$det_tmp"
        validate_checks_tsv "$det_tmp"
        rm -f "$det_tmp"
    fi
fi

# Event stream initialization — deliberately placed after every early-exit
# mode and after contract validation succeeded, so any stream that is created
# is guaranteed to receive exactly one terminal verification_completed event
# below. --events is independent of --format.
if [ -n "$EVENTS_FILE" ]; then
    if ! safe_events_destination "$EVENTS_FILE"; then
        echo "ERROR: events destination must be a relative path inside .agentic/runs/. '$EVENTS_FILE' is not allowed." >&2
        exit 1
    fi
    # mv -f returns success when the destination is an existing directory (it
    # moves the source inside it), which would strand the scratch stream where
    # the exit trap cannot remove it. Reject any existing non-regular file up
    # front; symlink leaves are already refused by safe_events_destination.
    if [ -e "$EVENTS_FILE" ] && [ ! -f "$EVENTS_FILE" ]; then
        echo "ERROR: event destination exists and is not a regular file." >&2
        exit 1
    fi
    # Atomic exclusive creation using hard link (O_CREAT|O_EXCL semantics).
    # The scratch file is created with mktemp on the same filesystem.
    # Hard-link creation fails atomically if the destination already exists.
    if [ -e "$EVENTS_FILE" ] && [ "$EVENTS_FORCE" -ne 1 ]; then
        echo "ERROR: refusing to overwrite existing event file '$EVENTS_FILE'. Use --events-force to overwrite." >&2
        exit 1
    fi
    mkdir -p "$(dirname "$EVENTS_FILE")"
    # Build in an unpredictable scratch name beside the destination (mktemp,
    # not $$/$RANDOM) on the same filesystem.
    events_scratch="$(mktemp "$(dirname "$EVENTS_FILE")/.verify-events.XXXXXX")" || exit 1
    EVENTS_SCRATCH="$events_scratch"
    # Write the initial event; fail if the write fails.
    if ! printf '{"event":"verification_started"}\n' > "$events_scratch"; then
        echo "ERROR: failed to initialize event stream." >&2
        rm -f "$events_scratch"
        exit 1
    fi
    if [ "$EVENTS_FORCE" -eq 1 ]; then
        # Force mode: use mv -f and check result
        if ! mv -f -- "$events_scratch" "$EVENTS_FILE"; then
            echo "ERROR: failed to promote event stream (forced)." >&2
            rm -f "$events_scratch"
            exit 1
        fi
        # Postcondition: promotion must leave a regular file at the exact
        # destination path, never a relocation into some other filesystem
        # entry that happened to occupy the path.
        if [ ! -f "$EVENTS_FILE" ]; then
            echo "ERROR: event promotion produced no regular file." >&2
            rm -f "$events_scratch"
            exit 1
        fi
        EVENTS_SCRATCH=""
    else
        # No-clobber mode: use atomic hard-link creation
        if ! ln "$events_scratch" "$EVENTS_FILE" 2>/dev/null; then
            echo "ERROR: refusing to overwrite existing event file '$EVENTS_FILE'. Use --events-force to overwrite." >&2
            rm -f "$events_scratch"
            exit 1
        fi
        rm -f "$events_scratch"
        EVENTS_SCRATCH=""
    fi
fi

if checks_defined; then
    log "Using project checks: .agentic/checks.tsv"
    DETECTED=1
    run_checks_from_file "$(checks_file)"
elif [ -n "${detected_lines:-}" ]; then
    DETECTED=1
    run_checks_from_file <(printf '%s\n' "$detected_lines")
fi

log ""
# Priority: a real failure beats a blocked check; a blocked required check
# beats "PASS" because not every required check ran, so "all passed" cannot
# be claimed.
if [ "$FAILED" -ne 0 ]; then
    log "VERIFICATION FAILED: $RAN check(s) ran, at least one required check failed."
    complete_verification "FAIL" 1
fi
if [ "$BLOCKED" -ne 0 ]; then
    log "VERIFICATION BLOCKED: $RAN check(s) ran; required tooling was unavailable."
    complete_verification "BLOCKED" 2
fi
if [ "$RAN_REQUIRED" -ne 0 ]; then
    log "VERIFICATION PASSED: $RAN check(s) ran."
    complete_verification "PASS" 0
fi
if [ "$DETECTED" -ne 0 ]; then
    log "VERIFICATION BLOCKED: $RAN check(s) ran; required tooling was unavailable."
    complete_verification "BLOCKED" 2
fi
log "VERIFICATION UNSUPPORTED: no supported project or check configuration found."
complete_verification "UNSUPPORTED" 3
