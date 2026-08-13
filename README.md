# Universal Agentic Development Protocol

A technology-agnostic, tool-agnostic agentic workflow you can drop into **any**
project. It gives every AI coding agent the same operating instructions, the
same 5-phase execution loop, and the same definition of "done" — regardless of
language, framework, or which agent tool you use.

- **Technology-independent**: Node, Rust, Python, Go, JVM, .NET — the protocol
  auto-detects how to verify your project.
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
bootstrap. Run the installer with `--generate-checks` to create
`.agentic/checks.tsv` from the detected stack, then edit it to match your
project's real definition of done.

### Use as a GitHub template

Click **Use this template** when creating a new repository — the protocol
ships pre-installed.

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

## What's Included

```
.
├── AGENTS.md                      # Canonical protocol — single source of truth
├── CLAUDE.md / GEMINI.md          # Import-only entry points
├── .aider.conf.yml                # Aider reads AGENTS.md + WORKFLOW.md
├── install.sh / install.ps1       # Non-destructive cross-platform installers
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