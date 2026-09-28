# ADR-0018 - Walking-skeleton checkpoint (opt-in integrated gate for orchestration)

- **Date**: 2026-09-27
- **Status**: Accepted
- **Deciders**: maintainers (adopted-ideas review: `awslabs/aidlc-workflows`, `qtalen/aidlc-skills`)

## Context

The orchestrator (ADR-0011) runs a generic worker in an isolated worktree and
optionally re-validates task-file contracts (`--review`), but it never proved
that the task's own definition of "working" still holds after the worker
finished. Verification lived entirely inside the worker command, where a
non-zero exit was the only signal and nothing recorded *which* end-to-end
check the task author considered the walking skeleton. Teams adopting the
aidlc workflows expressed the same gap: a thin, always-on integration path
should be checked on every orchestration run, with a named approval before it
can gate remote writes, and its outcome visible in the event stream.

## Decision

1. **`## Walking skeleton` is a canonical, opt-in task section.** When the
   coordinator runs with `--skeleton` (`-Skeleton`), the task file must carry
   exactly one `- Slice:`, one `- Integrated check:`, and one
   `- Skeleton approval: pending | approved by <approver> on YYYY-MM-DD`
   entry. A missing or malformed section (including empty, duplicated, or
   non-substantive values) blocks with exit 2 **before** any lock, worktree,
   or worker exists, mirroring the approval-gate contract.

2. **Pending approval gates remote writes.** A `pending` skeleton approval
   combined with `--push`/`--cleanup` (`-Push`/`-Cleanup`) blocks with exit 2
   and the `SKELETON_APPROVAL_PENDING` marker, so a skeleton that nobody
   signed off can never ride a push to the remote. Without those flags a
   pending skeleton still runs the worker and the integrated check.

3. **The recorded integrated check is the final gate.** After worker and
   review stages pass, the coordinator runs the `Integrated check` command
   inside the worktree — under the container sandbox when `--sandbox` is
   active — with the same stdout/stderr routing rules as the worker. Failure
   marks the orchestration FAIL (exit 1) with
   `reason_code: SKELETON_CHECK_FAILED` in the JSON result and in
   `worker_completed`, logs the failure in text mode, and preserves the
   worktree.

4. **Success is observable as `skeleton_checkpoint`.** A passing check emits
   `{"event":"skeleton_checkpoint","worker_id":...,"working_directory":...,
   "check_exit_code":0}` before `worker_completed`. The event is emitted only
   on success, so `check_exit_code` is a `const: 0` and a failing check is
   reported exclusively through `worker_completed.reason_code`.
   `orchestration-events-v1` (five definitions) and `orchestration-result-v1`
   gained `SKELETON_CHECK_FAILED` in their reason-code enums; no existing
   event or result shape changed.

5. **Twin parity and optionality.** Both `coordinator.sh` and
   `coordinator.ps1` implement the flag, the section parser, the gates, and
   the stage with byte-identical text-mode messages (flags differ only as
   `--push`/`--cleanup` vs `-Push`/`-Cleanup`), covered by mirrored Bats and
   Pester tests. Runs without `--skeleton` behave byte-identically to the
   previous contract.

## Consequences

- (+) Every skeleton run proves a task-defined end-to-end slice after the
  worker, and the event stream records the proof as a first-class event.
- (+) Remote writes require a named, dated skeleton approval — the same
  "human owns the gate" pattern as `AG-N` approval gates.
- (+) Failures keep the worktree and report one unambiguous reason code in
  both text and JSON modes.
- (-) Orchestration grows a third optional stage (besides review and hooks)
  and a seventh early-block reason; task files used with `--skeleton` must
  carry the canonical section or the run refuses to start.
- (-) The section is ignored by `validate-task` (unknown sections are not
  validated), so its correctness is enforced only at orchestration time.
