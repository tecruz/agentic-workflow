# TASK-014: Workspace and monorepo detection

## Status

Status: done
Updated: 2026-08-30

## Risk profile

Profile: standard

## Profile rationale

Feature addition to the verifier's stack detection (reading workspace manifests and emitting per-package checks). No authentication, payments, secrets, data migrations, production infrastructure, or safety-critical behavior is touched. No escalation signals apply; `standard` is the default per `.agentic/profiles/README.md`.

## Acceptance criteria

- AC-1: `verify.sh` and `verify.ps1` interpret `pnpm-workspace.yaml` `packages` (globs `*`/`**`, `!` exclusions) and emit per-package checks with stable `working-dir` labels.
- AC-2: `package.json` `workspaces` (array and `{packages:[...]}` object forms) is interpreted in both languages (Bash textual, PowerShell `ConvertFrom-Json`) with `!` exclusions.
- AC-3: `Cargo.toml` `[workspace]` `members` and `exclude` (globs) is interpreted and deduplicated.
- AC-4: `pom.xml` `<modules>` (literal dirs, globs) and `settings.gradle`/`settings.gradle.kts` `include` (`:a:b` → `a/b`) are interpreted.
- AC-5: Results are deduplicated between workspace manifests and the legacy `apps/`, `services/`, `packages/`, `modules/` one-level scan; the legacy scan now reuses the shared helper and preserves its `monorepo`/`nested-monorepo` contracts.
- AC-6: Seven new fixtures and goldens (`pnpm-workspace`, `npm-workspaces`, `yarn-workspaces-object`, `cargo-workspace`, `maven-modules`, `gradle-multimodule`, `pnpm-workspace-recursive`) are added and pass both Bash and PowerShell golden parity and `run-fixtures` smoke checks.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `workspace_expand_pattern` / `Expand-WorkspacePattern` + `emit_checks_for_dir` / `Emit-PackageChecks` helpers in `verify.sh`/`verify.ps1` handling `pnpm-workspace.yaml` with `*`/`**`/`!` | Passed |
| AC-2 | `package.json` workspaces handling (Bash `sed` block + PowerShell `ConvertFrom-Json`) with `!` exclusions | Passed |
| AC-3 | `Cargo.toml` `[workspace]` handling (`members`/`exclude` via `awk`+`sed` / PowerShell regex) | Passed |
| AC-4 | `pom.xml` `<modules>` and `settings.gradle(.kts)` `include` handling | Passed |
| AC-5 | `seen_packages`/`SeenPackages` + `excluded_dirs`/`ExcludedDirs` deduplication; legacy loop refactored to `emit_checks_for_dir`/`Emit-PackageChecks`; `bash tests/fixtures/run-fixtures.sh` and `pwsh tests/fixtures/run-fixtures.ps1` both report `BASH HARNESS EXIT:0` / `PS HARNESS EXIT:0` | Passed |
| AC-6 | New fixtures under `tests/fixtures/{pnpm-workspace,npm-workspaces,yarn-workspaces-object,cargo-workspace,maven-modules,gradle-multimodule,pnpm-workspace-recursive}` with `tests/fixtures/golden/*.tsv` goldens; `run-fixtures` and parity harnesses pass | Passed |

## Approval gates

- None identified

## Context modules

- None selected — detection is stack/workspace inference, not authentication, authorization, secrets, sessions, permissions, cryptography, schema changes, destructive data operations, production CI/CD, Terraform/Kubernetes/cloud resources, or public API compatibility beyond the documented detection contract.

## Files changed

