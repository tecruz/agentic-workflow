# TASK-000 — Post-install bootstrap: architecture record and checks contract

## Status

Status: planned
Updated: 2026-09-25

> Seeded by the agentic-workflow installer on first install. Completing this
> task replaces the manual post-install steps: the project ends up with a
> filled-in (or pointed) architecture record and an authoritative checks
> contract. If your project already satisfied both at install time, verify and
> close this task with that evidence instead of redoing the work.

## Risk profile

Profile: standard

## Profile rationale

Documentation and verification-contract setup for a freshly adopted project.
No authentication, payments, secrets, data migrations, production
infrastructure, irreversible operations, public API compatibility, privacy,
or safety-critical behavior.

## Acceptance criteria

- AC-1: `.agentic/ARCHITECTURE.md` no longer carries the seeded template's
  bracketed placeholders: it either describes this project's real architecture
  or is a short pointer to the project's canonical architecture document
  (pointers, never duplicated content).
- AC-2: `.agentic/checks.tsv` defines this project's real checks, and
  `.agentic/scripts/verify.sh` (Linux/macOS) or `.agentic/scripts/verify.ps1`
  (Windows, PowerShell 7+) exits `0` (PASS) or `2` (BLOCKED with the missing
  tooling named) when run from the project root.
- AC-3: The CI decision is recorded in this task's handoff: either a CI
  workflow step that runs the verifier was added, or CI verification was
  explicitly declined with a rationale.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Diff summary of `.agentic/ARCHITECTURE.md` versus the seeded file | Pending |
| AC-2 | Verifier command line, exit code, and result from the project root | Pending |
| AC-3 | CI workflow path added, or the recorded decline rationale | Pending |

## How to complete this task

1. Explore the repository, then fill in `.agentic/ARCHITECTURE.md` with the
   real architecture (stack, layout, modules, data flow). If the project
   already documents its architecture somewhere else, replace the seeded file
   with a short pointer to that canonical document instead of duplicating it.
2. If `.agentic/checks.tsv` is still the commented template, generate a
   candidate with `.agentic/scripts/verify.sh --detect-checks` (Linux/macOS)
   or `.agentic/scripts/verify.ps1 -DetectChecks` (Windows), review and edit
   `.agentic/checks.generated.tsv` until it matches the project's real
   definition of done, then re-run the installer with
   `--accept-detected-checks` / `-AcceptDetectedChecks` to validate and
   promote the exact reviewed file (never a fresh detection).
3. Run the verifier from the project root and repair any failures with at
   most three evidence-based cycles; record the final command, exit code,
   and result.
4. Decide on CI: add a workflow step that calls the verifier, or record why
   this project skips CI verification.
5. Mark this task `done` under `## Status`, add a one-line entry to
   `.agentic/STATUS.md`, and validate with
   `.agentic/scripts/validate-handoff.sh` / `validate-handoff.ps1`.

## Approval gates

- None identified

## Context modules

- None selected

## Skills

- None required

## Files changed

- [to be filled in when completing this task]

## Verification

### Baseline

- Post-install state: `.agentic/ARCHITECTURE.md` is the seeded template (or a
  pointer) and `.agentic/checks.tsv` is the commented template — until this
  task replaces both with project-owned content.

### Final

[to be filled in when completing this task]

## Remaining risks

- [to be filled in when completing this task]
