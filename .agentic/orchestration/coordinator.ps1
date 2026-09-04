#Requires -Version 7.0
<#
.SYNOPSIS
    coordinator.ps1 — isolated multi-agent task coordination (ADR-0011).

.DESCRIPTION
    Provides isolated worktree creation, generic worker spawning, observable
    JSONL events and versioned result contracts, with explicit approval gates.
    PowerShell twin of coordinator.sh; observable behavior is held to identical
    classifications by shared fixtures.

.PARAMETER TaskFile
    Task file to coordinate.

.PARAMETER Worker
    Worker command to execute inside the worktree (falls back to AGENTIC_WORKER_CMD).

.PARAMETER Approve
    Approve spawning workers (requires checked AG-N gate).

.PARAMETER Push
    Approve remote writes (requires -Approve).

.PARAMETER Cleanup
    Remove worktree after completion.

.PARAMETER Format
    Output format: Text (default) or Json.

.PARAMETER Events
    JSONL event stream destination (must be under .agentic/runs/).

.PARAMETER EventsForce
    Overwrite existing event file.

.EXAMPLE
    ./.agentic/orchestration/coordinator.ps1 -Approve -Worker "npm test" .agentic/tasks/TASK-009.md
#>

[CmdletBinding()]
param(
    [Parameter(Position=0, ValueFromRemainingArguments=$false)]
    [string] $TaskFile,
    [string] $Worker = "",
    [switch] $Approve,
    [switch] $Push,
    [switch] $Cleanup,
    [ValidateSet("Text", "Json")]
    [string] $Format = "Text",
    [string] $Events = "",
    [switch] $EventsForce,
    [switch] $Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProtocolVersion = "1.10.0"

if ($Help) {
    @"
Usage: coordinator.ps1 [options] <task-file>

Isolated multi-agent task coordination (ADR-0011).

Options:
  -Worker <cmd>        Worker command to run inside the worktree
  -Approve             Approve spawning workers (requires checked AG-N gate)
  -Push                Approve remote writes (requires -Approve)
  -Cleanup             Remove worktree after completion
  -Format <Text|Json>  Output format (default Text)
  -Events <path>       JSONL event stream (must be under .agentic/runs/)
  -EventsForce         Overwrite existing event file
  -Help                Show this help
"@
    exit 0
}

if ($Push -and -not $Approve) {
    Write-Host "ERROR: -Push requires -Approve." -ForegroundColor Red
    exit 2
}

# Worker fallback from env
if ([string]::IsNullOrWhiteSpace($Worker) -and $env:AGENTIC_WORKER_CMD) {
    $Worker = $env:AGENTIC_WORKER_CMD
}

# Format/Events mutual exclusion (case-insensitive)
if ($Format -ieq "Json" -and -not [string]::IsNullOrWhiteSpace($Events)) {
    Write-Host "ERROR: -Format Json and -Events cannot be used together." -ForegroundColor Red
    Write-Host "Use JSON stdout OR an event stream, not both." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($TaskFile)) {
    Write-Host "ERROR: task file is required." -ForegroundColor Red
    exit 1
}

$ProjectRoot = (Get-Location).Path
$ProjectRootPhysical = try { (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path } catch { $ProjectRoot }

function ConvertTo-PortablePath {
    param([string]$Path)
    return $Path.Replace('\', '/')
}

function Get-DisplayPath {
    param([string]$Path)
    $norm = ConvertTo-PortablePath $Path
    if ($norm.StartsWith("./")) { $norm = $norm.Substring(2) }
    $rootPortable = ConvertTo-PortablePath $ProjectRootPhysical
    if ($norm -eq $rootPortable) { return "." }
    if ($norm.StartsWith("$rootPortable/", [StringComparison]::Ordinal)) {
        return "./" + $norm.Substring($rootPortable.Length + 1)
    }
    # Also check logical ProjectRoot
    $logical = ConvertTo-PortablePath $ProjectRoot
    if ($norm -eq $logical) { return "." }
    if ($norm.StartsWith("$logical/", [StringComparison]::Ordinal)) {
        return "./" + $norm.Substring($logical.Length + 1)
    }
    if ([System.IO.Path]::IsPathRooted($norm) -or $norm -match '^[A-Za-z]:') {
        return [System.IO.Path]::GetFileName($norm)
    }
    return $norm
}

function Test-LexicallyWithinRoot {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $false }
    $top = 0
    $p = $Path
    while ($p.Length -gt 0) {
        $seg = if ($p.Contains('/')) { $p.Substring(0, $p.IndexOf('/')); $p = $p.Substring($p.IndexOf('/') + 1) } elseif ($p.Contains('\')) { $p.Substring(0, $p.IndexOf('\')); $p = $p.Substring($p.IndexOf('\') + 1) } else { $s = $p; $p = ""; $s }
        switch ($seg) {
            "" { }
            "." { }
            ".." {
                if ($top -gt 0) { $top-- } else { return $false }
            }
            default { $top++ }
        }
    }
    return $true
}

function Resolve-PhysicalPath {
    param([string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetPathRoot($full)
        $current = $root
        $parts = $full.Substring($root.Length) -split '[/\\]' | Where-Object { $_ -ne '' }
        $maxHops = 32
        foreach ($part in $parts) {
            $current = Join-Path $current $part
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            $hops = 0
            while ($true) {
                $key = [System.IO.Path]::GetFullPath($current)
                if (-not $seen.Add($key)) {
                    throw "symbolic-link cycle detected while resolving '$Path'"
                }
                if ($hops -gt $maxHops) {
                    throw "symbolic-link chain exceeds $maxHops hops while resolving '$Path'"
                }
                $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
                if (-not $item -or [string]::IsNullOrEmpty($item.Target)) { break }
                $hops++
                if ([System.IO.Path]::IsPathRooted($item.Target)) {
                    $current = $item.Target
                }
                else {
                    $parent = [System.IO.Path]::GetDirectoryName($current)
                    if ([string]::IsNullOrEmpty($parent)) {
                        $parent = [System.IO.Path]::GetPathRoot($current)
                    }
                    $current = Join-Path $parent $item.Target
                }
            }
        }
        return [System.IO.Path]::GetFullPath($current)
    } catch { return $null }
}

function Test-SafeDetectDestination {
    param([string]$Leaf)
    $leafPath = $Leaf
    while ((-not (Test-Path -LiteralPath $leafPath)) -and (-not (Test-Path -LiteralPath $leafPath -PathType Leaf)) -and ($leafPath -ne (Split-Path -Parent $leafPath))) {
        $parent = Split-Path -Parent $leafPath
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $leafPath) { break }
        $leafPath = $parent
    }
    try {
        $resolved = Resolve-PhysicalPath $leafPath
        $resolvedRoot = Resolve-PhysicalPath $ProjectRootPhysical
        if ($null -eq $resolved -or $null -eq $resolvedRoot) { return $false }
        $rootTrim = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $inside = $resolved.Equals($rootTrim, [StringComparison]::OrdinalIgnoreCase) -or $resolved.StartsWith($rootTrim + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        if ($IsWindows) { return $inside } else { return $resolved.StartsWith($rootTrim, [StringComparison]::Ordinal) -or $resolved.Equals($rootTrim, [StringComparison]::Ordinal) }
    } catch { return $false }
}

function Test-SafeEventsDestination {
    param([string]$Dest)
    $d = ConvertTo-PortablePath $Dest
    if ([System.IO.Path]::IsPathRooted($d)) { return $false }
    $norm = $d
    if ($norm.StartsWith("./")) { $norm = $norm.Substring(2) }
    if (-not $norm.StartsWith(".agentic/runs/")) { return $false }
    $segs = $norm.Split('/')
    foreach ($s in $segs) { if ($s -eq "" -or $s -eq "." -or $s -eq "..") { return $false } }
    return Test-SafeDetectDestination $norm
}

function Test-SafeWorktreeDestination {
    param([string]$Dest)
    $d = ConvertTo-PortablePath $Dest
    if ([System.IO.Path]::IsPathRooted($d)) { return $false }
    $norm = $d
    if ($norm.StartsWith("./")) { $norm = $norm.Substring(2) }
    if (-not $norm.StartsWith(".agentic/orchestration/worktrees/")) { return $false }
    $segs = $norm.Split('/')
    foreach ($s in $segs) { if ($s -eq "" -or $s -eq "." -or $s -eq "..") { return $false } }
    return Test-SafeDetectDestination $norm
}

function Write-Log {
    param([string]$Message)
    if ($Format -ieq "Json") {
        [Console]::Error.WriteLine($Message)
    } else {
        Write-Host $Message
    }
}

function Write-Event {
    param([string]$Payload)
    if (-not [string]::IsNullOrWhiteSpace($Events)) {
        Add-Content -LiteralPath $Events -Value $Payload -Encoding utf8NoBOM
    }
}

function Emit-OrchestrationStarted { Write-Event '{"event":"orchestration_started"}' }

function Emit-WorkerStarted {
    param([string]$WorkerId, [string]$CwdRel)
    $obj = [ordered]@{ event = "worker_started"; worker_id = $WorkerId; working_directory = $CwdRel }
    Write-Event ($obj | ConvertTo-Json -Compress)
}

function Emit-WorkerCompleted {
    param([string]$WorkerId, [string]$Status, $ExitCode, [int]$DurationMs, [string]$CwdRel, $ReasonCode)
    $obj = [ordered]@{
        event = "worker_completed"
        worker_id = $WorkerId
        status = $Status
        exit_code = $ExitCode
        duration_ms = $DurationMs
        working_directory = $CwdRel
        reason_code = $ReasonCode
    }
    Write-Event ($obj | ConvertTo-Json -Compress)
}

function Emit-OrchestrationCompleted {
    param([string]$Result, [int]$ExitCode)
    $obj = [ordered]@{ event = "orchestration_completed"; result = $Result; exit_code = $ExitCode }
    Write-Event ($obj | ConvertTo-Json -Compress)
}

function Output-OrchestrationJson {
    param([string]$Result, [int]$ExitCode, [string]$WorkersJson, [string]$SummaryJson, [string]$TaskDisp, [string]$WorktreeDisp)
    $workersArray = if ([string]::IsNullOrWhiteSpace($WorkersJson)) { "[]" } else { "[$WorkersJson]" }
    # TaskDisp and Worktree already escaped via ConvertTo-Json
    $taskEscaped = (ConvertTo-Json $TaskDisp -Compress).Trim('"')
    # Simpler: use the display values directly escaped via JSON
    $taskJsonVal = ConvertTo-Json $TaskDisp -Compress
    $worktreeJsonVal = ConvertTo-Json $WorktreeDisp -Compress
    $json = '{"schema_version":1,"protocol_version":"' + $ProtocolVersion + '","kind":"orchestration_result","result":"' + $Result + '","exit_code":' + $ExitCode + ',"task_file":' + $taskJsonVal + ',"worktree":' + $worktreeJsonVal + ',"workers":' + $workersArray + ',"summary":' + $SummaryJson + '}'
    Write-Output $json
}

function Complete-Orchestration {
    param([string]$Result, [int]$ExitCode, [string]$WorkersJson, [string]$SummaryJson, [string]$TaskDisp, [string]$WorktreeDisp)
    if (-not [string]::IsNullOrWhiteSpace($Events)) {
        try { Emit-OrchestrationCompleted $Result $ExitCode } catch { Write-Host "ERROR: failed to finalize orchestration event stream." -ForegroundColor Red; exit 1 }
    }
    if ($Format -ieq "Json") {
        try { Output-OrchestrationJson $Result $ExitCode $WorkersJson $SummaryJson $TaskDisp $WorktreeDisp } catch { Write-Host "ERROR: failed to write JSON orchestration result." -ForegroundColor Red; exit 1 }
    }
    exit $ExitCode
}

# Validate task file existence
if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    $disp = Get-DisplayPath $TaskFile
    if ($Format -ieq "Json") {
        $json = '{"schema_version":1,"protocol_version":"' + $ProtocolVersion + '","kind":"orchestration_result","result":"BLOCKED","exit_code":2,"task_file":' + (ConvertTo-Json $disp -Compress) + ',"worktree":".","workers":[],"summary":{"workers_defined":0,"workers_run":0,"passed":0,"failed":0,"blocked":1}}'
        Write-Output $json
        exit 2
    } else {
        Write-Host "ERROR: task file not found: $TaskFile" -ForegroundColor Red
        exit 2
    }
}

$base = [System.IO.Path]::GetFileName($TaskFile)
$taskId = if ($base.Contains('.')) { $base.Substring(0, $base.LastIndexOf('.')) } else { $base }
if ([string]::IsNullOrWhiteSpace($taskId) -or -not ($taskId -match '^[A-Za-z0-9][A-Za-z0-9._-]*$')) {
    Write-Host "ERROR: task ID '$taskId' contains invalid characters." -ForegroundColor Red
    exit 1
}

$worktreeRel = ".agentic/orchestration/worktrees/$taskId"
$worktreeAbs = Join-Path $ProjectRootPhysical $worktreeRel
$lockFile = Join-Path $ProjectRootPhysical ".agentic/orchestration/worktrees/$taskId.lock"

if (-not (Test-SafeWorktreeDestination $worktreeRel)) {
    Write-Host "ERROR: worktree destination is not safely inside the project root." -ForegroundColor Red
    exit 1
}

# Approval gates inspection (mirrors bash logic)
$approvalContent = ""
$inGates = $false
$inFence = $false
$inComment = $false
foreach ($rawLine in Get-Content -LiteralPath $TaskFile) {
    $line = $rawLine.TrimEnd("`r")
    if ($inComment) {
        if ($line.Contains('-->')) { $inComment = $false }
        continue
    }
    if ($line.Contains('<!--')) {
        if ($line.Contains('-->')) { continue } else { $inComment = $true; continue }
    }
    if ($inFence) {
        if ($line.StartsWith('```')) { $inFence = $false }
        continue
    }
    if ($line.StartsWith('```')) { $inFence = $true; continue }
    if ($line -match '^\s*>') { continue }
    if ($line -match '^##\s+') {
        $heading = $line.Substring(3).Trim().ToLowerInvariant() -replace '\s+', ' '
        if ($heading -eq "approval gates") { $inGates = $true }
        else { if ($inGates) { break } }
        continue
    }
    if ($inGates) { $approvalContent += "$line`n" }
}

$hasNone = $false
if ($approvalContent -match '(?im)^\s*[-*+]\s*none\s+identified') { $hasNone = $true }
$checked = ([regex]::Matches($approvalContent, '\[[xX]\]\s*AG-[0-9]+\s*:')).Count
$unchecked = ([regex]::Matches($approvalContent, '\[\s\]\s*AG-[0-9]+\s*:')).Count
$malformed = $false
$gateCount = 0
foreach ($agLine in $approvalContent -split "`n") {
    $trim = $agLine.Trim()
    if ([string]::IsNullOrWhiteSpace($trim)) { continue }
    $low = $trim.ToLowerInvariant()
    $bodyLow = $low -replace '^[-*+]\s+', ''
    $bodyLow = $bodyLow.Trim()
    if ($bodyLow -eq "none identified") { continue }
    if ($low -match '^\s*[-*+]\s*\[[ xX]\]') {
        if ($low -notmatch '^\s*[-*+]\s*\[[ xX]\]\s*ag-[0-9]+\s*:') { $malformed = $true }
        else { $gateCount++ }
    } elseif ($low -match 'ag-[0-9]+') { $malformed = $true }
}

$needsApproval = (-not $hasNone -and $gateCount -gt 0)

if ($malformed) {
    $disp = Get-DisplayPath $TaskFile
    if ($Format -ieq "Json") {
        $json = '{"schema_version":1,"protocol_version":"' + $ProtocolVersion + '","kind":"orchestration_result","result":"BLOCKED","exit_code":2,"task_file":' + (ConvertTo-Json $disp -Compress) + ',"worktree":".","workers":[],"summary":{"workers_defined":0,"workers_run":0,"passed":0,"failed":0,"blocked":1}}'
        Write-Output $json
        exit 2
    } else {
        Write-Host "ERROR: malformed approval gates in task file." -ForegroundColor Red
        exit 2
    }
}

function Fail-WithResult {
    param([string]$Result, [int]$ExitCode, [string]$Message)
    $disp = Get-DisplayPath $TaskFile
    $wtDisp = "./$worktreeRel"
    if ($Format -ieq "Json") {
        $summary = if ($Result -eq "FAIL") { '{"workers_defined":1,"workers_run":1,"passed":0,"failed":1,"blocked":0}' } else { '{"workers_defined":0,"workers_run":0,"passed":0,"failed":0,"blocked":1}' }
        $workers = if ($Result -eq "FAIL") { '{"worker_id":' + (ConvertTo-Json $taskId -Compress) + ',"status":"FAIL","exit_code":null,"duration_ms":0,"reason_code":"WORKER_FAILED"}' } else { "" }
        Complete-Orchestration $Result $ExitCode $workers $summary $disp $wtDisp
    } else {
        Write-Host "ERROR: $Message" -ForegroundColor Red
        if (-not [string]::IsNullOrWhiteSpace($Events)) { try { Emit-OrchestrationCompleted $Result $ExitCode } catch {} }
        exit $ExitCode
    }
}

if ($needsApproval -or $Push) {
    if (-not $Approve) { Fail-WithResult "BLOCKED" 2 "spawning workers requires -Approve and a checked AG-N gate." }
    if ($unchecked -gt 0) { Fail-WithResult "BLOCKED" 2 "task has unchecked approval gates." }
}
if (-not [string]::IsNullOrWhiteSpace($Worker) -or $Push) {
    if (-not $Approve) { Fail-WithResult "BLOCKED" 2 "spawning workers requires -Approve." }
}

# Check git
try { $null = Get-Command git -ErrorAction Stop } catch { Fail-WithResult "BLOCKED" 2 "git is required for isolated worktrees." }
try { git rev-parse --is-inside-work-tree 2>$null | Out-Null; if ($LASTEXITCODE -ne 0) { throw "not git" } } catch { Fail-WithResult "BLOCKED" 2 "not inside a git worktree." }

# Event stream initialization
$eventsScratch = $null
if (-not [string]::IsNullOrWhiteSpace($Events)) {
    if (-not (Test-SafeEventsDestination $Events)) {
        Write-Host "ERROR: events destination must be a relative path inside .agentic/runs/. '$Events' is not allowed." -ForegroundColor Red
        exit 1
    }
    if ((Test-Path -LiteralPath $Events) -and -not (Test-Path -LiteralPath $Events -PathType Leaf)) {
        Write-Host "ERROR: event destination exists and is not a regular file." -ForegroundColor Red
        exit 1
    }
    if ((Test-Path -LiteralPath $Events) -and -not $EventsForce) {
        Write-Host "ERROR: refusing to overwrite existing event file '$Events'. Use -EventsForce to overwrite." -ForegroundColor Red
        exit 1
    }
    $dir = Split-Path -Parent $Events
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $eventsScratch = Join-Path (Split-Path -Parent $Events) (".orchestration-events." + [System.IO.Path]::GetRandomFileName())
    if (Test-Path -LiteralPath $eventsScratch) { Remove-Item -LiteralPath $eventsScratch -Force }
    '{"event":"orchestration_started"}' | Set-Content -LiteralPath $eventsScratch -Encoding utf8NoBOM
    if ($EventsForce) {
        try { Move-Item -LiteralPath $eventsScratch -Destination $Events -Force -ErrorAction Stop } catch { Write-Host "ERROR: failed to promote event stream (forced)." -ForegroundColor Red; Remove-Item -LiteralPath $eventsScratch -Force -ErrorAction SilentlyContinue; exit 1 }
        if (-not (Test-Path -LiteralPath $Events -PathType Leaf)) { Write-Host "ERROR: event promotion produced no regular file." -ForegroundColor Red; exit 1 }
        $eventsScratch = $null
    } else {
        try {
            # Atomic no-clobber via .NET File.Move without overwrite? PowerShell Move-Item -Force would overwrite, so we check existence first and use hard link fallback via [IO.File]::Move?
            # Use New-Item hardlink approach: try to create hard link? Simpler: use Move without Force and catch EEXIST.
            if (Test-Path -LiteralPath $Events) { throw "exists" }
            Move-Item -LiteralPath $eventsScratch -Destination $Events -ErrorAction Stop
            $eventsScratch = $null
        } catch {
            Write-Host "ERROR: refusing to overwrite existing event file '$Events'. Use -EventsForce to overwrite." -ForegroundColor Red
            Remove-Item -LiteralPath $eventsScratch -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }
}

# Lock handling
$lockDir = Split-Path -Parent $lockFile
if (-not [string]::IsNullOrWhiteSpace($lockDir)) { New-Item -ItemType Directory -Path $lockDir -Force | Out-Null }
if (Test-Path -LiteralPath $lockFile) {
    try {
        $oldPidStr = Get-Content -LiteralPath $lockFile -ErrorAction Stop
        $oldPid = [int]$oldPidStr.Trim()
        $proc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if ($null -ne $proc) { Fail-WithResult "BLOCKED" 2 "task is already locked by PID $oldPid." }
        else { Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue }
    } catch {}
}
try {
    # Atomic via FileShare.None? Use New-Item with -Force:false
    $null = New-Item -Path $lockFile -ItemType File -Value $PID -Force:$false -ErrorAction Stop
} catch {
    if (Test-Path -LiteralPath $lockFile) { Fail-WithResult "BLOCKED" 2 "task lock contention." }
    else { Set-Content -LiteralPath $lockFile -Value $PID -Encoding ascii -NoNewline }
}

# Worktree creation or reuse
$worktreeBranch = "orchestration/$taskId"
$worktreeExists = $false
if (Test-Path -LiteralPath $worktreeAbs) {
    if (Test-Path -LiteralPath (Join-Path $worktreeAbs ".git")) { $worktreeExists = $true }
    else {
        Remove-Item -Recurse -Force $worktreeAbs -ErrorAction SilentlyContinue
        try { git worktree prune 2>$null | Out-Null } catch {}
    }
}
if (-not $worktreeExists) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $worktreeAbs) -Force | Out-Null
    $branchExists = $false
    try { git show-ref --verify --quiet "refs/heads/$worktreeBranch" 2>$null; if ($LASTEXITCODE -eq 0) { $branchExists = $true } } catch {}
    if ($branchExists) {
        git worktree add $worktreeAbs $worktreeBranch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue; Fail-WithResult "BLOCKED" 2 "worktree creation failed." }
    } else {
        git worktree add -b $worktreeBranch $worktreeAbs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue; Fail-WithResult "BLOCKED" 2 "worktree creation failed." }
    }
    Write-Log "Created isolated worktree: $worktreeRel (branch $worktreeBranch)"
} else {
    Write-Log "Reusing existing worktree: $worktreeRel"
}

$cwdRel = "./$worktreeRel"

if ([string]::IsNullOrWhiteSpace($Worker)) {
    if (-not [string]::IsNullOrWhiteSpace($Events)) {
        Emit-WorkerStarted $taskId $cwdRel
        Emit-WorkerCompleted $taskId "PASS" 0 0 $cwdRel $null
    }
    $workersJson = '{"worker_id":' + (ConvertTo-Json $taskId -Compress) + ',"status":"PASS","exit_code":0,"duration_ms":0,"reason_code":null}'
    $summaryJson = '{"workers_defined":1,"workers_run":1,"passed":1,"failed":0,"blocked":0}'
    Write-Log "No worker command supplied; worktree ready."
    if ($Push) {
        Write-Log "Pushing branch $worktreeBranch..."
        git -C $worktreeAbs push origin $worktreeBranch 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            $workersJson = '{"worker_id":' + (ConvertTo-Json $taskId -Compress) + ',"status":"FAIL","exit_code":1,"duration_ms":0,"reason_code":"WORKER_FAILED"}'
            $summaryJson = '{"workers_defined":1,"workers_run":1,"passed":0,"failed":1,"blocked":0}'
            Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
            if ($Cleanup) { try { git worktree remove --force $worktreeAbs 2>$null | Out-Null } catch {}; try { Remove-Item -Recurse -Force $worktreeAbs -ErrorAction SilentlyContinue } catch {} }
            $disp = Get-DisplayPath $TaskFile
            Complete-Orchestration "FAIL" 1 $workersJson $summaryJson $disp $cwdRel
        }
        Write-Log "Pushed $worktreeBranch"
    }
    if ($Cleanup) {
        try { git worktree remove --force $worktreeAbs 2>$null | Out-Null } catch {}
        try { Remove-Item -Recurse -Force $worktreeAbs -ErrorAction SilentlyContinue } catch {}
        Write-Log "Cleaned up worktree $worktreeRel"
    }
    Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
    $disp = Get-DisplayPath $TaskFile
    Complete-Orchestration "PASS" 0 $workersJson $summaryJson $disp $cwdRel
}

