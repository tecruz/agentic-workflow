# ADR-0009 — Machine-Readable Result Contracts

## Status

Accepted (v1.4.0)

## Context

Adopting CI systems, automated agents, dashboards, and evaluation harnesses currently rely on parsing human-readable text and exit codes from project verifiers (`verify.sh` / `verify.ps1`) and task validators (`validate-task.sh` / `validate-task.ps1`). This fragile integration boundary risks breaking on formatting changes and lacks structured error classification.

Anticipating extension versioning (ADR-0007), we need stable, versioned JSON result contracts with strict redaction policies, clean stdout handling, and backward-compatible text output.

## Decision

1. **JSON Output Modes**:
   - Project verifiers accept `--format json` (Bash) and `-Format Json` (PowerShell).
   - Task validators accept `--format json` (Bash) and `-Format Json` (PowerShell).
   - Text remains the default output format. Exit codes and text output remain fully backward-compatible.

2. **Managed JSON Schemas**:
   - Introduced `.agentic/schemas/verification-result-v1.schema.json` and `.agentic/schemas/task-validation-result-v1.schema.json`.
   - Registered as framework-managed files in installers, release bundles, and manifest categories.

3. **Redaction & Security Policy**:
   - Exclude raw command arguments, complete command lines, stdout/stderr, environment variables, absolute user-home paths, tokens, credentials, source files, and private reasoning from observable JSON result contracts.

4. **Stdout Isolation**:
   - In JSON mode, stdout contains exclusively one valid JSON document. All diagnostic progress, child process output, and ANSI sequences are emitted to stderr.

5. **Stable Diagnostic Codes**:
   - Task validation JSON includes structured error diagnostics with stable machine-readable error codes (e.g., `TASK_FILE_NOT_FOUND`, `PROFILE_UNKNOWN`, `STATUS_INVALID`, `STATUS_NOT_DONE`, `APPROVAL_UNRESOLVED`, etc.).

6. **Deferred Persistent Logs**:
   - Persistent run logs and trajectory event files are deferred to subsequent protocol extensions to maintain scope discipline.

## Consequences

- CI systems and external harnesses can reliably consume machine-readable verification and task validation results.
- Strict stdout separation ensures JSON documents are never contaminated by tool warnings or progress bars.
- Strict redaction protects secrets and environment details from leaking into observable outputs.

## Amendment (v1.4.0 review response)

Decision item 6 originally deferred persistent logs and trajectory event files.
During the v1.4.0 implementation cycle this partially changed: an opt-in JSONL
event stream (`verify.sh --events <path>` / `verify.ps1 -Events <path>`) shipped
in v1.4.0, governed by `.agentic/schemas/verification-events-v1.schema.json`.
What remains deferred: persistent run logs and trajectory recording beyond the
single-run event stream.

Amended decisions:

1. **Result/exit-code invariants are schema-enforced**: every JSON document
   pairs its `result` with the ADR-0002 state-model exit code (`PASS`=0,
   `FAIL`=1, `BLOCKED`=2, `UNSUPPORTED`=3 for verifiers; `VALID`=0, `INVALID`=1,
   `BLOCKED`=2 for task validators). These pairings, plus
   diagnostics-present-for-failure rules, are encoded as draft-07 `if/then`
   invariants inside each schema, so conforming documents cannot disagree with
   the state model.

2. **Diagnostic codes are closed-set and schema-enumerated**: the authoritative
   diagnostic code list lives in the `code` enum of
   `.agentic/schemas/task-validation-result-v1.schema.json`; both validator
   implementations emit only these codes at every failure site (verified
   cross-language by the fixture parity suite).

3. **Event-stream policy**:
   - The destination must be a relative path under `.agentic/runs/`
     (git-ignored); absolute paths and traversal outside the runs directory are
     rejected after lexical and physical containment checks.
   - The stream file is created atomically (unpredictable scratch name plus
     rename) and only after argument parsing and project-contract validation
     succeed; contract failures therefore never leave a truncated or
     unterminated stream behind.
   - Existing event files are refused unless `--events-force` /
     `-EventsForce` is given.
   - Each run emits exactly one terminal `verification_completed` event as the
     final line, pairing `result` with the verifier exit code; single-event
     pairing is schema-enforced, and ordering/single-terminal coverage lives in
     the Pester and fixture suites (JSON Schema cannot express cross-item
     ordering).
   - Events carry check identifiers, statuses, durations, and redacted
     working-directory labels only — never command lines, arguments, child
     output, environment details, or absolute user paths.

4. **Task-validator JSON mode requires Python 3**: the Bash validator's
   `--format json` mode needs `python3` and fails fast with a clear error when
   it is absent; text mode has no such dependency. Serializer failures are
   propagated as nonzero exits rather than emitting empty or malformed
   documents.
