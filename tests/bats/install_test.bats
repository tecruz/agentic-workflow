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

# Configure a local Git identity for tests that create temporary repositories.
# Clean CI environments have no inherited Git config, so commits and annotated
# tags fail with "Author identity unknown" without this.
configure_test_git_identity() {
    git config user.name "agentic-workflow-tests"
    git config user.email "agentic-workflow-tests@example.invalid"
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

@test "fresh install creates risk profiles, validators, and the task template" {
    bash "$INSTALL" . >/dev/null 2>&1
    [ -f .agentic/profiles/README.md ]
    [ -f .agentic/profiles/prototype.md ]
    [ -f .agentic/profiles/standard.md ]
    [ -f .agentic/profiles/high-assurance.md ]
    [ -f .agentic/scripts/validate-task.sh ]
    [ -f .agentic/scripts/validate-task.ps1 ]
    [ -f .agentic/templates/task.md ]
    # validate-task.sh must be executable in the installed tree
    [ -x .agentic/scripts/validate-task.sh ]
    # all new files are framework-managed and recorded in the manifest
    grep -q $'\.agentic/profiles/README\.md\tmanaged' .agentic/install-manifest.tsv
    grep -q $'\.agentic/scripts/validate-task\.sh\tmanaged' .agentic/install-manifest.tsv
    grep -q $'\.agentic/templates/task\.md\tmanaged' .agentic/install-manifest.tsv
}

@test "adopter task files in .agentic/tasks are never overwritten" {
    mkdir -p .agentic/tasks
    printf '# TASK-900: adopter task\nkeep me\n' > .agentic/tasks/TASK-900-adopter.md
    bash "$INSTALL" . >/dev/null 2>&1
    [ "$(cat .agentic/tasks/TASK-900-adopter.md)" = "# TASK-900: adopter task
keep me" ]
    # the framework's template travels, but the adopter's own file is untouched
    [ -f .agentic/templates/task.md ]
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
    [ "$status" -eq 3 ]
}

@test "installed task validator keeps its executable bit and runs directly" {
    bash "$INSTALL" . >/dev/null 2>&1
    [ -x .agentic/scripts/validate-task.sh ]
    run ./.agentic/scripts/validate-task.sh --handoff "$REPO_ROOT/tests/fixtures/tasks/standard-valid.md"
    [ "$status" -eq 0 ]
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
    [ "$(cat .agentic/VERSION)" = "$(cat "$REPO_ROOT/.agentic/VERSION")" ]
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
    if stat --version >/dev/null 2>&1; then
        [ "$(stat -c '%a' .agentic/scripts/verify.sh)" = "750" ]
    else
        [ "$(stat -f '%Lp' .agentic/scripts/verify.sh)" = "750" ]
    fi
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
    VERSION="$(cat "$REPO_ROOT/.agentic/VERSION")"
    BUNDLE="$REPO_ROOT/dist/agentic-workflow-$VERSION"
    [ -f "$REPO_ROOT/dist/SHA256SUMS" ]
    [ -f "$REPO_ROOT/dist/agentic-workflow-$VERSION.tar.gz" ]
    [ -f "$REPO_ROOT/dist/agentic-workflow-$VERSION.zip" ]
    [ -f "$BUNDLE/install.sh" ]
    [ -f "$BUNDLE/AGENTS.md" ]
    grep -q "agentic-workflow-$VERSION.tar.gz" "$REPO_ROOT/dist/SHA256SUMS"
    grep -q "agentic-workflow-$VERSION.zip" "$REPO_ROOT/dist/SHA256SUMS"

    # Verify the actual checksums match
    cd "$REPO_ROOT/dist"
    sha256sum -c SHA256SUMS
}

@test "release changelog section can be extracted" {
    VERSION="$(cat "$REPO_ROOT/.agentic/VERSION")"
    NOTES="$(sed -n "/^## \[$VERSION\]/,/^## \[/p" "$REPO_ROOT/CHANGELOG.md" | sed '$d')"
    [ -n "$NOTES" ]
    echo "$NOTES" | grep -q "## \[$VERSION\]"
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

@test "bundle carries profiles, validators, and the task template" {
    bash "$REPO_ROOT/scripts/build-bundle.sh" --no-archives
    BUNDLE="$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION")"
    [ -f "$BUNDLE/.agentic/profiles/README.md" ]
    [ -f "$BUNDLE/.agentic/profiles/prototype.md" ]
    [ -f "$BUNDLE/.agentic/profiles/standard.md" ]
    [ -f "$BUNDLE/.agentic/profiles/high-assurance.md" ]
    [ -f "$BUNDLE/.agentic/scripts/validate-task.sh" ]
    [ -f "$BUNDLE/.agentic/scripts/validate-task.ps1" ]
    [ -f "$BUNDLE/.agentic/templates/task.md" ]
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

@test "Bash candidate rename failure aborts with nonzero exit and outputs no success message" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks >/dev/null 2>&1
    [ -f .agentic/checks.generated.tsv ]
    mkdir -p shimbin
    cat > shimbin/mv <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == *"checks.tsv" ]]; then
        echo "shim: refusing mv for checks.tsv" >&2
        exit 1
    fi
done
exec /bin/mv "$@"
SHIM
    chmod +x shimbin/mv
    run env PATH="$PWD/shimbin:$PATH" bash "$INSTALL" . --accept-detected-checks
    [ "$status" -ne 0 ]
    ! grep -q "promoted" <<< "$output"
    [ ! -f .agentic/checks.tsv ]
}

