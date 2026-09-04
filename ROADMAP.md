# Roadmap

> Forward-looking plan for the Universal Agentic Development Protocol.
> This file records intent, not commitment; each landed item carries its own
> ADR under `docs/decisions/` and a CHANGELOG entry. Priorities change with
> adopter feedback.

## Current state

- **Version**: `1.9.0` (workspace/monorepo detection landed; deeper Android/Kotlin detection landed; context-module expansion + orchestration maturity landed)
- The core loop (`DISCOVER → CLASSIFY RISK → PLAN → IMPLEMENT → VERIFY →
  HANDOFF`), the honest verification model, the non-destructive installer, risk
  profiles + evidence contracts, context modules + behavioral evals, and the
  isolated multi-agent coordinator (ADR-0011, v1.6.0) are all shipped and in
  production use.
- Any new work is bounded by **ADR-0007** (extension versioning: register new
  files in both installers, N-1 migration guarantee, secrets-exclusion policy)
  and by the project's **cross-language parity rule** (every `*.sh` change is
  mirrored in `*.ps1` with shared fixtures).

## Guiding constraints

1. Detection never requires local tooling — project type is decided from repo
   signals first (README *Supported Stacks*).
2. `PASS` is impossible unless a required check actually ran; this invariant is
   structural, not advisory.
3. New context modules, risk profiles, and schemas version atomically with the
   distribution, not independently.

## Near-term (completed in v1.7)

### 1. First-class monorepo / workspace detection — **done in v1.7.0**
The previous one-level scan of `apps/`, `services/`, `packages/`, `modules/` is now
augmented by manifest-driven discovery (dual Bash + PowerShell, same fixtures).

- [x] Read workspace manifests (`pnpm-workspace.yaml` `packages` with `*`/`**`/`!`, `package.json` `workspaces` array + `{packages:[...]}` via `ConvertFrom-Json`/textual, `Cargo.toml` `[workspace]` `members`/`exclude` globs, `pom.xml` `<modules>`, `settings.gradle(.kts)` `include` `:a:b` → `a/b`).
- [x] Emit per-package checks with a stable, project-relative `working-dir` label (`apps/api` → `./apps/api` preserved, new `crates/foo`, `module-a`, `lib/core` etc.).
- [x] Extend the `tests/fixtures/golden/*.tsv` lock with 7 new workspace shapes (`pnpm-workspace`, `npm-workspaces`, `yarn-workspaces-object`, `cargo-workspace`, `maven-modules`, `gradle-multimodule`, `pnpm-workspace-recursive`) plus `run-fixtures` smoke coverage (Bash + PowerShell parity).
- Stale `feat/namespaced-checks-and-monorepo-detection` remains superseded; `feat/orchestration` local branches pruned.

### 2. Deeper Android / Kotlin detection — **done in v1.8.0**
Detection previously was root-only: it read root `build.gradle(.kts)` /
`AndroidManifest.xml` and could not follow Android plugins declared only in module
build files, version-catalog aliases, or convention plugins (README
*Supported Stacks* → *Detection notes*). Now implemented:

- [x] Follow `com.android.*` / `org.jetbrains.kotlin.android` markers in module
      build files and version catalogs.
- [x] Emit the wrapper-aware `test` / `lint` / `assembleDebug` checks per module.
- [x] Fixture coverage for convention-plugin and version-catalog layouts.

### 3. A published `ROADMAP.md` + grooming — **done**
This file. Plus:
- [x] Delete the long-superseded local feature branches (`feat/orchestration`, `feat/orchestration-impl`, `fix/review-harden-2026-08-28` pruned; remote `feat/namespaced-checks-and-monorepo-detection` remains flagged as superseded).
- [x] Add a short "Known limitations" cross-link from README to this roadmap (README now links to `ROADMAP.md` and documents the expanded workspace support).

## Medium-term (target v1.8+)

### 4. Broaden the context-module registry — **done in v1.9.0**
`.agentic/context/INDEX.md` now ships ten modules. Each declares ID / version /
load triggers / minimum profile per the existing module contract:

- [x] `performance` — latency- or memory-sensitive changes (standard).
- [x] `accessibility` — UI/UX changes affecting assistive tech (standard).
- [x] `i18n` / `localization` — new user-facing strings, locale data (standard).
- [x] `mobile-adaptive` — device/window-size/form-factor changes (standard).
- [x] `testing-infrastructure` — test harness, fixture, or CI-runner changes
  (standard).

Each new module ships `validate-context` fixture + golden coverage, and
`None selected`-correct negative fixtures (20 new fixtures: valid/none/fenced
variants per module). All ten modules are registered in both installers and
`build-bundle.sh` with installer/bundle/upgrade test coverage.

### 5. Orchestration maturity (ADR-0011)
The v1.6.0 coordinator replaced the v1.5.0 stub. Remaining follow-up:

- [x] Cross-platform integration test driving a real `--worker` through a
      complete `orchestration_started → … → orchestration_completed` run on
      Linux, macOS, and Windows (today coverage is unit/fixture-level).
- [x] Consumer docs for wiring common CLIs (`AGENTIC_WORKER_CMD`) as workers.
- [x] Decide and record a policy for stale worktree GC beyond manual
      `--cleanup`.

## Later / ideas (no target)

- **Skills as a first-class category** — ADR-0007 anticipated "skills" as a
  future extension; explore an on-demand skills registry parallel to context
  modules.
- **Optional-check policy review** — re-examine whether `optional` check
  failures should ever be promotable to blocking warnings on CI.
- **More agent-tool adapters** — add import-only entry points as new tools ship
  agent-instructions support (following the existing `CLAUDE.md` / `GEMINI.md`
  pattern).
- **Performance of large checks.tsv** — profile verifier startup on monorepos
  with hundreds of packages after item 1 lands.

## How items land

1. Open a feature branch; write the ADR first when the change is architectural.
2. Mirror every bash change in PowerShell and add shared fixtures + golden
   expectations.
3. Register any new managed/seed files in **both** installers and `build-bundle.sh`.
4. Bump `.agentic/VERSION`, sweep `protocol_version`, and add a CHANGELOG entry.
5. Land via the release workflow with extracted-archive + upgrade tests.