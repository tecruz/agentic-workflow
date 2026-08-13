# install.ps1 — ownership, merge, and manifest tests (Pester 5, dash assertions).
# Each test is self-contained: it creates its own temp project directory so
# tests never share state or depend on scope inheritance.
# Helpers and paths live in BeforeEach: Pester 5 does not expose file-scope
# functions/variables inside Describe/It blocks.
Describe 'install.ps1' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $install = Join-Path $repoRoot 'install.ps1'

        function New-TestDir {
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-ptest-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            return $d
        }
    }

    It 'fresh install creates the core file set and manifest' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
            Test-Path (Join-Path $tmp 'CLAUDE.md') | Should -Be $true
            Test-Path (Join-Path $tmp 'GEMINI.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\VERSION') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\ARCHITECTURE.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\install-manifest.tsv') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'second run is idempotent and produces no conflicts' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            & $install -Target $tmp *> $null
            Test-Path (Join-Path $tmp '.agentic\VERSION.new') | Should -Be $false
            Test-Path (Join-Path $tmp 'AGENTS.md.new') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'seed files are never overwritten' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value 'my custom checks'
            & $install -Target $tmp *> $null
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match 'my custom checks' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a modified managed file produces a conflict candidate and is not clobbered' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\WORKFLOW.md') -Value "`n# custom"
            & $install -Target $tmp *> $null
            Test-Path (Join-Path $tmp '.agentic\WORKFLOW.md.new') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\WORKFLOW.md')) -match '# custom' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-ReplaceManaged overwrites a modified managed file' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\WORKFLOW.md') -Value "`n# custom"
            & $install -Target $tmp -ReplaceManaged *> $null
            Test-Path (Join-Path $tmp '.agentic\WORKFLOW.md.new') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'merge preserves custom content and the managed block stays on top' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value 'TOP CUSTOM CONTENT'
            & $install -Target $tmp *> $null
            $ag = Join-Path $tmp 'AGENTS.md'
            (Get-Content -Raw $ag) -match 'TOP CUSTOM CONTENT' | Should -Be $true
            (Get-Content -Raw $ag) -match 'AGENTIC-PROTOCOL-START' | Should -Be $true
            $startLine = (Select-String -LiteralPath $ag -Pattern 'AGENTIC-PROTOCOL-START').LineNumber
            $customLine = (Select-String -LiteralPath $ag -Pattern 'TOP CUSTOM CONTENT').LineNumber
            $startLine | Should -BeLessThan $customLine
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'update preserves content appended below the managed block' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "`n## Team notes`nkeep this"
            & $install -Target $tmp *> $null
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'keep this' | Should -Be $true
            Test-Path (Join-Path $tmp 'AGENTS.md.new') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Plan makes no changes' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value 'keep me'
            & $install -Target $tmp -Plan *> $null
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'keep me' | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\install-manifest.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-GenerateChecks writes stack-detected checks for a Node project' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -GenerateChecks *> $null
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match "`tnpm`t" | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'checks.tsv is seeded from the template, not the framework checks' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            # the framework's own checks.tsv contains 'ps-syntax'; adopters must not get it
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match 'ps-syntax' | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-ReplaceManaged never touches checks.tsv' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value 'custom checks content'
            & $install -Target $tmp -ReplaceManaged *> $null
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match 'custom checks content' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-RegenerateChecks overwrites checks.tsv when -GenerateChecks is passed' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -GenerateChecks *> $null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value 'custom checks content'
            & $install -Target $tmp -GenerateChecks -RegenerateChecks *> $null
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match 'custom checks content' | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'malformed merge markers produce a conflict candidate' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "<!-- @@AGENTIC-PROTOCOL-START@@ -->`nsome content"
            & $install -Target $tmp *> $null
            Test-Path (Join-Path $tmp 'AGENTS.md.new') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a failed install rolls back partial changes' {
        $tmp = New-TestDir
        try {
            $agentic = Join-Path $tmp '.agentic'
            New-Item -ItemType Directory -Path $agentic -Force | Out-Null
            # a file where a managed-file parent directory is expected makes the
            # install fail partway through; files already written must be removed
            Set-Content -LiteralPath (Join-Path $agentic 'templates') -Value 'blocker'
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp '.agentic\VERSION') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\rules\01-general-principles.md') | Should -Be $false
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\install-manifest.tsv') | Should -Be $false
            (Get-Content -Raw (Join-Path $tmp '.agentic\templates')) -match 'blocker' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'an update that fails after the merge phase restores the merged files' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "`n## Team notes`nkeep this content"
            $mf = Join-Path $tmp '.agentic\install-manifest.tsv'
            Set-ItemProperty -LiteralPath $mf -Name IsReadOnly -Value $true
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Set-ItemProperty -LiteralPath $mf -Name IsReadOnly -Value $false
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'keep this content' | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'AGENTIC-PROTOCOL-START' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'reversed merge markers produce a conflict candidate and are not clobbered' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "<!-- @@AGENTIC-PROTOCOL-END@@ -->`ncustom content`n<!-- @@AGENTIC-PROTOCOL-START@@ -->"
            & $install -Target $tmp *> $null
            Test-Path (Join-Path $tmp 'AGENTS.md.new') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'custom content' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a pre-existing .new conflict candidate is restored on rollback' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\WORKFLOW.md') -Value "`n# custom"
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\WORKFLOW.md.new') -Value 'PRECIOUS CANDIDATE'
            $mf = Join-Path $tmp '.agentic\install-manifest.tsv'
            Set-ItemProperty -LiteralPath $mf -Name IsReadOnly -Value $true
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Set-ItemProperty -LiteralPath $mf -Name IsReadOnly -Value $false
            (Get-Content -Raw (Join-Path $tmp '.agentic\WORKFLOW.md.new')) -match 'PRECIOUS CANDIDATE' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
}