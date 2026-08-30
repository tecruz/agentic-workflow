# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **coordinator.sh:620** removed dead `printf` no-op that wrote to stderr then discarded output via `2>/dev/null || true`; the stdout JSON emission at line 622-623 is the intended path
- **coordinator.ps1:214-219** `Write-Log` double emission in JSON mode removed; kept only `[Console]::Error.WriteLine($Message)` to avoid writing the same message to host and stderr
- **coordinator.ps1:192-193** `Trim()` no-op removed from `Resolve-PhysicalPath`; the inner symlink-cycle check now stands alone, preventing potential infinite loops on symlink chains
- **Text/JSON exit-code asymmetry** for missing task file aligned: both text and JSON modes now exit 2 (BLOCKED), matching the `result↔exit_code` invariant and verifier semantics

### Changed
- Shellcheck coverage extended in `.agentic/checks.tsv` to `validate-context.sh`, `validate-handoff.sh`, and `coordinator.sh` (3 new scripts)
- `ps-syntax` inline PowerShell program moved from checks.tsv cell into `tests/ps-syntax.ps1`; checks.tsv now references via `-File` flag
- `.gitattributes` added enforcing LF line endings for `*.sh`/`*.ps1`/`*.md` and retiring the CRLF workaround in `tests/parity/run-golden.sh:71`
- `CODE_OF_CONDUCT.md` added (Community conduct policy per Contributor Covenant 2.1)
- `.editorconfig` added (indent style, line-ending policies for `*.sh`/`*.ps1`/`*.md`)
- `README.md` CI badge added (Shields.io badge linking to GitHub Actions CI)

### Added
- `.agentic/tasks/TASK-012-maintenance.md` — task file documenting the v1.6.1 fix round, profile: standard, context: None selected

## [1.6.0] - 2026-08-29

### Added
- **Isolated multi-agent task coordination (ADR-0011 realized).** The v1.5.0 stub is replaced by a complete coordinator:
  - Isolated `git worktree` per task under `.agentic/orchestration/worktrees/<task-id>` on branch `orchestration/<task-id>` with a per-task lock file enforcing explicit ownership and preventing concurrent conflicting mutations.
  - Generic worker runner (`AGENTIC_WORKER_CMD` or `--worker <cmd>` / `-Worker <cmd>`): any agent CLI may be supplied; the coordinator never logs command text and captures exit code/duration inside the worktree.
  - Observable handoff & aggregation: versioned JSONL event stream (`orchestration-events-v1.schema.json`: `orchestration_started` → `worker_started` → `worker_completed` → `orchestration_completed`) and aggregated `orchestration-result-v1` contract with `result↔exit_code` pairing invariants; working directories are project-relative redacted and no command lines, args, env vars, or absolute paths leak into events or results.
  - Approval controls: spawning requires both a checked `AG-N` gate and `--approve` (`-Approve`); remote writes require `--push` (`-Push`) in addition. `None identified` means the flag alone suffices; unchecked or malformed gates `BLOCK` with no worktree and no remote write. `--push` without `--approve` is rejected.
  - Bash+PowerShell twins (`coordinator.sh` / `coordinator.ps1`, `protocol_version` 1.6.0) held to identical observable behavior by shared fixtures; both plus the two new schemas are managed files (installers, bundle) and are validated by `checks.tsv`/`ps-syntax` and bundle-leak gates.
  - Operational guards: `git` required for worktrees; events and `--format json` remain mutually exclusive (like `verify`), event destinations confined to `.agentic/runs/` and promoted atomically (scratch + hard-link / `Move-Item -Force` with `EventsForce`); `--cleanup` removes the worktree.
  - ADR-0011 amended with the realized v1.6.0 design; orchestration `README.md` rewritten with usage and redaction guarantees; `VERSION` and `protocol_version` sweep to `1.6.0` across all emitters and schemas; real v1.5.0→v1.6.0 migration test; eval harness `protocol_version` also swept to `1.6.0` with scenario artifacts updated.

## [1.5.0] - 2026-08-24

