#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    run-evals.ps1 — offline deterministic runner for behavioral evaluations.

.DESCRIPTION
    PowerShell counterpart of evals/run-evals.sh. Evaluates observable
    behavior recorded in saved fixture artifacts by running the REAL
    production contracts against them:

      - scenario.json            validated against evals/schemas/scenario-v1.schema.json
      - artifacts/task.md        validated by validate-task -Handoff and
                                 validate-context -Handoff (the actual gates)
      - verification-result.json validated against the managed
                                 verification-result-v1.schema.json, including
                                 summary/checks-array agreement
      - approvals/evidence parsed ONLY from authoritative sections (fenced
        code, HTML comments, and blockquotes ignored)

    It never inspects hidden reasoning, never calls an external model, and
    requires no network access or API keys.

    Every emitted behavioral_evaluation_result document carries the three-way
    split required by evaluation-result-v1.schema.json (observed_result /
    expected_result / expectation_matched / result / exit_code) and is
    validated against that managed schema before it may be emitted; a
    document that violates its own schema aborts the run.

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

$repoRoot = Split-Path -Parent $PSScriptRoot
$taskValidator = Join-Path $repoRoot '.agentic\scripts\validate-task.ps1'
$contextValidator = Join-Path $repoRoot '.agentic\scripts\validate-context.ps1'
$scenarioSchemaPath = Join-Path $PSScriptRoot 'schemas\scenario-v1.schema.json'
$resultSchemaPath = Join-Path $PSScriptRoot 'schemas\evaluation-result-v1.schema.json'
$verificationSchemaPath = Join-Path $repoRoot '.agentic\schemas\verification-result-v1.schema.json'

if (-not (Test-Path -LiteralPath $ScenariosDir -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: scenarios directory not found: $ScenariosDir")
    exit 1
}
foreach ($dep in @($taskValidator, $contextValidator, $scenarioSchemaPath, $resultSchemaPath, $verificationSchemaPath)) {
    if (-not (Test-Path -LiteralPath $dep)) {
        [Console]::Error.WriteLine("ERROR: required dependency missing: $dep")
        exit 1
    }
}

$profileRank = @{ prototype = 0; standard = 1; 'high-assurance' = 2 }
$checkOrder = @(
    'SCENARIO_SCHEMA_VALID',
    'TASK_ARTIFACT_PRESENT',
    'TASK_CONTRACT_VALID',
    'CONTEXT_CONTRACT_VALID',
    'VERIFICATION_SCHEMA_VALID',
    'PROFILE_FLOOR_RESPECTED',
    'REQUIRED_MODULES_SELECTED',
    'FORBIDDEN_MODULES_AVOIDED',
    'APPROVALS_DECLARED',
    'EVIDENCE_PRESENT',
    'FORBIDDEN_PATHS_AVOIDED',
    'FORBIDDEN_ACTIONS_ABSENT'
)

# ---------------------------------------------------------------------------
# Minimal offline draft-07 subset interpreter (mirror of run-evals.sh).
# Supports exactly the keywords used by the managed schemas: type, const,
# enum, pattern, required, properties, additionalProperties:false, items,
# minimum, minItems, maxItems, allOf, if/then.
# ---------------------------------------------------------------------------

function Test-JsonType($Value, [string]$Name) {
    switch ($Name) {
        'object' { return ($null -ne $Value -and $Value -is [System.Collections.IDictionary]) }
        'array' { return ($null -ne $Value -and $Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) }
        'string' { return $Value -is [string] }
        'boolean' { return $Value -is [bool] }
        'integer' { return ($Value -is [int] -or $Value -is [long]) -and $Value -isnot [bool] }
        'number' { return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) -and $Value -isnot [bool] }
        'null' { return $null -eq $Value }
        default { return $true }
    }
}

function Test-JsonEqual($A, $B) {
    if ($null -eq $A -or $null -eq $B) { return ($null -eq $A -and $null -eq $B) }
    # JSON numbers deserialize as Int64 while constructed docs use Int32;
    # compare numerics across widths, everything else strictly.
    $aNum = ($A -is [int] -or $A -is [long] -or $A -is [double] -or $A -is [decimal]) -and ($A -isnot [bool])
    $bNum = ($B -is [int] -or $B -is [long] -or $B -is [double] -or $B -is [decimal]) -and ($B -isnot [bool])
    if ($aNum -and $bNum) { return ([double]$A -eq [double]$B) }
    return $A.Equals($B)
}

