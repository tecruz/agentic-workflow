# TASK-037 — Post-v1.14 backlog completion (v1.15.0)

## Status

Status: done
Updated: 2026-09-11

## Risk profile

Profile: standard

## Profile rationale

Framework documentation, registry data, template, fixture, eval-corpus,
and release-bookkeeping work: one new context module (MCP tool
governance), an optional task-template section, two offline eval
scenarios, doc-table updates, and the 1.15.0 version sweep. No
authentication, payments, secrets handling, data migrations, production
infrastructure, irreversible operations, public API compatibility
commitments, privacy-regulated data, or safety-critical behavior. The
new module's minimum profile is `standard` (governance guidance, same
precedent as `dependency-changes`); no selected module or invoked skill
requires escalation. No dependencies added; no files deleted.

## Acceptance criteria

- AC-1: MCP context module ships — `.agentic/context/mcp-tool-governance/MODULE.md`
  (v1, standard) plus INDEX row, installer/bundle registration
  (install.sh, install.ps1, build-bundle.sh), install test assertions
  (Bats + Pester), and 4 validate-context fixtures with golden outcome
  tests (Bats + Pester).
- AC-2: MCP/A2A doc tables updated — README tool tables and AGENTS.md §6
  record the MCP/A2A relationship with pointers to the orchestration README.
- AC-3: Goal-condition support lands — `.agentic/templates/task.md` gains an
  optional `## Goal conditions` section (exit-0 definition of done);
  validators are untouched (unknown sections are ignored by contract).
- AC-4: Spec-pipeline eval coverage — 2 new offline scenarios
  (`mcp-tool-governance`, `spec-pipeline-chain`); corpus 17→19 with both
  eval twins 19/19; JsonContracts counts updated (17→19 docs, 15→17
  positive, 17→19 dirs).
- AC-5: Release bookkeeping — `.agentic/VERSION` 1.15.0, protocol_version
  sweep across gate paths and test expectations, CHANGELOG `[1.15.0]`,
  ROADMAP items 7–13 marked done, STATUS.md entry, ADR-0016.
- AC-6: Full local verification green (available tooling) with no new
  failures versus baseline; CI green on the merge SHA.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Fresh-install + bundle contain mcp-tool-governance as managed; install suites green | passed |
| AC-2 | README + AGENTS.md diff shows MCP/A2A rows | passed |
| AC-3 | task.md template diff; validate-task --handoff on TASK-037 VALID | passed |
| AC-4 | run-evals twins 19/19; JsonContracts counts updated | passed |
| AC-5 | Sweep check: all gate paths agree on 1.15.0; CHANGELOG/ROADMAP/STATUS/ADR-0016 present | passed |
| AC-6 | Pester suites green (417 passed / 0 failed); Bats legs deferred to CI | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task adds test fixtures, eval scenarios, installer assertions, and runs the full test/CI verification gate

## Skills

- task-decomposition v1 invoked — request broken into module, template, eval, docs, and release-bookkeeping work units before planning
- verification-triage v1 invoked — check failures triaged to root cause before repair during verification
- release-verification v1 invoked — VERSION/CHANGELOG agreement, sweep consistency, and bundle integrity confirmed before handoff

## Files changed

- .agentic/context/mcp-tool-governance/MODULE.md (new)
- .agentic/context/INDEX.md
- install.sh, install.ps1, scripts/build-bundle.sh
- tests/bats/install_test.bats, tests/pester/Install.Tests.ps1
- tests/fixtures/context-tasks/context-mcp-tool-governance-*.md (new, 4 files)
- tests/bats/validate_context_test.bats, tests/pester/ValidateContext.Tests.ps1
- README.md, AGENTS.md
- .agentic/templates/task.md
- evals/generate-scenarios.ps1, evals/scenarios/mcp-tool-governance/*, evals/scenarios/spec-pipeline-chain/* (new)
- tests/pester/JsonContracts.Tests.ps1
- docs/decisions/ADR-0016-*.md (new), docs/decisions/README.md
- CHANGELOG.md, ROADMAP.md, .agentic/VERSION, .agentic/STATUS.md
- protocol_version sweep sites (scripts, schemas, orchestration, evals, tests)

## Verification

### Baseline

- PR #26 CI green on f2784b4; Pester coordinator suites 16/16 local.

### Final

- Fresh install via install.ps1: mcp-tool-governance MODULE.md present,
  manifest `managed` row present, INDEX mentions the module.
- Bundle build: dist/agentic-workflow-1.15.0 contains the module; dist/
  removed afterwards.
- evals/run-evals.ps1 19/19; evals/run-evals.sh 19/19.
- Pester: ValidateContext+JsonContracts 100/0, Install+Coordinator 99/0,
  ValidateTask+ValidateSkills+Verify+HealthReport 218/0.
- validate-context (ps1+sh) on new fixtures: valid/none VALID, fenced INVALID.
- New scenario artifacts pass validate-task/context/skills --handoff.
- Sweep: no 1.14.0 remains in gate paths; VERSION=1.15.0.
- Bats legs unavailable locally; proven in CI.

## Remaining risks

- Bats unavailable locally (Windows); Bats legs proven in CI.
- Release tag/publication is out of scope (release workflow owns it).
- No further gaps: roadmap items 7–13 fully checked; no new ADR needed
  beyond ADR-0016 (modules/template/eval additions are evolutionary).