@test "Bash stale-candidate removal failure aborts with nonzero exit and preserves stale candidate" {
    printf '{"name":"x","scripts":{"test":"true"}}\n' > package.json
    bash "$INSTALL" . --detect-checks >/dev/null 2>&1
    [ -f .agentic/checks.generated.tsv ]
    rm package.json
    mkdir -p shimbin
    cat > shimbin/rm <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == *"checks.generated.tsv"* ]]; then
        echo "shim: refusing rm for checks.generated.tsv" >&2
        exit 1
    fi
done
exec /bin/rm "$@"
SHIM
    chmod +x shimbin/rm
    run env PATH="$PWD/shimbin:$PATH" bash "$INSTALL" . --detect-checks
    [ "$status" -ne 0 ]
    [ -f .agentic/checks.generated.tsv ]
}

# ---------------------------------------------------------------------------
# Extracted-archive release tests: install from the final tar.gz and zip
# assets rather than the unarchived bundle directory.
# ---------------------------------------------------------------------------

@test "end-to-end: extract tar.gz and install from extracted archive" {
    bash "$REPO_ROOT/scripts/build-bundle.sh"
    VERSION="$(cat "$REPO_ROOT/.agentic/VERSION")"
    ARCHIVE="$REPO_ROOT/dist/agentic-workflow-$VERSION.tar.gz"
    [ -f "$ARCHIVE" ]

    EXTRACT_DIR="$TMP/extract-tar"
    mkdir -p "$EXTRACT_DIR"
    tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
    EXTRACTED_BUNDLE="$EXTRACT_DIR/agentic-workflow-$VERSION"

    # Verify risk profiles, task validators, task template
    [ -f "$EXTRACTED_BUNDLE/.agentic/profiles/README.md" ]
    [ -f "$EXTRACTED_BUNDLE/.agentic/profiles/prototype.md" ]
    [ -f "$EXTRACTED_BUNDLE/.agentic/profiles/standard.md" ]
    [ -f "$EXTRACTED_BUNDLE/.agentic/profiles/high-assurance.md" ]
    [ -f "$EXTRACTED_BUNDLE/.agentic/scripts/validate-task.sh" ]
    [ -x "$EXTRACTED_BUNDLE/.agentic/scripts/validate-task.sh" ]
    [ -f "$EXTRACTED_BUNDLE/.agentic/scripts/validate-task.ps1" ]
    [ -f "$EXTRACTED_BUNDLE/.agentic/templates/task.md" ]
    grep -q "Profile" "$EXTRACTED_BUNDLE/.agentic/templates/task.md"
    grep -q "Required evidence" "$EXTRACTED_BUNDLE/.agentic/templates/task.md"
    grep -q "Approval gates" "$EXTRACTED_BUNDLE/.agentic/templates/task.md"

    PROJECT="$TMP/project"
    mkdir -p "$PROJECT"
    cd "$PROJECT"
    bash "$EXTRACTED_BUNDLE/install.sh" . >/dev/null 2>&1

    [ -f AGENTS.md ]
    [ -f .aider.conf.yml ]
    [ -f .agentic/VERSION ]
    [ -f .agentic/checks.tsv ]
    grep -q "seed" .agentic/install-manifest.tsv

    # Execute installed validators against test fixtures
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/standard-valid.md"
    [ "$status" -eq 0 ]
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/completed-with-pending-evidence.md"
    [ "$status" -eq 2 ]
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/unknown-profile.md"
    [ "$status" -eq 1 ]

    # the verifier should report UNSUPPORTED (3) for an empty project
    run bash .agentic/scripts/verify.sh
    [ "$status" -eq 3 ]

    # exercise update, plan, prune, uninstall
    bash "$EXTRACTED_BUNDLE/install.sh" . >/dev/null 2>&1
    run bash "$EXTRACTED_BUNDLE/install.sh" . --prune --plan
    [ "$status" -eq 0 ]
    run bash "$EXTRACTED_BUNDLE/install.sh" . --uninstall --plan
    [ "$status" -eq 0 ]
}

