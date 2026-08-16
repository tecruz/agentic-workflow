#!/usr/bin/env bats

# install.sh — ownership, merge, and manifest tests.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"
OUTSIDE_DIR=""

setup() {
    TMP="$(mktemp -d)"
    cd "$TMP"
}

teardown() {
    cd "$REPO_ROOT"
    rm -rf "$TMP"
    [ -z "$OUTSIDE_DIR" ] || rm -rf "$OUTSIDE_DIR"
}

# A directory physically outside the project root (a sibling of the per-test
# $TMP), used by the symlink-confinement tests. Registered for teardown cleanup.
make_outside_dir() {
    OUTSIDE_DIR="$(mktemp -d "$(dirname "$TMP")/outside-XXXXXX")"
    printf '%s' "$OUTSIDE_DIR"
}

@test "fresh install creates the core file set and manifest" {
    bash "$INSTALL" . >/dev/null 2>&1
    [ -f AGENTS.md ]
    [ -f CLAUDE.md ]
    [ -f GEMINI.md ]
    [ -f .aider.conf.yml ]
    [ -f .agentic/VERSION ]
    [ -f .agentic/checks.tsv ]
    [ -f .agentic/ARCHITECTURE.md ]
    [ -f .agentic/STATUS.md ]
    [ -f .agentic/install-manifest.tsv ]
    grep -q "managed" .agentic/install-manifest.tsv
    grep -q "seed" .agentic/install-manifest.tsv
}

@test "install is idempotent: second run updates without conflicts" {
    bash "$INSTALL" . >/dev/null 2>&1
    bash "$INSTALL" . >/dev/null 2>&1
    [ ! -f .agentic/VERSION.new ]
    [ ! -f AGENTS.md.new ]
    [ -f AGENTS.md ]
}

@test "--plan makes no changes" {
    printf 'keep me\n' > AGENTS.md
    bash "$INSTALL" . --plan >/dev/null 2>&1
    [ "$(cat AGENTS.md)" = "keep me" ]
    [ ! -f .agentic/install-manifest.tsv ]
    [ ! -f CLAUDE.md ]
}

@test "seed files are never overwritten" {
    mkdir -p .agentic
    printf 'my custom checks\n' > .agentic/checks.tsv
    bash "$INSTALL" . >/dev/null 2>&1
    grep -q "my custom checks" .agentic/checks.tsv
}

@test "a modified managed file produces a conflict candidate and is not clobbered" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\n# custom\n' >> .agentic/WORKFLOW.md
    bash "$INSTALL" . >/dev/null 2>&1
    [ -f .agentic/WORKFLOW.md.new ]
    grep -q "# custom" .agentic/WORKFLOW.md
}

@test "--replace-managed overwrites a modified managed file" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\n# custom\n' >> .agentic/WORKFLOW.md
    bash "$INSTALL" . --replace-managed >/dev/null 2>&1
    [ ! -f .agentic/WORKFLOW.md.new ]
    grep -q "Universal Agentic Development Workflow" .agentic/WORKFLOW.md
}

@test "merge preserves custom content around the managed block" {
    printf 'TOP CUSTOM CONTENT\n' > AGENTS.md
    bash "$INSTALL" . >/dev/null 2>&1
    grep -q "TOP CUSTOM CONTENT" AGENTS.md
    grep -q "AGENTIC-PROTOCOL-START" AGENTS.md
    grep -q "AGENTIC-PROTOCOL-END" AGENTS.md
    # the managed block must appear ABOVE the custom content
    local start end top
    start="$(grep -n -F 'AGENTIC-PROTOCOL-START' AGENTS.md | cut -d: -f1)"
    top="$(grep -n -F 'TOP CUSTOM CONTENT' AGENTS.md | cut -d: -f1)"
    [ "$start" -lt "$top" ]
}

@test "update preserves custom content appended below the managed block" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\n## Team notes\nkeep this\n' >> AGENTS.md
    bash "$INSTALL" . >/dev/null 2>&1
    grep -q "keep this" AGENTS.md
    [ ! -f AGENTS.md.new ]
}

@test "--tools all installs AGENTS.md, CLAUDE.md, GEMINI.md, .aider.conf.yml" {
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    [ -f AGENTS.md ]
    [ -f CLAUDE.md ]
    [ -f GEMINI.md ]
    [ -f .aider.conf.yml ]
}

@test "--tools claude installs only AGENTS.md + CLAUDE.md" {
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    [ -f AGENTS.md ]
    [ -f CLAUDE.md ]
    [ ! -f GEMINI.md ]
    [ ! -f .aider.conf.yml ]
}