function Test-JsonHasKey($Dict, [string]$Key) {
    if ($Dict -is [System.Collections.Specialized.OrderedDictionary]) { return $Dict.Contains($Key) }
    return $Dict.ContainsKey($Key)
}

function Get-JsonSchemaErrors($Instance, $Hashtag, [string]$Path = '$') {
    $errors = @()
    if ($null -eq $Hashtag -or $Hashtag -isnot [System.Collections.IDictionary]) { return $errors }

    if ($Hashtag.Contains('type')) {
        $names = @($Hashtag['type'])
        $ok = $false
        foreach ($n in $names) { if (Test-JsonType $Instance $n) { $ok = $true; break } }
        if (-not $ok) {
            $errors += ("{0}: expected type {1}" -f $Path, ($names -join '/'))
            return $errors
        }
    }

    if ($Hashtag.Contains('const') -and -not (Test-JsonEqual $Instance $Hashtag['const'])) {
        $errors += ("{0}: must equal {1}" -f $Path, ($Hashtag['const'] | ConvertTo-Json -Compress))
    }

    if ($Hashtag.Contains('enum')) {
        $found = $false
        foreach ($opt in @($Hashtag['enum'])) { if (Test-JsonEqual $Instance $opt) { $found = $true; break } }
        if (-not $found) {
            $errors += ("{0}: value not in enum" -f $Path)
        }
    }

    if ($Hashtag.Contains('pattern') -and $Instance -is [string]) {
        if ($Instance -cnotmatch $Hashtag['pattern']) {
            $errors += ("{0}: does not match pattern {1}" -f $Path, $Hashtag['pattern'])
        }
    }

    if (Test-JsonType $Instance 'number') {
        if ($Hashtag.Contains('minimum') -and [double]$Instance -lt [double]$Hashtag['minimum']) {
            $errors += ("{0}: below minimum {1}" -f $Path, $Hashtag['minimum'])
        }
    }

    if (Test-JsonType $Instance 'array') {
        $list = @($Instance)
        if ($Hashtag.Contains('minItems') -and $list.Count -lt [int]$Hashtag['minItems']) {
            $errors += ("{0}: fewer than {1} items" -f $Path, $Hashtag['minItems'])
        }
        if ($Hashtag.Contains('maxItems') -and $list.Count -gt [int]$Hashtag['maxItems']) {
            $errors += ("{0}: more than {1} items" -f $Path, $Hashtag['maxItems'])
        }
        if ($Hashtag.Contains('items')) {
            for ($i = 0; $i -lt $list.Count; $i++) {
                $errors += @(Get-JsonSchemaErrors $list[$i] $Hashtag['items'] ('{0}[{1}]' -f $Path, $i))
            }
        }
    }

    if (Test-JsonType $Instance 'object') {
        if ($Hashtag.Contains('required')) {
            foreach ($prop in @($Hashtag['required'])) {
                if (-not (Test-JsonHasKey $Instance $prop)) {
                    $errors += ("{0}: missing required property '{1}'" -f $Path, $prop)
                }
            }
        }
        $props = $Hashtag['properties']
        foreach ($key in @($Instance.Keys)) {
            if ($null -ne $props -and (Test-JsonHasKey $props $key)) {
                $errors += @(Get-JsonSchemaErrors $Instance[$key] $props[$key] ("{0}.{1}" -f $Path, $key))
            }
            elseif ($Hashtag.Contains('additionalProperties') -and $Hashtag['additionalProperties'] -eq $false) {
                $errors += ("{0}: unexpected property '{1}'" -f $Path, $key)
            }
        }
    }

    if ($Hashtag.Contains('allOf')) {
        foreach ($sub in @($Hashtag['allOf'])) {
            $errors += @(Get-JsonSchemaErrors $Instance $sub $Path)
        }
    }

    if ($Hashtag.Contains('if')) {
        if (@(Get-JsonSchemaErrors $Instance $Hashtag['if'] $Path).Count -eq 0) {
            if ($Hashtag.Contains('then')) {
                $errors += @(Get-JsonSchemaErrors $Instance $Hashtag['then'] $Path)
            }
        }
    }

    return $errors
}