@test "end-to-end: extract zip and install from extracted archive" {
    command -v unzip >/dev/null 2>&1 || skip "unzip not available"
    bash "$REPO_ROOT/scripts/build-bundle.sh"
    VERSION="$(cat "$REPO_ROOT/.agentic/VERSION")"
    ARCHIVE="$REPO_ROOT/dist/agentic-workflow-$VERSION.zip"
    [ -f "$ARCHIVE" ]

    EXTRACT_DIR="$TMP/extract-zip"
    mkdir -p "$EXTRACT_DIR"
    unzip -q "$ARCHIVE" -d "$EXTRACT_DIR"

    # Detect the actual bundle directory (extraction tools may nest differently)
    BUNDLE="$(find "$EXTRACT_DIR" -name "install.sh" -path "*/agentic-workflow-*/install.sh" -exec dirname {} \; 2>/dev/null | head -1)"
    [ -n "$BUNDLE" ] || skip "could not locate bundle after zip extraction"

    # Verify risk profiles, task validators, task template
    [ -f "$BUNDLE/.agentic/profiles/README.md" ]
    [ -f "$BUNDLE/.agentic/scripts/validate-task.sh" ]
    [ -x "$BUNDLE/.agentic/scripts/validate-task.sh" ]
    [ -f "$BUNDLE/.agentic/templates/task.md" ]

    PROJECT="$TMP/project"
    mkdir -p "$PROJECT"
    cd "$PROJECT"
    bash "$BUNDLE/install.sh" . >/dev/null 2>&1

    [ -f AGENTS.md ]
    [ -f .aider.conf.yml ]
    [ -f .agentic/VERSION ]
    grep -q "seed" .agentic/install-manifest.tsv

    # Execute installed validators against test fixtures
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/standard-valid.md"
    [ "$status" -eq 0 ]
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/completed-with-pending-evidence.md"
    [ "$status" -eq 2 ]
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/unknown-profile.md"
    [ "$status" -eq 1 ]

    # the verifier should report UNSUPPORTED (3) for an empty project
    run bash .agentic/scripts/verify.sh
    [ "$status" -eq 3 ]

    # exercise update, plan, prune, uninstall
    bash "$BUNDLE/install.sh" . >/dev/null 2>&1
    run bash "$BUNDLE/install.sh" . --prune --plan
    [ "$status" -eq 0 ]
    run bash "$BUNDLE/install.sh" . --uninstall --plan
    [ "$status" -eq 0 ]
}

