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
1. **Permission First**: Create commits only when explicitly requested or permitted by documented project policy. Otherwise leave a working-tree diff for review.
2. **Atomic Commits**: Stage only intended files. Never commit temporary debug files, node_modules, or binaries.
3. **Imperative Mood**: Use "add feature" rather than "added feature".
4. **No Secrets**: Verify `git status` and `git diff` before committing to ensure no secrets or local environment files are committed.
