# ADR-0008 — Risk profiles and evidence contracts

- **Date**: 2026-08-18
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback (16).md`

## Context

Tasks varied wildly in how much evidence they carried. A one-line typo fix and a
database migration were treated identically by the workflow: the same template,
the same handoff expectations, and no structural way to know which evidence a
task owed. Reviewers could not tell at a glance whether a completed task had the
rigor its risk warranted, and agents had no deterministic, tool-independent
definition of "enough evidence" for a given task.

The protocol needed a way to classify tasks by risk and to make the required
evidence, verification depth, handoff contents, and approval gates depend on
that classification — without coupling to any particular model, agent, or CI
system.

## Decision

1. **Risk profiles live in `.agentic/profiles/`.** Three profiles are defined:
   - **`prototype`** — experiments, spikes, and disposable prototypes only;
     production readiness must be stated as *not established*.
   - **`standard`** — the default for ordinary product and maintenance work.
   - **`high-assurance`** — authentication, payments, secrets, data migrations,
     production infrastructure, irreversible operations, public API
     compatibility, privacy, and safety-critical behavior.

2. **The default is `standard`, escalation is automatic, downgrades are never
   silent.** Agents escalate to `high-assurance` when escalation signals apply.
   `prototype` is used only when the user explicitly requests an experiment
   with no production impact. A user-requested lower profile never overrides
   mandatory safety or approval constraints. Mixed-risk tasks use the highest
   applicable profile unless split into separately-classified tasks.

3. **Profiles are evidence contracts, not check selectors.** A profile declares
   which evidence a task must produce (acceptance criteria, baseline and final
   verification, changed files, remaining risks for `standard`; explicit
   requirements, risk analysis, requirement-to-evidence matrix, negative-path
   and integration tests, recovery plan, approval records, independent review
   for `high-assurance`). Profiles never change which checks run —
   `.agentic/checks.tsv` remains the authoritative definition of done.

4. **The task template is risk-aware.** `.agentic/templates/task.md` carries a
   `Profile:` declaration, a profile-rationale section, and the required
   evidence sections. Adopter task files in `.agentic/tasks/` are never
   overwritten by the installer.

5. **A deterministic, cross-platform task validator enforces the structural
   contract.** `.agentic/scripts/validate-task.sh` / `validate-task.ps1` check
   only structural facts: a recognized profile, the required sections for that
   profile, `AC-N` acceptance-criteria identifiers, evidence-table entries, no
   `Pending` evidence on a task marked complete, recorded approvals before
   completion, and the prototype production-readiness warning. The validators
   never judge whether prose is intellectually sufficient — that belongs to
   human or behavioral evaluation.

   Exit codes: `0` VALID, `1` INVALID, `2` BLOCKED (missing evidence or
   approval on a completed task). The Bash and PowerShell implementations are
   held to identical classifications by a parity test over shared fixtures.

6. **Profile and validator files are `managed`.** Per ADR-0007's category
   registry, the profiles, the task template, and the validator scripts are
   registered as `managed` files in both installers: updated on install when
   unchanged, `.new` conflict candidates when the adopter modified them, and
   removed on uninstall. Adopter-authored task files are never touched.

7. **Profiles are Markdown, not a policy engine.** The evidence contracts are
   documented in Markdown with YAML-style example blocks for readability. There
   is no separate YAML schema, no remote approval service, and no
   model-generated risk classification.

## Consequences

- Every task now declares a profile and carries the evidence that profile
  requires; a completed task with missing evidence or approvals is structurally
  blocked, not silently accepted.
- Reviewers and downstream agents can validate a task file's contract
  deterministically with one command, on any platform.
- The lifecycle gains a risk-classification step
  (`DISCOVER → CLASSIFY RISK → PLAN → IMPLEMENT → VERIFY → HANDOFF`).
- ADR-0007's tentative suggestion that profiles "will likely be seed" is
  superseded for the profiles themselves: they are `managed` so updates reach
  adopters on install. Adopter task files remain seed-like (created by the
  adopter, never overwritten).
- Higher-assurance tasks cost more (risk analysis, approvals, independent
  review), which is the intended trade-off for their blast radius.
- The validator is deliberately structural; it is not a substitute for human or
  behavioral review of whether the evidence is actually convincing.
