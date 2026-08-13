# 04 - Git Conventions & Workflow

## Commit Message Format

Follow the **Conventional Commits** specification:

```
<type>(<scope>): <short summary>

[optional body]
```

### Allowed Types
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation changes only
- `style`: Formatting, missing semicolons, no code changes
- `refactor`: Code refactoring without functionality changes
- `test`: Adding or correcting tests
- `chore`: Maintenance, build tasks, dependency updates

### Guidelines
1. **Atomic Commits**: Stage only intended files. Never commit temporary debug files, node_modules, or binaries.
2. **Imperative Mood**: Use "add feature" rather than "added feature".
3. **No Secrets**: Verify `git status` and `git diff` before committing to ensure no secrets or local environment files are committed.
