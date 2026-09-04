# Skill: release-verification

## ID

release-verification

## Version

1

## Minimum risk profile

standard

## Invoked when

- VERSION, CHANGELOG, and tag agreement must be confirmed before publication
- A distribution bundle (tar.gz/zip/SHA256SUMS) must be proven installable
- A release-to-release (N-1 to N) upgrade path must be demonstrated

## Required context

- `.agentic/VERSION`, CHANGELOG section, and the candidate tag name
- `scripts/build-bundle.sh` output and SHA256SUMS
- Extracted-archive install results for every published archive
- The N-1 bundle used for the upgrade leg

## Approval gates

- No extra approval beyond the task's own gates; publication itself follows project release policy

## Required evidence

- Metadata-agreement check (VERSION/CHANGELOG/tag) with exit code
- Bundle build log with no-leak gate result
- Extracted-archive install test results per archive plus SHA256SUMS verification
- N-1 upgrade demonstration (previous bundle install, custom content, upgrade, preservation check)

## Prohibited shortcuts

- Do not publish without extracted-archive install tests on the exact tagged SHA
- Do not hand-edit archives after SHA256SUMS is generated
- Do not skip the N-1 upgrade leg when the installer registry changed
