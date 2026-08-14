# Contributing

Thanks for helping improve the Universal Agentic Development Protocol.

## Getting started

1. Read [`AGENTS.md`](AGENTS.md) and [`.agentic/WORKFLOW.md`](.agentic/WORKFLOW.md).
   This repository is itself an adopter of the protocol — follow the same
   lifecycle and rules it documents.
2. Create a branch and make small, atomic changes that match the surrounding
   style.
3. Run the checks below before opening a pull request.

## Local verification

The repository is self-verifying via `.agentic/checks.tsv`:

```bash
# Linux / macOS (requires bash, pwsh, bats, node)
./.agentic/scripts/verify.sh

# Windows (PowerShell 7+)
pwsh -NoProfile -File .agentic/scripts/verify.ps1
```

Required checks run:

- `bash -n` on `install.sh` and `.agentic/scripts/verify.sh`
- a PowerShell parser check on `install.ps1` and `.agentic/scripts/verify.ps1`
- the Bats suites in `tests/bats`
- the Pester suites in `tests/pester`

Optional checks (warnings only) run when their tooling is installed:
- `shellcheck` on the shell scripts

For quick fixture smoke tests:

```bash
bash tests/fixtures/run-fixtures.sh .agentic/scripts/verify.sh        # bash
pwsh -NoProfile -File tests/fixtures/run-fixtures.ps1 .agentic/scripts/verify.ps1
```

## Architecture decisions

- **Both verifiers must behave identically.** Any change to `verify.sh`
  (detection, state model, checks.tsv parsing) must be mirrored in
  `verify.ps1`. Add fixture coverage in `tests/fixtures/` and a test in both
  `tests/bats/` and `tests/pester/`.
- **Both installers must stay in sync.** `install.sh` and `install.ps1` share
  the same file-ownership model and manifest format. Manifest paths are
  normalized to forward slashes so the two interoperate.
- **Record decisions as ADRs.** Meaningful design choices go into
  `docs/decisions/` (immutable; supersede, never edit, an old record).
- **Bump `.agentic/VERSION`** when the protocol or installer behavior changes
  in a way that affects adopters. New managed or seed files must be registered
  in the file lists of **both** installers.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):
`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`. Keep commits atomic.

## Pull requests

- Keep the diff focused; no unrelated refactoring.
- Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.
- If you change verification or installer behavior, add or update tests.

## Code of conduct

Be respectful and constructive. Harassment of any kind is not tolerated.