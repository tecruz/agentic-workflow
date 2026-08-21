# Security Review Module

## Trigger Rules
- High-assurance risk profile or task involves authentication, tokens, secrets, or payments.

## Guidelines
1. Never log, expose, or commit hardcoded secrets or API keys.
2. Validate all inputs defensively against injection and traversal attacks.
3. Require explicit approval gate verification before merging security-critical changes.
