# ADR-0015 — Workspace detection: Nx, Turborepo, and Bazel

- **Date**: 2026-09-06
- **Status**: Accepted
- **Deciders**: maintainers (ROADMAP.md, README.md detection notes gap)

## Context

ADR-0012 added manifest-driven workspace discovery for pnpm, npm/yarn,
Cargo, Maven, and Gradle. The README's Detection Notes explicitly
acknowledged that "Nx, Turborepo, and Bazel are not yet interpreted."
These three tools represent the most common monorepo platforms that
ADR-0012's existing manifests do not cover:

- **Nx** (`nx.json`): an incremental monorepo build system that can
  declare project paths explicitly via its `projects` field, independent
  of the underlying package-manager workspace configuration.
- **Turborepo** (`turbo.json`): a task-runner that builds on top of
  `package.json` `workspaces` and defines `pipeline` task dependencies.
  Its value is task-graph awareness, not project discovery.
- **Bazel** (`WORKSPACE`/`WORKSPACE.bazel` + `BUILD`/`BUILD.bazel`):
  a completely independent build system that does not use package.json
  at all; projects are defined by `BUILD` files containing targets.

The cross-language parity rule requires every `*.sh` change to be
mirrored in `*.ps1` with shared fixtures. ADR-0007 requires no new
managed files (verify scripts are existing managed files).

## Decision

1. **Nx detection** (`nx.json`): when `nx.json` exists, scan for a
   `projects` object and extract directory values. Each discovered
   directory is fed to `emit_checks_for_dir` / `Emit-PackageChecks`.
   If `nx.json` has no `projects` field, or projects is `"*"` (the
   default, meaning infer from `package.json workspaces`), detection
   falls through to the existing package-manager workspace detection
   which is already in place. This ensures Nx projects with non-standard
   paths are discovered even when the package-manager workspace field
   doesn't list them.

2. **Turborepo detection** (`turbo.json`): when `turbo.json` exists,
   it signals a Turborepo monorepo. Turborepo does not define project
   paths — it relies on the underlying package-manager workspace.
   Detection logs the signal and delegates to the existing pnpm/yarn/npm
   workspace detection, which is already active. No new emission logic
   is needed; the `turbo.json` signal is used only for logging and
   future extensibility (e.g., emitting `turbo run test` instead of
   per-package `pnpm test`).

3. **Bazel detection** (`WORKSPACE`/`WORKSPACE.bazel`): when a Bazel
   workspace root is detected, emit:
   - `required  bazel-test  .  bazel  test  //...`
   - `required  bazel-build  .  bazel  build  //...`
   The command `bazel` is resolved from PATH; a missing `bazel`
   produces BLOCKED (exit 2), consistent with every other stack.
   Sub-packages are not recursively discovered; Bazel's `//...`
   wildcard already covers all targets in the workspace.

4. **Detection order**: Nx, Turborepo, and Bazel are detected after
   the existing five manifests (pnpm, npm/yarn, Cargo, Maven, Gradle)
   and before the legacy directory scan. Each new block is independent
   and additive — if a project already emitted Node checks via
   `package.json` workspaces, the Nx/Turborepo signal is logged but
   no duplicate checks are emitted (deduplication via the existing
   `seen_packages` / `SeenPackages` sets).

5. **Fixtures and goldens**: two new test fixtures:
   - `nx-workspace`: `nx.json` with explicit `projects`, `package.json`
     workspaces absent, plus mock Nx project directories with
     `package.json` and `project.json`.
   - `bazel-workspace`: `WORKSPACE.bazel` with `BUILD.bazel` files
     in two sub-packages.
   Both fixtures get golden TSV files. Turborepo is covered by an
   `nx-workspace` variant (`turbo.json` present, `package.json`
     workspaces also present — existing detection covers members).
   `run-fixtures.sh` / `run-fixtures.ps1` gain smoke coverage.

6. **File categories**: no new managed files. Test fixtures and goldens
   are development material (like `monorepo`, `nested-monorepo`) and
   are excluded from the adopter bundle. The README Detection Notes are
   updated to document the new detection.

7. **Result contract**: the emitted TSV format is unchanged. Only the
   set of working-directory values grows. The `result ↔ exit_code`
   invariant is untouched.

## Consequences

- Bazel projects now get honest verification (`PASS` impossible unless
  `bazel test //...` actually ran) without hand-editing `.agentic/checks.tsv`.
- Nx monorepos with non-standard project paths (not captured by
  `package.json` `workspaces`) are now discovered automatically.
- Turborepo projects are explicitly recognized for logging and future
  `turbo run` emission, even though today they piggyback on the existing
  package-manager workspace detection.
- Non-workspace projects are unaffected: when none of the new manifest
  files exist, detection falls through unchanged to the legacy scan,
  preserving all existing golden contracts.
