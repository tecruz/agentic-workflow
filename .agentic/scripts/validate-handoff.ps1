#Requires -Version 7.0
<#
.SYNOPSIS
    validate-handoff.ps1 — single public handoff gate for completed tasks.

.DESCRIPTION
    Runs BOTH production validators against one task file and requires both to
    pass in -Handoff mode:

      1. validate-task.ps1    -Handoff   (risk profile, evidence, approvals)
      2. validate-context.ps1 -Handoff   (context-module selections)

    Both validators inspect the same file, so their results refer to the same
    task and profile by construction. The gate is satisfied only when neither
    reports an unresolved approval, evidence, or module-selection state.

    Exit codes: 0 both gates VALID; 1 any INVALID; 2 any BLOCKED.

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

if ($taskCode -eq 0 -and $contextCode -eq 0) {
    [Console]::Out.WriteLine('VALID: handoff gate satisfied (task contract + context contract)')
    exit 0
}

$gateCode = if ($taskCode -eq 2 -or $contextCode -eq 2) { 2 } else { 1 }

function Get-FirstDiagnostic($Output) {
    foreach ($line in @($Output)) {
        $s = "$line".Trim()
        if ($s) { return $s }
    }
    return '<no diagnostic>'
}

$verdict = if ($gateCode -eq 2) { 'BLOCKED' } else { 'INVALID' }
[Console]::Error.WriteLine("${verdict}: handoff gate failed (task=${taskCode}: $(Get-FirstDiagnostic $taskOut); context=${contextCode}: $(Get-FirstDiagnostic $contextOut))")
exit $gateCode
