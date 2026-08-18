# Risk Profiles

Every task declares a **risk profile** that determines how much process the
work requires. The profile decides the required evidence contract, the
verification depth, the handoff contents, and which approval gates apply.

Risk profiles answer *"how much rigor does this task need?"* — not *"which
model or tool does this task use?"*. Agentic engineering is determined by
intent specification, verification rigor, and risk, not by the particular
coding tool.

## The three profiles

| Profile | Intended for |
| :--- | :--- |
| [`prototype`](prototype.md) | Experiments, spikes, disposable prototypes, internal demonstrations |
| [`standard`](standard.md) | The default for ordinary product and maintenance work |
| [`high-assurance`](high-assurance.md) | Authentication, authorization, payments, data migrations, cryptography, production infrastructure, privacy-sensitive code, healthcare, and other high-impact changes |

## Default behavior

- The default profile is **`standard`**.
- Agents may **escalate** automatically when escalation signals apply.
- Agents **must not silently downgrade**. Any downgrade must be explicit and
  user-requested, and it never overrides mandatory safety or approval
  constraints.
- Mixed-risk tasks use the **highest applicable profile** unless the work is
  split into separately-classified tasks.

## Escalation signals

Escalate from `standard` to `high-assurance` when the task affects:

- Authentication or authorization
- Payments or financial calculations
- Secrets, credentials, or cryptography
- Database schemas or destructive migrations
- User privacy or regulated information
- Production infrastructure or deployment
- Irreversible data operations
- Public API compatibility
- Safety-critical or healthcare behavior

Use `prototype` only when:

- The user explicitly requests an experiment, spike, or disposable prototype.
- No production or persistent system is affected.
- The handoff clearly states that production readiness was **not** established.

## Evidence contracts

Each profile documents what evidence is required — not which specific tool must
produce it. The task template turns the profile's evidence contract into a
per-task table:

```text
profile: standard
required_evidence:
  - acceptance_criteria
  - baseline_verification
  - final_verification
  - changed_files
  - remaining_risks
```

High-assurance tasks require a deeper contract:

```text
profile: high-assurance
required_evidence:
  - explicit_requirements
  - risk_analysis
  - requirement_evidence_matrix
  - negative_path_tests
  - integration_tests
  - recovery_plan
  - approval_records
  - independent_review
  - final_verification
```

## Task status

Every task file declares exactly one `Status:` under a `## Status` section,
plus an `Updated: YYYY-MM-DD` field. The status enum is:

- `planned` — defined and queued.
- `in-progress` — implementation started, evidence may be `Pending`.
- `blocked` — work paused on a blocker.
- `done` — verification evidence exists and nothing required is unresolved.

`Status: done` requires every required-evidence row to be `passed`,
`satisfied`, or `n/a` and every approval gate to be checked. The
`--handoff` / `-Handoff` flag enforces the *handoff* gate: validation then
requires `Status: done` (run it immediately before handing off a task).

## Evidence results

Evidence rows use one of the following result tokens:

- **resolved**: `passed`, `satisfied`, `n/a`
- **unresolved**: `pending`, `partial`, `blocked`, `missing`, `not-run`

`n/a` is resolved only when the evidence description itself states an `n/a`
rationale. A task marked `done` with any unresolved evidence or unchecked
approval gate is **BLOCKED** (exit `2`), not INVALID.

## Approval gates

Structured approval gates are recorded as:

```text
- [x] AG-1: Approved by <approver> on YYYY-MM-DD
```

Prose such as "Approved by Alice" or "Not approved" is not a gate. Negated
statements never count as approval. `None identified` is permitted only for
non-high-assurance profiles; high-assurance tasks must declare explicit
`AG-N` gates.

## Validation

`.agentic/scripts/validate-task.sh` / `validate-task.ps1` check a task file's
**structural** contract only:

- Exactly one recognized profile and exactly one valid `Status:` are declared.
- Required sections exist for that profile; `### Baseline`/`### Final` must
  live inside `## Verification`.
- Acceptance criteria and high-assurance requirements carry identifiers
  (`AC-N`, `R-N`), are unique, and are mapped exactly to the required
  evidence / requirement-to-evidence tables.
- A task marked complete has no unresolved required evidence and no unchecked
  approval gate.
- Prototype tasks declare `Production readiness: not established` and
  `No production deployment or irreversible operation: confirmed` in their
  `## Handoff` section.

The validator never judges whether the prose is intellectually sufficient.
That belongs to human or behavioral evaluation.

- Exit `0` = VALID, `1` = INVALID, `2` = BLOCKED (evidence or approval missing
  on a completed task, or `--handoff` on a task that is not `done`).

## Profiles vs. project verification

Profile validation is **not** a replacement for code verification:

- `.agentic/checks.tsv` is the project's authoritative definition of *done*.
- Profile validation governs how much *process evidence* a task must carry.
- Profile selection never changes which checks run; it changes which evidence
  a task must produce and which approvals must be recorded.

See also: `.agentic/WORKFLOW.md` for the risk-classification lifecycle and
`.agentic/templates/task.md` for the task template that declares a profile.