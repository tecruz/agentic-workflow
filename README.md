# Universal Agentic Development Protocol

A technology-agnostic, tool-agnostic agentic workflow you can drop into your
project. It gives every AI coding agent the same operating instructions, the
same 5-phase execution loop, and the same definition of "done" — regardless of
language, framework, or which agent tool you use.

- **Technology-independent**: the verifier auto-detects the project stack
  (Node.js, Rust, Python, Go, Java/Maven, Gradle, Android/Kotlin, .NET — see
  the [supported stacks table](#supported-stacks)) and runs the checks that
  project defines.
- **Agent-tool-independent**: OpenCode, Claude Code, Gemini CLI, Cursor,
  Windsurf, Roo Code / Cline, GitHub Copilot, and Aider all read the same
  canonical instructions from `AGENTS.md`.
- **Honest verification**: the verifier can never report success when a
  required check did not actually run.

---

## Requirements

- **Linux / macOS / WSL**: `bash` 4+ with `sha256sum` (or `shasum` on macOS).
- **Windows**: [PowerShell 7+](https://github.com/PowerShell/PowerShell).
- Node.js, Rust, Python, Go, or .NET toolchains only if you want the verifier
  to run that stack's checks.

---

## Quick Start

### Install into an existing project

```bash
git clone https://github.com/tecruz/agentic-workflow.git
cd agentic-workflow

# Linux / macOS
./install.sh /path/to/your-project

# Windows (PowerShell 7+)
./install.ps1 -Target C:\path\to\your-project
```

The installer distinguishes three kinds of files and never silently destroys
project content (see [File ownership](#file-ownership)):

- **managed** — framework files. Updated only when unchanged since the last
  install; if you modified one, a `.new` conflict candidate is written instead.
- **seed** — project-owned files (`.agentic/ARCHITECTURE.md`,
  `.agentic/checks.tsv`, `.agentic/STATUS.md`). Created once, never overwritten.
- **merge** — `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`. Only the marker-delimited
  protocol block is added or updated; all your other content is preserved.

Update an existing install by re-running the installer; use `--replace-managed`
(`-ReplaceManaged`) to force-replace modified framework files. See
`./install.sh --help` for all options.

The installer also manages the lifecycle of what it installed:

- **Deselect an adapter**: re-run with a smaller `--tools`/`-Tools` list (e.g.
  `--tools claude`). The deselected adapter's files are removed; any custom
  content you added to a merge file outside the protocol block is preserved.
- **`--prune`** (`-Prune`): removes every file no longer part of the install
  (deselected adapters, renamed framework files) and the legacy v1.0 adapter
  files (`.cursorrules`, `.windsurfrules`, `.clinerules`, `CONVENTIONS.md`,
  `.github/copilot-instructions.md`), then rewrites the manifest. Legacy
  directories (`Memory/`, `.cursor/`) are reported but never deleted.
- **`--uninstall`** (`-Uninstall`): removes all managed files and strips the
  protocol block from merge files, leaving project-owned seeds
  (`.agentic/ARCHITECTURE.md`, `STATUS.md`, `checks.tsv`, `tasks/`,
  `decisions/`) intact.
- Modified managed files are never silently removed: during a prune or
  uninstall they are kept and reported as conflicts. Both `--prune` and
  `--uninstall` support `--plan` (`-Plan`) dry runs that show what would change.

Then commit the installed files and fill in `.agentic/ARCHITECTURE.md` with
your project's real architecture (or let your agent do it in its first session).

### Verify a project

```bash
# Linux / macOS
./.agentic/scripts/verify.sh

# Windows (PowerShell 7+)
./.agentic/scripts/verify.ps1
```

The verifier runs the checks defined in `.agentic/checks.tsv` (project-owned,
authoritative). If that file defines no checks, it auto-detects the stack as a
bootstrap.

### The checks candidate lifecycle

Stack detection never writes directly into `.agentic/checks.tsv`; it produces a
reviewable **candidate** first, so you can edit it before it becomes the
authoritative contract:

1. `--detect-checks` (`-DetectChecks`) writes the detected contract to
   `.agentic/checks.generated.tsv`. Re-running it replaces a stale candidate, or
   removes it when no stack is found.
2. Review and edit `.agentic/checks.generated.tsv` to match your project's real
   definition of done.
3. `--accept-detected-checks` (`-AcceptDetectedChecks`) validates the candidate
   and promotes it to `.agentic/checks.tsv`. It promotes the exact reviewed
   file, never a fresh detection, and refuses to overwrite an existing
   `.agentic/checks.tsv` unless `--replace-checks` (`-ReplaceChecks`) is given.

`--generate-checks` (`-GenerateChecks`) is the legacy single-step shortcut: it
runs detection, validates, and promotes the candidate to `.agentic/checks.tsv`
in one transaction. Because generation is transactional, a failed install
restores any pre-existing `.agentic/checks.generated.tsv` (and never leaks a
newly generated one).

### Use as a GitHub template

Click **Use this template** when creating a new repository — the protocol
ships pre-installed.

### Distribution bundle

`scripts/build-bundle.sh` packages a self-contained distribution into
`dist/agentic-workflow-<version>/` plus tar.gz, zip, and SHA256SUMS. The bundle
contains exactly what the installers seed and manage — the protocol entry
points, both installers, and the `.agentic/` payload — and deliberately omits
the framework's own checks, tests, CI, and docs so adopters start clean:

```bash
bash scripts/build-bundle.sh                    # assemble + archive
bash dist/agentic-workflow-1.2.0/install.sh /path/to/your-project
```

---

## How It Works

Every agent session follows the same 5-phase loop:

```
DISCOVER → PLAN → IMPLEMENT → VERIFY → HANDOFF
```

1. **Discover** — read `AGENTS.md`, project state, and existing patterns
   before touching code.
2. **Plan** — decompose the request into atomic, verifiable steps and record
   them in `.agentic/tasks/`.
3. **Implement** — minimal, style-matching changes per `.agentic/rules/`.
4. **Verify** — run the project's checks. Self-heal failures with at most
   three evidence-based repair cycles; never weaken a test to go green.
5. **Handoff** — report files changed, verification commands with exit codes
   and results, pre-existing failures, environment blockers, remaining risks,
   and commit status. Commits happen only when explicitly requested or
   permitted by project policy.

Full details: [`.agentic/WORKFLOW.md`](.agentic/WORKFLOW.md). Canonical agent
instructions: [`AGENTS.md`](AGENTS.md).

---

## Verification State Model

The verifier reports one of four states and never reports `PASS` unless at
least one required check actually ran:

| Code | Result | Meaning |
| ---: | :--- | :--- |
| 0 | **PASS** | At least one required check ran and all passed |
| 1 | **FAIL** | A required check ran and failed |
| 2 | **BLOCKED** | Project/checks found, but required tooling was unavailable |
| 3 | **UNSUPPORTED** | No supported project or check configuration found |

`optional` checks run when their tooling is available but never fail a run.

---

## Supported Stacks

The verifier auto-detects the following stacks and emits the checks shown. The
signal listed for each stack is checked **before** any tool is required to be
installed, so project type detection never depends on the local machine.

| Stack | Detection signal | Checks emitted | Fixture |
| :--- | :--- | :--- | :--- |
| Node.js (npm) | `package.json` (no lockfile) | `npm test`, `npm run lint --if-present` | `node-npm`, `node-npm-fail` |
| Node.js (pnpm) | `pnpm-lock.yaml` | `pnpm test`, `pnpm lint` | `node-pnpm`, `monorepo` |
| Node.js (yarn) | `yarn.lock` | `yarn test`, `yarn lint` | — |
| Node.js (bun) | `bun.lock` / `bun.lockb` | `bun test`, `bun run lint` | `node-bun` |
| Rust | `Cargo.toml` | `cargo test`, `cargo clippy -- -D warnings` | `rust-cargo` |
| Python | `pyproject.toml` / `requirements.txt` | `pytest`, `ruff check .` | `python-poetry`, `python-uv` |
| Python (poetry) | `poetry.lock` | `poetry run pytest`, `poetry run ruff check .` | `python-poetry` |
| Python (uv) | `uv.lock` | `uv run pytest`, `uv run ruff check .` | `python-uv` |
| Go | `go.mod` | `go test ./...`, `go vet ./...` | `go-mod` |
| Java (Maven) | `pom.xml` | `mvn test`, `mvn checkstyle:check`; `./mvnw` / `mvnw.cmd` when a wrapper is present | `java-maven`, `java-maven-wrapper` |
| Java (Gradle) | `build.gradle` / `build.gradle.kts` | `gradle test`, `gradle check`; `./gradlew` / `gradlew.bat` when a wrapper is present | `gradle-wrapper` |
| Android / Kotlin (Gradle) | root `build.gradle` / `build.gradle.kts` referencing `com.android` / `org.jetbrains.kotlin.android`, or a root `AndroidManifest.xml` | `test`, `lint`, `assembleDebug` via the Gradle wrapper or `gradle` | `android-gradle` |
| .NET | `*.sln` / `*.csproj` | `dotnet test`, `dotnet format --verify-no-changes` | `dotnet-sln-only`, `dotnet-csproj-only` |
| Nested monorepo | manifests in one level below `apps/`, `services/`, `packages/`, `modules/` | merged detection per nested sub-stack | `monorepo`, `nested-monorepo` |

Detection notes:

- **Android/Kotlin detection is basic root-project detection**: it inspects
  root `build.gradle`/`build.gradle.kts` (and a root `AndroidManifest.xml`). It
  does not yet follow Android plugins declared only in module build files,
  version-catalog aliases, or convention plugins.
- **Nested discovery is one-level**: it scans only direct children of
  `apps/`, `services/`, `packages/`, and `modules/`, and does not interpret
  pnpm/npm/Yarn workspaces, Nx, Turborepo, Cargo members, Gradle subprojects,
  Maven modules, or Bazel.
- The Gradle/Maven wrapper emitted is the platform script: `gradlew.bat` /
  `mvnw.cmd` on Windows, `./gradlew` / `./mvnw` on Linux/macOS.
- **Optional-check gating**: pnpm/yarn/bun `lint` checks are emitted only when
  `package.json` defines a `lint` script (npm keeps `--if-present`); the Python
  `ruff` check only when Ruff is configured (`[tool.ruff]`, `ruff.toml`, or
  `.ruff.toml`); `maven-lint` only when the POM references Checkstyle.

The fixture smoke harnesses (`tests/fixtures/run-fixtures.sh` and
`tests/fixtures/run-fixtures.ps1`) exercise the complete fixture list and fail
CI on any mismatch. Both the Bats and Pester suites run on all three platforms;
`run-fixtures.sh` runs on Linux/macOS and `run-fixtures.ps1` on Windows.

---

## What's Included

```
.
├── AGENTS.md                      # Canonical protocol — single source of truth
├── CLAUDE.md / GEMINI.md          # Import-only entry points
├── .aider.conf.yml                # Aider reads AGENTS.md + WORKFLOW.md
├── install.sh / install.ps1       # Non-destructive cross-platform installers
├── scripts/
│   └── build-bundle.sh            # Packages the clean adopter distribution
├── tests/
│   ├── bats/                      # Bats suites (verify.sh + install.sh)
│   ├── pester/                    # Pester suites (verify.ps1 + install.ps1)
│   └── fixtures/                  # Fixture projects + smoke harnesses
├── docs/decisions/                # This repository's ADRs
└── .agentic/
    ├── VERSION                    # Protocol version
    ├── WORKFLOW.md                # The 5-phase loop, in detail
    ├── ARCHITECTURE.md            # Fill-in template describing the host project
    ├── STATUS.md                  # Index of current project state
    ├── checks.tsv                 # Authoritative check list (auto-detect fallback)
    ├── rules/                     # Technology-agnostic standards
    ├── tasks/                     # One file per task
    ├── decisions/                 # Immutable Architecture Decision Records
    ├── templates/                 # Feature spec, bug report, refactor plan
    └── scripts/
        ├── verify.sh              # Verifier (Linux/macOS)
        └── verify.ps1             # Verifier (Windows)
```

---

## Supported Agent Tools

| Tool | How it loads the protocol |
| :--- | :--- |
| **OpenCode** | Reads `AGENTS.md` natively |
| **Claude Code** | `CLAUDE.md` imports `AGENTS.md` + `.agentic/WORKFLOW.md` |
| **Gemini CLI** | `GEMINI.md` imports `AGENTS.md` + `.agentic/WORKFLOW.md` |
| **Cursor** | Reads `AGENTS.md` directly |
| **Windsurf** | Discovers `AGENTS.md` automatically |
| **Cline / Roo Code** | Recognizes `AGENTS.md` as a rule source |
| **GitHub Copilot** | Supports `AGENTS.md` files |
| **Aider** | `.aider.conf.yml` reads `AGENTS.md` + `.agentic/WORKFLOW.md` |

Entry points contain only imports or pointers — never duplicated protocol
content. Change the protocol in **one place** (`AGENTS.md`) and every tool
stays in sync.

---

## Customization

- **Change the protocol**: edit `AGENTS.md` and `.agentic/WORKFLOW.md` — the
  entry points pick it up automatically; re-run the installer to push updates
  into adopting projects.
- **Add stack-specific rules**: drop a new file into `.agentic/rules/` and
  reference it from `AGENTS.md`.
- **Extend verification**: edit `.agentic/checks.tsv` in the adopting project;
  each line is `requirement<TAB>check-id<TAB>working-dir<TAB>executable<TAB>args...`.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to develop, test, and submit
changes. Tests run on the framework itself via the CI workflow
([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## Security

See [SECURITY.md](SECURITY.md) for the supported version policy and how to
report a vulnerability.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

[MIT](LICENSE) — use it in any project, commercial or otherwise.