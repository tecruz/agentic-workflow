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

        function Add-SkeletonSection {
            param([string]$Dir, [string]$Name, [string]$Approval, [string]$Check)
            $add = "`n## Walking skeleton`n`n- Slice: minimal end-to-end path`n- Integrated check: $Check`n- Skeleton approval: $Approval`n"
            Add-Content -LiteralPath (Join-Path $Dir ".agentic\tasks\$Name") -Value $add
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
            $r.Output | Should -Match '"protocol_version":"1.15.1"'
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

    It '-Skeleton blocks missing Walking skeleton section' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-914.md' '- None identified'
            $r = Invoke-Coord $tmp @('-Skeleton', '-Approve', '-Worker', 'echo hi', '.agentic/tasks/TASK-914.md')
            $r.Code | Should -Be 2
            $r.Output | Should -Match 'walking skeleton section is missing or malformed'
            Test-Path (Join-Path $tmp '.agentic\orchestration\worktrees\TASK-914') | Should -Be $false
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Skeleton blocks malformed Skeleton approval value' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-915.md' '- None identified'
            Add-SkeletonSection $tmp 'TASK-915.md' 'maybe' 'true'
            $r = Invoke-Coord $tmp @('-Skeleton', '-Approve', '-Worker', 'echo hi', '.agentic/tasks/TASK-915.md')
            $r.Code | Should -Be 2
            $r.Output | Should -Match "must be 'pending' or 'approved by <approver> on YYYY-MM-DD'"
            Test-Path (Join-Path $tmp '.agentic\orchestration\worktrees\TASK-915') | Should -Be $false
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Skeleton blocks pending approval with -Push' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-916.md' '- None identified'
            Add-SkeletonSection $tmp 'TASK-916.md' 'pending' 'true'
            $r = Invoke-Coord $tmp @('-Skeleton', '-Approve', '-Push', '-Worker', 'echo hi', '.agentic/tasks/TASK-916.md')
            $r.Code | Should -Be 2
            $r.Output | Should -Match 'SKELETON_APPROVAL_PENDING'
            Test-Path (Join-Path $tmp '.agentic\orchestration\worktrees\TASK-916') | Should -Be $false
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Skeleton blocks pending approval with -Cleanup' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-917.md' '- None identified'
            Add-SkeletonSection $tmp 'TASK-917.md' 'pending' 'true'
            $r = Invoke-Coord $tmp @('-Skeleton', '-Approve', '-Cleanup', '-Worker', 'echo hi', '.agentic/tasks/TASK-917.md')
            $r.Code | Should -Be 2
            $r.Output | Should -Match 'SKELETON_APPROVAL_PENDING'
            Test-Path (Join-Path $tmp '.agentic\orchestration\worktrees\TASK-917') | Should -Be $false
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Skeleton emits skeleton_checkpoint before worker_completed when the check passes' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-918.md' '- None identified'
            Add-SkeletonSection $tmp 'TASK-918.md' 'approved by Tester on 2026-09-28' 'true'
            $r = Invoke-Coord $tmp @('-Skeleton', '-Approve', '-Worker', 'echo hi', '-Events', '.agentic/runs/sk.jsonl', '.agentic/tasks/TASK-918.md')
            $r.Code | Should -Be 0
            $eventsPath = Join-Path $tmp '.agentic\runs\sk.jsonl'
            Test-Path -LiteralPath $eventsPath | Should -Be $true
            $lines = Get-Content -LiteralPath $eventsPath
            $skIdx = [array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match 'skeleton_checkpoint' })
            $wcIdx = [array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match 'worker_completed' })
            $skIdx | Should -BeGreaterOrEqual 0
            $wcIdx | Should -BeGreaterThan $skIdx
            $lines[-1] | Should -Match '"result":"PASS"'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Skeleton approved approval allows -Cleanup after a passing check' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-920.md' '- None identified'
            Add-SkeletonSection $tmp 'TASK-920.md' 'approved by Tester on 2026-09-28' 'true'
            $r = Invoke-Coord $tmp @('-Skeleton', '-Approve', '-Cleanup', '-Worker', 'echo hi', '.agentic/tasks/TASK-920.md')
            $r.Code | Should -Be 0
            $r.Output | Should -Match 'checkpoint passed'
            Test-Path (Join-Path $tmp '.agentic\orchestration\worktrees\TASK-920') | Should -Be $false
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It '-Skeleton fails the run with SKELETON_CHECK_FAILED when the check fails' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-919.md' '- None identified'
            Add-SkeletonSection $tmp 'TASK-919.md' 'approved by Tester on 2026-09-28' 'false'
            $r = Invoke-Coord $tmp @('-Skeleton', '-Approve', '-Worker', 'echo hi', '-Events', '.agentic/runs/skf.jsonl', '.agentic/tasks/TASK-919.md')
            $r.Code | Should -Be 1
            $eventsPath = Join-Path $tmp '.agentic\runs\skf.jsonl'
            Get-Content -LiteralPath $eventsPath -Raw | Should -Match '"reason_code":"SKELETON_CHECK_FAILED"'
            (Get-Content -LiteralPath $eventsPath -Raw) | Should -Not -Match 'skeleton_checkpoint'
            (Get-Content -LiteralPath $eventsPath)[-1] | Should -Match '"result":"FAIL"'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
}
