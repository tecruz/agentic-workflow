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
#                        an install manifest is already present). Files no
#                        longer managed (e.g. deselected tool adapters) are
#                        pruned; v1.0 legacy files are reported.
#   --prune              Remove obsolete framework files recorded by a previous
#                        install: managed files unchanged since install, managed
#                        blocks of deselected merge files, and v1.0 legacy
#                        files. Modified files are preserved as conflicts.
#   --uninstall          Remove the framework installation: managed files
#                        unchanged since install, managed blocks from merge
#                        files, the install manifest, and v1.0 legacy files.
#                        Project-owned seed files and custom merge content are
#                        preserved.
#   --prune-unverified-legacy Remove v1.0 legacy files whose content cannot be
#                        proven to be framework material. Every such file is
#                        backed up to .agentic-backup/ first. Without this flag
#                        unverifiable legacy files are preserved as conflicts.
#   --backup             Back up files to .agentic-backup/ before modifying.
#   --tools LIST         Comma-separated tool adapters: claude,gemini,aider,all.
#                        Default: claude,gemini,aider. AGENTS.md is always
#                        installed; other tools read AGENTS.md natively.
#   --generate-checks    Write .agentic/checks.tsv from the detected stack.
#   --detect-checks      Write .agentic/checks.generated.tsv from detected stack.
#   --accept-detected-checks Promote .agentic/checks.generated.tsv to .agentic/checks.tsv.
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
                       previous install manifest is present). Files no longer
                       managed (e.g. deselected tool adapters) are pruned;
                       v1.0 legacy files are reported.
  --prune              Remove obsolete framework files recorded by a previous
                       install: managed files unchanged since install, managed
                       blocks of deselected merge files, and v1.0 legacy
                       files. Modified files are preserved as conflicts.
  --uninstall          Remove the framework installation: managed files
                       unchanged since install, managed blocks from merge
                       files, the install manifest, and v1.0 legacy files.
                       Project-owned seed files and custom merge content are
                       preserved.
  --prune-unverified-legacy Remove v1.0 legacy files whose content cannot be
                       proven to be framework material. Every such file is
                       backed up to .agentic-backup/ first. Without this flag
                       unverifiable legacy files are preserved as conflicts.
  --backup             Back up files to .agentic-backup/ before modifying.
  --tools LIST         Comma-separated tool adapters: claude,gemini,aider,all.
                       Default: claude,gemini,aider. AGENTS.md is always
                       installed; other tools read AGENTS.md natively.
  --generate-checks    Write .agentic/checks.tsv from the detected stack.
  --detect-checks      Write .agentic/checks.generated.tsv from detected stack.
  --accept-detected-checks Promote .agentic/checks.generated.tsv to .agentic/checks.tsv.
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
DETECT_CHECKS=0
ACCEPT_DETECTED_CHECKS=0
UPDATE=0
PRUNE=0
UNINSTALL=0
PRUNE_UNVERIFIED_LEGACY=0
TOOLS_RAW="claude,gemini,aider"

START_MARKER='<!-- @@AGENTIC-PROTOCOL-START@@ -->'
END_MARKER='<!-- @@AGENTIC-PROTOCOL-END@@ -->'

while [ $# -gt 0 ]; do
    case "$1" in
        --plan) PLAN=1 ;;
        --update) UPDATE=1 ;;
        --prune) PRUNE=1 ;;
        --prune-unverified-legacy) PRUNE_UNVERIFIED_LEGACY=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --backup) BACKUP=1 ;;
        --replace-managed|--force) REPLACE_MANAGED=1 ;;
        --replace-checks) REPLACE_CHECKS=1 ;;
        --generate-checks) GENERATE_CHECKS=1 ;;
        --detect-checks) DETECT_CHECKS=1 ;;
        --accept-detected-checks) ACCEPT_DETECTED_CHECKS=1 ;;
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

# v1.0 shipped per-tool adapter files that were removed in 2.x (AGENTS.md is
# the single canonical protocol). On update they are only reported; --prune and
# --uninstall remove a legacy file only when its content can be proven to be a
# v1.0 framework artifact (see legacy_owned). Legacy directories can hold user
# settings, so they are always report-only and never auto-removed.
LEGACY_FILES=(
    ".cursorrules"
    ".windsurfrules"
    ".clinerules"
    "CONVENTIONS.md"
    ".github/copilot-instructions.md"
)
LEGACY_DIRS=(
    ".cursor"
    ".windsurf"
    "Memory"
)

# SHA-256 of the exact v1.0 shipped content (bytes of the v1.0.0 release).
# A checksum match proves the file is untouched framework material. Content
# that does not match byte-for-byte (for example after line-ending conversion)
# still matches the framework signature via legacy_owned().
legacy_v10_checksum() {
    case "$1" in
        .cursorrules) echo "010c2059541568ccf8fb7cb09792f741810814d98534b0bc2bc186124187a0a7" ;;
        .windsurfrules) echo "3d5dd1201a4cd96808da9099eeed85f310d41b00b7661e14e1e132b70651c1c8" ;;
        .clinerules) echo "af90e132e56e8a782a16e6ec5a622564af639fae3f4e075b082c93e73628c099" ;;
        CONVENTIONS.md) echo "b6e8886439aee9e5a34c10d67536dc5a75cc2e548c2914ed4ae5946e15b3ea20" ;;
        .github/copilot-instructions.md) echo "3f99180659e22a3bf7a707cb36e39bd41e033b217576193aab101279fe5ceda2" ;;
    esac
}