# Run worker
if (-not [string]::IsNullOrWhiteSpace($Events)) { Emit-WorkerStarted $taskId $cwdRel }

$startMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$workerExit = 0
$checkOk = $false
try {
    Push-Location $worktreeAbs
    # Use bash if available, else pwsh for command; worker is opaque string executed via bash -c or powershell -Command
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        bash -c $Worker 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { $checkOk = $true } ; $workerExit = $LASTEXITCODE
    } else {
        # Fallback: execute via PowerShell
        Invoke-Expression $Worker 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0 -or $?) { $checkOk = $true; $workerExit = 0 } else { $workerExit = 1 }
    }
} catch {
    $workerExit = 1
} finally { Pop-Location }

if ($checkOk) { $workerExit = 0 } elseif ($workerExit -eq 0) { $workerExit = 1 }

$endMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$durationMs = $endMs - $startMs
if ($durationMs -lt 0) { $durationMs = 0 }

$status = "PASS"; $reason = $null; $exitStr = 0; $result = "PASS"; $exitCode = 0
if (-not $checkOk) {
    if ($workerExit -eq 127 -or $workerExit -eq 126) {
        $status = "BLOCKED"; $reason = "TOOLING_UNAVAILABLE"; $exitStr = $null; $result = "BLOCKED"; $exitCode = 2
    } else {
        $status = "FAIL"; $reason = "WORKER_FAILED"; $exitStr = $workerExit; $result = "FAIL"; $exitCode = 1
    }
}

