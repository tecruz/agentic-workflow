# TASK-004: PR #9 review blocker — Bash --events-force directory destination

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

This task fixes one remaining release-contract defect in the v1.4.0 event
stream found during the second PR #9 review round: Bash force mode accepts an
existing directory as the event-file destination because `mv -f` moves the
scratch file inside the directory and returns 0, so promotion is reported
successful while the relocated scratch file escapes cleanup by the exit trap.
The change touches verifier observable behavior only (rejecting destinations
that were never usable); no authentication, payments, secrets handling, data
migration, production infrastructure, irreversible operation,
public-API compatibility commitment beyond the unreleased v1.4.0 contract,
privacy-regulated data, or safety-critical behavior is involved. The standard
profile provides adequate verification depth: a dedicated Bash regression test
mirroring the existing PowerShell force-promotion-failure Pester test plus
manual scenario runs. Escalation signals were reviewed; none apply.

## Acceptance criteria

- AC-1: Bash `--events-force` rejects an existing destination that is not a regular file (directory, FIFO, device) with a nonzero exit before any file is moved, leaving the destination untouched and no `.verify-events.*` scratch file inside or beside it.
- AC-2: After successful forced promotion, the destination at `$EVENTS_FILE` is verified to be a regular file (`[ -f ]`), and a failed promotion reports an error, removes the scratch, and exits nonzero.
- AC-3: `EVENTS_SCRATCH` is cleared immediately after successful forced promotion so the exit trap cannot act on a stale path.
- AC-4: A Bats regression test creates a directory at the destination path, runs `--events-force`, requires nonzero exit, requires the destination to remain a directory, and requires no `.verify-events.*` file inside or beside it.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Manual Git-Bash/WSL scenario matrix (22/22 assertions): directory + force → rc=1, "not a regular file" message, dir intact, zero scratch; directory + no force → rc=1; FIFO + force → rc=1, FIFO intact. New Bats test 54 passes | passed |
| AC-2 | Forced-promotion postcondition `[ -f "$EVENTS_FILE" ]` verified in scenario runs (regular file present, fresh `verification_started` first line, exactly 4 events after replace) and by code inspection of verify.sh:1069-1076 | passed |
| AC-3 | `EVENTS_SCRATCH=""` set on the forced-success path (verify.sh:1077); manual runs show zero `.verify-events.*` files under `.agentic/runs/` after every outcome | passed |
| AC-4 | Bats suite executed locally with bats-core 1.11.0 under WSL bash: verify_test.bats 55/55 pass including new `--events-force refuses a directory destination and leaves no scratch file`; old-code reproduction (git show HEAD) stranded `.verify-events.RwcKWw` inside the destination directory, proving the test is sensitive to this defect class | passed |

## Approval gates

- None identified

## Context modules

- .agentic/scripts/verify.sh
- tests/bats/verify_test.bats
- .agentic/scripts/verify.ps1 (reference implementation)
- tests/pester/JsonContracts.Tests.ps1 (PowerShell counterpart test)

## Verification

### Baseline

Before changes (77d1162): reproduced with WSL bash — created
`.agentic/runs/events.jsonl` as a directory, ran
`bash verify-old.sh --events .agentic/runs/events.jsonl --events-force` in a
temp project against `git show HEAD:.agentic/scripts/verify.sh`: promotion
reported success, hidden scratch file `.verify-events.RwcKWw` left stranded
inside the destination directory, exit trap removed nothing, run later exited
nonzero on append-to-directory failure.

### Final

- `bash -n .agentic/scripts/verify.sh` — OK.
- Manual scenario matrix (`events-force-check.sh`, WSL bash): 22 pass / 0 fail
  covering all four accepted destination states from the review (absent →
  create; regular file + no force → reject; regular file + force → replace;
  directory/FIFO → reject), each also asserting no `.verify-events.*`
  leftovers.
- Old-code regression sensitivity: pre-fix script leaves scratch inside the
  destination directory; new Bats assertion catches it via recursive find.
- Bats: bats-core 1.11.0, `bats tests/bats/verify_test.bats` → 55 ok / 0 fail
  / 1 environment skip (pwsh parity, pre-existing). Includes new test 54 and
  unchanged no-clobber test 53.
- PowerShell code untouched; Pester JSON-contract suite unaffected (its Bash
  cases exercise parse-time rejection paths that precede the changed block).
- CHANGELOG 1.4.0 Fixed entry added for the force-mode destination guard.

## Files changed

- .agentic/scripts/verify.sh — reject non-regular existing event destinations before promotion; postcondition `[ -f ]` check after forced promotion; clear `EVENTS_SCRATCH` on success; `mv -f --` argument hygiene.
- tests/bats/verify_test.bats — force-mode directory-destination regression test (nonzero exit, error message, destination stays a directory, recursive scratch-leak check).
- CHANGELOG.md — 1.4.0 Fixed bullet for the force-mode destination guard.

## Remaining risks

- CI gates from the review acceptance conditions still outstanding: exact-head
  fast CI and CI (Full) must run on the resulting SHA once pushed. Local
  environment lacks shellcheck; bats was bootstrapped ad hoc for local
  evidence, CI runners provide both natively.
- Non-blocking ADR-0009 wording refinement suggested by the reviewer
  (coverage statement) intentionally deferred as out of scope for this fix.
