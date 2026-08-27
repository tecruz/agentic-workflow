# Module: public-api-change

## ID

public-api-change

## Version

1

## Minimum risk profile

standard

## Load when

- Public HTTP endpoints or their request/response contracts change
- Published interfaces, exported symbols, or SDK surfaces change
- Wire formats, error codes, or status semantics change
- Backward-compatibility commitments could be affected

## Required context

- Published API documentation or interface definitions
- Existing compatibility tests or consumer contract fixtures
- Deprecation policy and versioning scheme used by the project
- Known external consumers of the affected surface

## Approval gates

- Approval required for breaking changes under the project's API policy

## Required evidence

- Compatibility evidence: tests proving old consumers continue to work, or a recorded deprecation/migration path
- Updated public documentation matching the implemented behavior
- Changelog entry describing the visible contract change

## Prohibited shortcuts

- Do not ship a breaking change without compatibility evidence or a documented migration path
- Do not let public documentation drift from the implemented contract
- Do not repurpose existing fields or status codes with new meanings silently
