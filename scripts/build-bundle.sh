#!/usr/bin/env bash
#
# build-bundle.sh — package the framework into a clean adopter distribution.
#
# The repository is the framework's development source: it carries the
# framework's own .agentic/checks.tsv, tests/, CI, and docs. Adopters installing
# via "Use this template" want none of that. This script assembles a
# self-contained distribution (dist/agentic-workflow-<version>/) containing
# exactly the files the installers seed and manage, then produces tar.gz and
# zip archives plus a SHA256SUMS file.
#
# What is intentionally NOT included:
#   .agentic/checks.tsv   the framework's own checks (adopters seed the generic
#                         template from .agentic/templates/checks.tsv instead)
#   tests/ .github/ docs/ CHANGELOG.md README.md CONTRIBUTING.md SECURITY.md
#
# Usage:
#   bash scripts/build-bundle.sh [--no-archives]
#
# Options:
#   --no-archives   Only assemble the bundle directory (skip archives and
#                   SHA256SUMS). Useful for tests and quick local installs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/.agentic/VERSION")"
DIST="$ROOT/dist"
BUNDLE="$DIST/agentic-workflow-$VERSION"
NO_ARCHIVES=0

# Portable SHA-256 helpers: detect GNU coreutils or BSD shasum.
sha256_generate() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$@"
    else
        echo "ERROR: no SHA-256 utility found" >&2
        return 1
    fi
}

sha256_verify() {
    local checksum_file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "$checksum_file"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -c "$checksum_file"
    else
        echo "ERROR: no SHA-256 utility found" >&2
        return 1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-archives) NO_ARCHIVES=1 ;;
        -h|--help) head -30 "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

rm -rf "$BUNDLE"
rm -f \
    "$DIST/agentic-workflow-$VERSION.tar.gz" \
    "$DIST/agentic-workflow-$VERSION.zip" \
    "$DIST/SHA256SUMS"
mkdir -p "$BUNDLE/.agentic/rules" \
         "$BUNDLE/.agentic/profiles" \
         "$BUNDLE/.agentic/scripts" \
         "$BUNDLE/.agentic/templates" \
         "$BUNDLE/.agentic/tasks" \
         "$BUNDLE/.agentic/decisions" \
         "$BUNDLE/.agentic/schemas" \
         "$BUNDLE/.agentic/context" \
         "$BUNDLE/.agentic/context/security-review" \
         "$BUNDLE/.agentic/context/database-migrations" \
         "$BUNDLE/.agentic/context/dependency-changes" \
         "$BUNDLE/.agentic/context/infrastructure-change" \
         "$BUNDLE/.agentic/context/public-api-change" \
         "$BUNDLE/.agentic/orchestration"

# Root-level protocol entry points and installers.
cp "$ROOT/AGENTS.md" "$ROOT/CLAUDE.md" "$ROOT/GEMINI.md" "$ROOT/.aider.conf.yml" "$BUNDLE/"
cp "$ROOT/LICENSE" "$BUNDLE/"
cp "$ROOT/install.sh" "$ROOT/install.ps1" "$BUNDLE/"

# .agentic payload: everything the installers seed or manage, minus the
# framework's own checks.tsv (adopters seed from .agentic/templates/checks.tsv).
cp "$ROOT/.agentic/VERSION" \
   "$ROOT/.agentic/WORKFLOW.md" \
   "$ROOT/.agentic/ARCHITECTURE.md" \
   "$ROOT/.agentic/STATUS.md" \
   "$BUNDLE/.agentic/"
