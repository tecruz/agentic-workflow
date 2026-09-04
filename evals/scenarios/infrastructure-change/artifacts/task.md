# TASK-EVAL: infrastructure-change

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: high-assurance

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Requirements

- R-1: The resize applies without unplanned resource replacement.
- R-2: A tested rollback path exists.

## Risk analysis

Threat model: unintended replacement of the production instance and an untested rollback window. Mitigations: create_before_destroy lifecycle, plan review, rollback rehearsed against a scratch workspace.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | Terraform plan shows a single in-place update with no replacement | passed |
| R-2 | Rollback rehearsal restored the prior instance size in scratch | passed |

## Negative-path and boundary tests

- Plan refuses to apply when the state backend is locked.
- Apply halts on any unexpected replacement diff.

## Integration verification

- Scratch-workspace apply reproduced the exact plan before production approval.

## Recovery plan

- Re-run the previous configuration from version control; backups retained per docs/ops.md.
## Approval gates

- [x] AG-1: Approved by Production Approval Lead on 2026-08-24

## Independent review

- Platform team reviewed the plan output (PR #14).

## Acceptance criteria

- AC-1: The production instance resize applies with a validated rollback.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | plan-reviewed: terraform plan attached and reviewed; rollback validated | passed |

## Context modules

- infrastructure-change v1 loaded — production-affecting infrastructure-as-code modification

## Skills

- task-decomposition v1 invoked — infra change broken into plan, apply, and verify steps

## Verification

### Baseline

- 'terraform plan' recorded with the previous instance size.

### Final

- 'terraform apply' executed after review; plan output attached to the change record.

## Files changed

- `infra/main.tf`

## Remaining risks

- None identified.