@test "--generate-checks writes stack-detected checks into .agentic/checks.tsv" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --generate-checks >/dev/null 2>&1
    grep -q $'\tnpm\t' .agentic/checks.tsv
}

@test "checks.tsv is seeded from the template (not the framework's own checks)" {
    bash "$INSTALL" . >/dev/null 2>&1
    # the generic template documents the format; the framework's own checks.tsv
    # contains 'ps-syntax', which must NOT leak into adopters
    ! grep -q "ps-syntax" .agentic/checks.tsv
    grep -q "requirement<TAB>check-id" .agentic/checks.tsv
}

@test "--backup writes pre-modification copies to .agentic-backup" {
    bash "$INSTALL" . >/dev/null 2>&1
    bash "$INSTALL" . --backup >/dev/null 2>&1
    [ -d .agentic-backup ]
    [ -f .agentic-backup/AGENTS.md ]
}

@test "malformed merge markers produce a conflict candidate and are not clobbered" {
    printf '%s\n' '<!-- @@AGENTIC-PROTOCOL-START@@ -->' 'broken' '<!-- @@AGENTIC-PROTOCOL-START@@ -->' > AGENTS.md
    bash "$INSTALL" . >/dev/null 2>&1
    [ -f AGENTS.md.new ]
    grep -q "broken" AGENTS.md
    [ "$(grep -c -F 'AGENTIC-PROTOCOL-START' AGENTS.md)" -eq 2 ]
}

@test "a failed install rolls back partial changes" {
    mkdir -p .agentic
    printf 'blocker\n' > .agentic/tasks
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    [ ! -f .agentic/VERSION ]
    [ ! -f .agentic/rules/01-general-principles.md ]
    [ ! -f AGENTS.md ]
    [ ! -f .agentic/install-manifest.tsv ]
    [ -f .agentic/tasks ]
    [ "$(cat .agentic/tasks)" = "blocker" ]
}

@test "an update that fails after the merge phase restores the merged files" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\n## Team notes\nkeep this content\n' >> AGENTS.md
    # Atomic temp-file writes can no longer be blocked by a read-only manifest
    # (mv only needs directory write access). Force the update to fail inside
    # write_manifest by turning the manifest path into a directory, which
    # snapshot_file cannot copy.
    rm .agentic/install-manifest.tsv
    mkdir .agentic/install-manifest.tsv
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    grep -q "keep this content" AGENTS.md
    grep -q "AGENTIC-PROTOCOL-START" AGENTS.md
}

@test "reversed merge markers produce a conflict candidate and are not clobbered" {
    printf '%s\n' '<!-- @@AGENTIC-PROTOCOL-END@@ -->' 'custom content' '<!-- @@AGENTIC-PROTOCOL-START@@ -->' > AGENTS.md
    bash "$INSTALL" . >/dev/null 2>&1
    [ -f AGENTS.md.new ]
    grep -q "custom content" AGENTS.md
    [ "$(grep -c -F 'AGENTIC-PROTOCOL-START' AGENTS.md)" -eq 1 ]
    [ "$(grep -c -F 'AGENTIC-PROTOCOL-END' AGENTS.md)" -eq 1 ]
}

@test "--generate-checks output is rolled back when the install fails" {
    mkdir -p .agentic
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    mkdir .agentic/install-manifest.tsv
    run bash "$INSTALL" . --generate-checks
    [ "$status" -ne 0 ]
    [ ! -f .agentic/checks.tsv ]
    [ ! -f .agentic/VERSION ]
    [ ! -f .agentic/rules/01-general-principles.md ]
    [ ! -f AGENTS.md ]
}

@test "a failed --generate-checks install leaves no generated candidate when none existed" {
    mkdir -p .agentic
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    mkdir .agentic/install-manifest.tsv
    run bash "$INSTALL" . --generate-checks
    [ "$status" -ne 0 ]
    [ ! -f .agentic/checks.generated.tsv ]
    [ ! -f .agentic/checks.tsv ]
}

@test "a failed --generate-checks install restores a reviewed candidate exactly" {
    mkdir -p .agentic
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    printf '# reviewed candidate\n' > .agentic/checks.generated.tsv
    mkdir .agentic/install-manifest.tsv
    run bash "$INSTALL" . --generate-checks
    [ "$status" -ne 0 ]
    [ "$(cat .agentic/checks.generated.tsv)" = "# reviewed candidate" ]
    [ ! -f .agentic/checks.tsv ]
}

