# Universal Agentic Development Workflow

This document details the 5-Phase Agentic Development Loop required for all software tasks.

---

## The 5-Phase Loop

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ 1. DISCOVER │ ──> │   2. PLAN   │ ──> │ 3. EXECUTE  │ ──> │ 4. VERIFY   │ ──> │ 5. COMMIT   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

---

### Phase 1: Discover & Context Gathering

**Goal**: Gain complete clarity on project conventions, dependencies, structure, and request scope before changing code.

1. **Context Check**:
   - Inspect `AGENTS.md` and active memory in `.agentic/Memory/PROJECT_STATE.md`.
   - Inspect package configuration (`package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, etc.).
2. **Search First**:
   - Search existing patterns before writing new utilities.
   - Respect established naming conventions, linting rules, and directory structure.
3. **Dependency Discipline**:
   - Do NOT introduce new external libraries unless explicitly approved or strictly required.

---

### Phase 2: Plan & Decompose

**Goal**: Transform user requests into atomic, verifiable steps.

1. **Task Breakdown**:
   - Create or update `.agentic/Memory/PROJECT_STATE.md` with explicit task checkpoints.
2. **Risk Assessment**:
   - Identify potential breaking changes, data migrations, or API contract modifications.
3. **Clarification**:
   - If user requirements are ambiguous or high-risk, ask targeted questions before taking irreversible actions.

---

### Phase 3: Execute & Implement

**Goal**: Make precise, high-quality, minimal changes.

1. **Atomic Edits**:
   - Implement one logically complete unit of work at a time.
2. **Coding Standards**:
   - Follow technology-agnostic guidelines in `.agentic/rules/`.
   - Keep comments focused on intent and rationale (*why*), not mechanics (*what*).
3. **Preserve Integrity**:
   - Avoid touching unrelated files or executing scope-creep refactoring.

---

### Phase 4: Verify & Self-Heal

**Goal**: Ensure zero regressions and total functional correctness.

1. **Automated Verification**:
   - Run unit tests, integration tests, type checks, and linters.
   - Run `.agentic/scripts/verify.sh` or `.agentic/scripts/verify.ps1` if available.
2. **Self-Healing Loop**:
   - If tests or builds fail:
     a. Analyze error stack traces carefully.
     b. Formulate a root-cause hypothesis.
     c. Apply fix.
     d. Re-run verification.
     e. Repeat until green.
3. **Never Hand Off Broken Code**:
   - Never report a task complete if builds or tests fail.

---

### Phase 5: Document & Commit

**Goal**: Persist knowledge and maintain clean history.

1. **Update Memory**:
   - Mark completed tasks in `.agentic/Memory/PROJECT_STATE.md`.
   - Document key decisions in `.agentic/Memory/DECISION_LOG.md` if architectural choices were made.
2. **Git Commit**:
   - Follow Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`).
   - Keep commits focused and atomic.
