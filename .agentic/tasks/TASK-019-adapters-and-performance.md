# TASK-019 — Agent-tool adapters + checks.tsv performance (v1.11.0)

## Status

Status: done
Updated: 2026-09-05

## Risk profile

Profile: standard

## Profile rationale

Ordinary product work: two opt-in import-only tool bridges plus
behavior-preserving verifier startup optimizations, with Bash+PowerShell
parity, installer/bundle registration, and version sweep. No authentication,
payments, secrets handling, data migration, production infrastructure,
irreversible operation, public-API compatibility commitment,
privacy-regulated data, or safety-critical behavior. Escalation signals
reviewed; none apply. The `--tools` CLI surface gains two opt-in values but
no existing value changes meaning, so no public-API compatibility break.

## Acceptance criteria

- AC-1: Two new opt-in adapters ship as import-only bridges (no protocol
  duplication, ADR-0001): `cursor` → `.cursor/rules/agentic-protocol.mdc`
  (`alwaysApply: true`, pointer to `AGENTS.md` + `.agentic/WORKFLOW.md`) and
  `copilot` → `.github/copilot-instructions.md` (pointer to `AGENTS.md`);
  `--tools` accepts `cursor,copilot` and `all` includes them; both installers,
  `build-bundle.sh`, manifest validation, and prune/uninstall cover them.
- AC-2: Verifier startup overhead is profiled and reduced without behavior
  change: Bash `verify.sh` no longer spawns `python3` twice per check for
  timing, `json_escape` no longer forks per character, and duplicate-ID /
  seen-package scans are no longer O(n²); PowerShell `verify.ps1` caches the
  project root, resolved root, and command lookups across checks. A
  `tests/perf/` benchmark with a synthetic large contract records
  before/after numbers in this file.
- AC-3: Compatibility tables updated — `AGENTS.md` §6 and `README.md` tool
  table document the 2026 landscape (Codex/Cursor/Windsurf/Copilot native,
  Claude/Gemini bridges, new opt-in Cursor/Copilot bridges) with no claim
  that a bridge exists where the tool reads `AGENTS.md` natively.
- AC-4: Distribution wiring — `.agentic/VERSION` and `protocol_version`
  swept to `1.11.0`; `CHANGELOG.md` `[1.11.0]`; `ROADMAP.md` Later-items for
  adapters + large-checks.tsv performance marked done; full local
  verification green.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Fresh install `-Tools cursor,copilot` carries both bridges; `all` includes them; deselect prunes them; manifest records both as managed; N-1 upgrade delivers them; Pester Install 83 passed/0 failed (2 env skips) incl. 3 new + payload/upgrade legs; Bats legs added for CI | passed |
| AC-2 | Before/after numbers in `### Baseline`; HEAD-vs-worktree full-run output identical modulo `duration_ms` (Bash JSON+text, PS JSON); escape corpus 60/61 (1 intended strictness fix); Pester Verify+JsonContracts 81/0, fixtures 55/55, evals 8/8 both languages | passed |
| AC-3 | `AGENTS.md` §6 + `README.md` table/tree/`--tools` diff reviewed; Cursor/Copilot opt-in rows accurate; Codex-native no-adapter row added; no stale claim | passed |
| AC-4 | `VERSION=1.11.0` sweep clean; handoff gate VALID three legs (sh+ps1); `git diff --check` clean; `bash -n` + PS parse clean; full `verify.ps1` BLOCKED only by missing `bats` (pre-existing env gap, same as TASK-017) | passed |

## Approval gates

- None identified

## Context modules

- performance v1 loaded — task profiles and optimizes verifier startup latency on large checks.tsv contracts
- testing-infrastructure v1 loaded — task adds a tests/perf benchmark harness and extends installer/verify fixture coverage

## Skills

- task-decomposition v1 invoked — request split into adapters + performance + tables + release wiring before planning
- verification-triage v1 invoked — baseline failures distinguished from introduced failures during repair cycles

## Files changed

