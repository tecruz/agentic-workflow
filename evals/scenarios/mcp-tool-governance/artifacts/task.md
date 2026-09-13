# TASK-EVAL: mcp-tool-governance

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Approval gates

- [x] AG-1: Approved by MCP Review on 2026-08-24

## Acceptance criteria

- AC-1: The inspector exposes only read-only tools within the scoped schema.
- AC-2: Widening any tool scope requires a new approval record.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | tool-scope-manifest: exposed tools listed with least-privilege bounds | passed |
| AC-2 | least-privilege-audit: audit confirms no write-capable tools | passed |

## Context modules

- mcp-tool-governance v1 loaded — read-only database inspector scoped to least privilege

## Skills

- verification-triage v1 invoked — scope manifest triaged before merge

## Verification

### Baseline

- No MCP database inspector exists; inspection runs against a shared credential.

### Final

- Inspector serves read-only tools under the scoped manifest; audit clean.

## Files changed

- `mcp/servers/db-inspector.json`

## Remaining risks

- None identified.