function ConvertTo-AuthoritativeSections([string]$TaskText) {
    # Authoritative task content grouped by `##` section (lowercased names),
    # mirroring the production validators' scan: fenced code, HTML comments,
    # and blockquotes are dropped. Approvals and evidence can only be
    # satisfied by their own authoritative sections.
    $sections = @{}
    $inFence = $false
    $inComment = $false
    $current = $null
    foreach ($raw in ($TaskText -split "`r?`n")) {
        $line = $raw.TrimEnd("`r")
        $stripped = $line.Trim()
        if ($inFence) {
            if ($line.StartsWith('```', [System.StringComparison]::Ordinal)) { $inFence = $false }
            continue
        }
        if ($line.StartsWith('```', [System.StringComparison]::Ordinal)) { $inFence = $true; continue }
        if ($inComment) {
            if ($stripped.Contains('-->')) { $inComment = $false }
            continue
        }
        if ($stripped.Contains('<!--')) {
            if (-not $stripped.Contains('-->')) { $inComment = $true }
            continue
        }
        if ($stripped.StartsWith('>', [System.StringComparison]::Ordinal)) { continue }
        if ($stripped.StartsWith('##', [System.StringComparison]::Ordinal)) {
            $current = $stripped.TrimStart('#').Trim().ToLowerInvariant()
            if (-not $sections.ContainsKey($current)) { $sections[$current] = [System.Collections.Generic.List[string]]::new() }
            continue
        }
        if ($null -ne $current) {
            if (-not $sections.ContainsKey($current)) { $sections[$current] = [System.Collections.Generic.List[string]]::new() }
            $sections[$current].Add($raw.TrimEnd("`r"))
        }
    }
    return $sections
}

$script:approvalSectionName = 'approval gates'
$script:evidenceSectionNames = @('required evidence', 'requirement-to-evidence')
$script:canonicalTableHeader = [regex]::new('^\|\s*(?:ac id|requirement id)\s*\|[^|]*\|\s*result\s*\|\s*$', 'IgnoreCase')

function Get-CanonicalEvidenceRows($SectionLines) {
    # Rows of the first canonical `<ID> | Evidence | Result` table only.
    $rows = [System.Collections.Generic.List[string]]::new()
    $collecting = $false
    foreach ($raw in $SectionLines) {
        $s = $raw.Trim()
        if (-not $collecting) {
            if ($script:canonicalTableHeader.IsMatch($s)) { $collecting = $true }
            continue
        }
        if (-not $s.StartsWith('|')) { break }
        $cells = @(($s.Trim('|').Split('|') | ForEach-Object { $_.Trim() }))
        $isSeparator = $true
        foreach ($c in $cells) { if ($c -and ($c.Trim('-: ') -ne '')) { $isSeparator = $false; break } }
        if ($isSeparator) { continue }
        $rows.Add($s.ToLowerInvariant())
    }
    return $rows.ToArray()
}

function Test-GateDeclared($Sections, [string]$Token) {
    $wanted = ($Token -replace '[-_]+', ' ').ToLowerInvariant()
    foreach ($line in $Sections[$script:approvalSectionName]) {
        if ($line -cmatch '^\s*[-*]\s*\[x\]\s*AG-\d+:') {
            $candidate = ($line -replace '[-_]+', ' ').ToLowerInvariant()
            if ($candidate.Contains($wanted)) { return $true }
        }
    }
    return $false
}

function Test-EvidencePresent($Sections, [string]$Token) {
    foreach ($name in $script:evidenceSectionNames) {
        if (-not $Sections.ContainsKey($name)) { continue }
        foreach ($row in (Get-CanonicalEvidenceRows $Sections[$name])) {
            if ($row.Contains($Token.ToLowerInvariant())) { return $true }
        }
    }
    return $false
}

function Test-ForbiddenPath([array]$ChangedPaths, [array]$ForbiddenPaths) {
    # Directory-aware match: equal, descendant of, or overwriting a
    # forbidden path.
    foreach ($changed in $ChangedPaths) {
        $norm = ($changed -replace '\\', '/').TrimStart('.', '/').TrimStart('/')
        foreach ($fp in $ForbiddenPaths) {
            $f = ($fp -replace '\\', '/').TrimStart('.', '/').TrimStart('/')
            if ($norm -eq $f -or $norm.StartsWith($f.TrimEnd('/') + '/') -or $f.StartsWith($norm.TrimEnd('/') + '/')) { return $true }
        }
    }
    return $false
}

