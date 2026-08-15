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

    It '-GenerateChecks leaves no generated candidate when the install fails and none existed' {
        $tmp = New-TestDir
        try {
            $agentic = Join-Path $tmp '.agentic'
            New-Item -ItemType Directory -Path $agentic -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            # a directory where the manifest is expected fails the install after
            # detection has already produced (and possibly replaced) the candidate
            New-Item -ItemType Directory -Path (Join-Path $agentic 'install-manifest.tsv') | Out-Null
            & $install -Target $tmp -GenerateChecks *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-GenerateChecks restores a reviewed candidate exactly when the install fails' {
        $tmp = New-TestDir
        try {
            $agentic = Join-Path $tmp '.agentic'
            New-Item -ItemType Directory -Path $agentic -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.generated.tsv') -Value '# reviewed candidate'
            New-Item -ItemType Directory -Path (Join-Path $agentic 'install-manifest.tsv') | Out-Null
            & $install -Target $tmp -GenerateChecks *> $null
            $LASTEXITCODE | Should -Not -Be 0
            $restored = (Get-Content -Raw (Join-Path $tmp '.agentic\checks.generated.tsv'))
            $restored.Trim() | Should -Be '# reviewed candidate'
            $restored | Should -Not -Match 'node-test'
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $false
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

    It 'a failed fresh install removes directories it created that are now empty' {
        $tmp = New-TestDir
        try {
            $agentic = Join-Path $tmp '.agentic'
            New-Item -ItemType Directory -Path $agentic -Force | Out-Null
            # a file where a managed-file parent directory is expected makes the
            # install fail partway through; empty dirs created by the install
            # must be removed during rollback
            Set-Content -LiteralPath (Join-Path $agentic 'templates') -Value 'blocker'
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $agentic 'rules') | Should -Be $false
            Test-Path (Join-Path $agentic 'scripts') | Should -Be $false
            (Get-Content -Raw (Join-Path $agentic 'templates')) -match 'blocker' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    # ---------------------------------------------------------------------
    # Candidate lifecycle regression tests (detect / validate / accept).
    # ---------------------------------------------------------------------

    It '-DetectChecks -Plan makes no filesystem changes' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks -Plan *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-GenerateChecks -Plan makes no filesystem changes' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -GenerateChecks -Plan *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-DetectChecks writes a candidate contract' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            $LASTEXITCODE | Should -Be 0
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.generated.tsv')) -match "`tnpm`t" | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-AcceptDetectedChecks promotes the exact reviewed candidate, not a fresh detection' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\checks.generated.tsv') -Value "`n# reviewer note: keep exactly this line"
            & $install -Target $tmp -AcceptDetectedChecks *> $null
            $LASTEXITCODE | Should -Be 0
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match 'reviewer note: keep exactly this line' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-AcceptDetectedChecks -Plan makes no filesystem changes' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            & $install -Target $tmp -AcceptDetectedChecks -Plan *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-AcceptDetectedChecks rejects an invalid candidate without writing checks.tsv' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.generated.tsv') -Value "bogus-requirement`tbad-id`t.`tpwsh`t-NoProfile"
            & $install -Target $tmp -AcceptDetectedChecks *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-AcceptDetectedChecks requires an existing candidate' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -AcceptDetectedChecks *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'existing checks.tsv is protected without -ReplaceChecks' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value 'project owned checks'
            & $install -Target $tmp -AcceptDetectedChecks *> $null
            $LASTEXITCODE | Should -Not -Be 0
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match 'project owned checks' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-ReplaceChecks overwrites a project-owned checks.tsv' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.tsv') -Value 'project owned checks'
            & $install -Target $tmp -AcceptDetectedChecks -ReplaceChecks *> $null
            $LASTEXITCODE | Should -Be 0
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match 'project owned checks' | Should -Be $false
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -match "`tnpm`t" | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'acceptance does not alter the install manifest' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp *> $null
            $mf = Join-Path $tmp '.agentic\install-manifest.tsv'
            $before = Get-FileHash -LiteralPath $mf -Algorithm SHA256
            & $install -Target $tmp -DetectChecks *> $null
            & $install -Target $tmp -AcceptDetectedChecks -ReplaceChecks *> $null
            $LASTEXITCODE | Should -Be 0
            $after = Get-FileHash -LiteralPath $mf -Algorithm SHA256
            $after.Hash | Should -Be $before.Hash
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a stale candidate is removed and never promoted when detection finds nothing' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $true
            Remove-Item -LiteralPath (Join-Path $tmp 'package.json') -Force
            & $install -Target $tmp -DetectChecks *> $null
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $false
            & $install -Target $tmp -GenerateChecks *> $null
            # the template may be seeded, but stale detection content must not be
            $stale = Join-Path $tmp '.agentic\checks.tsv'
            if (Test-Path $stale) {
                (Get-Content -Raw $stale) -match 'node-test' | Should -Be $false
                (Get-Content -Raw $stale) -match "`tnpm`t" | Should -Be $false
            }
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'detection and acceptance leave no temporary files behind' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            & $install -Target $tmp -AcceptDetectedChecks *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\checks.tsv.agentic-tmp') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\install-manifest.tsv.agentic-tmp') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    # -----------------------------------------------------------------------
    # Migration, pruning, and uninstall lifecycle tests (-Update migrations,
    # -Prune, -Uninstall, tool-adapter deselection, v1.0 legacy migration).
    # -----------------------------------------------------------------------

    It 'update prunes a deselected managed adapter and installs the new one' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true
            & $install -Target $tmp -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $false
            Test-Path (Join-Path $tmp 'GEMINI.md') | Should -Be $false
            Test-Path (Join-Path $tmp 'CLAUDE.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a deselected merge adapter keeps its custom content' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools claude *> $null
            Add-Content -LiteralPath (Join-Path $tmp 'CLAUDE.md') -Value "`n## Team notes`nkeep this content"
            & $install -Target $tmp -Tools gemini *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'CLAUDE.md') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'CLAUDE.md')) -match 'keep this content' | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'CLAUDE.md')) -match 'AGENTIC-PROTOCOL-START' | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'pruning a modified managed adapter preserves it as a conflict' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.aider.conf.yml') -Value '# adopter config'
            & $install -Target $tmp -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.aider.conf.yml')) -match '# adopter config' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Prune removes obsolete files and rewrites the manifest' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            & $install -Target $tmp -Prune -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'GEMINI.md') | Should -Be $false
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $false
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\install-manifest.tsv')) -match 'GEMINI.md' | Should -Be $false
            (Get-Content -Raw (Join-Path $tmp '.agentic\install-manifest.tsv')) -match '\tseed\t' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Prune -Plan makes no changes' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            & $install -Target $tmp -Prune -Plan -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'GEMINI.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Uninstall removes managed files, strips merge blocks, preserves seeds' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools claude *> $null
            & $install -Target $tmp -Uninstall *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $false
            Test-Path (Join-Path $tmp 'CLAUDE.md') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\VERSION') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\install-manifest.tsv') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\ARCHITECTURE.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\STATUS.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Uninstall preserves modified managed files and custom merge content' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\WORKFLOW.md') -Value '# adopter notes'
            Add-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "`n## Team notes`nkeep this content"
            & $install -Target $tmp -Uninstall *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\WORKFLOW.md') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\WORKFLOW.md')) -match '# adopter notes' | Should -Be $true
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'keep this content' | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'AGENTIC-PROTOCOL-START' | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Uninstall -Plan makes no changes' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            & $install -Target $tmp -Uninstall -Plan *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\install-manifest.tsv') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'v1.0 legacy migration: update reports, -Prune removes files but keeps dirs' {
        $tmp = New-TestDir
        try {
            foreach ($d in @('.github', '.cursor\rules', '.windsurf', 'Memory')) {
                New-Item -ItemType Directory -Path (Join-Path $tmp $d) -Force | Out-Null
            }
            foreach ($f in @('.cursorrules', '.windsurfrules', '.clinerules', 'CONVENTIONS.md', '.github\copilot-instructions.md')) {
                Set-Content -LiteralPath (Join-Path $tmp $f) -Value 'v1.0 adapter'
            }
            Set-Content -LiteralPath (Join-Path $tmp 'Memory\PROJECT_STATE.md') -Value 'v1.0 project state'
            Set-Content -LiteralPath (Join-Path $tmp '.cursor\rules\user.txt') -Value 'v1.0 user rules'
            Set-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "# v1.0 AGENTS.md`ncustom content"

            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Be 0
            # legacy artifacts are reported, not removed, by a plain install/update
            Test-Path (Join-Path $tmp '.cursorrules') | Should -Be $true
            Test-Path (Join-Path $tmp 'Memory\PROJECT_STATE.md') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'AGENTIC-PROTOCOL-START' | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'custom content' | Should -Be $true

            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.cursorrules') | Should -Be $false
            Test-Path (Join-Path $tmp '.windsurfrules') | Should -Be $false
            Test-Path (Join-Path $tmp '.clinerules') | Should -Be $false
            Test-Path (Join-Path $tmp 'CONVENTIONS.md') | Should -Be $false
            Test-Path (Join-Path $tmp '.github\copilot-instructions.md') | Should -Be $false
            Test-Path (Join-Path $tmp 'Memory\PROJECT_STATE.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.cursor\rules\user.txt') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\ARCHITECTURE.md') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'AGENTIC-PROTOCOL-START' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    # -----------------------------------------------------------------------
    # Clean adopter bundle end-to-end (scripts/build-bundle.sh). The build
    # script itself is bash; this test only exercises it when bash is present,
    # so the suite still runs on Windows without git-bash.
    # -----------------------------------------------------------------------

    It 'bundle end-to-end: build, then install from the bundle' {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if (-not $bash) { Set-ItResult -Skipped -Because 'bash (git-bash/WSL) is required to build the bundle' }
        $version = (Get-Content -Raw (Join-Path $repoRoot '.agentic\VERSION')).Trim()
        $dist = Join-Path $repoRoot 'dist'
        & $bash.Source "scripts/build-bundle.sh" *> $null
        if ($LASTEXITCODE -ne 0) { throw 'build-bundle.sh failed' }
        $bundleRoot = Join-Path $dist "agentic-workflow-$version"

        $tmp = New-TestDir
        try {
            & (Join-Path $bundleRoot 'install.ps1') -Target $tmp *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\install-manifest.tsv') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.tsv')) -notmatch 'ps-syntax' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Help prints usage and never runs an install' {
        $tmp = New-TestDir
        try {
            $out = & $install -Help *>&1 | Out-String
            $out -match 'Usage:' | Should -Be $true
            $out -match '-Uninstall' | Should -Be $true
            (Get-ChildItem -LiteralPath $tmp -Force -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'an unknown parameter is rejected instead of silently running with defaults' {
        $tmp = New-TestDir
        try {
            { & $install -Target $tmp -BogusParam *>&1 | Out-Null } | Should -Throw
            (Get-ChildItem -LiteralPath $tmp -Force -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
}