#Requires -Version 7.0
<#
.SYNOPSIS
    validate-context.ps1 — structural validator for context-module selections.

.DESCRIPTION
    Validates only structural facts about the `## Context modules` section of a
    task file against the managed registry under `.agentic/context/`:

      - every selected module exists in the registry
      - no duplicate module IDs
      - every selection carries a real rationale
      - the task's risk profile satisfies each module's minimum profile
      - a completed task has no unresolved selection placeholders
      - the `None selected` sentinel never coexists with selections
      - selection versions are recognized by the registry

    Content in fenced code blocks, HTML comments, and blockquote lines is not
    authoritative and is ignored.

    Exit codes: 0 VALID, 1 INVALID, 2 BLOCKED.

.PARAMETER TaskFile
    Task file to validate.

.PARAMETER Handoff
    Require Status: done and enforce the completion gate.

.PARAMETER Format
    Output format: Text (default) or Json.

.EXAMPLE
    pwsh -NoProfile -File validate-context.ps1 .agentic/tasks/TASK-001.md
#>
param(
    [switch]$Handoff,
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TaskFile,
    [ValidateSet('Text', 'Json')]
    [string] $Format = 'Text'
)

$ErrorActionPreference = 'Stop'

$script:RegistryDir = if ($env:AGENTIC_CONTEXT_REGISTRY) {
    $env:AGENTIC_CONTEXT_REGISTRY
}
else {
    Join-Path (Split-Path -Parent $PSScriptRoot) 'context'
}

$script:ProfileName = $null
$script:StatusName = $null
$script:SectionFound = $false
$script:SectionLines = [System.Collections.Generic.List[string]]::new()

function Output-ContextJson {
    param(
        [string]$Result,
        [int]$ExitCode,
        [string]$Message,
        [string]$Code = 'MODULE_UNKNOWN',
        [string]$Section = $null,
        [string]$Identifier = $null,
        [array]$SelectedModules = @()
    )
    $diagList = @()
    if ($Result -ne 'VALID') {
        $diagList += [ordered]@{
            code       = $Code
            section    = $Section
            identifier = $Identifier
            message    = $Message
        }
    }
    # Profile: null when not present or recognized — never invent defaults that
    # would mislead automation.
    $profileOut = if ($script:ProfileName -in @('prototype', 'standard', 'high-assurance')) { $script:ProfileName } else { $null }

    $selectedOut = @()
    foreach ($m in $SelectedModules) {
        $selectedOut += [ordered]@{ id = $m.Id; version = [int]$m.Version }
    }

    $resultObject = [ordered]@{
        schema_version   = 1
        protocol_version = "1.5.0"
        kind             = "context_validation_result"
        mode             = if ($Handoff) { "handoff" } else { "standard" }
        result           = $Result
        exit_code        = $ExitCode
        task_file        = $TaskFile
        profile          = $ProfileOut
        selected_modules = $selectedOut
        diagnostics      = $diagList
    }
    [Console]::Out.WriteLine(($resultObject | ConvertTo-Json -Compress -Depth 4))
}

function Write-Invalid {
    param([string]$Code, [string]$Section, [string]$Identifier, [string]$Message)
    if ($Format -eq 'Json') {
        Output-ContextJson 'INVALID' 1 $Message $Code $Section $Identifier
        exit 1
    }
    else {
        [Console]::Error.WriteLine("INVALID: $Message")
        exit 1
    }
}

function Write-Blocked {
    param([string]$Code, [string]$Section, [string]$Identifier, [string]$Message)
    if ($Format -eq 'Json') {
        Output-ContextJson 'BLOCKED' 2 $Message $Code $Section $Identifier
        exit 2
    }
    else {
        [Console]::Error.WriteLine("BLOCKED: $Message")
        exit 2
    }
}

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    if ($Format -eq 'Json') {
        Write-Invalid 'CONTEXT_SECTION_MISSING' '' '' "Task file was not found: $(Split-Path -Leaf $TaskFile)"
    }
    else {
        [Console]::Error.WriteLine("Error: task file not found: $TaskFile")
    }
    exit 1
}

# True when the value carries at least one Unicode letter or number (or ASCII
# equivalent), so symbol-only strings are not mistaken for rationales.
function Test-MeaningfulChar {
    param([string]$Value)
    return ($Value -match '[\p{L}\p{N}]')
}

