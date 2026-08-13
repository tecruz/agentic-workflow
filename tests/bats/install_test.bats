#!/usr/bin/env bats

# install.sh — ownership, merge, and manifest tests.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"

setup() {
    TMP="$(mktemp -d)"
    cd "$TMP"
}

teardown() {
    cd "$REPO_ROOT"
    rm -rf "$TMP"
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