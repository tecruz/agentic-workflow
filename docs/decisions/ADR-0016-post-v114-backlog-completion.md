# ADR-0016 — Post-v1.14 trend-driven backlog completion (v1.15.0)

- **Date**: 2026-09-11
- **Status**: Accepted
- **Deciders**: maintainers (ROADMAP.md post-v1.14 backlog items 7–13)

## Context

ROADMAP.md recorded a post-v1.14 trend-driven backlog (items 7–13) as
uncommitted candidates. PR #26 implemented the committed core of all
seven items (sandboxing, review stage, trace context, hooks, MCP/A2A
guidance, spec pipeline templates, memory lifecycle) with Bash+PowerShell
parity. Four sub-items remained unchecked: an MCP-governed tool-access
module, README/AGENTS.md tool-table updates, verifiable goal-condition
support, and eval coverage for the spec pipeline. The release process
also required closing out: VERSION sweep, CHANGELOG entry, and ROADMAP
status.

## Decision

1. **MCP tool governance ships as a context module, not an adapter.**
   `mcp-tool-governance` (v1, standard) records least-privilege scoping,
   approval, logging, and trace-propagation guidance for MCP server work,
   following the ADR-0010 module contract and the TASK-016 registration
   precedent (installers, bundle, install tests, per-module fixtures).
   No new validator or schema is introduced: the module is evolutionary
   registry data, so no protocol-breaking change results.

2. **Goal conditions are a validated, executable template section.**
   `## Goal conditions` in `task.md` states the exit-0 definition of
   done, one bullet per machine-checkable end state. Both task
   validators enforce the canonical `- Exit 0 when: <command>` form
   (reusing the in-schema `CRITERION_INVALID` code, so no schema change
   ships), and a new opt-in `--run-goals` / `-RunGoals` mode executes
   each command in the working directory and requires exit 0. Unknown
   sections remain ignored by contract, so existing task files validate
   unchanged.

3. **Spec-pipeline coverage is behavioral, not structural.** The eval
   harness classifies task files; it cannot verify cross-file SPEC →
   PLAN → TASKS linkage without new check types. Coverage therefore
   consists of a `spec-pipeline-chain` scenario whose artifact carries a
   `## Goal conditions` section through all three production validators,
   proving the template extension is contract-safe end to end.

4. **Version 1.15.0.** New registry content, template surface, and eval
   corpus justify a minor bump. `protocol_version` sweeps to 1.15.0
   across the CI gate paths and test expectations; no schema shape
   changes ship (only the version const), so existing consumers upgrade
   without migration beyond the standard N-1 installer path.

## Consequences

- All 14 context modules have registry entries, installer coverage,
  fixtures, and eval scenarios.
- The eval corpus grows 17→19 scenarios; both twins classify 19/19.
- The post-v1.14 backlog is fully checked off; ROADMAP.md records the
  completed state and v1.15.0 becomes the current version.
- Tagging and publication remain owned by the release workflow, not
  this change.
