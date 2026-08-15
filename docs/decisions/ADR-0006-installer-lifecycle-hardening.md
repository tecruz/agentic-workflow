# ADR-0006 — Installer lifecycle hardening: read-only plans, confined manifests, proven legacy ownership

- **Date**: 2026-08-15
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback (8).md`

## Context

The v1.2.0 installer lifecycle (ADR-0003) introduced `--prune`, `--uninstall`,
and automatic adapter pruning during updates, but review found four defects the
green suite did not catch:

1. `--plan` was not read-only: merge-block stripping rewrote the file before
   plan mode was handled, so a dry run could remove a managed block.
2. `.agentic/install-manifest.tsv` was trusted as authoritative input. A
   tampered manifest could record paths outside the project (including via
   `..` or a symlinked directory) and steer the installer into deleting or
   rewriting external files.
3. Legacy cleanup deleted files by filename only, so a project-owned
   `.github/copilot-instructions.md` (for example) could be removed as a "v1.0
   artifact" even though the framework never created it.
4. Merge-marker validation was stricter on install than on prune, so malformed
   markers could be partially rewritten despite the documented contract.

## Decision

- **Byte-for-byte read-only plans.** Merge-block removal becomes a pure
  calculation. A shared `merge_state` classification (`absent` / `empty` /
  `plain` / `valid` / `malformed`) is used by install, update, prune, and
  uninstall in both installers. Plan mode prints the would-be outcome from the
  predicted remainder and returns without snapshotting, backing up, creating
  scratch files, or writing. Only a valid single block is ever rewritten,
  atomically.
- **Manifest validation before any mutation.** Before any file is installed,
  updated, pruned, or uninstalled — in every mode including plan — the entire
  previous manifest is validated: exactly three tab-separated fields, a known
  category, a valid SHA-256, unique paths, a lexical path with no empty / `.` /
  `..` segments, drive prefixes, backslashes, or control characters,
  membership in the framework's known file registry, and physical confinement
  via symlink-following path resolution against the physical project root. Any
  invalid row hard-fails the run before anything changes.
- **Legacy ownership by content, not filename.** v1.0 legacy files are removed
  only when a known v1.0 checksum matches, the content carries the framework
  signature, or the previous manifest records ownership. Unprovable files are
  preserved as conflicts. The new `--prune-unverified-legacy`
  (`-PruneUnverifiedLegacy`) removes them only with an automatic backup to
  `.agentic-backup/`.
- **Unpredictable temporary files.** All managed, merge, seed, manifest, and
  promoted-checks writes go through a `mktemp`-generated (Bash) or randomly
  named (PowerShell) scratch file created in the destination directory and
  atomically renamed. Predictable `.agentic-tmp` names are eliminated, and
  scratch files are created only in non-plan runs.
- **Corrected distribution guidance.** The development repository is not
  advertised as the adopter template; the clean bundle is the supported
  distribution.

## Consequences

- Plan mode is a true dry run: tests now assert byte-for-byte equality of the
  project tree before and after `--prune --plan` and `--uninstall --plan`.
- A malformed or adversarial manifest can no longer cause out-of-project file
  operations; the installer stops before any mutation.
- Legacy cleanup no longer risks deleting independent project content, at the
  cost of an explicit opt-in flag for unprovable files.
- Install and prune share one merge parser, so behavior cannot diverge.
- Installer writes are concurrency-safe against pre-existing temp-named files.
