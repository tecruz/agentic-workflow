#Requires -Version 7.0
<#
.SYNOPSIS
    Structural validator for agentic task files.

.DESCRIPTION
    Validates only structural facts about a task file's risk profile, evidence
    contract, and completion state. It does not judge whether the prose is
    intellectually sufficient; that belongs to human or behavioral evaluation.

    Checks:
      - a recognized risk profile is declared (prototype | standard | high-assurance)
      - required sections exist for the declared profile
      - high-assurance tasks include risk analysis and a recovery plan
      - acceptance criteria carry identifiers (AC-N)
      - required evidence entries are present
      - a task marked complete has no Pending required evidence
      - required approvals are recorded before completion
      - a prototype task's handoff states that production readiness was not established

.EXAMPLE
    ./.agentic/scripts/validate-task.ps1 path/to/TASK-001.md

    Exit codes:
      0  VALID
      1  INVALID
      2  BLOCKED - referenced evidence or approval is missing
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TaskFile
)

$ErrorActionPreference = 'Stop'

function Write-Invalid {
    param([string]$Message)
    [Console]::Error.WriteLine("INVALID: $Message")
    exit 1
}

function Write-Blocked {
    param([string]$Message)
    [Console]::Error.WriteLine("BLOCKED: $Message")
    exit 2
}

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    [Console]::Error.WriteLine("Error: task file not found: $TaskFile")
    exit 1
}

$lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $TaskFile).Path)

function Normalize-Heading {
    param([string]$Text)
    $t = $Text.ToLowerInvariant() -replace '\s+', ' '
    return $t.Trim()
}

# The file's `## ` and `### ` headings, normalized into space-delimited tokens.
$sections = @()
$subsections = @()
foreach ($line in $lines) {
    if ($line -like '## *' -and $line -notlike '### *') {
        $sections += (Normalize-Heading ($line.Substring(3)))
    }
    elseif ($line -like '### *') {
        $subsections += (Normalize-Heading ($line.Substring(4)))
    }
}

function Test-HasSection {
    param([string]$Name)
    return $sections -contains $Name
}

function Test-HasSubsection {
    param([string]$Name)
    return $subsections -contains $Name
}

# Returns the content between a `## <name>` heading and the next `## ` heading.
function Get-SectionContent {
    param([string]$Name)
    $inside = $false
    $content = @()
    foreach ($line in $lines) {
        if ($line -like '## *') {
            if ($inside) { break }
            if ((Normalize-Heading ($line.Substring(3))) -eq $Name) { $inside = $true }
            continue
        }
        if ($inside) { $content += $line }
    }
    return $content
}

# Detect the declared profile from a `Profile: <name>` line.
$profile = ''
foreach ($line in $lines) {
    if ($line -match '^\s*[Pp]rofile\s*:\s*[A-Za-z-]+\s*$') {
        $profile = (($line -replace '^\s*[Pp]rofile\s*:\s*', '').Trim()).ToLowerInvariant()
        break
    }
}

if ($profile -notin @('prototype', 'standard', 'high-assurance')) {
    Write-Invalid 'task must declare a recognized risk profile (prototype, standard, or high-assurance).'
}

# Required `## ` sections and `### ` subsections per profile.
$requiredSections = @()
$requiredSubsections = @()
switch ($profile) {
    'prototype' {
        $requiredSections = @('risk profile', 'profile rationale', 'task goal', 'smoke verification', 'known limitations', 'handoff')
    }
    'standard' {
        $requiredSections = @('risk profile', 'profile rationale', 'acceptance criteria', 'required evidence', 'verification', 'files changed', 'remaining risks')
        $requiredSubsections = @('baseline', 'final')
    }
    'high-assurance' {
        $requiredSections = @(
            'risk profile', 'profile rationale', 'requirements', 'risk analysis', 'requirement-to-evidence',
            'negative-path and boundary tests', 'integration verification', 'recovery plan', 'approval gates',
            'independent review', 'acceptance criteria', 'required evidence', 'verification', 'files changed', 'remaining risks'
        )
        $requiredSubsections = @('baseline', 'final')
    }
}

$missing = @()
foreach ($s in $requiredSections) {
    if (-not (Test-HasSection $s)) { $missing += "section '## $s'" }
}
foreach ($s in $requiredSubsections) {
    if (-not (Test-HasSubsection $s)) { $missing += "subsection '### $s'" }
}
if ($missing.Count -gt 0) {
    Write-Invalid "missing required $($missing -join ', ') for profile '$profile'."
}

if ($profile -ne 'prototype') {
    # Acceptance criteria must carry identifiers (AC-N).
    $hasAc = $false
    foreach ($line in $lines) {
        if ($line -match '(^|\s|-)AC-[0-9]+') { $hasAc = $true; break }
    }
    if (-not $hasAc) {
        Write-Invalid "acceptance criteria must carry identifiers (e.g. 'AC-1')."
    }
    # The required evidence table must map at least one criterion to evidence.
    $evidence = Get-SectionContent 'required evidence'
    $hasEvidenceRow = $false
    foreach ($line in $evidence) {
        if ($line -match '^\|.*AC-[0-9]+.*\|.*\|') { $hasEvidenceRow = $true; break }
    }
    if (-not $hasEvidenceRow) {
        Write-Invalid 'required evidence must contain a table mapping each AC-N to evidence.'
    }
}

if ($profile -eq 'prototype') {
    # A prototype cannot claim production readiness; its handoff must state that
    # production readiness was not established.
    $hasWarning = $false
    foreach ($line in $lines) {
        if ($line -match 'Production readiness\s*:\s*not established') { $hasWarning = $true; break }
    }
    if (-not $hasWarning) {
        Write-Invalid "prototype task handoff must state 'Production readiness: not established'."
    }
}

# Detect whether the task is marked complete (Status: done|complete|completed).
$completed = $false
foreach ($line in $lines) {
    if ($line -match '^[-*]*\s*\*?[Ss]tatus\*?\s*:\s*[^|]*\b(done|complete|completed)\b') {
        $completed = $true
        break
    }
}

if ($completed) {
    $hasPending = $false
    foreach ($line in $lines) {
        if ($line -match '^\|[^|]*\|[^|]*\|\s*Pending\s*\|') { $hasPending = $true; break }
    }
    if ($hasPending) {
        Write-Blocked 'task is marked complete but required evidence remains Pending.'
    }
    # A checked completion must not leave identified approval gates unchecked.
    $gates = Get-SectionContent 'approval gates'
    $unchecked = $false
    foreach ($line in $gates) {
        if ($line -match '\[[[:space:]]\]') { $unchecked = $true; break }
    }
    if ($unchecked) {
        Write-Blocked 'task is marked complete but an approval gate is still unchecked.'
    }
    if ($profile -eq 'high-assurance') {
        $approved = $false
        foreach ($line in $gates) {
            if ($line -match '(approved|granted|\[x\]|signed off)') { $approved = $true; break }
        }
        if (-not $approved) {
            Write-Blocked 'completed high-assurance task lacks recorded approval gates.'
        }
    }
}

Write-Host "VALID: profile=$profile"
exit 0