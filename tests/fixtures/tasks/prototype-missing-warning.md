# PROTOTYPE-002: Spike alternate hashing

## Risk profile

Profile: prototype

## Profile rationale

User requested a disposable comparison of two hashing strategies. No production impact.

## Task goal

Compare hash throughput on representative keys.

## Smoke verification

Both variants ran over the sample corpus without errors.

## Known limitations

- Only one corpus tested.
- Not cryptographically reviewed.

## Remaining risks

- Different key distributions may change results.

## Handoff

Outcome: variant B is faster on the sample corpus.
Smoke verification: passed.
Known limitations: single corpus, no crypto review.
No production deployment or irreversible operation was performed.