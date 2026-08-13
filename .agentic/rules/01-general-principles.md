# 01 - General Software Design Principles

## Core Tenets

1. **KISS (Keep It Simple, Stupid)**
   - Always choose the simplest solution that satisfies all requirements.
   - Avoid premature abstraction, over-engineering, or speculative features.

2. **DRY (Don't Repeat Yourself)**
   - Reuse existing logic, helper functions, and components.
   - Do not duplicate code unless explicit separation of concerns warrants it.

3. **YAGNI (You Aren't Gonna Need It)**
   - Build only what is needed now.
   - Do not add theoretical parameters, unused interfaces, or dead code paths.

4. **Single Responsibility Principle (SRP)**
   - Functions, classes, and modules should have one clear responsibility and one reason to change.

5. **Defensive Programming**
   - Validate input parameters at module boundaries.
   - Fail fast and handle errors explicitly rather than suppressing exceptions.
