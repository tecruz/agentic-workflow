# 02 - Code Quality & Readability Standard

## Guidelines

1. **Strict Typing & Explicit Interfaces**
   - Leverage strong static typing whenever available (TypeScript, Rust, Go, Python type hints, Kotlin, Java).
   - Avoid `any`, `Object`, or untyped dynamic structures unless strictly required.

2. **Error Propagation & Exception Handling**
   - Use explicit error returning (`Result`, explicit error return values) or descriptive custom exceptions.
   - Never catch exceptions without logging or handling them. Do not use empty `catch` blocks.

3. **Immutability Defaults**
   - Prefer immutable variables and data structures (`const`, `val`, `final`, `readonly`) unless mutation is necessary.

4. **Self-Documenting Code & High-Value Comments**
   - Variable and function names should clearly convey intent.
   - Comments must explain *why* non-obvious business logic exists, NOT *what* standard syntax does.
   - Never add conversational or meta comments about AI code generation.

5. **Formatting & Style Consistency**
   - Strictly adhere to surrounding formatting, indentation (tabs vs. spaces), and import ordering styles.
