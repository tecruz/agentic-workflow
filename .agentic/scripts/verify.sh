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
    echo "==> [$id] $exe ${args[*]}"

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

    if (cd "$cwd" && "$exe" "${args[@]}"); then
        :
    else
        if [ "$requirement" = "required" ]; then
            FAILED=1
        else
            echo "  WARNING: optional check '$id' failed"
        fi
    fi
}

run_check_line() {
    local line="$1"
    local requirement id cwd exe rest
    local -a args=()
    IFS=$'\t' read -r requirement id cwd exe rest <<< "$line"
    if [ -n "$rest" ]; then
        IFS=$'\t' read -r -a args <<< "$rest"
    fi
    run_check "$requirement" "$id" "$cwd" "$exe" "${args[@]}"
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

validate_checks_tsv() {
    local file="$1"
    local line_num=0
    local line
    declare -A seen_ids=()
    local root_dir
    root_dir="$(pwd)"

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        case "$line" in
            '' | \#*) continue ;;
        esac

        local requirement id cwd exe rest
        local -a fields=()
        IFS=$'\t' read -r -a fields <<< "$line"

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

        if [ -n "${seen_ids[$id]:-}" ]; then
            echo "ERROR: .agentic/checks.tsv line $line_num has duplicate check ID '$id'." >&2
            exit 1
        fi
        seen_ids["$id"]=1

        local resolved_cwd
        resolved_cwd="$(cd "$cwd" 2>/dev/null && pwd || true)"
        if [ -z "$resolved_cwd" ] || [[ "$resolved_cwd" != "$root_dir"* ]]; then
            echo "ERROR: .agentic/checks.tsv line $line_num working directory '$cwd' escapes project root." >&2
            exit 1
        fi
    done < "$file"
}

emit_checks() {
    detect
    exit 0
}

if [ "${1:-}" = "--emit-checks" ]; then
    emit_checks
fi

if checks_defined; then
    validate_checks_tsv "$(checks_file)"
    echo "Using project checks: .agentic/checks.tsv"
    DETECTED=1
    while IFS= read -r line; do
        case "$line" in
            '' | \#*) continue ;;
        esac
        run_check_line "$line"
    done < "$(checks_file)"
else
    if [ -f "$(checks_file)" ]; then
        echo "Note: .agentic/checks.tsv defines no checks; falling back to auto-detection."
    fi
    echo "Auto-detecting project stack (no checks.tsv)..."
    local_lines="$(detect)"
    if [ -n "$local_lines" ]; then
        DETECTED=1
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            run_check_line "$line"
        done <<< "$local_lines"
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
