#Requires -Version 7.0
<#
.SYNOPSIS
    Agentic Workflow Health Report — scans .agentic/ and prints a plain-text summary.
.DESCRIPTION
    Reports task state, context module usage, skill invocation usage, profile
    distribution, VERSION/protocol_version consistency, and recent task changes.
    Exit 0 always (informational only).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Paths ──────────────────────────────────────────────────────────────────────

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$AgenticDir = Split-Path -Parent $ScriptDir
$TasksDir = Join-Path $AgenticDir 'tasks'

# ── Helpers ────────────────────────────────────────────────────────────────────

function Trim([string]$v) { $v.Trim() }

# Collect non-README task files
$taskFiles = Get-ChildItem -Path $TasksDir -Filter '*.md' -File |
    Where-Object { $_.Name -ne 'README.md' }
$total = $taskFiles.Count

# ── 1. Task status breakdown ──────────────────────────────────────────────────

$statusCounts = @{}
foreach ($tf in $taskFiles) {
    $line = Select-String -Path $tf.FullName -Pattern '^Status:\s+(.+)' | Select-Object -First 1
    $s = if ($line) { Trim $line.Matches[0].Groups[1].Value } else { 'unknown' }
    if (-not $statusCounts.ContainsKey($s)) { $statusCounts[$s] = 0 }
    $statusCounts[$s]++
}

# ── 2. Context module usage ───────────────────────────────────────────────────

$moduleTasks = @{}   # module-id → [list of task basenames]
$moduleTotal = 0

foreach ($tf in $taskFiles) {
    $base = $tf.Name
    $inSection = $false
    foreach ($rawLine in (Get-Content $tf.FullName)) {
        $line = [string]$rawLine
        if ($line -match '^## Context modules') {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match '^## ') { break }
        if ($inSection -and $line -match '^- (.+) v\d+ loaded') {
            $modId = $Matches[1]
            if (-not $moduleTasks.ContainsKey($modId)) { $moduleTasks[$modId] = [System.Collections.Generic.List[string]]::new() }
            $moduleTasks[$modId].Add($base)
            $moduleTotal++
        }
    }
}

# ── 3. Skill invocation usage ─────────────────────────────────────────────────

$skillTasks = @{}    # skill-id → [list of task basenames]
$skillTotal = 0

foreach ($tf in $taskFiles) {
    $base = $tf.Name
    $inSection = $false
    foreach ($rawLine in (Get-Content $tf.FullName)) {
        $line = [string]$rawLine
        if ($line -match '^## Skills') {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match '^## ') { break }
        if ($inSection -and $line -match '^- (.+) v\d+ invoked') {
            $skId = $Matches[1]
            if (-not $skillTasks.ContainsKey($skId)) { $skillTasks[$skId] = [System.Collections.Generic.List[string]]::new() }
            $skillTasks[$skId].Add($base)
            $skillTotal++
        }
    }
}

# ── 4. Profile distribution ──────────────────────────────────────────────────

$profileCounts = @{}
foreach ($tf in $taskFiles) {
    $line = Select-String -Path $tf.FullName -Pattern '^Profile:\s+(.+)' | Select-Object -First 1
    $p = if ($line) { Trim $line.Matches[0].Groups[1].Value } else { 'unknown' }
    if (-not $profileCounts.ContainsKey($p)) { $profileCounts[$p] = 0 }
    $profileCounts[$p]++
}

# ── 5. VERSION and protocol_version consistency ───────────────────────────────

$versionFile = Join-Path $AgenticDir 'VERSION'
if (Test-Path $versionFile) {
    $fileVersion = Trim (Get-Content $versionFile -Raw)
} else {
    $fileVersion = '(missing)'
}

$protoFiles = @(
    'scripts/verify.sh',
    'scripts/verify.ps1',
    'scripts/validate-task.sh',
    'scripts/validate-task.ps1',
    'scripts/validate-context.sh',
    'scripts/validate-context.ps1',
    'scripts/validate-skills.sh',
    'scripts/validate-skills.ps1',
    'orchestration/coordinator.sh',
    'orchestration/coordinator.ps1'
)

$protoVersions = @{}  # short-name → version
foreach ($rel in $protoFiles) {
    $full = Join-Path $AgenticDir $rel
    if (-not (Test-Path $full)) { continue }
    $content = Get-Content $full -Raw
    $pv = $null
    # JSON form: "protocol_version": "x.y.z"
    if ($content -match '"protocol_version":\s*"([0-9][^"]*)"') {
        $pv = $Matches[1]
    }
    # PS form: protocol_version = "x.y.z"
    if (-not $pv -and $content -match 'protocol_version\s*=\s*"([0-9][^"]*)"') {
        $pv = $Matches[1]
    }
    # Coordinator form: $ProtocolVersion = "x.y.z"
    if (-not $pv -and $content -match '\$ProtocolVersion\s*=\s*"([0-9][^"]*)"') {
        $pv = $Matches[1]
    }
    if ($pv) { $protoVersions[(Split-Path $rel -Leaf)] = $pv }
}

