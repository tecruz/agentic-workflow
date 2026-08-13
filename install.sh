#!/usr/bin/env bash
#
# install.sh — Install the Universal Agentic Development Protocol into a project.
#
# File ownership model
# --------------------
#   managed   Framework files. On update they are replaced only when unchanged
#             since the last install; if the adopter modified them, a conflict
#             is reported and a `.new` candidate is written. `--replace-managed`
#             forces replacement. Project-owned files are never touched.
#   seed      Project-owned templates (ARCHITECTURE.md, checks.tsv, STATUS.md,
#             task/decision files). Never overwritten after creation.
#   merge     AGENTS.md / CLAUDE.md / GEMINI.md. A bounded managed block is
#             added or updated; any other content in the file is preserved.
#
# Usage:
#   ./install.sh [TARGET_DIR] [OPTIONS]
#
# Options:
#   --plan               Show what would be done without changing anything.
#   --update             Update an existing installation (the default whenever
#                        an install manifest is already present).
#   --backup             Back up files to .agentic-backup/ before modifying.
#   --tools LIST         Comma-separated tool adapters: claude,gemini,aider,all.
#                        Default: claude,gemini,aider. AGENTS.md is always
#                        installed; other tools read AGENTS.md natively.
#   --generate-checks    Write .agentic/checks.tsv from the detected stack.
#   --replace-checks     Overwrite existing .agentic/checks.tsv when generating checks.
#   --replace-managed    Replace framework-managed files even when the adopter
#                        modified them. Never touches project-owned files.
#   --force              Deprecated alias for --replace-managed.
#   -h, --help           Show this help.

set -euo pipefail

usage() {
    cat <<'EOF'
install.sh — Install the Universal Agentic Development Protocol into a project.

Usage:
  ./install.sh [TARGET_DIR] [OPTIONS]

Options:
  --plan               Show what would be done without changing anything.
  --update             Update an existing installation (default when a
                       previous install manifest is present).
  --backup             Back up files to .agentic-backup/ before modifying.
  --tools LIST         Comma-separated tool adapters: claude,gemini,aider,all.
                       Default: claude,gemini,aider. AGENTS.md is always
                       installed; other tools read AGENTS.md natively.
  --generate-checks    Write .agentic/checks.tsv from the detected stack.
  --replace-checks     Overwrite existing .agentic/checks.tsv when generating checks.
  --replace-managed    Replace framework-managed files even when the adopter
                       modified them. Never touches project-owned files.
  --force              Deprecated alias for --replace-managed.
  -h, --help           Show this help.
EOF
}

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOCOL_VERSION="$(cat "$SOURCE_DIR/.agentic/VERSION")"
TARGET_DIR="."
PLAN=0
BACKUP=0
REPLACE_MANAGED=0
REPLACE_CHECKS=0
GENERATE_CHECKS=0
UPDATE=0
TOOLS_RAW="claude,gemini,aider"

START_MARKER='<!-- @@AGENTIC-PROTOCOL-START@@ -->'
END_MARKER='<!-- @@AGENTIC-PROTOCOL-END@@ -->'

while [ $# -gt 0 ]; do
    case "$1" in
        --plan) PLAN=1 ;;
        --update) UPDATE=1 ;;
        --backup) BACKUP=1 ;;
        --replace-managed|--force) REPLACE_MANAGED=1 ;;
        --replace-checks) REPLACE_CHECKS=1 ;;
        --generate-checks) GENERATE_CHECKS=1 ;;
        --tools) TOOLS_RAW="$2"; shift ;;
        --tools=*) TOOLS_RAW="${1#*=}" ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) TARGET_DIR="$1" ;;
    esac
    shift
done

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: target directory '$TARGET_DIR' does not exist." >&2
    exit 1
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ "$TOOLS_RAW" = "all" ]; then
    TOOLS=(claude gemini aider)
else
    IFS=',' read -r -a TOOLS <<< "$TOOLS_RAW"
fi
for t in "${TOOLS[@]}"; do
    case "$t" in
        claude|gemini|aider) ;;
        *) echo "Error: unknown tool '$t' (expected claude, gemini, aider, or all)" >&2; exit 2 ;;
    esac
done

# Framework-managed files: replaced on update when unchanged, or via
# --replace-managed. Never project memory/architecture/tasks/decisions.
MANAGED_FILES=(
    ".agentic/VERSION"
    ".agentic/WORKFLOW.md"
    ".agentic/rules/01-general-principles.md"
    ".agentic/rules/02-code-quality.md"
    ".agentic/rules/03-testing-verification.md"
    ".agentic/rules/04-git-conventions.md"
    ".agentic/rules/05-security-safety.md"
    ".agentic/scripts/verify.sh"
    ".agentic/scripts/verify.ps1"
    ".agentic/templates/FEATURE_SPEC.md"
    ".agentic/templates/BUG_REPORT.md"
    ".agentic/templates/REFACTOR_PLAN.md"
    ".agentic/templates/checks.tsv"
    ".agentic/tasks/README.md"
    ".agentic/decisions/README.md"
)