@test "a pre-existing .new conflict candidate is restored on rollback" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\n# custom\n' >> .agentic/WORKFLOW.md
    printf 'PRECIOUS CANDIDATE\n' > .agentic/WORKFLOW.md.new
    # see "an update that fails after the merge phase" for why a directory
    # replaces the old read-only-manifest failure mechanism
    rm .agentic/install-manifest.tsv
    mkdir .agentic/install-manifest.tsv
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    grep -q "PRECIOUS CANDIDATE" .agentic/WORKFLOW.md.new
    grep -q "# custom" .agentic/WORKFLOW.md
}

@test "a failed fresh install removes directories it created that are now empty" {
    mkdir -p .agentic
    printf 'blocker\n' > .agentic/templates
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    [ ! -d .agentic/rules ]
    [ ! -d .agentic/scripts ]
    [ -f .agentic/templates ]
    [ "$(cat .agentic/templates)" = "blocker" ]
}

# ---------------------------------------------------------------------------
# Candidate lifecycle regression tests (detect / validate / accept).
# ---------------------------------------------------------------------------

@test "--detect-checks writes a candidate contract for a detected stack" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    run bash "$INSTALL" . --detect-checks --tools claude
    [ "$status" -eq 0 ]
    [ -f .agentic/checks.generated.tsv ]
    grep -q $'\tnpm\t' .agentic/checks.generated.tsv
}

@test "--detect-checks --plan makes no filesystem changes" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    run bash "$INSTALL" . --detect-checks --plan --tools claude
    [ "$status" -eq 0 ]
    [ ! -f .agentic/checks.generated.tsv ]
}

@test "--generate-checks --plan makes no filesystem changes" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    run bash "$INSTALL" . --generate-checks --plan --tools claude
    [ "$status" -eq 0 ]
    [ ! -f .agentic/checks.generated.tsv ]
    [ ! -f .agentic/checks.tsv ]
}

@test "--accept-detected-checks promotes the exact reviewed candidate, not a fresh detection" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    # simulate a human review edit to the candidate
    printf '\n# reviewer note: keep exactly this line\n' >> .agentic/checks.generated.tsv
    run bash "$INSTALL" . --accept-detected-checks --tools claude
    [ "$status" -eq 0 ]
    [ -f .agentic/checks.tsv ]
    grep -q "reviewer note: keep exactly this line" .agentic/checks.tsv
}

@test "--accept-detected-checks --plan makes no filesystem changes" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    run bash "$INSTALL" . --accept-detected-checks --plan --tools claude
    [ "$status" -eq 0 ]
    [ ! -f .agentic/checks.tsv ]
}

@test "--accept-detected-checks rejects an invalid candidate without writing checks.tsv" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    printf 'bogus-requirement\tbad-id\t.\tnpm\ttest\n' > .agentic/checks.generated.tsv
    run bash "$INSTALL" . --accept-detected-checks --tools claude
    [ "$status" -ne 0 ]
    [ ! -f .agentic/checks.tsv ]
}

@test "--accept-detected-checks requires an existing candidate" {
    run bash "$INSTALL" . --accept-detected-checks --tools claude
    [ "$status" -ne 0 ]
    [ ! -f .agentic/checks.tsv ]
}

@test "existing checks.tsv is protected without --replace-checks" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    printf 'project owned checks\n' > .agentic/checks.tsv
    run bash "$INSTALL" . --accept-detected-checks --tools claude
    [ "$status" -ne 0 ]
    grep -q "project owned checks" .agentic/checks.tsv
}

@test "--replace-checks overwrites a project-owned checks.tsv" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    printf 'project owned checks\n' > .agentic/checks.tsv
    run bash "$INSTALL" . --accept-detected-checks --replace-checks --tools claude
    [ "$status" -eq 0 ]
    ! grep -q "project owned checks" .agentic/checks.tsv
    grep -q $'\tnpm\t' .agentic/checks.tsv
}

@test "acceptance does not alter the install manifest" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    cp .agentic/install-manifest.tsv manifest.before
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    run bash "$INSTALL" . --accept-detected-checks --replace-checks --tools claude
    [ "$status" -eq 0 ]
    diff -q manifest.before .agentic/install-manifest.tsv
}

@test "a stale candidate is removed and never promoted when detection finds nothing" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    [ -f .agentic/checks.generated.tsv ]
    rm package.json
    run bash "$INSTALL" . --detect-checks --tools claude
    [ "$status" -eq 0 ]
    [ ! -f .agentic/checks.generated.tsv ]
    run bash "$INSTALL" . --generate-checks --tools claude
    [ "$status" -eq 0 ]
    # the template may be seeded, but stale detection content must not be
    ! grep -q 'node-test' .agentic/checks.tsv 2>/dev/null
    ! grep -q $'\tnpm\t' .agentic/checks.tsv 2>/dev/null
}

