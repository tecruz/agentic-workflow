# validate-context.ps1 - context-module selection validator tests (Pester 5).
# The classifications are deterministic and language-independent:
# 0 = VALID, 1 = INVALID, 2 = BLOCKED. The cross-language parity section
# requires the Bash and PowerShell validators to produce identical exit codes
# and identical first-line messages for every shared fixture.

Describe 'validate-context.ps1 context-selection validator' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:validate = Join-Path $repoRoot '.agentic' 'scripts' 'validate-context.ps1'
        $fixtures = Join-Path $repoRoot 'tests' 'fixtures' 'context-tasks'

        function Invoke-Validator([string]$fixture, [switch]$Handoff, [string]$Format) {
            $params = @{ TaskFile = (Join-Path $fixtures $fixture) }
            if ($Handoff) { $params.Handoff = $true }
            if ($Format) { $params.Format = $Format }
            $out = & $script:validate @params 2>&1
            return @{ Code = $LASTEXITCODE; Output = ($out | Out-String).Trim() }
        }
    }

    It 'VALID (0) for a single known selection' {
        Invoke-Validator 'context-valid-single.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for multiple distinct selections' {
        Invoke-Validator 'context-valid-multi.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for the None selected sentinel' {
        Invoke-Validator 'context-valid-none.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for a bare None selected sentinel' {
        Invoke-Validator 'context-valid-bare-none.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'INVALID (1) for an unknown module id' {
        Invoke-Validator 'context-unknown-module.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for a duplicate selection' {
        Invoke-Validator 'context-duplicate-module.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the loaded confirmation token is missing' {
        Invoke-Validator 'context-missing-loaded-token.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for a selection without a rationale' {
        Invoke-Validator 'context-missing-rationale.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for an unrecognized selection version' {
        Invoke-Validator 'context-version-unsupported.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the task profile sits below the module minimum' {
        Invoke-Validator 'context-profile-too-low.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the Context modules section is absent' {
        Invoke-Validator 'context-section-missing.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the section has neither selection nor sentinel' {
        Invoke-Validator 'context-empty-section.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'BLOCKED (2) for a completed task with a placeholder rationale' {
        Invoke-Validator 'context-done-placeholder.md' | Select-Object -ExpandProperty Code | Should -Be 2
    }

    It 'INVALID (1) when the sentinel coexists with selections' {
        Invoke-Validator 'context-sentinel-conflict.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It '--handoff rejects a task whose status is not done' {
        Invoke-Validator 'context-valid-bare-none.md' -Handoff | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It '--handoff accepts a completed valid task' {
        Invoke-Validator 'context-valid-single.md' -Handoff | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'JSON mode emits a schema-shaped document on success' {
        # Nested invocation: [Console]::Out in-process bypasses stream capture.
        $path = Join-Path $fixtures 'context-valid-single.md'
        $raw = & pwsh -NoProfile -File $script:validate -Format Json $path 2>$null
        $LASTEXITCODE | Should -Be 0
        $doc = ("$raw" | ConvertFrom-Json)
        $doc.kind | Should -Be 'context_validation_result'
        $doc.result | Should -Be 'VALID'
        $doc.exit_code | Should -Be 0
        $doc.protocol_version | Should -Be '1.5.0'
        @($doc.selected_modules).Count | Should -Be 1
        $doc.selected_modules[0].id | Should -Be 'security-review'
        $doc.selected_modules[0].version | Should -Be 1
        @($doc.diagnostics).Count | Should -Be 0
    }

    It 'JSON mode carries the stable diagnostic code on failure' {
        $path = Join-Path $fixtures 'context-unknown-module.md'
        $raw = & pwsh -NoProfile -File $script:validate -Format Json $path 2>$null
        $LASTEXITCODE | Should -Be 1
        $doc = ("$raw" | ConvertFrom-Json)
        $doc.result | Should -Be 'INVALID'
        $doc.exit_code | Should -Be 1
        @($doc.diagnostics).Count | Should -Be 1
        $doc.diagnostics[0].code | Should -Be 'MODULE_UNKNOWN'
        $doc.diagnostics[0].identifier | Should -Be 'mystery-module'
    }
}

Describe 'validate-context cross-language semantic parity' {

    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $validateSh = Join-Path $repoRoot '.agentic' 'scripts' 'validate-context.sh'
        $validatePs = Join-Path $repoRoot '.agentic' 'scripts' 'validate-context.ps1'
        $fixturesDir = Join-Path $repoRoot 'tests' 'fixtures' 'context-tasks'

        $script:BashCmd = Get-Command "$env:ProgramFiles\Git\bin\bash.exe" -ErrorAction SilentlyContinue
        if (-not $script:BashCmd) { $script:BashCmd = Get-Command bash -ErrorAction SilentlyContinue }

        function ConvertTo-PosixPath([string]$windowsPath) {
            $posix = $windowsPath -replace '\\', '/'
            if ($posix -match '^([A-Za-z]):/(.*)$') { $posix = "/$($Matches[1].ToLowerInvariant())/$($Matches[2])" }
            return $posix
        }
    }

    It 'agrees on classification and message for every shared fixture' {
        if ($null -eq $script:BashCmd) {
            Set-ItResult -Skipped -Because 'bash (git-bash/WSL) is not available'
            return
        }
        $mismatches = @()
        foreach ($fixture in (Get-ChildItem -LiteralPath $fixturesDir -Filter '*.md' | Sort-Object Name)) {
            $psOut = & pwsh -NoProfile -File $validatePs $fixture.FullName 2>&1
            $psCode = $LASTEXITCODE
            $psFirst = "$(@($psOut) | Select-Object -First 1)"

            $posix = ConvertTo-PosixPath $fixture.FullName
            $shOut = & $script:BashCmd.Source $validateSh $posix 2>&1
            $shCode = $LASTEXITCODE
            $shFirst = "$(@($shOut) | Select-Object -First 1)"

            if ($psCode -ne $shCode -or $psFirst -cne $shFirst) {
                $mismatches += "{0}: sh={1}/{2} ps={3}/{4}" -f $fixture.Name, $shCode, $shFirst, $psCode, $psFirst
            }
        }
        if ($mismatches.Count -gt 0) {
            throw "parity mismatches:`n" + ($mismatches -join "`n")
        }
    }
}
