# validate-skills.ps1 - skill-invocation validator tests (Pester 5, ADR-0014).
# The classifications are deterministic and language-independent:
# 0 = VALID, 1 = INVALID, 2 = BLOCKED. The cross-language parity section
# requires the Bash and PowerShell validators to produce identical exit codes
# for every shared fixture.

Describe 'validate-skills.ps1 skill-invocation validator' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:validate = Join-Path $repoRoot '.agentic' 'scripts' 'validate-skills.ps1'
        $fixtures = Join-Path $repoRoot 'tests' 'fixtures' 'skill-tasks'

        function Invoke-Validator([string]$fixture, [switch]$Handoff, [string]$Format) {
            $params = @{ TaskFile = (Join-Path $fixtures $fixture) }
            if ($Handoff) { $params.Handoff = $true }
            if ($Format) { $params.Format = $Format }
            $out = & $script:validate @params 2>&1
            return @{ Code = $LASTEXITCODE; Output = ($out | Out-String).Trim() }
        }
    }

    It 'VALID (0) for a single known invocation' {
        Invoke-Validator 'skill-valid-single.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for multiple distinct invocations' {
        Invoke-Validator 'skill-valid-multi.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for the None required sentinel' {
        Invoke-Validator 'skill-valid-none.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for a bare None required sentinel' {
        Invoke-Validator 'skill-valid-bare-none.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'INVALID (1) for an unknown skill id' {
        Invoke-Validator 'skill-unknown.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for a duplicate invocation' {
        Invoke-Validator 'skill-duplicate.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the invoked confirmation token is missing' {
        Invoke-Validator 'skill-missing-invoked-token.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for an invocation without a rationale' {
        Invoke-Validator 'skill-missing-rationale.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for an unrecognized invocation version' {
        Invoke-Validator 'skill-version-unsupported.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the task profile sits below the skill minimum' {
        Invoke-Validator 'skill-profile-too-low.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the Skills section is absent' {
        Invoke-Validator 'skill-section-missing.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) when the section has neither invocation nor sentinel' {
        Invoke-Validator 'skill-empty-section.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'BLOCKED (2) for a completed task with a placeholder rationale' {
        Invoke-Validator 'skill-done-placeholder.md' | Select-Object -ExpandProperty Code | Should -Be 2
    }

    It 'INVALID (1) when the sentinel coexists with invocations' {
        Invoke-Validator 'skill-sentinel-conflict.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'the None required sentinel rejects unresolved suffixes' {
        Invoke-Validator 'skill-none-tbd.md' | Select-Object -ExpandProperty Code | Should -Be 2
        Invoke-Validator 'skill-none-empty-rationale.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for an invocation hidden inside a fenced code block' {
        Invoke-Validator 'skill-fenced-selection.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It '--handoff rejects a task whose status is not done' {
        Invoke-Validator 'skill-valid-bare-none.md' -Handoff | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It '--handoff accepts a completed valid task' {
        Invoke-Validator 'skill-valid-single.md' -Handoff | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'JSON mode emits a schema-shaped document on success' {
        # Nested invocation: [Console]::Out in-process bypasses stream capture.
        $path = Join-Path $fixtures 'skill-valid-single.md'
        $raw = & pwsh -NoProfile -File $script:validate -Format Json $path 2>$null
        $LASTEXITCODE | Should -Be 0
        $doc = ("$raw" | ConvertFrom-Json)
        $doc.kind | Should -Be 'skill_validation_result'
        $doc.result | Should -Be 'VALID'
        $doc.exit_code | Should -Be 0
        $doc.protocol_version | Should -Be '1.11.0'
        @($doc.invoked_skills).Count | Should -Be 1
        $doc.invoked_skills[0].id | Should -Be 'verification-triage'
        $doc.invoked_skills[0].version | Should -Be 1
        @($doc.diagnostics).Count | Should -Be 0
    }

    It 'JSON mode carries the stable diagnostic code on failure' {
        $path = Join-Path $fixtures 'skill-unknown.md'
        $raw = & pwsh -NoProfile -File $script:validate -Format Json $path 2>$null
        $LASTEXITCODE | Should -Be 1
        $doc = ("$raw" | ConvertFrom-Json)
        $doc.result | Should -Be 'INVALID'
        $doc.exit_code | Should -Be 1
        @($doc.diagnostics).Count | Should -Be 1
        $doc.diagnostics[0].code | Should -Be 'SKILL_UNKNOWN'
        # JSON diagnostics deliberately redact task content: identifiers are
        # neutral (null/empty), never task-provided text.
        $doc.diagnostics[0].identifier | Should -BeNullOrEmpty
    }

    It 'BLOCKED (2) for an unusable registry with a malformed skill version' {
        $sb = Join-Path ([System.IO.Path]::GetTempPath()) ("skreg-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $sb 'broken-skill') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sb 'broken-skill' 'SKILL.md') -Value @('# Skill: broken', '', '## ID', '', 'broken-skill', '', '## Version', '', 'zero')
        $old = $env:AGENTIC_SKILLS_REGISTRY
        $env:AGENTIC_SKILLS_REGISTRY = $sb
        try {
            Invoke-Validator 'skill-valid-single.md' | Select-Object -ExpandProperty Code | Should -Be 2
        }
        finally {
            if ($null -eq $old) { Remove-Item Env:AGENTIC_SKILLS_REGISTRY -ErrorAction SilentlyContinue }
            else { $env:AGENTIC_SKILLS_REGISTRY = $old }
            Remove-Item -Recurse -Force $sb -ErrorAction SilentlyContinue
        }
    }
}

Describe 'validate-skills cross-language semantic parity' {

    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $validateSh = Join-Path $repoRoot '.agentic' 'scripts' 'validate-skills.sh'
        $validatePs = Join-Path $repoRoot '.agentic' 'scripts' 'validate-skills.ps1'
        $fixturesDir = Join-Path $repoRoot 'tests' 'fixtures' 'skill-tasks'

        $script:BashCmd = Get-Command "$env:ProgramFiles\Git\bin\bash.exe" -ErrorAction SilentlyContinue
        if (-not $script:BashCmd) { $script:BashCmd = Get-Command bash -ErrorAction SilentlyContinue }

        function ConvertTo-PosixPath([string]$windowsPath) {
            $posix = $windowsPath -replace '\\', '/'
            if ($posix -match '^([A-Za-z]):/(.*)$') { $posix = "/$($Matches[1].ToLowerInvariant())/$($Matches[2])" }
            return $posix
        }
    }

    It 'agrees on classification for every shared fixture' {
        if ($null -eq $script:BashCmd) {
            Set-ItResult -Skipped -Because 'bash (git-bash/WSL) is not available'
            return
        }
        if ($IsWindows) {
            # Same rationale as the context parity suite: the bash validator
            # re-validates the whole registry per invocation through per-line
            # subprocess spawns that cost ~50ms each under Git Bash on
            # Windows. The bash leg runs on the Ubuntu and macOS full-suite
            # legs instead.
            Set-ItResult -Skipped -Because 'bash-leg parity runs on the Ubuntu and macOS full-suite legs; Windows subprocess spawn costs make it prohibitively slow here'
            return
        }

        $env:VSKL_PARITY_VP = $validatePs
        $env:VSKL_PARITY_FD = $fixturesDir
        $env:VSKL_PARITY_VSH = $validateSh

        $psRows = @(& pwsh -NoProfile -Command '
            Get-ChildItem -LiteralPath $env:VSKL_PARITY_FD -Filter *.md |
                Sort-Object Name |
                ForEach-Object {
                    $out = & $env:VSKL_PARITY_VP $_.FullName 2>&1
                    $code = $LASTEXITCODE
                    "{0}`t{1}" -f $_.Name, $code
                }
        ')

        $posixDir = ConvertTo-PosixPath $fixturesDir
        $bashArg = if ($script:BashCmd.Source -like '*\System32\bash.exe') {
            $script:BashCmd.Source
        }
        else {
            ConvertTo-PosixPath $script:BashCmd.Source
        }
        $shRows = @(& $script:BashCmd.Source -c '
            for f in "$1"/*.md; do
                [ -e "$f" ] || continue
                "$2" "$VSKL_PARITY_VSH" "$f" >/dev/null 2>&1
                code=$?
                printf "%s\t%s\n" "$(basename "$f")" "$code"
            done
        ' _ "$posixDir" "$bashArg")

        Remove-Item Env:VSKL_PARITY_VP, Env:VSKL_PARITY_FD, Env:VSKL_PARITY_VSH -ErrorAction SilentlyContinue

        $psMap = @{}
        foreach ($row in $psRows) {
            if ("$row" -notmatch '\S') { continue }
            $parts = "$row" -split "`t", 2
            $psMap[$parts[0]] = [int]$parts[1]
        }
        $mismatches = @()
        foreach ($row in $shRows) {
            if ("$row" -notmatch '\S') { continue }
            $parts = "$row" -split "`t", 2
            $name = $parts[0]
            $shCode = [int]$parts[1]
            if (-not $psMap.ContainsKey($name)) {
                $mismatches += "${name}: missing from the PowerShell run"
                continue
            }
            if ($psMap[$name] -ne $shCode) {
                $mismatches += "{0}: sh={1} ps={2}" -f $name, $shCode, $psMap[$name]
            }
        }
        if ($mismatches.Count -gt 0) {
            throw "parity mismatches:`n" + ($mismatches -join "`n")
        }
    }
}