# True when the value is recognized placeholder content rather than a real
# rationale. Mirrors the Bash predicate on the shared fixture corpus.
function Test-PlaceholderText {
    param([string]$Text)
    $trimmed = $Text.Trim()
    if ($trimmed -match '^[\[\]<].*[\[\]>]$' -and $trimmed.Length -ge 2) { return $true }
    $n = (($trimmed -replace '^\s*[-*+]\s+', '').Trim() -replace '\s*[.!?;:,-]+$', '').ToLowerInvariant()
    if (-not $n) { return $true }
    if ($n -in @('tbd', 'todo', 'pending', 'placeholder', 'tbc', 'none', 'n/a')) { return $true }
    if ($n -match 'tbd|todo|pending') { return $true }
    return $false
}

# ---------------------------------------------------------------------------
# Load the registry: every <registry>/<id>/MODULE.md declaring ID and Version.
# A module whose declared Version is malformed makes the registry unverifiable
# and blocks the run rather than guessing.
# ---------------------------------------------------------------------------
$script:ModuleIds = [System.Collections.Generic.List[string]]::new()
$script:ModuleVersions = [System.Collections.Generic.List[string]]::new()

function Get-HeadingValue {
    # Returns the first non-blank line after `<heading>` in $content, or $null.
    param([string[]]$ContentLines, [string]$HeadingLower)
    $grab = $false
    foreach ($line in $ContentLines) {
        $norm = $line.TrimEnd().ToLowerInvariant()
        if ($norm -match '^##\s') {
            if ($grab) { break }
            if ($norm -eq $HeadingLower) { $grab = $true }
            continue
        }
        if ($grab -and -not [string]::IsNullOrWhiteSpace($line)) {
            return $line.Trim()
        }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $script:RegistryDir -PathType Container)) {
    Write-Blocked 'CONTEXT_REGISTRY_MISSING' '' '' "Context module registry not found: $(Split-Path -Leaf $script:RegistryDir)"
}

foreach ($dir in (Get-ChildItem -LiteralPath $script:RegistryDir -Directory | Sort-Object Name)) {
    $mf = Join-Path $dir.FullName 'MODULE.md'
    if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) { continue }
    $moduleLines = Get-Content -LiteralPath $mf
    $id = Get-HeadingValue $moduleLines '## id'
    $ver = Get-HeadingValue $moduleLines '## version'
    if ($null -eq $ver -or $ver -notmatch '^[1-9][0-9]*$') {
        Write-Blocked 'MODULE_VERSION_UNSUPPORTED' 'registry' $dir.Name "Module '$($dir.Name)' declares an unsupported version ('$ver'); registry is unusable."
    }
    $script:ModuleIds.Add($id)
    $script:ModuleVersions.Add($ver)
}

# ---------------------------------------------------------------------------
# Authoritative-line scan of the task file: drop fenced code blocks, HTML
# comment blocks, and blockquote lines; collect Profile/Status declarations
# and the raw body of `## Context modules` until the next `##` heading.
# ---------------------------------------------------------------------------
$inFence = $false
$inComment = $false
$inSection = $false
foreach ($raw in (Get-Content -LiteralPath $TaskFile)) {
    $line = $raw.TrimEnd()
    if ($inFence) {
        if ($line -match '^```)') { $inFence = $false }
        continue
    }
    if ($line -match '^```') { $inFence = $true; continue }
    if ($inComment) {
        if ($line -match '-->') { $inComment = $false }
        continue
    }
    if ($line -match '<!--') {
        if ($line -notmatch '-->') { $inComment = $true }
        continue
    }
    if ($line -match '^>') { continue }

    $norm = $line.ToLowerInvariant().TrimEnd()
    if ($norm -match '^profile:\s*(\S+)') {
        $script:ProfileName = $Matches[1]
        continue
    }
    if ($norm -match '^status:\s*(\S+)') {
        $script:StatusName = $Matches[1]
        continue
    }
    if ($norm -match '^##\s') {
        $inSection = $false
        if ($norm -eq '## context modules') {
            $script:SectionFound = $true
            $inSection = $true
        }
        continue
    }
    if ($inSection) {
        $script:SectionLines.Add($line)
    }
}

if ($Handoff -and $script:StatusName -ne 'done') {
    Write-Invalid 'CONTEXT_SECTION_MISSING' '## Status' '' "--handoff requires 'Status: done'; found '$($script:StatusName ?? '<none>')'."
}

if (-not $script:SectionFound) {
    Write-Invalid 'CONTEXT_SECTION_MISSING' '## Context modules' '' "Task file has no '## Context modules' section."
}

# Selection state.
$selectionCount = 0
$noneSentinelSeen = $false
$selectedIds = [System.Collections.Generic.List[string]]::new()
$selectedVersions = [System.Collections.Generic.List[string]]::new()
$selectedForJson = [System.Collections.Generic.List[object]]::new()

function Get-Rank([string]$p) {
    switch ($p) {
        'prototype' { 0 }
        'standard' { 1 }
        'high-assurance' { 2 }
        default { -1 }
    }
}