@test "detection and acceptance leave no temporary files behind" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    run bash "$INSTALL" . --accept-detected-checks --tools claude
    [ "$status" -eq 0 ]
    [ ! -f .agentic/checks.tsv.agentic-tmp ]
    [ ! -f .agentic/install-manifest.tsv.agentic-tmp ]
}

# ---------------------------------------------------------------------------
# Migration, pruning, and uninstall lifecycle tests (--update migrations,
# --prune, --uninstall, tool-adapter deselection, v1.0 legacy migration).
# ---------------------------------------------------------------------------

@test "update prunes a deselected managed adapter and installs the new one" {
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    [ -f .aider.conf.yml ]
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    [ -f AGENTS.md ]
    [ -f CLAUDE.md ]
    [ ! -f .aider.conf.yml ]        # managed adapter deselected -> pruned
    [ ! -f GEMINI.md ]              # was never installed with --tools claude
    ! grep -q '.aider.conf.yml' .agentic/install-manifest.tsv
}

@test "update prunes a deselected merge adapter that is only the managed block" {
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    [ -f CLAUDE.md ]
    bash "$INSTALL" . --tools gemini >/dev/null 2>&1
    [ ! -f CLAUDE.md ]              # block-only file -> removed on deselection
    [ -f GEMINI.md ]
    [ -f AGENTS.md ]
}

@test "a deselected merge adapter keeps its custom content" {
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    printf '\n## Team notes\nkeep this content\n' >> CLAUDE.md
    bash "$INSTALL" . --tools gemini >/dev/null 2>&1
    [ -f CLAUDE.md ]
    grep -q "keep this content" CLAUDE.md
    ! grep -q "AGENTIC-PROTOCOL-START" CLAUDE.md
}

@test "pruning a modified managed adapter preserves it as a conflict" {
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    printf '\n# adopter config\n' >> .aider.conf.yml
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    [ -f .aider.conf.yml ]          # modified -> preserved, never clobbered
    grep -q "# adopter config" .aider.conf.yml
}

@test "--prune removes obsolete files and rewrites the manifest" {
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    grep -q 'GEMINI.md' .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune --tools claude
    [ "$status" -eq 0 ]
    [ ! -f GEMINI.md ]
    [ ! -f .aider.conf.yml ]
    [ -f AGENTS.md ]
    [ -f CLAUDE.md ]
    [ -f .agentic/checks.tsv ]
    ! grep -q 'GEMINI.md' .agentic/install-manifest.tsv
    grep -q 'seed' .agentic/install-manifest.tsv
}

@test "--prune --plan makes no changes" {
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    run bash "$INSTALL" . --prune --plan --tools claude
    [ "$status" -eq 0 ]
    [ -f GEMINI.md ]
    [ -f .aider.conf.yml ]
}

@test "--uninstall removes managed files, strips merge blocks, preserves seeds" {
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    run bash "$INSTALL" . --uninstall
    [ "$status" -eq 0 ]
    [ ! -f AGENTS.md ]
    [ ! -f CLAUDE.md ]
    [ ! -f .agentic/VERSION ]
    [ ! -f .agentic/scripts/verify.sh ]
    [ ! -f .agentic/install-manifest.tsv ]
    [ -f .agentic/ARCHITECTURE.md ]
    [ -f .agentic/STATUS.md ]
    [ -f .agentic/checks.tsv ]
}

@test "--uninstall preserves modified managed files as conflicts" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\n# adopter notes\n' >> .agentic/WORKFLOW.md
    run bash "$INSTALL" . --uninstall
    [ "$status" -eq 0 ]
    [ -f .agentic/WORKFLOW.md ]
    grep -q "# adopter notes" .agentic/WORKFLOW.md
}

@test "--uninstall strips the merge block and keeps custom content" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\n## Team notes\nkeep this content\n' >> AGENTS.md
    run bash "$INSTALL" . --uninstall
    [ "$status" -eq 0 ]
    [ -f AGENTS.md ]
    grep -q "keep this content" AGENTS.md
    ! grep -q "AGENTIC-PROTOCOL-START" AGENTS.md
}

@test "--uninstall --plan makes no changes" {
    bash "$INSTALL" . >/dev/null 2>&1
    run bash "$INSTALL" . --uninstall --plan
    [ "$status" -eq 0 ]
    [ -f AGENTS.md ]
    [ -f .agentic/install-manifest.tsv ]
}

