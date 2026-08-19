# validate-task.ps1 — risk-profile and evidence-contract validator tests
# (Pester 5). The classifications are deterministic and language-independent:
# 0 = VALID, 1 = INVALID, 2 = BLOCKED.

Describe 'validate-task.ps1 risk-profile validator' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $validate = Join-Path $repoRoot '.agentic' 'scripts' 'validate-task.ps1'
        $fixtures = Join-Path $repoRoot 'tests' 'fixtures' 'tasks'

        function Invoke-Validator([string]$fixture) {
            $out = & $validate (Join-Path $fixtures $fixture) 2>&1
            $code = $LASTEXITCODE
            if ($code -ne 0) {
                Write-Host "--- VALIDATE FAILED (exit $code) ---"
                $out | ForEach-Object { Write-Host $_ }
                Write-Host "------------------------------------"
            }
            return $code
        }
    }

    It 'VALID (0) for a complete prototype task' {
        Invoke-Validator 'prototype-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a prototype task whose handoff lacks the production-readiness warning' {
        Invoke-Validator 'prototype-missing-warning.md' | Should -Be 1
    }

    It 'VALID (0) for a complete standard task' {
        Invoke-Validator 'standard-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a standard task missing its baseline verification' {
        Invoke-Validator 'standard-missing-baseline.md' | Should -Be 1
    }

    It 'VALID (0) for a complete high-assurance task' {
        Invoke-Validator 'high-assurance-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a high-assurance task missing risk analysis' {
        Invoke-Validator 'high-assurance-missing-risk-analysis.md' | Should -Be 1
    }

    It 'INVALID (1) for a high-assurance task missing a recovery plan' {
        Invoke-Validator 'high-assurance-missing-recovery-plan.md' | Should -Be 1
    }

    It 'BLOCKED (2) for a completed task with Pending required evidence' {
        Invoke-Validator 'completed-with-pending-evidence.md' | Should -Be 2
    }

    It 'INVALID (1) for a task declaring an unknown profile' {
        Invoke-Validator 'unknown-profile.md' | Should -Be 1
    }

    It 'VALID (0) for a completed high-assurance task with approvals recorded' {
        Invoke-Validator 'high-assurance-completed-valid.md' | Should -Be 0
    }

    It 'BLOCKED (2) for a completed high-assurance task lacking approval records' {
        Invoke-Validator 'high-assurance-completed-missing-approval.md' | Should -Be 2
    }

    It 'INVALID (1) when the task file does not exist' {
        & $validate (Join-Path $fixtures 'does-not-exist.md') *> $null
        $LASTEXITCODE | Should -Be 1
    }

    It 'INVALID (1) for a prototype task missing the no-production-deployment declaration' {
        Invoke-Validator 'prototype-missing-production-declaration.md' | Should -Be 1
    }

    It 'VALID (0) for an in-progress standard task' {
        Invoke-Validator 'standard-in-progress.md' | Should -Be 0
    }

    It 'BLOCKED (2) for -Handoff on a task that is not done' {
        & $validate -Handoff (Join-Path $fixtures 'standard-in-progress.md') *> $null
        $LASTEXITCODE | Should -Be 2
    }

    It 'VALID (0) for -Handoff on a done standard task' {
        & $validate -Handoff (Join-Path $fixtures 'standard-valid.md') *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'BLOCKED (2) for a completed task with Partial required evidence' {
        Invoke-Validator 'completed-with-partial-evidence.md' | Should -Be 2
    }

    It 'INVALID (1) for a completed task with a blank evidence result' {
        Invoke-Validator 'completed-with-blank-result.md' | Should -Be 1
    }

    It 'INVALID (1) when required evidence does not map every criterion' {
        Invoke-Validator 'unmapped-evidence.md' | Should -Be 1
    }

    It 'INVALID (1) when acceptance criteria repeat an identifier' {
        Invoke-Validator 'duplicate-ac.md' | Should -Be 1
    }

    It 'INVALID (1) for an unrecognized status value' {
        Invoke-Validator 'unknown-status.md' | Should -Be 1
    }

    It 'INVALID (1) when Status is declared more than once' {
        Invoke-Validator 'duplicate-status.md' | Should -Be 1
    }

    It 'INVALID (1) when Profile is declared more than once' {
        Invoke-Validator 'duplicate-profile.md' | Should -Be 1
    }

    It 'INVALID (1) when all required words live in a single heading' {
        Invoke-Validator 'single-heading-all-words.md' | Should -Be 1
    }

    It 'INVALID (1) when the profile heading is split' {
        Invoke-Validator 'split-headings.md' | Should -Be 1
    }

    It 'INVALID (1) when Baseline is not scoped under Verification' {
        Invoke-Validator 'baseline-outside-verification.md' | Should -Be 1
    }

    It 'INVALID (1) when required headings are inside a fenced code block' {
        Invoke-Validator 'headings-in-fenced-code.md' | Should -Be 1
    }

    It 'BLOCKED (2) for a completed task with an unchecked approval gate' {
        Invoke-Validator 'unchecked-gate.md' | Should -Be 2
    }

    It 'INVALID (1) when approval is negated rather than granted' {
        Invoke-Validator 'negated-approval.md' | Should -Be 1
    }

    It 'INVALID (1) when approval is recorded as not granted' {
        Invoke-Validator 'approval-not-granted.md' | Should -Be 1
    }

    It 'INVALID (1) when high-assurance evidence mapping omits a requirement' {
        Invoke-Validator 'high-assurance-unmapped-matrix.md' | Should -Be 1
    }

    It 'INVALID (1) for an empty high-assurance risk analysis' {
        Invoke-Validator 'high-assurance-empty-risk-analysis.md' | Should -Be 1
    }

    It 'INVALID (1) when a high-assurance task declares None identified approvals' {
        Invoke-Validator 'high-assurance-none-identified.md' | Should -Be 1
    }

    It 'VALID (0) when required-evidence rows are reordered' {
        Invoke-Validator 'standard-reordered-evidence-valid.md' | Should -Be 0
    }

    It 'VALID (0) when requirement-to-evidence matrix rows are reordered' {
        Invoke-Validator 'high-assurance-reordered-matrix-valid.md' | Should -Be 0
    }

    It 'VALID (0) for an all-uppercase Profile, Status, and Updated' {
        Invoke-Validator 'uppercase-profile-status-valid.md' | Should -Be 0
    }

    It 'VALID (0) for mixed-case Profile and Status declarations' {
        Invoke-Validator 'mixed-case-profile-status-valid.md' | Should -Be 0
    }

    It 'INVALID (1) when Status is declared outside the Status section' {
        Invoke-Validator 'status-outside-status-section-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when Profile is declared outside the Risk profile section' {
        Invoke-Validator 'profile-outside-risk-profile-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when the Updated declaration is missing' {
        Invoke-Validator 'missing-updated-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) for an invalid Updated date' {
        Invoke-Validator 'invalid-updated-date.md' | Should -Be 1
    }

    It 'INVALID (1) for a checked approval gate with placeholder values' {
        Invoke-Validator 'checked-placeholder-approval-blocked.md' | Should -Be 1
    }

    It 'VALID (0) for a checked approval gate with a real approver and date' {
        Invoke-Validator 'checked-real-approval-valid.md' | Should -Be 0
    }

    It 'INVALID (1) when a high-assurance section contains only a heading' {
        Invoke-Validator 'high-assurance-heading-only-risk-analysis-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when reordered evidence rows repeat a criterion' {
        Invoke-Validator 'duplicate-evidence-reordered.md' | Should -Be 1
    }

    It 'INVALID (1) when the Status section is missing' {
        Invoke-Validator 'missing-status-section-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when the Updated declaration is duplicated' {
        Invoke-Validator 'duplicate-updated-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when Updated is declared outside the Status section' {
        Invoke-Validator 'updated-outside-status-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) for a checked approval gate with an invalid date' {
        Invoke-Validator 'invalid-approval-date-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when an approval gate identifier is declared more than once' {
        Invoke-Validator 'duplicate-gate-invalid.md' | Should -Be 1
    }

    It 'VALID (0) for lowercase table, matrix, and approval identifiers' {
        Invoke-Validator 'lowercase-identifiers-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a completed task with an empty Baseline' {
        Invoke-Validator 'done-empty-baseline-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) for a completed task with an empty Final' {
        Invoke-Validator 'done-empty-final-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) for a completed task whose Final is only a placeholder' {
        Invoke-Validator 'done-placeholder-final-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) for a completed prototype with an empty Smoke verification' {
        Invoke-Validator 'prototype-empty-smoke-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) for a malformed approval entry in the gates list' {
        Invoke-Validator 'malformed-approval-entry-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when None identified is used as a substring, not a sentinel' {
        Invoke-Validator 'none-identified-substring-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) for an Updated date with year 0000' {
        Invoke-Validator 'invalid-year-zero.md' | Should -Be 1
    }

    It 'BLOCKED (2) when the Baseline keeps the template placeholder' {
        Invoke-Validator 'done-template-baseline-placeholder-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when the Final keeps the template placeholder' {
        Invoke-Validator 'done-template-final-placeholder-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when a completed prototype keeps the Smoke placeholder' {
        Invoke-Validator 'prototype-template-smoke-placeholder-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when a high-assurance section is a bracket placeholder' {
        Invoke-Validator 'high-assurance-bracket-placeholder-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) for a completed task with an empty Files changed' {
        Invoke-Validator 'done-empty-files-changed-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when Files changed keeps the template placeholder' {
        Invoke-Validator 'done-placeholder-files-changed-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) for a completed task with an empty Remaining risks' {
        Invoke-Validator 'done-empty-remaining-risks-invalid.md' | Should -Be 1
    }

    It 'VALID (0) when Remaining risks states the None identified sentinel' {
        Invoke-Validator 'done-none-identified-remaining-risks-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a completed prototype with an empty Task goal' {
        Invoke-Validator 'prototype-empty-task-goal-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) for a completed prototype with empty Known limitations' {
        Invoke-Validator 'prototype-empty-known-limitations-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when a + bullet approval gate remains unchecked' {
        Invoke-Validator 'plus-bullet-unchecked-gate-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when a + bullet checkbox is not a valid approval gate' {
        Invoke-Validator 'plus-bullet-malformed-gate-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when an approval records an earlier date before an invalid one' {
        Invoke-Validator 'approval-early-date-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when an acceptance criterion keeps the template placeholder' {
        Invoke-Validator 'done-template-acceptance-criterion-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when an evidence description is a placeholder' {
        Invoke-Validator 'done-placeholder-evidence-description-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when a high-assurance requirement keeps the template placeholder' {
        Invoke-Validator 'high-assurance-template-requirement-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when the profile rationale keeps the template instruction' {
        Invoke-Validator 'done-template-profile-rationale-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when Files changed is a table of placeholders' {
        Invoke-Validator 'done-placeholder-files-table-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when a high-assurance section is a table of placeholders' {
        Invoke-Validator 'high-assurance-placeholder-risk-table-invalid.md' | Should -Be 1
    }

    It 'VALID (0) when a high-assurance section is a real table' {
        Invoke-Validator 'high-assurance-real-risk-table-valid.md' | Should -Be 0
    }

    It 'BLOCKED (2) when every section is a punctuated placeholder' {
        Invoke-Validator 'done-tbd-period-everywhere-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when high-assurance approvals use the punctuated None identified sentinel' {
        Invoke-Validator 'high-assurance-none-identified-period-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when the Final is a punctuated Pending placeholder' {
        Invoke-Validator 'done-pending-period-final-blocked.md' | Should -Be 2
    }

    It 'VALID (0) when a real sentence merely mentions TBD as a word' {
        Invoke-Validator 'done-real-sentence-containing-tbd-valid.md' | Should -Be 0
    }

    It 'VALID (0) for a lowercase acceptance criterion declaration' {
        Invoke-Validator 'lowercase-criterion-valid.md' | Should -Be 0
    }

    It 'VALID (0) for a lowercase high-assurance requirement declaration' {
        Invoke-Validator 'lowercase-requirement-valid.md' | Should -Be 0
    }

    It 'INVALID (1) when one list entry declares multiple AC identifiers' {
        Invoke-Validator 'multiple-ac-ids-one-line-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when one list entry declares multiple R identifiers' {
        Invoke-Validator 'multiple-r-ids-one-line-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when the first criterion is a placeholder and the second is real' {
        Invoke-Validator 'first-id-placeholder-second-id-real-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when an AC identifier appears only in prose' {
        Invoke-Validator 'criterion-id-mentioned-in-prose-invalid.md' | Should -Be 1
    }

    It 'VALID (0) for a substantive n/a rationale' {
        Invoke-Validator 'na-evidence-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a bare n/a evidence cell' {
        Invoke-Validator 'na-evidence-bare-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) for a placeholder n/a rationale' {
        Invoke-Validator 'na-evidence-placeholder-blocked.md' | Should -Be 2
    }

    It 'VALID (0) for a substantive n/a matrix rationale' {
        Invoke-Validator 'na-matrix-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a bare n/a matrix cell' {
        Invoke-Validator 'na-matrix-bare-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) for a placeholder n/a matrix rationale' {
        Invoke-Validator 'na-matrix-placeholder-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when the approval section contains unrecognized plain prose' {
        Invoke-Validator 'approval-plain-prose-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when None identified approvals are followed by unresolved prose' {
        Invoke-Validator 'none-plus-pending-prose-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a checked approval gate is followed by unresolved prose' {
        Invoke-Validator 'checked-gate-plus-pending-prose-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when an acceptance criterion list entry has no AC identifier' {
        Invoke-Validator 'unnumbered-criterion-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a high-assurance requirement list entry has no R identifier' {
        Invoke-Validator 'unnumbered-requirement-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a valid criterion is followed by an unnumbered bullet' {
        Invoke-Validator 'valid-criterion-plus-unnumbered-bullet-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a valid requirement is followed by an unnumbered bullet' {
        Invoke-Validator 'valid-requirement-plus-unnumbered-bullet-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a section holds two consecutive empty tables' {
        Invoke-Validator 'consecutive-empty-tables-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when a completed section contains only punctuation' {
        Invoke-Validator 'done-punctuation-only-content-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when an evidence cell is only punctuation' {
        Invoke-Validator 'punctuation-only-evidence-cell-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when an n/a rationale is only punctuation' {
        Invoke-Validator 'na-punctuation-only-rationale-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a checked approval approver is only punctuation' {
        Invoke-Validator 'checked-punctuation-only-approver-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when a Files changed table row is only punctuation' {
        Invoke-Validator 'punctuation-only-table-row-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when required evidence contains an unknown ID' {
        Invoke-Validator 'required-evidence-unknown-id-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when required evidence contains an extra column' {
        Invoke-Validator 'required-evidence-extra-column-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when required evidence contains a malformed ID' {
        Invoke-Validator 'required-evidence-malformed-id-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when required evidence hides a duplicate unresolved row' {
        Invoke-Validator 'required-evidence-hidden-unresolved-duplicate-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when the requirement matrix contains an unknown ID' {
        Invoke-Validator 'requirement-matrix-unknown-id-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when the requirement matrix contains an extra column' {
        Invoke-Validator 'requirement-matrix-extra-column-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when a completed section contains only underscores' {
        Invoke-Validator 'done-underscore-only-content-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) when an evidence cell is only underscores' {
        Invoke-Validator 'underscore-only-evidence-cell-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when an n/a rationale is symbol-only' {
        Invoke-Validator 'na-symbol-only-rationale-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a checked approval approver is symbol-only' {
        Invoke-Validator 'checked-underscore-only-approver-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a high-assurance risk table is symbol-only' {
        Invoke-Validator 'symbol-only-risk-table-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a malformed row is used as the evidence header' {
        Invoke-Validator 'required-evidence-malformed-row-as-header-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when an unknown unresolved row is used as the evidence header' {
        Invoke-Validator 'required-evidence-unknown-row-as-header-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when a malformed row is used as the matrix header' {
        Invoke-Validator 'requirement-matrix-malformed-row-as-header-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when an evidence row omits its leading pipe' {
        Invoke-Validator 'required-evidence-row-without-leading-pipe-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) for a completed task whose profile rationale is a bold-wrapped TBD' {
        Invoke-Validator 'done-bold-tbd-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) for a completed task whose Final is a code-wrapped Pending' {
        Invoke-Validator 'done-code-wrapped-pending-blocked.md' | Should -Be 2
    }

    It 'BLOCKED (2) for a completed task whose Baseline is an underscore-suffixed TBD' {
        Invoke-Validator 'done-tbd-underscore-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when an n/a rationale is a Markdown-wrapped placeholder' {
        Invoke-Validator 'na-markdown-placeholder-rationale-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) when an acceptance criterion is a bracket placeholder with a suffix' {
        Invoke-Validator 'criterion-bracket-placeholder-with-suffix-blocked.md' | Should -Be 2
    }

    It 'INVALID (1) when required evidence has a no-leading-pipe row with an empty result' {
        Invoke-Validator 'required-evidence-empty-cell-no-leading-pipe-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when required evidence has a no-leading-pipe row with a missing column' {
        Invoke-Validator 'required-evidence-missing-column-no-leading-pipe-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when required evidence hides a pending row with an empty cell' {
        Invoke-Validator 'required-evidence-hidden-pending-empty-cell-invalid.md' | Should -Be 1
    }

    It 'INVALID (1) when the requirement matrix has a no-leading-pipe row with an empty cell' {
        Invoke-Validator 'requirement-matrix-empty-cell-no-leading-pipe-invalid.md' | Should -Be 1
    }

    It 'BLOCKED (2) for a completed prototype with an unchecked approval gate' {
        Invoke-Validator 'prototype-unchecked-gate-blocked.md' | Should -Be 2
    }

    It 'VALID (0) for a completed prototype with a checked approval gate' {
        Invoke-Validator 'prototype-checked-gate-valid.md' | Should -Be 0
    }

    It 'INVALID (1) for a completed prototype with a malformed approval gate' {
        Invoke-Validator 'prototype-malformed-gate-invalid.md' | Should -Be 1
    }

    It 'VALID (0) for a completed prototype with None identified approval gates' {
        Invoke-Validator 'prototype-none-identified-valid.md' | Should -Be 0
    }

    It 'VALID (0) for non-ASCII meaningful content' {
        Invoke-Validator 'unicode-content-valid.md' | Should -Be 0
    }

    It 'PowerShell and Bash classifiers agree on every fixture' {
        if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { return }
        # Probe: bash must be able to invoke the validator and read the
        # fixtures. On Windows hosts where 'bash' is WSL, Windows paths are
        # not resolvable; in that case skip the cross-language comparison.
        $bashValidator = Join-Path $repoRoot '.agentic' 'scripts' 'validate-task.sh'
        $probeFixture = Join-Path $fixtures 'prototype-valid.md'
        bash $bashValidator $probeFixture *> $null
        if ($LASTEXITCODE -notin 0, 1, 2) { return }
        Get-ChildItem -LiteralPath $fixtures -Filter *.md | ForEach-Object {
            # Run both validators as subprocesses so their stderr is captured:
            # the PowerShell validator writes failures via [Console]::Error,
            # which PowerShell stream redirection does not capture in-process.
            $psOut = (pwsh -NoProfile -File $validate (Join-Path $fixtures $_.Name) 2>&1 | Out-String)
            $psCode = $LASTEXITCODE
            $bashOut = (bash $bashValidator $_.FullName 2>&1 | Out-String)
            $bashCode = $LASTEXITCODE
            $psCode | Should -Be $bashCode
            $psOut.Trim() | Should -Be $bashOut.Trim()
        }
    }
}