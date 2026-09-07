# Module: api-design-patterns

## ID

api-design-patterns

## Version

1

## Minimum risk profile

standard

## Load when

- Public or internal API endpoints changed
- Request or response contracts modified
- Versioning strategy updated or applied
- Backward compatibility concerns arise
- Pagination, filtering, or sorting patterns added or changed
- Rate limiting rules introduced or adjusted
- API documentation or OpenAPI specs updated

## Required context

- Current API versioning strategy and deprecation policy
- Existing request/response schemas and validation rules
- Rate limiting configuration and enforcement points
- Pagination conventions and cursor vs. offset strategies
- API review process and required sign-offs
- Consumer dependency map for affected endpoints

## Approval gates

- Public API changes require API review before merge
- Breaking changes require documented deprecation timeline
- Rate limiting changes require impact analysis on existing consumers

## Required evidence

- Contract tests confirming request/response schema compliance
- Backward compatibility analysis documenting affected consumers
- API review approval recorded in task file
- Pagination and filtering tests covering edge cases
- Rate limit behavior tests under threshold and burst conditions

## Prohibited shortcuts

- Do not ship API changes without contract test coverage
- Do not introduce breaking changes without deprecation plan
- Do not skip backward compatibility analysis for "minor" tweaks
- Do not omit API documentation updates for new or changed endpoints
