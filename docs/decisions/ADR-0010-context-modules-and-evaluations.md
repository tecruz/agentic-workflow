# ADR-0010 — Portable context modules and offline behavioral evaluations

- **Date**: 2026-08-24
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback (14).md` (PR #10 direction)

## Context

The protocol has deterministic verification (v1.2.x), risk profiles and
evidence contracts (v1.3.0), and versioned machine-readable results with
observable events (v1.4.0). The remaining gap before any orchestration work is
context engineering: agents currently receive all specialist knowledge through
the always-loaded `AGENTS.md`, which cannot scale and contradicts the
portable-skills guidance — specialist context should be loaded on demand,
only when a task triggers it.

ADR-0007 anticipated this extension: it reserved the versioning policy, the
managed/seed/merge registry mechanism, and predicted that "context modules
will likely be `managed`". This ADR records the concrete decisions.

## Decision

1. **The static protocol stays compact.** `AGENTS.md` gains only a short
   §5.2 instructing DISCOVER-time inspection of `.agentic/context/INDEX.md`
   and recording of selections in the task file. No module content ever loads
   into every session.

2. **Five modules ship first**, covering cross-cutting risks that generic
   stack detection handles poorly: `security-review`,
   `database-migrations`, `dependency-changes`, `infrastructure-change`,
   and `public-api-change`. Each `MODULE.md` declares: ID, Version,
   Load-when triggers, Minimum risk profile, Required context, Approval
   gates, Required evidence, and Prohibited shortcuts.

3. **File categories.** All registry files are **`managed`**: INDEX.md, the
   five `MODULE.md` files, both validators, and
   `.agentic/schemas/context-selection-v1.schema.json`. Updates flow to
   adopters; adopter modifications produce conflict candidates per the
   standard managed-file lifecycle. No new seeds or merge entries.

4. **Selection contract.** A task records one bullet per selected module:

       - <module-id> v<version> loaded — <selection rationale>

   plus the `- None selected` sentinel for untriggered work. The validator
   enforces: known ID, no duplicates, recognized version (must equal the
   registry version), meaningful rationale, loaded confirmation, sentinel
   exclusivity, and the minimum-profile floor. A completed task may not carry
   placeholder rationales.

5. **Validator contract mirrors v1.4.0 result principles.**
   `validate-context.sh` / `validate-context.ps1` exit `0` VALID / `1`
   INVALID / `2` BLOCKED, emit one diagnostic at a time from the closed set
   (`CONTEXT_SECTION_MISSING`, `CONTEXT_REGISTRY_MISSING`, `MODULE_UNKNOWN`,
   `MODULE_DUPLICATE`, `MODULE_RATIONALE_MISSING`,
   `MODULE_VERSION_UNSUPPORTED`, `MODULE_PROFILE_TOO_LOW`,
   `MODULE_SELECTION_UNRESOLVED`), and serialize to
   `kind: "context_validation_result"` documents validated by
   `context-selection-v1.schema.json`. Bash JSON mode requires python3;
   text mode does not. Both implementations are held to identical
   classifications by shared fixtures.

6. **Behavioral evaluations are offline and deterministic.** `evals/`
   defines a scenario schema (v1) and an evaluation-result schema (v1). The
   runners evaluate saved observable artifacts only — final task file,
   selected modules, risk profile, approvals, verification results, changed
   paths — never hidden reasoning. Eight scenarios cover the required
   behaviors; negative-control scenarios declare
   `"fixture_expected_result": "FAIL"` so the harness proves it detects
   forbidden behavior (for example a recorded `weaken-security-test` action)
   rather than trivially passing everything. No scenario calls a model, needs
   an API key, or touches the network. Live-model benchmarking may later plug
   into the same scenario schema without becoming a merge gate.

7. **Evaluations do not ship to adopters.** `evals/` is framework-development
   material: `build-bundle.sh` copies it nowhere and lists it as a leak; the
   release workflow's bundle gate rejects it identically. The registry,
   validators, and schema do ship.

8. **Migration rules.** N-1 (v1.4.0) → N (v1.5.0): the upgrade installs the
   registry, validators, and schema as new managed files; existing managed
   files update under the unchanged-since-install rule; adopter task files
   gain nothing automatically (the template carries the section going
   forward); prune/uninstall remove the whole `.agentic/context/` tree when
   its files are unchanged. Verified by a release-to-release test from tag
   `v1.4.0`.

9. **Protocol version bump.** `protocol_version` constants move to `"1.5.0"`
   across emitters and schemas as one atomic sweep, per ADR-0007's
   distribution-level versioning.

## Consequences

- Adopters gain specialist enforcement without prompt bloat; the always-loaded
  protocol grows by ~10 lines.
- Module content is data, not code: expanding coverage means adding managed
  markdown files, registered in both installers and the bundle manifest.
- The evaluation corpus lives beside the framework it tests, so scenario
  additions ride the same review path as framework changes.
- Orchestration work (PR #11) can now consume profiles (v1.3.0), JSON results
  and events (v1.4.0), and context modules with behavioral evaluations
  (v1.5.0) — the ordering the feedback review requires before any
  multi-agent execution.
