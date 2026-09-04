# TASK-006: PR #10 — portable context modules and offline behavioral evaluations (v1.5.0)

## Status

Status: done
Updated: 2026-08-25

## Risk profile

Profile: standard

## Profile rationale

The change adds framework documentation artifacts (a context-module registry),
two new structural validators, an offline evaluation harness, and installer
registration for the new managed files. No authentication, payments, secrets
handling, data migration, production infrastructure, irreversible operation,
public-API compatibility commitment, privacy-regulated data, or safety-critical
behavior is implemented by this feature itself; the security-review module
describes process requirements, it does not implement security controls.
Escalation signals were reviewed; none apply. The standard profile with full
CI plus a real N-1 migration test provides adequate verification depth. The
infrastructure-change module is likewise not triggered: its Load-when trigger
is scoped to production-affecting pipeline/deployment changes, and this task's
workflow edits only run this framework repository's own test suites.

## Acceptance criteria

- AC-1: Five portable context modules exist under `.agentic/context/`, each declaring ID, version, load triggers, minimum risk profile, required context, approval gates, required evidence, and prohibited shortcuts; AGENTS.md stays compact and only instructs DISCOVER-time inspection of `.agentic/context/INDEX.md`.
- AC-2: `.agentic/templates/task.md` records selected context modules with known ID, rationale, recognized version, and a loaded confirmation, or the exact `None selected` sentinel.
- AC-3: `validate-context.sh` and `validate-context.ps1` agree semantically across shared fixtures and reject unknown, duplicate, rationale-missing, version-unsupported, profile-incompatible, and unresolved selections with stable diagnostic codes; exit codes are 0/1/2.
- AC-4: The validators emit JSON that validates against `.agentic/schemas/context-selection-v1.schema.json` using the v1.4.0 result-contract principles.
- AC-5: An offline deterministic evaluation runner executes at least eight scenarios covering expected and forbidden observable behavior without any external model, API key, or network access, and all scenarios pass.
- AC-6: Adopter bundles ship the registry, validators, and schema but exclude evaluation fixtures (`evals/`), enforced by leak gates in both build-bundle.sh and release.yml.
- AC-7: A real v1.4.0 to v1.5.0 migration test passes alongside fresh-install, update/conflict, prune/uninstall, tar+zip, and executable-bit coverage for the new files.
- AC-8: Version metadata is coherent: VERSION 1.5.0, CHANGELOG `[1.5.0]` section, protocol_version "1.5.0" constants synchronized across emitters and schemas.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Five `MODULE.md` files + `INDEX.md` written; Bats suite asserts installed files and manifest rows; AGENTS.md delta limited to a Discover sentence and compact §5.2 | passed |
| AC-2 | Template extended with canonical selection grammar; fixtures `context-valid-single/multi/none/bare-none` accepted by both validators | passed |
| AC-3 | The shared fixture corpus produces identical exit codes AND identical first-line messages from both validators (Pester parity test green); stable codes asserted in Bats/Pester; registry identity/metadata violations block as CONTEXT_REGISTRY_INVALID | passed |
| AC-4 | JsonContracts.Tests.ps1 validates emitted documents against context-selection-v1.schema.json via jsonschema for both validators (valid + invalid legs) — all four legs pass | passed |
| AC-5 | run-evals.sh and run-evals.ps1 each evaluate 8/8 scenarios correctly offline: every positive artifact passes BOTH validators in handoff mode with a schema-valid verification document, and the negative control fails on exactly FORBIDDEN_ACTIONS_ABSENT; every emitted document is checked against evaluation-result-v1.schema.json before emission; no network, no keys; CI steps added to both fast jobs | passed |
| AC-6 | build-bundle.sh copies evals nowhere and lists it as a leak; release.yml leak loop includes evals; Pester zip-leak test asserts evals absent and context files present in the extracted archive | passed |
| AC-7 | New Pester release-to-release test upgrades a real v1.4.0 bundle install to current: registry/validators/schema land as managed, adopter content preserved, conflict candidate written, installed validator passes an end-to-end selection, uninstall removes the registry but keeps seeds | passed |
| AC-8 | Sweep confirms protocol_version "1.5.0" in verify.sh/.ps1, validate-task.sh/.ps1, validate-context.sh/.ps1, and all three v1 result schemas; VERSION=1.5.0; CHANGELOG `[1.5.0]` section added | passed |

## Approval gates

- None identified

## Context modules

- None selected — framework feature development with no specialist trigger

## Skills

- None required — task predates the skills registry (v1.10.0); no reusable procedure was invoked

## Files changed