@test "build-bundle.sh removes stale archives and checksums before rebuilding and validates SHA256SUMS" {
    VERSION="$(cat "$REPO_ROOT/.agentic/VERSION")"
    touch "$REPO_ROOT/dist/agentic-workflow-$VERSION.tar.gz"
    touch "$REPO_ROOT/dist/agentic-workflow-$VERSION.zip"
    touch "$REPO_ROOT/dist/SHA256SUMS"
    echo "stale" > "$REPO_ROOT/dist/agentic-workflow-$VERSION.tar.gz"
    echo "stale" > "$REPO_ROOT/dist/agentic-workflow-$VERSION.zip"
    bash "$REPO_ROOT/scripts/build-bundle.sh"
    [ "$(cat "$REPO_ROOT/dist/agentic-workflow-$VERSION.tar.gz")" != "stale" ]
    [ "$(cat "$REPO_ROOT/dist/agentic-workflow-$VERSION.zip")" != "stale" ]
    [ -s "$REPO_ROOT/dist/SHA256SUMS" ]
    grep -q "agentic-workflow-$VERSION.tar.gz" "$REPO_ROOT/dist/SHA256SUMS"
    grep -q "agentic-workflow-$VERSION.zip" "$REPO_ROOT/dist/SHA256SUMS"
}

@test "build-bundle.sh invokes pwsh.exe fallback when pwsh is absent and pwsh.exe is present" {
    MOCK_BIN="$TMP/mock-bin"
    mkdir -p "$MOCK_BIN"
    cat << 'EOF' > "$MOCK_BIN/pwsh.exe"
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_BIN/pwsh.exe"

    PATH="$MOCK_BIN:/usr/bin:/bin" OS="Windows_NT" bash "$REPO_ROOT/scripts/build-bundle.sh"
    [ -f "$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION").zip" ]
}

@test "release tar.gz does not leak development-only files" {
    bash "$REPO_ROOT/scripts/build-bundle.sh"
    VERSION="$(cat "$REPO_ROOT/.agentic/VERSION")"
    EXTRACT_DIR="$TMP/extract-leak"
    mkdir -p "$EXTRACT_DIR"
    tar -xzf "$REPO_ROOT/dist/agentic-workflow-$VERSION.tar.gz" -C "$EXTRACT_DIR"
    BUNDLE="$EXTRACT_DIR/agentic-workflow-$VERSION"

    [ ! -e "$BUNDLE/tests" ]
    [ ! -e "$BUNDLE/.github" ]
    [ ! -e "$BUNDLE/docs" ]
    [ ! -e "$BUNDLE/.agentic/checks.tsv" ]
    [ ! -e "$BUNDLE/CHANGELOG.md" ]
    [ ! -e "$BUNDLE/README.md" ]
    [ ! -e "$BUNDLE/CONTRIBUTING.md" ]
    [ ! -e "$BUNDLE/SECURITY.md" ]
    [ ! -e "$BUNDLE/dist" ]
    [ ! -e "$BUNDLE/.agentic/decisions/ADR-"* ]
    [ -f "$BUNDLE/.agentic/templates/checks.tsv" ]
    [ -f "$BUNDLE/.agentic/scripts/verify.sh" ]
    [ -f "$BUNDLE/LICENSE" ]
}