# Seed-once, project-owned: never overwritten after creation.
SEED_FILES=(
    ".agentic/ARCHITECTURE.md"
    ".agentic/STATUS.md"
)

# Merge-managed: bounded managed block is added/updated, other content preserved.
MERGE_FILES=(
    "AGENTS.md"
)

for t in "${TOOLS[@]}"; do
    case "$t" in
        claude) MERGE_FILES+=("CLAUDE.md") ;;
        gemini) MERGE_FILES+=("GEMINI.md") ;;
        aider)  MANAGED_FILES+=(".aider.conf.yml") ;;
    esac
done

BACKUP_DIR=""
MANIFEST_TMP="$(mktemp)"
SNAP_DIR="$(mktemp -d)"
CHANGED_RELS=()
BACKUP_DIR_EXISTED=0
[ -e "$TARGET_DIR/.agentic-backup" ] && BACKUP_DIR_EXISTED=1

# Transactional safety: every file we are about to modify is snapshotted first;
# if the install fails partway through, rollback() restores the target to its
# prior state instead of leaving a partial installation behind.
snapshot_file() {
    local rel="$1" snap
    snap="$SNAP_DIR/${rel//\//_}"
    # First snapshot wins: a path modified more than once in one transaction
    # must always be rolled back to its state before the transaction began.
    if [ -e "$snap" ] || [ -e "$snap.present" ] || [ -e "$snap.absent" ]; then
        return
    fi
    if [ -e "$TARGET_DIR/$rel" ]; then
        cp -p "$TARGET_DIR/$rel" "$snap" 2>/dev/null || cp "$TARGET_DIR/$rel" "$snap"
        : > "$snap.present"
    else
        : > "$snap.absent"
    fi
    CHANGED_RELS+=("$rel")
}

rollback() {
    local rel dst snap
    echo "ERROR: installation failed; restoring '$TARGET_DIR' to its prior state." >&2
    for rel in "${CHANGED_RELS[@]}"; do
        dst="$TARGET_DIR/$rel"
        snap="$SNAP_DIR/${rel//\//_}"
        if [ -f "$snap.present" ]; then
            cp "$snap" "$dst" 2>/dev/null || true
        else
            rm -f "$dst" 2>/dev/null || true
        fi
        rm -f "${dst}.agentic-tmp" 2>/dev/null || true
    done
    if [ "$BACKUP_DIR_EXISTED" -eq 0 ] && [ -n "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR" 2>/dev/null || true
    fi
}

cleanup() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        rollback
    fi
    rm -rf "$SNAP_DIR" 2>/dev/null || true
    exit "$rc"
}
trap cleanup EXIT

manifest_file() { printf '%s' "$TARGET_DIR/.agentic/install-manifest.tsv"; }

manifest_checksum() {
    local mf
    mf="$(manifest_file)"
    if [ -f "$mf" ]; then
        awk -F'\t' -v p="$1" '$1==p {print $3}' "$mf" | head -n1
    fi
}

cksum_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

backup_file() {
    local rel="$1" src flat
    src="$TARGET_DIR/$rel"
    flat="${rel//\//_}"
    [ -z "$BACKUP_DIR" ] && BACKUP_DIR="$TARGET_DIR/.agentic-backup"
    mkdir -p "$BACKUP_DIR"
    snapshot_file ".agentic-backup/$flat"
    cp -p "$src" "$BACKUP_DIR/$flat"
    echo "  backup $rel -> .agentic-backup/$flat"
}

