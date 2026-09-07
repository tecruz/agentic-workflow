# health-report.ps1 - project health summary smoke tests (Pester 5).
# The report is informational (always exit 0); these tests assert the
# sections render and the VERSION consistency check sees every emitter
# twin plus the eval runner, mirroring tests/bats/health_report_test.bats.
# The script is invoked as a child process because it terminates with
# `exit 0` and writes its report through Write-Host (information stream).

Describe 'health-report.ps1 project health summary' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:report = Join-Path $repoRoot '.agentic' 'scripts' 'health-report.ps1'

        function Invoke-HealthReport {
            $out = & pwsh -NoProfile -File $script:report 2>&1
            return @{ Code = $LASTEXITCODE; Text = ($out | Out-String).Trim() }
        }
    }

    It 'exits 0 and renders the expected sections' {
        $r = Invoke-HealthReport
        $r.Code | Should -Be 0
        $r.Text | Should -Match 'Agentic Workflow Health Report'
        $r.Text | Should -Match '── Tasks'
        $r.Text | Should -Match '── Context Module Usage'
        $r.Text | Should -Match '── Skill Invocation Usage'
        $r.Text | Should -Match '── Profile Distribution'
        $r.Text | Should -Match '── VERSION Consistency'
        $r.Text | Should -Match '── Recent Task Changes'
        $r.Text | Should -Match 'Report complete'
    }

    It 'VERSION consistency covers Bash and PowerShell emitters' {
        $r = Invoke-HealthReport
        $r.Text | Should -Match 'verify\.sh:'
        $r.Text | Should -Match 'verify\.ps1:'
        $r.Text | Should -Match 'coordinator\.sh:'
        $r.Text | Should -Match 'coordinator\.ps1:'
        $r.Text | Should -Match 'Status: CONSISTENT'
    }

    It 'reports the repository own version' {
        $r = Invoke-HealthReport
        $expected = (Get-Content -Raw (Join-Path $repoRoot '.agentic' 'VERSION')).Trim()
        $r.Text | Should -Match ([regex]::Escape(" .agentic/VERSION: $expected"))
    }
}
