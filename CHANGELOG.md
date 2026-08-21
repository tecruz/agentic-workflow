# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-08-20

### Added
- **Risk profiles and evidence contracts (PR #7).** Tasks now declare a risk
  profile — `prototype`, `standard` (default), or `high-assurance` — that
  determines the evidence a task must carry, the verification depth, the
  handoff contents, and the approval gates.
  - `.agentic/profiles/` documents the three profiles, the escalation signals
    (authentication, payments, secrets, data migrations, production
    infrastructure, irreversible operations, public API compatibility,
    privacy, safety-critical behavior), and the default-is-`standard` /
    never-downgrade-silently rules.
  - `.agentic/templates/task.md` is a risk-aware task template with profile,
    rationale, acceptance criteria (`AC-N`), required evidence, approval
    gates, and remaining risks.
  - `.agentic/scripts/validate-task.sh` / `validate-task.ps1` structurally
    validate task files: recognized profile, required sections per profile,
    `AC-N` identifiers, evidence-table entries, no `Pending` evidence on a
    completed task, recorded approvals before completion, and the prototype
    production-readiness warning. Exit codes: `0` VALID, `1` INVALID,
    `2` BLOCKED. The Bash and PowerShell validators are held to identical
    classifications by a fixture parity test.
  - The lifecycle is now `DISCOVER → CLASSIFY RISK → PLAN → IMPLEMENT →
    VERIFY → HANDOFF` (`.agentic/WORKFLOW.md`, `AGENTS.md`).
  - Profile files, the task template, and the validators are registered as
    `managed` files in both installers and travel in the distribution bundle;
    adopter task files are never overwritten.
  - New ADR: `docs/decisions/ADR-0008-risk-profiles-and-evidence-contracts.md`.

### Changed
- **Golden-expectation CI + canonical-section hardening (PR #7 review round).**
  - Fast CI now validates every task fixture against a checked-in golden
    expectation file (`tests/parity/task-expectations.tsv`) that records the
    expected exit code and diagnostic message per fixture, so the PR gate proves
    each validator classifies each fixture correctly instead of only matching
    the two implementations to each other. `tests/parity/run-golden.sh` runs
    either validator against the golden file; `run-parity.sh` /
    `run-parity.ps1` drive both validators plus the detection parity.
  - Acceptance criteria and high-assurance Requirements now reject any
    `AC-N` / `R-N` identifier that appears in prose or a non-canonical list
    line (not only list items that fail to declare an identifier), so a
    prose-declared extra criterion or requirement can no longer escape the
    evidence contract.
  - Three new shared fixtures cover both rejections and the valid continuation
    case (154 total), with matching Bats and Pester tests.
  - The macOS compatibility job now runs the Bash task validator over the full
    fixture set against the golden file, exercising the validator under Bash
    3.2 on the compact PR gate.
  - ShellCheck is no longer globally soft-failing: targeted suppressions
    (the known SC1087 false positive plus two inline SC2034 directives for
    intentional dead assignments) let it run as a blocking check.
  - The Bash validator's Perl dependency for non-ASCII classification is now
    documented in the README requirements.

### Fixed
- **Task validator contract hardening (PR #7 follow-up).** Closes three
  evidence-contract bypasses in `validate-task.sh` / `validate-task.ps1`:
  - Unrecognized nonblank approval-gate prose is rejected instead of ignored,
    so `## Approval gates` accepts only `None identified` or structured
    `- [ ] AG-N:` / `- [x] AG-N:` records.
  - A list item without an `AC-N` / `R-N` identifier in Acceptance criteria or
    high-assurance Requirements is rejected, so every criterion and requirement
    is part of the evidence contract.
  - Table parsing state is reset at each table boundary, so the header of a
    second empty table is no longer mistaken for the first table's data row.
  - Eight new shared fixtures cover all three behaviors in both Bash and
    PowerShell (100 total), and the parity tests keep the validators identical.
- **Task validator evidence-integrity hardening (PR #7 follow-up).** Closes two
  false-success paths in `validate-task.sh` / `validate-task.ps1`:
  - Punctuation-only text is now placeholder content: a value that normalizes to
    empty after trailing punctuation is stripped (a bare `.`), so punctuation-only
    criteria, evidence, verification, risk, and `n/a` rationale statements are no
    longer counted as substantive evidence, and a punctuation-only approval
    identity is rejected because it records no meaningful approver.
  - The evidence table (`## Required evidence`) and requirement matrix
    (`## Requirement-to-evidence`) now validate every table-shaped row instead of
    silently filtering malformed rows out: unknown or malformed identifiers,
    extra or missing columns, duplicate rows, and rows that do not belong to the
    declared identifier set are rejected rather than ignored, so visibly
    unresolved evidence can no longer be hidden behind a malformed row.
  - Eleven new shared fixtures cover both behaviors in Bash and PowerShell
    (111 total), and the parity tests keep the validators identical.
- **Large-file and `pipefail` regression fixes in task validator.** Prevented pipefail bypass on large non-ASCII tasks without perl.

## [1.2.2] - 2026-08-18

Release-integrity hardfix; addresses the `feedback (12).md` and `feedback (13).md`
reviews. Ensures the source, version number, changelog, release tag, and
downloadable assets all represent the same product. Includes the PR #5 write
confinement and atomicity hardening that was not present in the published
v1.2.1 assets.

### Fixed
- **Version bump to 1.2.2.** `.agentic/VERSION` updated to match the release
  tag and published assets, resolving the mismatch where `master` contained
  PR #5 fixes but the published v1.2.1 assets pointed to the earlier commit.
- **Corrected changelog contradictions.** The previous `1.2.1` changelog
  section contained contradictory statements about legacy ownership: one entry
  correctly stated that a manifest row alone no longer proves ownership, while
  a later entry still described a previous-manifest record as proof. The
  `1.2.1` section now describes only the state at that release; all PR #5
  hardening changes are recorded here in `1.2.2`.
- **Consistent ownership policy across documentation.** `README.md`,
  `CHANGELOG.md`, `SECURITY.md`, and release notes now agree: a previous
  install manifest record is never sufficient by itself to prove legacy file
  ownership.
- **Tightened supported-version table.** `SECURITY.md` now clearly states that
  only the latest 1.x patch release is supported; older 1.x releases require
  an upgrade; pre-1.0 is unsupported.
- **Release workflow fixes.** Fixed invalid Bats `run` helper invocation in
  tar.gz archive test; corrected `cd dist` path resolution; added Bats
  installation on Windows CI; resolved immutable commit SHA for manual
  dispatch; added `--verify-tag` to `gh release create`; passed manual input
  through environment variable instead of direct shell interpolation; applied
  least-privilege permissions; used changelog-derived release notes instead of
  auto-generated notes; added draft/release lifecycle with retry; cleaned
  archives before rebuild.

### Added
- **Extracted-archive release tests.** Bats and Pester suites now extract the
  final tar.gz and zip assets into a clean directory, install from the
  extracted location, and assert that no development-only files leaked into
  the distribution.
- **Release-to-release upgrade test.** An automated scenario installs from
  the v1.2.1 bundle, adds custom content, modifies a managed file, adds a
  reviewed candidate, upgrades using the v1.2.2 bundle, and verifies exact
  preservation and expected conflicts through plan/update/prune/uninstall.
- **Release workflow** (`.github/workflows/release.yml`). Triggered by version
  tags or manual dispatch. Validates that `.agentic/VERSION`, the CHANGELOG
  section, and the tag all agree; runs all CI checks; builds the clean bundle;
  extracts and tests both archives; verifies `SHA256SUMS`; and uploads assets
  from the exact tagged commit.
- **ADR-0007: Extension versioning.** Records the policy for how future
  protocol extensions (risk profiles, skills, event logs, context modules)
  version their schemas and are migrated.

### Changed
- Every installer write is now physically confined and atomic: writes staged
  as temporary files with atomic rename; destinations whose nearest existing
  ancestor resolves outside the project root are refused.
- Manifest categories enforced against a canonical registry; tampering fails
  the run before any mutation.
- Legacy ownership no longer trusts a manifest row by itself; files must prove
  ownership via byte-for-byte match with shipped v1.0 content or the framework
  signature.
- `--plan` is byte-for-byte read-only in every mode (prune, uninstall,
  update). No snapshotting, backup, temp-file creation, or writing occurs.
- Manifest validation runs before any mutation in every mode including
  `--plan`: field count, categories, checksums, duplicates, lexical path
  safety, framework membership, and physical confinement.
- Merge-marker validation shared between install and prune (absent / empty /
  plain / valid / malformed); malformed files are preserved untouched.
- Unpredictable temp files: all writes use `mktemp`/random scratch files with
  atomic rename.
- The README no longer advertises the development repository itself as the
  adopter template; the clean bundle is the supported distribution for
  adopters.
- CI workflow (`.github/workflows/ci.yml`) is now reusable via
  `workflow_call`; release workflow calls it as a gate before publication.

## [1.2.1] - 2026-08-15

Lifecycle hardening hotfix; addresses the `feedback (8).md` and `feedback (9).md`
findings.

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
- `--prune-unverified-legacy` / `-PruneUnverifiedLegacy`: removes legacy files
  whose ownership cannot be proven by content, with automatic backup to
  `.agentic-backup/`.
- Candidate lifecycle: `--detect-checks`, `--accept-detected-checks`, and
  `--replace-checks` for a reviewable checks pipeline.
- Clean adopter bundle: `scripts/build-bundle.sh` assembles
  `dist/agentic-workflow-<version>/` plus tar.gz, zip, and SHA256SUMS.
- End-to-end bundle install tests covering both installers.

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