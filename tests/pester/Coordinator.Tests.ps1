# coordinator.ps1 — isolated worktree and approval tests (Pester 5).
Describe 'coordinator.ps1' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $coord = Join-Path $repoRoot '.agentic\orchestration\coordinator.ps1'

        function New-TestDir {
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-coord-ps-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            return $d
        }

        function New-TaskFile {
            param([string]$Dir, [string]$Name, [string]$Approval)
            $taskDir = Join-Path $Dir '.agentic\tasks'
            New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
            $content = @"
# $Name

## Status

Status: planned
Updated: 2026-08-28

## Risk profile

Profile: standard

## Profile rationale

Test.

## Acceptance criteria

- AC-1: Stub.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | test | passed |

## Approval gates

$Approval

## Context modules

- None selected — test

## Verification

### Baseline

- baseline

### Final

- final

## Files changed

- file

## Remaining risks

- None identified
"@
            Set-Content -LiteralPath (Join-Path $taskDir $Name) -Value $content
        }

        function Init-GitRepo {
            param([string]$Dir)
            git -C $Dir init -q 2>$null
            git -C $Dir config user.email "test@test.com" 2>$null
            git -C $Dir config user.name "Test" 2>$null
            git -C $Dir commit --allow-empty -m "init" -q 2>$null
        }

        function Invoke-Coord {
            param([string]$Dir, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
            Push-Location $Dir
            try {
                $out = & pwsh -NoProfile -File $coord @Args 2>&1
                return @{ Code = $LASTEXITCODE; Output = ($out | Out-String).Trim() }
            } finally { Pop-Location }
        }
    }

    It 'shows help with -Help' {
        $r = Invoke-Coord $repoRoot @('-Help')
        $r.Code | Should -Be 0
        $r.Output | Should -Match 'Usage'
    }

    It 'blocks spawning without -Approve' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-900.md' '- [x] AG-1: Approved by Tester on 2026-08-28'
            $r = Invoke-Coord $tmp @('-Worker', 'exit 0', '.agentic/tasks/TASK-900.md')
            $r.Code | Should -Be 2
            Test-Path (Join-Path $tmp '.agentic\orchestration\worktrees\TASK-900') | Should -Be $false
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'blocks unchecked gate even with -Approve' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-901.md' '- [ ] AG-1: Pending'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'exit 0', '.agentic/tasks/TASK-901.md')
            $r.Code | Should -Be 2
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'creates isolated worktree on approved task' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-902.md' '- [x] AG-1: Approved by Tester on 2026-08-28'
            $r = Invoke-Coord $tmp @('-Approve', '.agentic/tasks/TASK-902.md')
            $r.Code | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\orchestration\worktrees\TASK-902') | Should -Be $true
            # Cleanup
            Invoke-Coord $tmp @('-Approve', '-Cleanup', '.agentic/tasks/TASK-902.md') | Out-Null
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'worker success produces PASS json' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-904.md' '- [x] AG-1: Approved by Tester on 2026-08-28'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'exit 0', '-Format', 'Json', '.agentic/tasks/TASK-904.md')
            $r.Code | Should -Be 0
            $r.Output | Should -Match '"result":"PASS"'
            $r.Output | Should -Match '"protocol_version":"1.11.0"'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'worker failure produces FAIL' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-905.md' '- [x] AG-1: Approved by Tester on 2026-08-28'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'exit 1', '-Format', 'Json', '.agentic/tasks/TASK-905.md')
            $r.Code | Should -Be 1
            $r.Output | Should -Match '"result":"FAIL"'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'events stream contains terminal event last' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-907.md' '- [x] AG-1: Approved by Tester on 2026-08-28'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'exit 0', '-Events', '.agentic/runs/coord.jsonl', '.agentic/tasks/TASK-907.md')
            $r.Code | Should -Be 0
            Test-Path (Join-Path $tmp '.agentic\runs\coord.jsonl') | Should -Be $true
            $lines = Get-Content -LiteralPath (Join-Path $tmp '.agentic\runs\coord.jsonl')
            $lines[0] | Should -Match 'orchestration_started'
            $lines[-1] | Should -Match 'orchestration_completed'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Format Json and -Events are mutually exclusive' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-908.md' '- [x] AG-1: Approved by Tester on 2026-08-28'
            $r = Invoke-Coord $tmp @('-Approve', '-Format', 'Json', '-Events', '.agentic/runs/x.jsonl', '.agentic/tasks/TASK-908.md')
            $r.Code | Should -Be 1
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'None identified gates allow spawning with only -Approve' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-911.md' '- None identified'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'exit 0', '-Format', 'Json', '.agentic/tasks/TASK-911.md')
            $r.Code | Should -Be 0
            $r.Output | Should -Match '"result":"PASS"'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'fresh install creates coordinator twins and schemas as managed' {
        $tmp = New-TestDir
        $install = Join-Path $repoRoot 'install.ps1'
        try {
            & $install -Target $tmp *> $null
            Test-Path (Join-Path $tmp '.agentic\orchestration\coordinator.ps1') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\schemas\orchestration-result-v1.schema.json') | Should -Be $true
            Test-Path (Join-Path $tmp '.agentic\schemas\orchestration-events-v1.schema.json') | Should -Be $true
            $manifest = Get-Content -Raw (Join-Path $tmp '.agentic\install-manifest.tsv')
            $manifest -match "\.agentic/orchestration/coordinator\.ps1`tmanaged" | Should -Be $true
            $manifest -match "\.agentic/schemas/orchestration-result-v1\.schema\.json`tmanaged" | Should -Be $true
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
}
