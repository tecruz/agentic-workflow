# Refactor Plan

> Copy this template before any structural change. Refactors change *structure*, never *behavior*.

## Motivation
[Why this refactor is warranted now. What pain or risk does the current structure cause?]

## Scope
- **In scope**: [modules/files that will change]
- **Out of scope**: [related code that must NOT be touched]

## Behavioral Invariants
[What must remain identical after the refactor — public APIs, outputs, performance characteristics.]

- [Invariant 1]
- [Invariant 2]

## Step Plan
1. [Atomic step 1 — independently verifiable]
2. [Atomic step 2]
3. [Atomic step 3]

## Verification
- [ ] Test suite passes after **each** step (not just at the end)
- [ ] No public API changes, or all call sites updated

## Rollback Strategy
[How to revert safely if verification fails mid-refactor — e.g. one commit per step.]
