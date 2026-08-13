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
}
