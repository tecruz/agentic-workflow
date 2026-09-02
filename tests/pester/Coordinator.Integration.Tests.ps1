# coordinator.ps1 — cross-platform integration tests (Pester 5).
# Drives a real worker through a complete orchestration lifecycle.

Describe 'coordinator.ps1 integration' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $coord = Join-Path $repoRoot '.agentic\orchestration\coordinator.ps1'

        function New-TestDir {
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-integ-ps-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            return $d
        }

        function New-TaskFile {
            param([string]$Dir, [string]$Name, [string]$Approval, [string]$Title = '')
            $taskDir = Join-Path $Dir '.agentic\tasks'
            New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
            if ([string]::IsNullOrEmpty($Title)) { $Title = $Name }
            $content = @"
# $Title

## Status

Status: planned
Updated: 2026-09-02

## Risk profile

Profile: standard

## Profile rationale

Integration test.

## Acceptance criteria

- AC-1: Worker executes successfully.
- AC-2: Events stream captures full lifecycle.

## Approval gates

$Approval

## Context modules

- None selected -- integration test

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
                $out = & pwsh -NoProfile -File $coord @Args 2>$null
                return @{ Code = $LASTEXITCODE; Output = ($out | Out-String).Trim() }
            } finally { Pop-Location }
        }
    }

    It 'complete lifecycle: worker success with events stream' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-INTEG-PS-001.md' '- [x] AG-1: Approved on 2026-09-02' 'TASK-INTEG-PS-001'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'echo worker-executed', '-Events', '.agentic/runs/integ.jsonl', '.agentic/tasks/TASK-INTEG-PS-001.md')
            $r.Code | Should -Be 0

            $eventsFile = Join-Path $tmp '.agentic\runs\integ.jsonl'
            Test-Path $eventsFile | Should -Be $true

            $lines = Get-Content -LiteralPath $eventsFile
            $lines.Count | Should -BeGreaterOrEqual 4
            $lines[0] | Should -Match 'orchestration_started'
            $lines[-1] | Should -Match 'orchestration_completed'

            $hasWorkerStarted = $lines | Where-Object { $_ -match 'worker_started' }
            $hasWorkerStarted | Should -Not -BeNullOrEmpty
            $hasWorkerCompleted = $lines | Where-Object { $_ -match 'worker_completed' }
            $hasWorkerCompleted | Should -Not -BeNullOrEmpty

            foreach ($line in $lines) {
                { $line | ConvertFrom-Json } | Should -Not -Throw
            }

            $result = $lines[-1] | ConvertFrom-Json
            $result.result | Should -Be 'PASS'
            $result.exit_code | Should -Be 0
            $result.event | Should -Be 'orchestration_completed'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'complete lifecycle: worker failure with events stream' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-INTEG-PS-002.md' '- [x] AG-1: Approved on 2026-09-02' 'TASK-INTEG-PS-002'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'exit 1', '-Events', '.agentic/runs/integ-fail.jsonl', '.agentic/tasks/TASK-INTEG-PS-002.md')
            $r.Code | Should -Be 1

            $eventsFile = Join-Path $tmp '.agentic\runs\integ-fail.jsonl'
            $lines = Get-Content -LiteralPath $eventsFile
            $lines[0] | Should -Match 'orchestration_started'
            $lines[-1] | Should -Match 'orchestration_completed'

            $result = $lines[-1] | ConvertFrom-Json
            $result.result | Should -Be 'FAIL'
            $result.exit_code | Should -Be 1

            $wc = $lines | Where-Object { $_ -match 'worker_completed' }
            $wcObj = ($wc | ConvertFrom-Json)
            $wcObj.status | Should -Be 'FAIL'
            $wcObj.reason_code | Should -Be 'WORKER_FAILED'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'complete lifecycle: JSON output with cleanup' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-INTEG-PS-003.md' '- [x] AG-1: Approved on 2026-09-02' 'TASK-INTEG-PS-003'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'true', '-Format', 'Json', '-Cleanup', '.agentic/tasks/TASK-INTEG-PS-003.md')
            $r.Code | Should -Be 0
            $jsonLine = ($r.Output -split "`n") | Where-Object { $_ -match '"kind":"orchestration_result"' } | Select-Object -First 1
            $jsonLine | Should -Not -BeNullOrEmpty
            $json = $jsonLine | ConvertFrom-Json
            $json.result | Should -Be 'PASS'
            $json.exit_code | Should -Be 0
            $json.protocol_version | Should -Be '1.8.0'
            $json.kind | Should -Be 'orchestration_result'
            $json.workers.Count | Should -Be 1
            $json.workers[0].status | Should -Be 'PASS'
            $json.workers[0].exit_code | Should -Be 0
            $json.workers[0].duration_ms | Should -BeGreaterOrEqual 0
            $json.summary.passed | Should -Be 1
            $json.summary.failed | Should -Be 0
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'no raw command leakage in events' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-INTEG-PS-004.md' '- [x] AG-1: Approved on 2026-09-02' 'TASK-INTEG-PS-004'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'echo secret-command-line', '-Events', '.agentic/runs/noleak.jsonl', '.agentic/tasks/TASK-INTEG-PS-004.md')
            $r.Code | Should -Be 0
            $eventsFile = Join-Path $tmp '.agentic\runs\noleak.jsonl'
            $content = Get-Content -Raw -LiteralPath $eventsFile
            $content | Should -Not -Match 'secret-command-line'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'task file path is project-relative in JSON output' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-INTEG-PS-005.md' '- [x] AG-1: Approved on 2026-09-02' 'TASK-INTEG-PS-005'
            $r = Invoke-Coord $tmp @('-Approve', '-Worker', 'echo hi', '-Format', 'Json', '.agentic/tasks/TASK-INTEG-PS-005.md')
            $r.Code | Should -Be 0
            $jsonLine = ($r.Output -split "`n") | Where-Object { $_ -match '"kind":"orchestration_result"' } | Select-Object -First 1
            $jsonLine | Should -Not -BeNullOrEmpty
            $jsonLine | Should -Not -Match ([regex]::Escape($tmp))
            $jsonLine | Should -Match 'TASK-INTEG-PS-005'
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }

    It 'stale lock from dead PID is cleaned up and worktree succeeds' {
        $tmp = New-TestDir
        try {
            Init-GitRepo $tmp
            New-TaskFile $tmp 'TASK-INTEG-PS-006.md' '- [x] AG-1: Approved on 2026-09-02' 'TASK-INTEG-PS-006'
            $lockDir = Join-Path $tmp '.agentic\orchestration\worktrees'
            New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $lockDir 'TASK-INTEG-PS-006.lock') -Value '999999' -NoNewline
            $r = Invoke-Coord $tmp @('-Approve', '.agentic/tasks/TASK-INTEG-PS-006.md')
            $r.Code | Should -Be 0
        } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
}
