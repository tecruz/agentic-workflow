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
        $script:reportSh = Join-Path $repoRoot '.agentic' 'scripts' 'health-report.sh'

        function Invoke-HealthReport {
            $out = & pwsh -NoProfile -File $script:report 2>&1
            return @{ Code = $LASTEXITCODE; Text = ($out | Out-String).Trim() }
        }

        function Normalize-Report([string]$text) {
            $out = @()
            $inVersionBlock = $false
            foreach ($ln in ($text -split "`n")) {
                if ($ln -match '^[[:space:]]*$') { continue }
                if ($ln -match '^  \d{4}-\d{2}-\d{2} ') { continue }
                if ($ln -match 'VERSION Consistency') { $inVersionBlock = $true; continue }
                if ($inVersionBlock -and $ln -match 'Recent Task Changes') {
                    $inVersionBlock = $false
                    $out += $ln
                    continue
                }
                if (-not $inVersionBlock) { $out += $ln }
            }
            return ($out -join "`n")
        }

        function Get-EmitterNames([string]$text) {
            $names = @()
            $inVersionBlock = $false
            foreach ($ln in ($text -split "`n")) {
                if ($ln -match 'VERSION Consistency') { $inVersionBlock = $true; continue }
                if ($ln -match 'Recent Task Changes') { break }
                if ($inVersionBlock -and $ln -match '^    ([^:]+): [0-9]') { $names += $Matches[1].Trim() }
            }
            return (($names | Sort-Object) -join ',')
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

    It 'bash and pwsh twins emit identical normalized output (parity)' {
        if ($IsWindows) {
            Set-ItResult -Skipped -Because 'bash-leg parity runs on the Ubuntu and macOS full-suite legs'
            return
        }
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($null -eq $bash) {
            Set-ItResult -Skipped -Because 'bash not available'
            return
        }
        $shOut = (& $bash.Source $script:reportSh 2>&1 | Out-String).Trim()
        $psOut = (Invoke-HealthReport).Text
        Normalize-Report $shOut | Should -Be (Normalize-Report $psOut) -Because 'the twins must render identical normalized output'
        Get-EmitterNames $shOut | Should -Be (Get-EmitterNames $psOut) -Because 'the twins must scan the same emitter set'
        $psOut | Should -Match 'Status: CONSISTENT'
    }
}
