# TASK-031 — README adoption-focused improvements

## Status

Status: done
Updated: 2026-09-09

## Risk profile

Profile: standard

## Profile rationale

Documentation-only change to the development repository's README — no
authentication, payments, secrets handling, data migration, production
infrastructure, irreversible operation, public-API compatibility
commitment, privacy-regulated data, or safety-critical behavior.

## Acceptance criteria

- AC-1: A table of contents links every top-level section.
- AC-2: Quick Start leads with a clear adoption path: install → what
  happens after install (commit, ARCHITECTURE.md, checks contract,
  verifier) → what to expect from the agent's first task → installer
  lifecycle detail moved into a reference subsection.
- AC-3: The stale bundle version in the Distribution bundle example is
  replaced with a `<version>` placeholder plus a note that the version
  is stamped from `.agentic/VERSION`.
- AC-4: A FAQ section answers adoption questions (partial adoption,
  unsupported stacks, CI, tool support, why-not-your-own-AGENTS.md,
  licensing).
- AC-5: The pre-existing broken `#file-ownership` anchor is removed; all
  remaining internal anchors resolve.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `## Contents` with 18 entries; anchor-check script: 24 links, 0 broken | passed |
| AC-2 | New `### What happens after install` and `### Your first task` sections; lifecycle bullets moved under `### Installer lifecycle reference` | passed |
| AC-3 | `dist/agentic-workflow-<version>/install.sh` + VERSION note in Distribution bundle | passed |
| AC-4 | `## FAQ` with six adoption questions before Contributing | passed |
| AC-5 | anchor-check script output: broken: none | passed |

## Approval gates

- None identified

## Context modules

- None selected — documentation edit does not trigger any specialist module

## Skills

- None required — prose restructuring, no procedural work

## Files changed

- README.md — TOC, reworked Quick Start, bundle-version fix, FAQ, anchor fix
- .agentic/tasks/TASK-031-readme-adoption-improvements.md (new)

## Verification

### Baseline

README was reference-complete but adoption-weak: no table of contents,
installer internals front-loaded before first-run guidance, a stale
`1.4.0` bundle example, a broken `#file-ownership` anchor, and no
answers to first-adopter questions.

### Final

README now opens with a Contents table; Quick Start walks an adopter
through install → post-install setup → first task expectations, with
lifecycle detail kept in a reference subsection; the bundle example uses
a version placeholder; a six-question FAQ covers the common adoption
objections. Anchor check: 38 headings, 24 links, 0 broken. No code,
behavior, or installer changes.

## Remaining risks

- None identified. Bundle tests only assert the dev README is excluded
  from the distribution; no test asserts README content.
