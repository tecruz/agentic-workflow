# Universal Agentic Development Protocol

A technology-agnostic, tool-agnostic agentic workflow you can drop into **any** project. It gives every AI coding agent the same operating instructions, the same 5-phase execution loop, and the same definition of "done" — regardless of language, framework, or which agent tool you use.

- **Technology-independent**: Node, Rust, Python, Go, JVM, .NET — the protocol auto-detects how to verify your project.
- **Agent-tool-independent**: OpenCode, Claude Code, Gemini CLI, Cursor, Windsurf, Roo Code / Cline, GitHub Copilot, and Aider all read the same canonical instructions from `AGENTS.md`.

---

## Quick Start

### Install into an existing project

```bash
git clone https://github.com/<your-user>/agentic-workflow.git
cd agentic-workflow

# Linux / macOS
./install.sh /path/to/your-project

# Windows (PowerShell)
./install.ps1 -Target C:\path\to\your-project
```

The installer never overwrites existing files. Re-run with `--force` / `-Force` to update a project to a newer protocol version.

Then commit the installed files and fill in `.agentic/ARCHITECTURE.md` with your project's real architecture (or let your agent do it in its first session).

### Use as a GitHub template

Click **Use this template** when creating a new repository — the protocol ships pre-installed.

---

## How It Works

Every agent session follows the same 5-phase loop:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ 1. DISCOVER │ ──> │   2. PLAN   │ ──> │ 3. EXECUTE  │ ──> │ 4. VERIFY   │ ──> │ 5. COMMIT   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

1. **Discover** — read project context, manifests, and existing patterns before touching code.
2. **Plan** — decompose the request into atomic, verifiable steps.
3. **Execute** — minimal changes that match surrounding style, per `.agentic/rules/`.
4. **Verify** — run the project's own build/test/lint commands (or `./.agentic/scripts/verify.sh`, which auto-detects the stack). Self-heal failures until green.
5. **Commit** — update memory logs, use Conventional Commits.

Full details: [`.agentic/WORKFLOW.md`](.agentic/WORKFLOW.md). Canonical agent instructions: [`AGENTS.md`](AGENTS.md).

---

## What's Included

```
.
├── AGENTS.md                      # Canonical protocol — the single source of truth
├── CLAUDE.md                      # Claude Code entry point
├── GEMINI.md                      # Gemini CLI entry point
├── CONVENTIONS.md                 # Aider entry point
├── .cursorrules                   # Cursor (legacy format)
├── .cursor/rules/agentic-protocol.mdc   # Cursor (modern format)
├── .windsurfrules                 # Windsurf (legacy format)
├── .windsurf/rules/agentic-protocol.md  # Windsurf (modern format)
├── .clinerules                    # Cline / Roo Code entry point
├── .github/copilot-instructions.md      # GitHub Copilot entry point
├── install.sh / install.ps1       # Cross-platform installers
└── .agentic/
    ├── WORKFLOW.md                # The 5-phase loop, in detail
    ├── ARCHITECTURE.md            # Fill-in template describing the host project
    ├── rules/                     # Technology-agnostic standards
    │   ├── 01-general-principles.md
    │   ├── 02-code-quality.md
    │   ├── 03-testing-verification.md
    │   ├── 04-git-conventions.md
    │   └── 05-security-safety.md
    ├── Memory/
    │   ├── PROJECT_STATE.md       # Live task state — agents read & update this
    │   └── DECISION_LOG.md        # Architecture Decision Records (ADRs)
    ├── templates/                 # Feature spec, bug report, refactor plan
    └── scripts/
        ├── verify.sh              # Stack auto-detection: test + lint (Linux/macOS)
        └── verify.ps1             # Stack auto-detection: test + lint (Windows)
```

All tool-specific files are thin pointers to `AGENTS.md` — update the protocol in **one place** and every agent tool stays in sync.

---

## Supported Agent Tools

| Tool | How it loads the protocol |
| :--- | :--- |
| **OpenCode** | Reads `AGENTS.md` natively |
| **Claude Code** | `CLAUDE.md` → `AGENTS.md` |
| **Gemini CLI** | `GEMINI.md` → `AGENTS.md` |
| **Cursor** | `.cursor/rules/agentic-protocol.mdc` (legacy `.cursorrules` included) |
| **Windsurf** | `.windsurf/rules/agentic-protocol.md` (legacy `.windsurfrules` included) |
| **Cline / Roo Code** | `.clinerules` → `AGENTS.md` |
| **GitHub Copilot** | `.github/copilot-instructions.md` → `AGENTS.md` |
| **Aider** | `aider --read AGENTS.md --read .agentic/WORKFLOW.md` |

---

## Customization

- **Change the protocol**: edit `AGENTS.md` and `.agentic/WORKFLOW.md` — entry points pick it up automatically.
- **Add stack-specific rules**: drop a new file into `.agentic/rules/` (e.g. `06-react.md`) and reference it from `AGENTS.md` Section 3.
- **Extend verification**: edit `.agentic/scripts/verify.sh` / `verify.ps1` to add your stack's commands.

---

## License

[MIT](LICENSE) — use it in any project, commercial or otherwise.
