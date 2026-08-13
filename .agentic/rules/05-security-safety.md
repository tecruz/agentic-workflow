# 05 - Security & Safety Rules

## Imperative Safety Rules

1. **Zero Secret Leakage**
   - Never hardcode or commit secrets, API keys, passwords, database URLs with credentials, or private tokens.
   - Use environment variables (`.env`, secret stores) and ensure environment secret files are in `.gitignore`.

2. **Input Sanitization & Injection Prevention**
   - Sanitize all external inputs (HTTP request query/body, user input, file inputs).
   - Use parameterized queries for SQL to prevent SQL injection.
   - Avoid unsafe evaluation functions (`eval`, dangerous shell invocations).

3. **Command Execution Bounds**
   - Explain shell commands before executing actions that modify filesystem state, remote repositories, or environment packages.
   - Never run destructive or high-risk system commands (e.g. `rm -rf /`, format drives, system reconfiguration) without confirmation.

4. **Dependency Auditing**
   - Avoid adding untrusted or unmaintained third-party libraries.
