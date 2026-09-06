# Skill: dependency-audit

## ID

dependency-audit

## Version

1

## Minimum risk profile

standard

## Invoked when

- A manifest or lockfile changes (package.json, Cargo.toml, pyproject.toml, go.mod, pom.xml, gradle files)
- A dependency is added, upgraded, removed, or pinned
- Supply-chain implications of a dependency change must be assessed

## Required context

- The exact manifest/lockfile diff being proposed
- The dependency's purpose and the reason it cannot be avoided
- The project's existing dependency-change policy (`.agentic/context/dependency-changes/`)
- Lockfile regeneration state and transitive-impact expectations

## Approval gates

- No extra approval beyond the task's own gates; add or upgrade nothing before the audit is recorded in the task file

## Required evidence

- The manifest diff with before/after versions for every changed dependency
- A recorded assessment: purpose, alternatives considered, lockfile state
- Post-change verification result (the project's checks.tsv checks pass or blockers are documented)

## Prohibited shortcuts

- Do not add a new dependency when an existing one satisfies the need
- Do not commit a manifest change without its matching lockfile update
- Do not bypass version pinning or supply-chain review to save a cycle