@test "release zip does not leak development-only files" {
    command -v unzip >/dev/null 2>&1 || skip "unzip not available"
    bash "$REPO_ROOT/scripts/build-bundle.sh"
    VERSION="$(cat "$REPO_ROOT/.agentic/VERSION")"
    EXTRACT_DIR="$TMP/extract-zip-leak"
    mkdir -p "$EXTRACT_DIR"
    unzip -q "$REPO_ROOT/dist/agentic-workflow-$VERSION.zip" -d "$EXTRACT_DIR"

    BUNDLE="$(find "$EXTRACT_DIR" -name "install.sh" -path "*/agentic-workflow-*/install.sh" -exec dirname {} \; 2>/dev/null | head -1)"
    [ -n "$BUNDLE" ] || skip "could not locate bundle after zip extraction"

    [ ! -e "$BUNDLE/tests" ]
    [ ! -e "$BUNDLE/.github" ]
    [ ! -e "$BUNDLE/docs" ]
    [ ! -e "$BUNDLE/.agentic/checks.tsv" ]
    [ ! -e "$BUNDLE/CHANGELOG.md" ]
    [ ! -e "$BUNDLE/README.md" ]
    [ ! -e "$BUNDLE/CONTRIBUTING.md" ]
    [ ! -e "$BUNDLE/SECURITY.md" ]
    [ -f "$BUNDLE/.agentic/templates/checks.tsv" ]
    [ -f "$BUNDLE/.agentic/scripts/verify.sh" ]
}

# ---------------------------------------------------------------------------
# Release-to-release upgrade test: install from the v1.2.2 bundle, modify
# project state, then upgrade using the current bundle.
# ---------------------------------------------------------------------------

