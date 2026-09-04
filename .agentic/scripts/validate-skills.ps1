#Requires -Version 7.0
<#
.SYNOPSIS
    validate-skills.ps1 — structural validator for skill invocations.

.DESCRIPTION
    Validates only structural facts about the `## Skills` section of a
    task file against the managed registry under `.agentic/skills/`:

      - every invoked skill exists in the registry
      - no duplicate skill IDs
      - every invocation carries a real rationale
      - the task's risk profile satisfies each skill's minimum profile
      - a completed task has no unresolved invocation placeholders
      - the `None required` sentinel never coexists with invocations
      - invocation versions are recognized by the registry

    The registry itself is validated before use: a skill's declared ID must
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
    pwsh -NoProfile -File validate-skills.ps1 .agentic/tasks/TASK-001.md
#>
param(
    [switch]$Handoff,
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TaskFile,
    [ValidateSet('Text', 'Json')]
    [string] $Format = 'Text'
)

$ErrorActionPreference = 'Stop'

$script:RegistryDir = if ($env:AGENTIC_SKILLS_REGISTRY) {
    $env:AGENTIC_SKILLS_REGISTRY
}
else {
    Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'
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

function Output-SkillJson {
    param(
        [string]$Result,
        [int]$ExitCode,
        [string]$Message,
        [string]$Code = 'SKILL_UNKNOWN',
        [string]$Section = $null,
        [string]$Identifier = $null,
        [array]$InvokedSkills = @()
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

    $invokedOut = @()
    foreach ($m in $InvokedSkills) {
        $invokedOut += [ordered]@{ id = $m.Id; version = [int]$m.Version }
    }

    $resultObject = [ordered]@{
        schema_version   = 1
        protocol_version = "1.10.0"
        kind             = "skill_validation_result"
        mode             = if ($Handoff) { "handoff" } else { "standard" }
        result           = $Result
        exit_code        = $ExitCode
        task_file        = Get-DisplayPath $TaskFile
        profile          = $ProfileOut
        invoked_skills = $invokedOut
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
            'SKILLS_SECTION_MISSING' { "Task file is missing the required '## Skills' section." }
            'SKILLS_PROFILE_INVALID' { "Task must declare exactly one recognized risk profile." }
            'SKILL_UNKNOWN' { "Invoked skill is not in the managed registry." }
            'SKILL_VERSION_UNSUPPORTED' { "Invocation declares an unsupported skill version." }
            'SKILL_RATIONALE_MISSING' { "Invocation must carry an invocation rationale." }
            'SKILL_DUPLICATE' { "Skill is invoked more than once." }
            'SKILL_PROFILE_TOO_LOW' { "Task profile is below the minimum required by the invoked skill." }
            'SKILL_SELECTION_UNRESOLVED' { "Skill invocation does not match the required structure." }
            default { "Structural contract violation." }
        }
        Output-SkillJson 'INVALID' 1 $jsonMsg $Code $Section $jsonIdent
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
            'SKILLS_REGISTRY_MISSING' { "Skills registry not found." }
            'SKILLS_REGISTRY_INVALID' { "Skills registry is unusable." }
            'SKILL_SELECTION_UNRESOLVED' { "Completed task carries an unresolved invocation placeholder." }
            default { "Completion gate not satisfied." }
        }
        Output-SkillJson 'BLOCKED' 2 $jsonMsg $Code $Section $jsonIdent
        exit 2
    }
    else {
        [Console]::Error.WriteLine("BLOCKED: $Message")
        exit 2
    }
}

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    if ($Format -eq 'Json') {
        Write-Invalid 'SKILLS_SECTION_MISSING' '' '' "Task file was not found: $(Get-DisplayPath $TaskFile)"
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
# Registry validation. Every skill becomes one structured record carrying its
# directory name, declared ID, Version, and Minimum risk profile. A registry
# that violates any identity or metadata rule is rejected whole
# (SKILLS_REGISTRY_INVALID, BLOCKED); task-provided IDs are only ever matched
# against validated records and never used to build filesystem paths.
# ---------------------------------------------------------------------------
$script:RegistryRecords = [System.Collections.Generic.List[object]]::new()

function Get-HeadingStats {
    # Returns an ordered hashtable heading-lower-name -> @{ Count; First; HasContent }
    param([string[]]$ContentLines)
    $required = @(
        'id', 'version', 'minimum risk profile',
        'invoked when', 'required context', 'approval gates',
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
    Write-Blocked 'SKILLS_REGISTRY_MISSING' '' '' "Skills registry not found: $(Split-Path -Leaf $script:RegistryDir)"
}

foreach ($dir in (Get-ChildItem -LiteralPath $script:RegistryDir -Directory | Sort-Object Name)) {
    $mf = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) { continue }

    $stats = Get-HeadingStats (Get-Content -LiteralPath $mf)

    foreach ($heading in $stats.Keys) {
        if ($stats[$heading].Count -eq 0) {
            Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill '$($dir.Name)' is missing its '$heading' section."
        }
        elseif ($stats[$heading].Count -gt 1) {
            Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill '$($dir.Name)' declares heading '$heading' more than once."
        }
    }

    $id = $stats['id'].First
    $ver = $stats['version'].First
    $minRaw = $stats['minimum risk profile'].First

    if ([string]::IsNullOrWhiteSpace($id) -or $id -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
        Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill '$($dir.Name)' declares ID '$id', which does not match ^[a-z0-9][a-z0-9-]*`$. "
    }
    if (-not [System.StringComparer]::Ordinal.Equals($id, $dir.Name)) {
        Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill '$($dir.Name)' declares ID '$id' that differs from its directory name."
    }
    $duplicate = $script:RegistryRecords | Where-Object { [System.StringComparer]::Ordinal.Equals($_.Id, $id) }
    if ($duplicate) {
        Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill ID '$id' is declared more than once."
    }
    if ([string]::IsNullOrWhiteSpace($ver) -or $ver -cnotmatch '^[1-9][0-9]*$') {
        Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill '$($dir.Name)' declares an unsupported Version ('$ver')."
    }
    $minProfile = if ($minRaw) { ($minRaw -split '\s+')[0].ToLowerInvariant() } else { $null }
    if ($minProfile -notin @('prototype', 'standard', 'high-assurance')) {
        Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill '$($dir.Name)' declares missing or unrecognized Minimum risk profile ('$minProfile')."
    }
    foreach ($docSection in @('invoked when', 'required context', 'approval gates', 'required evidence', 'prohibited shortcuts')) {
        if (-not $stats[$docSection].HasContent) {
            Write-Blocked 'SKILLS_REGISTRY_INVALID' 'registry' $dir.Name "Skills registry is unusable: skill '$($dir.Name)' is missing substantive content under '$docSection'."
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
# and the raw body of `## Skills` until the next `##` heading.
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
        if ($norm -eq '## skills') {
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
    Write-Invalid 'SKILLS_SECTION_MISSING' '## Status' '' "--handoff requires 'Status: done'; found '$($script:StatusName ?? '<none>')'."
}

if (-not $script:SectionFound) {
    Write-Invalid 'SKILLS_SECTION_MISSING' '## Skills' '' "Task file has no '## Skills' section."
}

# The minimum-profile floor is part of this validator's contract, so it can
# only be evaluated against exactly one recognized profile declaration. A
# missing, unknown, or duplicated profile is INVALID before any selection is
# examined — JSON results are never VALID with a null profile.
if ($script:ProfileCount -ne 1) {
    Write-Invalid 'SKILLS_PROFILE_INVALID' '## Risk profile' '' "Task must declare exactly one risk profile (found $($script:ProfileCount) declarations)."
}
if ($script:ProfileName -notin @('prototype', 'standard', 'high-assurance')) {
    Write-Invalid 'SKILLS_PROFILE_INVALID' '## Risk profile' $script:ProfileName "'$($script:ProfileName)' is not a recognized risk profile (prototype | standard | high-assurance)."
}

# Invocation state.
$invocationCount = 0
$noneSentinelSeen = $false
$invokedIds = [System.Collections.Generic.List[string]]::new()
$invokedForJson = [System.Collections.Generic.List[object]]::new()

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

    # Sentinel: '- None required' optionally followed by '— <why>'. Mirrors the
    # Bash validator byte for byte: 'required' must be followed by end-of-line
    # or whitespace ('requiredness' and 'required-but-not-really' are malformed
    # sentinels, not invocations), and any suffix must be whitespace, one
    # separator (— / – / -), whitespace, then a substantive rationale.
    # Placeholder suffixes (TBD/TODO/Pending/...) block a completed task.
    if ($entry -imatch '^none\s+required') {
        if ($entry -notmatch '^none\s+required($|\s+)') {
            Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' $entry "'None required' must be followed by end-of-line or a separator ( — / – / - ) with surrounding whitespace: $entry"
        }
        $noneSentinelSeen = $true
        $suffix = $entry -creplace '^[Nn][Oo][Nn][Ee]\s+[Rr][Ee][Qq][Uu][Ii][Rr][Ee][Dd]', ''
        if (-not [string]::IsNullOrWhiteSpace($suffix)) {
            $afterLeadingWs = $suffix -replace '^\s+', ''
            if ($afterLeadingWs.Length -eq $suffix.Length) {
                Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' 'None required' "'None required' must use a separator ( — / – / - ) with surrounding whitespace before rationale: $entry"
            }
            $sep = $null
            foreach ($s in @([string][char]0x2014, [string][char]0x2013, [string]'-')) {
                if ($afterLeadingWs.StartsWith($s)) { $sep = $s; break }
            }
            if ($null -eq $sep) {
                Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' 'None required' "'None required' must use a separator ( — / – / - ) with surrounding whitespace before rationale: $entry"
            }
            $afterSep = $afterLeadingWs.Substring($sep.Length)
            $rationale = $afterSep -replace '^\s+', ''
            if ($rationale.Length -eq $afterSep.Length) {
                Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' 'None required' "'None required' carries a separator but no rationale."
            }
            if (-not (Test-MeaningfulChar $rationale)) {
                Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' 'None required' "'None required' carries a separator but no rationale."
            }
            if ((Test-PlaceholderText $rationale) -and $script:StatusName -eq 'done') {
                Write-Blocked 'SKILL_SELECTION_UNRESOLVED' '## Skills' 'None required' "Completed task carries an unresolved 'None required' rationale placeholder."
            }
        }
        continue
    }

    $invocationCount++
    $tokens = $entry -split '\s+'
    $id = if ($tokens.Count -gt 0) { $tokens[0] } else { '' }
    $verToken = if ($tokens.Count -gt 1) { $tokens[1] } else { '' }
    $invokedToken = if ($tokens.Count -gt 2) { $tokens[2] } else { '' }
    $rest = if ($tokens.Count -gt 3) { ($tokens[3..($tokens.Count - 1)] -join ' ') } else { '' }

    # Canonical grammar (ADR-0014): <id> v<N> invoked — <rationale>
    # Requires id, version, lowercase 'invoked', separator and rationale.
    if ($entry -cnotmatch '^\S+\s+v[1-9][0-9]*\s+invoked\s+[—–-]\s+\S') {
        Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' $entry "Invocation entry is not in the canonical form '<skill-id> v<N> invoked — <rationale>': $entry"
    }

    $sepRationale = ($rest -creplace '^[—–-]\s*', '')

    if ($invokedToken -cne 'invoked') {
        Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' $id "Invocation of '$id' does not confirm the skill was invoked for this task."
    }

    $record = Get-RegistryRecord $id
    if ($null -eq $record) {
        Write-Invalid 'SKILL_UNKNOWN' '## Skills' $id "Invoked skill '$id' is not in the managed registry."
    }

    $skillVer = $verToken -creplace '^v', ''
    if (-not [System.StringComparer]::Ordinal.Equals($skillVer, $record.Version)) {
        Write-Invalid 'SKILL_VERSION_UNSUPPORTED' '## Skills' $id "Invocation of '$id' declares version '$skillVer' but the registry provides '$($record.Version)'."
    }

    if (-not (Test-MeaningfulChar $sepRationale)) {
        Write-Invalid 'SKILL_RATIONALE_MISSING' '## Skills' $id "Invocation of '$id' must carry an invocation rationale."
    }

    if ((Test-PlaceholderText $sepRationale) -and $script:StatusName -eq 'done') {
        Write-Blocked 'SKILL_SELECTION_UNRESOLVED' '## Skills' $id "Completed task carries an unresolved rationale placeholder for '$id'."
    }

    if ($invokedIds.Contains($id)) {
        Write-Invalid 'SKILL_DUPLICATE' '## Skills' $id "Skill '$id' is invoked more than once."
    }

    $invokedIds.Add($id)
    $invokedForJson.Add([pscustomobject]@{ Id = $id; Version = [int]$skillVer })
}

if ($invocationCount -eq 0 -and -not $noneSentinelSeen) {
    Write-Invalid 'SKILLS_SECTION_MISSING' '## Skills' "" "'## Skills' records neither an invocation nor the 'None required' sentinel."
}

if ($noneSentinelSeen -and $invocationCount -gt 0) {
    Write-Invalid 'SKILL_SELECTION_UNRESOLVED' '## Skills' 'None required' "'None required' cannot coexist with invoked skills."
}

# Minimum-profile floor: uses the pre-validated registry record's declared
# minimum; the floor lookup never reconstructs paths from task-provided text.
$pRank = Get-Rank $script:ProfileName
if ($pRank -ge 0) {
    foreach ($id in $invokedIds) {
        $record = Get-RegistryRecord $id
        if ($null -eq $record) { continue }
        $mRank = Get-Rank $record.MinProfile
        if ($mRank -ge 0 -and $pRank -lt $mRank) {
            Write-Invalid 'SKILL_PROFILE_TOO_LOW' '## Skills' $id "Task profile '$($script:ProfileName)' is below the '$($record.MinProfile)' minimum required by skill '$id'."
        }
    }
}

if ($Format -eq 'Json') {
    Output-SkillJson 'VALID' 0 '' 'SKILL_UNKNOWN' $null $null $invokedForJson
}
else {
    $summary = if ($noneSentinelSeen) { 'none required' } else { ($invokedIds -join ' ') }
    [Console]::Out.WriteLine("VALID: skill invocations ok ($summary)")
}
exit 0
