#Requires -Version 7.0
<#
.SYNOPSIS
    validate-handoff.ps1 — single public handoff gate for completed tasks.

.DESCRIPTION
    Runs ALL THREE production validators against one task file and requires all
    to pass in -Handoff mode:

      1. validate-task.ps1    -Handoff   (risk profile, evidence, approvals)
      2. validate-context.ps1 -Handoff   (context-module selections)
      3. validate-skills.ps1  -Handoff   (skill invocations)

    All validators inspect the same file, so their results refer to the same
    task and profile by construction. The gate is satisfied only when none
    reports an unresolved approval, evidence, module-selection, or
    skill-invocation state.

    Exit codes: 0 all gates VALID; 1 any INVALID; 2 any BLOCKED.

.PARAMETER TaskFile
    Task file to gate.

.EXAMPLE
    pwsh -NoProfile -File validate-handoff.ps1 .agentic/tasks/TASK-006.md
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TaskFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    [Console]::Error.WriteLine("INVALID: task file not found: $TaskFile")
    exit 1
}

$scriptDir = $PSScriptRoot

$taskOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'validate-task.ps1') -Handoff -TaskFile $TaskFile 2>&1
$taskCode = $LASTEXITCODE

$contextOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'validate-context.ps1') -Handoff -TaskFile $TaskFile 2>&1
$contextCode = $LASTEXITCODE

$skillsOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'validate-skills.ps1') -Handoff -TaskFile $TaskFile 2>&1
$skillsCode = $LASTEXITCODE

if ($taskCode -eq 0 -and $contextCode -eq 0 -and $skillsCode -eq 0) {
    [Console]::Out.WriteLine('VALID: handoff gate satisfied (task contract + context contract + skills contract)')
    exit 0
}

$gateCode = if ($taskCode -eq 2 -or $contextCode -eq 2 -or $skillsCode -eq 2) { 2 } else { 1 }

function Get-FirstDiagnostic($Output) {
    foreach ($line in @($Output)) {
        $s = "$line".Trim()
        if ($s) { return $s }
    }
    return '<no diagnostic>'
}

$verdict = if ($gateCode -eq 2) { 'BLOCKED' } else { 'INVALID' }
[Console]::Error.WriteLine("${verdict}: handoff gate failed (task=${taskCode}: $(Get-FirstDiagnostic $taskOut); context=${contextCode}: $(Get-FirstDiagnostic $contextOut); skills=${skillsCode}: $(Get-FirstDiagnostic $skillsOut))")
exit $gateCode
