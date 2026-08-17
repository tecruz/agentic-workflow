# ADR-0007 — Extension versioning: how future protocol extensions evolve

- **Date**: 2026-08-15
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback (12).md`

## Context

The protocol has shipped six releases with a single versioning axis
(`.agentic/VERSION`) and three file categories (`managed`, `seed`, `merge`).
Future work — risk profiles, skills, structured event logs, on-demand context
modules, and behavioral evaluations — will introduce new file types, new schema
fields, and new migration requirements. Without an agreed versioning strategy
before that work begins, each feature risks inventing an incompatible approach,
making the installer unable to reason about what it manages and making upgrades
from N-1 to N unreliable.

## Decision

1. **`.agentic/VERSION` describes the distribution.** It is the protocol
   specification version — the set of schemas, file categories, and behavioral
   contracts that the installer and verifiers implement. It does not separately
   version individual file schemas; the distribution is the unit of
   compatibility.

2. **New managed files are registered in the canonical category registry.**
   Every file the installer creates, updates, or removes is classified as
   `managed`, `seed`, or `merge` and recorded in the shared registry used by
   both installers. A new extension that adds files (e.g. a risk-profile
   schema or a run-record file) must register its files before they can be
   installed.

3. **Forward compatibility by ignoring unknown fields.** When a newer
   installer writes a schema that an older installer reads, unknown top-level
   fields are ignored. The installer never rejects a file for containing
   fields it does not recognise. Missing required fields (e.g. a missing
   `schema_version` when one is expected) are reported as warnings, not hard
   failures, unless the field is essential for the operation being performed.

4. **Schema versioning is opt-in per file.** Individual schemas that have
   backward-compatibility implications may declare an optional
   `schema_version` integer and a `protocol_version` string:

   ```json
   {
     "schema_version": 1,
     "protocol_version": "1.3.0"
   }
   ```

   This is recommended for any file that may be read by multiple installer
   versions (e.g. run records, risk profiles). It is not required for simple
   configuration files.

5. **Migration guarantees: N-1 to N.** The installer guarantees migration from
   the immediately preceding release to the current one. The oldest supported
   installer can migrate to the current version through a chain of
   intermediate upgrades. There is no guarantee of migration from N-2 or older
   without first upgrading through N-1.

6. **Which new files are managed versus seed versus generated.**

   | Category | Rule | Example |
   | :--- | :--- | :--- |
   | **managed** | Framework-authored, updated by the installer, never silently overwritten by the installer when the adopter modified it | `.agentic/WORKFLOW.md`, adapter files |
   | **seed** | Framework-authored on first install, then adopter-owned; never overwritten | `.agentic/checks.tsv`, `.agentic/ARCHITECTURE.md`, task/decision files |
   | **merge** | Protocol block managed, rest preserved | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` |
   | **generated** | Produced by detection, reviewed by the adopter, promoted explicitly | `.agentic/checks.generated.tsv` |

   Risk profiles and event records will likely be `seed` (created once, then
   adopter-managed). Context modules will likely be `managed` (updated by the
   installer). Specific classifications are recorded in the ADR for each
   feature.

7. **Run records and observable data exclude secrets by design.** The
   installer and verifier never write the following into observable files
   (task logs, run records, event logs):

   - Raw environment variables
   - API keys, tokens, or credentials
   - Private agent reasoning or chain-of-thought
   - Unbounded command output (stdout/stderr is truncated to a configurable
     limit)
   - File contents from outside the project root

   This is a policy constraint, not a schema constraint: the schemas do not
   contain fields for this data, and the installer does not populate them.

8. **Unknown profile fields are ignored.** If a newer release adds fields to a
   risk profile, skill definition, or run-record schema, an older installer
   reads the file, ignores the unknown fields, and continues. This prevents
   a newer schema from breaking an older installer.

## Consequences

- Each new extension (risk profiles, skills, events, context modules) ships
  with an ADR that records its file categories, schema fields, and migration
  rules — not just its feature design.
- The installer's category registry is the single source of truth for what
  files exist and how they are handled. Adding a file without registering it
  is a bug, not a feature.
- The versioning ADR prevents "version drift" where each feature team
  invents its own schema versioning scheme.
- The N-1 migration guarantee keeps the upgrade path predictable without
  requiring indefinite backward compatibility.
- The secrets-exclusion policy is established before run records and event
  logs exist, so they are designed correctly from the start rather than
  retrofitted.
