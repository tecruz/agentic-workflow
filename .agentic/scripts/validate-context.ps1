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

    The registry itself is validated before use: a module's declared ID must
    match `^[a-z0-9][a-z0-9-]*$`, must equal its directory name, must be
    unique, must declare a positive-integer Version and a recognized Minimum
    risk profile, must not repeat any required heading, and must carry
    substantive content under every required documentation section. A violating
    registry is rejected wholesale as unusable (BLOCKED), so task-provided text
    can never influence filesystem paths.

    JSON output redacts the task path exactly like the Bash validator:
    project-relative when inside the project, basename when outside.

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
$script:ProfileCount = 0
$script:StatusName = $null
$script:SectionFound = $false
$script:SectionLines = [System.Collections.Generic.List[string]]::new()

# Platform-aware path comparison: case-insensitive on Windows, ordinal on
# Unix — mirroring the installers and the Bash validator's byte-exact match.
$script:PathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}

function Get-DisplayPath {
    # Redacted display form of the task file path for JSON output: passed
    # through when already relative, made project-relative when it lives under
    # the working directory, degraded to its basename otherwise, so an
    # absolute user-home path can never leak into machine-readable results.
    param([string]$Path)
    $norm = $Path.Replace('\', '/')
    if ($norm.StartsWith('./')) { $norm = $norm.Substring(2) }
    $cwd = (Get-Location).ProviderPath.Replace('\', '/').TrimEnd('/')
    if ($norm -eq $cwd) { return '.' }
    if ($norm.StartsWith($cwd + '/', $script:PathComparison)) {
        return './' + $norm.Substring($cwd.Length + 1)
    }
    if ($norm -match '^[A-Za-z]:/' -or $norm.StartsWith('/')) {
        return [System.IO.Path]::GetFileName($norm)
    }
    return $norm
}

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
        protocol_version = "1.7.0"
        kind             = "context_validation_result"
        mode             = if ($Handoff) { "handoff" } else { "standard" }
        result           = $Result
        exit_code        = $ExitCode
        task_file        = Get-DisplayPath $TaskFile
        profile          = $ProfileOut
        selected_modules = $selectedOut
        diagnostics      = $diagList
    }
    [Console]::Out.WriteLine(($resultObject | ConvertTo-Json -Compress -Depth 4))
}

function Write-Invalid {
    param([string]$Code, [string]$Section, [string]$Identifier, [string]$Message)
    if ($Format -eq 'Json') {
        # JSON mode: use neutral identifier and generic message to avoid leaking task content
        $jsonIdent = $null
        $jsonMsg = switch ($Code) {
            'CONTEXT_SECTION_MISSING' { "Task file is missing the required '## Context modules' section." }
            'CONTEXT_PROFILE_INVALID' { "Task must declare exactly one recognized risk profile." }
            'MODULE_UNKNOWN' { "Selected module is not in the managed registry." }
            'MODULE_VERSION_UNSUPPORTED' { "Selection declares an unsupported module version." }
            'MODULE_RATIONALE_MISSING' { "Selection must carry a selection rationale." }
            'MODULE_DUPLICATE' { "Module is selected more than once." }
            'MODULE_PROFILE_TOO_LOW' { "Task profile is below the minimum required by the selected module." }
            'MODULE_SELECTION_UNRESOLVED' { "Module selection does not match the required structure." }
            default { "Structural contract violation." }
        }
        Output-ContextJson 'INVALID' 1 $jsonMsg $Code $Section $jsonIdent
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
        # JSON mode: use neutral identifier and generic message
        $jsonIdent = $null
        $jsonMsg = switch ($Code) {
            'CONTEXT_REGISTRY_MISSING' { "Context module registry not found." }
            'CONTEXT_REGISTRY_INVALID' { "Context module registry is unusable." }
            'MODULE_SELECTION_UNRESOLVED' { "Completed task carries an unresolved selection placeholder." }
            default { "Completion gate not satisfied." }
        }
        Output-ContextJson 'BLOCKED' 2 $jsonMsg $Code $Section $jsonIdent
        exit 2
    }
    else {
        [Console]::Error.WriteLine("BLOCKED: $Message")
        exit 2
    }
}

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    if ($Format -eq 'Json') {
        Write-Invalid 'CONTEXT_SECTION_MISSING' '' '' "Task file was not found: $(Get-DisplayPath $TaskFile)"
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
    if ($trimmed -match '^(\[.*\]|<.*>)$' -and $trimmed.Length -ge 2) { return $true }
    $n = (($trimmed -replace '^\s*[-*+]\s+', '').Trim() -replace '\s*[.!?;:,-]+$', '').ToLowerInvariant()
    if (-not $n) { return $true }
    if ($n -in @('tbd', 'todo', 'pending', 'placeholder', 'tbc', 'none', 'n/a')) { return $true }
    if ($n -match 'tbd|todo|pending') { return $true }
    return $false
}