@test "v1.0 legacy migration: update reports, --prune removes files but keeps dirs" {
    # The v1.0 layout shipped per-tool adapters and a pseudo-memory store with
    # no install manifest. Migrating runs a fresh install (reported legacy
    # artifacts), then --prune cleans the legacy FILES while legacy DIRECTORIES
    # (which can hold user settings) are reported but preserved. Each legacy
    # file carries the framework signature so ownership is provable; a
    # signature-less file would be preserved as an unverified conflict.
    mkdir -p .github .cursor/rules .windsurf Memory
    printf '# Universal Agentic Development Protocol\n' > .cursorrules
    printf '# Universal Agentic Development Protocol\n' > .windsurfrules
    printf '# Universal Agentic Development Protocol\n' > .clinerules
    printf '# Universal Agentic Development Protocol\n' > CONVENTIONS.md
    printf '# Universal Agentic Development Protocol\n' > .github/copilot-instructions.md
    printf 'v1.0 project state\n' > Memory/PROJECT_STATE.md
    printf 'v1.0 decision log\n' > Memory/DECISION_LOG.md
    printf 'v1.0 user rules\n' > .cursor/rules/user.txt
    printf '# v1.0 AGENTS.md\ncustom content\n' > AGENTS.md

    run bash "$INSTALL" .
    [ "$status" -eq 0 ]
    # legacy artifacts are reported, not removed, by a plain install/update
    [ -f .cursorrules ]
    [ -f Memory/PROJECT_STATE.md ]
    grep -q "AGENTIC-PROTOCOL-START" AGENTS.md
    grep -q "custom content" AGENTS.md

    run bash "$INSTALL" . --prune
    [ "$status" -eq 0 ]
    [ ! -f .cursorrules ]
    [ ! -f .windsurfrules ]
    [ ! -f .clinerules ]
    [ ! -f CONVENTIONS.md ]
    [ ! -f .github/copilot-instructions.md ]
    [ -f Memory/PROJECT_STATE.md ]       # legacy dirs are preserved
    [ -f .cursor/rules/user.txt ]
    [ -f .agentic/ARCHITECTURE.md ]
    [ -f .agentic/checks.tsv ]
    grep -q "AGENTIC-PROTOCOL-START" AGENTS.md
}

@test "uninstall after migration leaves seeds and legacy dirs intact" {
    mkdir -p Memory
    printf '# Universal Agentic Development Protocol\n' > .cursorrules
    printf 'project state\n' > Memory/PROJECT_STATE.md
    bash "$INSTALL" . >/dev/null 2>&1
    run bash "$INSTALL" . --uninstall
    [ "$status" -eq 0 ]
    [ ! -f .cursorrules ]
    [ -f Memory/PROJECT_STATE.md ]
    [ -f .agentic/ARCHITECTURE.md ]
    [ -f .agentic/STATUS.md ]
    [ -f .agentic/checks.tsv ]
    [ ! -f .agentic/install-manifest.tsv ]
}

# ---------------------------------------------------------------------------
# Adversarial manifest, plan read-only, and temp-file regression tests.
# ---------------------------------------------------------------------------

@test "a manifest path that escapes the project root is rejected before any mutation" {
    mkdir -p "$TMP/proj"
    cd "$TMP/proj"
    bash "$INSTALL" . >/dev/null 2>&1
    printf 'PRECIOUS SIBLING\n' > "$TMP/evil"
    printf '../evil\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" "$TMP/proj" --prune
    [ "$status" -ne 0 ]
    [ "$(cat "$TMP/evil")" = "PRECIOUS SIBLING" ]
    [ -f AGENTS.md ]
    grep -q '^\.\./evil' .agentic/install-manifest.tsv
}

@test "a manifest path outside the framework set is rejected before any mutation" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf 'evil.txt\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f AGENTS.md ]
}

@test "an invalid manifest category is rejected before any mutation" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf 'AGENTS.md\tbogus\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f AGENTS.md ]
}

@test "an invalid manifest blocks a plain update before any mutation" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf 'evil.txt\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    [ -f AGENTS.md ]
}

@test "--prune never rewrites a malformed merge file" {
    printf '%s\n' '<!-- @@AGENTIC-PROTOCOL-START@@ -->' 'broken' '<!-- @@AGENTIC-PROTOCOL-START@@ -->' > GEMINI.md
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    run bash "$INSTALL" . --prune --tools claude
    [ "$status" -eq 0 ]
    [ -f GEMINI.md ]
    [ "$(grep -c -F 'AGENTIC-PROTOCOL-START' GEMINI.md)" -eq 2 ]
    grep -q "broken" GEMINI.md
}

