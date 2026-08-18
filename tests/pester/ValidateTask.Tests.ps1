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