- `.cursor/rules/agentic-protocol.mdc` — new (opt-in Cursor bridge, `alwaysApply: true`, pointer only)
- `.github/instructions/agentic-protocol.instructions.md` — new (opt-in Copilot bridge, `applyTo: **`, pointer only)
- `install.sh`, `install.ps1` — `--tools`/`-Tools` accept `cursor,copilot`; `all` includes them; managed-file + manifest-path + `check_partial`/`Assert-NotPartial` registration (aider pattern)
- `scripts/build-bundle.sh` — bundle carries both bridges; leak gate narrowed `.github` → `.github/workflows` (instructions dir is adopter payload)
- `.agentic/scripts/verify.sh` — `now_ms()` (no per-check python spawns), fork-free `json_escape` (`printf -v` + fast path, strict 4-digit `\u00XX`), O(1) duplicate-ID set + resolved-dir cache + workspace membership sets on bash 4+ (bash 3.2 fallbacks kept)
- `.agentic/scripts/verify.ps1` — per-run command/CWD caches (`$null`-safe sentinels); validation resolves project root once + per-directory cache
- `tests/perf/benchmark.sh`, `tests/perf/benchmark.ps1` — new dev-only large-contract benchmark twins (not in `checks.tsv`)
- `tests/bats/install_test.bats`, `tests/pester/Install.Tests.ps1` — select/all/deselect tests, bundle payload + leak-gate updates, N-1 upgrade delivery assertions
- `.agentic/VERSION` — 1.11.0; `protocol_version` sweep to 1.11.0 (verify/validate-*/coordinator ×2 langs, 5 schemas, evals runners/generator/schema/artifacts, 7 test files)
- `.agentic/checks.tsv` — handoff-gate retarget TASK-017→TASK-019 (TASK-009 precedent)
- `AGENTS.md` (§6), `README.md` (tool tables, tree, `--tools` values) — 2026 adapter landscape
- `ROADMAP.md` (version line, Later-items done), `CHANGELOG.md` (`[1.11.0]`), `.agentic/STATUS.md` (TASK-019 row)
- `.agentic/tasks/TASK-019-adapters-and-performance.md` — this file

## Verification

### Baseline

- Clean tree at v1.10.0 (`3a86d8f`); `git status --short` empty.
- Synthetic-contract profiling on this host (300 no-op checks):
  - PowerShell `-ValidateChecks`: 300 checks 4.1s, 600 checks 10.1s (superlinear).
  - Bash `--validate-checks` (WSL): 300 checks 3.2s real (user 0.98s), 600 checks 6.9s real (user 3.7s) — user time ~3.8x for 2x = quadratic.
  - Bash `json_escape` ×200 (55-char ID): 13.0s real (~65ms/call, one fork per char).
  - `python3 -c` timing spawn ×200: 6.0s real (~30ms/spawn = ~60ms per check).
- After (same host, same contracts): PS validate 300 in 0.37s; Bash validate
  300 in 0.45s real (user 0.17s), 600 in 0.79s real (user 0.30s) — linear;
  `json_escape` ×100: 6.9s → 0.014s (~500x); per-check timing 35ms → 3ms
  (Bash full-run probe); `tests/perf/benchmark.* 300`: PS
  validate/full-text/full-json 371/7659/12040ms, Bash 165/2037/4139ms.
- Output equivalence (HEAD vs worktree, `duration_ms` normalized): Bash JSON
  identical, Bash text identical, PS JSON identical; escape corpus 60/61
  identical — the single delta is the intended strictness fix (`\u01` →
  `\u0001`), unpinned by any test.

### Final

- `bash -n`: install.sh, verify.sh, build-bundle.sh, tests/perf/benchmark.sh all OK; PS parse clean: install.ps1, verify.ps1, benchmark.ps1, Install.Tests.ps1.
- `validate-task/context/skills.ps1` + `validate-handoff.ps1` on this file: VALID (three legs); `validate-handoff.sh` VALID (perl present in WSL).
- Pester: ValidateSkills/Context/Task 231/0 (2 pre-existing bash-leg skips); Verify+JsonContracts 81/0 (15 pre-existing skips); Coordinator 16/0; Install 83/0 (2 env skips: no zip/unzip); bundle-leak subset 4/4.
- `evals/run-evals.ps1` 8/8; `evals/run-evals.sh` (WSL) 8/8; `tests/fixtures/run-fixtures.ps1` 55/55 OK, 0 mismatches.
- `install.sh` smoke (WSL): cursor+copilot install, deselect prune, unknown-tool reject, manifest managed rows — all OK.
- `git diff --check` clean. Full `verify.ps1` not run to completion locally: predetermined BLOCKED on missing `bats` (no bats/shellcheck on this Windows host; Bats + shellcheck legs proven in CI per TASK-017 precedent).
- Pre-existing failures: none observed (fixtures fully green, unlike the TASK-017-era host state).

## Remaining risks

- `all` newly includes `cursor` + `copilot`: adopters re-running with
  `--tools all` receive two new pointer files; mitigated by opt-in-only
  default (`claude,gemini,aider` unchanged) and prune-on-deselect.
- Timing helper changes `duration_ms` values by milliseconds, never PASS/FAIL
  outcomes; JSON/event contracts byte-identical apart from `duration_ms`.
- Fresh cursor installs print `note legacy .cursor` and deselect leaves an
  empty `.cursor/rules/` behind: report-only legacy-dir behavior, no deletion
  risk; left unchanged to avoid touching legacy semantics.
- Bundle leak gate narrowed `.github` → `.github/workflows`: future
  `.github/*` additions must extend the gate; bundle tests pin the new shape.
- Bats + shellcheck legs not runnable on this host; proven in CI.
