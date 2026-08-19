#!/usr/bin/env bats

# validate-task.sh — risk-profile and evidence-contract validator tests.
# Runs against the fixture task files under tests/fixtures/tasks. Expected
# classifications are deterministic and language-independent:
#   0 = VALID, 1 = INVALID, 2 = BLOCKED.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
VALIDATE="$REPO_ROOT/.agentic/scripts/validate-task.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/tasks"

have() { command -v "$1" >/dev/null 2>&1; }

classify() {  # classify <fixture>
    run bash "$VALIDATE" "$FIXTURES/$1" >/dev/null 2>&1
}

@test "VALID (0) for a complete prototype task" {
    classify prototype-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a prototype task whose handoff lacks the production-readiness warning" {
    classify prototype-missing-warning.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a complete standard task" {
    classify standard-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a standard task missing its baseline verification" {
    classify standard-missing-baseline.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a complete high-assurance task" {
    classify high-assurance-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a high-assurance task missing risk analysis" {
    classify high-assurance-missing-risk-analysis.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a high-assurance task missing a recovery plan" {
    classify high-assurance-missing-recovery-plan.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a completed task with Pending required evidence" {
    classify completed-with-pending-evidence.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) for a task declaring an unknown profile" {
    classify unknown-profile.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a completed high-assurance task with approvals recorded" {
    classify high-assurance-completed-valid.md
    [ "$status" -eq 0 ]
}

@test "BLOCKED (2) for a completed high-assurance task lacking approval records" {
    classify high-assurance-completed-missing-approval.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when the task file does not exist" {
    run bash "$VALIDATE" "$FIXTURES/does-not-exist.md" >/dev/null 2>&1
    [ "$status" -eq 1 ]
}

