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

    echo ""
    # `:-` guards the display-only expansion because bash 3.2 (macOS) treats
    # expanding an empty array under `set -u` as an unbound variable.
    echo "==> [$id] $exe ${args[*]:-}"

    if [ ! -d "$cwd" ]; then
        if [ "$requirement" = "required" ]; then
            BLOCKED=1
        fi
        echo "  BLOCKED: working directory '$cwd' does not exist"
        return
    fi

    if [[ "$exe" == */* ]]; then
        if [ ! -x "$cwd/$exe" ]; then
            if [ "$requirement" = "required" ]; then
                BLOCKED=1
                echo "  BLOCKED: executable '$exe' was not found"
            else
                echo "  skip (optional): executable '$exe' was not found"
            fi
            return
        fi
    elif ! command -v "$exe" >/dev/null 2>&1; then
        if [ "$requirement" = "required" ]; then
            BLOCKED=1
            echo "  BLOCKED: executable '$exe' was not found"
        else
            echo "  skip (optional): executable '$exe' was not found"
        fi
        return
    fi

    RAN=$((RAN + 1))
    if [ "$requirement" = "required" ]; then
        RAN_REQUIRED=1
    fi

    # bash 3.2 (macOS) treats expanding an empty array under `set -u` as an
    # unbound variable, so branch on whether the check takes arguments.
    local check_ok=0
    if [ "${#args[@]}" -gt 0 ]; then
        (cd "$cwd" && "$exe" "${args[@]}") && check_ok=1
    else
        (cd "$cwd" && "$exe") && check_ok=1
    fi
    if [ "$check_ok" -eq 0 ]; then
        if [ "$requirement" = "required" ]; then
            FAILED=1
        else
            echo "  WARNING: optional check '$id' failed"
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
            *) segs[$top]="$seg"; top=$((top + 1)) ;;
        esac
    done
    return 0
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
    mkdir -p ".agentic"
    local checks
    checks="$(detect)" || exit 1
    if [ -z "$checks" ]; then
        rm -f "$gen_file"
        echo "No stack detected. Removed stale candidate '$gen_file'." >&2
        exit 0
    fi
    local tmp
    tmp="$(mktemp)"
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
    validate_checks_tsv "$(checks_file)"
    echo "Using project checks: .agentic/checks.tsv"
    DETECTED=1
    run_checks_from_file "$(checks_file)"
else
    if [ -f "$(checks_file)" ]; then
        echo "Note: .agentic/checks.tsv defines no checks; falling back to auto-detection."
    fi
    echo "Auto-detecting project stack (no checks.tsv)..."
    local_lines="$(detect)" || exit 1
    if [ -n "$local_lines" ]; then
        local det_tmp
        det_tmp="$(mktemp)"
        printf '%s\n' "$local_lines" > "$det_tmp"
        validate_checks_tsv "$det_tmp"
        rm -f "$det_tmp"
        DETECTED=1
        run_checks_from_file <(printf '%s\n' "$local_lines")
    fi
fi

echo ""
# Priority: a real failure beats a blocked check; a blocked required check
# beats "PASS" because not every required check ran, so "all passed" cannot
# be claimed.
if [ "$FAILED" -ne 0 ]; then
    echo "VERIFICATION FAILED: $RAN check(s) ran, at least one required check failed."
    exit 1
fi
if [ "$BLOCKED" -ne 0 ]; then
    echo "VERIFICATION BLOCKED: $RAN check(s) ran; required tooling was unavailable."
    exit 2
fi
if [ "$RAN_REQUIRED" -ne 0 ]; then
    echo "VERIFICATION PASSED: $RAN check(s) ran."
    exit 0
fi
if [ "$DETECTED" -ne 0 ]; then
    echo "VERIFICATION BLOCKED: $RAN check(s) ran; required tooling was unavailable."
    exit 2
fi
echo "VERIFICATION UNSUPPORTED: no supported project or check configuration found."
exit 3
