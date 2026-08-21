# Database Migrations Module

## Trigger Rules
- File path matches `*migration*`, `*schema*`, or `*.sql`.

## Guidelines
1. Always test forward and backward migration scripts.
2. Never perform irreversible data deletions without explicit approval gates.
3. Ensure zero-downtime compatibility where applicable.
