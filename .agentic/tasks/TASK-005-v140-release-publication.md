# TASK-005: Publish v1.4.0 — date alignment, annotated tag, workflow release, supersede v1.3.0

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: high-assurance

## Profile rationale

Publication of a public GitHub release is an irreversible remote write and
production-facing infrastructure action: once the annotated tag is pushed and
the workflow publishes, assets and metadata are publicly visible and the tag
must never be moved or deleted. Escalation signals apply (production
infrastructure, irreversible operations), so the standard default is
escalated rather than downgraded later.

## Requirements

- R-1: Published 1.4.0 metadata must be internally consistent — `.agentic/VERSION` equals the tag version equals the CHANGELOG `[1.4.0]` section at the tagged commit — and the changelog section date must equal the actual publication date (2026-08-24).
- R-2: Release archives must be built from the immutable tagged SHA, uploaded as an exact three-asset set (`tar.gz`, `.zip`, `SHA256SUMS`), and verified by checksum after download-back before the draft is published.
- R-3: The previous stable release (v1.3.0) must be marked superseded in project state using the repository's established bookkeeping convention.
- R-4: The publication must not modify source code or managed protocol files; only release metadata and status bookkeeping may change.

## Risk analysis

Primary risks of this task are publication-integrity risks rather than
code risks: (a) tagging the wrong commit would publish stale or untruthful
metadata permanently, because tags are never moved or deleted; (b) a partial
or corrupted upload would give adopters broken artifacts; (c) an inconsistent
VERSION/CHANGELOG/tag triple would fail the workflow's validation gate but
could waste a release slot if unnoticed; (d) skipping the supersede marking
would leave project state claiming v1.3.0 is current. Mitigations: tag only
the final metadata commit after CI was green on its parent merge SHA; rely on
the workflow's validate → ci → build-and-publish pipeline with checksum and
asset-set gates; verify published state after the fact with `gh release`;
record supersede bookkeeping in the same convention used for every prior
release. Residual risk is limited to GitHub-side availability, which is
outside this repository's control.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | CHANGELOG.md `[1.4.0]` date edited 2026-08-21 → 2026-08-24 in commit `b4f1248`, pushed directly to master (no branch-protection fallback needed); release validate job confirmed VERSION = `1.4.0` agrees with tag and CHANGELOG section at the resolved SHA | passed |
| R-2 | Release run 32772112733 success on tagged SHA `b4f1248`: Build bundle → Verify SHA256SUMS → no-dev-file leak gate → Extract-and-test tar.gz and zip → draft created with exact asset set → assets re-downloaded and checksummed → `--draft=false`; post-publish `gh release view v1.4.0`: not draft, Latest, exactly the expected three assets | passed |
| R-3 | Commit `docs(status): mark v1.3.0 superseded by v1.4.0` compresses the PR #7/#8 entry with "Superseded by v1.4.0." and adds a v1.4.0 Notes bullet, mirroring precedent `5c7c5fb` (v1.2.2) | passed |
| R-4 | Diff scope audit: publication-day commits touch only CHANGELOG.md (one line), .agentic/STATUS.md, and this task record; no source, script, schema, test, or installer files changed | passed |

## Negative-path and boundary tests

The tagged run exercised the workflow's rejection paths at their boundaries:
metadata validation would fail on any VERSION/CHANGELOG/tag disagreement;
the asset-set exactness gate rejects stale or unexpected draft files; the
leak gate fails the build if development-only files enter the bundle; both
extract-install tests assert the boundary behavior that an empty adopter
project must report UNSUPPORTED (exit 3) rather than PASS; the download-back
checksum step fails publication on any byte drift between built and uploaded
artifacts; the release state machine refuses to overwrite an already-published
release. All gates passed green on this run.

## Integration verification

Full CI (reusable matrix across Ubuntu, macOS, Windows) ran on the exact
tagged SHA inside the release workflow (run 32772112733), integrating the
Bats and Pester suites, cross-language fixture parity, and shell/PowerShell
syntax gates. Independent confirmation from the same day: Fast CI run
32766790325 (success, 4m34s) and CI (Full) run 32766790304 (success, 9m20s)
on the merge SHA `b65a822`. Post-publication inspection via `gh release
list` / `gh release view v1.4.0` confirmed the end-to-end result.

## Recovery plan

