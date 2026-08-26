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

        # Batched execution: exactly one child process per language covers the
        # whole corpus. Per-fixture spawns cost minutes under CI/job hosts.
        # The validators emit through [Console]::Out/Error, so the PowerShell
        # leg must redirect those streams around each in-process call — a
        # plain 2>&1 merge cannot see them — and read the script's exit code
        # from $LASTEXITCODE afterwards ('exit' inside an invoked script file
        # sets it without terminating this child).
        $env:VCTX_PARITY_VP = $validatePs
        $env:VCTX_PARITY_FD = $fixturesDir
        $env:VCTX_PARITY_VSH = $validateSh

        $psRows = @(& pwsh -NoProfile -Command '
            Get-ChildItem -LiteralPath $env:VCTX_PARITY_FD -Filter *.md |
                Sort-Object Name |
                ForEach-Object {
                    $swOut = [System.IO.StringWriter]::new()
                    $swErr = [System.IO.StringWriter]::new()
                    $oldOut = [Console]::Out
                    $oldErr = [Console]::Error
                    [Console]::SetOut($swOut)
                    [Console]::SetError($swErr)
                    try { & $env:VCTX_PARITY_VP $_.FullName }
                    finally {
                        [Console]::SetOut($oldOut)
                        [Console]::SetError($oldErr)
                    }
                    $code = $LASTEXITCODE
                    $combined = ($swOut.ToString() + $swErr.ToString()) -replace "`r", ""
                    $first = ($combined -split "`n")[0]
                    "{0}`t{1}`t{2}" -f $_.Name, $code, $first
                }
        ')

        $posixDir = ConvertTo-PosixPath $fixturesDir
        $shRows = @(& $script:BashCmd.Source -c '
            for f in "$1"/*.md; do
                [ -e "$f" ] || continue
                out="$(bash "$VCTX_PARITY_VSH" "$f" 2>&1)"
                code=$?
                first="$(printf "%s" "$out" | head -n 1)"
                printf "%s\t%s\t%s\n" "$(basename "$f")" "$code" "$first"
            done
        ' _ "$posixDir")

        Remove-Item Env:VCTX_PARITY_VP, Env:VCTX_PARITY_FD, Env:VCTX_PARITY_VSH -ErrorAction SilentlyContinue

        $psMap = @{}
        foreach ($row in $psRows) {
            if ("$row" -notmatch '\S') { continue }
            $parts = "$row" -split "`t", 3
            $psMap[$parts[0]] = @{ Code = [int]$parts[1]; First = $parts[2] }
        }
        $mismatches = @()
        foreach ($row in $shRows) {
            if ("$row" -notmatch '\S') { continue }
            $parts = "$row" -split "`t", 3
            $name = $parts[0]
            $shCode = [int]$parts[1]
            $shFirst = $parts[2]
            if (-not $psMap.ContainsKey($name)) {
                $mismatches += "${name}: missing from the PowerShell run"
                continue
            }
            if ($psMap[$name].Code -ne $shCode -or $psMap[$name].First -cne $shFirst) {
                $mismatches += "{0}: sh={1}/{2} ps={3}/{4}" -f $name, $shCode, $shFirst, $psMap[$name].Code, $psMap[$name].First
            }
        }
        if ($mismatches.Count -gt 0) {
            throw "parity mismatches:`n" + ($mismatches -join "`n")
        }
    }
}


Describe 'validate-context review-blocker regressions' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:vctx = Join-Path $repoRoot '.agentic' 'scripts' 'validate-context.ps1'
        $script:vhand = Join-Path $repoRoot '.agentic' 'scripts' 'validate-handoff.ps1'
        $fixtures = Join-Path $repoRoot 'tests' 'fixtures' 'context-tasks'

        function Invoke-Ctx([string]$fixture, [string]$registry = $null, [switch]$Json) {
            $old = $env:AGENTIC_CONTEXT_REGISTRY
            if ($registry) { $env:AGENTIC_CONTEXT_REGISTRY = $registry }
            try {
                $call = @{ TaskFile = (Join-Path $fixtures $fixture) }
                if ($Json) { $call.Format = 'Json' }
                $out = & pwsh -NoProfile -File $script:vctx @call 2>&1
                return @{ Code = $LASTEXITCODE; Output = ($out | Out-String).Trim() }
            }
            finally {
                if ($null -eq $old) { Remove-Item Env:AGENTIC_CONTEXT_REGISTRY -ErrorAction SilentlyContinue }
                else { $env:AGENTIC_CONTEXT_REGISTRY = $old }
            }
        }

        function New-SandboxModule([string]$registry, [string]$dirname, [string]$id, [string]$version, [string]$minProfile) {
            $dir = Join-Path $registry $dirname
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $lines = @(
                "# Module: $dirname", '', '## ID', '', $id, '',
                '## Version', '', $version, '',
                '## Minimum risk profile', ''
            )
            if ($minProfile) { $lines += @($minProfile, '') }
            $lines += @(
                '## Load when', '', '- trigger line', '',
                '## Required context', '', '- context line', '',
                '## Approval gates', '', '- gate line', '',
                '## Required evidence', '', '- evidence line', '',
                '## Prohibited shortcuts', '', '- shortcut line', ''
            )
            Set-Content -LiteralPath (Join-Path $dir 'MODULE.md') -Value $lines
        }

        function New-TempRegistry {
            $sb = Join-Path ([System.IO.Path]::GetTempPath()) ("ctxreg-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $sb -Force | Out-Null
            return $sb
        }
    }

    It 'INVALID (1) for fenced/commented/quoted/unclosed-fence content' -ForEach @(
        @{ f = 'context-fenced-selection.md'; c = 1 },
        @{ f = 'context-fenced-none.md'; c = 1 },
        @{ f = 'context-unclosed-fence.md'; c = 1 },
        @{ f = 'context-commented-selection.md'; c = 1 },
        @{ f = 'context-blockquote-selection.md'; c = 1 }
    ) {
        Invoke-Ctx $_.f | Select-Object -ExpandProperty Code | Should -Be $_.c
    }

    It 'INVALID (1): selections require exactly one recognized risk profile' -ForEach @(
        'context-profile-missing.md'
        'context-profile-unknown.md'
        'context-profile-duplicate.md'
        'context-profile-invalid-with-ha-module.md'
        'context-profile-invalid-none-selected.md'
    ) {
        Invoke-Ctx $_ | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'the None selected sentinel rejects unresolved suffixes' -ForEach @(
        @{ f = 'context-none-tbd.md'; c = 2 }
        @{ f = 'context-none-empty-rationale.md'; c = 1 }
        @{ f = 'context-none-narrative-ok.md'; c = 0 }
    ) {
        Invoke-Ctx $_.f | Select-Object -ExpandProperty Code | Should -Be $_.c
    }

    It 'JSON mode never reports VALID with a null profile' {
        $out = Invoke-Ctx 'context-profile-unknown.md' -Json
        $doc = ($out.Output -split "`n")[0] | ConvertFrom-Json
        $doc.result | Should -Be 'INVALID'
        $doc.profile | Should -BeNullOrEmpty
        $doc.diagnostics[0].code | Should -Be 'CONTEXT_PROFILE_INVALID'
    }

    It 'a fenced Profile declaration cannot satisfy the profile floor' {
        # Message text is pinned by the Bash suite; the classification alone
        # proves the fenced high-assurance declaration was ignored.
        Invoke-Ctx 'context-fenced-profile-status.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'BLOCKED (2) for registry identity and metadata violations' -ForEach @(
        @{ n = 'good-name'; i = 'other-name'; v = '1'; m = 'high-assurance' }  # ID/dir mismatch
        @{ n = 'evil'; i = '../other-module'; v = '1'; m = 'standard' }         # path-like ID
        @{ n = 'no-id'; i = ''; v = '1'; m = 'standard' }                       # missing ID
        @{ n = 'odd-min'; i = 'some-id'; v = '1'; m = 'critical' }              # unknown min profile
        @{ n = 'no-min'; i = 'some-id'; v = '1'; m = '' }                       # missing min profile
    ) {
        $sb = New-TempRegistry
        try {
            New-SandboxModule $sb $_.n $_.i $_.v $_.m
            Invoke-Ctx 'context-valid-single.md' $sb | Select-Object -ExpandProperty Code | Should -Be 2
        }
        finally { Remove-Item -Recurse -Force $sb -ErrorAction SilentlyContinue }
    }

    It 'BLOCKED (2) for a duplicated declared ID across directories' {
        $sb = New-TempRegistry
        try {
            New-SandboxModule $sb 'module-a' 'dup-id' '1' 'standard'
            New-SandboxModule $sb 'module-b' 'dup-id' '1' 'standard'
            Invoke-Ctx 'context-valid-single.md' $sb | Select-Object -ExpandProperty Code | Should -Be 2
        }
        finally { Remove-Item -Recurse -Force $sb -ErrorAction SilentlyContinue }
    }

    It 'BLOCKED (2) for a duplicated heading and for an empty doc section' {
        $sb = New-TempRegistry
        try {
            New-SandboxModule $sb 'dup-head' 'some-id' '1' 'standard'
            Add-Content -LiteralPath (Join-Path $sb 'dup-head\MODULE.md') -Value "`n## Version`n`n2`n"
            Invoke-Ctx 'context-valid-single.md' $sb | Select-Object -ExpandProperty Code | Should -Be 2

            $sb2 = New-TempRegistry
            New-SandboxModule $sb2 'empty-docs' 'some-id' '1' 'standard'
            $mf = Join-Path $sb2 'empty-docs\MODULE.md'
            (Get-Content -LiteralPath $mf) | Where-Object { $_ -ne '- trigger line' } | Set-Content -LiteralPath $mf
            Invoke-Ctx 'context-valid-single.md' $sb2 | Select-Object -ExpandProperty Code | Should -Be 2
            Remove-Item -Recurse -Force $sb2 -ErrorAction SilentlyContinue
        }
        finally { Remove-Item -Recurse -Force $sb -ErrorAction SilentlyContinue }
    }

    It 'JSON redacts absolute outside-project paths in the full document' {
        # Nested invocation: [Console]::Out bypasses in-process stream capture.
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) 'ctx-redact-probe.md'
        Set-Content -LiteralPath $outside -Value "# TASK-X`n`n## Risk profile`n`nProfile: standard`n`n## Context modules`n`n- None selected`n"
        try {
            $raw = & pwsh -NoProfile -File $script:vctx -Format Json $outside 2>$null
            $LASTEXITCODE | Should -Be 0
            $json = "$raw"
            $doc = $json | ConvertFrom-Json
            $doc.task_file | Should -Be 'ctx-redact-probe.md'
            $json | Should -Not -Match 'Temp|Users'
        }
        finally { Remove-Item -LiteralPath $outside -Force -ErrorAction SilentlyContinue }
    }

    It 'composite handoff gate accepts a fully valid completed HA task' {
        & pwsh -NoProfile -File $script:vhand (Join-Path $fixtures 'context-full-contract-ha.md') *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'composite handoff gate propagates INVALID from the context leg' {
        & pwsh -NoProfile -File $script:vhand (Join-Path $fixtures 'context-unknown-module.md') *> $null
        $LASTEXITCODE | Should -Be 1
    }

    It 'composite handoff gate propagates BLOCKED from the task leg' {
        & pwsh -NoProfile -File $script:vhand (Join-Path $fixtures 'context-valid-bare-none.md') *> $null
        $LASTEXITCODE | Should -Be 2
    }
}

Describe 'validate-context golden expected outcomes for new fixtures' {
    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:validate = Join-Path $repoRoot '.agentic' 'scripts' 'validate-context.ps1'
        $fixtures = Join-Path $repoRoot 'tests' 'fixtures' 'context-tasks'

        function Invoke-Validator([string]$fixture) {
            $out = & $script:validate (Join-Path $fixtures $fixture) 2>&1
            return @{ Code = $LASTEXITCODE; Output = ($out | Out-String).Trim() }
        }
    }

    It 'VALID (0) for uppercase profile STANDARD' {
        Invoke-Validator 'context-profile-uppercase-standard.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for canonical em-dash separator' {
        Invoke-Validator 'context-selection-canonical-emdash.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'VALID (0) for canonical hyphen separator' {
        Invoke-Validator 'context-selection-canonical-hyphen.md' | Select-Object -ExpandProperty Code | Should -Be 0
    }

    It 'INVALID (1) for colon separator' {
        Invoke-Validator 'context-selection-colon-separator.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for missing separator' {
        Invoke-Validator 'context-selection-missing-separator.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for uppercase LOADED token' {
        Invoke-Validator 'context-selection-uppercase-loaded.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for None selectedness malformed sentinel' {
        Invoke-Validator 'context-sentinel-selectedness.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }

    It 'INVALID (1) for None selected-but-not-really malformed sentinel' {
        Invoke-Validator 'context-sentinel-hyphen-nospace.md' | Select-Object -ExpandProperty Code | Should -Be 1
    }
}

