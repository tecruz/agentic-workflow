# TASK-FX: waived-gates-valid

## Status

Status: done
Updated: 2026-09-27

## Risk profile

Profile: standard

## Profile rationale

Standard product work; fixture for the optional `## Waived gates` section.

## Acceptance criteria

- AC-1: The scenario behaves as described.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `scenario_test.go` | Passed |
## Approval gates

- [x] AG-1: Approved by alice@example.com on 2026-09-20

## Waived gates

- WG-1: Brand-color contrast check for the settings pane — waived by bob@example.com on 2026-09-21 — pane is admin-only; tracked as issue 412
- WG-2: Legacy export-format regression suite - waived by carol@example.com on 2026-09-22 - format support was dropped in RFC 88
## Verification

### Baseline

- `go test ./...` → 10 passed, 0 failed.

### Final

- `go test ./...` → 11 passed, 0 failed.
## Files changed

- `internal/scenario/scenario.go`
## Remaining risks

- None identified.