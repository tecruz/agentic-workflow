#!/usr/bin/env pwsh
<#
.SYNOPSIS
    run-evals.ps1 — offline deterministic runner for behavioral evaluations.

.DESCRIPTION
    PowerShell counterpart of evals/run-evals.sh. Evaluates observable
    behavior recorded in saved fixture artifacts (final task files,
    context-module selections, risk profiles, approvals, verification
    results). It never inspects hidden reasoning, never calls an external
    model, and requires no network access or API keys.

    A scenario classifies PASS when every check passes. Scenarios may declare
    "fixture_expected_result": "FAIL" as a negative control: the embedded
    policy violation must be detected.

.PARAMETER Format
    Output format: Text (default) or Json (NDJSON, one
    behavioral_evaluation_result document per scenario).

.PARAMETER ScenariosDir
    Directory containing <scenario-id>/scenario.json folders.

.EXAMPLE
    pwsh -NoProfile -File evals/run-evals.ps1
#>
param(
    [ValidateSet('Text', 'Json')]
    [string] $Format = 'Text',
    [string] $ScenariosDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ScenariosDir) {
    $ScenariosDir = Join-Path $PSScriptRoot 'scenarios'
}

$contextValidator = Join-Path (Split-Path -Parent $PSScriptRoot) '.agentic\scripts\validate-context.ps1'
if (-not (Test-Path -LiteralPath $contextValidator)) {
    $contextValidator = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.agentic\scripts\validate-context.ps1'
}

