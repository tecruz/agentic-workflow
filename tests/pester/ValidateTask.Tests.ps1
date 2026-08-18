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
            $psCode = Invoke-Validator $_.Name
            bash $bashValidator $_.FullName *> $null
            $bashCode = $LASTEXITCODE
            $psCode | Should -Be $bashCode
        }
    }
}