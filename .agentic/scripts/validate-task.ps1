#Requires -Version 7.0
<#
.SYNOPSIS
    Structural validator for agentic task files.

.DESCRIPTION
    Validates only structural facts about a task file's risk profile, evidence
    contract, status, and completion state. It never judges whether the prose
    is intellectually sufficient; that belongs to human or behavioral
    evaluation.

    Content in fenced code blocks, HTML comments, and blockquote lines is not
    authoritative and is ignored. The scanner also rejects duplicate `##`
    headings and duplicate Profile/Status declarations.

    Checks (all case-insensitive):
      - exactly one recognized risk profile: prototype | standard | high-assurance
      - exactly one recognized status: planned | in-progress | blocked | done
      - exact required `##` sections per profile, with `### Baseline` and
        `### Final` scoped inside `## Verification`
      - acceptance criteria declare unique `AC-N` identifiers, and the
        required evidence table maps every `AC-N` exactly once with nonempty
        evidence and a recognized result value
      - high-assurance tasks map every `R-N` through the requirement-to-
        evidence matrix and carry nonempty risk analysis, negative-path and
        boundary tests, integration verification, recovery plan, and
        independent review
      - prototypes declare that no production deployment or irreversible
        operation occurred and that production readiness was not established
      - approvals use structured records: `- [x] AG-N: Approved by <x> on <date>`
      - a task marked `done` has no unresolved evidence and no unchecked gates

    Result values: passed | satisfied | n/a are resolved; pending | partial |
    blocked | missing | not-run are unresolved and block a completed task.
    `n/a` requires an `n/a` rationale in the evidence description.

    Exit codes:
      0  VALID
      1  INVALID — structural contract violation
      2  BLOCKED — completion gate not satisfied (evidence or approval missing)

.EXAMPLE
    ./.agentic/scripts/validate-task.ps1 path/to/TASK-001.md

.EXAMPLE
    ./.agentic/scripts/validate-task.ps1 -Handoff path/to/TASK-001.md
#>
[CmdletBinding()]
param(
    [switch]$Handoff,
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

$fileLines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $TaskFile).Path)


function Normalize-Heading {
    param([string]$Text)
    return (($Text.ToLowerInvariant() -replace '\s+', ' ').Trim())
}

# Scan: drop non-authoritative Markdown (fenced code blocks, HTML comments, and
# blockquote lines) and collect headings, declarations, and content.
$contentLines = [System.Collections.Generic.List[string]]::new()
$SECTIONS = [System.Collections.Generic.List[string]]::new()
$SECTION_START = [System.Collections.Generic.List[int]]::new()
$SUBSECTIONS = [System.Collections.Generic.List[string]]::new()
$SUB_SECTION = [System.Collections.Generic.List[string]]::new()
$ProfileDecl = 0
$ProfileName = ''
$StatusDecl = 0
$StatusName = ''
$inFence = $false
$inComment = $false
$cur = ''


$i = 0
foreach ($line in $fileLines) {
    if ($inComment) {
        if ($line -match '-->') { $inComment = $false }
        continue
    }
    if ($line -match '<!--') {
        if ($line -match '-->') { continue }
        $inComment = $true
        continue
    }
    if ($inFence) {
        if ($line -match '```' -or $line -match '~~~') { $inFence = $false }
        continue
    }
    if ($line -match '```' -or $line -match '~~~') { $inFence = $true; continue }
    if ($line -match '^\s*>') { continue }
    if ($line -match '^###\s') {
        $h = Normalize-Heading $line.Substring(4)
        $SUBSECTIONS.Add($h)
        $SUB_SECTION.Add($cur)
        $contentLines.Add($line)
        continue
    }
    if ($line -match '^##\s') {
        $h = Normalize-Heading $line.Substring(3)
        $SECTIONS.Add($h)
        $SECTION_START.Add($contentLines.Count)
        $cur = $h
        $contentLines.Add($line)
        continue
    }
    if ($line -match '^\s*Profile\s*:') {
        $ProfileDecl++
        if (-not $ProfileName) {
            $ProfileName = (($line -replace '^\s*[Pp]rofile\s*:\s*', '').Trim()).ToLowerInvariant()
        }
    }
    if ($line -match '^\s*[-*]*\s*\*?[Ss]tatus\s*:') {
        $StatusDecl++
        if (-not $StatusName) {
            $StatusName = (($line -replace '^\s*[-*]*\s*\*?[Ss]tatus\s*:\s*', '').Trim()).ToLowerInvariant()
        }
    }
    $contentLines.Add($line)
}



