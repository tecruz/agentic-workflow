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
        required evidence table maps every `AC-N` exactly once with meaningful
        evidence (at least one letter or number after trimming Markdown syntax
        and recognized placeholders) and a recognized result value
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
    [string]$TaskFile,
    [ValidateSet('Text', 'Json')]
    [string] $Format = 'Text'
)

$ErrorActionPreference = 'Stop'

function Output-TaskJson {
    param([string]$Result, [int]$ExitCode, [string]$Message, [string]$Code = 'CRITERION_INVALID', [string]$Section = $null, [string]$Identifier = $null)
    $diagList = @()
    if ($Result -ne 'VALID') {
        $diagList += [ordered]@{
            code       = $Code
            section    = $Section
            identifier = $Identifier
            message    = $Message
        }
    }
    # Profile/task_status: null when not present or recognized — never invent
    # defaults that would mislead automation (schema marks both nullable).
    $profileOut = if ($script:ProfileName -in @('prototype', 'standard', 'high-assurance')) { $script:ProfileName } else { $null }
    $statusOut = if ($script:StatusName -in @('planned', 'in-progress', 'blocked', 'done')) { $script:StatusName } else { $null }
    $resultObject = [ordered]@{
        schema_version   = 1
        protocol_version = "1.4.0"
        kind             = "task_validation_result"
        mode             = if ($Handoff) { "handoff" } else { "standard" }
        result           = $Result
        exit_code        = $ExitCode
        task_file        = Get-TaskFileDisplay
        profile          = $profileOut
        task_status      = $statusOut
        diagnostics      = $diagList
    }
    [Console]::Out.WriteLine(($resultObject | ConvertTo-Json -Depth 10 -Compress))
}