function Invoke-TaskValidatorContract([string]$TaskPath) {
    $out = & pwsh -NoProfile -File $taskValidator -Handoff $TaskPath 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 0) { return @{ Ok = $true; Detail = '' } }
    $first = "$(@($out) | Select-Object -First 1)".Trim()
    if (-not $first) { $first = "validate-task -Handoff rejected the artifact (exit $code)" }
    return @{ Ok = $false; Detail = $first }
}

function Invoke-ContextValidatorContract([string]$TaskPath) {
    $out = & pwsh -NoProfile -File $contextValidator -Handoff -Format Json $TaskPath 2>$null
    $code = $LASTEXITCODE
    $profile = $null
    $ids = @()
    $ok = ($code -eq 0)
    try {
        $joined = ($out | Out-String).Trim()
        $firstLine = ($joined -split "`n")[0]
        $doc = $firstLine | ConvertFrom-Json -AsHashtable
        $profile = $doc['profile']
        $ids = @($doc['selected_modules'] | ForEach-Object { $_['id'] })
    }
    catch {
        $ok = $false
    }
    return @{ Ok = $ok; Profile = $profile; Ids = $ids }
}

$summaryFields = @('checks_defined', 'checks_run', 'required_run',
    'passed', 'failed', 'optional_failed', 'blocked', 'optional_skipped')

function Get-VerificationMismatches([hashtable]$VDoc) {
    # Summary counts must be derivable from the actual checks array.
    $summary = $VDoc['summary']
    $checks = @($VDoc['checks'])
    $executed = @($checks | Where-Object { $_['status'] -in @('PASS', 'FAIL') })
    $derived = @{
        checks_defined   = $checks.Count
        checks_run       = $executed.Count
        required_run     = @($executed | Where-Object { $_['requirement'] -eq 'required' }).Count
        passed           = @($checks | Where-Object { $_['status'] -eq 'PASS' }).Count
        failed           = @($checks | Where-Object { $_['requirement'] -eq 'required' -and $_['status'] -eq 'FAIL' }).Count
        optional_failed  = @($checks | Where-Object { $_['requirement'] -eq 'optional' -and $_['status'] -eq 'FAIL' }).Count
        blocked          = @($checks | Where-Object { $_['status'] -eq 'BLOCKED' }).Count
        optional_skipped = @($checks | Where-Object { $_['status'] -eq 'SKIPPED_OPTIONAL' }).Count
    }
    $mismatched = @()
    foreach ($field in $summaryFields) {
        if (-not (Test-JsonEqual $summary[$field] $derived[$field])) { $mismatched += $field }
    }
    return $mismatched
}

