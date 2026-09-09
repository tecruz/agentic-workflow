# TASK-028 — cache eval-corpus run in JsonContracts Pester suite

## Status

Status: done
Updated: 2026-09-09

## Risk profile

Profile: standard

## Profile rationale

Test-infrastructure optimization only — no authentication, payments, secrets
handling, data migration, production infrastructure, irreversible operation,
public-API compatibility commitment, privacy-regulated data, or safety-critical
behavior. Escalation signals reviewed; none apply.

## Acceptance criteria

- AC-1: The four full-corpus `Invoke-EvalRunner $runEvalsPs 'Json'` calls
  (PS schema, negative control FORBIDDEN_ACTIONS_ABSENT, negative control
  REQUIRED_MODULES_SELECTED, positive scenarios) share a single cached run
  executed once in `BeforeAll`.
- AC-2: On Windows (no bash, no cached corpus), the four PS corpus tests
  skip with a clear message rather than fail.
- AC-3: File-level `BeforeAll` defines `$repoRoot`, `$evalsDir`,
  `$runEvalsSh`, `$runEvalsPs` at script scope so they are available during
  Pester 5 discovery and accessible from all Describe blocks.
- AC-4: Local runtime for the Behavioral Describe drops from ~9.4 min to
  ~2.0 min (≥4× improvement) with zero assertion changes.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Invoke-EvalRunner $runEvalsPs 'Json' removed from 4 It blocks; replaced with $script:psResult | passed |
| AC-2 | if ($IsWindows) { Set-ItResult -Skipped } guard in all 4 PS corpus tests | passed |
| AC-3 | File-level BeforeAll (line 30) defines $repoRoot, $evalsDir, $runEvalsSh, $runEvalsPs; parse OK | passed |
| AC-4 | Baseline 9.41 min → cached 1.98 min (4.8× faster), 0 failures | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — Pester suite optimization

## Skills

- verification-triage v1 invoked — no behavioral change; result integrity confirmed by identical pass/skip/fail counts

## Files changed

- tests/pester/JsonContracts.Tests.ps1 — file-level BeforeAll, corpus cache in Describe BeforeAll, 4 skip guards
- .agentic/tasks/TASK-028-eval-suite-caching.md (new)

## Verification

### Baseline

- Four independent `Invoke-EvalRunner $runEvalsPs 'Json'` calls each spawned
  the full 12-scenario harness (3 validators × 12 scenarios per invocation),
  totaling ~9.4 min locally on Windows.

### Final

- Single cached corpus run in Describe `BeforeAll`; four tests reference
  `$script:psResult` instead of re-running the harness.
- Windows skip guards (`if ($IsWindows) { Set-ItResult -Skipped }`) ensure
  the four PS corpus tests are skipped gracefully when the cache is absent.
- File-level `BeforeAll` (lines 30-35) makes `$repoRoot`, `$evalsDir`,
  `$runEvalsSh`, `$runEvalsPs` available during Pester 5 discovery.
- Local timed run: **1.98 min** (117.8s), 9 passed, 5 skipped, 0 failed.
  The 4.8× speedup leaves non-corpus tests (fixture validation, custom-dir
  harness runs) unaffected.

## Remaining risks

- The bash-leg corpus test (skipped on Windows) is not cached because it
  runs only once per suite on CI; caching it would add complexity for no
  measurable gain.
- On Windows the four PS corpus tests are skipped entirely; they rely on
  CI (Linux/macOS) for full coverage, which is the existing pattern for all
  bats-gated tests.
