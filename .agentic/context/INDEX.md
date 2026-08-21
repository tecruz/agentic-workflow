# Context Module Index

To keep static context small and efficient, specialist knowledge is loaded on demand only when triggered by task characteristics, file paths, or risk profiles.

## Available Modules

- [Database Migrations](database-migrations/MODULE.md) — Loaded when migration scripts or schema files are touched.
- [Security Review](security-review/MODULE.md) — Loaded for authentication, authorization, cryptography, or token handling tasks.
- [Dependency Changes](dependency-changes/MODULE.md) — Loaded when adding, upgrading, or removing package dependencies.
- [Infrastructure Change](infrastructure-change/MODULE.md) — Loaded for CI/CD workflows, Dockerfiles, cloud configs, or deployment scripts.