# Canonical path -> category registry. Built independent of the current tool
# selection so that deselected adapters remain validatable (a deselected
# CLAUDE.md must still be recognized and pruned safely). The category recorded
# in the manifest must match exactly: a known path carrying the wrong valid
# category is tampering (e.g. CLAUDE.md recorded as managed would let prune
# delete the entire file instead of only its managed block). Legacy paths and
# the manifest itself are deliberately absent: they are never legitimate
# managed / merge / seed records.
MERGE_PATHS=" AGENTS.md CLAUDE.md GEMINI.md "
SEED_PATHS=" .agentic/ARCHITECTURE.md .agentic/STATUS.md .agentic/checks.tsv "
MANAGED_PATHS=""
for _f in "${MANAGED_FILES[@]}"; do
    case " $MANAGED_PATHS " in
        *" $_f "*) ;;
        *) MANAGED_PATHS="$MANAGED_PATHS $_f" ;;
    esac
done
case " $MANAGED_PATHS " in
    *" .aider.conf.yml "*) ;;
    *) MANAGED_PATHS="$MANAGED_PATHS .aider.conf.yml" ;;
esac

# Prints the one legitimate category for a canonical manifest path, or returns
# 1 when the path is not a framework-managed path at all.
manifest_category() {
    case " $MERGE_PATHS " in
        *" $1 "*) printf '%s' merge; return 0 ;;
    esac
    case " $SEED_PATHS " in
        *" $1 "*) printf '%s' seed; return 0 ;;
    esac
    case " $MANAGED_PATHS " in
        *" $1 "*) printf '%s' managed; return 0 ;;
    esac
    return 1
}

BACKUP_DIR=""
# Scratch files are created lazily and only in a non-plan run: --plan must
# never create snapshots or manifest scratch files, byte-for-byte read-only.
MANIFEST_TMP=""
SNAP_DIR=""
TMP_FILES=()
CHANGED_RELS=()
BACKUP_DIR_EXISTED=0
[ -e "$TARGET_DIR/.agentic-backup" ] && BACKUP_DIR_EXISTED=1
if [ "$PLAN" -eq 0 ]; then
    MANIFEST_TMP="$(mktemp)"
    SNAP_DIR="$(mktemp -d)"
fi

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

# Central mutation primitives. Every write, restore, and removal a framework
# mutation performs goes through one of these so a symlinked or junctioned
# parent can never redirect a change outside the physical project root, and so
# every content change lands via an atomic rename (never a partial in-place
# write).
#
#   safe_atomic_copy    source file -> $TARGET_DIR/$rel, source mode preserved
#   safe_atomic_write   content fed on stdin -> $TARGET_DIR/$rel
#   safe_atomic_restore snapshot -> $TARGET_DIR/$rel (rollback only; never
#                       snapshots or backs up again)
#   safe_remove_file    remove $TARGET_DIR/$rel (confined)
#   safe_remove_empty_directory  remove an empty directory (confined; never
#                       follows a symlink/junction out of the project)
#
# Each asserts the destination is safe immediately before the operation. The
# assert resolves the nearest existing ancestor physically, so an outside-
# pointing `.agentic` or `.github` is rejected even when the leaf does not
# exist yet.

safe_atomic_copy() {
    local src="$1" rel="$2" dst="$TARGET_DIR/$2" tmp
    if ! assert_safe_destination "$rel"; then
        echo "ERROR: refusing to write '$rel': destination is not safely inside the project root." >&2
        return 1
    fi
    mkdir -p "$(dirname "$dst")"
    new_tmp "$dst" tmp || return 1
    if ! copy_with_mode "$src" "$tmp"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
    if ! mv "$tmp" "$dst"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
}

safe_atomic_write() {
    local rel="$1" dst="$TARGET_DIR/$1" tmp mode
    if ! assert_safe_destination "$rel"; then
        echo "ERROR: refusing to write '$rel': destination is not safely inside the project root." >&2
        return 1
    fi
    mkdir -p "$(dirname "$dst")"
    new_tmp "$dst" tmp || return 1
    if ! cat > "$tmp"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
    # Rewritten generated files keep the mode they already had (or a normal
    # 0644 on first creation) instead of mktemp's 0600.
    mode="0644"
    if [ -e "$dst" ] && command -v stat >/dev/null 2>&1; then
        mode="$(stat -c '%a' "$dst" 2>/dev/null || stat -f '%Lp' "$dst" 2>/dev/null || true)"
    fi
    [ -n "$mode" ] && chmod "$mode" "$tmp" 2>/dev/null || true
    if ! mv "$tmp" "$dst"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
}

# Restores a snapshot to its destination atomically, preserving the snapshot's
# permission bits (snapshot_file keeps them via cp -p), so rollback repairs the
# original mode and not only the content.
safe_atomic_restore() {
    local snap="$1" rel="$2" dst="$TARGET_DIR/$2" tmp
    if ! assert_safe_destination "$rel"; then
        return 1
    fi
    mkdir -p "$(dirname "$dst")"
    new_tmp "$dst" tmp || return 1
    if ! copy_with_mode "$snap" "$tmp"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
    if ! mv "$tmp" "$dst"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
}

safe_remove_file() {
    local rel="$1"
    if ! assert_safe_destination "$rel"; then
        echo "ERROR: refusing to remove '$rel': destination is not safely inside the project root." >&2
        return 1
    fi
    rm -f "$TARGET_DIR/$rel"
}

