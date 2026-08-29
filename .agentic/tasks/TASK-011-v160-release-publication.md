# TASK-011: Publish v1.6.0 — date alignment, annotated tag, workflow release, supersede v1.4.0

## Status

Status: done
Updated: 2026-08-29

## Risk profile

Profile: high-assurance

## Profile rationale

Publication of a public GitHub release is an irreversible remote write and
production-facing infrastructure action: once the annotated tag is pushed and
the workflow publishes, assets and metadata are publicly visible and the tag
must never be moved or deleted. Escalation signals apply (production
infrastructure, irreversible operations), so the standard default is
escalated rather than downgraded later. The orchestration feature (PR #13)
itself was shipped under the standard profile in TASK-010; only the
publication step carries the high-assurance contract.

## Requirements

- R-1: Published 1.6.0 metadata must be internally consistent — `.agentic/VERSION` equals the tag version equals the CHANGELOG `[1.6.0]` section at the tagged commit — and the changelog section date must equal the actual publication date (2026-08-29).
- R-2: Release archives must be built from the immutable tagged SHA, uploaded as an exact three-asset set (`tar.gz`, `.zip`, `SHA256SUMS`), and verified by checksum after download-back before the draft is published.
- R-3: The previous stable release (v1.4.0) must be marked superseded in project state using the repository's established bookkeeping convention (v1.5.0 was never published).
- R-4: The publication must not modify source code or managed protocol files; only release metadata and status bookkeeping may change.

## Risk analysis

Primary risks are publication-integrity risks rather than code risks:
(a) tagging the wrong commit would publish stale or untruthful metadata
permanently, because tags are never moved or deleted; (b) a partial or
corrupted upload would give adopters broken artifacts; (c) an inconsistent
VERSION/CHANGELOG/tag triple would fail the workflow's validation gate but
could waste a release slot if unnoticed; (d) skipping the supersede marking
would leave project state claiming v1.4.0 is current. Mitigations: tag only
the verified merge SHA (`0f84cb0`) of a PR whose head had a fully green CI
(Full) run; rely on the workflow's validate → ci → build-and-publish pipeline
with checksum and asset-set gates; verify published state after the fact with
`gh release`; record supersede bookkeeping in the same convention used for
every prior release. Residual risk is limited to GitHub-side availability,
which is outside this repository's control.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | CHANGELOG.md `[1.6.0]` date edited 2026-08-28 → 2026-08-29 in the post-publication bookkeeping commit; release validate job confirmed VERSION = `1.6.0` agrees with tag and CHANGELOG section at the resolved SHA `0f84cb0` | passed |
| R-2 | Release run 33266040485 success on tagged SHA `0f84cb0`: Validate → CI full matrix → Build & publish; post-publish `gh release view v1.6.0` returned `draft=false`, `latest=true`, assets exactly `agentic-workflow-1.6.0.tar.gz` (129907 B), `agentic-workflow-1.6.0.zip` (157053 B), `SHA256SUMS` (189 B) | passed |
| R-3 | STATUS.md: v1.4.0 release bullet annotated "Superseded by v1.6.0." and a new v1.6.0 release Notes bullet added, mirroring precedent `5c7c5fb` (v1.2.2) and TASK-005 (v1.4.0); v1.5.0 noted as never published | passed |
| R-4 | Diff scope audit: publication-day commits touch only CHANGELOG.md (one line), .agentic/STATUS.md, and this task record; no source, script, schema, test, or installer files changed | passed |

## Negative-path and boundary tests

The tagged run exercised the workflow's rejection paths at their boundaries:
metadata validation would fail on any VERSION/CHANGELOG/tag disagreement; the
asset-set exactness gate rejects stale or unexpected draft files; the leak
gate fails the build if development-only files enter the bundle; both
extract-install tests assert the boundary behavior that an empty adopter
project must report UNSUPPORTED (exit 3) rather than PASS; the download-back
checksum step fails publication on any byte drift between built and uploaded
artifacts; the release state machine refuses to overwrite an already-published
release. All gates passed green on this run.

## Integration verification

Full CI (reusable matrix across Ubuntu, macOS, Windows) ran on the exact
tagged SHA inside the release workflow (run 33266040485, all jobs success:
Validate release metadata; Full Bats Ubuntu, macOS; Full Pester Windows;
Validator parity; ci-required). Independent confirmation on the PR head
`dc7d37b` before merge: CI (Full) run 33265130453 success (all four jobs and
the ci-required aggregator, including the repaired Windows Pester job) and
Fast CI run 33265132588 success. Post-publication inspection via `gh release
list` / `gh release view v1.6.0` confirmed the end-to-end result.

## Recovery plan

No rollback of a published release is performed by deleting tags; the
workflow's state machine forbids overwriting a published release and never
deletes the tag. If a future defect were found in v1.6.0 assets, recovery
follows the repository's existing pattern: publish a corrective patch release
(v1.6.x) built from a fix commit, and mark the affected release superseded.
If the workflow had failed mid-publish, the draft-reuse path allows a clean
re-run without orphaned or duplicate releases; failed runs leave the previous
stable release (v1.4.0) untouched and still authoritative.

## Approval gates

- [x] AG-1: Approved by tecruz on 2026-08-29

## Independent review

Publication followed the repository's established flow audited against live
GitHub state rather than local assertions alone: `gh run view` confirmed the
release workflow's green jobs, `gh release view` confirmed the published
metadata and exact asset set, and the CHANGELOG date was aligned to the
actual publication date per the TASK-005 precedent before final bookkeeping.
Approval was given explicitly by the maintainer in the working session
("yes") after the merge/tag/push/release plan was presented and CI (Full) on
the PR head was confirmed green.

## Acceptance criteria

- AC-1: Annotated tag `v1.6.0` exists on the master merge commit `0f84cb0` and is pushed with matching remote tag object.
- AC-2: The Release workflow completes green on the tagged SHA and publishes a non-draft Latest release whose asset set is exactly `agentic-workflow-1.6.0.tar.gz`, `agentic-workflow-1.6.0.zip`, `SHA256SUMS`.
- AC-3: The `[1.6.0]` CHANGELOG section date equals the actual publication date (2026-08-29) at the bookkeeping commit.
- AC-4: Project state marks v1.4.0 as superseded by v1.6.0 following the `docs(status)` convention.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `git tag -a v1.6.0 -m "v1.6.0 — isolated multi-agent task coordination (ADR-0011)"` created on `0f84cb0` (merge of PR #13, 2026-08-29T17:35Z); push accepted; release workflow resolve step matched the remote tag object | passed |
| AC-2 | Run 33266040485 success: Validate → CI full matrix on tagged SHA → Build & publish; post-publish `gh release view v1.6.0` returned `draft=false`, `latest=true`, assets exactly the expected three | passed |
| AC-3 | CHANGELOG.md one-line edit `2026-08-28 → 2026-08-29` in the bookkeeping commit pushed to master | passed |
| AC-4 | STATUS.md: v1.4.0 bullet annotated "Superseded by v1.6.0."; new v1.6.0 release Notes bullet added; TASK-011 indexed | passed |

## Context modules

- None selected — release bookkeeping with no specialist trigger

## Verification

### Baseline

Pre-publication state: PR #13 merged to master as `0f84cb0`; latest GitHub
release still v1.4.0 (v1.5.0 never published); tags stopped at `v1.4.0`; the
`[1.6.0]` changelog section dated 2026-08-28 while publication would occur
2026-08-29. CI (Full) on the PR head `dc7d37b` (run 33265130453) fully green,
including the repaired Windows Pester job.

### Final

- Release workflow run 33266040485: all jobs green (validate, CI full matrix
  including the repaired Windows job, build-and-publish), including
  SHA256SUMS verification, extracted-archive install tests for both archives,
  exact-asset-set gate, download-back checksum verification, and final
  `--draft=false` publication.
- Post-publish inspection: `gh release list` shows `v1.6.0 … Latest`;
  `gh release view v1.6.0` returns `draft=false` and exactly the three
  expected assets; published `2026-08-29T17:48:09Z`.
- Task file validated with the handoff gate (high-assurance contract).

## Files changed

- CHANGELOG.md — `[1.6.0]` section date aligned to publication date.
- .agentic/STATUS.md — v1.4.0 marked superseded by v1.6.0; v1.6.0 release note added; TASK-011 indexed.
- .agentic/tasks/TASK-011-v160-release-publication.md — this record.

## Remaining risks

- None material. Historical convention marks superseded releases in
  STATUS.md only; no banner was added to the v1.4.0 release body itself,
  matching prior releases. Master advances past the tag with bookkeeping
  commits by design; releases always build from the immutable tagged SHA.
- The release title renders the pre-alignment changelog date
  (`v1.6.0 — [1.6.0] - 2026-08-28`), matching how v1.4.0's title kept its
  original date after the same alignment step; cosmetic only.