@test "Bash and PowerShell classifiers agree on every fixture" {
    have pwsh || skip "pwsh not available"
    local f bash_code ps_code bash_out ps_out
    for f in "$FIXTURES"/*.md; do
        run bash "$VALIDATE" "$f"
        bash_code=$status
        bash_out="$output"
        run pwsh -NoProfile -File "$REPO_ROOT/.agentic/scripts/validate-task.ps1" "$f"
        ps_code=$status
        ps_out="$output"
        if [ "$bash_code" -ne "$ps_code" ]; then
            echo "classification mismatch for '$(basename "$f")': bash=$bash_code ps=$ps_code" >&2
            return 1
        fi
        if [ "$bash_out" != "$ps_out" ]; then
            echo "message mismatch for '$(basename "$f")'." >&2
            echo "  bash: $bash_out" >&2
            echo "  ps:   $ps_out" >&2
            return 1
        fi
    done
}

@test "INVALID (1) for a prototype task missing the no-production-deployment declaration" {
    classify prototype-missing-production-declaration.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for an in-progress standard task" {
    classify standard-in-progress.md
    [ "$status" -eq 0 ]
}

@test "BLOCKED (2) for --handoff on a task that is not done" {
    run bash "$VALIDATE" --handoff "$FIXTURES/standard-in-progress.md" >/dev/null 2>&1
    [ "$status" -eq 2 ]
}

@test "VALID (0) for --handoff on a done standard task" {
    run bash "$VALIDATE" --handoff "$FIXTURES/standard-valid.md" >/dev/null 2>&1
    [ "$status" -eq 0 ]
}

@test "BLOCKED (2) for a completed task with Partial required evidence" {
    classify completed-with-partial-evidence.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) for a completed task with a blank evidence result" {
    classify completed-with-blank-result.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when required evidence does not map every criterion" {
    classify unmapped-evidence.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when acceptance criteria repeat an identifier" {
    classify duplicate-ac.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an unrecognized status value" {
    classify unknown-status.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Status is declared more than once" {
    classify duplicate-status.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Profile is declared more than once" {
    classify duplicate-profile.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when all required words live in a single heading" {
    classify single-heading-all-words.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the profile heading is split" {
    classify split-headings.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Baseline is not scoped under Verification" {
    classify baseline-outside-verification.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when required headings are inside a fenced code block" {
    classify headings-in-fenced-code.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a completed task with an unchecked approval gate" {
    classify unchecked-gate.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when approval is negated rather than granted" {
    classify negated-approval.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when approval is recorded as not granted" {
    classify approval-not-granted.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when high-assurance evidence mapping omits a requirement" {
    classify high-assurance-unmapped-matrix.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an empty high-assurance risk analysis" {
    classify high-assurance-empty-risk-analysis.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when a high-assurance task declares None identified approvals" {
    classify high-assurance-none-identified.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) when required-evidence rows are reordered" {
    classify standard-reordered-evidence-valid.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) when requirement-to-evidence matrix rows are reordered" {
    classify high-assurance-reordered-matrix-valid.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for an all-uppercase Profile, Status, and Updated" {
    classify uppercase-profile-status-valid.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for mixed-case Profile and Status declarations" {
    classify mixed-case-profile-status-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) when Status is declared outside the Status section" {
    classify status-outside-status-section-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Profile is declared outside the Risk profile section" {
    classify profile-outside-risk-profile-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the Updated declaration is missing" {
    classify missing-updated-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an invalid Updated date" {
    classify invalid-updated-date.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a checked approval gate with placeholder values" {
    classify checked-placeholder-approval-blocked.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a checked approval gate with a real approver and date" {
    classify checked-real-approval-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) when a high-assurance section contains only a heading" {
    classify high-assurance-heading-only-risk-analysis-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when reordered evidence rows repeat a criterion" {
    classify duplicate-evidence-reordered.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the Status section is missing" {
    classify missing-status-section-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when the Updated declaration is duplicated" {
    classify duplicate-updated-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when Updated is declared outside the Status section" {
    classify updated-outside-status-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a checked approval gate with an invalid date" {
    classify invalid-approval-date-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when an approval gate identifier is declared more than once" {
    classify duplicate-gate-invalid.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for lowercase table, matrix, and approval identifiers" {
    classify lowercase-identifiers-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a completed task with an empty Baseline" {
    classify done-empty-baseline-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a completed task with an empty Final" {
    classify done-empty-final-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a completed task whose Final is only a placeholder" {
    classify done-placeholder-final-blocked.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) for a completed prototype with an empty Smoke verification" {
    classify prototype-empty-smoke-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a malformed approval entry in the gates list" {
    classify malformed-approval-entry-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when None identified is used as a substring, not a sentinel" {
    classify none-identified-substring-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for an Updated date with year 0000" {
    classify invalid-year-zero.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) when the Baseline keeps the template placeholder" {
    classify done-template-baseline-placeholder-blocked.md
    [ "$status" -eq 2 ]
}

@test "BLOCKED (2) when the Final keeps the template placeholder" {
    classify done-template-final-placeholder-blocked.md
    [ "$status" -eq 2 ]
}

@test "BLOCKED (2) when a completed prototype keeps the Smoke placeholder" {
    classify prototype-template-smoke-placeholder-blocked.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when a high-assurance section is a bracket placeholder" {
    classify high-assurance-bracket-placeholder-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a completed task with an empty Files changed" {
    classify done-empty-files-changed-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) when Files changed keeps the template placeholder" {
    classify done-placeholder-files-changed-blocked.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) for a completed task with an empty Remaining risks" {
    classify done-empty-remaining-risks-invalid.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) when Remaining risks states the None identified sentinel" {
    classify done-none-identified-remaining-risks-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a completed prototype with an empty Task goal" {
    classify prototype-empty-task-goal-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) for a completed prototype with empty Known limitations" {
    classify prototype-empty-known-limitations-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) when a + bullet approval gate remains unchecked" {
    classify plus-bullet-unchecked-gate-blocked.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when a + bullet checkbox is not a valid approval gate" {
    classify plus-bullet-malformed-gate-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when an approval records an earlier date before an invalid one" {
    classify approval-early-date-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) when an acceptance criterion keeps the template placeholder" {
    classify done-template-acceptance-criterion-blocked.md
    [ "$status" -eq 2 ]
}

@test "BLOCKED (2) when an evidence description is a placeholder" {
    classify done-placeholder-evidence-description-blocked.md
    [ "$status" -eq 2 ]
}

@test "BLOCKED (2) when a high-assurance requirement keeps the template placeholder" {
    classify high-assurance-template-requirement-blocked.md
    [ "$status" -eq 2 ]
}

@test "BLOCKED (2) when the profile rationale keeps the template instruction" {
    classify done-template-profile-rationale-blocked.md
    [ "$status" -eq 2 ]
}

@test "BLOCKED (2) when Files changed is a table of placeholders" {
    classify done-placeholder-files-table-blocked.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when a high-assurance section is a table of placeholders" {
    classify high-assurance-placeholder-risk-table-invalid.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) when a high-assurance section is a real table" {
    classify high-assurance-real-risk-table-valid.md
    [ "$status" -eq 0 ]
}

@test "BLOCKED (2) when every section is a punctuated placeholder" {
    classify done-tbd-period-everywhere-blocked.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when high-assurance approvals use the punctuated None identified sentinel" {
    classify high-assurance-none-identified-period-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) when the Final is a punctuated Pending placeholder" {
    classify done-pending-period-final-blocked.md
    [ "$status" -eq 2 ]
}

@test "VALID (0) when a real sentence merely mentions TBD as a word" {
    classify done-real-sentence-containing-tbd-valid.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for a lowercase acceptance criterion declaration" {
    classify lowercase-criterion-valid.md
    [ "$status" -eq 0 ]
}

@test "VALID (0) for a lowercase high-assurance requirement declaration" {
    classify lowercase-requirement-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) when one list entry declares multiple AC identifiers" {
    classify multiple-ac-ids-one-line-invalid.md
    [ "$status" -eq 1 ]
}

@test "INVALID (1) when one list entry declares multiple R identifiers" {
    classify multiple-r-ids-one-line-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) when the first criterion is a placeholder and the second is real" {
    classify first-id-placeholder-second-id-real-blocked.md
    [ "$status" -eq 2 ]
}

@test "INVALID (1) when an AC identifier appears only in prose" {
    classify criterion-id-mentioned-in-prose-invalid.md
    [ "$status" -eq 1 ]
}

@test "VALID (0) for a substantive n/a rationale" {
    classify na-evidence-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a bare n/a evidence cell" {
    classify na-evidence-bare-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a placeholder n/a rationale" {
    classify na-evidence-placeholder-blocked.md
    [ "$status" -eq 2 ]
}

@test "VALID (0) for a substantive n/a matrix rationale" {
    classify na-matrix-valid.md
    [ "$status" -eq 0 ]
}

@test "INVALID (1) for a bare n/a matrix cell" {
    classify na-matrix-bare-invalid.md
    [ "$status" -eq 1 ]
}

@test "BLOCKED (2) for a placeholder n/a matrix rationale" {
    classify na-matrix-placeholder-blocked.md
    [ "$status" -eq 2 ]
}