@test "--prune --plan is byte-for-byte read-only" {
    mkdir -p "$TMP/proj"
    cd "$TMP/proj"
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    printf '\n## Team notes\nkeep this\n' >> AGENTS.md
    cp -r . "$TMP/before-snap"
    run bash "$INSTALL" "$TMP/proj" --prune --plan --tools claude
    [ "$status" -eq 0 ]
    diff -r "$TMP/before-snap" . >/dev/null
    [ ! -d .agentic-backup ]
}

@test "--uninstall --plan is byte-for-byte read-only" {
    mkdir -p "$TMP/proj"
    cd "$TMP/proj"
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    cp -r . "$TMP/before-snap"
    run bash "$INSTALL" "$TMP/proj" --uninstall --plan
    [ "$status" -eq 0 ]
    diff -r "$TMP/before-snap" . >/dev/null
    [ ! -d .agentic-backup ]
}

@test "unverified legacy files are preserved by --prune without the new flag" {
    printf 'my custom claude rules\n' > .clinerules
    bash "$INSTALL" . >/dev/null 2>&1
    run bash "$INSTALL" . --prune
    [ "$status" -eq 0 ]
    [ -f .clinerules ]
    grep -q "my custom claude rules" .clinerules
    [ ! -d .agentic-backup ]
}

@test "--prune-unverified-legacy backs up then removes unverified legacy files" {
    printf 'my custom claude rules\n' > .clinerules
    bash "$INSTALL" . >/dev/null 2>&1
    run bash "$INSTALL" . --prune --prune-unverified-legacy
    [ "$status" -eq 0 ]
    [ ! -f .clinerules ]
    [ -f .agentic-backup/.clinerules ]
    grep -q "my custom claude rules" .agentic-backup/.clinerules
}

@test "--prune-unverified-legacy --plan makes no changes" {
    printf 'my custom claude rules\n' > .clinerules
    bash "$INSTALL" . >/dev/null 2>&1
    run bash "$INSTALL" . --prune --prune-unverified-legacy --plan
    [ "$status" -eq 0 ]
    [ -f .clinerules ]
    [ ! -d .agentic-backup ]
}

@test "a pre-existing .agentic-tmp file is never clobbered" {
    mkdir -p .agentic
    printf 'PRECIOUS TMP\n' > .agentic/install-manifest.tsv.agentic-tmp
    printf 'PRECIOUS TMP\n' > .agentic/checks.tsv.agentic-tmp
    bash "$INSTALL" . --tools claude >/dev/null 2>&1
    [ "$(cat .agentic/install-manifest.tsv.agentic-tmp)" = "PRECIOUS TMP" ]
    [ "$(cat .agentic/checks.tsv.agentic-tmp)" = "PRECIOUS TMP" ]
}

# ---------------------------------------------------------------------------
# Canonical category-registry and write-confinement adversarial tests. Every
# test asserts the run FAILS before modifying the project or any external
# target, and that no partial destination is ever left behind.
# ---------------------------------------------------------------------------

@test "manifest category enforcement: CLAUDE.md recorded as managed is rejected" {
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    printf 'CLAUDE.md\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f CLAUDE.md ]
    grep -q "AGENTIC-PROTOCOL-START" CLAUDE.md
}

@test "manifest category enforcement: .aider.conf.yml recorded as merge is rejected" {
    bash "$INSTALL" . --tools all >/dev/null 2>&1
    printf '.aider.conf.yml\tmerge\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f .aider.conf.yml ]
}

@test "manifest category enforcement: a seed path recorded as managed is rejected" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '.agentic/ARCHITECTURE.md\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f .agentic/ARCHITECTURE.md ]
}

@test "a forged legacy manifest row (.clinerules) is rejected before any mutation" {
    printf 'my custom claude rules\n' > .clinerules
    bash "$INSTALL" . >/dev/null 2>&1
    printf '.clinerules\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune --prune-unverified-legacy
    [ "$status" -ne 0 ]
    [ -f .clinerules ]
    grep -q "my custom claude rules" .clinerules
    [ ! -d .agentic-backup ]
}

@test "a merge destination that is a symlink to an outside file is refused" {
    outside="$(make_outside_dir)"
    printf 'PRECIOUS OUTSIDE CONTENT\n' > "$outside/precious"
    ln -s "$outside/precious" AGENTS.md
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    [ "$(cat "$outside/precious")" = "PRECIOUS OUTSIDE CONTENT" ]
    [ -L AGENTS.md ]
}

@test "an .agentic directory symlinked outside is refused without writing there" {
    outside="$(make_outside_dir)"
    printf 'PRECIOUS OUTSIDE\n' > "$outside/keep.txt"
    ln -s "$outside" .agentic
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    [ "$(cat "$outside/keep.txt")" = "PRECIOUS OUTSIDE" ]
    [ ! -e "$outside/VERSION" ]
    [ -L .agentic ]
}

