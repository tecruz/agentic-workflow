#!/usr/bin/env bash
#
# verify.sh — Universal project verification script.
# Auto-detects the project stack and runs its native test + lint commands.
# Implements the detection matrix from AGENTS.md (Section 5).
#
# Usage: ./.agentic/scripts/verify.sh   (run from the project root)

set -uo pipefail

FAILED=0
DETECTED=0

run() {
    echo ""
    echo "==> $*"
    "$@" || FAILED=1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# --- Node.js / JavaScript / TypeScript ---
if [ -f package.json ]; then
    DETECTED=1
    echo "Detected: Node.js project (package.json)"
    if have npm; then
        run npm test
        run npm run lint --if-present
    fi
fi

# --- Rust ---
if [ -f Cargo.toml ]; then
    DETECTED=1
    echo "Detected: Rust project (Cargo.toml)"
    if have cargo; then
        run cargo test
        run cargo clippy -- -D warnings
    fi
fi

# --- Python ---
if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
    DETECTED=1
    echo "Detected: Python project (pyproject.toml / requirements.txt)"
    if have pytest; then
        run pytest
    fi
    if have ruff; then
        run ruff check .
    fi
fi

# --- Go ---
if [ -f go.mod ]; then
    DETECTED=1
    echo "Detected: Go project (go.mod)"
    if have go; then
        run go test ./...
        run go vet ./...
    fi
fi

# --- Java / JVM ---
if [ -f pom.xml ]; then
    DETECTED=1
    echo "Detected: Maven project (pom.xml)"
    if have mvn; then
        run mvn test
    fi
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    DETECTED=1
    echo "Detected: Gradle project (build.gradle)"
    if [ -x ./gradlew ]; then
        run ./gradlew test
        run ./gradlew check
    fi
fi

# --- .NET ---
if ls *.sln *.csproj >/dev/null 2>&1; then
    DETECTED=1
    echo "Detected: .NET project (*.sln / *.csproj)"
    if have dotnet; then
        run dotnet test
    fi
fi

echo ""
if [ "$DETECTED" -eq 0 ]; then
    echo "No known project manifest detected. Nothing to verify."
    exit 0
fi

if [ "$FAILED" -ne 0 ]; then
    echo "VERIFICATION FAILED — see output above."
    exit 1
fi

echo "VERIFICATION PASSED."
