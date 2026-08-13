# 03 - Testing & Self-Verification Standard

## Guidelines

1. **Verification-First Mindset**
   - Code is not done until verified by execution, unit/integration tests, or static analysis.
   - Run tests before making changes to establish a baseline, and after making changes to prevent regressions.

2. **Testing Granularity**
   - **Unit Tests**: Test business logic in isolation with mock dependencies when appropriate.
   - **Integration Tests**: Test interactions across real modules, DBs, or APIs.
   - **Smoke Tests**: Verify core execution path runs without crashing.

3. **Self-Healing Loop Procedure**
   - Read build and test output carefully.
   - Isolate failing test assertions or stack traces.
   - Modify implementation or test expectation if specifications changed.
   - Re-verify until green.

4. **Test Maintenance**
   - When introducing new features or fixing bugs, include corresponding automated tests covering happy path and edge cases.