function Get-TaskFileDisplay {
    # Redacts the task file path for observable JSON output: passed through
    # when already relative, made project-relative under the working
    # directory, degraded to its basename otherwise, so an absolute user-home
    # path can never leak into machine-readable results.
    $rawNorm = ($TaskFile -replace '\\', '/')
    if ($rawNorm -match '^[A-Za-z]:') {
        # A drive-letter path can only be a real absolute path on Windows; on
        # any other host it is a foreign path form that must degrade to its
        # basename instead of being resolved against the working directory
        # (where it would masquerade as a project-relative label).
        if (-not $IsWindows) { return [System.IO.Path]::GetFileName($rawNorm) }
    }
    elseif ($rawNorm -notmatch '^/') {
        return ($rawNorm -replace '^\./', '')
    }
    $root = [System.IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\', '/')
    try {
        $full = [System.IO.Path]::GetFullPath($TaskFile).TrimEnd('\', '/')
    }
    catch {
        return [System.IO.Path]::GetFileName($TaskFile)
    }
    if ($full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { return '.' }
    if ($full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        return './' + $full.Substring($root.Length + 1).Replace('\', '/')
    }
    return [System.IO.Path]::GetFileName($full)
}

function Write-Invalid {
    # Explicit diagnostic code at every failure site — never inferred from
    # message keywords, because keyword matching diverged silently between
    # implementations.
    param([string]$Code, [string]$Section, [string]$Identifier, [string]$Message)
    if ($Format -eq 'Json') {
        Output-TaskJson 'INVALID' 1 $Message $Code $Section $Identifier
        exit 1
    }
    else {
        [Console]::Error.WriteLine("INVALID: $Message")
        exit 1
    }
}

function Write-Blocked {
    # Same explicit-arguments contract as Write-Invalid.
    param([string]$Code, [string]$Section, [string]$Identifier, [string]$Message)
    if ($Format -eq 'Json') {
        Output-TaskJson 'BLOCKED' 2 $Message $Code $Section $Identifier
        exit 2
    }
    else {
        [Console]::Error.WriteLine("BLOCKED: $Message")
        exit 2
    }
}

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    if ($Format -eq 'Json') {
        # The diagnostic message carries only the redacted display value: the
        # raw input path must never leak into serialized JSON through a
        # message when its structured field is redacted.
        Output-TaskJson 'INVALID' 1 "Task file was not found: $(Get-TaskFileDisplay)" 'TASK_FILE_NOT_FOUND'
    }
    else {
        [Console]::Error.WriteLine("Error: task file not found: $TaskFile")
    }
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
$SUB_SECTION_START = [System.Collections.Generic.List[int]]::new()
$ProfileDecl = 0
$ProfileName = ''
$ProfileInRisk = $false
$StatusDecl = 0
$StatusName = ''
$StatusInStatus = $false
$UpdatedCount = 0
$Updated = ''
$UpdatedInStatus = $false
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
        $SUB_SECTION_START.Add($contentLines.Count)
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
        if ($cur -eq 'risk profile') { $ProfileInRisk = $true }
        if (-not $ProfileName) {
            $ProfileName = (($line -replace '^\s*profile\s*:\s*', '').Trim()).ToLowerInvariant()
        }
    }
    if ($line -match '^\s*[-*]*\s*\*?Status\s*:') {
        $StatusDecl++
        if ($cur -eq 'status') { $StatusInStatus = $true }
        if (-not $StatusName) {
            $StatusName = (($line -replace '^\s*[-*]*\s*\*?status\s*:\s*', '').Trim()).ToLowerInvariant()
        }
    }
    if ($line -match '^\s*Updated\s*:') {
        $UpdatedCount++
        if ($cur -eq 'status') { $UpdatedInStatus = $true }
        if (-not $Updated) {
            $Updated = (($line -replace '^\s*updated\s*:\s*', '').Trim()).ToLowerInvariant()
        }
    }
    $contentLines.Add($line)
}

function Test-IsoDate {
    param([string]$Value)
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}$') { return $false }
    $parts = $Value -split '-'
    $y = [int]$parts[0]; $m = [int]$parts[1]; $d = [int]$parts[2]
    if ($y -lt 1 -or $m -lt 1 -or $m -gt 12 -or $d -lt 1) { return $false }
    $leap = ([DateTime]::IsLeapYear($y))
    $max = switch ($m) {
        1 { 31 } 3 { 31 } 5 { 31 } 7 { 31 } 8 { 31 } 10 { 31 } 12 { 31 }
        4 { 30 } 6 { 30 } 9 { 30 } 11 { 30 }
        2 { if ($leap) { 29 } else { 28 } }
    }
    return ($d -le $max)
}

# ---------------------------------------------------------------------------
# Profile and status declarations.
# ---------------------------------------------------------------------------
if ($ProfileDecl -ne 1) {
    Write-Invalid "PROFILE_DECLARATION_INVALID" '' '' "task must declare exactly one 'Profile:' (found $ProfileDecl)."
}
if (-not $ProfileInRisk) {
    Write-Invalid "PROFILE_DECLARATION_INVALID" '' '' "Profile: must be declared inside '## Risk profile'."
}
if ($ProfileName -notin @('prototype', 'standard', 'high-assurance')) {
    Write-Invalid "PROFILE_UNKNOWN" '' '' "task must declare a recognized risk profile (prototype, standard, or high-assurance)."
}
if ($StatusDecl -ne 1) {
    Write-Invalid "STATUS_DECLARATION_INVALID" '' '' "task must declare exactly one 'Status:' (found $StatusDecl)."
}
if (-not $StatusInStatus) {
    Write-Invalid "STATUS_DECLARATION_INVALID" '' '' "Status: must be declared inside '## Status'."
}
if ($StatusName -notin @('planned', 'in-progress', 'blocked', 'done')) {
    Write-Invalid "STATUS_INVALID" '' '' "task status must be one of: planned, in-progress, blocked, done (found '$StatusName')."
}
if ($UpdatedCount -ne 1) {
    Write-Invalid "UPDATED_INVALID" '' '' "task must declare exactly one 'Updated:' (found $UpdatedCount)."
}
if (-not $UpdatedInStatus) {
    Write-Invalid "UPDATED_INVALID" '' '' "Updated: must be declared inside '## Status'."
}
if (-not $Updated) {
    Write-Invalid "UPDATED_INVALID" '' '' "Updated: must have a value."
}
if (-not (Test-IsoDate $Updated)) {
    Write-Invalid "UPDATED_INVALID" '' '' "Updated: must be a valid ISO date YYYY-MM-DD (found '$Updated')."
}
$Completed = ($StatusName -eq 'done')
if ($Handoff -and -not $Completed) {
    Write-Blocked "STATUS_NOT_DONE" '' '' "handoff requires 'Status: done' (found '$StatusName')."
}

# ---------------------------------------------------------------------------
# Headings: no duplicates; exact required sections per profile; Baseline and
# Final must live inside Verification.
# ---------------------------------------------------------------------------
$seenSections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($s in $SECTIONS) {
    if (-not $seenSections.Add($s)) { Write-Invalid "SECTION_DUPLICATE" '' '' "duplicate section heading '## $s'." }
}
$seenSubsections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($s in $SUBSECTIONS) {
    if (-not $seenSubsections.Add($s)) { Write-Invalid "SECTION_DUPLICATE" '' '' "duplicate subsection heading '### $s'." }
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

function Get-SubsectionContent {
    param([string]$Name, [string]$Section)
    for ($i = 0; $i -lt $SUBSECTIONS.Count; $i++) {
        if ($SUBSECTIONS[$i] -eq $Name -and $SUB_SECTION[$i] -eq $Section) {
            $begin = $SUB_SECTION_START[$i] + 1
            $result = [System.Collections.Generic.List[string]]::new()
            for ($j = $begin; $j -lt $contentLines.Count; $j++) {
                if ($contentLines[$j] -match '^##\s' -or $contentLines[$j] -match '^###\s') { break }
                $result.Add($contentLines[$j])
            }
            return , $result.ToArray()
        }
    }
    return @()
}

# Test-TableRowContent — returns true when at least one data cell is real
# (non-placeholder) content. Cells that are bracket/angle markers, bare dates,
# TBD / TODO / Pending, or blank do not count, so a table of template
# placeholders is not treated as real evidence.
function Test-TableRowContent {
    param([string]$Line)
    $line = $Line -replace '^\s*\|', '' -replace '\|\s*$', ''
    foreach ($cell in $line -split '\|') {
        $cell = $cell.Trim()
        if ($cell -and ((Get-ContentClass @($cell)) -eq 'content')) { return $true }
    }
    return $false
}

# Test-MeaningfulChar — true when the text contains at least one Unicode
# Letter or Number (any script), or an ASCII letter/digit. Symbol-only values
# ('_', '()', '+++', '^^^'), Unicode punctuation ('—', '…'), emoji, and
# invisible format characters (zero-width space) carry no real content and are
# rejected. This is the authoritative letter-or-number test: a Unicode
# category Letter or Number, never "any non-ASCII character".
function Test-MeaningfulChar {
    param([string]$Value)
    return ($Value -match '[\p{L}\p{N}]')
}

# Test-TextIsPlaceholder — true when a single text value is template placeholder
# content: an exact placeholder token (optionally punctuated, e.g. 'TBD.' or
# 'None identified.'), a placeholder label ('<label>: TBD'), a
# placeholder-prefixed instruction ('TODO: add tests', 'TBD test reference'),
# a whole bracketed or angle-bracket marker, a bare date, or the
# profile-rationale instruction. Real sentences are not placeholders.
function Test-TextIsPlaceholder {
    param([string]$Text)
    $n = (($Text -replace '^\s*[-*+]\s+', '').Trim() -replace '\s*[.!?;:,-]+$', '').ToLowerInvariant()
    if (-not $n) { return $true }
    # Strip common whole-value Markdown formatting wrappers before placeholder
    # classification so that '**TBD**', '`Pending`', '~~TODO~~', 'TBD_',
    # 'TBD()', and similar wrappers are recognized as placeholders rather than
    # real content.
    $prev = ''
    while ($n -ne $prev) {
        $prev = $n
        $n = $n -replace '^\*\*([^*]+)\*\*$', '$1'
        $n = $n -replace '^\*([^*]+)\*$', '$1'
        $n = $n -replace '^__([^_]+)__$', '$1'
        $n = $n -replace '^_([^_]+)_$', '$1'
        $n = $n -replace '^`([^`]+)`$', '$1'
        $n = $n -replace '^~~([^~]+)~~$', '$1'
        # Wrapper symbols may trail a marker or token ('TBD_', 'TBD()',
        # '[label]_'); strip them so the underlying value can be classified.
        $n = ($n -replace '\s*[_()]+$', '') -replace '^[_()]+', ''
    }
    # Stripping trailing punctuation may leave an empty value (e.g. a bare '.');
    # punctuation-only text carries no real content and is a placeholder.
    $n = ($n.Trim() -replace '\s*[.!?;:,-]+$', '').Trim()
    if (-not $n) { return $true }
    # A whole bracketed or angle-bracket marker (optionally with trailing
    # wrapper symbols) is a placeholder; brackets are not unwrapped to prose.
    if ($n -match '^\[[^]]+\][\s_.()*~-]*$') { return $true }
    if ($n -match '^<[^>]+>[\s_.()*~-]*$') { return $true }
    # Symbol-only text is also a placeholder even though it is not one of the
    # recognized placeholder tokens.
    if (-not (Test-MeaningfulChar $n)) { return $true }
    switch -Regex ($n) {
        '^(tbd|todo|pending|none\s+identified|none\s+provided)$' { return $true }
        '^(tbd|todo|pending|none\s+identified|none\s+provided):' { return $true }
        '^(tbd|todo|pending)\s' { return $true }
        '^[^:]+:\s*(tbd|todo|pending|none\s+identified|none\s+provided)$' { return $true }
        '^\d{4}-\d{2}-\d{2}$' { return $true }
    }
    if (($n -replace '[^a-z0-9]', '') -eq 'explainwhythislevelappliesandidentifyanyescalationsignals') { return $true }
    return $false
}

# Get-ContentClass — classifies authoritative content lines as 'content'
# (real evidence), 'placeholder' (lines exist but none are real), or 'empty'.
# Headings, table separators, blank bullets, and placeholder text (see
# Test-TextIsPlaceholder) do not count as content. A table counts only once a
# data row with at least one real cell follows its header.
function Get-ContentClass {
    param([string[]]$Content)
    $tableHeaderSeen = $false
    $sawLines = $false
    foreach ($line in $Content) {
        if ($line -notmatch '\S') {
            # A blank line ends any in-progress table; reset so the header of a
            # following table is not mistaken for the prior table's data row.
            $tableHeaderSeen = $false
            continue
        }
        if ($line -match '^\s*#') { continue }
        if ($line -match '---') { continue }
        $sawLines = $true
        if ($line -match '^\s*\|.*\|.*\|\s*$') {
            if ($tableHeaderSeen) {
                if (Test-TableRowContent $line) { return 'content' }
                continue
            }
            $tableHeaderSeen = $true
            continue
        }
        # A non-table line ends any in-progress table.
        $tableHeaderSeen = $false
        $text = ($line -replace '^\s*[-*+]\s+', '').Trim()
        if (-not $text) { continue }
        if (Test-TextIsPlaceholder $text) { continue }
        return 'content'
    }
    if (-not $sawLines) { return 'empty' }
    return 'placeholder'
}

function Test-SectionRealContent {
    param([string]$Name)
    return ((Get-ContentClass (Get-SectionContent $Name)) -eq 'content')
}

function Test-SubsectionRealContent {
    param([string]$Name, [string]$Section)
    return ((Get-ContentClass (Get-SubsectionContent $Name $Section)) -eq 'content')
}

# Assert-VerificationEvidence — a completed task must carry real verification
# evidence. Missing evidence is INVALID; placeholder-only evidence is BLOCKED.
function Assert-VerificationEvidence {
    param([string]$Kind, [string[]]$Content)
    $cls = Get-ContentClass $Content
    if ($cls -eq 'content') { return }
    if ($cls -eq 'empty') { Write-Invalid "EVIDENCE_MAPPING_INVALID" $Kind '' "completed task must record verification evidence under '$Kind'." }
    Write-Blocked "EVIDENCE_UNRESOLVED" $Kind '' "completed task verification under '$Kind' is still a placeholder (TBD, TODO, Pending, or similar)."
}

# Assert-VerificationEvidenceNone — like Assert-VerificationEvidence, but accepts
# the exact 'None identified' sentinel as a resolved statement (Remaining risks).
function Assert-VerificationEvidenceNone {
    param([string]$Kind, [string[]]$Content)
    $cls = Get-ContentClass $Content
    if ($cls -eq 'content') { return }
    if ($cls -eq 'placeholder') {
        $normalized = (($Content -join "`n").ToLowerInvariant() -replace '^\s*[-*+]\s+', '' -replace '[^a-z0-9]', '')
        if ($normalized -eq 'noneidentified') { return }
    }
    if ($cls -eq 'empty') { Write-Invalid "EVIDENCE_MAPPING_INVALID" $Kind '' "completed task must record verification evidence under '$Kind'." }
    Write-Blocked "EVIDENCE_UNRESOLVED" $Kind '' "completed task verification under '$Kind' is still a placeholder (TBD, TODO, Pending, or similar)."
}

# Assert-CompletionDescriptions — a completed task must give every declared
# identifier a real, non-placeholder description.
function Assert-CompletionDescriptions {
    param([string[]]$ContentLines, [string]$IdPattern, [string]$Kind)
    foreach ($line in $ContentLines) {
        if ($line -notmatch '^\s*[-*+]\s+') { continue }
        $lowLine = $line.ToLowerInvariant()
        $idMatch = [regex]::Match($lowLine, $IdPattern)
        if (-not $idMatch.Success) { continue }
        $id = $idMatch.Value
        $desc = ([regex]::Match($lowLine, "^\s*[-*+]\s*$IdPattern\s*:\s*(.*?)\s*$")).Groups[1].Value
        if (-not $desc -or ((Get-ContentClass @($desc)) -eq 'placeholder')) {
            Write-Blocked "EVIDENCE_UNRESOLVED" $Kind $id "$Kind '$id' has a placeholder description."
        }
    }
}

# Get-CanonicalIds — gathers identifiers only from canonical list rows of the
# form '- <id>: <description>' (case-insensitive) and sets the script-scope
# globals MultiIds (a row declares more than one identifier), BadForm (a list
# row with an identifier that is not canonical), and DupIds. Identifiers
# mentioned in prose are not collected, so criteria must be declared as
# canonical rows.
function Get-CanonicalIds {
    param([string[]]$ContentLines, [string]$IdPattern)
    $script:MultiIds = $false
    $script:BadForm = $false
    $script:DupIds = $false
    $script:Unnumbered = $false
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $ContentLines) {
        if ($line -notmatch '^\s*[-*+]\s+') { continue }
        $lowLine = $line.ToLowerInvariant()
        $idMatches = [regex]::Matches($lowLine, $IdPattern)
        if ($idMatches.Count -gt 1) { $script:MultiIds = $true; continue }
        if ($idMatches.Count -eq 0) { $script:Unnumbered = $true; continue }
        if ($lowLine -notmatch "^\s*[-*+]\s*$IdPattern\s*:\s*\S") { $script:BadForm = $true; continue }
        $id = $idMatches[0].Value
        if (-not $seen.Add($id)) { $script:DupIds = $true }
        elseif (-not $out.Contains($id)) { $out.Add($id) }
    }
    return , $out.ToArray()
}

# Assert-CanonicalSection — every line in a canonical-only section that is a
# candidate entry or mentions an identifier token must be a canonical list item
# '- <ID>: <description>'. A candidate entry is a line that starts a list item
# (bullet, numbered, or bare '<ID>:' declaration); those are exactly the lines
# that could declare a criterion or requirement. Any line that contains an
# identifier token anywhere (for example 'AC-2' embedded in a paragraph) must
# also be a canonical entry, so a prose mention cannot declare an extra
# criterion or requirement that escapes the evidence contract. Bare, numbered,
# and prose-declared identifiers are rejected rather than skipped. Continuation
# lines and notes paragraphs that contain no identifier token are allowed: they
# belong to the preceding canonical item.
function Assert-CanonicalSection {
    param([string[]]$ContentLines, [string]$IdPattern, [string]$Label, [string]$EntryForm)
    # An identifier token is delimited by non-alphanumerics so that a prose
    # fragment such as 'R-2D2' is not mistaken for a requirement identifier.
    $idBound = '(^|[^a-z0-9])' + $IdPattern + '($|[^a-z0-9])'
    foreach ($line in $ContentLines) {
        if ($line -notmatch '\S') { continue }
        $lowLine = $line.ToLowerInvariant()
        if ($lowLine -match $idBound) {
            if ($lowLine -notmatch "^[-*+]\s*$IdPattern\s*:\s*\S") {
                Write-Invalid "CRITERION_INVALID" $Label '' "$Label must contain only canonical '$EntryForm' list entries; identifiers may not appear in prose or non-canonical lines."
            }
        }
        if ($lowLine -notmatch '^([-*+]\s*|\d+[.)]\s+|(ac|r)-\d+\s*:)') { continue }
        if ($lowLine -notmatch "^[-*+]\s*$IdPattern\s*:\s*\S") {
            Write-Invalid "CRITERION_INVALID" $Label '' "$Label must contain only canonical '$EntryForm' list entries; identifiers may not appear in prose or non-canonical lines."
        }
    }
}

$AllowedResults = @('passed', 'satisfied', 'n/a', 'pending', 'partial', 'blocked', 'missing', 'not-run')
$UnresolvedResults = @('pending', 'partial', 'blocked', 'missing', 'not-run')

# Get-TableRowParts <trimmed-line> — splits a Markdown table row into its trimmed
# cells (leading/trailing pipe stripped, cells split on '|') and returns an array.
function Get-TableRowParts {
    param([string]$Row)
    $body = $Row -replace '^\s*\|', '' -replace '\|\s*$', ''
    if (-not $body) { return @() }
    $cells = @()
    foreach ($c in ($body -split '\|')) { $cells += $c.Trim() }
    return , $cells
}

# Test-TableRowIsSeparator <cells> — true when the row has exactly three cells,
# all of which are a Markdown `---` (or `:---:` etc.) separator of at least
# three hyphens.
function Test-TableRowIsSeparator {
    param([string[]]$Cells)
    if ($Cells.Count -ne 3) { return $false }
    foreach ($c in $Cells) {
        if ($c -notmatch '^:?-{3,}:?$') { return $false }
    }
    return $true
}

# Test-Table <section> <id-pattern> <label> <header-label> — validates a
# canonical `| <header-label> | Evidence | Result |` table: an exact header
# row, one separator row, then canonical data rows with exactly three
# meaningful cells. Every table-shaped row is structurally authoritative;
# malformed rows (extra or missing columns, unknown or malformed ids, a header
# whose labels do not match the expected schema, rows before the header, a
# second header/separator, and pipe-delimited lines without a leading pipe)
# are rejected rather than silently skipped. Returns the lowercased row ids
# and sets the globals TableDup and HasUnresolved.
function Test-Table {
    param([string]$Section, [string]$IdPattern, [string]$Label, [string]$HeaderLabel)
    $script:TableDup = $false
    $script:HasUnresolved = $false
    $ids = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $stage = 0
    $lp = $IdPattern.ToLowerInvariant()
    $hl = $HeaderLabel.ToLowerInvariant()
    # Literal id prefix (the pattern before its regex suffix), e.g. 'AC-\d+' -> 'ac-'.
    $idPrefix = ($IdPattern -split '\\')[0].ToLowerInvariant()
    foreach ($rawLine in (Get-SectionContent $Section)) {
        if ($rawLine -notmatch '\S') { continue }
        $trimmed = $rawLine.Trim()
        if ($trimmed -notmatch '^\|') {
            # A pipe-delimited line that omitted its leading pipe is a table
            # row; reject it rather than silently treating it as prose.
            if ($trimmed -match '[^|]+\|[^|]+\|[^|]+') {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table rows must begin with a leading pipe."
            }
            # Also reject a row that opens with a known identifier or the
            # expected header label even when its other cells are empty or
            # missing, so a malformed duplicate cannot hide an unresolved row.
            if ($trimmed -match "^($([regex]::Escape($idPrefix))|$([regex]::Escape($hl)))[^|]*\|") {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table rows must begin with a leading pipe."
            }
            continue
        }
        $cells = Get-TableRowParts $trimmed
        $id = if ($cells.Count -gt 0) { $cells[0] } else { '' }
        if ($stage -eq 0) {
            if (Test-TableRowIsSeparator $cells) {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table must have a header row before its separator."
            }
            if ($id.ToLowerInvariant() -match "^$lp$") {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table has a data row before its header."
            }
            if ($cells.Count -ne 3) { Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table row has $($cells.Count) columns (expected 3)." }
            $h1 = $cells[0].ToLowerInvariant()
            $h2 = $cells[1].ToLowerInvariant()
            $h3 = $cells[2].ToLowerInvariant()
            if ($h1 -ne $hl -or $h2 -ne 'evidence' -or $h3 -ne 'result') {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table header must be '| $HeaderLabel | Evidence | Result |'."
            }
            $stage = 1
            continue
        }
        if ($stage -eq 1) {
            if (-not (Test-TableRowIsSeparator $cells)) {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table is missing its separator row."
            }
            if ($cells.Count -ne 3) { Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table separator has $($cells.Count) columns (expected 3)." }
            $stage = 2
            continue
        }
        # Canonical data row.
        if (Test-TableRowIsSeparator $cells) {
            Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table must not contain a second header or separator."
        }
        if ($cells.Count -ne 3) { Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label '' "$Label table row has $($cells.Count) columns (expected 3)." }
        $ev = $cells[1]
        $res = $cells[2]
        if ($id -notmatch "^$IdPattern$") {
            Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label $id "$Label row '$id' has an unrecognized identifier."
        }
        $idLower = $id.ToLowerInvariant()
        if (-not $ev) { Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label $idLower "$Label row '$idLower' has an empty evidence description." }
        if ($script:Completed -and ((Get-ContentClass @($ev)) -eq 'placeholder')) {
            Write-Blocked "EVIDENCE_UNRESOLVED" $Label $idLower "$Label row '$idLower' has a placeholder evidence description."
        }
        if (-not $res) { Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label $idLower "$Label row '$idLower' has an empty result." }
        $lres = $res.ToLowerInvariant()
        if ($AllowedResults -notcontains $lres) {
            Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label $idLower "$Label row '$idLower' has unrecognized result '$res' (allowed: passed, satisfied, n/a, pending, partial, blocked, missing, not-run)."
        }
        if ($lres -eq 'n/a') {
            # A resolved 'n/a' must carry a structured 'N/A: <reason>'
            # rationale with meaningful text after the colon.
            $evLower = $ev.ToLowerInvariant()
            if ($evLower -notmatch '^\s*n/a\s*:\s*\S') {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label $idLower "$Label row '$idLower' uses 'n/a' without a substantive 'N/A: <reason>' rationale."
            }
            $rationale = ([regex]::Match($evLower, '^\s*n/a\s*:\s*(.*?)\s*$')).Groups[1].Value
            if ((Get-ContentClass @($rationale)) -ne 'content') {
                Write-Invalid "EVIDENCE_MAPPING_INVALID" $Label $idLower "$Label row '$idLower' uses 'n/a' with a placeholder rationale."
            }
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
        $requiredSections = @('status', 'risk profile', 'profile rationale', 'task goal', 'smoke verification', 'known limitations', 'approval gates', 'handoff')
    }
    'standard' {
        $requiredSections = @('status', 'risk profile', 'profile rationale', 'acceptance criteria', 'required evidence', 'approval gates', 'verification', 'files changed', 'remaining risks')
        $requiredSubsections = @('baseline', 'final')
    }
    'high-assurance' {
        $requiredSections = @(
            'status', 'risk profile', 'profile rationale', 'requirements', 'risk analysis', 'requirement-to-evidence',
            'negative-path and boundary tests', 'integration verification', 'recovery plan', 'approval gates',
            'independent review', 'acceptance criteria', 'required evidence', 'verification', 'files changed', 'remaining risks'
        )
        $requiredSubsections = @('baseline', 'final')
    }
}

foreach ($s in $requiredSections) {
    if ($SECTIONS -notcontains $s) { Write-Invalid "SECTION_MISSING" '' '' "missing required section '## $s' for profile '$ProfileName'." }
}
foreach ($s in $requiredSubsections) {
    $found = $false
    for ($i = 0; $i -lt $SUBSECTIONS.Count; $i++) {
        if ($SUBSECTIONS[$i] -eq $s -and $SUB_SECTION[$i] -eq 'verification') { $found = $true; break }
    }
    if (-not $found) { Write-Invalid "SECTION_MISSING" '' '' "missing '### $s' subsection under '## Verification' for profile '$ProfileName'." }
}

# Completed tasks must record real evidence in every section the profile
# declares as required. Missing content is INVALID; placeholder-only content
# is BLOCKED at completion.
if ($Completed) {
    Assert-VerificationEvidence '## Profile rationale' (Get-SectionContent 'profile rationale')
}
if ($ProfileName -ne 'prototype' -and $Completed) {
    Assert-VerificationEvidence '### Baseline' (Get-SubsectionContent 'baseline' 'verification')
    Assert-VerificationEvidence '### Final' (Get-SubsectionContent 'final' 'verification')
    Assert-VerificationEvidence '## Files changed' (Get-SectionContent 'files changed')
    Assert-VerificationEvidenceNone '## Remaining risks' (Get-SectionContent 'remaining risks')
}

# ---------------------------------------------------------------------------
# Prototype contract.
# ---------------------------------------------------------------------------
if ($ProfileName -eq 'prototype') {
    # The two handoff declarations must appear as exact normalized declaration
    # lines, each exactly once. Substring matches are not enough: a line that
    # carries the phrase but adds negation or commentary ("... not established
    # — this statement is false.", "... confirmed? No.") is rejected, and a
    # phrase that appears only inside prose is not counted. Insignificant
    # casing and surrounding whitespace are ignored; a leading list marker is
    # stripped so a bulleted declaration still counts as a declaration line.
    $readinessDecl = 0
    $noDeployDecl = 0
    foreach ($dl in (Get-SectionContent 'handoff')) {
        $d = ((($dl -replace '^\s*[-*+]\s+', '').Trim() -replace '\s+', ' ').Trim()).ToLowerInvariant()
        if (-not $d) { continue }
        if ($d -eq 'production readiness: not established') { $readinessDecl++ }
        elseif ($d -eq 'no production deployment or irreversible operation: confirmed') { $noDeployDecl++ }
        if ($d -match '^production\s+readiness\s*:' -and $d -ne 'production readiness: not established') {
            Write-Invalid "PROTOTYPE_DECLARATION_INVALID" '' '' "prototype handoff declaration 'Production readiness' must appear as the exact line 'Production readiness: not established'."
        }
        if ($d -match '^no\s+production\s+deployment\s+or\s+irreversible\s+operation\s*:' -and $d -ne 'no production deployment or irreversible operation: confirmed') {
            Write-Invalid "PROTOTYPE_DECLARATION_INVALID" '' '' "prototype handoff declaration 'No production deployment or irreversible operation' must appear as the exact line 'No production deployment or irreversible operation: confirmed'."
        }
    }
    if ($readinessDecl -ne 1) {
        Write-Invalid "PROTOTYPE_DECLARATION_INVALID" '' '' "prototype handoff must state 'Production readiness: not established' exactly once."
    }
    if ($noDeployDecl -ne 1) {
        Write-Invalid "PROTOTYPE_DECLARATION_INVALID" '' '' "prototype handoff must declare 'No production deployment or irreversible operation: confirmed' exactly once."
    }
    if ($Completed) {
        Assert-VerificationEvidence '## Task goal' (Get-SectionContent 'task goal')
        Assert-VerificationEvidence '## Known limitations' (Get-SectionContent 'known limitations')
        Assert-VerificationEvidence '## Smoke verification' (Get-SectionContent 'smoke verification')
        Assert-VerificationEvidence '## Handoff' (Get-SectionContent 'handoff')
    }
}

# ---------------------------------------------------------------------------
# Standard and high-assurance evidence contracts.
# ---------------------------------------------------------------------------
if ($ProfileName -ne 'prototype') {
    $acIds = Get-CanonicalIds (Get-SectionContent 'acceptance criteria') 'ac-\d+'
    if ($script:MultiIds) { Write-Invalid "CRITERION_INVALID" '' '' "an acceptance criterion list entry declares more than one 'AC-N' identifier." }
    if ($script:BadForm) { Write-Invalid "CRITERION_INVALID" '' '' "acceptance criteria must use the form '- AC-N: <description>'." }
    if ($script:Unnumbered) { Write-Invalid "CRITERION_INVALID" '' '' "every acceptance criterion list entry must begin with exactly one 'AC-N:' identifier; explanatory prose belongs in a separate Notes section." }
    Assert-CanonicalSection (Get-SectionContent 'acceptance criteria') 'ac-\d+' 'acceptance criteria' 'AC-N: <description>'
    if ($acIds.Count -eq 0) { Write-Invalid "CRITERION_INVALID" '' '' "acceptance criteria must declare at least one 'AC-N' identifier." }
    if ($script:DupIds) { Write-Invalid "CRITERION_INVALID" '' '' "acceptance criteria declare duplicate 'AC-N' identifiers." }
    if ($Completed) {
        Assert-CompletionDescriptions (Get-SectionContent 'acceptance criteria') 'ac-\d+' 'acceptance criterion'
    }

    $evIds = Test-Table 'required evidence' 'AC-\d+' 'required evidence' 'AC ID'
    if ($evIds.Count -eq 0) { Write-Invalid "EVIDENCE_MAPPING_INVALID" '' '' "required evidence must map at least one 'AC-N' to evidence." }
    if ($script:TableDup) { Write-Invalid "EVIDENCE_MAPPING_INVALID" '' '' "required evidence maps a criterion more than once." }
    if (((Get-SortedUnique $acIds) -join ' ') -ne ((Get-SortedUnique $evIds) -join ' ')) {
        Write-Invalid "EVIDENCE_MAPPING_INVALID" '' '' "acceptance criteria and required evidence must list exactly the same 'AC-N' identifiers."
    }
    if ($Completed -and $script:HasUnresolved) {
        Write-Blocked "EVIDENCE_UNRESOLVED" '' '' "task is marked complete but required evidence remains unresolved (pending, partial, blocked, missing, or not-run)."
    }

    if ($ProfileName -eq 'high-assurance') {
        $rIds = Get-CanonicalIds (Get-SectionContent 'requirements') 'r-\d+'
        if ($script:MultiIds) { Write-Invalid "CRITERION_INVALID" '' '' "a high-assurance requirement list entry declares more than one 'R-N' identifier." }
        if ($script:BadForm) { Write-Invalid "CRITERION_INVALID" '' '' "high-assurance requirements must use the form '- R-N: <description>'." }
        if ($script:Unnumbered) { Write-Invalid "CRITERION_INVALID" '' '' "every high-assurance requirement list entry must begin with exactly one 'R-N:' identifier; explanatory prose belongs in a separate Notes section." }
        Assert-CanonicalSection (Get-SectionContent 'requirements') 'r-\d+' 'high-assurance requirements' 'R-N: <description>'
        if ($rIds.Count -eq 0) { Write-Invalid "CRITERION_INVALID" '' '' "high-assurance requirements must declare at least one 'R-N' identifier." }
        if ($script:DupIds) { Write-Invalid "CRITERION_INVALID" '' '' "high-assurance requirements declare duplicate 'R-N' identifiers." }
        if ($Completed) {
            Assert-CompletionDescriptions (Get-SectionContent 'requirements') 'r-\d+' 'high-assurance requirement'
        }

        $mIds = Test-Table 'requirement-to-evidence' 'R-\d+' 'requirement-to-evidence' 'Requirement ID'
        if ($mIds.Count -eq 0) { Write-Invalid "EVIDENCE_MAPPING_INVALID" '' '' "the requirement-to-evidence matrix must map at least one 'R-N' to evidence." }
        if ($script:TableDup) { Write-Invalid "EVIDENCE_MAPPING_INVALID" '' '' "the requirement-to-evidence matrix maps a requirement more than once." }
        if (((Get-SortedUnique $rIds) -join ' ') -ne ((Get-SortedUnique $mIds) -join ' ')) {
            Write-Invalid "EVIDENCE_MAPPING_INVALID" '' '' "requirements and the requirement-to-evidence matrix must list exactly the same 'R-N' identifiers."
        }
        if ($Completed -and $script:HasUnresolved) {
            Write-Blocked "EVIDENCE_UNRESOLVED" '' '' "task is marked complete but the requirement-to-evidence matrix has unresolved rows."
        }

        foreach ($s in @('risk analysis', 'negative-path and boundary tests', 'integration verification', 'recovery plan', 'independent review')) {
            if (-not (Test-SectionRealContent $s)) { Write-Invalid "CRITERION_INVALID" $s '' "high-assurance section '## $s' must contain real content (no headings, placeholders, or separators)." }
        }
    }
}

# ---------------------------------------------------------------------------
# Approval gates: structured records only; no prose-based approval inference.
# Validated for every profile whenever an '## Approval gates' section exists.
# ---------------------------------------------------------------------------
if ($SECTIONS -contains 'approval gates') {
    $hasNone = $false
    $gateCount = 0
    $checked = 0
    $unchecked = 0
    $gateSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rawLine in (Get-SectionContent 'approval gates')) {
        $gl = $rawLine.Trim()
        if (-not $gl) { continue }
        $glLow = $gl.ToLowerInvariant()
        $bodyLow = (($glLow -replace '^[-*+]\s+', '').Trim() -replace '\s*[.!?;:,-]+$', '')
        if ($bodyLow -eq 'none identified') { $hasNone = $true; continue }
        if ($glLow -match '^[-*+]\s*\[[ xX]\]') {
            if ($glLow -notmatch '^[-*+]\s*\[[ xX]\]\s*ag-\d+\s*:') {
                Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "malformed approval entry in '## Approval gates': entries must be '- [ ] AG-N: <requirement>' or '- [x] AG-N: Approved by <approver> on YYYY-MM-DD'."
            }
            $m = [regex]::Match($glLow, '^[-*+]\s*\[([ xX])\]\s*(ag-\d+)\s*:\s*(.*?)\s*$')
            $gid = $m.Groups[2].Value
            $gbox = $m.Groups[1].Value
            $gdet = $m.Groups[3].Value.Trim()
            $gateCount++
            if (-not $gateSeen.Add($gid)) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' is declared more than once." }
            if ($gbox -eq 'x') {
                $checked++
                if ($gdet -notmatch '^approved\s+by\s+.+\s+on\s+\d{4}-\d{2}-\d{2}\s*$') {
                    Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' must be in the form '- [x] AG-N: Approved by <approver> on YYYY-MM-DD'."
                }
                if ($gdet -match '<approver>|tbd|pending|unknown|n/a|not\s+approved|approval\s+not\s+granted') {
                    Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' must not use placeholder values."
                }
                # Parse anchored groups so the date validated is the trailing
                # approval date, not an earlier date that happens to appear in
                # the approver text.
                $am = [regex]::Match($gdet, '^approved\s+by\s+(.+?)\s+on\s+(\d{4}-\d{2}-\d{2})\s*$')
                $approvalDate = $am.Groups[2].Value
                $approver = $am.Groups[1].Value
                if (-not $approvalDate) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' must record an ISO date YYYY-MM-DD." }
                if (-not (Test-IsoDate $approvalDate)) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' has an invalid ISO date '$approvalDate'." }
                if (-not $approver) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' must record an approver." }
                if ($approver -match '[<>]') { Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' must not use template placeholders." }
                if (-not (Test-MeaningfulChar $approver)) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' must record a meaningful approver." }
            }
            else {
                $unchecked++
                if (-not $gdet) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "approval gate '$gid' must describe the required approval." }
                if ($gdet -match '^approved\s+by\s+.+\s+on\s+\d{4}-\d{2}-\d{2}\s*$') {
                    Write-Invalid "APPROVAL_INVALID" '## Approval gates' $gid "unchecked approval gate '$gid' cannot record an approval; describe the requirement instead."
                }
            }
            continue
        }
        if ($glLow -match '\[[ xX]\]') {
            Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "malformed approval entry in '## Approval gates': entries must be '- [ ] AG-N: <requirement>' or '- [x] AG-N: Approved by <approver> on YYYY-MM-DD'."
        }
        if ($glLow -match '^[-*+]\s+') {
            Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "malformed approval entry in '## Approval gates': entries must be '- [ ] AG-N: <requirement>' or '- [x] AG-N: Approved by <approver> on YYYY-MM-DD'."
        }
        Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "malformed approval entry in '## Approval gates': entries must be '- [ ] AG-N: <requirement>' or '- [x] AG-N: Approved by <approver> on YYYY-MM-DD'."
    }

    if ($hasNone -and $gateCount -gt 0) {
        Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "approval gates cannot both declare 'None identified' and structured gates."
    }
    if ($ProfileName -eq 'high-assurance') {
        if ($hasNone) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "high-assurance tasks require explicit approval gates ('None identified' is not permitted)." }
        if ($gateCount -eq 0) { Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "high-assurance tasks must declare at least one approval gate 'AG-N'." }
    }
    elseif (-not $hasNone -and $gateCount -eq 0) {
        Write-Invalid "APPROVAL_INVALID" '## Approval gates' '' "approval gates must declare structured 'AG-N' records or 'None identified'."
    }
    if ($Completed -and $unchecked -gt 0) {
        Write-Blocked "APPROVAL_UNRESOLVED" '## Approval gates' '' "task is marked complete but an approval gate remains unchecked."
    }
}

if ($Format -eq 'Json') {
    Output-TaskJson 'VALID' 0 'Task is valid.' 'VALID'
}
else {
    Write-Host "VALID: profile=$ProfileName"
}
exit 0