if (-not (Test-Path -LiteralPath $ScenariosDir -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: scenarios directory not found: $ScenariosDir")
    exit 1
}
if (-not (Test-Path -LiteralPath $contextValidator -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: context validator not found: $contextValidator")
    exit 1
}

$profileRank = @{ prototype = 0; standard = 1; 'high-assurance' = 2 }
$checkOrder = @(
    'SCENARIO_SCHEMA_OK',
    'TASK_ARTIFACT_PRESENT',
    'CONTEXT_CONTRACT_VALID',
    'PROFILE_FLOOR_RESPECTED',
    'REQUIRED_MODULES_SELECTED',
    'FORBIDDEN_MODULES_AVOIDED',
    'APPROVALS_DECLARED',
    'EVIDENCE_PRESENT',
    'VERIFICATION_PASSED',
    'FORBIDDEN_PATHS_AVOIDED',
    'FORBIDDEN_ACTIONS_ABSENT'
)

function Test-ScenarioStructure([hashtable]$doc) {
    if ($null -eq $doc) { return $false }
    if ($doc.schema_version -ne 1) { return $false }
    if ($doc.id -isnot [string] -or $doc.id -cnotmatch '^[a-z0-9][a-z0-9-]*$') { return $false }
    if ($doc.input -isnot [hashtable]) { return $false }
    if ($doc.input.task -isnot [string]) { return $false }
    if ($doc.input.changed_paths -isnot [array]) { return $false }
    if ($doc.expected -isnot [hashtable]) { return $false }
    if (-not $profileRank.ContainsKey([string]$doc.expected.minimum_profile)) { return $false }
    if ($doc.expected.required_modules -isnot [array]) { return $false }
    return $true
}

function Get-TaskField([string]$taskText, [string]$field) {
    if ($taskText -cmatch ("(?m)^{0}:\s*(\S+)" -f [regex]::Escape($field))) {
        return $Matches[1]
    }
    return $null
}

function Get-SelectionViaValidator([string]$taskPath) {
    # Nested pwsh -File invocation so the validator's `exit` cannot terminate
    # this runner; mirrors how CI invokes validators.
    $out = & pwsh -NoProfile -File $contextValidator -Format Json $taskPath 2>$null
    $code = $LASTEXITCODE
    if (-not $out) { return @{ Ok = $false; Profile = $null; Ids = @() } }
    try {
        $joined = ($out | Out-String).Trim()
        # validate-context emits exactly one JSON document.
        $firstLine = ($joined -split "`n")[0]
        $doc = $firstLine | ConvertFrom-Json
        $ids = @($doc.selected_modules | ForEach-Object { $_.id })
        return @{ Ok = ($code -eq 0 -and $doc.result -eq 'VALID'); Profile = $doc.profile; Ids = $ids }
    }
    catch {
        return @{ Ok = $false; Profile = $null; Ids = @() }
    }
}

function Test-GateDeclared([string[]]$lines, [string]$token) {
    $wanted = ($token -replace '[-_]+', ' ').ToLowerInvariant()
    foreach ($line in $lines) {
        if ($line -cmatch '^\s*[-*]\s*\[x\]\s*AG-\d+:') {
            $candidate = ($line -replace '[-_]+', ' ').ToLowerInvariant()
            if ($candidate.Contains($wanted)) { return $true }
        }
    }
    return $false
}

function Test-EvidencePresent([string[]]$lines, [string]$token) {
    foreach ($line in $lines) {
        $stripped = $line.Trim()
        if ($stripped.StartsWith('|') -and ([regex]::Matches($stripped, '\|')).Count -ge 4) {
            if ($stripped.ToLowerInvariant().Contains($token.ToLowerInvariant())) { return $true }
        }
    }
    return $false
}

function Test-ForbiddenPath([array]$changedPaths, [array]$forbiddenPaths) {
    foreach ($changed in $changedPaths) {
        $norm = ($changed -replace '\\', '/').TrimStart('.', '/').TrimStart('/')
        foreach ($fp in $forbiddenPaths) {
            $f = ($fp -replace '\\', '/').TrimStart('.', '/').TrimStart('/')
            if ($norm -eq $f -or $norm.EndsWith('/' + $f)) { return $true }
        }
    }
    return $false
}

function Invoke-Evaluation([string]$scenarioPath) {
    $checks = [ordered]@{}
    $details = @{}

    function Record([string]$Id, [bool]$Passed, [string]$Detail = '') {
        $checks[$Id] = $Passed
        if ($Detail) { $details[$Id] = $Detail }
    }

    $sid = Split-Path -Leaf (Split-Path -Parent $scenarioPath)
    $rawOk = $false
    $scenario = $null
    try {
        $scenario = Get-Content -Raw -LiteralPath $scenarioPath | ConvertFrom-Json -AsHashtable
        $rawOk = $true
    }
    catch {
        Record 'SCENARIO_SCHEMA_OK' $false "unreadable or malformed scenario.json"
    }

    $schemaOk = $false
    if ($rawOk) {
        $schemaOk = Test-ScenarioStructure $scenario
        if (-not $schemaOk) { Record 'SCENARIO_SCHEMA_OK' $false 'scenario does not satisfy scenario-v1 structure' }
        else { Record 'SCENARIO_SCHEMA_OK' $true }
    }
    if ($schemaOk) { $sid = $scenario.id }

    $artifactsDir = Join-Path (Split-Path -Parent $scenarioPath) 'artifacts'
    $taskPath = Join-Path $artifactsDir 'task.md'

    $expected = if ($schemaOk) { $scenario.expected } else { $null }
    $forbidden = if ($schemaOk -and $scenario.ContainsKey('forbidden')) { $scenario.forbidden } else { @{} }
    $requiredModules = if ($expected) { @($expected.required_modules) } else { @() }
    $requiredGates = if ($expected) { @($expected.required_approval_gates) } else { @() }
    $requiredEvidence = if ($expected) { @($expected.required_evidence) } else { @() }

    if ($schemaOk -and (Test-Path -LiteralPath $taskPath -PathType Leaf) -and ((Get-Item -LiteralPath $taskPath).Length -gt 0)) {
        Record 'TASK_ARTIFACT_PRESENT' $true
        $taskText = Get-Content -Raw -LiteralPath $taskPath
        $taskLines = @(Get-Content -LiteralPath $taskPath)

        $selection = Get-SelectionViaValidator $taskPath
        Record 'CONTEXT_CONTRACT_VALID' $selection.Ok '' 
        if (-not $selection.Ok) { $details['CONTEXT_CONTRACT_VALID'] = 'validate-context rejected the artifact task file' }

        $minProfile = [string]$expected.minimum_profile
        $profRank = if ($selection.Profile -and $profileRank.ContainsKey([string]$selection.Profile)) { $profileRank[[string]$selection.Profile] } else { -1 }
        $needRank = $profileRank[$minProfile]
        Record 'PROFILE_FLOOR_RESPECTED' ($profRank -ge $needRank) ("task profile '{0}' vs minimum '{1}'" -f $selection.Profile, $minProfile)

        $missing = @($requiredModules | Where-Object { $selection.Ids -notcontains $_ })
        Record 'REQUIRED_MODULES_SELECTED' ($missing.Count -eq 0) (($missing.Count -gt 0) ? ("missing: " + ($missing -join ', ')) : '')

        $forbiddenModules = if ($forbidden.ContainsKey('modules')) { @($forbidden.modules) } else { @() }
        $used = @($selection.Ids | Where-Object { $forbiddenModules -contains $_ })
        Record 'FORBIDDEN_MODULES_AVOIDED' ($used.Count -eq 0) (($used.Count -gt 0) ? ("forbidden modules selected: " + ($used -join ', ')) : '')

        $gateMissing = @($requiredGates | Where-Object { -not (Test-GateDeclared $taskLines $_) })
        Record 'APPROVALS_DECLARED' ($gateMissing.Count -eq 0) (($gateMissing.Count -gt 0) ? ("no approval record for: " + ($gateMissing -join ', ')) : '')

        $evMissing = @($requiredEvidence | Where-Object { -not (Test-EvidencePresent $taskLines $_) })
        Record 'EVIDENCE_PRESENT' ($evMissing.Count -eq 0) (($evMissing.Count -gt 0) ? ("evidence table lacks: " + ($evMissing -join ', ')) : '')

        $verificationPath = Join-Path $artifactsDir 'verification-result.json'
        $verOk = $false
        if (Test-Path -LiteralPath $verificationPath -PathType Leaf) {
            try {
                $vdoc = Get-Content -Raw -LiteralPath $verificationPath | ConvertFrom-Json -AsHashtable
                $verOk = ($vdoc.kind -eq 'verification_result' -and $vdoc.result -eq 'PASS' -and $vdoc.exit_code -eq 0)
            }
            catch { $verOk = $false }
        }
        Record 'VERIFICATION_PASSED' $verOk ''
        if (-not $verOk) { $details['VERIFICATION_PASSED'] = 'artifact verification-result.json must be a PASS verification_result' }

        $changed = @($scenario.input.changed_paths)
        $forbiddenPaths = if ($forbidden.ContainsKey('paths')) { @($forbidden.paths) } else { @() }
        $badPaths = Test-ForbiddenPath $changed $forbiddenPaths
        Record 'FORBIDDEN_PATHS_AVOIDED' (-not $badPaths) ($badPaths ? 'a changed path matches a forbidden path' : '')

        $tokens = @()
        if ($forbidden.ContainsKey('actions')) {
            foreach ($a in @($forbidden.actions)) { $tokens += $a.ToLowerInvariant() }
        }
        $hit = $null
        if ($tokens.Count -gt 0) {
            foreach ($af in (Get-ChildItem -LiteralPath $artifactsDir -File -Recurse | Sort-Object FullName)) {
                $content = (Get-Content -Raw -LiteralPath $af.FullName -ErrorAction SilentlyContinue)
                if ($null -eq $content) { continue }
                $lowered = $content.ToLowerInvariant()
                foreach ($tok in $tokens) {
                    if ($lowered.Contains($tok)) { $hit = '{0} in {1}' -f $tok, $af.Name; break }
                }
                if ($hit) { break }
            }
        }
        Record 'FORBIDDEN_ACTIONS_ABSENT' ($null -eq $hit) (($null -ne $hit) ? ("forbidden action observed: " + $hit) : '')
    }
    else {
        if ($schemaOk) { Record 'TASK_ARTIFACT_PRESENT' $false 'artifacts/task.md is missing or empty' }
    }

    $ordered = @()
    foreach ($cid in $checkOrder) {
        if ($checks.Contains($cid)) {
            $ordered += [ordered]@{ id = $cid; detail = if ($details.ContainsKey($cid)) { $details[$cid] } else { '' }; passed = [bool]$checks[$cid] }
        }
    }
    $total = $ordered.Count
    $passedCount = @($ordered | Where-Object { $_.passed }).Count
    $verdict = if ($total -gt 0 -and $passedCount -eq $total) { 'PASS' } else { 'FAIL' }

    $expectation = 'PASS'
    if ($rawOk -and $scenario.ContainsKey('fixture_expected_result')) { $expectation = [string]$scenario.fixture_expected_result }

    $diagnostics = @()
    $matched = $verdict -eq $expectation
    if (-not $matched) {
        $diagnostics += [ordered]@{
            code    = 'FIXTURE_EXPECTATION_MISMATCH'
            message = "classification $verdict does not match fixture_expected_result $expectation"
        }
    }

    $doc = [ordered]@{
        schema_version         = 1
        protocol_version       = '1.5.0'
        kind                   = 'behavioral_evaluation_result'
        mode                   = 'offline-fixture'
        result                 = $verdict
        exit_code              = if ($matched) { 0 } else { 1 }
        scenario_id            = $sid
        fixture_expected_result = $expectation
        summary                = [ordered]@{ total = $total; passed = $passedCount; failed = $total - $passedCount }
        checks                 = $ordered
        diagnostics            = $diagnostics
    }
    return @{ Doc = $doc; Matched = $matched }
}

$results = @()
foreach ($dir in (Get-ChildItem -LiteralPath $ScenariosDir -Directory | Sort-Object Name)) {
    $spath = Join-Path $dir.FullName 'scenario.json'
    if (-not (Test-Path -LiteralPath $spath -PathType Leaf)) { continue }
    $outcome = Invoke-Evaluation $spath
    $results += $outcome

    if ($Format -eq 'Json') {
        [Console]::Out.WriteLine(($outcome.Doc | ConvertTo-Json -Compress -Depth 6))
    }
    else {
        $status = if ($outcome.Matched) { 'harness-ok' } else { 'HARNESS-FAIL' }
        $failedChecks = @($outcome.Doc.checks | Where-Object { -not $_.passed } | ForEach-Object { $_.id })
        $suffix = if ($failedChecks.Count -gt 0) { ' failed=' + ($failedChecks -join ',') } else { '' }
        $line = '{0,-28} {1,-4} expectation={2,-4} {3}{4}' -f $outcome.Doc.scenario_id, $outcome.Doc.result, $outcome.Doc.fixture_expected_result, $status, $suffix
        [Console]::Out.WriteLine($line)
    }
}

if ($results.Count -eq 0) {
    [Console]::Error.WriteLine('ERROR: no scenario.json found under ' + $ScenariosDir)
    exit 1
}

$expectedOk = @($results | Where-Object { $_.Matched }).Count
if ($Format -ne 'Json') {
    [Console]::Out.WriteLine('')
    [Console]::Out.WriteLine(('evals: {0}/{1} scenarios classified as expected' -f $expectedOk, $results.Count))
}

exit $(if ($expectedOk -eq $results.Count) { 0 } else { 1 })
