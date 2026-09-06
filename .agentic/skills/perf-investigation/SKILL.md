# Skill: perf-investigation

## ID

perf-investigation

## Version

1

## Minimum risk profile

standard

## Invoked when

- A latency- or memory-sensitive change is proposed or regresses
- A benchmark, profile, or CI timing check shows a degradation
- A hot path, cache, or resource-pooling change must be justified

## Required context

- The baseline measurement before the change and the measurement after it
- The benchmark harness used and how to reproduce both measurements
- The `.agentic/context/performance/` module guidance
- The change diff isolating the suspected hot path

## Approval gates

- No extra approval beyond the task's own gates; a regression that cannot be explained blocks merge

## Required evidence

- Before/after measurements from the same benchmark on the same host
- The hypothesis linking the diff to the measured change
- Verification that the change was not merely noise (repeat runs, variance noted)

## Prohibited shortcuts

- Do not optimize without a baseline measurement
- Do not present a single noisy run as proof of improvement
- Do not ship a measured regression without recording why it is acceptable