function Invoke-Evaluation([string]$ScenarioPath) {
    $checks = [ordered]@{}
    $details = @{}

    function Record([string]$Id, [bool]$Passed, [string]$Detail = '') {
        $checks[$Id] = $Passed
        if ($Detail) { $details[$Id] = $Detail }
    }

    $sid = Split-Path -Leaf (Split-Path -Parent $ScenarioPath)
    $scenario = $null
    $schemaOk = $false
    try {
        $scenario = Get-Content -Raw -LiteralPath $ScenarioPath | ConvertFrom-Json -AsHashtable
        $sschema = Get-Content -Raw -LiteralPath $scenarioSchemaPath | ConvertFrom-Json -AsHashtable
        $errs = @(Get-JsonSchemaErrors $scenario $sschema)
        $schemaOk = ($errs.Count -eq 0)
        Record 'SCENARIO_SCHEMA_VALID' $schemaOk (($schemaOk) ? '' : ('scenario.json violates scenario-v1: ' + ($errs[0..([Math]::Min(2, $errs.Count - 1))] -join '; ')))
    }
    catch {
        Record 'SCENARIO_SCHEMA_VALID' $false ("unreadable or malformed scenario.json: " + $_.Exception.Message)
    }

    if ($schemaOk) { $sid = $scenario['id'] }

    $artifactsDir = Join-Path (Split-Path -Parent $ScenarioPath) 'artifacts'
    $taskPath = Join-Path $artifactsDir 'task.md'

    $expected = if ($null -ne $scenario -and $scenario.ContainsKey('expected')) { $scenario['expected'] } else { @{} }
    $forbidden = if ($null -ne $scenario -and $scenario.ContainsKey('forbidden')) { $scenario['forbidden'] } else { @{} }
    $requiredModules = if ($schemaOk -and $expected.ContainsKey('required_modules')) { @($expected['required_modules']) } else { @() }
    $requiredGates = if ($schemaOk -and $expected.ContainsKey('required_approval_gates')) { @($expected['required_approval_gates']) } else { @() }
    $requiredEvidence = if ($schemaOk -and $expected.ContainsKey('required_evidence')) { @($expected['required_evidence']) } else { @() }

    if ($schemaOk -and (Test-Path -LiteralPath $taskPath -PathType Leaf) -and ((Get-Item -LiteralPath $taskPath).Length -gt 0)) {
        Record 'TASK_ARTIFACT_PRESENT' $true

        $contract = Invoke-TaskValidatorContract $taskPath
        Record 'TASK_CONTRACT_VALID' $contract.Ok $contract.Detail

        $selection = Invoke-ContextValidatorContract $taskPath
        Record 'CONTEXT_CONTRACT_VALID' $selection.Ok (($selection.Ok) ? '' : 'validate-context -Handoff rejected the artifact task file')

        $minProfile = [string]$expected['minimum_profile']
        $profRank = if ($selection.Profile -and $profileRank.ContainsKey([string]$selection.Profile)) { $profileRank[[string]$selection.Profile] } else { -1 }
        $needRank = $profileRank[$minProfile]
        Record 'PROFILE_FLOOR_RESPECTED' ($profRank -ge $needRank) ("task profile '{0}' vs minimum '{1}'" -f $selection.Profile, $minProfile)

        $missing = @($requiredModules | Where-Object { $selection.Ids -notcontains $_ })
        Record 'REQUIRED_MODULES_SELECTED' ($missing.Count -eq 0) (($missing.Count -gt 0) ? ("missing: " + ($missing -join ', ')) : '')

        $forbiddenModules = if ($forbidden.ContainsKey('modules')) { @($forbidden['modules']) } else { @() }
        $used = @($selection.Ids | Where-Object { $forbiddenModules -contains $_ })
        Record 'FORBIDDEN_MODULES_AVOIDED' ($used.Count -eq 0) (($used.Count -gt 0) ? ("forbidden modules selected: " + ($used -join ', ')) : '')

        $taskText = Get-Content -Raw -LiteralPath $taskPath
        $authSections = ConvertTo-AuthoritativeSections $taskText

        $gateMissing = @($requiredGates | Where-Object { -not (Test-GateDeclared $authSections $_) })
        Record 'APPROVALS_DECLARED' ($gateMissing.Count -eq 0) (($gateMissing.Count -gt 0) ? ("no approval record for: " + ($gateMissing -join ', ')) : '')

        $evMissing = @($requiredEvidence | Where-Object { -not (Test-EvidencePresent $authSections $_) })
        Record 'EVIDENCE_PRESENT' ($evMissing.Count -eq 0) (($evMissing.Count -gt 0) ? ("evidence table lacks: " + ($evMissing -join ', ')) : '')

        $verificationPath = Join-Path $artifactsDir 'verification-result.json'
        $verOk = $false
        $verDetail = 'artifact verification-result.json must be a schema-valid PASS verification_result'
        if (Test-Path -LiteralPath $verificationPath -PathType Leaf) {
            try {
                $vdoc = Get-Content -Raw -LiteralPath $verificationPath | ConvertFrom-Json -AsHashtable
                $vschema = Get-Content -Raw -LiteralPath $verificationSchemaPath | ConvertFrom-Json -AsHashtable
                $verrs = @(Get-JsonSchemaErrors $vdoc $vschema)
                $mismatched = @(Get-VerificationMismatches $vdoc)
                if ($verrs.Count -gt 0) {
                    $verDetail = 'violates verification-result-v1: ' + ($verrs[0..([Math]::Min(2, $verrs.Count - 1))] -join '; ')
                }
                elseif ($mismatched.Count -gt 0) {
                    $verDetail = 'summary disagrees with checks array: ' + ($mismatched -join ', ')
                }
                elseif ([string]$vdoc['result'] -ne 'PASS') {
                    $verDetail = "verification result is '$($vdoc['result'])', not PASS"
                }
                else { $verOk = $true }
            }
            catch { $verDetail = "unreadable verification-result.json: $($_.Exception.Message)" }
        }
        Record 'VERIFICATION_SCHEMA_VALID' $verOk $verDetail

        $changed = if ($schemaOk) { @($scenario['input']['changed_paths']) } else { @() }
        $forbiddenPaths = if ($forbidden.ContainsKey('paths')) { @($forbidden['paths']) } else { @() }
        $badPaths = Test-ForbiddenPath $changed $forbiddenPaths
        Record 'FORBIDDEN_PATHS_AVOIDED' (-not $badPaths) (($badPaths) ? 'a changed path matches a forbidden path' : '')

        $tokens = @()
        if ($forbidden.ContainsKey('actions')) {
            foreach ($a in @($forbidden['actions'])) { $tokens += $a.ToLowerInvariant() }
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
    $observed = if ($total -gt 0 -and $passedCount -eq $total) { 'PASS' } else { 'FAIL' }

    $expectation = 'PASS'
    $expectedFailures = @()
    if ($null -ne $scenario) {
        if ($scenario.ContainsKey('fixture_expected_result')) { $expectation = [string]$scenario['fixture_expected_result'] }
        if ($scenario.ContainsKey('expected_failed_checks')) { $expectedFailures = @($scenario['expected_failed_checks'] | ForEach-Object { [string]$_ }) }
    }

    # A negative control only proves detection when the EXACT intended check
    # set failed; a failure of any other check must fail the harness itself.
    $actualFailures = @($checks.Keys | Where-Object { -not $checks[$_] } | Sort-Object)
    $expectedSorted = @($expectedFailures | Sort-Object)
    $matched = ($observed -eq $expectation) -and (@(Compare-Object $actualFailures $expectedSorted).Count -eq 0)
    $diagnostics = @()
    if ($observed -ne $expectation) {
        $diagnostics += [ordered]@{
            code    = 'FIXTURE_EXPECTATION_MISMATCH'
            message = "observed $observed does not match fixture_expected_result $expectation"
        }
    }
    elseif (@(Compare-Object $actualFailures $expectedSorted).Count -ne 0) {
        $diagnostics += [ordered]@{
            code    = 'FIXTURE_EXPECTATION_MISMATCH'
            message = "failed checks [$($actualFailures -join ', ')] do not match expected_failed_checks [$($expectedSorted -join ', ')]"
        }
    }

    $doc = [ordered]@{
        schema_version       = 1
        protocol_version     = '1.5.0'
        kind                 = 'behavioral_evaluation_result'
        mode                 = 'offline-fixture'
        observed_result      = $observed
        expected_result      = $expectation
        expectation_matched  = [bool]$matched
        result               = if ($matched) { 'PASS' } else { 'FAIL' }
        exit_code            = if ($matched) { 0 } else { 1 }
        scenario_id          = $sid
        summary              = [ordered]@{ total = $total; passed = $passedCount; failed = $total - $passedCount }
        checks               = $ordered
        diagnostics          = $diagnostics
    }

    # Every emitted document must satisfy its own managed schema before the
    # runner may print it or report success (#review blocker 4).
    $resultSchema = Get-Content -Raw -LiteralPath $resultSchemaPath | ConvertFrom-Json -AsHashtable
    $selfErrs = @(Get-JsonSchemaErrors $doc $resultSchema)
    if ($selfErrs.Count -gt 0) {
        [Console]::Error.WriteLine(('ERROR: emitted document violates evaluation-result-v1.schema.json for {0}: {1}' -f $sid, ($selfErrs[0..([Math]::Min(4, $selfErrs.Count - 1))] -join '; ')))
        exit 1
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
        $failedChecks = @($outcome.Doc.checks | Where-Object { -not $_.passed } | ForEach-Object { $_.id })
        $suffix = if ($failedChecks.Count -gt 0) { ' failed=' + ($failedChecks -join ',') } else { '' }
        $line = '{0,-28} observed={1,-4} expected={2,-4} harness={3,-4}{4}' -f $outcome.Doc.scenario_id, $outcome.Doc.observed_result, $outcome.Doc.expected_result, $outcome.Doc.result, $suffix
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
    [Console]::Out.WriteLine(('evals: {0}/{1} scenarios evaluated correctly' -f $expectedOk, $results.Count))
}

exit $(if ($expectedOk -eq $results.Count) { 0 } else { 1 })