# Also check evals/run-evals.sh (dev-repo only; absent in adopter installs).
$evalsSh = Join-Path $AgenticDir '..' 'evals' 'run-evals.sh'
if (Test-Path $evalsSh) {
    $content = Get-Content $evalsSh -Raw
    if ($content -match '"protocol_version":\s*"([^"]+)"') {
        $protoVersions['run-evals.sh'] = $Matches[1]
    }
}

# ── 6. Recent changes (last 5 modified task files) ────────────────────────────

$recentLines = @()
$gitRoot = $null
try {
    $gitRoot = (git -C $AgenticDir rev-parse --show-toplevel 2>$null)
} catch { }
if ($gitRoot) {
    $logOutput = git -C $gitRoot log -5 --format='%ai|%s' -- "$TasksDir/*.md" 2>$null
    if ($logOutput) {
        $recentLines = $logOutput -split "`n" | Where-Object { $_.Trim() -ne '' }
    }
}

# ── Output ────────────────────────────────────────────────────────────────────

$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════════════════'
Write-Host '  Agentic Workflow Health Report'
Write-Host "  $now"
Write-Host '═══════════════════════════════════════════════════════════════════════'
Write-Host ''

Write-Host '── Tasks ─────────────────────────────────────────────────────────────'
Write-Host "  Total: $total"
foreach ($kv in $statusCounts.GetEnumerator() | Sort-Object Name) {
    Write-Host "    $($kv.Key): $($kv.Value)"
}
Write-Host ''

Write-Host '── Context Module Usage ──────────────────────────────────────────────'
Write-Host "  Total selections: $moduleTotal"
if ($moduleTasks.Count -gt 0) {
    foreach ($kv in $moduleTasks.GetEnumerator() | Sort-Object Name) {
        Write-Host "    $($kv.Key):"
        foreach ($t in $kv.Value) {
            Write-Host "      - $t"
        }
    }
} else {
    Write-Host '    (none)'
}
Write-Host ''

Write-Host '── Skill Invocation Usage ────────────────────────────────────────────'
Write-Host "  Total invocations: $skillTotal"
if ($skillTasks.Count -gt 0) {
    foreach ($kv in $skillTasks.GetEnumerator() | Sort-Object Name) {
        Write-Host "    $($kv.Key):"
        foreach ($t in $kv.Value) {
            Write-Host "      - $t"
        }
    }
} else {
    Write-Host '    (none)'
}
Write-Host ''

Write-Host '── Profile Distribution ─────────────────────────────────────────────'
foreach ($kv in $profileCounts.GetEnumerator() | Sort-Object Name) {
    Write-Host "    $($kv.Key): $($kv.Value)"
}
Write-Host ''

Write-Host '── VERSION Consistency ───────────────────────────────────────────────'
Write-Host "  .agentic/VERSION: $fileVersion"

$allMatch = $true
if ($protoVersions.Count -gt 0) {
    foreach ($kv in $protoVersions.GetEnumerator() | Sort-Object Name) {
        $pv = $kv.Value
        if ($pv -eq $fileVersion) {
            Write-Host "    $($kv.Key): $pv  ✓"
        } else {
            Write-Host "    $($kv.Key): $pv  ✗ (expected $fileVersion)"
            $allMatch = $false
        }
    }
} else {
    Write-Host '    (no protocol_version found in scripts)'
}

if ($allMatch) {
    Write-Host '  Status: CONSISTENT'
} else {
    Write-Host '  Status: MISMATCH — protocol_version does not match VERSION'
}
Write-Host ''

Write-Host '── Recent Task Changes (last 5 git-modified) ────────────────────────'
if ($recentLines.Count -gt 0) {
    foreach ($entry in $recentLines) {
        $parts = $entry -split '\|', 2
        $date = $parts[0].Trim()
        $msg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
        Write-Host "    $date  $msg"
    }
} else {
    Write-Host '    (no git history or not in a repo)'
}
Write-Host ''

Write-Host '═══════════════════════════════════════════════════════════════════════'
Write-Host '  Report complete. All checks informational — exit 0.'
Write-Host '═══════════════════════════════════════════════════════════════════════'
Write-Host ''

exit 0