# Removes one empty directory, but only after confirming its physical location
# stays inside the project root. `cd` follows symlinks, so an emptied directory
# that is (or is reached through) a link to an outside tree is skipped rather
# than deleted. Only ever removes an empty directory (rmdir semantics).
safe_remove_empty_directory() {
    local dir="$1" resolved resolved_root
    [ -e "$dir" ] || return 0
    resolved="$(cd "$dir" 2>/dev/null && pwd -P)" || return 0
    resolved_root="$(cd "$TARGET_DIR" && pwd -P)"
    case "$resolved" in
        "$resolved_root" | "$resolved_root/"*) ;;
        *) return 0 ;;
    esac
    rmdir "$dir" 2>/dev/null || true
}

rollback() {
    local rel dst snap dir
    echo "ERROR: installation failed; restoring '$TARGET_DIR' to its prior state." >&2
    for rel in "${CHANGED_RELS[@]:-}"; do
        dst="$TARGET_DIR/$rel"
        snap="$SNAP_DIR/${rel//\//_}"
        # Never restore through a path that now escapes the project (e.g. a
        # symlink planted mid-transaction): skip it rather than write outside.
        if [ -f "$snap.present" ]; then
            safe_atomic_restore "$snap" "$rel" || continue
        else
            safe_remove_file "$rel" || continue
        fi
    done
    # A failed fresh install can leave behind directories that did not exist
    # before (e.g. .agentic/). Remove any directory that became empty only
    # because of this transaction, walking up toward the project root.
    for rel in "${CHANGED_RELS[@]:-}"; do
        dir="$(dirname "$TARGET_DIR/$rel")"
        while [ "$dir" != "$TARGET_DIR" ] && [ "$dir" != "/" ]; do
            [ "$dir" = "$BACKUP_DIR" ] && [ "$BACKUP_DIR_EXISTED" -eq 1 ] && break
            safe_remove_empty_directory "$dir"
            dir="$(dirname "$dir")"
        done
    done
    if [ "$BACKUP_DIR_EXISTED" -eq 0 ] && [ -n "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR" 2>/dev/null || true
    fi
}

cleanup() {
    local rc=$? f
    if [ "$rc" -ne 0 ]; then
        rollback
    fi
    for f in "${TMP_FILES[@]:-}"; do
        rm -f "$f" 2>/dev/null || true
    done
    [ -n "$SNAP_DIR" ] && rm -rf "$SNAP_DIR" 2>/dev/null || true
    [ -n "$MANIFEST_TMP" ] && rm -f "$MANIFEST_TMP" 2>/dev/null || true
    exit "$rc"
}
trap cleanup EXIT

# Creates an unpredictable scratch file next to $1 (same filesystem, so the
# final `mv` is atomic), records it for cleanup, and stores the path in the
# caller-named variable $2. Command substitution runs in a subshell, so the
# TMP_FILES registration would be lost if the result were captured with
# `$(...)`; assignment through a named variable keeps cleanup able to see every
# temporary file. Never a predictable ".agentic-tmp" name: concurrent installs
# cannot clobber each other.
new_tmp() {
    local prefix="$1" var="$2" f
    f="$(mktemp "$prefix.XXXXXX")" || return 1
    TMP_FILES+=("$f")
    printf -v "$var" '%s' "$f"
}

# Applies $1's permission bits to $2. Uses GNU `stat -c '%a'` on Linux and BSD
# `stat -f '%Lp'` on macOS; both print an octal mode suitable for chmod. Fails
# open (never aborts a copy) when stat is unavailable.
apply_mode_from() {
    local src="$1" dst="$2" mode
    if command -v stat >/dev/null 2>&1; then
        mode="$(stat -c '%a' "$src" 2>/dev/null || stat -f '%Lp' "$src" 2>/dev/null || true)"
        if [ -n "$mode" ]; then
            chmod "$mode" "$dst" 2>/dev/null || true
        fi
    fi
}

# Copies $1 into $2, then restores $1's permission bits on $2. `mktemp` creates
# the scratch file with mode 0600, and a plain `cp` keeps that mode, so without
# this an installed `.agentic/scripts/verify.sh` would silently lose its
# executable bits.
copy_with_mode() {
    local src="$1" dst="$2"
    cp "$src" "$dst" || return 1
    apply_mode_from "$src" "$dst"
}

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
    snapshot_file ".agentic-backup/$flat"
    atomic_copy "$src" ".agentic-backup/$flat"
    echo "  backup $rel -> .agentic-backup/$flat"
}

