# Module: testing-infrastructure

## ID

testing-infrastructure

## Version

1

## Minimum risk profile

standard

## Load when

- Test framework configuration changes (Jest, Vitest, Playwright, Cypress, etc.)
- Test runner or runner configuration changes
- CI pipeline test stage modifications
- New test types added (unit, integration, e2e, contract, visual, performance)
- Test fixtures, factories, or helpers added/modified
- Coverage thresholds or reporting changes
- Flaky test mitigation or quarantine changes
- Test parallelization or sharding changes
- Mock/msw/msw configuration changes
- Test environment or container configuration changes

## Required context

- Test framework(s) in use and version constraints
- CI pipeline test execution model (parallelism, retries, timeouts)
- Coverage targets and enforcement mechanism
- Flaky test detection and quarantine process
- Test data management strategy (fixtures, factories, seeds)
- Contract testing setup (Pact, etc.) if applicable
- Visual regression testing setup if applicable

## Approval gates

- Test infrastructure changes require CI validation before merge
- Coverage threshold changes require team approval
- New test type introduction requires architecture review

## Required evidence

- CI pipeline test execution time before/after comparison
- Coverage report showing no regression (or documented improvement)
- Flaky test rate before/after for affected test suites
- New test type execution proof (sample run output)
- Test environment provisioning time comparison
- Parallelization efficiency metrics (if changed)

## Prohibited shortcuts

- Do not lower coverage thresholds to make CI pass
- Do not skip tests instead of fixing flakiness
- Do not disable CI test stages to speed up pipeline
- Do not add tests without CI integration
- Do not modify test timeouts without root-cause analysis
- Do not commit test infrastructure changes without CI validation