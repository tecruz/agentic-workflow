# Module: infrastructure-change

## ID

infrastructure-change

## Version

1

## Minimum risk profile

high-assurance

## Load when

- CI/CD pipeline changes that affect production deployments, release gates, or deployment credentials (framework-test workflow edits that only run this repository's own checks do not trigger this module)
- Terraform/OpenTofu or other infrastructure-as-code changes
- Kubernetes manifests, Helm charts, or controller configuration
- Cloud resource definitions and deployment configuration

## Required context

- Target environment topology and environment promotion path
- State-management approach (remote state, locking) for IaC changes
- Rollback procedure for the affected infrastructure layer
- Monitoring/alerting coverage for the changed resources

## Approval gates

- Explicit approval required for production-affecting infrastructure changes

## Required evidence

- Plan/dry-run output reviewed and attached or referenced in the task file
- Verification that non-production targets deploy cleanly first
- Documented rollback steps validated for the specific change

## Prohibited shortcuts

- Do not apply production infrastructure changes without a reviewed plan
- Do not weaken pipeline gates or remove required checks to unblock deploys
- Do not hand-edit generated infrastructure state outside the IaC workflow