install_managed() {
    local src="$1" rel="$2"
    local dst="$TARGET_DIR/$rel" prev cur
    if [ ! -e "$dst" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  copy   $rel (create)"; return; }
        snapshot_file "$rel"
        atomic_copy "$src" "$rel"
        echo "  copy   $rel (create)"
        printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        return
    fi
    if [ "$REPLACE_MANAGED" -eq 1 ]; then
        [ "$PLAN" -eq 1 ] && { echo "  copy   $rel (replace: --replace-managed)"; return; }
        snapshot_file "$rel"
        [ "$BACKUP" -eq 1 ] && backup_file "$rel"
        atomic_copy "$src" "$rel"
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
            atomic_copy "$src" "$rel"
            echo "  update $rel (unchanged since last install)"
            printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
        else
            [ "$PLAN" -eq 1 ] && { echo "  conflict $rel (modified since install; candidate: $rel.new)"; return; }
            snapshot_file "$rel"
            snapshot_file "$rel.new"
            atomic_copy "$src" "$rel.new"
            echo "  conflict $rel (modified since install; wrote $rel.new)"
            printf '%s\t%s\t%s\n' "$rel" managed "$(cksum_file "$src")" >> "$MANIFEST_TMP"
        fi
    else
        [ "$PLAN" -eq 1 ] && { echo "  conflict $rel (pre-existing; candidate: $rel.new)"; return; }
        snapshot_file "$rel"
        snapshot_file "$rel.new"
        atomic_copy "$src" "$rel.new"
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
    atomic_copy "$src" "$rel"
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

# ---------------------------------------------------------------------------
# Shared merge-marker parsing. Both install_merge and the prune/uninstall path
# classify a merge file the same way so their behavior can never diverge:
#   absent    file does not exist
#   empty     file exists but has no non-whitespace content
#   plain     file has content but no framework markers
#   valid     exactly one start + one end marker, end after start
#   malformed any other marker arrangement (never rewritten in place)
# merge_state <rel> sets MERGE_STATE and, for a valid block, MS_START/MS_END.
# ---------------------------------------------------------------------------
MERGE_STATE=""
MS_START=""
MS_END=""

merge_state() {
    local rel="$1" dst="$TARGET_DIR/$rel"
    local start_count end_count start_line end_line
    MERGE_STATE=""
    MS_START=""
    MS_END=""
    if [ ! -e "$dst" ]; then
        MERGE_STATE="absent"
        return 0
    fi
    start_count="$(grep -c -F -- "$START_MARKER" "$dst" 2>/dev/null || true)"
    end_count="$(grep -c -F -- "$END_MARKER" "$dst" 2>/dev/null || true)"
    start_line="$(grep -n -F -- "$START_MARKER" "$dst" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
    end_line="$(grep -n -F -- "$END_MARKER" "$dst" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
    if [ "$start_count" -gt 1 ] || [ "$end_count" -gt 1 ] \
        || { [ "$start_count" -eq 1 ] && [ "$end_count" -eq 0 ]; } \
        || { [ "$start_count" -eq 0 ] && [ "$end_count" -eq 1 ]; } \
        || { [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] && [ "$end_line" -le "$start_line" ]; }; then
        MERGE_STATE="malformed"
    elif [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ]; then
        MERGE_STATE="valid"
        MS_START="$start_line"
        MS_END="$end_line"
    elif [ -s "$dst" ]; then
        MERGE_STATE="plain"
    else
        MERGE_STATE="empty"
    fi
    return 0
}

# True when removing the managed block from $rel would leave no non-whitespace
# content behind. Read-only: lets --plan report the would-be outcome.
merge_remainder_blank() {
    local rel="$1" dst="$TARGET_DIR/$rel"
    merge_state "$rel"
    [ "$MERGE_STATE" = "valid" ] || return 1
    if {
        [ "$MS_START" -gt 1 ] && head -n "$((MS_START - 1))" "$dst"
        tail -n +"$((MS_END + 1))" "$dst"
    } | grep -q '[^[:space:]]'; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Previous-manifest validation. The manifest is the record of what this
# installer may later prune or replace; it is never trusted implicitly. A
# malformed entry hard-fails the run before anything is written, so a tampered
# or adversarial manifest can never steer the installer into removing files
# outside its documented scope.
# ---------------------------------------------------------------------------

# Lexical checks: a valid manifest path is relative, has no empty / "." / ".."
# segments, no drive-letter prefix, no backslashes, and no control characters.
lexical_manifest_path_ok() {
    local p="$1" seg
    [ -n "$p" ] || return 1
    case "$p" in
        /*) return 1 ;;
        *[[:cntrl:]]*) return 1 ;;
        *'\\'*) return 1 ;;
        [A-Za-z]:*) return 1 ;;
    esac
    while [ -n "$p" ]; do
        case "$p" in
            */*) seg="${p%%/*}"; p="${p#*/}" ;;
            *) seg="$p"; p="" ;;
        esac
        case "$seg" in
            '' | '.' | '..') return 1 ;;
        esac
    done
    return 0
}

