# TASK-034: CI retry hardening

## Status

Status: done
Updated: 2026-09-10

## Risk profile

Profile: standard

## Profile rationale

Standard profile for CI hardening. No secrets, auth, payments, or irreversible operations.

## Approval gates

- [x] AG-1: Approved by maintainers on 2026-09-10

## Acceptance criteria

- AC-1: All Install-CiModule calls in ci.yml and ci-full.yml include bounded retry (3 attempts, backoff).
- AC-2: Transient 403 errors from PSGallery are caught and retried instead of failing the workflow.
- AC-3: Workflow YAML remains valid after the change.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | ci-pipeline-comparison: all 5 Install-CiModule call sites have retry logic | passed |
| AC-2 | transient-403-coverage: retry catches 403 and retries with backoff | passed |
| AC-3 | yaml-validation: ci.yml and ci-full.yml parse without error | passed |

## Context modules

- None selected — CI hardening is a repo-maintenance change with no specialist context needed.

## Skills

- None required — workflow edits are mechanical and follow existing conventions.

## Verification

### Baseline

- Transient 403 from PSGallery during v1.14.0 release commit caused a full CI rerun.

### Final

- All 5 Install-CiModule call sites have bounded retry (3 attempts, 2s backoff, exponential). CI validated.

## Files changed

- `.github/workflows/ci.yml`
- `.github/workflows/ci-full.yml`

## Remaining risks

- None identified.
