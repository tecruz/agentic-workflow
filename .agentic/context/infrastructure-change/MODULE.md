# Infrastructure Change Module

## Trigger Rules
- Changes to `.github/workflows/`, `Dockerfile`, `docker-compose.yml`, or deployment scripts.

## Guidelines
1. Validate GitHub Actions workflows using `actionlint`.
2. Ensure least-privilege permissions in CI jobs.
3. Test deployment scripts in sandboxed environments prior to release.