# ---------------------------------------------------------------------------
# Profile and status declarations.
# ---------------------------------------------------------------------------
if ($ProfileDecl -ne 1) {
    Write-Invalid "task must declare exactly one 'Profile:' (found $ProfileDecl)."
}
if ($ProfileName -notin @('prototype', 'standard', 'high-assurance')) {
    Write-Invalid 'task must declare a recognized risk profile (prototype, standard, or high-assurance).'
}
if ($StatusDecl -ne 1) {
    Write-Invalid "task must declare exactly one 'Status:' (found $StatusDecl)."
}
if ($StatusName -notin @('planned', 'in-progress', 'blocked', 'done')) {
    Write-Invalid "task status must be one of: planned, in-progress, blocked, done (found '$StatusName')."
}
$Completed = ($StatusName -eq 'done')
if ($Handoff -and -not $Completed) {
    Write-Blocked "handoff requires 'Status: done' (found '$StatusName')."
}

# ---------------------------------------------------------------------------
# Headings: no duplicates; exact required sections per profile; Baseline and
# Final must live inside Verification.
# ---------------------------------------------------------------------------
$seenSections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($s in $SECTIONS) {
    if (-not $seenSections.Add($s)) { Write-Invalid "duplicate section heading '## $s'." }
}
$seenSubsections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($s in $SUBSECTIONS) {
    if (-not $seenSubsections.Add($s)) { Write-Invalid "duplicate subsection heading '### $s'." }
}

function Get-SectionContent {
    param([string]$Name)
    $start = -1
    for ($i = 0; $i -lt $SECTIONS.Count; $i++) {
        if ($SECTIONS[$i] -eq $Name) { $start = $i; break }
    }
    if ($start -lt 0) { return @() }
    $begin = $SECTION_START[$start] + 1
    $end = if ($start + 1 -lt $SECTIONS.Count) { $SECTION_START[$start + 1] - 1 } else { $contentLines.Count - 1 }
    $result = [System.Collections.Generic.List[string]]::new()
    for ($j = $begin; $j -le $end; $j++) { $result.Add($contentLines[$j]) }
    return , $result.ToArray()
}

function Test-SectionContent {
    param([string]$Name)
    foreach ($l in (Get-SectionContent $Name)) {
        if ($l -match '\S') { return $true }
    }
    return $false
}

function Get-Ids {
    param([string[]]$ContentLines, [string]$Pattern)
    $script:DupIds = $false
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $ContentLines) {
        foreach ($m in [regex]::Matches($line, $Pattern, 'IgnoreCase')) {
            $id = $m.Value.ToLowerInvariant()
            if (-not $seen.Add($id)) { $script:DupIds = $true }
            if (-not $out.Contains($id)) { $out.Add($id) }
        }
    }
    return , $out.ToArray()
}

$AllowedResults = @('passed', 'satisfied', 'n/a', 'pending', 'partial', 'blocked', 'missing', 'not-run')
$UnresolvedResults = @('pending', 'partial', 'blocked', 'missing', 'not-run')

