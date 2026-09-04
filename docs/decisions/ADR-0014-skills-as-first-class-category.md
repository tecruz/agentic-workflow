# ADR-0014 — Skills as a first-class category

- **Date**: 2026-09-04
- **Status**: Accepted
- **Deciders**: maintainers (ROADMAP.md Later/ideas, TASK-017)

## Context

The protocol ships an on-demand context-module registry (ADR-0010, v1.5.0,
extended v1.9.0): specialist review lenses loaded during DISCOVER, recorded in
the task file under `## Context modules`, and enforced by
`validate-context.sh/ps1`. Context modules answer *"which specialist review
does this task need?"*

ADR-0007 anticipated a parallel extension — *"skills"* — and reserved the
versioning policy, the managed/seed/merge registry mechanism, and the N-1
migration guarantee for it. ROADMAP.md carried it as *"Skills as a first-class
category — explore an on-demand skills registry parallel to context modules."*

No skills mechanism exists yet: reusable procedures (decompose a request,
triage a verification failure, verify a release) live only as prose in
`WORKFLOW.md` or as tribal knowledge. There is no registry to discover them,
no selection contract to record which procedure a task invoked, and no
validator to prove the record is well-formed.

## Decision

1. **Skills are procedures; context modules are lenses.** A context module
   declares review obligations for a risk area. A skill declares a repeatable
   procedure an agent invokes: when to invoke it, what inputs it needs, what
   outputs it produces, and what evidence proves it ran. The two registries are
   parallel but distinct and are validated independently.

2. **Registry layout mirrors context.** `.agentic/skills/` ships `INDEX.md`
   plus one directory per skill containing `SKILL.md`. Each `SKILL.md`
   declares exactly: ID, Version, Minimum risk profile, Invoked when, Required
   context, Approval gates, Required evidence, and Prohibited shortcuts — the
   same structural shape as `MODULE.md`, with `Invoked when` replacing
   `Load when` and the file named `SKILL.md` replacing `MODULE.md`.

3. **Three framework-native skills ship first**, covering procedures this
   repository itself exercises on every change:
   - `task-decomposition` (standard) — break a request into atomic, verifiable
     steps before planning.
   - `verification-triage` (standard) — diagnose a check failure, form a
     root-cause hypothesis, apply one fix, re-run (bounded repair loop).
   - `release-verification` (standard) — confirm VERSION/CHANGELOG/tag
     agreement, bundle integrity, and extracted-archive installability.

4. **File categories.** All registry files are **`managed`**: `INDEX.md`, the
   three `SKILL.md` files, both validators, and
   `.agentic/schemas/skill-selection-v1.schema.json`. Updates flow to adopters;
   adopter modifications produce conflict candidates per the standard
   managed-file lifecycle. No new seeds or merge entries. `evals/` remains
   framework-development material and does not ship (ADR-0010 §7 unchanged).

5. **Selection contract.** A task records one bullet per invoked skill under a
   new `## Skills` section:

        - <skill-id> v<N> invoked — <invocation rationale>

   plus the `- None required — <why no skill applies>` sentinel for work that
   invokes no procedure (e.g. bootstrapping the category itself). The
   validator enforces: known ID, no duplicates, recognized version (must equal
   the registry version), meaningful rationale, `invoked` confirmation,
   sentinel exclusivity, and the minimum-profile floor. A completed task may
   not carry placeholder rationales. Grammar, fencing/comment/blockquote
   authority-scope rules, path redaction, and stdout isolation mirror
   validate-context exactly.

6. **Validator contract mirrors v1.4.0 result principles.**
   `validate-skills.sh` / `validate-skills.ps1` exit `0` VALID / `1` INVALID /
   `2` BLOCKED, emit one diagnostic at a time from the closed set
   (`SKILLS_SECTION_MISSING`, `SKILLS_REGISTRY_MISSING`,
   `SKILLS_REGISTRY_INVALID`, `SKILLS_PROFILE_INVALID`, `SKILL_UNKNOWN`,
   `SKILL_DUPLICATE`, `SKILL_RATIONALE_MISSING`, `SKILL_VERSION_UNSUPPORTED`,
   `SKILL_PROFILE_TOO_LOW`, `SKILL_SELECTION_UNRESOLVED`,
   `TOOLING_UNAVAILABLE`), and serialize to `kind:
   "skill_validation_result"` documents validated by
   `skill-selection-v1.schema.json`. Bash JSON mode requires python3; text
   mode does not. Both implementations are held to identical classifications
   by shared fixtures. `AGENTIC_SKILLS_REGISTRY` overrides the registry
   directory in tests (mirroring `AGENTIC_CONTEXT_REGISTRY`).

7. **Handoff gate runs three legs.** `validate-handoff.sh/ps1` run
   `validate-task --handoff`, `validate-context --handoff`, and
   `validate-skills --handoff` against the same file. All three must be VALID.
   Exit codes unchanged: `0` all VALID, `1` any INVALID, `2` any BLOCKED.

8. **Migration rules.** N-1 (v1.9.0) → N (v1.10.0): the upgrade installs the
   skills registry, validators, and schema as new managed files; existing
   managed files update under the unchanged-since-install rule; adopter task
   files gain nothing automatically (the template carries `## Skills` going
   forward); prune/uninstall remove the whole `.agentic/skills/` tree when its
   files are unchanged. Historical tasks (TASK-001..016) predate `## Skills`
   and are not re-validated — the same precedent as the v1.5.0 context
   introduction.

9. **Protocol version bump.** `protocol_version` constants move to `"1.10.0"`
   across emitters and schemas as one atomic sweep, per ADR-0007's
   distribution-level versioning.

## Consequences

- Adopters gain discoverable procedures without prompt bloat; the
   always-loaded protocol grows by a short §5.3 plus a template section.
- Adding a skill means adding managed markdown files, registered in both
   installers and the bundle manifest — no code change to the validator.
- The handoff gate can no longer be satisfied without an explicit skills
   record, so skipped procedures become visible at review time.
- Skill content is data, not code: skills constrain *what the record must
   show*, never *which tool the agent runs* (profiles README principle).

## Alternatives considered

- **Reusing `## Context modules` for skills**: Rejected — lenses and
   procedures have different selection moments (DISCOVER vs PLAN/IMPLEMENT)
   and different confirmation tokens (`loaded` vs `invoked`); conflating them
   would weaken both contracts.
- **YAML-frontmatter SKILL.md (Claude-style)**: Rejected for v1 — the
   heading-based contract is already parseable by the zero-dependency
   Bash validator; frontmatter parsing would add a new dependency class.
- **Optional `## Skills` section**: Rejected — an optional record is
   unenforceable at handoff; the missing-section INVALID mirrors the v1.5.0
   context precedent.