- .agentic/scripts/verify.sh — new helpers `workspace_expand_pattern`, `emit_checks_for_dir`; manifest-driven discovery for 5 manifest types plus deduplication; legacy scan refactored
- .agentic/scripts/verify.ps1 — new helpers `Expand-WorkspacePattern`, `Emit-PackageChecks` (`$script:WorkspaceLines`/`SeenPackages`/`ExcludedDirs`), manifest-driven discovery for 5 manifest types, `ConvertFrom-Json` for `package.json` workspaces, legacy scan refactored
- tests/fixtures/pnpm-workspace/** — new fixture (pnpm-workspace.yaml `packages/*`)
- tests/fixtures/npm-workspaces/** — new fixture (package.json workspaces array)
- tests/fixtures/yarn-workspaces-object/** — new fixture (package.json workspaces object form)
- tests/fixtures/cargo-workspace/** — new fixture ([workspace] members/exclude)
- tests/fixtures/maven-modules/** — new fixture (pom.xml modules)
- tests/fixtures/gradle-multimodule/** — new fixture (settings.gradle include)
- tests/fixtures/pnpm-workspace-recursive/** — new fixture (pnpm `**` recursion)
- tests/fixtures/golden/pnpm-workspace.tsv — new golden
- tests/fixtures/golden/npm-workspaces.tsv — new golden
- tests/fixtures/golden/yarn-workspaces-object.tsv — new golden
- tests/fixtures/golden/cargo-workspace.tsv — new golden
- tests/fixtures/golden/maven-modules.tsv — new golden
- tests/fixtures/golden/gradle-multimodule.tsv — new golden
- tests/fixtures/golden/pnpm-workspace-recursive.tsv — new golden
- tests/fixtures/run-fixtures.sh — new `expect_detect` lines for 7 fixtures
- tests/fixtures/run-fixtures.ps1 — new `Expect-Detect` lines for 7 fixtures
- .agentic/VERSION — bump to 1.7.0
- .agentic/schemas/*.json — `protocol_version` sweep to 1.7.0
- .agentic/orchestration/coordinator.sh/ps1 — `PROTOCOL_VERSION` sweep to 1.7.0
- docs/decisions/ADR-0012-workspace-monorepo-detection.md — new ADR
- README.md — Supported Stacks table and Detection notes rewritten for workspace discovery; Roadmap cross-link
- ROADMAP.md — workspace item marked done
- CHANGELOG.md — 1.7.0 section

## Verification

### Baseline

- `bash -n .agentic/scripts/verify.sh` exit 0
- `bash tests/fixtures/run-fixtures.sh .agentic/scripts/verify.sh` exit 0 (13 fixtures, pre-change)
- `pwsh tests/fixtures/run-fixtures.ps1 .agentic/scripts/verify.ps1` exit 0

### Final

- `bash -n .agentic/scripts/verify.sh` exit 0
- `pwsh -NoProfile -File tests/ps-syntax.ps1` exit 0
- `bash tests/fixtures/run-fixtures.sh .agentic/scripts/verify.sh` exit 0 — now 20 fixtures including 7 new workspace shapes, all `golden OK`
- `pwsh tests/fixtures/run-fixtures.ps1 .agentic/scripts/verify.ps1` exit 0 — same 20, all `golden OK`
- Manual workspace tackles: `pnpm-workspace`, `npm-workspaces`, `yarn-workspaces-object`, `cargo-workspace`, `maven-modules`, `gradle-multimodule`, `pnpm-workspace-recursive` each emit the expected `required` checks in both Bash and PowerShell and respect `!` exclusions and `**` recursion; overlapping `apps/*`/`packages/*` deduplicates to one emit
- `bash -n` and `ps-syntax` still pass after the `1.7.0` protocol sweep

## Remaining risks

- Workspace discovery does not yet interpret Nx (`nx.json`), Turborepo (`turbo.json`), Cargo members declared only in `Cargo.toml` outside `[workspace]`, or Bazel — documented as out of scope in README and ADR-0012
- `pnpm-workspace.yaml` parsing is line-oriented (no YAML parser) and assumes the `packages:` block is top-level; deeply nested or flow-style YAML is not interpreted
- `package.json` workspaces object form only reads `packages` (not `nohoist`); unknown fields are ignored per ADR-0007 forward-compatibility
- `settings.gradle` `include` parsing assumes quoted `:a:b` notation; `projectDir` overrides and Kotlin DSL functions are not followed