if (-not [string]::IsNullOrWhiteSpace($Events)) {
    if ($status -eq "PASS") { Emit-WorkerCompleted $taskId $status 0 $durationMs $cwdRel $null }
    elseif ($status -eq "BLOCKED") { Emit-WorkerCompleted $taskId $status $null $durationMs $cwdRel $reason }
    else { Emit-WorkerCompleted $taskId $status $workerExit $durationMs $cwdRel $reason }
}

if ($status -eq "PASS") {
    $workersJson = '{"worker_id":' + (ConvertTo-Json $taskId -Compress) + ',"status":"PASS","exit_code":0,"duration_ms":' + $durationMs + ',"reason_code":null}'
    $summaryJson = '{"workers_defined":1,"workers_run":1,"passed":1,"failed":0,"blocked":0}'
} elseif ($status -eq "FAIL") {
    $workersJson = '{"worker_id":' + (ConvertTo-Json $taskId -Compress) + ',"status":"FAIL","exit_code":' + $workerExit + ',"duration_ms":' + $durationMs + ',"reason_code":"WORKER_FAILED"}'
    $summaryJson = '{"workers_defined":1,"workers_run":1,"passed":0,"failed":1,"blocked":0}'
} else {
    $workersJson = '{"worker_id":' + (ConvertTo-Json $taskId -Compress) + ',"status":"BLOCKED","exit_code":null,"duration_ms":' + $durationMs + ',"reason_code":' + (ConvertTo-Json $reason -Compress) + '}'
    $summaryJson = '{"workers_defined":1,"workers_run":1,"passed":0,"failed":0,"blocked":1}'
}