@test "upgrade from v1.2.2 bundle to the current bundle preserves project state and adds v1.3.0 profiles and validators" {
    # Verify the v1.2.2 tag exists and has the expected VERSION
    if [ "${CI:-}" = "true" ]; then
        git -C "$REPO_ROOT" rev-parse v1.2.2 >/dev/null 2>&1 ||
            fail "required migration tag v1.2.2 is unavailable in CI"
    else
        git -C "$REPO_ROOT" rev-parse v1.2.2 >/dev/null 2>&1 ||
            skip "v1.2.2 tag not found"
    fi
    V122_VERSION="$(git -C "$REPO_ROOT" show v1.2.2:.agentic/VERSION 2>/dev/null)"
    [ "$V122_VERSION" = "1.2.2" ]

    # Extract the actual v1.2.2 source tree and build its bundle
    V122_SRC="$TMP/v122-src"
    mkdir -p "$V122_SRC"
    git -C "$REPO_ROOT" archive v1.2.2 | tar -x -C "$V122_SRC"
    bash "$V122_SRC/scripts/build-bundle.sh" --no-archives
    V122_DIR="$V122_SRC/dist/agentic-workflow-1.2.2"

    # Build the current bundle
    bash "$REPO_ROOT/scripts/build-bundle.sh" --no-archives
    CURRENT_BUNDLE="$REPO_ROOT/dist/agentic-workflow-$(cat "$REPO_ROOT/.agentic/VERSION")"

    PROJECT="$TMP/upgrade-project"
    mkdir -p "$PROJECT"
    cd "$PROJECT"

    # Step 1: Install from the real v1.2.2 bundle
    run bash "$V122_DIR/install.sh" . --tools all
    [ "$status" -eq 0 ]
    [ -f AGENTS.md ]
    [ -f CLAUDE.md ]
    [ -f GEMINI.md ]
    [ -f .aider.conf.yml ]
    [ -f .agentic/VERSION ]
    [ "$(cat .agentic/VERSION)" = "1.2.2" ]

    # Step 2: Add custom content outside merge blocks and adopter task file
    printf '\n## Team notes\nkeep this content\n' >> AGENTS.md
    printf '\n# custom aider config\n' >> .aider.conf.yml
    mkdir -p .agentic/tasks
    printf '# TASK-900: adopter task evidence' > .agentic/tasks/TASK-900-adopter.md

    # Step 3: Modify managed files to produce conflict candidates
    printf '\n# adopter workflow override\n' >> .agentic/WORKFLOW.md
    printf '\n# adopter aider override\n' >> .aider.conf.yml

    # Step 4: Add a reviewed candidate
    printf 'required\tcustom-check\t.\tnpm\ttest\n' > .agentic/checks.generated.tsv

    # Step 5: Upgrade using current bundle
    run bash "$CURRENT_BUNDLE/install.sh" . --tools all
    [ "$status" -eq 0 ]

    # Step 6: Verify v1.3.0 additions and preservation
    [ "$(cat .agentic/VERSION)" = "1.3.0" ]
    [ -f .agentic/profiles/README.md ]
    [ -f .agentic/profiles/prototype.md ]
    [ -f .agentic/profiles/standard.md ]
    [ -f .agentic/profiles/high-assurance.md ]
    [ -f .agentic/scripts/validate-task.sh ]
    [ -x .agentic/scripts/validate-task.sh ]
    [ -f .agentic/scripts/validate-task.ps1 ]
    [ -f .agentic/templates/task.md ]
    [ -f .agentic/tasks/TASK-900-adopter.md ]
    grep -q "adopter task evidence" .agentic/tasks/TASK-900-adopter.md

    # Verify exact managed manifest entries for new v1.3.0 files
    manifest="$(cat .agentic/install-manifest.tsv)"
    for f in ".agentic/profiles/README.md" ".agentic/profiles/prototype.md" ".agentic/profiles/standard.md" ".agentic/profiles/high-assurance.md" ".agentic/scripts/validate-task.sh" ".agentic/scripts/validate-task.ps1" ".agentic/templates/task.md"; do
        printf '%s\n' "$manifest" | grep -q "$f$'\t'managed"$ || printf '%s\n' "$manifest" | grep -q "$f	managed"
    done

    # Verify modified managed files produced .new conflict candidates and contain managed content
    [ -f .agentic/WORKFLOW.md.new ]
    [ -f .aider.conf.yml.new ]
    grep -q "CLASSIFY RISK" .agentic/WORKFLOW.md.new
    grep -q "aider" .aider.conf.yml.new

    # Execute installed validators against test fixtures
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/standard-valid.md"
    [ "$status" -eq 0 ]
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/completed-with-pending-evidence.md"
    [ "$status" -eq 2 ]
    run bash .agentic/scripts/validate-task.sh "$REPO_ROOT/tests/fixtures/tasks/unknown-profile.md"
    [ "$status" -eq 1 ]

    grep -q "keep this content" AGENTS.md
    grep -q "AGENTIC-PROTOCOL-START" AGENTS.md
    grep -q "# adopter workflow override" .agentic/WORKFLOW.md
    [ -f .agentic/checks.generated.tsv ]
    grep -q "custom-check" .agentic/checks.generated.tsv
    [ "$(cat .agentic/checks.generated.tsv)" = "required"$'\t'"custom-check"$'\t'"."$'\t'"npm"$'\t'"test" ]
    grep -q "# custom aider config" .aider.conf.yml

    # Step 7: Exercise plan, prune, uninstall
    run bash "$CURRENT_BUNDLE/install.sh" . --prune --plan --tools claude
    [ "$status" -eq 0 ]
    [ -f GEMINI.md ]
    [ -f .aider.conf.yml ]

    run bash "$CURRENT_BUNDLE/install.sh" . --uninstall --plan
    [ "$status" -eq 0 ]
    [ -f AGENTS.md ]

    # Step 8: Actual prune removes deselected adapters
    run bash "$CURRENT_BUNDLE/install.sh" . --prune --tools claude
    [ "$status" -eq 0 ]
    [ -f AGENTS.md ]
    [ -f CLAUDE.md ]

    # Step 9: Uninstall removes managed files, preserves seeds
    run bash "$CURRENT_BUNDLE/install.sh" . --uninstall
    [ "$status" -eq 0 ]
    [ ! -f .agentic/VERSION ]
    [ ! -f .agentic/scripts/verify.sh ]
    [ -f .agentic/ARCHITECTURE.md ]
    [ -f .agentic/STATUS.md ]
    [ -f .agentic/checks.tsv ]
    [ -f .agentic/tasks/TASK-900-adopter.md ]
    grep -q "adopter task evidence" .agentic/tasks/TASK-900-adopter.md
}

