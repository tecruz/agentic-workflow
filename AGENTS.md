# AGENTS.md — Universal Agentic Development Protocol

> **Universal Standard for AI Coding Agents**  
> Compatible with OpenCode, Claude Code, Gemini CLI, Cursor, Windsurf, Roo Code / Cline, GitHub Copilot, Aider, and custom agentic frameworks.

---

## 1. Core Operating Directives

1. **Self-Verification Loop**: Never present unverified code. Always verify through building, running test suites, or running static analysis before finalizing changes.
2. **Context-First Execution**: Before modifying any codebase, analyze existing patterns, file structures, and conventions. Mimic the surrounding style exactly.
3. **Incremental & Atomic Modifications**: Make minimal, target-driven changes. Avoid scope creep, unauthorized refactoring, or collateral modifications.
4. **State & Memory Discipline**: Maintain project state in `.agentic/Memory/PROJECT_STATE.md` and log architectural decisions in `.agentic/Memory/DECISION_LOG.md`.
5. **Safety & Security First**: Never expose, commit, or log hardcoded API keys, tokens, or credentials. Always explain filesystem or environment modifications before executing.

---

## 2. Universal Agent Execution Lifecycle

All tasks must follow the 5-Phase Agentic Development Loop. Full details: `.agentic/WORKFLOW.md`.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ 1. DISCOVER │ ──> │   2. PLAN   │ ──> │ 3. EXECUTE  │ ──> │ 4. VERIFY   │ ──> │ 5. COMMIT   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

1. **Discover**: Read `AGENTS.md`, `.agentic/Memory/PROJECT_STATE.md`, and package manifests. Map existing patterns and dependencies before writing code.
2. **Plan**: Decompose the request into atomic, verifiable steps. Track them in `PROJECT_STATE.md`. Ask before destructive or ambiguous actions.
3. **Execute**: Make minimal, style-matching changes per `.agentic/rules/`. Comments explain *why*, not *what*.
4. **Verify**: Run the project's build, test, and lint commands (see Section 5, or `.agentic/scripts/verify.sh` / `verify.ps1`). Self-heal failures until green.
5. **Commit**: Update memory logs. Use Conventional Commits (`feat:`, `fix:`, `refactor:`). Keep commits atomic.

---

## 3. Technology-Agnostic Standards

Detailed guidelines are located in `.agentic/rules/`:
- **`01-general-principles.md`**: KISS, DRY, YAGNI, Single Responsibility, Defensive Design.
- **`02-code-quality.md`**: Strict typing, explicit error propagation, immutability defaults.
- **`03-testing-verification.md`**: Unit testing, integration tests, self-verification protocols.
- **`04-git-conventions.md`**: Atomic commits, Conventional Commits format, secret hygiene.
- **`05-security-safety.md`**: Input validation, secret protection, command execution bounds.

Task templates (feature specs, bug reports, refactor plans): `.agentic/templates/`.

---

## 4. Multi-Agent & Tool Interoperability

This repository uses `AGENTS.md` as the canonical source of truth. Tool-specific entry points reference it:

| Tool | Entry Point(s) |
| :--- | :--- |
| **OpenCode** | `AGENTS.md` (read natively) |
| **Claude Code** | `CLAUDE.md` |
| **Gemini CLI** | `GEMINI.md` |
| **Cursor** | `.cursor/rules/agentic-protocol.mdc` (+ legacy `.cursorrules`) |
| **Windsurf** | `.windsurf/rules/agentic-protocol.md` (+ legacy `.windsurfrules`) |
| **Cline / Roo Code** | `.clinerules` |
| **GitHub Copilot** | `.github/copilot-instructions.md` |
| **Aider** | `CONVENTIONS.md` |

Entry points contain only pointers to this file — never duplicate protocol content into them.

---

## 5. Project Command Auto-Detection Matrix

Agents should run auto-detected verification commands based on project files present:

| Project File | Package Manager / Runtime | Build / Test Command | Lint / Format Command |
| :--- | :--- | :--- | :--- |
| `package.json` | `npm` / `pnpm` / `yarn` / `bun` | `npm test` / `pnpm test` | `npm run lint` / `pnpm lint` |
| `Cargo.toml` | `cargo` | `cargo test` | `cargo clippy` / `cargo fmt` |
| `pyproject.toml` / `requirements.txt` | `pytest` / `poetry` / `uv` | `pytest` / `poetry run pytest` | `ruff check .` / `flake8` |
| `go.mod` | `go` | `go test ./...` | `go vet ./...` / `golangci-lint run` |
| `pom.xml` / `build.gradle` | `maven` / `gradle` | `mvn test` / `./gradlew test` | `mvn checkstyle:check` / `./gradlew check` |
| `*.csproj` / `*.sln` | `dotnet` | `dotnet test` | `dotnet format --verify-no-changes` |

The same detection logic is implemented in `.agentic/scripts/verify.sh` and `verify.ps1`.
