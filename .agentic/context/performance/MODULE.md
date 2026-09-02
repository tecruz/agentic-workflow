# Module: performance

## ID

performance

## Version

1

## Minimum risk profile

standard

## Load when

- Latency-critical code paths changed
- Memory allocation patterns modified
- Algorithmic complexity changes
- Caching strategy modifications
- Database query performance changes
- Resource pooling or connection management changes
- Hot path optimizations

## Required context

- Baseline performance metrics (latency percentiles, throughput, memory usage)
- Profiling tools and methodology used by the project
- Existing performance budgets or SLAs
- Benchmark suite and how to run it
- Production traffic patterns and peak load characteristics

## Approval gates

- Performance regression approval required for changes affecting hot paths
- Benchmark results required before merging latency-sensitive changes

## Required evidence

- Before/after benchmark results for affected code paths
- Memory allocation profiles showing no regression
- Load test results demonstrating sustained performance under load
- Profiling data showing no new hotspots introduced

## Prohibited shortcuts

- Do not skip benchmarks for "small" changes on hot paths
- Do not commit performance optimizations without measurements
- Do not disable performance tests to make CI pass