cp "$ROOT"/.agentic/rules/*.md "$BUNDLE/.agentic/rules/"
cp "$ROOT"/.agentic/profiles/*.md "$BUNDLE/.agentic/profiles/"
cp "$ROOT/.agentic/scripts/verify.sh" "$ROOT/.agentic/scripts/verify.ps1" "$ROOT/.agentic/scripts/validate-task.sh" "$ROOT/.agentic/scripts/validate-task.ps1" "$ROOT/.agentic/scripts/validate-context.sh" "$ROOT/.agentic/scripts/validate-context.ps1" "$ROOT/.agentic/scripts/validate-handoff.sh" "$ROOT/.agentic/scripts/validate-handoff.ps1" "$BUNDLE/.agentic/scripts/"
cp "$ROOT"/.agentic/templates/*.md "$ROOT"/.agentic/templates/checks.tsv "$BUNDLE/.agentic/templates/"
cp "$ROOT/.agentic/tasks/README.md" "$BUNDLE/.agentic/tasks/"
cp "$ROOT/.agentic/decisions/README.md" "$BUNDLE/.agentic/decisions/"
cp "$ROOT"/.agentic/schemas/*.json "$BUNDLE/.agentic/schemas/"
cp "$ROOT/.agentic/context/INDEX.md" "$BUNDLE/.agentic/context/"
for _mod in security-review database-migrations dependency-changes infrastructure-change public-api-change; do
    cp "$ROOT/.agentic/context/$_mod/MODULE.md" "$BUNDLE/.agentic/context/$_mod/"
done
cp "$ROOT/.agentic/orchestration/README.md" "$BUNDLE/.agentic/orchestration/"
cp "$ROOT/.agentic/orchestration/coordinator.sh" "$BUNDLE/.agentic/orchestration/"

# Safety: the bundle must never leak the framework's own checks, dev-only
# dirs, or the behavioral-evaluation harness (evals are framework-development
# material, not adopter payload).
for leak in ".agentic/checks.tsv" "tests" ".github" "docs" "evals" "CHANGELOG.md" "README.md" "CONTRIBUTING.md" "SECURITY.md"; do
    if [ -e "$BUNDLE/$leak" ]; then
        echo "ERROR: bundle leaked '$leak'; aborting." >&2
        exit 1
    fi
done

if [ "$NO_ARCHIVES" -eq 1 ]; then
    echo "Bundle assembled: $BUNDLE"
    exit 0
fi

# Archives: tar.gz via tar; zip via zip or pwsh Compress-Archive.
# Compress-Archive on Linux pwsh omits dotfiles (.agentic/), so prefer
# the zip utility when available.
tar -C "$DIST" -czf "$DIST/agentic-workflow-$VERSION.tar.gz" "agentic-workflow-$VERSION"
if command -v zip >/dev/null 2>&1; then
    (cd "$DIST" && zip -qr "agentic-workflow-$VERSION.zip" "agentic-workflow-$VERSION")
elif [ "${OS:-}" = "Windows_NT" ] || uname -s | grep -qE "MINGW|MSYS|CYGWIN"; then
    PWSH_CMD=""
    if command -v pwsh >/dev/null 2>&1; then
        PWSH_CMD="pwsh"
    elif command -v pwsh.exe >/dev/null 2>&1; then
        PWSH_CMD="pwsh.exe"
    elif command -v powershell.exe >/dev/null 2>&1; then
        PWSH_CMD="powershell.exe"
    fi

    if [ -n "$PWSH_CMD" ]; then
        # Compress-Archive needs Windows paths even when launched from git-bash.
        bundle_win="$BUNDLE"
        dist_win="$DIST/agentic-workflow-$VERSION.zip"
        if command -v cygpath >/dev/null 2>&1; then
            bundle_win="$(cygpath -w "$BUNDLE")"
            dist_win="$(cygpath -w "$DIST/agentic-workflow-$VERSION.zip")"
        fi
        AGENTIC_BUNDLE_WIN="$bundle_win" \
        AGENTIC_ZIP_WIN="$dist_win" \
        "$PWSH_CMD" -NoProfile -Command \
            'Compress-Archive -LiteralPath $env:AGENTIC_BUNDLE_WIN -DestinationPath $env:AGENTIC_ZIP_WIN -Force'
        if [ ! -s "$DIST/agentic-workflow-$VERSION.zip" ]; then
            echo "ERROR: PowerShell Compress-Archive failed to create zip archive." >&2
            exit 1
        fi
    else
        echo "WARNING: neither zip nor pwsh found; skipping zip archive." >&2
    fi
else
    echo "WARNING: 'zip' utility not found on Unix; skipping zip archive (tar.gz is available)." >&2
fi

# Checksums for every archive in dist/ (the bundle directory is a build output).
{
    cd "$DIST"
    for f in agentic-workflow-$VERSION.tar.gz agentic-workflow-$VERSION.zip; do
        [ -e "$f" ] && sha256_generate "$f"
    done
} > "$DIST/SHA256SUMS"

echo "Bundle: $BUNDLE"
echo "Archives:"
echo "  $DIST/agentic-workflow-$VERSION.tar.gz"
[ -f "$DIST/agentic-workflow-$VERSION.zip" ] && echo "  $DIST/agentic-workflow-$VERSION.zip"
echo "  $DIST/SHA256SUMS"