# Resolves $1 to a canonical absolute path, following directory symlinks via
# `cd -P` and the final component via readlink when it is itself a symlink.
# Returns 1 when the path cannot be resolved.
resolve_physical() {
    local p="$1" depth="${2:-0}" parent name target new
    [ "$depth" -lt 8 ] || return 1
    parent="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
    name="$(basename "$p")"
    if [ -L "$p" ]; then
        target="$(readlink "$p")"
        case "$target" in
            /*) new="$target" ;;
            *) new="$parent/$target" ;;
        esac
        resolve_physical "$new" "$((depth + 1))"
    else
        printf '%s/%s\n' "$parent" "$name"
    fi
}

# True when $rel stays physically at or beneath the physical project root. A
# symlinked directory inside the project that points outside, or a final
# component that is a symlink to an outside path, fails confinement. Paths
# whose parent does not exist cannot escape and are accepted.
physical_within_root() {
    local rel="$1" resolved resolved_root
    if [ -e "$TARGET_DIR/$(dirname "$rel")" ] || [ -L "$TARGET_DIR/$rel" ]; then
        resolved="$(resolve_physical "$TARGET_DIR/$rel" 2>/dev/null)" || return 1
        resolved_root="$(cd "$TARGET_DIR" && pwd -P)"
        case "$resolved" in
            "$resolved_root" | "$resolved_root/"*) return 0 ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

# Central write-confinement primitive. Refuses a destination $TARGET_DIR/$1
# when:
#   - the final component exists as a symlink (a write would follow it, and an
#     in-project symlink is still an unexpected indirection for a framework
#     file), or
#   - the nearest existing ancestor resolves physically outside the project
#     root (e.g. .agentic -> /outside, even when the leaf does not exist yet).
# Paths whose ancestors do not exist cannot escape and are accepted.
assert_safe_destination() {
    local rel="$1" full leaf parent resolved resolved_root
    [ -n "$rel" ] || return 1
    full="$TARGET_DIR/$rel"
    [ -L "$full" ] && return 1
    leaf="$full"
    while [ ! -e "$leaf" ] && [ ! -L "$leaf" ]; do
        parent="$(dirname "$leaf")"
        [ "$parent" = "$leaf" ] && break
        leaf="$parent"
    done
    resolved="$(resolve_physical "$leaf" 2>/dev/null)" || return 1
    resolved_root="$(cd "$TARGET_DIR" && pwd -P)"
    case "$resolved" in
        "$resolved_root" | "$resolved_root/"*) return 0 ;;
    esac
    return 1
}

# Atomic install write: asserts the destination is safe, then copies $1 onto a
# scratch file created next to $2 (same filesystem, so the final rename is a
# single atomic step), preserving the source's permission bits. An interrupted
# copy can never expose a partially written destination, and a pre-existing
# destination is only ever replaced by rename. $2 is relative to TARGET_DIR.
atomic_copy() {
    safe_atomic_copy "$@"
}

# Validates the on-disk install manifest when one exists; returns 1 on any
# malformed entry. Read-only, so it also runs under --plan.
validate_previous_manifest() {
    local mf line_num=0 line seen="" first=1 p c s expected
    mf="$(manifest_file)"
    [ -f "$mf" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        line="${line%$'\r'}"
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac
        if [ "$first" -eq 1 ]; then
            first=0
            if ! [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "ERROR: install manifest line $line_num is not a valid version header ('$line')." >&2
                return 1
            fi
            continue
        fi
        # awk's -F'\t' never collapses adjacent tabs nor trims leading/trailing
        # ones, unlike `IFS=$'\t' read`, so a row with an empty or extra field
        # is rejected here and Bash and PowerShell agree on "exactly three
        # fields". (Tabs are translated to a non-whitespace IFS character first,
        # mirroring verify.sh, because tab is IFS whitespace.)
        if ! printf '%s\n' "$line" | awk -F'\t' 'NF==3 {exit 0} {exit 1}'; then
            echo "ERROR: install manifest line $line_num is malformed (expected exactly three tab-separated fields: path, category, sha256)." >&2
            return 1
        fi
        IFS=$'\t' read -r p c s <<< "$line"
        if [ -z "$p" ] || [ -z "$c" ] || [ -z "$s" ]; then
            echo "ERROR: install manifest line $line_num is malformed (expected path<TAB>category<TAB>sha256)." >&2
            return 1
        fi
        case "$c" in
            managed|merge|seed) ;;
            *) echo "ERROR: install manifest line $line_num has invalid category '$c' for '$p'." >&2; return 1 ;;
        esac
        if ! [[ "$s" =~ ^[0-9a-f]{64}$ ]]; then
            echo "ERROR: install manifest line $line_num has invalid checksum for '$p'." >&2
            return 1
        fi
        if ! lexical_manifest_path_ok "$p"; then
            echo "ERROR: install manifest line $line_num has invalid path '$p'." >&2
            return 1
        fi
        case " $seen " in
            *" $p "*)
                echo "ERROR: install manifest line $line_num has duplicate path '$p'." >&2
                return 1 ;;
        esac
        seen="$seen $p"
        if ! expected="$(manifest_category "$p")"; then
            echo "ERROR: install manifest line $line_num records path '$p', which is not a framework-managed path." >&2
            return 1
        fi
        if [ "$c" != "$expected" ]; then
            echo "ERROR: install manifest line $line_num records category '$c' for '$p'; expected '$expected'." >&2
            return 1
        fi
        if ! physical_within_root "$p"; then
            echo "ERROR: install manifest line $line_num path '$p' escapes the project root." >&2
            return 1
        fi
    done < "$mf"
    if [ "$first" -eq 1 ]; then
        echo "ERROR: install manifest '$mf' contains no version header." >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Migration, pruning, and uninstall. A previous install is described by the
# on-disk manifest; a file is obsolete when it is no longer in the desired set
# (for example a deselected tool adapter). Managed files are pruned only when
# unchanged since the recorded checksum; merge files are pruned by stripping
# the marker-delimited managed block and removing the file only if that leaves
# nothing behind. Seeds are project-owned and never pruned.
# ---------------------------------------------------------------------------

# Entries (path<TAB>category<TAB>sha256) recorded by a previous install.
prev_manifest_entries() {
    local mf
    mf="$(manifest_file)"
    [ -f "$mf" ] || return 0
    awk -F'\t' 'NF>=3 && $1 !~ /^#/ {print}' "$mf"
}

# True when $rel is part of the current desired set (including the seeded
# .agentic/checks.tsv, which install_seed_checks records under seed).
is_desired() {
    local rel="$1" r
    [ "$rel" = ".agentic/checks.tsv" ] && return 0
    for r in "${MANAGED_FILES[@]}" "${SEED_FILES[@]}" "${MERGE_FILES[@]}"; do
        [ "$r" = "$rel" ] && return 0
    done
    return 1
}

file_is_blank() {  # file_is_blank <file>
    [ ! -s "$1" ] && return 0
    ! grep -q '[^[:space:]]' "$1"
}

# Removes a well-formed marker-delimited managed block from a merge file.
# Returns 0 on success; 1 when the markers are malformed (never rewritten).
strip_merge_block() {
    local rel="$1" tmp
    local dst="$TARGET_DIR/$rel"
    merge_state "$rel"
    if [ "$MERGE_STATE" != "valid" ]; then
        return 1
    fi
    [ "$PLAN" -eq 1 ] && return 0
    snapshot_file "$rel"
    [ "$BACKUP" -eq 1 ] && backup_file "$rel"
    if ! (
        if [ "$MS_START" -gt 1 ]; then head -n "$((MS_START - 1))" "$dst"; fi
        tail -n +"$((MS_END + 1))" "$dst"
    ) | safe_atomic_write "$rel"; then
        return 1
    fi
    return 0
}

# Removes a single obsolete entry. $3 may be empty for unrecorded files.
prune_entry() {
    local rel="$1" cat="$2" cks="$3" cur
    local dst="$TARGET_DIR/$rel"
    case "$cat" in
        seed)
            return 0 ;;
        merge)
            if [ -e "$dst" ]; then
                merge_state "$rel"
                case "$MERGE_STATE" in
                    malformed)
                        echo "  conflict $rel (malformed merge markers; not pruned)"
                        return 0 ;;
                    valid)
                        if [ "$PLAN" -eq 1 ]; then
                            if merge_remainder_blank "$rel"; then
                                echo "  prune  $rel (managed block removed; file would be empty)"
                            else
                                echo "  prune  $rel (managed block removed; custom content preserved)"
                            fi
                        else
                            if strip_merge_block "$rel"; then
                                if file_is_blank "$dst"; then
                                    snapshot_file "$rel"
                                    [ "$BACKUP" -eq 1 ] && backup_file "$rel"
                                    safe_remove_file "$rel"
                                    echo "  prune  $rel (managed block removed; file removed)"
                                else
                                    echo "  prune  $rel (managed block removed; custom content preserved)"
                                fi
                            else
                                echo "  conflict $rel (malformed merge markers; not pruned)"
                            fi
                        fi
                        return 0 ;;
                    plain)
                        echo "  note   $rel (no managed block found; custom content preserved)"
                        return 0 ;;
                    empty)
                        [ "$PLAN" -eq 1 ] && { echo "  prune  $rel (empty; no managed content)"; return 0; }
                        snapshot_file "$rel"
                        [ "$BACKUP" -eq 1 ] && backup_file "$rel"
                        safe_remove_file "$rel"
                        echo "  prune  $rel (empty; no managed content)"
                        return 0 ;;
                esac
            fi
            return 0 ;;
        managed)
            if [ ! -e "$dst" ]; then
                echo "  note   $rel (already absent; nothing to prune)"
                return 0
            fi
            cur="$(cksum_file "$dst")"
            if [ "$cks" = "$cur" ]; then
                [ "$PLAN" -eq 1 ] && { echo "  prune  $rel (unchanged since install)"; return 0; }
                snapshot_file "$rel"
                [ "$BACKUP" -eq 1 ] && backup_file "$rel"
                safe_remove_file "$rel"
                echo "  prune  $rel (unchanged since install)"
            else
                echo "  conflict $rel (modified since install; preserved)"
            fi
            return 0 ;;
    esac
}

# True when $rel (a legacy file path) is provably a framework artifact. A
# manifest record is never sufficient on its own: ownership must be evidenced
# by content (a checksum match against the exact v1.0 content, or a framework
# signature in the file), otherwise the file is only removed via
# --prune-unverified-legacy after a mandatory backup.
legacy_owned() {
    local rel="$1" known cur
    known="$(legacy_v10_checksum "$rel")"
    if [ -n "$known" ]; then
        cur="$(cksum_file "$TARGET_DIR/$rel")"
        [ "$cur" = "$known" ] && return 0
    fi
    if grep -q -E '@@AGENTIC-PROTOCOL-|Universal Agentic Development Protocol|\.agentic/Memory/' "$TARGET_DIR/$rel" 2>/dev/null; then
        return 0
    fi
    return 1
}

# v1.0 adapter files are removed only by explicit --prune/--uninstall, and only
# when their content can be proven to be framework material. Unverifiable files
# are preserved as conflicts unless --prune-unverified-legacy is given, in
# which case they are removed after a mandatory backup to .agentic-backup/.
prune_legacy() {
    local f
    for f in "${LEGACY_FILES[@]}"; do
        if [ -e "$TARGET_DIR/$f" ]; then
            if legacy_owned "$f"; then
                [ "$PLAN" -eq 1 ] && { echo "  prune  $f (legacy v1.0 artifact)"; continue; }
                snapshot_file "$f"
                [ "$BACKUP" -eq 1 ] && backup_file "$f"
                safe_remove_file "$f"
                echo "  prune  $f (legacy v1.0 artifact)"
            elif [ "$PRUNE_UNVERIFIED_LEGACY" -eq 1 ]; then
                [ "$PLAN" -eq 1 ] && { echo "  prune  $f (unverified legacy artifact; would back up to .agentic-backup first)"; continue; }
                snapshot_file "$f"
                backup_file "$f"
                safe_remove_file "$f"
                echo "  prune  $f (unverified legacy artifact; backed up to .agentic-backup)"
            else
                echo "  conflict $f (content could not be verified as a v1.0 framework artifact; preserved; use --prune-unverified-legacy to remove)"
            fi
        fi
    done
    for f in "${LEGACY_DIRS[@]}"; do
        if [ -e "$TARGET_DIR/$f" ]; then
            echo "  note   legacy directory $f/ left in place (may contain user settings); remove manually if unused"
        fi
    done
}

# Reports v1.0 legacy artifacts without touching them (used on plain update).
report_legacy() {
    local f
    for f in "${LEGACY_FILES[@]}" "${LEGACY_DIRS[@]}"; do
        if [ -e "$TARGET_DIR/$f" ]; then
            echo "  note   legacy $f (v1.0 artifact; run --prune to remove)"
        fi
    done
}

# Prunes every previous-manifest entry that is no longer desired. Used both as
# the migration step of an update and by the standalone --prune operation.
prune_obsolete() {
    local p c s
    while IFS=$'\t' read -r p c s; do
        is_desired "$p" || prune_entry "$p" "$c" "$s"
    done < <(prev_manifest_entries)
}

# Rewrites the manifest without the pruned entries (standalone --prune path;
# the update path rebuilds the manifest from this install's records instead).
write_pruned_manifest() {
    local mf
    [ "$PLAN" -eq 1 ] && return
    mf="$(manifest_file)"
    [ -f "$mf" ] || return 0
    snapshot_file ".agentic/install-manifest.tsv"
    {
        echo "# agentic-workflow install manifest (auto-generated)"
        echo "# path<TAB>category<TAB>sha256"
        echo "$PROTOCOL_VERSION"
        while IFS=$'\t' read -r p c s; do
            is_desired "$p" && printf '%s\t%s\t%s\n' "$p" "$c" "$s"
        done < <(prev_manifest_entries)
        # `read` at EOF returns 1, which would fail the whole pipeline under
        # pipefail; the group must end with a success for the manifest to land.
        :
    } | safe_atomic_write ".agentic/install-manifest.tsv"
}

uninstall() {
    local p c s
    echo ""
    echo "Uninstalling Universal Agentic Development Protocol v$PROTOCOL_VERSION"
    echo "  from: $TARGET_DIR"
    echo "  preserving project-owned seed files and custom merge content"
    echo ""
    while IFS=$'\t' read -r p c s; do
        prune_entry "$p" "$c" "$s"
    done < <(prev_manifest_entries)
    prune_legacy
    if [ -f "$(manifest_file)" ]; then
        [ "$PLAN" -eq 1 ] && { echo "  prune  .agentic/install-manifest.tsv"; return 0; }
        snapshot_file ".agentic/install-manifest.tsv"
        safe_remove_file ".agentic/install-manifest.tsv"
        echo "  prune  .agentic/install-manifest.tsv"
    fi
    if [ "$PLAN" -eq 1 ]; then
        echo "  note   empty framework directories under .agentic/ would be removed"
    else
        # Seed files keep .agentic/ itself and its project-owned contents alive;
        # only directories emptied by managed-file removal are cleaned up. The
        # confinement guard rejects a linked .agentic so the find never walks
        # into (and empties) an external tree.
        if assert_safe_destination ".agentic"; then
            find "$TARGET_DIR/.agentic" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        fi
    fi
}

install_merge() {
    local src="$1" rel="$2"
    local dst="$TARGET_DIR/$rel" tmp
    merge_state "$rel"
    case "$MERGE_STATE" in
        absent)
            [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (create)"; return; }
            snapshot_file "$rel"
            atomic_copy "$src" "$rel"
            echo "  merge  $rel (create)"
            printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
            return ;;
        malformed)
            # A malformed marker set is never rewritten in place: the adopter's
            # file is preserved and the framework content goes to a candidate.
            [ "$PLAN" -eq 1 ] && { echo "  conflict $rel (malformed merge markers; candidate: $rel.new)"; return; }
            snapshot_file "$rel"
            snapshot_file "$rel.new"
            atomic_copy "$src" "$rel.new"
            echo "  conflict $rel (malformed merge markers detected; wrote $rel.new)"
            printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$src")" >> "$MANIFEST_TMP"
            return ;;
        valid)
            [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (update managed block, preserve custom content)"; return; }
            snapshot_file "$rel"
            [ "$BACKUP" -eq 1 ] && backup_file "$rel"
            if ! (
                if [ "$MS_START" -gt 1 ]; then head -n "$((MS_START - 1))" "$dst"; fi
                cat "$src"
                tail -n +"$((MS_END + 1))" "$dst"
            ) | safe_atomic_write "$rel"; then
                echo "ERROR: failed to rewrite '$rel'." >&2
                exit 1
            fi
            echo "  merge  $rel (managed block updated, custom content preserved)"
            printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
            return ;;
        plain)
            [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (insert managed block above existing content)"; return; }
            snapshot_file "$rel"
            [ "$BACKUP" -eq 1 ] && backup_file "$rel"
            if ! ( cat "$src"; printf '\n\n---\n\n'; cat "$dst" ) | safe_atomic_write "$rel"; then
                echo "ERROR: failed to rewrite '$rel'." >&2
                exit 1
            fi
            echo "  merge  $rel (managed block inserted, existing content preserved)"
            printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
            return ;;
        empty)
            [ "$PLAN" -eq 1 ] && { echo "  merge  $rel (create)"; return; }
            snapshot_file "$rel"
            atomic_copy "$src" "$rel"
            echo "  merge  $rel (create)"
            printf '%s\t%s\t%s\n' "$rel" merge "$(cksum_file "$dst")" >> "$MANIFEST_TMP"
            return ;;
    esac
}

# Runs stack detection and writes (or, when nothing is detected, removes)
# .agentic/checks.generated.tsv through the confined destination-local atomic
# primitives. The verifier's own --detect-checks mode is deliberately not
# invoked for the write: it would `mkdir -p .agentic` and `mv` from the system
# temp directory, neither confined to the project root nor destination-local.
# Detection output is captured on stdout (--emit-checks) and staged next to the
# candidate, validated, then renamed into place.
write_generated_candidate() {
    local gen_rel=".agentic/checks.generated.tsv" tmp detection
    if ! assert_safe_destination "$gen_rel"; then
        echo "ERROR: refusing to write '$gen_rel': destination is not safely inside the project root." >&2
        return 1
    fi
    mkdir -p "$TARGET_DIR/.agentic"
    new_tmp "$TARGET_DIR/$gen_rel" tmp || return 1
    if ! detection="$(cd "$TARGET_DIR" && bash "$SOURCE_DIR/.agentic/scripts/verify.sh" --emit-checks 2>/dev/null)"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
    if [ -n "$detection" ]; then
        {
            echo "# .agentic/checks.generated.tsv — candidate verification contract."
            echo "# Auto-generated by detection workflow. Review assumptions and promote to .agentic/checks.tsv"
            printf '%s\n' "$detection"
        } > "$tmp"
        if ! (cd "$TARGET_DIR" && bash "$SOURCE_DIR/.agentic/scripts/verify.sh" --validate-checks "$tmp"); then
            rm -f "$tmp" 2>/dev/null || true
            return 1
        fi
        mv "$tmp" "$TARGET_DIR/$gen_rel"
        echo "Candidate contract written to $gen_rel"
    else
        rm -f "$tmp" 2>/dev/null || true
        safe_remove_file "$gen_rel"
        echo "No stack detected. Removed stale candidate '$gen_rel'." >&2
    fi
    return 0
}

generate_checks() {
    local gen="$TARGET_DIR/.agentic/checks.generated.tsv"
    local rel=".agentic/checks.tsv"
    local dst="$TARGET_DIR/$rel"
    if [ -e "$dst" ] && [ "$REPLACE_CHECKS" -eq 0 ]; then
        echo "  skip   $rel (project-owned; use --replace-checks to overwrite)"
        return
    fi
    if [ "$PLAN" -eq 1 ]; then
        echo "  gen    $rel (plan: detect and validate candidate checks, then promote)"
        return
    fi
    # Detection creates, replaces, or removes the generated candidate; snapshot
    # it before detection so a failed install restores a reviewed candidate (or
    # removes a freshly generated one) exactly as it was before this run.
    snapshot_file ".agentic/checks.generated.tsv"
    write_generated_candidate || exit 1
    if [ ! -f "$gen" ]; then
        echo "  note   no stack detected; $rel not generated"
        return
    fi
    snapshot_file "$rel"
    [ "$BACKUP" -eq 1 ] && [ -e "$dst" ] && backup_file "$rel"
    atomic_copy "$gen" "$rel"
    echo "  gen    $rel (from detected stack)"
}

write_manifest() {
    [ "$PLAN" -eq 1 ] && return
    snapshot_file ".agentic/install-manifest.tsv"
    {
        echo "# agentic-workflow install manifest (auto-generated)"
        echo "# path<TAB>category<TAB>sha256"
        echo "$PROTOCOL_VERSION"
        cat "$MANIFEST_TMP"
    } | safe_atomic_write ".agentic/install-manifest.tsv"
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

# The previous manifest is never trusted implicitly: any malformed entry fails
# the run before a single file is touched. Read-only, so it also guards --plan.
validate_previous_manifest || exit 1

if [ "$DETECT_CHECKS" -eq 1 ]; then
    if [ "$PLAN" -eq 1 ]; then
        echo "=== Project Detection Explanation (Plan) ==="
        (cd "$TARGET_DIR" && bash "$SOURCE_DIR/.agentic/scripts/verify.sh" --explain-detection)
        echo "  gen    .agentic/checks.generated.tsv (from detected stack)"
        exit 0
    fi
    # Snapshot so a failed detection rolls the candidate back to its prior
    # state (or removes a freshly created one) instead of leaving a partial
    # file behind.
    snapshot_file ".agentic/checks.generated.tsv"
    write_generated_candidate || exit 1
    exit 0
fi

if [ "$PRUNE" -eq 1 ]; then
    prune_obsolete
    prune_legacy
    write_pruned_manifest
    echo ""
    echo "Prune complete. Seeds and project-owned files were preserved."
    exit 0
fi

if [ "$UNINSTALL" -eq 1 ]; then
    uninstall
    echo ""
    echo "Uninstall complete. Project-owned seed files (.agentic/ARCHITECTURE.md,"
    echo "STATUS.md, checks.tsv, tasks/, decisions/) were left in place."
    exit 0
fi

if [ "$ACCEPT_DETECTED_CHECKS" -eq 1 ]; then
    gen="$TARGET_DIR/.agentic/checks.generated.tsv"
    rel=".agentic/checks.tsv"
    dst="$TARGET_DIR/$rel"
    if [ ! -f "$gen" ]; then
        echo "Error: '$gen' does not exist. Run with --detect-checks first." >&2
        exit 1
    fi
    if [ -e "$dst" ] && [ "$REPLACE_CHECKS" -eq 0 ]; then
        if [ "$PLAN" -eq 1 ]; then
            echo "  skip   $rel (project-owned; use --replace-checks to overwrite)"
            exit 0
        fi
        echo "Error: '$dst' already exists. Use --replace-checks to overwrite." >&2
        exit 1
    fi
    if [ "$PLAN" -eq 1 ]; then
        echo "  promote $gen -> $rel"
        exit 0
    fi
    (cd "$TARGET_DIR" && bash "$SOURCE_DIR/.agentic/scripts/verify.sh" --validate-checks "$gen") || exit 1

    snapshot_file "$rel"
    [ "$BACKUP" -eq 1 ] && [ -e "$dst" ] && backup_file "$rel"
    atomic_copy "$gen" "$rel"
    echo "  promoted '$gen' to '$rel'"
    exit 0
fi

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

# Migration step of an update: files recorded by a previous install that are no
# longer part of the desired set (deselected adapters, renamed framework files)
# are pruned before the manifest is rewritten. Legacy v1.0 artifacts are only
# reported here; --prune/--uninstall remove them explicitly.
prune_obsolete
report_legacy

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