if ($Push -and $result -eq "PASS") {
    Write-Log "Pushing branch $worktreeBranch..."
    git -C $worktreeAbs push origin $worktreeBranch 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        $workersJson = '{"worker_id":' + (ConvertTo-Json $taskId -Compress) + ',"status":"FAIL","exit_code":1,"duration_ms":' + $durationMs + ',"reason_code":"WORKER_FAILED"}'
        $summaryJson = '{"workers_defined":1,"workers_run":1,"passed":0,"failed":1,"blocked":0}'
        $result = "FAIL"; $exitCode = 1
        Write-Host "Push failed for $worktreeBranch" -ForegroundColor Red
    } else { Write-Log "Pushed $worktreeBranch" }
}

if ($Cleanup) {
    try { git worktree remove --force $worktreeAbs 2>$null | Out-Null } catch {}
    try { Remove-Item -Recurse -Force $worktreeAbs -ErrorAction SilentlyContinue } catch {}
    Write-Log "Cleaned up worktree $worktreeRel"
}

Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue

$disp = Get-DisplayPath $TaskFile
if ($Format -ieq "Json") {
    Complete-Orchestration $result $exitCode $workersJson $summaryJson $disp $cwdRel
} else {
    if ($result -eq "PASS") { Write-Log "Orchestration PASS: worker succeeded in $worktreeRel" }
    elseif ($result -eq "FAIL") { Write-Log "Orchestration FAIL: worker failed in $worktreeRel" }
    else { Write-Log "Orchestration BLOCKED: worker blocked in $worktreeRel" }
    Complete-Orchestration $result $exitCode $workersJson $summaryJson $disp $cwdRel
}
