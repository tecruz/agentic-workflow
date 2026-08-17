# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-08-15

Lifecycle hardening hotfix; addresses the `feedback (8).md` and `feedback (9).md` findings.

### Fixed
- **Every installer write is physically confined and atomic.** All destinations
  written by `install.sh` and `install.ps1` (managed, seed, merge, generated
  checks, manifests, backups, rollback) now pass through a shared confinement
  check plus an atomic copy: the write is staged as a temporary file next to
  the destination and moved into place, so a failed write never leaves a
  partial destination and a destination whose nearest existing ancestor
  resolves outside the project root (e.g. a `.agentic` junction to an external
  directory, or a symlinked framework file) is refused before anything is
  touched. Manifest validation keeps the more permissive physical check
  (`physical_within_root`) so in-project symlinked targets remain installable;
  the write guard rejects any final-component symlink.
- **Manifest categories are enforced against a canonical registry.** Each
  path→category mapping (`AGENTS.md`/`CLAUDE.md`/`GEMINI.md`→merge,
  `.aider.conf.yml` + managed files→managed, seed files→seed) is the single
  source of truth shared by install and prune. A known path recorded under the
  wrong valid category, or a non-registry path, is tampering and fails the run
  before mutation; the manifest itself and legacy paths are not legitimate
  entries.
- **Legacy ownership no longer trusts a manifest row by itself.** The
  manifest-only ownership branch was removed; legacy files must prove
  ownership via byte-for-byte match with shipped v1.0 content or the framework
  signature.
- **Bash manifest parsing uses exact field counts.** Each manifest line is
  pre-checked with `awk -F'\t' 'NF==3'` (which never collapses or trims
  tabs) before field splitting, so leading, trailing, and adjacent empty
  fields are rejected identically in both implementations.
- **Adversarial regression coverage.** Twelve Bats tests and twelve Pester
  tests exercise category tampering, forged legacy rows, symlinked/junctioned
  destinations that point outside the project, write-blocked copies that must
  leave no partial destination and no outside mutation, and every malformed
  manifest field shape.
- **`--plan` is byte-for-byte read-only.** Merge-block removal during planned
  prune, uninstall, and ordinary updates is now a pure calculation: the shared
  merge parser classifies the file, the would-be remainder is predicted, and
  plan mode reports it without snapshotting, backing up, creating temporary
  files, or writing. Prior plan tests only asserted that files still existed;
  new byte-for-byte Bats and Pester tests hash the tree before and after
  `--prune --plan` and `--uninstall --plan`.
- **Previous-manifest paths are validated and physically confined before any
  mutation** (in every mode, including `--plan`). Every manifest row is
  checked: exactly three tab-separated fields, a known category
  (`managed`/`merge`/`seed`), a valid SHA-256, no duplicate paths, a lexical
  path with no empty / `.` / `..` segments, drive prefixes, backslashes, or
  control characters, membership in the framework's known file registry, and
  physical confinement (symlink/junction traversal cannot escape the project
  root). A malformed or adversarial manifest hard-fails the run before any file
  is created, modified, or removed.
- **Legacy cleanup no longer deletes by filename.** v1.0 legacy files
  (`.cursorrules`, `.windsurfrules`, `.clinerules`, `CONVENTIONS.md`,
  `.github/copilot-instructions.md`) are removed only when ownership is proven:
  byte-for-byte match with shipped v1.0 content, the framework signature, or a
  previous-manifest record. Unprovable files are preserved and reported as
  conflicts; the new `--prune-unverified-legacy` / `-PruneUnverifiedLegacy`
  removes them only with an automatic backup to `.agentic-backup/`.
- **Merge-marker validation is shared between install and prune.** Prune and
  uninstall now reuse the same strict parser as installation
  (`merge_state`: absent / empty / plain / valid / malformed); only a valid
  single block is ever rewritten. Malformed files are reported as conflicts
  and preserved untouched.
- **Unpredictable temporary files.** Installers write every managed, merge,
  seed, manifest, and promoted-checks file through a `mktemp`-generated (Bash)
  or randomly named (PowerShell) scratch file created in the destination
  directory, then atomically rename it. Predictable `.agentic-tmp` paths are
  gone, so a pre-existing file or symlink at one of those names can never be
  clobbered or written through. Scratch files are created only in non-plan
  runs.

### Changed
- The README no longer advertises the development repository itself as the
  adopter template; the clean bundle (`dist/agentic-workflow-<version>/`) is
  the supported distribution for adopters.

## [1.2.0] - 2026-08-14

### Added
- Installer lifecycle: `--prune` and `--uninstall` options for `install.sh` /
  `install.ps1`, both supporting `--plan` dry runs.
- Manifest-diff migration engine: an update removes files a previous install
  recorded that are no longer part of the desired set (deselected adapters,
  renamed framework files). Managed files matching their recorded checksum are
  removed; modified ones are preserved and reported as conflicts; merge files
  lose only the marker-delimited protocol block, keeping adopter content.