foreach ($rawLine in $script:SectionLines) {
    $entry = ($rawLine -replace '^\s*[-*+]\s+', '').Trim()
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }

    if ($entry -imatch '^none\s+selected\b') {
        $noneSentinelSeen = $true
        continue
    }

    $selectionCount++
    $tokens = $entry -split '\s+'
    $id = if ($tokens.Count -gt 0) { $tokens[0] } else { '' }
    $verToken = if ($tokens.Count -gt 1) { $tokens[1] } else { '' }
    $loadedToken = if ($tokens.Count -gt 2) { $tokens[2] } else { '' }
    $rest = if ($tokens.Count -gt 3) { ($tokens[3..($tokens.Count - 1)] -join ' ') } else { '' }

    # Case-sensitive grammar checks mirror the Bash validator exactly.
    if ($entry -cnotmatch '^\S+\s+v[1-9][0-9]*\s+\S+') {
        Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' $entry "Selection entry is not in the canonical form '<module-id> v<N> loaded — <rationale>': $entry"
    }

    $sepRationale = ($rest -creplace '^[—–-]\s*', '')

    if ($loadedToken -cne 'loaded') {
        Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' $id "Selection of '$id' does not confirm the module was loaded before planning."
    }

    $regIndex = -1
    for ($ri = 0; $ri -lt $script:ModuleIds.Count; $ri++) {
        if ([System.StringComparer]::Ordinal.Equals($script:ModuleIds[$ri], $id)) { $regIndex = $ri; break }
    }
    if ($regIndex -lt 0) {
        Write-Invalid 'MODULE_UNKNOWN' '## Context modules' $id "Selected module '$id' is not in the managed registry."
    }

    $regVer = $script:ModuleVersions[$regIndex]
    $selVer = $verToken -creplace '^v', ''
    if ($selVer -cne $regVer) {
        Write-Invalid 'MODULE_VERSION_UNSUPPORTED' '## Context modules' $id "Selection of '$id' declares version '$selVer' but the registry provides '$regVer'."
    }

    if (-not (Test-MeaningfulChar $sepRationale)) {
        Write-Invalid 'MODULE_RATIONALE_MISSING' '## Context modules' $id "Selection of '$id' must carry a selection rationale."
    }

    if ((Test-PlaceholderText $sepRationale) -and $script:StatusName -eq 'done') {
        Write-Blocked 'MODULE_SELECTION_UNRESOLVED' '## Context modules' $id "Completed task carries an unresolved rationale placeholder for '$id'."
    }

    if ($selectedIds.Contains($id)) {
        Write-Invalid 'MODULE_DUPLICATE' '## Context modules' $id "Module '$id' is selected more than once."
    }

    $selectedIds.Add($id)
    $selectedVersions.Add($selVer)
    $selectedForJson.Add([pscustomobject]@{ Id = $id; Version = [int]$selVer })
}

if ($selectionCount -eq 0 -and -not $noneSentinelSeen) {
    Write-Invalid 'CONTEXT_SECTION_MISSING' '## Context modules' "" "'## Context modules' records neither a selection nor the 'None selected' sentinel."
}

if ($noneSentinelSeen -and $selectionCount -gt 0) {
    Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' 'None selected' "'None selected' cannot coexist with selected modules."
}

# Minimum-profile floor: only enforced when the task declares a recognized
# profile; unrecognized profiles belong to the task validator's contract.
$pRank = Get-Rank $script:ProfileName
if ($pRank -ge 0) {
    for ($i = 0; $i -lt $selectedIds.Count; $i++) {
        $id = $selectedIds[$i]
        $mf = Join-Path $script:RegistryDir (Join-Path $id 'MODULE.md')
        if (-not (Test-Path -LiteralPath $mf)) { continue }
        $minProfile = Get-HeadingValue (Get-Content -LiteralPath $mf) '## minimum risk profile'
        if ($null -ne $minProfile) { $minProfile = ($minProfile -split '\s+')[0].ToLowerInvariant() }
        $mRank = Get-Rank $minProfile
        if ($mRank -ge 0 -and $pRank -lt $mRank) {
            Write-Invalid 'MODULE_PROFILE_TOO_LOW' '## Context modules' $id "Task profile '$($script:ProfileName)' is below the '$minProfile' minimum required by module '$id'."
        }
    }
}

if ($Format -eq 'Json') {
    Output-ContextJson 'VALID' 0 '' 'MODULE_UNKNOWN' $null $null $selectedForJson
}
else {
    $summary = if ($noneSentinelSeen) { 'none selected' } else { ($selectedIds -join ' ') }
    [Console]::Out.WriteLine("VALID: context selections ok ($summary)")
}
exit 0
