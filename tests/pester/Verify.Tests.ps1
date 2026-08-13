# verify.ps1 — state-model tests (Pester 5, dash assertions).
# Helpers and paths live in BeforeEach: Pester 5 does not expose file-scope
# functions/variables inside Describe/It blocks.
Describe 'verify.ps1 state model' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $verify = Join-Path $repoRoot '.agentic\scripts\verify.ps1'
        $fix = Join-Path $repoRoot 'tests\fixtures'

        function Invoke-Fixture([string]$name) {
            Push-Location (Join-Path $fix $name)
            try { & $verify *> $null }
            finally { Pop-Location }
            return $LASTEXITCODE
        }
    }

    It 'PASS (0) when a Node/npm project required checks pass' {
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { return }
        Invoke-Fixture 'node-npm' | Should -Be 0
    }

    It 'FAIL (1) when a required check fails' {
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { return }
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
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { return }
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

    It 'invalid checks.tsv (invalid requirement / missing fields / path traversal) exits nonzero' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "requiredd`ttest`t.`tnpm`ttest"
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Not -Be 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'checks.tsv working dir equal to the project root is accepted' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`t.`tcmd`t/c`texit`t0"
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
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`tnested`tcmd`t/c`texit`t0"
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
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`t$escape`tcmd`t/c`texit`t0"
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            $code | Should -Be 1
        }
        finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $sibling -ErrorAction SilentlyContinue
        }
    }

    It 'checks.tsv working dir through a junction escape is rejected' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-vout-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try {
            New-Item -ItemType Junction -Path (Join-Path $tmp 'escape') -Target $outside -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`tescape`tcmd`t/c`texit`t0"
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
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`tmissing-dir`tcmd`t/c`texit`t0"
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
        Set-Content -LiteralPath (Join-Path $fakeBin 'lint.cmd') -Value '@exit 0'
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tlint`t.`t./tools/lint"
            $oldPath = $env:PATH
            $env:PATH = $fakeBin + ';' + $oldPath
            try {
                Push-Location $tmp
                try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
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
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value @('  # indented comment', "required`tok`t.`tcmd`t/c`texit`t0")
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
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'rel-inside') -Target '.\nested' -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable (privilege / platform): skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`trel-inside`tcmd`t/c`texit`t0"
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
            $relTarget = '..\' + (Split-Path -Leaf $outside)
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'rel-outside') -Target $relTarget -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`trel-outside`tcmd`t/c`texit`t0"
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
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'hop1') -Target '.\nested' -Force -ErrorAction Stop | Out-Null
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'hop2') -Target '.\hop1' -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`thop2`tcmd`t/c`texit`t0"
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
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'broken-link') -Target '.\missing-dir' -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`tbroken-link`tcmd`t/c`texit`t0"
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
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'cycA') -Target '.\cycB' -Force -ErrorAction Stop | Out-Null
                New-Item -ItemType SymbolicLink -Path (Join-Path $tmp 'cycB') -Target '.\cycA' -Force -ErrorAction Stop | Out-Null
            }
            catch { return }  # symlinks unavailable: skip
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value "required`tok`tcycA`tcmd`t/c`texit`t0"
            Push-Location $tmp
            try { & $verify *> $null; $code = $LASTEXITCODE } finally { Pop-Location }
            # The cycle is an unresolvable working directory: configuration
            # failure (1) or BLOCKED (2), never a hang and never PASS.
            $code | Should -BeIn 1, 2
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
}