# ---------------------------------------------------------------------------
# Registry validation. Every module becomes one structured record carrying its
# directory name, declared ID, Version, and Minimum risk profile. A registry
# that violates any identity or metadata rule is rejected whole
# (CONTEXT_REGISTRY_INVALID, BLOCKED); task-provided IDs are only ever matched
# against validated records and never used to build filesystem paths.
# ---------------------------------------------------------------------------
$script:RegistryRecords = [System.Collections.Generic.List[object]]::new()

function Get-HeadingStats {
    # Returns an ordered hashtable heading-lower-name -> @{ Count; First; HasContent }
    param([string[]]$ContentLines)
    $required = @(
        'id', 'version', 'minimum risk profile',
        'load when', 'required context', 'approval gates',
        'required evidence', 'prohibited shortcuts'
    )
    $stats = [ordered]@{}
    foreach ($h in $required) {
        $stats[$h] = @{ Count = 0; First = $null; HasContent = $false }
    }
    $current = $null
    foreach ($line in $ContentLines) {
        $norm = $line.TrimEnd().ToLowerInvariant()
        if ($norm -match '^##\s+(.+?)\s*$') {
            $heading = $Matches[1]
            if ($stats.Contains($heading)) {
                $stats[$heading].Count++
                $current = $heading
            }
            else {
                $current = $null
            }
            continue
        }
        if ($null -ne $current -and -not [string]::IsNullOrWhiteSpace($line)) {
            if ($null -eq $stats[$current].First) { $stats[$current].First = $line.Trim() }
            if (-not $stats[$current].HasContent -and (Test-MeaningfulChar $line) -and -not (Test-PlaceholderText $line)) {
                $stats[$current].HasContent = $true
            }
        }
    }
    return $stats
}

if (-not (Test-Path -LiteralPath $script:RegistryDir -PathType Container)) {
    Write-Blocked 'CONTEXT_REGISTRY_MISSING' '' '' "Context module registry not found: $(Split-Path -Leaf $script:RegistryDir)"
}

