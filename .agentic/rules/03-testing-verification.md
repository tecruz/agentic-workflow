# 03 - Testing & Self-Verification Standard

## Guidelines

1. **Verification-First Mindset**
   - Code is not done until verified by execution, unit/integration tests, or static analysis.
   - Run tests before making changes to establish a baseline, and after making changes to prevent regressions.
   - Prefer the project's checks in `.agentic/checks.tsv`; they are the authoritative definition of done.

2. **Testing Granularity**
   - **Unit Tests**: Test business logic in isolation with mock dependencies when appropriate.
   - **Integration Tests**: Test interactions across real modules, DBs, or APIs.
   - **Smoke Tests**: Verify core execution path runs without crashing.

3. **Bounded Self-Healing Loop**
   - Read build and test output carefully.
   - Isolate failing test assertions or stack traces.
   - Formulate a root-cause hypothesis before changing code.
   - Attempt at most **three** evidence-based repair cycles; then stop, preserve the latest useful state, and report the blocker.

4. **Test Integrity**
   - Never weaken, delete, skip, or rewrite a failing test merely to obtain a green result.
   - A test expectation may change only with evidence that the intended behavior changed: an accepted specification, a user instruction, or a documented contract.

5. **Test Maintenance**
   - When introducing new features or fixing bugs, include corresponding automated tests covering the happy path and edge cases.

6. **Honest Reporting**
   - Distinguish failures introduced by the change from failures already present at baseline.
   - Report external outages, unavailable compilers, missing credentials, and pre-existing failing tests honestly instead of looping indefinitely or concealing results.