### Added
- **Portable context modules and offline behavioral evaluations (PR #10).**
  Specialist knowledge moves out of the always-loaded protocol into an
  on-demand registry that agents consult during DISCOVER.
  - `.agentic/context/` ships five portable modules — `security-review`,
    `database-migrations`, `dependency-changes`, `infrastructure-change`, and
    `public-api-change` — each declaring ID, version, load triggers, minimum
    risk profile, required context, approval gates, required evidence, and
    prohibited shortcuts, indexed by `.agentic/context/INDEX.md`.
  - The task contract records selections under `## Context modules`:
    known module ID, recognized version, a `loaded` confirmation, and a real
    rationale; the `None selected` sentinel covers untriggered work. A
    module's minimum risk profile is a floor for the task's profile.
  - New structural validators `.agentic/scripts/validate-context.sh` /
    `validate-context.ps1` (exit codes: 0 VALID, 1 INVALID, 2 BLOCKED) reject
    unknown (`MODULE_UNKNOWN`), duplicate (`MODULE_DUPLICATE`),
    rationale-missing (`MODULE_RATIONALE_MISSING`), version-unsupported
    (`MODULE_VERSION_UNSUPPORTED`), profile-incompatible
    (`MODULE_PROFILE_TOO_LOW`), unresolved (`MODULE_SELECTION_UNRESOLVED`),
    and section-less (`CONTEXT_SECTION_MISSING`) selections; both
    implementations are held to identical classifications by shared fixtures,
    and JSON output follows the v1.4.0 result-contract principles validated by
    `.agentic/schemas/context-selection-v1.schema.json`.
  - Offline deterministic behavioral evaluations under `evals/`: scenario
    schema, evaluation-result schema, eight scenarios covering expected and
    forbidden observable behavior (authentication change, database migration,
    dependency bump, infrastructure change, public API change,
    documentation-only edit, untrusted issue instruction, test-weakening
    attempt), and cross-platform runners (`run-evals.sh` / `run-evals.ps1`).
    No scenario calls an external model; no API keys are required.
  - Adopter bundles ship the registry, validators, and schema but exclude the
    evaluation harness: `evals/` is enforced as a leak in `build-bundle.sh`
    and the release workflow's bundle gate.
  - New ADR-0010 records file categories, schema fields, and migration rules.

### Changed
- **Review hardening for the context and evaluation layer.**
  - The handoff gate is now a single public command:
    `.agentic/scripts/validate-handoff.sh` / `.ps1` run BOTH
    `validate-task --handoff` and `validate-context --handoff` against one
    task file (exit 0/1/2), so context validation can no longer be skipped at
    handoff; WORKFLOW.md, AGENTS.md, checks.tsv, and both fast CI legs use it.
  - `validate-context` validates its own registry before use: declared IDs
    must match `^[a-z0-9][a-z0-9-]*$`, equal their directory name, be unique,
    carry a positive-integer version and a recognized minimum profile, declare
    each required heading exactly once, and keep substantive documentation
    content; violations block wholesale as `CONTEXT_REGISTRY_INVALID`, and
    task-provided IDs never construct filesystem paths.
  - Fixed a PowerShell regex typo that crashed fenced-code handling
    (`'^```\)'`); new shared fixtures pin identical classification of
    fenced/commented/blockquoted/unclosed-fence content in both validators.
  - JSON output redacts absolute task paths identically on both platforms
    (project-relative inside the project, basename outside).
  - Successful-leg Bash JSON serialization is checked like every failure leg;
    an unwritable destination or failing interpreter exits non-zero instead of
    reporting VALID with no document.

### Fixed
- Behavioral evaluations now enforce the real production contracts: scenario
  definitions validate against `scenario-v1.schema.json`, artifact tasks must
  pass BOTH validators in handoff mode, verification artifacts must satisfy
  `verification-result-v1.schema.json` with summary counts agreeing with their
  checks array, and approvals/evidence are parsed only from authoritative
  sections. Positive fixtures are full production-contract high-assurance /
  standard tasks; the negative control is valid in every other respect and
  fails only its intended forbidden-action check.
- Evaluation result documents separate observation from harness verdict
  (`observed_result` / `expected_result` / `expectation_matched` / `result` /
  `exit_code`) so negative controls no longer violate their own schema; every
  emitted document is schema-checked before emission and revalidated by CI's
  pinned-jsonschema job.

## [1.4.0] - 2026-08-24

### Added
- Versioned JSON result contracts and optional run events (PR #9).
  - Added JSON output modes (`--format json` in Bash, `-Format Json` in PowerShell) to both project verifiers and task validators.
  - Added managed JSON schemas (`.agentic/schemas/verification-result-v1.schema.json` and `.agentic/schemas/task-validation-result-v1.schema.json`) registered in installers, bundles, and manifest categories.
  - Added optional local JSONL observable event streams (`--events` / `-Events`) with strict privacy safeguards and git-ignored run directories (`.agentic/runs/`).
  - Added stable diagnostic error codes for task validation failures.
  - Added ADR-0009.
  - Pure-bash JSON serialization in verify.sh (no Python dependency).
  - Project-relative path redaction in verification working_directory.
  - Explicit diagnostic codes at failure sites (no keyword inference).
  - Nullable profile/task_status in task validation JSON.
  - Restricted event destination to `.agentic/runs/` with overwrite protection.
  - Real JSON encoding for events (ConvertTo-Json in PowerShell, `json_escape` in Bash).
  - Terminal verification_completed event emitted in text mode; `--format json` / `-Format Json` and `--events` / `-Events` cannot be combined.
  - Versioned event schema (`verification-events-v1.schema.json`).

### Changed
- Refined redaction policy: project-relative paths only; no raw malformed source lines in JSON diagnostics.
- Strengthened JSON schemas with `additionalProperties: false`, integer bounds on summary counts/durations, and protocol_version constraining to "1.4.0".
- Strengthened schemas further with draft-07 `if/then` invariants pairing every `result` with its exit code and requiring diagnostics on task-validation failures; the stable diagnostic codes are now a closed set enumerated in the schema.
- Diagnostic code helpers take explicit `<code> <section> <identifier> <message>` arguments at every call site; message-keyword inference removed from both validators.
- Verification summaries separate failure kinds: `failed` counts failed required checks only and a new `optional_failed` field counts failed optional checks, which never fail a run. The verification schema additionally requires any PASS document to have run at least one required check (`required_run >= 1`) with zero required failures.
- Output format is strict in both languages: unknown or missing `--format` values are rejected with a clear error instead of silently degrading to text mode (PowerShell via ValidateSet, Bash via explicit validation).

### Fixed
- Optional check failures no longer produce schema-invalid `PASS` documents.
- Bash JSON preserves full project-relative working-directory labels for nested monorepo paths (`apps/api` becomes `./apps/api`, never a bare basename), matching PowerShell labels exactly; relative labels are normalized lexically like the validated checks.tsv contract.
- Task-validator not-found diagnostics no longer leak absolute task paths into serialized JSON: the message carries only the redacted display value, and Windows-drive-style paths degrade to their basename on non-Windows hosts.
- Bash event streams are built under an unpredictable `mktemp` scratch name beside the destination and promoted with a no-clobber recheck immediately before the atomic rename; failed promotions clean up the scratch file.
- Bash `--events-force` rejects existing non-regular destinations (directories, FIFOs, devices) before promotion instead of letting `mv -f` move the scratch stream inside a directory and report success; forced promotion now verifies that a regular file actually landed at the destination path and releases the scratch tracker on success.
- Bash `--events` initialization ordering (function hoisting).
- Bash JSON stdout contamination (all messages routed through `log()`).
- Bash serialization failure propagation (`|| exit 1` on python3 failure).
- PowerShell event string-concatenation vulnerabilities (now use `ConvertTo-Json`).
- PowerShell working_directory and task_file redaction to project-relative paths.
- Invalid task metadata no longer generates misleading JSON defaults.
- Event streams initialize only after contract validation succeeds, so contract failures never leave an unterminated stream or a mismatched UNSUPPORTED/exit-1 pairing; destinations are confined to `.agentic/runs/` lexically and physically, created atomically, and never overwritten without `--events-force` / `-EventsForce`.
- Bash task-validator JSON mode now requires `python3` only for `--format json` (text mode unchanged) and propagates serializer failures as nonzero exits instead of emitting empty documents.
- JsonContracts suite parses verifier output before its temp-file cleanup, so the python3-stub test can pass on Linux CI where it actually runs.

## [1.3.0] - 2026-08-21

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