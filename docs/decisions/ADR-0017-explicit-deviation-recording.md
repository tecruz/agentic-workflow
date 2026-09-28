# ADR-0017 - Explicit deviation recording (phase route, waived gates, completion protocol)

- **Date**: 2026-09-27
- **Status**: Accepted
- **Deciders**: maintainers (adopted-ideas review: `awslabs/aidlc-workflows`, `qtalen/aidlc-skills`)

## Context

The 5-phase loop (`AGENTS.md`, Section 2) requires every task to execute
DISCOVER -> CLASSIFY RISK -> PLAN -> IMPLEMENT -> VERIFY -> HANDOFF, but the
task file carried no machine-readable trace of what actually ran. Skipped
phases, waived expectations, and partial outcomes were reported only in
prose (if at all), so a reviewer could not distinguish a followed process
from an assumed one. Completion reports also had no fixed shape: tasks ended
with ad-hoc summaries whose verification claims varied in form, and
deviations discovered mid-task had no canonical home, which invited
unrecorded scope drift.

## Decision

1. **`## Phase route` records the loop as it ran.** An optional task-file
   section lists each of the six phases exactly once as
   `- <PHASE>: EXECUTED` or `- <PHASE>: SKIPPED - <rationale>` (dash
   separators `-`, en, and em dashes accepted after normalization). Both
   task validators reject malformed, duplicate, and missing entries as
   `PHASE_ROUTE_INVALID`, and reject forbidden skips as
   `PHASE_SKIP_FORBIDDEN`: `HANDOFF` may never be skipped on any profile,
   `VERIFY` may be skipped only on `prototype` tasks.

2. **`## Waived gates` records waivers with a named owner.** An optional
   section lists canonical
   `- WG-N: <what> - waived by <approver> on YYYY-MM-DD - <rationale>` rows;
   unique ids, a substantive approver, a valid ISO date, and a substantive
   rationale are `WAIVER_INVALID`. High-assurance tasks may carry no waiver
   row at all (`WAIVER_FORBIDDEN`): under that profile an expectation must
   surface as an unresolved gate (BLOCKED), never be routed around.

3. **Completion is a two-option protocol, not a free-form summary.**
   `.agentic/rules/06-completion-messages.md` requires every completed-task
   report to start with exactly `TASK-<ID>: done` or
   `TASK-<ID>: blocked - <reason>`, followed by the fixed field order
   (`files:`, `verify:`, `deviations:`, `risks:`, `commit:`), verification
   stated as `<command> -> exit <code>`, and the **no-emergent-deviation**
   rule: anything that deviated from the declared plan must be recorded in
   the task file before `done` may be reported. Like rules 01-05, this is a
   behavioral norm the tooling does not enforce.

4. **Backward compatibility by optionality.** Both sections are optional;
   task files without them validate byte-identically to the previous
   contract. The four new diagnostic codes are admitted by
   `task-validation-result-v1.schema.json`, and parity golden rows pin both
   validators to the same exit codes and messages.

## Consequences

- (+) Reviewers can audit skipped phases and waivers directly from the task
  file, and completion reports converge on one parseable shape with
  exit-code evidence.
- (+) High-assurance tasks structurally cannot launder an expectation past
  their approval gates via a waiver.
- (-) The template and both validators grow two more optional surfaces; the
  default copied task stays lean because both sections ship as template
  comment guidance and are omitted when nothing deviated.
- (-) The completion protocol and no-emergent-deviation rule are prompt-shape
  norms, not tooling; the offline eval harness checks artifact contracts,
  not message text (rules 01-05 precedent).
