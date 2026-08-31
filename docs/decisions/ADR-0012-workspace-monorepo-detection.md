# ADR-0012 — Workspace and monorepo detection

- **Date**: 2026-08-30
- **Status**: Accepted
- **Deciders**: maintainers (ROADMAP.md item 1, `feat/namespaced-checks-and-monorepo-detection` predecessor noted as superseded)

## Context

`verify.sh` / `verify.ps1` auto-detection was one-level and hardcoded: it inspected
only direct children of `apps/`, `services/`, `packages/`, `modules/` and emitted
Node, Go, Rust, and Python checks there. The README's *Detection notes*
explicitly documented the gap: no interpretation of `pnpm-workspace.yaml`,
`package.json` `workspaces`, `Cargo.toml` `[workspace]`, `pom.xml` `<modules>`,
or `settings.gradle(.kts)` `include`, and no handling of globs, `!` exclusions,
or `**` recursion. Nx, Turborepo, and Bazel were also noted as not yet
interpreted. The stale exploratory branch `feat/namespaced-checks-and-monorepo-detection`
predated v1.3.0 and had diverged beyond useful merge.

ADR-0007 requires that new file types register in the canonical managed/seed/merge
registry and that the distribution's `protocol_version` move atomically when the
detection contract changes. The cross-language parity rule requires every
`*.sh` change to be mirrored in `*.ps1` with shared fixtures.

## Decision

1. **Manifest-driven discovery augments the legacy scan.** `detect()` /
   `Get-DetectedChecks` now, in order:
   - `pnpm-workspace.yaml` `packages` (quoted/unquoted entries, `#` comments, `!` exclusions, `*`/`**` globs via `nullglob`+`globstar` / `Get-ChildItem -Recurse`)
   - `package.json` `workspaces` (array `["pkg/*"]` and object `{"packages":[...]}`; Bash textual extraction via `sed` on `"workspaces"` blocks, PowerShell via `ConvertFrom-Json`; `!` exclusions)
   - `Cargo.toml` `[workspace]` `members` and `exclude` (quoted-string extraction from the `[workspace]` section via `awk`+`sed` / PowerShell regex, globs)
   - `pom.xml` `<modules>` (`<module>dir</module>` literal dirs, globs)
   - `settings.gradle` / `settings.gradle.kts` `include` (`:lib:core` → `lib/core`, multiple per line, single/double quotes)
   - Legacy one-level scan of `apps/`, `services/`, `packages/`, `modules/` (now via the shared helper, deduplicated)

2. **Shared helpers and deduplication.** Both languages gain
   `workspace_expand_pattern` / `Expand-WorkspacePattern` (control-char and
   `node_modules`/`target`/`build`/`.venv`/`.git` filtering, `*`/`**` expansion)
   and `emit_checks_for_dir` / `Emit-PackageChecks` (per-stack emission for Node
   with `pnpm`/`yarn`/`bun`/`npm` lockfile gating and `lint` script gating, Go,
   Rust, Python with Poetry/uv/Ruff gating, Maven with `mvn`/`./mvnw` and
   Checkstyle gating, Gradle with Android detection and `gradle`/`./gradlew`
   selection, .NET `*.sln`/`*.csproj`). A `seen_packages`/`SeenPackages` set
   and `excluded_dirs`/`ExcludedDirs` set (populated from `!` / Cargo `exclude`)
   deduplicate workspace and legacy results; the legacy scan now calls the same
   helper instead of inline duplication.

3. **File categories.** No new managed files. `verify.sh` and `verify.ps1` are
   existing managed files and update under the unchanged-since-install rule.
   The seven new fixtures (`pnpm-workspace`, `npm-workspaces`,
   `yarn-workspaces-object`, `cargo-workspace`, `maven-modules`,
   `gradle-multimodule`, `pnpm-workspace-recursive`) and their
   `tests/fixtures/golden/*.tsv` goldens are framework-development material
   (like `monorepo` / `nested-monorepo`), not shipped in the adopter bundle.
   `run-fixtures.sh`/`run-fixtures.ps1` gain smoke coverage for the new
   shapes; the Bats/Pester parity harness automatically covers them via the
   `golden/*.tsv` loop.

4. **Result contract.** The emitted TSV contract is unchanged (same columns,
   same `requirement<TAB>id<TAB>cwd<TAB>exe<TAB>args...` rows); only the set of
   `cwd` values grows. Working-directory labels remain project-relative with
   `./` prefix handling via `normalize_project_rel`. The `result↔exit_code`
   and `required_run` invariants are untouched.

5. **Protocol version bump.** `protocol_version` constants move to `"1.7.0"`
   across all emitters (`verify.sh/ps1`, `validate-task.sh/ps1`,
   `validate-context.sh/ps1`, `coordinator.sh/ps1`) and schemas
   (`verification-result-v1`, `task-validation-result-v1`,
   `context-selection-v1`, `orchestration-result-v1`,
   `orchestration-events-v1`, `verification-events-v1`) as one atomic sweep,
   per ADR-0007's distribution-level versioning. `.agentic/VERSION` moves to
   `1.7.0`. `evals/` artifact `verification-result.json` files are swept
   likewise; they are not shipped.

## Consequences

- Adopters whose repos define workspaces via the supported manifests now get
  per-package checks without hand-maintaining `.agentic/checks.tsv` or relying
  on the legacy `apps/*` convention; `**` recursion covers deep packages.
- Non-workspace projects are unaffected: when no workspace manifest is present,
  detection falls back to the existing root + legacy scan, whose golden
  contracts are preserved (`monorepo`, `nested-monorepo`, `polyglot-node-go`,
  etc.).
- The verifier's dependency on local tooling remains none: detection is purely
  filesystem + textual parsing, required before any tool is needed.
- Future workspace formats (Nx `nx.json`, Turborepo `turbo.json`, Bazel) remain
  explicitly out of scope and continue to be documented as such in the README
  until a follow-up ADR lands.