install_managed() {
    local src="$1" rel="$2"
    local dst="$TARGET_DIR/$rel" prev cur
    if [ ! -e "$dst" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  copy   $rel (create)"; return; }
        snapshot_file "$rel"
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "  copy   $rel (create)"
        printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        return
    fi
    if [ "$REPLACE_MANAGED" -eq 1 ]; then
        [ "$PLAN" -eq 1 ] && { echo "  copy   $rel (replace: --replace-managed)"; return; }
        snapshot_file "$rel"
        [ "$BACKUP" -eq 1 ] && backup_file "$rel"
        cp "$src" "$dst"
        echo "  copy   $rel (replaced: --replace-managed)"
        printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        return
    fi
    prev="$(manifest_checksum "$rel")"
    if [ -n "$prev" ]; then
        cur="$(cksum_file "$dst")"
        if [ "$prev" = "$cur" ]; then
            [ "$PLAN" -eq 1 ] && { echo "  update $rel (unchanged since last install)"; return; }
            snapshot_file "$rel"
            cp "$src" "$dst"
            echo "  update $rel (unchanged since last install)"
            printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        else
            [ "$PLAN" -eq 1 ] && { echo "  conflict $rel (modified since install; candidate: $rel.new)"; return; }
            snapshot_file "$rel"
            snapshot_file "$rel.new"
            cp "$src" "${dst}.new"
            echo "  conflict $rel (modified since install; wrote $rel.new)"
            printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$src")" >> "$MANIFEST_TMP"
        fi
    else
        [ "$PLAN" -eq 1 ] && { echo "  conflict $rel (pre-existing; candidate: $rel.new)"; return; }
        snapshot_file "$rel"
        snapshot_file "$rel.new"
        cp "$src" "${dst}.new"
        echo "  conflict $rel (pre-existing; wrote $rel.new; use --replace-managed to overwrite)"
        printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$src")" >> "$MANIFEST_TMP"
    fi
}

install_seed() {
    local src="$1" rel="$2"
    local dst="$TARGET_DIR/$rel"
    if [ -e "$dst" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  skip   $rel (project-owned; never overwritten)"; return; }
        echo "  skip   $rel (project-owned; never overwritten)"
        printf '%s\t%s\t%s\n' "$rel" seed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        return
    fi
    [ "$PLAN" -eq 1 ] && { echo "  seed   $rel (create)"; return; }
    snapshot_file "$rel"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  seed   $rel (create)"
    printf '%s\t%s\t%s\n' "$rel" seed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
}

# checks.tsv is special: on a fresh install it seeds the generic template from
# .agentic/templates/checks.tsv, unless --generate-checks already produced a
# stack-generated file. Existing files are always treated as project-owned.
install_seed_checks() {
    local rel=".agentic/checks.tsv"
    local dst="$TARGET_DIR/$rel"
    if [ -e "$dst" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  skip   $rel (project-owned; never overwritten)"; return; }
        echo "  skip   $rel (project-owned; never overwritten)"
        printf '%s\t%s\t%s\n' "$rel" seed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        return
    fi
    install_seed "$SOURCE_DIR/.agentic/templates/checks.tsv" "$rel"
}

install_merge() {
    local src="$1" rel="$2"
    local dst="$TARGET_DIR/$rel" start_line end_line tmp start_count end_count
    if [ ! -e "$dst" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (create)"; return; }
        snapshot_file "$rel"
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "  merge  $rel (create)"
        printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        return
    fi
    start_count="$(grep -c -F -- "$START_MARKER" "$dst" 2>/dev/null || true)"
    end_count="$(grep -c -F -- "$END_MARKER" "$dst" 2>/dev/null || true)"
    start_line="$(grep -n -F -- "$START_MARKER" "$dst" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
    end_line="$(grep -n -F -- "$END_MARKER" "$dst" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
    # Malformed marker sets are never rewritten in place: a single start+end
    # pair where the end marker precedes the start marker is also malformed.
    if [ "$start_count" -gt 1 ] || [ "$end_count" -gt 1 ] \
        || { { [ "$start_count" -eq 1 ] && [ "$end_count" -eq 0 ]; } || { [ "$start_count" -eq 0 ] && [ "$end_count" -eq 1 ]; }; } \
        || { [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] && [ "$end_line" -le "$start_line" ]; }; then
        [ "$PLAN" -eq 1 ] && { echo "  conflict $rel (malformed merge markers; candidate: $rel.new)"; return; }
        snapshot_file "$rel"
        snapshot_file "$rel.new"
        cp "$src" "${dst}.new"
        echo "  conflict $rel (malformed merge markers detected; wrote $rel.new)"
        printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$src")" >> "$MANIFEST_TMP"
        return
    fi
    if [ -n "$start_line" ] && [ -n "$end_line" ] && [ "$start_line" -lt "$end_line" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (update managed block, preserve custom content)"; return; }
        snapshot_file "$rel"
        [ "$BACKUP" -eq 1 ] && backup_file "$rel"
        tmp="${dst}.agentic-tmp"
        if ! (
            if [ "$start_line" -gt 1 ]; then head -n "$((start_line - 1))" "$dst"; fi
            cat "$src"
            tail -n +"$((end_line + 1))" "$dst"
        ) > "$tmp"; then
            echo "ERROR: failed to rewrite '$rel'." >&2
            rm -f "$tmp" 2>/dev/null || true
            exit 1
        fi
        mv "$tmp" "$dst"
        echo "  merge  $rel (managed block updated, custom content preserved)"
        printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
    elif [ -s "$dst" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (insert managed block above existing content)"; return; }
        snapshot_file "$rel"
        [ "$BACKUP" -eq 1 ] && backup_file "$rel"
        tmp="${dst}.agentic-tmp"
        if ! ( cat "$src"; printf '\n\n---\n\n'; cat "$dst" ) > "$tmp"; then
            echo "ERROR: failed to rewrite '$rel'." >&2
            rm -f "$tmp" 2>/dev/null || true
            exit 1
        fi
        mv "$tmp" "$dst"
        echo "  merge  $rel (managed block inserted, existing content preserved)"
        printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
    else
        [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (create)"; return; }
        snapshot_file "$rel"
        cp "$src" "$dst"
        echo "  merge  $rel (create)"
        printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
    fi
}

generate_checks() {
    local rel=".agentic/checks.tsv"
    local dst="$TARGET_DIR/$rel"
    local checks tmp
    if [ -e "$dst" ] && [ "$REPLACE_CHECKS" -eq 0 ]; then
        echo "  skip   .agentic/checks.tsv (already exists; use --replace-checks to overwrite)"
        return
    fi
    [ "$PLAN" -eq 1 ] && { echo "  gen    .agentic/checks.tsv (from detected stack)"; return; }
    mkdir -p "$TARGET_DIR/.agentic"
    checks="$(cd "$TARGET_DIR" && bash "$SOURCE_DIR/.agentic/scripts/verify.sh" --emit-checks 2>/dev/null || true)"
    if [ -z "$checks" ]; then
        echo "  note   no stack detected; .agentic/checks.tsv not generated"
        return
    fi
    snapshot_file "$rel"
    tmp="${dst}.agentic-tmp"
    {
        echo "# .agentic/checks.tsv — project-owned verification checks (authoritative)."
        echo "# Auto-generated by install.sh --generate-checks. Edit to match your definition of done."
        printf '%s\n' "$checks"
    } > "$tmp"
    mv "$tmp" "$dst"
    echo "  gen    .agentic/checks.tsv (from detected stack)"
}

write_manifest() {
    local mf
    [ "$PLAN" -eq 1 ] && return
    mf="$(manifest_file)"
    snapshot_file ".agentic/install-manifest.tsv"
    mkdir -p "$(dirname "$mf")"
    {
        echo "# agentic-workflow install manifest (auto-generated)"
        echo "# path<TAB>category<TAB>sha256"
        echo "$PROTOCOL_VERSION"
        cat "$MANIFEST_TMP"
    } > "$mf"
}

check_partial() {
    local missing=0 rel
    if [ ! -e "$TARGET_DIR/AGENTS.md" ]; then
        echo "ERROR: AGENTS.md was not installed into '$TARGET_DIR'." >&2
        missing=1
    fi
    for t in "${TOOLS[@]}"; do
        case "$t" in
            claude) rel="CLAUDE.md" ;;
            gemini) rel="GEMINI.md" ;;
            aider) rel=".aider.conf.yml" ;;
            *) continue ;;
        esac
        if [ ! -e "$TARGET_DIR/$rel" ]; then
            echo "WARNING: tool '$t' was requested but '$rel' is not present" \
                  "(a pre-existing file may have conflicted; review '$rel.new')." >&2
        fi
    done
    [ "$missing" -eq 0 ] || exit 1
}

echo "Installing Universal Agentic Development Protocol v$PROTOCOL_VERSION"
echo "  from: $SOURCE_DIR"
echo "  into: $TARGET_DIR"
echo "  tools: ${TOOLS[*]}"
[ "$PLAN" -eq 1 ] && echo "  mode: plan (dry run, nothing will be modified)"
echo ""

for rel in "${MANAGED_FILES[@]}"; do
    install_managed "$SOURCE_DIR/$rel" "$rel"
done
# Generate checks before seeding: the seed step creates the checks.tsv template
# and must not shadow a stack-generated file on a fresh install.
if [ "$GENERATE_CHECKS" -eq 1 ]; then
    generate_checks
fi
for rel in "${SEED_FILES[@]}"; do
    install_seed "$SOURCE_DIR/$rel" "$rel"
done
install_seed_checks
for rel in "${MERGE_FILES[@]}"; do
    install_merge "$SOURCE_DIR/$rel" "$rel"
done

write_manifest

if [ "$PLAN" -eq 1 ]; then
    echo ""
    echo "Plan complete — nothing was modified. Re-run without --plan to apply."
    exit 0
fi

echo ""
check_partial
echo "Done. Review any '.new' conflict candidates, then commit the installed files."
echo "Next: fill in .agentic/ARCHITECTURE.md for this project, and run ./.agentic/scripts/verify.sh."