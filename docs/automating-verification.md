# Automating verification with agent lifecycle events

> Dev-repo documentation. `docs/` is intentionally excluded from the
> distribution bundle, so this page serves adopters reading the repository
> (e.g., on GitHub); nothing here is installed into your project.

`.agentic/checks.tsv` is the **contract** layer: it declares *what* must run
for the project to be considered done, with the honest-PASS invariant
(a `PASS` is structurally impossible unless a required check actually ran).
This page is about the **wiring** layer: *when* those checks run. Modern agent
tools expose lifecycle events (session finished, file edited, idle) that can
invoke the verifier automatically, so green-check discipline no longer depends
on the agent — or a human — remembering to run it.

Each example below runs the platform-appropriate verifier from the project
root and treats its exit code as the result (`0` PASS, `1` FAIL, `2` BLOCKED,
`3` UNSUPPORTED). Adapt the paths and policies to your project; the wiring
never weakens or replaces the contract.

## OpenCode (plugin: `session.idle`)

Project plugins in `.opencode/plugins/` auto-load and receive an `event` hook.
OpenCode emits `session.idle` when the agent stops working, which makes it a
natural "verify on handoff" trigger. Example `.opencode/plugins/agentic-verify.js`
(see the [OpenCode plugins docs](https://opencode.ai/docs/plugins/) for the
full API):

```js
// .opencode/plugins/agentic-verify.js
// Runs .agentic/scripts/verify.{ps1,sh} whenever a session goes idle and logs
// the outcome. Deliberately non-blocking: it reports, it does not gate.
export const AgenticVerify = async ({ client, $, directory }) => {
  return {
    event: async ({ event }) => {
      if (event.type !== "session.idle") return
      try {
        if (process.platform === "win32") {
          await $`pwsh -NoProfile -File .agentic/scripts/verify.ps1`.cwd(directory)
        } else {
          await $`bash .agentic/scripts/verify.sh`.cwd(directory)
        }
        await client.app.log({
          body: { service: "agentic-verify", level: "info", message: "verification PASS" },
        })
      } catch (err) {
        await client.app.log({
          body: {
            service: "agentic-verify",
            level: "warn",
            message: "verification did not pass",
            extra: { exitCode: err.exitCode },
          },
        })
      }
    },
  }
}
```

Notes:

- `session.idle` fires every time the agent pauses; on chatty sessions you may
  want to debounce, or switch to the `file.edited` / `tool.execute.after`
  events for per-change verification of smaller scopes.
- Because the file lives in the project, commit it so the whole team (and
  every fresh checkout) gets the same wiring.

## Claude Code (`Stop` hook)

Claude Code hooks are configured in `.claude/settings.json` (committable,
project-scoped). A `Stop` hook fires when Claude finishes responding — the
right place to require a green verifier before the turn is accepted:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PROJECT_DIR}/.agentic/scripts/verify.sh"
          }
        ]
      }
    ]
  }
}
```

On Windows, point the command at the PowerShell twin instead, e.g.
`powershell.exe -NoProfile -File ${CLAUDE_PROJECT_DIR}/.agentic/scripts/verify.ps1`.
Unlike a passing run, a failing verifier can feed its output back to the
model so it keeps working: the hook blocks stopping and Claude receives the
stderr output (exit-code-2 semantics — see the *Stop* section of the
[Claude Code hooks reference](https://code.claude.com/docs/en/hooks) for the
exact decision contract).

## Aider (declared commands + auto flags)

Aider's contract is two config keys; the wiring is built in. In
`.aider.conf.yml`:

```yaml
test-cmd: "bash .agentic/scripts/verify.sh"   # or pwsh -File .agentic/scripts/verify.ps1
auto-test: true                               # run after every change
```

Aider runs `test-cmd` automatically after edits when `auto-test` is enabled
(`--auto-lint` / `lint-cmd` are the lint equivalents). Because `verify.sh`
already aggregates your checks, one command is enough.

## GitHub Copilot coding agent (environment prep)

Copilot's cloud agent takes a different approach: `.github/workflows/copilot-setup-steps.yml`
is a GitHub Actions job that prepares the environment (toolchains, dependency
installs) deterministically *before* the agent starts — the agent then builds
and tests using your normal project commands in that prepped environment. It
is environment wiring rather than end-of-turn verification; your CI workflow
calling the verifier remains the green gate.

## Plain Git (`pre-push`)

Tool-agnostic fallback that gates every push, human or agent:

```sh
# .git/hooks/pre-push (or wire with lefthook/husky/pre-commit for sharing)
bash .agentic/scripts/verify.sh || exit 1
```

Git hooks are not shared by default; commit the hook script and point
`core.hooksPath` at it (e.g., `.githooks/`) if you want it versioned.

## Or orchestration-level verification

If you use this workflow's multi-agent coordinator, deterministic lifecycle
hooks already exist outside the model's judgment: `pre-spawn`, `post-worker`,
and `post-review` scripts run at fixed points of every coordinated task. See
`.agentic/orchestration/README.md` (`--hooks`). Those hooks can call the
verifier directly, giving automated verification to every delegated task
without any agent-tool-specific plugin.

## What wiring does not change

- `.agentic/checks.tsv` stays the authoritative definition of done; wiring
  only decides when it runs.
- The verification state model is unchanged: `PASS` still requires at least
  one required check to have actually run.
- Wiring is additive automation. It must never edit, regenerate, or weaken
  the contract to make a run green.