- v1.0 legacy migration: installers report legacy artifacts (`.cursorrules`,
  `.windsurfrules`, `.clinerules`, `CONVENTIONS.md`,
  `.github/copilot-instructions.md`); `--prune`/`--uninstall` remove the files
  while preserving `Memory/` and `.cursor/` user data.
- Bun detection: `bun.lock` and `bun.lockb` are recognized.
- Script-aware lint emission: pnpm/yarn/bun `lint` checks are emitted only when
  `package.json` defines a `lint` script (npm keeps `--if-present`).
- Ruff gating: the Python `ruff` check is emitted only when Ruff is configured
  (`[tool.ruff]`, `ruff.toml`, or `.ruff.toml`).
- Maven Checkstyle gating: `maven-lint` is emitted only when the POM mentions
  Checkstyle.
- Nested Python projects inherit Poetry/uv detection from the repository root.
- Golden-output contract: `tests/fixtures/golden/*.tsv` lock detection output;
  a corrected Bash/PowerShell parity test asserts both verifiers emit identical
  checks for every fixture.
- Clean adopter bundle: `scripts/build-bundle.sh` assembles
  `dist/agentic-workflow-<version>/` (installers, protocol entry points, and the
  `.agentic/` payload minus the framework's own checks) plus tar.gz, zip, and
  SHA256SUMS. End-to-end bundle install tests cover both installers.

### Changed
- CI is hardened: least-privilege `permissions: contents: read`, GitHub Actions
  pinned by full commit SHA, PSScriptAnalyzer pinned to 1.25.0, and dependabot
  for GitHub Actions.

## [1.1.0] - 2026-08-14

### Added
- Basic Android / Kotlin Gradle root-project detection (root
  `build.gradle`/`build.gradle.kts` with `com.android` /
  `org.jetbrains.kotlin.android` markers, or a root `AndroidManifest.xml`).
- Wrapper-enabled Gradle and Maven fixtures asserting platform-aware wrapper
  selection: `gradlew.bat` / `mvnw.cmd` on Windows, `./gradlew` / `./mvnw`
  elsewhere.
- `tests/` with Bats and Pester suites plus fixture projects and smoke
  harnesses (`tests/fixtures/run-fixtures.sh` / `run-fixtures.ps1`).
- GitHub Actions CI (`.github/workflows/ci.yml`) running the verifier, both
  test suites, shellcheck, and PSScriptAnalyzer on Linux, macOS, and Windows.
- `docs/decisions/` with this repository's Architecture Decision Records.
- `CONTRIBUTING.md` and `SECURITY.md`.

### Changed
- **Verification is now honest** (ADR-0002). `verify.sh` / `verify.ps1`
  report `PASS` (0), `FAIL` (1), `BLOCKED` (2), or `UNSUPPORTED` (3), and
  `PASS` is impossible unless at least one required check actually ran. A
  blocked required check always reports `BLOCKED`, never `PASS`.
- `.agentic/checks.tsv` is the authoritative, project-owned check list;
  stack auto-detection is now only a bootstrap fallback. Every populated row is
  validated before any command runs (requirement value, field count, non-empty
  IDs, uniqueness, and working-directory confinement to the project root).
- Installers are non-destructive, checksum-aware, and transactional
  (ADR-0003). They classify files as `managed`, `seed`, or `merge`, record
  SHA-256 in `.agentic/install-manifest.tsv`, write `.new` conflict candidates
  instead of clobbering modifications, and preserve adopter content around the
  marker-delimited protocol block in `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`. If an
  install fails partway through, a snapshot/rollback trap restores the target
  to its prior state instead of leaving a partial installation behind.
- Generating checks is decoupled from `--replace-managed`; overwriting an
  existing `.agentic/checks.tsv` requires the explicit `--replace-checks`
  (`-RegenerateChecks`) option.
- `.agentic/checks.generated.tsv` is now part of the installer transaction:
  `--generate-checks` snapshots the candidate before detection, so a failed
  install restores a reviewed candidate exactly and never leaks a freshly
  generated one.
- PowerShell detection emits the platform Gradle/Maven wrapper script
  (`gradlew.bat` / `mvnw.cmd` on Windows) instead of always emitting the Unix
  script.
- Lifecycle now ends in **HANDOFF**, not commit (ADR-0004); self-healing is
  bounded to three evidence-based repair cycles; tests are never weakened to
  go green.
- `AGENTS.md` is the canonical protocol. Redundant adapters were removed:
  `.cursorrules`, `.cursor/`, `.windsurfrules`, `.windsurf/`, `.clinerules`,
  `CONVENTIONS.md`, `.github/copilot-instructions.md`. `CLAUDE.md` and
  `GEMINI.md` are now import-only; Cursor, Windsurf, Cline/Roo, Copilot, and
  OpenCode read `AGENTS.md` natively.
- `Memory/` was removed; per-project state lives in `.agentic/STATUS.md`,
  `.agentic/tasks/`, and `.agentic/decisions/` (ADR-0005).
- Python `uv` detection prefers a `uv.lock` marker over the `uv` binary being
  present.

### Removed
- All legacy per-tool adapter files and the `Memory/` pseudo-memory store.

## [1.0.0] - 2026-08-13

Initial release of the universal agentic development protocol.