# ---------------------------------------------------------------------------
# Tag resolution tests: verify that the release workflow's tag validation
# logic correctly handles both lightweight and annotated tags.
# ---------------------------------------------------------------------------

@test "lightweight tag resolves to a valid commit SHA" {
    TAG_REPO="$TMP/tag-repo"
    mkdir -p "$TAG_REPO"
    git -C "$REPO_ROOT" archive HEAD | tar -x -C "$TAG_REPO"
    cd "$TAG_REPO"

    git init -q
    configure_test_git_identity
    git add -A
    git commit -q -m "initial commit"
    git tag v0.0.1

    # Resolve the tag (mirrors release.yml:61)
    SHA="$(git rev-list -n 1 "v0.0.1" 2>/dev/null)"
    [ -n "$SHA" ]

    # For a lightweight tag, tag object == commit SHA
    TAG_OBJECT="$(git rev-parse "v0.0.1")"
    TAG_COMMIT="$(git rev-parse "v0.0.1^{commit}")"
    [ "$TAG_OBJECT" = "$TAG_COMMIT" ]
    [ "$TAG_COMMIT" = "$SHA" ]
}

@test "annotated tag resolves to a valid commit SHA" {
    TAG_REPO="$TMP/tag-repo-annotated"
    mkdir -p "$TAG_REPO"
    git -C "$REPO_ROOT" archive HEAD | tar -x -C "$TAG_REPO"
    cd "$TAG_REPO"

    git init -q
    configure_test_git_identity
    git add -A
    git commit -q -m "initial commit"
    git tag -a v0.0.2 -m "annotated release tag"

    # Resolve the tag (mirrors release.yml:61)
    SHA="$(git rev-list -n 1 "v0.0.2" 2>/dev/null)"
    [ -n "$SHA" ]

    # For an annotated tag, tag object != commit SHA
    TAG_OBJECT="$(git rev-parse "v0.0.2")"
    TAG_COMMIT="$(git rev-parse "v0.0.2^{commit}")"
    [ "$TAG_OBJECT" != "$TAG_COMMIT" ]
    [ "$TAG_COMMIT" = "$SHA" ]

    # The peeled commit SHA must match rev-list output
    [ "$TAG_COMMIT" = "$SHA" ]
}

@test "tag validation rejects SemVer pre-release suffix" {
    TAG_REPO="$TMP/tag-repo-prerelease"
    mkdir -p "$TAG_REPO"
    git -C "$REPO_ROOT" archive HEAD | tar -x -C "$TAG_REPO"
    cd "$TAG_REPO"

    git init -q
    configure_test_git_identity
    git add -A
    git commit -q -m "initial commit"
    git tag v1.0.0-beta.1

    # Pre-release tags must fail the SemVer check (mirrors release.yml:55)
    [[ ! "v1.0.0-beta.1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

@test "tag validation rejects missing tag" {
    TAG_REPO="$TMP/tag-repo-missing"
    mkdir -p "$TAG_REPO"
    git -C "$REPO_ROOT" archive HEAD | tar -x -C "$TAG_REPO"
    cd "$TAG_REPO"

    git init -q
    configure_test_git_identity
    git add -A
    git commit -q -m "initial commit"

    # Non-existent tag should fail to resolve
    run git rev-list -n 1 "v9.9.9" 2>/dev/null
    [ "$status" -ne 0 ]
}
