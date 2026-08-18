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

        function Set-ProtectedDir {
            param([string] $Path)
            if ($IsWindows) {
                # Deny only the Write rights (creating files/children), leaving
                # reads intact so assertions below can still inspect the tree.
                $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $acl = Get-Acl -LiteralPath $Path
                $deny = [System.Security.AccessControl.FileSystemAccessRule]::new(
                    $identity, 'Write', 'ContainerInherit,ObjectInherit', 'None', 'Deny')
                $acl.AddAccessRule($deny)
                Set-Acl -LiteralPath $Path $acl
            }
            else {
                if ((& id -u) -eq '0') { throw 'running as root; cannot protect a directory via chmod' }
                & chmod 555 $Path
                if ($LASTEXITCODE -ne 0) { throw "chmod failed with exit code $LASTEXITCODE" }
            }
        }

        function Restore-ProtectedDir {
            param([string] $Path)
            if ($IsWindows) {
                try {
                    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                    $acl = Get-Acl -LiteralPath $Path
                    $denyRules = $acl.Access | Where-Object {
                        $_.AccessControlType -eq 'Deny' -and $_.IdentityReference -eq $identity
                    }
                    foreach ($rule in $denyRules) { $acl.RemoveAccessRule($rule) | Out-Null }
                    Set-Acl -LiteralPath $Path $acl
                }
                catch { }
            }
            else {
                & chmod 755 $Path 2>$null
            }
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

    It 'fresh install creates risk profiles, validators, and the task template' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Test-Path (Join-Path $tmp '.agentic\profiles\README.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\profiles\prototype.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\profiles\standard.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\profiles\high-assurance.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\scripts\validate-task.sh') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\scripts\validate-task.ps1') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\templates\task.md') | Should -Be $true
            # all new files are framework-managed and recorded in the manifest
            $manifest = Get-Content -Raw (Join-Path $tmp '.agentic\install-manifest.tsv')
            $manifest -match "\.agentic/profiles/README\.md`tmanaged" | Should -Be $true
            $manifest -match "\.agentic/scripts/validate-task\.ps1`tmanaged" | Should -Be $true
            $manifest -match "\.agentic/templates/task\.md`tmanaged" | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'adopter task files in .agentic/tasks are never overwritten' {
        $tmp = New-TestDir
        try {
            New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic\tasks') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\tasks\TASK-900-adopter.md') -Value '# TASK-900: adopter task'
            & $install -Target $tmp *> $null
            (Get-Content -Raw (Join-Path $tmp '.agentic\tasks\TASK-900-adopter.md')) -match 'adopter task' | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\templates\task.md') | Should -Be $true
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
            # Atomic temp-file writes can no longer be reliably blocked by a
            # read-only manifest; force the failure inside Write-Manifest by
            # turning the manifest path into a directory (mirrors the bats
            # suite, which uses the same mechanism on bash).
            $mf = Join-Path $tmp '.agentic\install-manifest.tsv'
            Remove-Item -LiteralPath $mf -Force
            New-Item -ItemType Directory -Path $mf | Out-Null
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
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
            # see "an update that fails after the merge phase" for why a
            # directory replaces the old read-only-manifest failure mechanism
            $mf = Join-Path $tmp '.agentic\install-manifest.tsv'
            Remove-Item -LiteralPath $mf -Force
            New-Item -ItemType Directory -Path $mf | Out-Null
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
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
            # each legacy file carries the framework signature so ownership is
            # provable; a signature-less file is preserved as an unverified
            # conflict (see the adversarial tests below)
            foreach ($f in @('.cursorrules', '.windsurfrules', '.clinerules', 'CONVENTIONS.md', '.github\copilot-instructions.md')) {
                Set-Content -LiteralPath (Join-Path $tmp $f) -Value '# Universal Agentic Development Protocol'
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
    # Adversarial manifest, plan read-only, and temp-file regression tests.
    # -----------------------------------------------------------------------

    It 'a manifest path that escapes the project root is rejected before any mutation' {
        $tmp = New-TestDir
        $evil = Join-Path (Split-Path -Parent $tmp) 'evil'
        try {
            & $install -Target $tmp *> $null
            Set-Content -LiteralPath $evil -Value 'PRECIOUS SIBLING'
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`n../evil`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            (Get-Content -Raw $evil) -match 'PRECIOUS SIBLING' | Should -Be $true
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
        }
        finally {
            Remove-Item -LiteralPath $evil -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'a manifest path outside the framework set is rejected before any mutation' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`nevil.txt`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'an invalid manifest category is rejected before any mutation' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`nAGENTS.md`tbogus`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'an invalid manifest blocks a plain update before any mutation' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`nevil.txt`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Prune never rewrites a malformed merge file' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'GEMINI.md') -Value "<!-- @@AGENTIC-PROTOCOL-START@@ -->`nbroken`n<!-- @@AGENTIC-PROTOCOL-START@@ -->"
            & $install -Target $tmp -Tools all *> $null
            & $install -Target $tmp -Prune -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'GEMINI.md') | Should -Be $true
            $gem = Get-Content -Raw (Join-Path $tmp 'GEMINI.md')
            ([regex]::Matches($gem, 'AGENTIC-PROTOCOL-START')).Count | Should -Be 2
            $gem -match 'broken' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Prune -Plan is byte-for-byte read-only' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            Add-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "`n## Team notes`nkeep this"
            $snap = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Force | ForEach-Object {
                '{0}={1}' -f $_.FullName.Substring($tmp.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            } | Sort-Object) -join "`n"
            & $install -Target $tmp -Prune -Plan -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic-backup') | Should -Be $false
            $after = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Force | ForEach-Object {
                '{0}={1}' -f $_.FullName.Substring($tmp.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            } | Sort-Object) -join "`n"
            $after | Should -Be $snap
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Uninstall -Plan is byte-for-byte read-only' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            $snap = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Force | ForEach-Object {
                '{0}={1}' -f $_.FullName.Substring($tmp.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            } | Sort-Object) -join "`n"
            & $install -Target $tmp -Uninstall -Plan *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic-backup') | Should -Be $false
            $after = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Force | ForEach-Object {
                '{0}={1}' -f $_.FullName.Substring($tmp.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            } | Sort-Object) -join "`n"
            $after | Should -Be $snap
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'unverified legacy files are preserved by -Prune without the new flag' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.clinerules') -Value 'my custom claude rules'
            & $install -Target $tmp *> $null
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.clinerules') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.clinerules')) -match 'my custom claude rules' | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic-backup') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-PruneUnverifiedLegacy backs up then removes unverified legacy files' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.clinerules') -Value 'my custom claude rules'
            & $install -Target $tmp *> $null
            & $install -Target $tmp -Prune -PruneUnverifiedLegacy *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.clinerules') | Should -Be $false
            (Get-Content -Raw (Join-Path $tmp '.agentic-backup\.clinerules')) -match 'my custom claude rules' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-PruneUnverifiedLegacy -Plan makes no changes' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.clinerules') -Value 'my custom claude rules'
            & $install -Target $tmp *> $null
            & $install -Target $tmp -Prune -PruneUnverifiedLegacy -Plan *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.clinerules') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic-backup') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a pre-existing .agentic-tmp file is never clobbered' {
        $tmp = New-TestDir
        try {
            $agentic = Join-Path $tmp '.agentic'
            New-Item -ItemType Directory -Path $agentic -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $agentic 'install-manifest.tsv.agentic-tmp') -Value 'PRECIOUS TMP'
            Set-Content -LiteralPath (Join-Path $agentic 'checks.tsv.agentic-tmp') -Value 'PRECIOUS TMP'
            & $install -Target $tmp -Tools claude *> $null
            (Get-Content -Raw (Join-Path $agentic 'install-manifest.tsv.agentic-tmp')) -match 'PRECIOUS TMP' | Should -Be $true
            (Get-Content -Raw (Join-Path $agentic 'checks.tsv.agentic-tmp')) -match 'PRECIOUS TMP' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    # -----------------------------------------------------------------------
    # Canonical category-registry and write-confinement adversarial tests.
    # Every test asserts the run FAILS before modifying the project or any
    # external target, and that no partial destination is ever left behind.
    # -----------------------------------------------------------------------

    It 'manifest category enforcement: CLAUDE.md recorded as managed is rejected' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`nCLAUDE.md`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'CLAUDE.md') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'CLAUDE.md')) -match 'AGENTIC-PROTOCOL-START' | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'manifest category enforcement: .aider.conf.yml recorded as merge is rejected' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp -Tools all *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`n.aider.conf.yml`tmerge`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'manifest category enforcement: a seed path recorded as managed is rejected' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`n.agentic/ARCHITECTURE.md`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp '.agentic\ARCHITECTURE.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a forged legacy manifest row (.clinerules) is rejected before any mutation' {
        $tmp = New-TestDir
        try {
            Set-Content -LiteralPath (Join-Path $tmp '.clinerules') -Value 'my custom claude rules'
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`n.clinerules`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune -PruneUnverifiedLegacy *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp '.clinerules') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.clinerules')) -match 'my custom claude rules' | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic-backup') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a merge destination that is a symlink to an outside file is refused' {
        $tmp = New-TestDir
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-out-' + [guid]::NewGuid().ToString('N'))
        try {
            Set-Content -LiteralPath $outside -Value 'PRECIOUS OUTSIDE CONTENT'
            if ($IsWindows) {
                try {
                    New-Item -ItemType Symlink -Path (Join-Path $tmp 'AGENTS.md') -Target $outside | Out-Null
                }
                catch {
                    Set-ItResult -Skipped -Because 'creating a file symlink requires elevated privileges on Windows'
                    return
                }
            }
            else {
                & ln -s $outside (Join-Path $tmp 'AGENTS.md')
                if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because 'symlink creation unavailable'; return }
            }
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            (Get-Content -Raw $outside) -match 'PRECIOUS OUTSIDE CONTENT' | Should -Be $true
            (Get-Item -LiteralPath (Join-Path $tmp 'AGENTS.md')).LinkType | Should -Not -Be $null
        }
        finally {
            Remove-Item -LiteralPath $outside -Force -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'an .agentic directory linked outside is refused without writing there' {
        $tmp = New-TestDir
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-out-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'PRECIOUS OUTSIDE'
            if ($IsWindows) {
                # Junction: directory links work without elevated privileges.
                New-Item -ItemType Junction -Path (Join-Path $tmp '.agentic') -Target $outside | Out-Null
            }
            else {
                & ln -s $outside (Join-Path $tmp '.agentic')
                if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because 'symlink creation unavailable'; return }
            }
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            (Get-Content -Raw (Join-Path $outside 'keep.txt')) -match 'PRECIOUS OUTSIDE' | Should -Be $true
            Test-Path (Join-Path $outside 'VERSION') | Should -Be $false
        }
        finally {
            # Remove the link itself first so the recursive temp cleanup never
            # traverses into the external target.
            Remove-Item -LiteralPath (Join-Path $tmp '.agentic') -Force -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $outside -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'a failed managed copy leaves no partial destination and nothing outside is touched' {
        $tmp = New-TestDir
        $agentic = Join-Path $tmp '.agentic'
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-evil-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $agentic -Force | Out-Null
            Set-Content -LiteralPath $outside -Value 'PRECIOUS SIBLING'
            try { Set-ProtectedDir $agentic }
            catch { Set-ItResult -Skipped -Because "cannot protect a directory: $($_.Exception.Message)"; return }
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $agentic 'VERSION') | Should -Be $false
            (Get-Content -Raw $outside) -match 'PRECIOUS SIBLING' | Should -Be $true
        }
        finally {
            if (Test-Path -LiteralPath $agentic) { Restore-ProtectedDir $agentic }
            Remove-Item -LiteralPath $outside -Force -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'a failed seed copy leaves no partial destination' {
        $tmp = New-TestDir
        $agentic = Join-Path $tmp '.agentic'
        try {
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $agentic 'checks.generated.tsv') | Should -Be $true
            Test-Path (Join-Path $agentic 'checks.tsv') | Should -Be $false
            try { Set-ProtectedDir $agentic }
            catch { Set-ItResult -Skipped -Because "cannot protect a directory: $($_.Exception.Message)"; return }
            & $install -Target $tmp -AcceptDetectedChecks -Tools claude *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $agentic 'checks.tsv') | Should -Be $false
            Test-Path (Join-Path $agentic 'checks.generated.tsv') | Should -Be $true
        }
        finally {
            if (Test-Path -LiteralPath $agentic) { Restore-ProtectedDir $agentic }
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'a manifest row with a leading empty field is rejected' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`n`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a manifest row with a trailing empty field is rejected' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`nAGENTS.md`tmanaged`t"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a manifest row with an adjacent empty field is rejected' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`nAGENTS.md`t`t0000000000000000000000000000000000000000000000000000000000000000"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a manifest row with an excess (4th) field is rejected' {
        $tmp = New-TestDir
        try {
            & $install -Target $tmp *> $null
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\install-manifest.tsv') -Value "`nAGENTS.md`tmanaged`t0000000000000000000000000000000000000000000000000000000000000000`textra"
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
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

    # -----------------------------------------------------------------------
    # Write-confinement and atomicity regression tests (PR #5 review). These
    # mirror the Bats tests so Bash and PowerShell lock in the same behavior;
    # on Windows the directory links are junctions (no elevation required).
    # -----------------------------------------------------------------------

    It 'detect mode refuses a linked .agentic without writing outside' {
        $tmp = New-TestDir
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-out-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'PRECIOUS OUTSIDE'
            if ($IsWindows) {
                New-Item -ItemType Junction -Path (Join-Path $tmp '.agentic') -Target $outside | Out-Null
            }
            else {
                & ln -s $outside (Join-Path $tmp '.agentic')
                if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because 'symlink creation unavailable'; return }
            }
            & $install -Target $tmp -DetectChecks -Tools claude *> $null
            $LASTEXITCODE | Should -Not -Be 0
            (Get-Content -Raw (Join-Path $outside 'keep.txt')) -match 'PRECIOUS OUTSIDE' | Should -Be $true
             Test-Path (Join-Path $outside 'checks.generated.tsv') | Should -Be $false
             (Get-ChildItem -LiteralPath $tmp -Force | Where-Object Name -eq '.agentic').LinkType | Should -Not -Be $null
         }
        finally {
            Remove-Item -LiteralPath (Join-Path $tmp '.agentic') -Force -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $outside -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'prune refuses to remove a legacy file through a linked .github' {
        $tmp = New-TestDir
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-out-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try {
            & $install -Target $tmp *> $null
            Set-Content -LiteralPath (Join-Path $outside 'copilot-instructions.md') -Value 'PRECIOUS OUTSIDE'
            if ($IsWindows) {
                New-Item -ItemType Junction -Path (Join-Path $tmp '.github') -Target $outside | Out-Null
            }
            else {
                & ln -s $outside (Join-Path $tmp '.github')
                if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because 'symlink creation unavailable'; return }
            }
            & $install -Target $tmp -Prune -PruneUnverifiedLegacy *> $null
            $LASTEXITCODE | Should -Not -Be 0
             (Get-Content -Raw (Join-Path $outside 'copilot-instructions.md')) -match 'PRECIOUS OUTSIDE' | Should -Be $true
             (Get-ChildItem -LiteralPath $tmp -Force | Where-Object Name -eq '.github').LinkType | Should -Not -Be $null
         }
        finally {
            Remove-Item -LiteralPath (Join-Path $tmp '.github') -Force -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $outside -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'prune refuses to rewrite a manifest reached through a linked .agentic' {
        $tmp = New-TestDir
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-out-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $outside 'install-manifest.tsv') -Value "1.2.1`nAGENTS.md`tmerge`t0000000000000000000000000000000000000000000000000000000000000000"
            if ($IsWindows) {
                New-Item -ItemType Junction -Path (Join-Path $tmp '.agentic') -Target $outside | Out-Null
            }
            else {
                & ln -s $outside (Join-Path $tmp '.agentic')
                if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because 'symlink creation unavailable'; return }
            }
            & $install -Target $tmp -Prune *> $null
            $LASTEXITCODE | Should -Not -Be 0
             (Get-Content -Raw (Join-Path $outside 'install-manifest.tsv')) -match "`tmerge`t" | Should -Be $true
             (Get-ChildItem -LiteralPath $tmp -Force | Where-Object Name -eq '.agentic').LinkType | Should -Not -Be $null
         }
        finally {
            Remove-Item -LiteralPath (Join-Path $tmp '.agentic') -Force -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $outside -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'case-different framework path is distinct on a case-sensitive filesystem' {
        $tmp = New-TestDir
        try {
            # Probe: on a case-insensitive filesystem the two names collide.
            Set-Content -LiteralPath (Join-Path $tmp '.CaseProbe') -Value 'probe'
            if (Test-Path -LiteralPath (Join-Path $tmp '.caseprobe')) {
                Set-ItResult -Skipped -Because 'case-insensitive filesystem'
                return
            }
            Remove-Item -LiteralPath (Join-Path $tmp '.CaseProbe') -Force
            New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\version') -Value 'lowercase custom'
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\VERSION') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\VERSION')).Trim() | Should -Be (Get-Content -Raw (Join-Path $repoRoot '.agentic\VERSION')).Trim()
            (Get-Content -Raw (Join-Path $tmp '.agentic\version')) -match 'lowercase custom' | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\version.new') | Should -Be $false
        }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'a mid-transaction failure after a managed replacement restores prior content and mode' {
        $tmp = New-TestDir
        $templates = Join-Path $tmp '.agentic\templates'
        $expectedMode = $null
        try {
            & $install -Target $tmp *> $null
            $verifySh = Join-Path $tmp '.agentic\scripts\verify.sh'
            if (-not $IsWindows) {
                # Distinctive mode: the update rewrites the verifier, then a
                # later write fails; rollback must restore content and this mode.
                & chmod 750 $verifySh
                if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because 'chmod unavailable'; return }
                $expectedMode = [int](Get-Item -LiteralPath $verifySh).UnixFileMode
            }
            try { Set-ProtectedDir $templates }
            catch { Set-ItResult -Skipped -Because "cannot protect a directory: $($_.Exception.Message)"; return }
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Not -Be 0
            # The verifier was replaced mid-transaction and rolled back to its
            # prior content (and its mode on Unix).
            (Get-Content -Raw (Join-Path $tmp '.agentic\scripts\verify.ps1')) -match 'Universal project verification script' | Should -Be $true
            if (-not $IsWindows) {
                [int](Get-Item -LiteralPath $verifySh).UnixFileMode | Should -Be $expectedMode
            }
            # The protected destination was never modified, and no randomized
            # scratch file was left behind anywhere in the project.
            Test-Path (Join-Path $templates 'FEATURE_SPEC.md') | Should -Be $true
            $strays = @(Get-ChildItem -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^[^/\\]+\.(md|yml|tsv|sh|ps1)\.[0-9A-Za-z_-]{2,}$' })
            $strays | Should -HaveCount 0
        }
        finally {
            if (Test-Path -LiteralPath $templates) { Restore-ProtectedDir $templates }
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'stale candidate removal failure (locked checks.generated.tsv) aborts with nonzero exit and preserves prior candidate' {
        $tmp = New-TestDir
        $gen = Join-Path $tmp '.agentic\checks.generated.tsv'
        $fs = $null
        try {
            New-Item -ItemType Directory -Path (Join-Path $tmp '.agentic') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp 'package.json') -Value '{"name":"x","scripts":{"test":"true"}}'
            & $install -Target $tmp -DetectChecks *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path $gen | Should -Be $true
            $candidateBefore = Get-Content -Raw $gen
            $fs = [System.IO.FileStream]::new($gen, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            Remove-Item -LiteralPath (Join-Path $tmp 'package.json') -Force
            & $install -Target $tmp -GenerateChecks *> $null
            $LASTEXITCODE | Should -Not -Be 0
            # Release the lock before verifying file contents.
            $fs.Dispose(); $fs = $null
            # Prior candidate preserved: the locked file was never removed.
            Test-Path $gen | Should -Be $true
            (Get-Content -Raw $gen) | Should -Be $candidateBefore
            # No stale content promoted to checks.tsv.
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $false
            # No randomized temp files remain in the .agentic directory.
            $strays = @(Get-ChildItem -LiteralPath (Join-Path $tmp '.agentic') -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\.[0-9A-Za-z_-]{6,}$' })
            $strays | Should -HaveCount 0
        }
        finally {
            if ($fs) { $fs.Dispose() }
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'uninstall failure (locked managed file) aborts with nonzero exit and preserves manifest and locked file' {
        $tmp = New-TestDir
        $ver = Join-Path $tmp '.agentic\VERSION'
        $mf = Join-Path $tmp '.agentic\install-manifest.tsv'
        $fs = $null
        try {
            & $install -Target $tmp *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path $ver | Should -Be $true
            Test-Path $mf | Should -Be $true
            $verBefore = Get-Content -Raw $ver
            $fs = [System.IO.FileStream]::new($ver, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            & $install -Target $tmp -Uninstall *> $null
            $LASTEXITCODE | Should -Not -Be 0
            # Release the lock before verifying file contents.
            $fs.Dispose(); $fs = $null
            # Rollback: the locked file is restored (or still present).
            Test-Path $ver | Should -Be $true
            (Get-Content -Raw $ver) | Should -Be $verBefore
            # Manifest preserved: never removed because uninstall aborted first.
            Test-Path $mf | Should -Be $true
            # No randomized temp files remain in the .agentic directory.
            $strays = @(Get-ChildItem -LiteralPath (Join-Path $tmp '.agentic') -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\.[0-9A-Za-z_-]{6,}$' })
            $strays | Should -HaveCount 0
        }
        finally {
            if ($fs) { $fs.Dispose() }
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    # -----------------------------------------------------------------------
    # Extracted-archive release tests: install from the final zip asset
    # rather than the unarchived bundle directory.
    # -----------------------------------------------------------------------

    It 'end-to-end: extract zip and install from extracted archive' {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if (-not $bash) { Set-ItResult -Skipped -Because 'bash (git-bash/WSL) is required to build the bundle' }
        $version = (Get-Content -Raw (Join-Path $repoRoot '.agentic\VERSION')).Trim()
        & $bash.Source "scripts/build-bundle.sh" *> $null
        if ($LASTEXITCODE -ne 0) { throw 'build-bundle.sh failed' }
        $archive = Join-Path $repoRoot "dist\agentic-workflow-$version.zip"
        if (-not (Test-Path $archive)) { Set-ItResult -Skipped -Because 'zip archive was not created' }

        $extractDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-extract-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        try {
            # Platform-appropriate zip extraction: Expand-Archive on Windows,
            # unzip on Linux/macOS (PowerShell's Expand-Archive has path issues).
            $unzip = Get-Command unzip -ErrorAction SilentlyContinue
            if ($IsWindows -or (-not $unzip)) {
                Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
            } else {
                & unzip -q $archive -d $extractDir
            }
            # Detect actual bundle directory (extraction tools may nest differently)
            $bundleRoot = Get-ChildItem -Recurse -Path $extractDir -Filter 'install.ps1' -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -match 'agentic-workflow-' } |
                Select-Object -First 1 -ExpandProperty DirectoryName
            if (-not $bundleRoot) { Set-ItResult -Skipped -Because 'could not locate bundle after zip extraction' }

            $tmp = New-TestDir
            try {
                & (Join-Path $bundleRoot 'install.ps1') -Target $tmp *> $null
                $LASTEXITCODE | Should -Be 0
                Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
                Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true
                Test-Path (Join-Path $tmp '.agentic\VERSION') | Should -Be $true
                (Get-Content -Raw (Join-Path $tmp '.agentic\install-manifest.tsv')) -match '\tseed\t' | Should -Be $true

                # the verifier should report UNSUPPORTED (3) for an empty project.
                # verify.ps1 resolves .agentic/checks.tsv from the current
                # location, so run it inside $tmp or it picks up the framework's
                # own checks at the repo root and recursively re-runs this suite.
                Push-Location $tmp
                try {
                    & (Join-Path $tmp '.agentic\scripts\verify.ps1')
                    $LASTEXITCODE | Should -Be 3
                }
                finally { Pop-Location }

                # exercise update, plan, prune, uninstall
                & (Join-Path $bundleRoot 'install.ps1') -Target $tmp *> $null
                $LASTEXITCODE | Should -Be 0
                & (Join-Path $bundleRoot 'install.ps1') -Target $tmp -Prune -Plan *> $null
                $LASTEXITCODE | Should -Be 0
                & (Join-Path $bundleRoot 'install.ps1') -Target $tmp -Uninstall -Plan *> $null
                $LASTEXITCODE | Should -Be 0
            }
            finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
        }
        finally { Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue }
    }

    It 'release zip does not leak development-only files' {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if (-not $bash) { Set-ItResult -Skipped -Because 'bash (git-bash/WSL) is required to build the bundle' }
        $version = (Get-Content -Raw (Join-Path $repoRoot '.agentic\VERSION')).Trim()
        & $bash.Source "scripts/build-bundle.sh" *> $null
        if ($LASTEXITCODE -ne 0) { throw 'build-bundle.sh failed' }
        $archive = Join-Path $repoRoot "dist\agentic-workflow-$version.zip"
        if (-not (Test-Path $archive)) { Set-ItResult -Skipped -Because 'zip archive was not created' }

        $extractDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-extract-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        try {
            $unzip = Get-Command unzip -ErrorAction SilentlyContinue
            if ($IsWindows -or (-not $unzip)) {
                Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
            } else {
                & unzip -q $archive -d $extractDir
            }
            $bundleRoot = Get-ChildItem -Recurse -Path $extractDir -Filter 'install.ps1' -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -match 'agentic-workflow-' } |
                Select-Object -First 1 -ExpandProperty DirectoryName
            if (-not $bundleRoot) { Set-ItResult -Skipped -Because 'could not locate bundle after zip extraction' }

            Test-Path (Join-Path $bundleRoot 'tests') | Should -Be $false
            Test-Path (Join-Path $bundleRoot '.github') | Should -Be $false
            Test-Path (Join-Path $bundleRoot 'docs') | Should -Be $false
            Test-Path (Join-Path $bundleRoot '.agentic\checks.tsv') | Should -Be $false
            Test-Path (Join-Path $bundleRoot 'CHANGELOG.md') | Should -Be $false
            Test-Path (Join-Path $bundleRoot 'README.md') | Should -Be $false
            Test-Path (Join-Path $bundleRoot 'CONTRIBUTING.md') | Should -Be $false
            Test-Path (Join-Path $bundleRoot 'SECURITY.md') | Should -Be $false
            Test-Path (Join-Path $bundleRoot '.agentic\templates\checks.tsv') | Should -Be $true
            Test-Path (Join-Path $bundleRoot '.agentic\scripts\verify.ps1') | Should -Be $true
            Test-Path (Join-Path $bundleRoot '.agentic\profiles\README.md') | Should -Be $true
            Test-Path (Join-Path $bundleRoot '.agentic\profiles\high-assurance.md') | Should -Be $true
            Test-Path (Join-Path $bundleRoot '.agentic\scripts\validate-task.ps1') | Should -Be $true
            Test-Path (Join-Path $bundleRoot '.agentic\templates\task.md') | Should -Be $true
        }
        finally { Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue }
    }

    # -----------------------------------------------------------------------
    # Release-to-release upgrade test: install from a v1.2.1-like bundle,
    # modify project state, then upgrade using the current bundle.
    # -----------------------------------------------------------------------

    It 'upgrade from v1.2.1 bundle to the current bundle preserves project state' {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if (-not $bash) { Set-ItResult -Skipped -Because 'bash (git-bash/WSL) is required to build the bundle' }

        # Verify the v1.2.1 tag exists and has the expected VERSION
        $v121Version = & git -C $repoRoot show 'v1.2.1:.agentic/VERSION' 2>$null
        if ($LASTEXITCODE -ne 0 -or $v121Version.Trim() -ne '1.2.1') {
            if ($env:CI -eq 'true') {
                throw 'required migration tag v1.2.1 is unavailable in CI'
            }
            Set-ItResult -Skipped -Because 'v1.2.1 tag not found or VERSION mismatch'
        }

        # Extract the actual v1.2.1 source tree and build its bundle
        $v121Src = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-v121-src-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $v121Src -Force | Out-Null
        & git -C $repoRoot archive v1.2.1 | tar -x -C $v121Src
        if ($LASTEXITCODE -ne 0) { throw 'git archive v1.2.1 failed' }
        & $bash.Source (Join-Path $v121Src 'scripts/build-bundle.sh') --no-archives *> $null
        if ($LASTEXITCODE -ne 0) { throw 'v1.2.1 build-bundle.sh failed' }
        $v121Dir = Join-Path $v121Src 'dist' 'agentic-workflow-1.2.1'

        # Build the current bundle
        $version = (Get-Content -Raw (Join-Path $repoRoot '.agentic\VERSION')).Trim()
        & $bash.Source "scripts/build-bundle.sh" --no-archives *> $null
        if ($LASTEXITCODE -ne 0) { throw 'build-bundle.sh failed' }
        $currentBundle = Join-Path $repoRoot "dist\agentic-workflow-$version"

        $tmp = New-TestDir
        try {
            # Step 1: Install from the real v1.2.1 bundle
            & (Join-Path $v121Dir 'install.ps1') -Target $tmp -Tools all *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true
            Test-Path (Join-Path $tmp 'CLAUDE.md') | Should -Be $true
            Test-Path (Join-Path $tmp 'GEMINI.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\VERSION')).Trim() | Should -Be '1.2.1'

            # Step 2: Add custom content outside merge blocks
            Add-Content -LiteralPath (Join-Path $tmp 'AGENTS.md') -Value "`n## Team notes`nkeep this content"
            Add-Content -LiteralPath (Join-Path $tmp '.aider.conf.yml') -Value '# custom aider config'

            # Step 3: Modify a managed file
            Add-Content -LiteralPath (Join-Path $tmp '.agentic\WORKFLOW.md') -Value '# adopter workflow override'

            # Step 4: Add a reviewed candidate (correct field order: requirement, check-id, dir, shell, command)
            Set-Content -LiteralPath (Join-Path $tmp '.agentic\checks.generated.tsv') -Value "required`tcustom-check`t.`tnpm`ttest"

            # Step 5: Upgrade using current bundle
            & (Join-Path $currentBundle 'install.ps1') -Target $tmp -Tools all *> $null
            $LASTEXITCODE | Should -Be 0

            # Step 6: Verify preservation
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'keep this content' | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp 'AGENTS.md')) -match 'AGENTIC-PROTOCOL-START' | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\WORKFLOW.md')) -match '# adopter workflow override' | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\checks.generated.tsv') | Should -Be $true
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.generated.tsv')) -match 'custom-check' | Should -Be $true
            # Verify the reviewed candidate is preserved exactly (byte-for-byte)
            (Get-Content -Raw (Join-Path $tmp '.agentic\checks.generated.tsv')).Trim() | Should -Be "required`tcustom-check`t.`tnpm`ttest"

            # Verify .aider.conf.yml custom content is preserved
            (Get-Content -Raw (Join-Path $tmp '.aider.conf.yml')) -match '# custom aider config' | Should -Be $true

            # Step 7: Exercise plan, prune, uninstall
            & (Join-Path $currentBundle 'install.ps1') -Target $tmp -Prune -Plan -Tools claude *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'GEMINI.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.aider.conf.yml') | Should -Be $true

            & (Join-Path $currentBundle 'install.ps1') -Target $tmp -Uninstall -Plan *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp 'AGENTS.md') | Should -Be $true

            # Step 8: Uninstall removes managed files, preserves seeds
            & (Join-Path $currentBundle 'install.ps1') -Target $tmp -Uninstall *> $null
            $LASTEXITCODE | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\VERSION') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\scripts\verify.ps1') | Should -Be $false
            Test-Path (Join-Path $tmp '.agentic\ARCHITECTURE.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\STATUS.md') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\checks.tsv') | Should -Be $true
        }
        finally {
            Remove-Item -Recurse -Force $v121Src -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }
}