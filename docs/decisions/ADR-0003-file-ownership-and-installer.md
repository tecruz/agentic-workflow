# ADR-0003 — Non-destructive installer with file ownership & checksums

- **Date**: 2026-08-13
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback.md`

## Context

The original installer overwrote project files with `-Force`, silently
clobbering adopter customizations and shipping `Memory/` files that gave the
impression of stateful memory. Review feedback (§4 "file ownership",
§6 "non-destructive installer") required an installer that never destroys
project content and clearly distinguishes framework files from project files.

## Decision

- File ownership model:
  - **managed** — framework files. Replaced on update only if unchanged since
    the last install (verified against `.agentic/install-manifest.tsv`
    checksums). If the adopter modified a file, a conflict is reported and a
    `.new` candidate is written; `--replace-managed`/`--force` forces
    replacement.
  - **seed** — project-owned templates (`.agentic/ARCHITECTURE.md`,
    `.agentic/checks.tsv`, `.agentic/STATUS.md`). Created once, never
    overwritten.
  - **merge** — `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`. Only the marker-delimited
    managed block is added or updated; all other content is preserved.
- `.agentic/install-manifest.tsv` records version, category, and SHA-256 per
  file; paths are normalized to forward slashes so `install.sh` and
  `install.ps1` interoperate.
- Flags: `--plan`, `--update`, `--backup`, `--tools`, `--generate-checks`,
  `--replace-managed`, `--force`. A partial-install guard aborts if
  `AGENTS.md` was not installed.
- `Memory/` files were removed; per-project state now lives in `STATUS.md`,
  `tasks/`, and `decisions/` (see ADR-0005).

## Consequences

- Adopter customizations are never silently lost; conflicts surface as
  reviewable `.new` files.
- Manifest must be kept consistent across both installers; any future file
  added to the framework must be registered in both file lists.
- `--generate-checks` runs before seeding so a generated `checks.tsv` is not
  shadowed by the template.