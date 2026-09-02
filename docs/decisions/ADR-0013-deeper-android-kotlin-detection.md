# ADR-0013 — Deeper Android and Kotlin detection

- **Date**: 2026-09-01
- **Status**: Accepted
- **Deciders**: maintainers (ROADMAP.md item 2, PR #17)

## Context

The verifier's Gradle/Android detection was root-only: it inspected only the
root `build.gradle`/`build.gradle.kts` and `AndroidManifest.xml` for Android
plugin markers (`com.android.*`, `org.jetbrains.kotlin.android`). It could not
interpret:

- Module-level `build.gradle(.kts)` where the Android plugin is actually
  applied (root often uses `apply false`).
- Version catalogs (`gradle/libs.versions.toml`) where the Android plugin
  version is declared via `android-application = { id = "com.android.application" }`.
- Convention plugins in `build-logic/` that encapsulate Android/Kotlin
  configuration and are referenced by modules via `id("...")`.

The README's *Detection notes* explicitly documented this gap. The stale
exploratory branch `feat/namespaced-checks-and-monorepo-detection` predated
this work but had diverged.

ADR-0007 requires that protocol_version move atomically when the detection
contract changes. The cross-language parity rule requires every `*.sh` change
mirrored in `*.ps1` with shared fixtures.

## Decision

1. **Split detection into two scopes** — **root-level** and **per-module**:
   - `is_android_project_root` / `Test-AndroidProjectRoot`: checks the
     project root for Android plugins in root build files, version catalog
     (`gradle/libs.versions.toml`), and convention plugin references
     (`id("...android...")`).
   - `is_android_module` / `Test-AndroidModule`: checks ONLY the module's
     own build files and `AndroidManifest.xml` — **excludes** version
     catalog to avoid false positives in mixed Android + pure-Java/Kotlin
     projects.

2. **Root-level detection** (`detect()` / `Get-DetectedChecks`) now calls
   the root helper, gaining version-catalog and convention-plugin awareness.
   A root project using `alias(libs.plugins.android.application) apply false`
   is now correctly detected.

3. **Per-module detection** (`emit_checks_for_dir` / `Emit-PackageChecks`)
   calls the module helper. Modules discovered via `settings.gradle(.kts)`
   `include` are checked against their own build files only. Mixed projects
   (Android `:app` + pure-Java `:shared`) correctly emit Android checks only
   for the Android modules.

4. **Fixtures + goldens** — two new fixtures with CI parity:
   - `android-version-catalog`: root uses `alias(libs.plugins.android.application)`
     via `gradle/libs.versions.toml`; app module uses alias + convention plugin;
     shared module is pure Kotlin-JVM.
   - `android-convention-plugin`: root applies `apply false` convention plugin
     (`com.example.android.lib`); app module applies it; `build-logic/conventions`
     declares AGP dependency.

5. **Protocol version bump** — `protocol_version` and `.agentic/VERSION`
   sweep to `1.8.0` (per ADR-0007: detection contract change).

6. **Cross-language parity** — both Bash (`verify.sh`) and PowerShell
   (`verify.ps1`) implement the split helpers; `git -C $Dir` parity fixed.

## Consequences

- Projects using modern Gradle (version catalogs + convention plugins) are
  now fully detected without hand-maintained `.agentic/checks.tsv`.
- Mixed Android + library projects no longer misclassify pure-library modules
  as Android (version-catalog check is root-level only).
- Detection remains zero-toolchain: purely filesystem + textual parsing.
- The verifier's contract (TSV columns, `requirement<tab>id<tab>cwd<tab>exe<tab>args...`)
  is unchanged — only the set of emitted `cwd` values grows.
- Future workspace formats (Nx, Turborepo, Bazel) remain explicitly out of
  scope per README.

## Alternatives considered

- **Single helper with scope parameter**: Rejected — clarity and false-positive
  isolation is better with two distinct functions.
- **Full `build.gradle` AST parsing**: Overkill; textual grep is zero-dep and
  sufficient for marker detection.
- **Parsing `settings.gradle` `includeBuild` for convention plugins**: Added
  for `android-convention-plugin` fixture scope; general case left for future
  ADR if needed.