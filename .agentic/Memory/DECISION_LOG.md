# Architecture Decision Log (ADR)

> Record significant technical and architectural decisions made by humans and AI agents.

## [ADR-001] Universal Agentic Development Protocol Standard

- **Date**: 2026-08-13
- **Status**: Approved
- **Context**: Projects need a single, technology-agnostic agentic workflow standard compatible with OpenCode, Claude Code, Cursor, Windsurf, Roo Code, Aider, and GitHub Copilot.
- **Decision**: Adopt `AGENTS.md` as canonical master directive file, supported by `.agentic/` directory containing rules, memory state, and verification scripts.
- **Consequences**: Enables any AI agent to instantly align with project conventions and verification standards regardless of stack.

## [ADR-002] Entry Points Are Pointers; Support Legacy + Modern Tool Config Formats

- **Date**: 2026-08-13
- **Status**: Approved
- **Context**: Agent tools load instructions from tool-specific files, and some tools changed their config format over time (Cursor: `.cursorrules` → `.cursor/rules/*.mdc`; Windsurf: `.windsurfrules` → `.windsurf/rules/`). Duplicating protocol text into each file would guarantee drift.
- **Decision**: Ship both legacy and modern entry-point files, but every entry point contains only pointers to `AGENTS.md` — never duplicated protocol content. Protocol edits happen in exactly one place.
- **Consequences**: Updating the protocol requires editing only `AGENTS.md` / `.agentic/`; all tools stay in sync. Slight increase in file count at repo root.