foreach ($dir in (Get-ChildItem -LiteralPath $script:RegistryDir -Directory | Sort-Object Name)) {
    $mf = Join-Path $dir.FullName 'MODULE.md'
    if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) { continue }

    $stats = Get-HeadingStats (Get-Content -LiteralPath $mf)

    foreach ($heading in $stats.Keys) {
        if ($stats[$heading].Count -eq 0) {
            Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module '$($dir.Name)' is missing its '$heading' section."
        }
        elseif ($stats[$heading].Count -gt 1) {
            Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module '$($dir.Name)' declares heading '$heading' more than once."
        }
    }

    $id = $stats['id'].First
    $ver = $stats['version'].First
    $minRaw = $stats['minimum risk profile'].First

    if ([string]::IsNullOrWhiteSpace($id) -or $id -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
        Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module '$($dir.Name)' declares ID '$id', which does not match ^[a-z0-9][a-z0-9-]*`$. "
    }
    if (-not [System.StringComparer]::Ordinal.Equals($id, $dir.Name)) {
        Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module '$($dir.Name)' declares ID '$id' that differs from its directory name."
    }
    $duplicate = $script:RegistryRecords | Where-Object { [System.StringComparer]::Ordinal.Equals($_.Id, $id) }
    if ($duplicate) {
        Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module ID '$id' is declared more than once."
    }
    if ([string]::IsNullOrWhiteSpace($ver) -or $ver -cnotmatch '^[1-9][0-9]*$') {
        Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module '$($dir.Name)' declares an unsupported Version ('$ver')."
    }
    $minProfile = if ($minRaw) { ($minRaw -split '\s+')[0].ToLowerInvariant() } else { $null }
    if ($minProfile -notin @('prototype', 'standard', 'high-assurance')) {
        Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module '$($dir.Name)' declares missing or unrecognized Minimum risk profile ('$minProfile')."
    }
    foreach ($docSection in @('load when', 'required context', 'approval gates', 'required evidence', 'prohibited shortcuts')) {
        if (-not $stats[$docSection].HasContent) {
            Write-Blocked 'CONTEXT_REGISTRY_INVALID' 'registry' $dir.Name "Context module registry is unusable: module '$($dir.Name)' is missing substantive content under '$docSection'."
        }
    }

    $script:RegistryRecords.Add([pscustomobject]@{
            DirectoryName = $dir.Name
            Id            = $id
            Version       = $ver
            MinProfile    = $minProfile
            Path          = $mf
        })
}

function Get-RegistryRecord([string]$Id) {
    foreach ($record in $script:RegistryRecords) {
        if ([System.StringComparer]::Ordinal.Equals($record.Id, $Id)) { return $record }
    }
    return $null
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
        if ($line -cmatch '^```') { $inFence = $false }
        continue
    }
    if ($line -cmatch '^```') { $inFence = $true; continue }
    if ($inComment) {
        if ($line -match '-->') { $inComment = $false }
        continue
    }
    if ($line -match '<!--') {
        if ($line -notmatch '-->') { $inComment = $true }
        continue
    }
    if ($line -cmatch '^>') { continue }

    # Heading and declaration comparisons are case-insensitive, mirroring the
    # Bash validator's lowercased-line matching.
    $norm = $line.ToLowerInvariant().TrimEnd()
    if ($norm -match '^profile:\s*(\S+)') {
        $script:ProfileCount++
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

# The minimum-profile floor is part of this validator's contract, so it can
# only be evaluated against exactly one recognized profile declaration. A
# missing, unknown, or duplicated profile is INVALID before any selection is
# examined — JSON results are never VALID with a null profile.
if ($script:ProfileCount -ne 1) {
    Write-Invalid 'CONTEXT_PROFILE_INVALID' '## Risk profile' '' "Task must declare exactly one risk profile (found $($script:ProfileCount) declarations)."
}
if ($script:ProfileName -notin @('prototype', 'standard', 'high-assurance')) {
    Write-Invalid 'CONTEXT_PROFILE_INVALID' '## Risk profile' $script:ProfileName "'$($script:ProfileName)' is not a recognized risk profile (prototype | standard | high-assurance)."
}

# Selection state.
$selectionCount = 0
$noneSentinelSeen = $false
$selectedIds = [System.Collections.Generic.List[string]]::new()
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
    $entry = ($rawLine -creplace '^\s*[-*+]\s+', '').Trim()
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }

    # Sentinel: '- None selected' optionally followed by '— <why>'. Mirrors the
    # Bash validator byte for byte: 'selected' must be followed by end-of-line
    # or whitespace ('selectedness' and 'selected-but-not-really' are malformed
    # sentinels, not selections), and any suffix must be whitespace, one
    # separator (— / – / -), whitespace, then a substantive rationale.
    # Placeholder suffixes (TBD/TODO/Pending/...) block a completed task.
    if ($entry -imatch '^none\s+selected') {
        if ($entry -notmatch '^none\s+selected($|\s+)') {
            Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' $entry "'None selected' must be followed by end-of-line or a separator ( — / – / - ) with surrounding whitespace: $entry"
        }
        $noneSentinelSeen = $true
        $suffix = $entry -creplace '^[Nn][Oo][Nn][Ee]\s+[Ss][Ee][Ll][Ee][Cc][Tt][Ee][Dd]', ''
        if (-not [string]::IsNullOrWhiteSpace($suffix)) {
            $afterLeadingWs = $suffix -replace '^\s+', ''
            if ($afterLeadingWs.Length -eq $suffix.Length) {
                Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' 'None selected' "'None selected' must use a separator ( — / – / - ) with surrounding whitespace before rationale: $entry"
            }
            $sep = $null
            foreach ($s in @([string][char]0x2014, [string][char]0x2013, [string]'-')) {
                if ($afterLeadingWs.StartsWith($s)) { $sep = $s; break }
            }
            if ($null -eq $sep) {
                Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' 'None selected' "'None selected' must use a separator ( — / – / - ) with surrounding whitespace before rationale: $entry"
            }
            $afterSep = $afterLeadingWs.Substring($sep.Length)
            $rationale = $afterSep -replace '^\s+', ''
            if ($rationale.Length -eq $afterSep.Length) {
                Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' 'None selected' "'None selected' carries a separator but no rationale."
            }
            if (-not (Test-MeaningfulChar $rationale)) {
                Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' 'None selected' "'None selected' carries a separator but no rationale."
            }
            if ((Test-PlaceholderText $rationale) -and $script:StatusName -eq 'done') {
                Write-Blocked 'MODULE_SELECTION_UNRESOLVED' '## Context modules' 'None selected' "Completed task carries an unresolved 'None selected' rationale placeholder."
            }
        }
        continue
    }

    $selectionCount++
    $tokens = $entry -split '\s+'
    $id = if ($tokens.Count -gt 0) { $tokens[0] } else { '' }
    $verToken = if ($tokens.Count -gt 1) { $tokens[1] } else { '' }
    $loadedToken = if ($tokens.Count -gt 2) { $tokens[2] } else { '' }
    $rest = if ($tokens.Count -gt 3) { ($tokens[3..($tokens.Count - 1)] -join ' ') } else { '' }

    # Canonical grammar (ADR-0010): <id> v<N> loaded — <rationale>
    # Requires id, version, lowercase 'loaded', separator and rationale.
    if ($entry -cnotmatch '^\S+\s+v[1-9][0-9]*\s+loaded\s+[—–-]\s+\S') {
        Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' $entry "Selection entry is not in the canonical form '<module-id> v<N> loaded — <rationale>': $entry"
    }

    $sepRationale = ($rest -creplace '^[—–-]\s*', '')

    if ($loadedToken -cne 'loaded') {
        Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' $id "Selection of '$id' does not confirm the module was loaded before planning."
    }

    $record = Get-RegistryRecord $id
    if ($null -eq $record) {
        Write-Invalid 'MODULE_UNKNOWN' '## Context modules' $id "Selected module '$id' is not in the managed registry."
    }

    $selVer = $verToken -creplace '^v', ''
    if (-not [System.StringComparer]::Ordinal.Equals($selVer, $record.Version)) {
        Write-Invalid 'MODULE_VERSION_UNSUPPORTED' '## Context modules' $id "Selection of '$id' declares version '$selVer' but the registry provides '$($record.Version)'."
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
    $selectedForJson.Add([pscustomobject]@{ Id = $id; Version = [int]$selVer })
}

if ($selectionCount -eq 0 -and -not $noneSentinelSeen) {
    Write-Invalid 'CONTEXT_SECTION_MISSING' '## Context modules' "" "'## Context modules' records neither a selection nor the 'None selected' sentinel."
}

if ($noneSentinelSeen -and $selectionCount -gt 0) {
    Write-Invalid 'MODULE_SELECTION_UNRESOLVED' '## Context modules' 'None selected' "'None selected' cannot coexist with selected modules."
}

# Minimum-profile floor: uses the pre-validated registry record's declared
# minimum; the floor lookup never reconstructs paths from task-provided text.
$pRank = Get-Rank $script:ProfileName
if ($pRank -ge 0) {
    foreach ($id in $selectedIds) {
        $record = Get-RegistryRecord $id
        if ($null -eq $record) { continue }
        $mRank = Get-Rank $record.MinProfile
        if ($mRank -ge 0 -and $pRank -lt $mRank) {
            Write-Invalid 'MODULE_PROFILE_TOO_LOW' '## Context modules' $id "Task profile '$($script:ProfileName)' is below the '$($record.MinProfile)' minimum required by module '$id'."
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
