# Module: error-handling

## ID

error-handling

## Version

1

## Minimum risk profile

standard

## Load when

- Error classification or taxonomy changes
- Retry or fallback logic introduced or modified
- Circuit breaker patterns added or tuned
- Error reporting or alerting pipelines changed
- Graceful degradation behavior implemented
- User-facing error messages added or revised
- Error propagation boundaries altered

## Required context

- Current error classification scheme and codes
- Retry policies (backoff strategy, max attempts, jitter)
- Circuit breaker thresholds and recovery rules
- Error reporting destinations and alerting rules
- Graceful degradation behaviors per failure mode
- User-facing error message style guide and localization approach

## Approval gates

- Changes to error classification require review from observability owner
- Retry policy changes require load-test validation
- User-facing error message changes require content review

## Required evidence

- Error injection tests confirming correct classification and handling
- Failure-mode analysis documenting covered failure scenarios
- Retry behavior verification showing backoff and max-attempt enforcement
- Circuit breaker tests validating state transitions and recovery
- Graceful degradation tests confirming fallback behavior activates correctly

## Prohibited shortcuts

- Do not add retry logic without verifying backoff under load
- Do not change error classification without updating all consumers
- Do not merge user-facing error messages without content review
- Do not disable error injection tests to pass CI