@test "a failed managed copy leaves no partial destination and nothing outside is touched" {
    [ "$(id -u)" -ne 0 ] || skip "root bypasses directory permissions"
    mkdir -p .agentic
    chmod 555 .agentic
    printf 'PRECIOUS SIBLING\n' > "$TMP/evil"
    run bash "$INSTALL" .
    [ "$status" -ne 0 ]
    [ ! -e .agentic/VERSION ]
    [ "$(cat "$TMP/evil")" = "PRECIOUS SIBLING" ]
    chmod 755 .agentic 2>/dev/null || true
}

@test "a failed seed copy leaves no partial destination" {
    [ "$(id -u)" -ne 0 ] || skip "root bypasses directory permissions"
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks --tools claude >/dev/null 2>&1
    [ -f .agentic/checks.generated.tsv ]
    [ ! -e .agentic/checks.tsv ]
    chmod 555 .agentic
    run bash "$INSTALL" . --accept-detected-checks --tools claude
    [ "$status" -ne 0 ]
    [ ! -e .agentic/checks.tsv ]
    [ -f .agentic/checks.generated.tsv ]
    chmod 755 .agentic 2>/dev/null || true
}

@test "a manifest row with a leading empty field is rejected" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf '\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f AGENTS.md ]
}

@test "a manifest row with a trailing empty field is rejected" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf 'AGENTS.md\tmanaged\t\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f AGENTS.md ]
}

@test "a manifest row with an adjacent empty field is rejected" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf 'AGENTS.md\t\t0000000000000000000000000000000000000000000000000000000000000000\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f AGENTS.md ]
}

@test "a manifest row with an excess (4th) field is rejected" {
    bash "$INSTALL" . >/dev/null 2>&1
    printf 'AGENTS.md\tmanaged\t0000000000000000000000000000000000000000000000000000000000000000\textra\n' >> .agentic/install-manifest.tsv
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    [ -f AGENTS.md ]
}

# ---------------------------------------------------------------------------
# Review-mandated regression tests (PR #5 blockers):
#   B1  atomic copies preserve the source's executable bits
#   B2  candidate detection, legacy cleanup, and manifest removal are confined
#   B3  Bash path registries stay case-sensitive (PowerShell is tested in Pester)
#   B4  a failed final rename leaves the prior destination intact, no randomized
#       temp remains, and rollback restores contents and the executable mode
# ---------------------------------------------------------------------------

@test "installed verifier keeps its executable bit and runs directly" {
    bash "$INSTALL" . >/dev/null 2>&1
    [ -x .agentic/scripts/verify.sh ]
    run ./.agentic/scripts/verify.sh
    [ "$status" -le 3 ]
}

@test "--detect-checks refuses an .agentic symlink to an outside directory" {
    outside="$(make_outside_dir)"
    printf 'PRECIOUS OUTSIDE\n' > "$outside/keep.txt"
    ln -s "$outside" .agentic
    run bash "$INSTALL" . --detect-checks --tools claude
    [ "$status" -ne 0 ]
    [ "$(cat "$outside/keep.txt")" = "PRECIOUS OUTSIDE" ]
    [ ! -e "$outside/checks.generated.tsv" ]
    [ -L .agentic ]
}

@test "--prune refuses to remove a legacy file through a linked .github" {
    outside="$(make_outside_dir)"
    printf 'PRECIOUS OUTSIDE\n' > "$outside/copilot-instructions.md"
    mkdir -p .github
    ln -s "$outside/copilot-instructions.md" .github/copilot-instructions.md
    bash "$INSTALL" . >/dev/null 2>&1
    run bash "$INSTALL" . --prune --prune-unverified-legacy
    [ "$status" -ne 0 ]
    [ "$(cat "$outside/copilot-instructions.md")" = "PRECIOUS OUTSIDE" ]
    [ -L .github/copilot-instructions.md ]
}

@test "--prune refuses to rewrite a manifest reached through a linked .agentic" {
    outside="$(make_outside_dir)"
    printf '1.2.1\nAGENTS.md\tmerge\t0000000000000000000000000000000000000000000000000000000000000000\n' > "$outside/install-manifest.tsv"
    ln -s "$outside" .agentic
    run bash "$INSTALL" . --prune
    [ "$status" -ne 0 ]
    grep -q $'\tmerge\t' "$outside/install-manifest.tsv"
    [ -L .agentic ]
}

