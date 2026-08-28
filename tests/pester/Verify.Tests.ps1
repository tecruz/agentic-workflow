# verify.ps1 — state-model tests (Pester 5, dash assertions).
# Helpers and paths live in BeforeEach: Pester 5 does not expose file-scope
# functions/variables inside Describe/It blocks.
#
# These tests run on every CI platform (Windows, Linux, macOS) because the
# framework's own checks invoke the Pester suite via verify.sh/verify.ps1.
# They must therefore be cross-platform: the no-op passing check uses pwsh
# (installed on all runners), and link/junction constructs are created only
# where the platform supports them.
Describe 'verify.ps1 state model' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $verify = Join-Path $repoRoot '.agentic\scripts\verify.ps1'
        $fix = Join-Path $repoRoot 'tests\fixtures'

        function Invoke-Verify {
            $out = & $verify 2>&1
            $code = $LASTEXITCODE
            if ($code -ne 0) {
                Write-Host "--- VERIFY FAILED (exit $code) ---"
                $out | ForEach-Object { Write-Host $_ }
                Write-Host "----------------------------------"
            }
            return $code
        }

        function Invoke-Fixture([string]$name) {
            Push-Location (Join-Path $fix $name)
            try { return Invoke-Verify }
            finally { Pop-Location }
        }

        # A check that runs and exits 0 on every platform. pwsh is present on all
        # CI runners, so it is the cross-platform stand-in for `cmd /c exit 0`.
        function New-PassingCheck([string]$cwd = '.', [string]$id = 'ok') {
            "required`t$id`t$cwd`tpwsh`t-NoProfile`t-Command`texit`t0"
        }
    }

    It 'PASS (0) when a Node/npm project required checks pass' {
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'npm not available'; return }
        Invoke-Fixture 'node-npm' | Should -Be 0
    }

    It 'FAIL (1) when a required check fails' {
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'npm not available'; return }
        Invoke-Fixture 'node-npm-fail' | Should -Be 1
    }

    It 'BLOCKED (2) when a required check executable is missing' {
        Invoke-Fixture 'checks-tsv' | Should -Be 2
    }

    It 'BLOCKED (2) beats PASS when one required check is blocked and another passes' {
        Invoke-Fixture 'checks-tsv' | Should -Be 2
    }

    It 'UNSUPPORTED (3) when no supported project or checks exist' {
        Invoke-Fixture 'unsupported' | Should -Be 3
    }

    It 'a checks.tsv with only optional checks never reports PASS' {
        Invoke-Fixture 'checks-tsv-optional-only' | Should -Not -Be 0
    }

    It '--emit-checks prints the detected npm checks on stdout' {
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'npm not available'; return }
        Push-Location (Join-Path $fix 'node-npm')
        try { $out = & $verify -EmitChecks 2> $null; $code = $LASTEXITCODE } finally { Pop-Location }
        $code | Should -Be 0
        $out | Where-Object { $_ -match "`tnpm`t" } | Should -Not -Be $null
    }

    It 'a uv.lock project is detected as uv via --emit-checks' {
        Push-Location (Join-Path $fix 'python-uv')
        try { $out = & $verify -EmitChecks 2> $null; $code = $LASTEXITCODE } finally { Pop-Location }
        $code | Should -Be 0
        $out | Where-Object { $_ -match "`tuv`t" } | Should -Not -Be $null
    }

    It 'a bun.lock project is detected as bun via --emit-checks' {
        Push-Location (Join-Path $fix 'node-bun')
        try { $out = & $verify -EmitChecks 2> $null; $code = $LASTEXITCODE } finally { Pop-Location }
        $code | Should -Be 0
        $out | Where-Object { $_ -match "`tbun`t" } | Should -Not -Be $null
    }

    It 'detection matches the golden contract for every deterministic fixture' {
        # The checked-in golden files are the exact, sorted emitted contract.
        # Catches missing and unexpected checks alike. The Bash implementation is
        # held to the same contract by the Bats suite, so both stay in parity.
        $goldenDir = Join-Path $fix 'golden'
        Get-ChildItem -LiteralPath $goldenDir -Filter *.tsv | ForEach-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            Push-Location (Join-Path $fix $name)
            try {
                $actual = (& $verify -EmitChecks 2> $null) | Where-Object { $_ -and -not $_.StartsWith('Detected:') }
            }
            finally { Pop-Location }
            $actualSorted = (($actual | Sort-Object) -join "`n")
            $actualSorted | Should -Be ((Get-Content -LiteralPath $_.FullName) -join "`n")
        }
    }

    It 'a pnpm project without a lint script does not emit a lint check' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            Set-Content -LiteralPath (Join-Path $tmp 'pnpm-lock.yaml') -Value ''
            Push-Location $tmp
            try { $out = & $verify -EmitChecks 2> $null } finally { Pop-Location }
            $out | Where-Object { $_ -match "`tpnpm`ttest" } | Should -Not -Be $null
            $out | Where-Object { $_ -match 'node-lint' } | Should -BeNullOrEmpty
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a Python project without Ruff config does not emit a ruff check' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'pyproject.toml') -Value "[project]`nname = `"x`""
            Push-Location $tmp
            try { $out = & $verify -EmitChecks 2> $null } finally { Pop-Location }
            $out | Where-Object { $_ -match "`tpytest" } | Should -Not -Be $null
            $out | Where-Object { $_ -match 'python-ruff' } | Should -BeNullOrEmpty
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'Maven detection emits checkstyle only when the pom configures it' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'pom.xml') -Value '<project></project>'
            Push-Location $tmp
            try { $out = & $verify -EmitChecks 2> $null } finally { Pop-Location }
            $out | Where-Object { $_ -match 'maven-lint' } | Should -BeNullOrEmpty
            Set-Content -LiteralPath (Join-Path $tmp 'pom.xml') -Value '<project><build><plugins><plugin><groupId>org.apache.maven.plugins</groupId><artifactId>maven-checkstyle-plugin</artifactId></plugin></plugins></build></project>'
            Push-Location $tmp
            try { $out = & $verify -EmitChecks 2> $null } finally { Pop-Location }
            $out | Where-Object { $_ -match 'maven-lint' } | Should -Not -Be $null
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'invalid checks.tsv (invalid requirement / missing fields / path traversal) exits nonzero' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "requiredd`ttest`t.`tnpm`ttest"
            Push-Location $tmp
            try { $code = Invoke-Verify } finally { Pop-Location }
            $code | Should -Not -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'checks.tsv working dir equal to the project root is accepted' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck '.')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'checks.tsv working dir inside the project is accepted' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'nested') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'nested')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'checks.tsv working dir with a sibling-prefix path is rejected' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        $parent = Split-Path -Parent $tmp
        $sibling = Join-Path $parent ((Split-Path -Leaf $tmp) + '-backup')
        New-Item -ItemType Directory -Path $sibling -Force | Out-Null
        try {
            $escape = Join-Path '..' (Split-Path -Leaf $sibling)
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck $escape)
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $sibling -ErrorAction SilentlyContinue
        }
    }

    It 'checks.tsv working dir with a case-differing sibling path is rejected on case-sensitive filesystems' {
        if ($env:OS -eq 'Windows_NT' -or $IsWindows) { return }
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        $tmpParent = Split-Path -Parent $tmp
        $tmpLeaf = Split-Path -Leaf $tmp
        $siblingLeaf = if ($tmpLeaf -ceq $tmpLeaf.ToLower()) { $tmpLeaf.ToUpper() } else { $tmpLeaf.ToLower() }
        $sibling = Join-Path $tmpParent $siblingLeaf

        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $probeTarget = Join-Path $tmp "ABC"
        $probeCheck = Join-Path $tmp "abc"
        New-Item -ItemType Directory -Path $probeTarget -Force | Out-Null
        $isCaseSensitive = -not (Test-Path -LiteralPath $probeCheck)
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

        if (-not $isCaseSensitive) { return }

        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        New-Item -ItemType Directory -Path $sibling -Force | Out-Null
        try {
            $escape = Join-Path '..' (Split-Path -Leaf $sibling)
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck $escape)
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $sibling -ErrorAction SilentlyContinue
        }
    }

    It 'checks.tsv working dir through a link escape is rejected' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vout-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try {
            # Junctions are Windows-only; use a symbolic link elsewhere.
            try {
                if ($env:OS -eq 'Windows_NT') {
                    New-Item -ItemType Junction -Path (Join-Path $tmp 'escape') -Target $outside -Force -ErrorAction Stop | Out-Null
                }
                else {
                    New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'escape') -Target $outside -Force -ErrorAction Stop | Out-Null
                }
            }
            catch { return }  # links unavailable (privilege / platform): skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'escape')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $outside -ErrorAction SilentlyContinue
        }
    }

    # -----------------------------------------------------------------------
    # Review regression tests: missing directories report BLOCKED, missing
    # path-qualified executables never fall back to PATH, and relative
    # symbolic-link targets resolve against the link's parent directory.
    # -----------------------------------------------------------------------

    It 'a missing inside-project working directory reports BLOCKED (2)' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'missing-dir')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 2
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a missing path-qualified executable is BLOCKED (2) even when a same-name command is on PATH' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        $fakeBin = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-fakebin-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        if ($env:OS -eq 'Windows_NT') {
            Set-Content -LiteralPath (Join-Path $fakeBin 'lint.cmd') -Value '@exit 0'
        }
        else {
            Set-Content -LiteralPath (Join-Path $fakeBin 'lint') -Value "#!/usr/bin/env sh`nexit 0"
            & chmod +x (Join-Path $fakeBin 'lint')
        }
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tlint`t.`t./tools/lint"
            $oldPath = $env:PATH
            $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $oldPath
            try {
                Push-Location $tmp
                try { $code = Invoke-Verify } finally { Pop-Location }
            }
            finally { $env:PATH = $oldPath }
            # A missing configured path must be BLOCKED (2), never resolved to
            # the unrelated global `lint` command which would falsely PASS (0).
            $code | Should -Be 2
        }
        finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $fakeBin -ErrorAction SilentlyContinue
        }
    }

    It 'an empty executable in checks.tsv is a configuration failure' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tunit`t.`t`ttrue"
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'indented comment lines in checks.tsv are ignored' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value @('  # indented comment', (New-PassingCheck '.'))
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a relative symbolic link inside the project is accepted' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'nested') -Force | Out-Null
        try {
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'rel-inside') -Target (Join-Path '.' 'nested') -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable (privilege / platform): skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'rel-inside')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a relative symbolic link pointing outside the project is rejected' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vout-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try {
            $relTarget = Join-Path '..' (Split-Path -Leaf $outside)
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'rel-outside') -Target $relTarget -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'rel-outside')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $outside -ErrorAction SilentlyContinue
        }
    }

    It 'multi-hop relative symbolic links resolve to the final target' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'nested') -Force | Out-Null
        try {
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'hop1') -Target (Join-Path '.' 'nested') -Force -ErrorAction Stop | Out-Null
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'hop2') -Target (Join-Path '.' 'hop1') -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'hop2')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a broken relative symbolic link reports BLOCKED (2)' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'broken-link') -Target (Join-Path '.' 'missing-dir') -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'broken-link')
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 2
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a symbolic-link cycle fails deterministically' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'cycA') -Target (Join-Path '.' 'cycB') -Force -ErrorAction Stop | Out-Null
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'cycB') -Target (Join-Path '.' 'cycA') -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value (New-PassingCheck 'cycA')
            Push-Location $tmp
            try { $code = Invoke-Verify } finally { Pop-Location }
            # The cycle is an unresolvable working directory: configuration
            # failure (1) or BLOCKED (2), never a hang and never PASS.
            $code | Should -BeIn 1, 2
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    # ---------------------------------------------------------------------
    # Candidate lifecycle regression tests (-DetectChecks / -ValidateChecks).
    # ---------------------------------------------------------------------

    It '-DetectChecks writes a candidate contract that validates' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            Push-Location $tmp
            try {
                & $verify -DetectChecks *> $null
                $detectCode = $LASTEXITCODE
                & $verify -ValidateChecks '.agentic/checks.generated.tsv' *> $null
                $validateCode = $LASTEXITCODE
            }
            finally { Pop-Location }
            $detectCode | Should -Be 0
            $validateCode | Should -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-DetectChecks removes a stale candidate when no stack is detected' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            Push-Location $tmp
            try { & $verify -DetectChecks *> $null } finally { Pop-Location }
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $true
            Remove-Item -LiteralPath (Join-Path $tmp 'package.json') -Force
            Push-Location $tmp
            try { & $verify -DetectChecks *> $null } finally { Pop-Location }
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-ValidateChecks accepts a valid candidate' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\candidate.tsv') -Value (New-PassingCheck 'ok' 'cand')
            Push-Location $tmp
            try { & $verify -ValidateChecks '.agentic/candidate.tsv' *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-ValidateChecks rejects a malformed candidate' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\candidate.tsv') -Value "bogus-requirement`tbad-id`t.`tpwsh`t-NoProfile"
            Push-Location $tmp
            try { & $verify -ValidateChecks '.agentic/candidate.tsv' *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-ValidateChecks rejects duplicate check IDs' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            $dup = @(
                (New-PassingCheck '.' 'dup-id'),
                (New-PassingCheck '.' 'dup-id')
            )
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\candidate.tsv') -Value $dup
            Push-Location $tmp
            try { & $verify -ValidateChecks '.agentic/candidate.tsv' *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-ValidateChecks fails when the file does not exist' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Push-Location $tmp
            try { & $verify -ValidateChecks '.agentic/missing.tsv' *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    # ---------------------------------------------------------------------
    # Platform-aware Gradle/Maven wrapper detection. Wrapper-enabled projects
    # ship both scripts; the emitted contract must use the script the current
    # platform can execute (gradlew.bat / mvnw.cmd on Windows, ./gradlew /
    # ./mvnw elsewhere).
    # ---------------------------------------------------------------------

    It 'Maven wrapper detection is platform-aware (mvnw.cmd on Windows, ./mvnw elsewhere)' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'pom.xml') -Value '<project></project>'
            Set-Content -LiteralPath (Join-Path $tmp 'mvnw') -Value '#!/usr/bin/env sh'
            Set-Content -LiteralPath (Join-Path $tmp 'mvnw.cmd') -Value '@echo off'
            Push-Location $tmp
            try { $out = & $verify -EmitChecks 2> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
            $maven = $out | Where-Object { $_ -match 'maven-test' } | Select-Object -First 1
            $maven | Should -Not -BeNullOrEmpty
            if ($IsWindows) { $maven | Should -Match 'mvnw\.cmd' }
            else { $maven | Should -Match '\./mvnw' }
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'Gradle wrapper detection is platform-aware (gradlew.bat on Windows, ./gradlew elsewhere)' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'build.gradle') -Value 'plugins { id "com.android.application" }'
            Set-Content -LiteralPath (Join-Path $tmp 'gradlew') -Value '#!/usr/bin/env sh'
            Set-Content -LiteralPath (Join-Path $tmp 'gradlew.bat') -Value '@echo off'
            Push-Location $tmp
            try { $out = & $verify -EmitChecks 2> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 0
            $android = $out | Where-Object { $_ -match 'android-unit' } | Select-Object -First 1
            $android | Should -Not -BeNullOrEmpty
            if ($IsWindows) { $android | Should -Match 'gradlew\.bat' }
            else { $android | Should -Match '\./gradlew' }
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
}
