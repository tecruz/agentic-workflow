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

detect() {
    # Emits auto-detected checks as TSV on stdout. Human-readable detection
    # messages go to stderr so they never corrupt the TSV stream.
    #
    # -- Node.js / JavaScript / TypeScript --
    if [ -f package.json ]; then
        echo "Detected: Node.js project (package.json)" >&2
        if [ -f pnpm-lock.yaml ]; then
            echo "required	test	.	pnpm	test"
            echo "required	lint	.	pnpm	lint"
        elif [ -f yarn.lock ]; then
            echo "required	test	.	yarn	test"
            echo "required	lint	.	yarn	lint"
        elif [ -f bun.lockb ]; then
            echo "required	test	.	bun	test"
            echo "required	lint	.	bun	run	lint"
        else
            echo "required	test	.	npm	test"
            echo "required	lint	.	npm	run	lint	--if-present"
        fi
    fi

    # -- Rust --
    if [ -f Cargo.toml ]; then
        echo "Detected: Rust project (Cargo.toml)" >&2
        echo "required	test	.	cargo	test"
        echo "required	lint	.	cargo	clippy	--	-D	warnings"
    fi

    # -- Python --
    if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
        echo "Detected: Python project (pyproject.toml / requirements.txt)" >&2
        if [ -f poetry.lock ]; then
            echo "required	test	.	poetry	run	pytest"
            echo "required	lint	.	poetry	run	ruff	check	."
        elif [ -f uv.lock ]; then
            echo "required	test	.	uv	run	pytest"
            echo "required	lint	.	uv	run	ruff	check	."
        else
            echo "required	test	.	pytest"
            echo "required	lint	.	ruff	check	."
        fi
    fi

    # -- Go --
    if [ -f go.mod ]; then
        echo "Detected: Go project (go.mod)" >&2
        echo "required	test	.	go	test	./..."
        echo "required	lint	.	go	vet	./..."
    fi

    # -- Java / JVM --
    if [ -f pom.xml ]; then
        echo "Detected: Maven project (pom.xml)" >&2
        if [ -x ./mvnw ]; then
            echo "required	test	.	./mvnw	test"
            echo "required	lint	.	./mvnw	checkstyle:check"
        else
            echo "required	test	.	mvn	test"
            echo "required	lint	.	mvn	checkstyle:check"
        fi
    elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
        echo "Detected: Gradle project (build.gradle)" >&2
        if [ -x ./gradlew ]; then
            echo "required	test	.	./gradlew	test"
            echo "required	lint	.	./gradlew	check"
        else
            echo "required	test	.	gradle	test"
            echo "required	lint	.	gradle	check"
        fi
    fi

    # -- .NET -- (compgen, not ls: a single *.sln or *.csproj must be detected)
    if compgen -G '*.sln' >/dev/null 2>&1 || compgen -G '*.csproj' >/dev/null 2>&1; then
        echo "Detected: .NET project (*.sln / *.csproj)" >&2
        echo "required	test	.	dotnet	test"
        echo "required	lint	.	dotnet	format	--verify-no-changes"
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

if [ "${1:-}" = "--emit-checks" ]; then
    emit_checks
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
    local_lines="$(detect)"
    if [ -n "$local_lines" ]; then
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
