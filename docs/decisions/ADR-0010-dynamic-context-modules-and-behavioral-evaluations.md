# ADR-0010 — Dynamic Context Modules and Behavioral Evaluations

## Status

Accepted (v1.5.0)

## Context

Static system prompts and oversized context windows degrade agent performance and reasoning quality. Evaluation based solely on final outputs is insufficient to guarantee harness safety and rule adherence.

## Decision

1. **Portable On-Demand Context Modules**:
   - Introduce `.agentic/context/` modules triggered by specific file paths, risk profiles, or task characteristics.
2. **Behavioral Evaluation Framework**:
   - Introduce `evals/` containing observable behavioral scenarios to score harness reactions, module selection, risk escalation, and approval gating without inspecting private reasoning.

## Consequences

- Agents load specialist knowledge only when needed, reducing noise.
- Evaluations objectively verify observable harness behavior against protocol standards.
