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
