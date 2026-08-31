# TASK-013: Draft ROADMAP.md

## Status

Status: done
Updated: 2026-08-30

## Risk profile

Profile: standard

## Profile rationale

Documentation-only change: authoring a forward-looking `ROADMAP.md`. No code, runtime behavior, installer, verifier, or CI configuration is affected. No authentication, payments, secrets, data migrations, production infrastructure, or safety-critical behavior is touched, so no escalation signals apply.

## Acceptance criteria

- AC-1: A new `ROADMAP.md` exists at the repository root.
- AC-2: The roadmap states the current version and grounds each proposed item in an existing source of truth (README detection notes, ADR-0007, ADR-0011, the context-module registry).
- AC-3: The roadmap is organized into priority tiers with a "How items land" process section aligned to the project's parity/registration/versioning rules.
- AC-4: The roadmap is not speculative beyond what the project itself documents as gaps (monorepo/workspace detection and Android/Kotlin detection depth are the primary cited gaps).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `ROADMAP.md` present at repo root | Passed |
| AC-2 | Content references README *Supported Stacks → Detection notes*, ADR-0007, ADR-0011, `.agentic/context/INDEX.md` | Passed |
| AC-3 | Section order: Current state → Guiding constraints → Near-term → Medium-term → Later → How items land | Passed |
| AC-4 | Near-term tiers cite only the documented monorepo/workspace and Android/Kotlin gaps | Passed |

## Approval gates

- None identified

## Context modules

- None selected — documentation-only change; no module's *Load when* triggers match.

## Files changed

- ROADMAP.md — new file (forward-looking plan)

## Verification

### Baseline

- No `ROADMAP.md` existed at the repository root (`git status` clean before change, v1.6.1 on `master`).

### Final

- `ROADMAP.md` created and reviewed; references resolve against existing files (README detection notes, ADR-0007/0011, context INDEX).
- `git status` shows only the new `ROADMAP.md` as untracked; no tracked files modified.

## Remaining risks

- Roadmap priorities are intent only and may change with adopter feedback; each landed item still requires its own ADR, changes, and release workflow (as documented in "How items land").
- The two near-term detection gaps (monorepo/workspace detection, Android/Kotlin depth) remain unimplemented; the roadmap only plans them.
- No commit has been made; the file is uncommitted in the working tree.