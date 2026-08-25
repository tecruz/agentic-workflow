# Module: dependency-changes

## ID

dependency-changes

## Version

1

## Minimum risk profile

standard

## Load when

- Manifest or lockfile changes (package.json, go.mod, Cargo.toml, requirements files, and equivalents)
- Dependency upgrades, downgrades, or replacements
- Introduction of new external libraries or services
- Changes with supply-chain implications (registries, mirrors, postinstall scripts)

## Required context

- Current lockfile state and the project's upgrade policy
- Known-vulnerability status of added or upgraded packages
- License compatibility for new dependencies
- CI coverage that exercises the changed dependency surface

## Approval gates

- Approval required wherever project policy gates dependency upgrades

## Required evidence

- Build and test suite passing with the updated dependency set
- Recorded rationale for adding, upgrading, or replacing each dependency
- Lockfile diff reviewed for unexpected transitive changes

## Prohibited shortcuts

- Do not bypass the lockfile or commit hand-edited lockfiles
- Do not ignore peer-dependency conflicts without recording why
- Do not add dependencies with unvetted install scripts silently
