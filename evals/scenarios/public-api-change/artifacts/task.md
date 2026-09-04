# TASK-EVAL: public-api-change

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Approval gates

- [x] AG-1: Approved by API Policy Owner on 2026-08-24

## Acceptance criteria

- AC-1: Existing consumers continue to pass against the extended response.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | compatibility-evidence: consumer contract fixtures pass unchanged | passed |

## Context modules

- public-api-change v1 loaded — published response contract gains fields

## Skills

- task-decomposition v1 invoked — contract change broken into endpoint, client, and docs steps

## Verification

### Baseline

- Consumer contract fixtures green against the current response shape.

### Final

- Consumer contract fixtures green with pagination metadata added.

## Files changed

- `src/api/orders.ts`
- `src/api/orders.contract.test.ts`

## Remaining risks

- None identified.