No rollback of a published release is performed by deleting tags; the
workflow's state machine forbids overwriting a published release and never
deletes the tag. If a future defect were found in v1.4.0 assets, recovery
follows the repository's existing pattern: publish a corrective patch release
(v1.4.x) built from a fix commit, and mark the affected release superseded.
If the workflow had failed mid-publish, the draft-reuse path (existing draft
→ upload --clobber → edit notes) allows a clean re-run without orphaned or
duplicate releases; failed runs leave the previous stable release (v1.3.0)
untouched and still authoritative.

## Approval gates

- [x] AG-1: Approved by repository maintainer via reviewer feedback document explicitly authorizing "Immediate step: publish v1.4.0" steps 1–5 on 2026-08-24

## Independent review

Publication followed a reviewer-supplied feedback document which audited the
merged source, identified the stale changelog date and unpublished state, and
enumerated the required steps. Each step's outcome was independently verified
against live GitHub state (`gh release view`, `gh run watch`) rather than
trusting local assertions alone.

## Acceptance criteria

- AC-1: Annotated tag `v1.4.0` exists on the final master publication commit containing the corrected changelog date, and is pushed with matching remote tag object.
- AC-2: The Release workflow completes green on the tagged SHA and publishes a non-draft Latest release whose asset set is exactly `agentic-workflow-1.4.0.tar.gz`, `agentic-workflow-1.4.0.zip`, `SHA256SUMS`.
- AC-3: The `[1.4.0]` CHANGELOG section date equals the actual publication date (2026-08-24) at the tagged commit.
- AC-4: Project state marks v1.3.0 as superseded by v1.4.0 following the `docs(status)` convention.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | `git tag -a v1.4.0 -m "v1.4.0 — versioned JSON result contracts and observable events"` created on `b4f1248`; push accepted; workflow resolve step compared remote tag object against local and matched | passed |
| AC-2 | Run 32772112733 success (~10 min): Validate → CI full matrix on tagged SHA → build-and-publish; post-publish `gh release view v1.4.0` returned `draft=false`, listed as Latest, assets exactly the expected three | passed |
| AC-3 | CHANGELOG.md one-line edit committed as `docs(changelog): align 1.4.0 section date with publication date` (`b4f1248`) before tagging; release title rendered as `v1.4.0 — [1.4.0] - 2026-08-24` from that section | passed |
| AC-4 | STATUS.md updated: PR #7/#8 entry annotated "Superseded by v1.4.0.", new v1.4.0 release Notes bullet added; committed and pushed to master | passed |

## Context modules

- None selected — release bookkeeping with no specialist trigger

## Verification

### Baseline

Pre-publication state: PR #9 merged (`b65a822`); latest GitHub release still
v1.3.0; tags stopped at `v1.3.0`; the `[1.4.0]` changelog section dated
2026-08-21 while publication would occur 2026-08-24. Full workflow already
green on the merge SHA: Fast CI run 32766790325 (success, 4m34s) and CI
(Full) run 32766790304 (success, 9m20s) on 2026-08-24. Local working tree
clean on master after fast-forward to the merge commit.

### Final

- Release workflow run 32772112733: all jobs green (validate, ci full matrix,
  build-and-publish), including SHA256SUMS verification, extracted-archive
  install tests for both archives, exact-asset-set gate, download-back
  checksum verification, and final `--draft=false` publication.
- Post-publish inspection: `gh release list` shows `v1.4.0 … Latest`;
  `gh release view v1.4.0 --json tagName,isDraft,assets` returns tag
  `v1.4.0`, `isDraft=false`, and exactly the three expected assets.
- Task file validated with `.agentic/scripts/validate-task.ps1 -Handoff`
  (high-assurance contract) — see handoff report.

## Files changed

- CHANGELOG.md — `[1.4.0]` section date aligned to publication date (commit `b4f1248`).
- .agentic/STATUS.md — v1.3.0 marked superseded; v1.4.0 release note added; TASK-005 indexed.
- .agentic/tasks/TASK-005-v140-release-publication.md — this record.

## Remaining risks

- None material. Historical convention marks superseded releases in
  STATUS.md only; no banner was added to the v1.3.0 release body itself,
  matching how v1.2.2 was handled. A visible release-body banner remains an
  optional future enhancement if maintainers want it. Master advances past
  the tag with bookkeeping commits by design; releases always build from the
  immutable tagged SHA.