# Test-Table <section> <id-pattern> <label> — validates a canonical
# `| id | evidence | result |` table. Returns the lowercased row ids and sets
# the globals TableDup and HasUnresolved. Fails on structural problems.
function Test-Table {
    param([string]$Section, [string]$IdPattern, [string]$Label)
    $script:TableDup = $false
    $script:HasUnresolved = $false
    $ids = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in (Get-SectionContent $Section)) {
        if ($row -notmatch '^\s*\|.*\|.*\|.*\|\s*$') { continue }
        $parts = $row -split '\|'
        if ($parts.Count -ne 5) { continue }
        $id = $parts[1].Trim()
        $ev = $parts[2].Trim()
        $res = $parts[3].Trim()
        if ($id -notmatch "^$IdPattern$") { continue }
        $idLower = $id.ToLowerInvariant()
        if (-not $ev) { Write-Invalid "$Label row '$id' has an empty evidence description." }
        if (-not $res) { Write-Invalid "$Label row '$id' has an empty result." }
        $lres = $res.ToLowerInvariant()
        if ($AllowedResults -notcontains $lres) {
            Write-Invalid "$Label row '$id' has unrecognized result '$res' (allowed: passed, satisfied, n/a, pending, partial, blocked, missing, not-run)."
        }
        if ($lres -eq 'n/a' -and $ev -notmatch 'n/a') {
            Write-Invalid "$Label row '$id' uses 'n/a' without an 'n/a' rationale in the evidence description."
        }
        if (-not $seen.Add($idLower)) { $script:TableDup = $true }
        if (-not $ids.Contains($idLower)) { $ids.Add($idLower) }
        if ($UnresolvedResults -contains $lres) { $script:HasUnresolved = $true }
    }
    return , $ids.ToArray()
}

function Get-SortedUnique {
    param([string[]]$Ids)
    return , @($Ids | Sort-Object -Unique)
}