@test "case-different framework path is distinct on a case-sensitive filesystem" {
    printf 'probe\n' > .CaseProbe
    if [ -e .caseprobe ]; then rm -f .CaseProbe; skip "case-insensitive filesystem"; fi
    rm -f .CaseProbe
    mkdir -p .agentic
    printf 'lowercase custom\n' > .agentic/version
    bash "$INSTALL" . >/dev/null 2>&1
    [ -f .agentic/VERSION ]
    [ "$(cat .agentic/VERSION)" = "1.2.1" ]
    [ "$(cat .agentic/version)" = "lowercase custom" ]
    [ ! -e .agentic/version.new ]
}

@test "a failed final rename leaves the prior destination intact and rollback restores contents and mode" {
    bash "$INSTALL" . >/dev/null 2>&1
    # Distinctive mode on the verifier: the update rewrites it (mode -> source
    # 777), then a later rename fails and rollback must restore the 750.
    chmod 750 .agentic/scripts/verify.sh
    # Shim `mv` to refuse only the final rename onto CLAUDE.md, which happens
    # after verify.sh has already been replaced, forcing a mid-transaction
    # failure at the rename step rather than at temp creation or content copy.
    mkdir -p shimbin
    cat > shimbin/mv <<'SHIM'
#!/usr/bin/env bash
if [ "${@: -1}" = "$PWD/CLAUDE.md" ]; then
    echo "shim: refusing rename to CLAUDE.md" >&2
    exit 1
fi
exec /bin/mv "$@"
SHIM
    chmod +x shimbin/mv
    run env PATH="$PWD/shimbin:$PATH" bash "$INSTALL" .
    [ "$status" -ne 0 ]
    # Rollback restored the prior destination's content and executable mode.
    [ "$(stat -c '%a' 2>/dev/null || stat -f '%Lp' 2>/dev/null .agentic/scripts/verify.sh)" = "750" ]
    grep -q "Universal project verification script" .agentic/scripts/verify.sh
    # The interrupted rename left the prior CLAUDE.md untouched and no
    # randomized temp files behind anywhere in the project.
    grep -q "AGENTIC-PROTOCOL-START" CLAUDE.md
    [ -z "$(find . -maxdepth 3 \( -name 'verify.sh.*' -o -name 'CLAUDE.md.*' \) 2>/dev/null)" ]
}

# ---------------------------------------------------------------------------
# Clean adopter bundle (scripts/build-bundle.sh) end-to-end tests.
# ---------------------------------------------------------------------------

@test "bundle build produces archives and a SHA256SUMS file" {
    bash "$REPO_ROOT/scripts/build-bundle.sh"
    BUNDLE="$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION")"
    [ -f "$REPO_ROOT/dist/SHA256SUMS" ]
    [ -f "$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION").tar.gz" ]
    [ -f "$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION").zip" ]
    [ -f "$BUNDLE/install.sh" ]
    [ -f "$BUNDLE/AGENTS.md" ]
    grep -q "agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION").tar.gz" "$REPO_ROOT/dist/SHA256SUMS"
    grep -q "agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION").zip" "$REPO_ROOT/dist/SHA256SUMS"
}

@test "bundle excludes framework-only files" {
    bash "$REPO_ROOT/scripts/build-bundle.sh" --no-archives
    BUNDLE="$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION")"
    [ ! -e "$BUNDLE/.agentic/checks.tsv" ]
    [ ! -e "$BUNDLE/tests" ]
    [ ! -e "$BUNDLE/.github" ]
    [ ! -e "$BUNDLE/docs" ]
    [ ! -e "$BUNDLE/CHANGELOG.md" ]
    [ ! -e "$BUNDLE/README.md" ]
    [ ! -e "$BUNDLE/dist" ]
    [ -f "$BUNDLE/.agentic/templates/checks.tsv" ]   # generic template travels
    [ -f "$BUNDLE/.agentic/scripts/verify.sh" ]
    [ -f "$BUNDLE/LICENSE" ]
}

@test "end-to-end: install from the bundle into an empty project" {
    bash "$REPO_ROOT/scripts/build-bundle.sh" --no-archives
    BUNDLE="$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION")"
    mkdir -p empty-project
    cd empty-project
    bash "$BUNDLE/install.sh" . >/dev/null 2>&1
    [ -f AGENTS.md ]
    [ -f .aider.conf.yml ]
    [ -f .agentic/VERSION ]
    [ -f .agentic/checks.tsv ]
    grep -q "seed" .agentic/install-manifest.tsv
    # the seeded checks come from the generic (comment-only) template, so the
    # framework's own checks are not forced on adopters: an empty project with
    # no check lines is reported UNSUPPORTED (exit 3), never FAIL (exit 1).
    run bash .agentic/scripts/verify.sh
    [ "$status" -eq 3 ]
}
