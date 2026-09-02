# Context Module Index

> Portable, on-demand specialist context for agentic tasks. Each directory
> holds one module following the shared contract in `MODULE.md`. Inspect this
> index during **DISCOVER**, select every module whose *Load when* triggers
> match the task, and record each selection in the task file under
> `## Context modules`. Do not load module contents into every session: load
> only what the task triggers, before planning begins.
>
> Selection line format (one bullet per module, recorded in the task file):
>
>     - <module-id> v<version> loaded — <selection rationale>
>
> Documentation-only or otherwise untriggered work records the sentinel:
>
>     - None selected — <why no module applies>

## Registry

| ID | Version | Minimum risk profile | Load when (summary) |
| --- | --- | --- | --- |
| security-review | 1 | high-assurance | Authentication, authorization, secrets, sessions, permissions, cryptography |
| database-migrations | 1 | high-assurance | Schema changes, migration files, backfills, destructive data operations |
| dependency-changes | 1 | standard | Manifest or lockfile changes, dependency upgrades, new external libraries, supply-chain implications |
| infrastructure-change | 1 | high-assurance | Production-affecting CI/CD, Terraform/OpenTofu, Kubernetes, cloud resources, deployment configuration |
| public-api-change | 1 | standard | Public endpoints, published interfaces, SDK contracts, backward compatibility |
| performance | 1 | standard | Latency/memory/caching changes, hot path optimizations, resource pooling |
| accessibility | 1 | standard | UI/UX changes, color contrast, keyboard nav, ARIA, screen reader support |
| i18n | 1 | standard | New/modified user strings, locale files, date/number formatting, pluralization |
| mobile-adaptive | 1 | standard | Responsive breakpoints, touch targets, safe area, orientation, PWA installability |
| testing-infrastructure | 1 | standard | Test framework/CI config, fixtures, coverage, flaky tests, test types |

## Rules

- A selected module must exist in this registry; unknown IDs are rejected by
  `.agentic/scripts/validate-context.sh` / `validate-context.ps1`.
- The declared version must match the module's current version.
- A module's minimum risk profile is a floor: a task may always escalate, but
  it must not run at a lower profile than any selected module requires.
- Duplicate selections of the same module are rejected.
- A completed task may not carry unresolved placeholders in its selections.
