#!/usr/bin/env bash
#
# install.sh — Install the Universal Agentic Development Protocol into a project.
#
# Usage:
#   ./install.sh [TARGET_DIR] [--force]
#
#   TARGET_DIR   Project to install into (default: current directory)
#   --force      Overwrite files that already exist in the target
#
# Existing files are NEVER overwritten unless --force is passed.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="."
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help)
            grep '^#' "$0" | head -n 10 | cut -c 3-
            exit 0
            ;;
        *) TARGET_DIR="$arg" ;;
    esac
done

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: target directory '$TARGET_DIR' does not exist."
    exit 1
fi

# Files installed into every project. Repo meta files (README, LICENSE,
# .gitignore, the installers themselves) are intentionally excluded.
ROOT_FILES=(
    "AGENTS.md"
    "CLAUDE.md"
    "GEMINI.md"
    "CONVENTIONS.md"
    ".cursorrules"
    ".windsurfrules"
    ".clinerules"
)

NESTED_FILES=(
    ".cursor/rules/agentic-protocol.mdc"
    ".windsurf/rules/agentic-protocol.md"
    ".github/copilot-instructions.md"
)

COPIED=0
SKIPPED=0

copy_file() {
    local rel="$1"
    local src="$SOURCE_DIR/$rel"
    local dst="$TARGET_DIR/$rel"

    if [ -f "$dst" ] && [ "$FORCE" -eq 0 ]; then
        echo "  skip  $rel (already exists; use --force to overwrite)"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  copy  $rel"
    COPIED=$((COPIED + 1))
}

echo "Installing Universal Agentic Development Protocol"
echo "  from: $SOURCE_DIR"
echo "  into: $(cd "$TARGET_DIR" && pwd)"
echo ""

for f in "${ROOT_FILES[@]}"; do
    copy_file "$f"
done

for f in "${NESTED_FILES[@]}"; do
    copy_file "$f"
done

# Copy the .agentic directory tree (rules, memory, templates, scripts).
while IFS= read -r src; do
    rel="${src#"$SOURCE_DIR"/}"
    copy_file "$rel"
done < <(find "$SOURCE_DIR/.agentic" -type f)

echo ""
echo "Done: $COPIED file(s) installed, $SKIPPED skipped."
echo "Next: commit these files, then fill in .agentic/ARCHITECTURE.md for this project."
