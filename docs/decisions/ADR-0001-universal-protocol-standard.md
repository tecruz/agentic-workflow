# ADR-0001 — Universal protocol standard & import-only entry points

- **Date**: 2026-08-13
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback.md`

## Context

Each AI coding tool (Claude Code, Gemini CLI, Cursor, Windsurf, Cline/Roo,
GitHub Copilot, Aider, OpenCode) loads configuration from a different file. A
repository shipped several near-duplicate adapter files that could drift and
were a maintenance burden. Review feedback (§2 "tool interoperability")
asked for a single canonical source of truth with thin, import-only entry
points.

## Decision

- `AGENTS.md` at the repository root is the canonical protocol document.
- Tools that support it (OpenCode, Cursor, Windsurf, Cline/Roo, GitHub
  Copilot) read `AGENTS.md` natively and need no adapter.
- `CLAUDE.md` imports `AGENTS.md` and `.agentic/WORKFLOW.md`; `GEMINI.md`
  imports them with `./` prefixes; `.aider.conf.yml` reads them. These
  adapters contain only imports or pointers — never duplicated protocol text.
- Redundant adapters (`.cursorrules`, `.windsurfrules`, `.clinerules`,
  `CONVENTIONS.md`, `.github/copilot-instructions.md`, `.cursor/`, `.windsurf/`)
  were deleted. Cursor/Windsurf/Cline read `AGENTS.md` directly.
- The managed region of the root protocol file is wrapped between
  `<!-- @@AGENTIC-PROTOCOL-START@@ -->` and `<!-- @@AGENTIC-PROTOCOL-END@@ -->
  markers so the installer can update it without touching adopter content.

## Consequences

- One file to edit for protocol content; tool coverage no longer drifts.
- Tools without native `AGENTS.md` support get a generated, import-only file.
- Marker-delimited sections enable non-destructive updates (see ADR-0003).