$requiredSections = @()
$requiredSubsections = @()
switch ($ProfileName) {
    'prototype' {
        $requiredSections = @('risk profile', 'profile rationale', 'task goal', 'smoke verification', 'known limitations', 'handoff')
    }
    'standard' {
        $requiredSections = @('risk profile', 'profile rationale', 'acceptance criteria', 'required evidence', 'approval gates', 'verification', 'files changed', 'remaining risks')
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

foreach ($s in $requiredSections) {
    if ($SECTIONS -notcontains $s) { Write-Invalid "missing required section '## $s' for profile '$ProfileName'." }
}
foreach ($s in $requiredSubsections) {
    $found = $false
    for ($i = 0; $i -lt $SUBSECTIONS.Count; $i++) {
        if ($SUBSECTIONS[$i] -eq $s -and $SUB_SECTION[$i] -eq 'verification') { $found = $true; break }
    }
    if (-not $found) { Write-Invalid "missing '### $s' subsection under '## Verification' for profile '$ProfileName'." }
}

# ---------------------------------------------------------------------------
# Prototype contract.
# ---------------------------------------------------------------------------
if ($ProfileName -eq 'prototype') {
    $handoffLines = Get-SectionContent 'handoff'
    $handoffText = ($handoffLines -join "`n")
    if ($handoffText -notmatch 'production\s+readiness\s*:\s*not\s+established') {
        Write-Invalid "prototype handoff must state 'Production readiness: not established'."
    }
    if ($handoffText -notmatch 'no\s+production\s+deployment\s+or\s+irreversible\s+operation\s*:\s*confirmed') {
        Write-Invalid "prototype handoff must declare 'No production deployment or irreversible operation: confirmed'."
    }
}

# ---------------------------------------------------------------------------
# Standard and high-assurance evidence contracts.
# ---------------------------------------------------------------------------
if ($ProfileName -ne 'prototype') {
    $acIds = Get-Ids (Get-SectionContent 'acceptance criteria') 'AC-\d+'
    if ($acIds.Count -eq 0) { Write-Invalid "acceptance criteria must declare at least one 'AC-N' identifier." }
    if ($script:DupIds) { Write-Invalid "acceptance criteria declare duplicate 'AC-N' identifiers." }

    $evIds = Test-Table 'required evidence' 'AC-\d+' 'required evidence'
    if ($evIds.Count -eq 0) { Write-Invalid "required evidence must map at least one 'AC-N' to evidence." }
    if ($script:TableDup) { Write-Invalid "required evidence maps a criterion more than once." }
    if (((Get-SortedUnique $acIds) -join ' ') -ne ((Get-SortedUnique $evIds) -join ' ')) {
        Write-Invalid "acceptance criteria and required evidence must list exactly the same 'AC-N' identifiers."
    }
    if ($Completed -and $script:HasUnresolved) {
        Write-Blocked 'task is marked complete but required evidence remains unresolved (pending, partial, blocked, missing, or not-run).'
    }

    if ($ProfileName -eq 'high-assurance') {
        $rIds = Get-Ids (Get-SectionContent 'requirements') 'R-\d+'
        if ($rIds.Count -eq 0) { Write-Invalid "high-assurance requirements must declare at least one 'R-N' identifier." }
        if ($script:DupIds) { Write-Invalid "high-assurance requirements declare duplicate 'R-N' identifiers." }

        $mIds = Test-Table 'requirement-to-evidence' 'R-\d+' 'requirement-to-evidence'
        if ($mIds.Count -eq 0) { Write-Invalid "the requirement-to-evidence matrix must map at least one 'R-N' to evidence." }
        if ($script:TableDup) { Write-Invalid "the requirement-to-evidence matrix maps a requirement more than once." }
        if (((Get-SortedUnique $rIds) -join ' ') -ne ((Get-SortedUnique $mIds) -join ' ')) {
            Write-Invalid "requirements and the requirement-to-evidence matrix must list exactly the same 'R-N' identifiers."
        }
        if ($Completed -and $script:HasUnresolved) {
            Write-Blocked 'task is marked complete but the requirement-to-evidence matrix has unresolved rows.'
        }

        foreach ($s in @('risk analysis', 'negative-path and boundary tests', 'integration verification', 'recovery plan', 'independent review')) {
            if (-not (Test-SectionContent $s)) { Write-Invalid "high-assurance section '## $s' must have content." }
        }
    }
}

# ---------------------------------------------------------------------------
# Approval gates: structured records only; no prose-based approval inference.
# ---------------------------------------------------------------------------
if ($ProfileName -ne 'prototype') {
    $hasNone = $false
    $gateCount = 0
    $checked = 0
    $unchecked = 0
    $gateSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($gl in (Get-SectionContent 'approval gates')) {
        if ($gl -match 'none\s+identified') { $hasNone = $true }
        if ($gl -match '^\s*-\s*\[[ xX]\]\s*AG-\d+\s*:') {
            $gateCount++
            $m = [regex]::Match($gl, '^\s*-\s*\[([ xX])\]\s*(AG-\d+)\s*:\s*(.*?)\s*$')
            $gid = $m.Groups[2].Value.ToLowerInvariant()
            $gbox = $m.Groups[1].Value
            $gdet = $m.Groups[3].Value.Trim()
            if (-not $gateSeen.Add($gid)) { Write-Invalid "approval gate '$gid' is declared more than once." }
            if ($gbox -match '[xX]') { $checked++ } else { $unchecked++ }
            if ($gdet -notmatch '^approved\s+by\s+.+\s+on\s+[\w@./-]+\s*$') {
                Write-Invalid "approval gate '$gid' must be in the form '- [x] AG-N: Approved by <approver> on <date>'."
            }
        }
    }

    if ($hasNone -and $gateCount -gt 0) {
        Write-Invalid "approval gates cannot both declare 'None identified' and structured gates."
    }
    if ($ProfileName -eq 'high-assurance') {
        if ($hasNone) { Write-Invalid "high-assurance tasks require explicit approval gates ('None identified' is not permitted)." }
        if ($gateCount -eq 0) { Write-Invalid "high-assurance tasks must declare at least one approval gate 'AG-N'." }
    }
    elseif (-not $hasNone -and $gateCount -eq 0) {
        Write-Invalid "approval gates must declare structured 'AG-N' records or 'None identified'."
    }
    if ($Completed -and $unchecked -gt 0) {
        Write-Blocked 'task is marked complete but an approval gate remains unchecked.'
    }
}

Write-Host "VALID: profile=$ProfileName"
exit 0