- .agentic/context/INDEX.md — module index, selection grammar, registry rules (new).
- .agentic/context/{security-review,database-migrations,dependency-changes,infrastructure-change,public-api-change}/MODULE.md — five portable modules (new).
- .agentic/scripts/validate-context.sh / validate-context.ps1 — structural selection validators with text+JSON output (new); registry identity/metadata validation, authoritative-scope fence handling, and redacted display paths hardened after review.
- .agentic/scripts/validate-handoff.sh / validate-handoff.ps1 — single public composite handoff gate running both validators in handoff mode (new).
- .agentic/schemas/context-selection-v1.schema.json — result-contract schema (new).
- .agentic/templates/task.md — Context modules selection contract documented.
- .agentic/checks.tsv — sh-syntax-validate-context, evals-sh/ps1 required checks; ps-syntax list extended.
- .agentic/WORKFLOW.md, AGENTS.md — lightweight DISCOVER-time module-selection instruction (§5.2).
- .agentic/VERSION — 1.5.0. CHANGELOG.md — `[1.5.0]` section.
- .agentic/scripts/verify.sh / verify.ps1 / validate-task.sh / validate-task.ps1 — protocol_version sweep to 1.5.0; mutually-exclusive-modes message made version-neutral.
- .agentic/schemas/verification-result-v1.schema.json, task-validation-result-v1.schema.json — protocol_version const 1.5.0.
- install.sh / install.ps1 — eleven managed-file registrations.
- scripts/build-bundle.sh — context dirs + copies, validator copies, evals leak gate.
- .github/workflows/ci.yml — shellcheck/bash -n/PSA lists extended; offline eval steps on both fast legs.
- .github/workflows/release.yml — bundle leak list includes evals.
- evals/ — schemas, eight scenario fixtures (full production-contract artifacts), cross-platform runners enforcing the real contracts, README, generator script (new).
- tests/fixtures/context-tasks/*.md — forty-two shared fixtures (new).
- tests/bats/validate_context_test.bats — 57 structural/golden cases (new).
- tests/bats/install_test.bats — fresh-install/exec-bit/uninstall coverage for the registry and validators.
- tests/pester/ValidateContext.Tests.ps1 — 41 cases incl. full fixture parity (new).
- tests/pester/JsonContracts.Tests.ps1 — four context JSON contract legs.
- tests/pester/Install.Tests.ps1 — v1.4.0→v1.5.0 migration test; bundle presence/leak assertions.
- README.md — Context Modules section, What's Included tree. docs/decisions/ADR-0010-context-modules-and-evaluations.md (new).

## Verification

### Baseline

Pre-change master (`b65a822` lineage): Fast CI and CI (Full) green on the
merge SHA on 2026-08-24; latest published release v1.4.0; no context
registry, validators, or evaluation harness existed; task template carried an
undocumented `- None selected` stub.

### Final

- Syntax: `bash -n` clean for install.sh, verify.sh, validate-task.sh,
  validate-context.sh, and validate-handoff.sh; PowerShell parse and
  PSScriptAnalyzer gates cover all five .ps1 counterparts (checks.tsv + CI).
- Behavioral evaluations: run-evals.sh exit 0 (8/8) and run-evals.ps1
  exit 0 (8/8); the negative control fails on exactly FORBIDDEN_ACTIONS_ABSENT;
  every emitted document is validated against evaluation-result-v1.schema.json
  by the runners themselves and revalidated with pinned jsonschema in CI's
  JSON-contract job.
- Composite handoff gate: validate-handoff.sh/.ps1 accept TASK-002 and this
  task file; both fast CI legs run the gate.
- Fixture smoke harnesses: run-fixtures.sh and run-fixtures.ps1 finish green
  across every golden detection fixture.
- Bundle smoke: build-bundle.sh --no-archives produces the 1.5.0 bundle with
  INDEX, five MODULE.md files, both validators, and the schema present;
  checks.tsv, tests/, docs/, evals/, CHANGELOG/README absent.
- Full Bats/Pester suites plus archive/installer lifecycle, conflict, prune,
  uninstall, leak, and migration coverage execute in CI (Full). The exact
  release candidate must pass both CI (Fast) and CI (Full) on its own HEAD SHA
  before merge/tag; local suite runs are development evidence only and are
  deliberately not pinned to a run number here so this file stays valid at any
  reviewed commit.
- Task file validated with `.agentic/scripts/validate-handoff.ps1` after
  finalization.

## Remaining risks

- Local WSL lacks `zip` and sudo, so the four archive-building Bats tests are
  proven only in CI (ubuntu installs zip); tar.gz paths were verified locally.
- The Bash runner embeds python3 for scenario parsing (documented in its
  header); environments without python3 must use run-evals.ps1. CI provides
  python3 natively.
- Module content is deliberately minimal (five modules); expanding coverage
  is additive managed-file work with no installer changes beyond registration.
