# run-parity.ps1 — single cross-language parity check for validators.
#   Compares PowerShell and Bash classifiers on every task fixture,
#   and compares PowerShell and Bash detection contracts on every
#   golden fixture.  Runs once instead of per-OS per-framework.
param()

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtures = Join-Path $repoRoot 'tests' 'fixtures' 'tasks'
$golden   = Join-Path $repoRoot 'tests' 'fixtures' 'golden'
$validatePS = Join-Path $repoRoot '.agentic' 'scripts' 'validate-task.ps1'
$validateSH = Join-Path $repoRoot '.agentic' 'scripts' 'validate-task.sh'
$verifyPS   = Join-Path $repoRoot '.agentic' 'scripts' 'verify.ps1'
$verifySH   = Join-Path $repoRoot '.agentic' 'scripts' 'verify.sh'

$failures = 0

# ── 1. Task fixture parity ──────────────────────────────────────────────
Write-Host '=== Task fixture parity ==='

if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: bash not available'
    exit 0
}

Get-ChildItem -LiteralPath $fixtures -Filter *.md | ForEach-Object {
    $name = $_.Name
    $bashOut = (bash $validateSH $_.FullName 2>&1 | Out-String).Trim()
    $bashCode = $LASTEXITCODE
    $psOut = (pwsh -NoProfile -File $validatePS $_.FullName 2>&1 | Out-String).Trim()
    $psCode = $LASTEXITCODE

    if ($bashCode -ne $psCode) {
        Write-Host "  CODE MISMATCH: $name  bash=$bashCode ps=$psCode"
        $failures++
    }
    elseif ($psOut -ne $bashOut) {
        Write-Host "  OUTPUT MISMATCH: $name"
        Write-Host "    bash: $bashOut"
        Write-Host "    ps:   $psOut"
        $failures++
    }
}

# ── 2. Detection parity ────────────────────────────────────────────────
Write-Host '=== Detection parity ==='

Get-ChildItem -LiteralPath $golden -Filter *.tsv | ForEach-Object {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $fixtureDir = Join-Path $repoRoot 'tests' 'fixtures' $name
    if (-not (Test-Path -LiteralPath $fixtureDir)) { return }

    # Run PowerShell detector
    $psTmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $psTmp | Out-Null
    Copy-Item -LiteralPath "$fixtureDir\*" -Destination $psTmp -Recurse -Force
    Push-Location $psTmp
    try {
        & pwsh -NoProfile -File $verifyPS -DetectChecks 2>&1 | Out-Null
        $psChecks = (Get-Content -LiteralPath (Join-Path $psTmp '.agentic' 'checks.generated.tsv') |
            Where-Object { $_ -and -not $_.StartsWith('#') } | Sort-Object) -join "`n"
    }
    finally { Pop-Location; Remove-Item -LiteralPath $psTmp -Recurse -Force -ErrorAction SilentlyContinue }

    # Run Bash detector
    $bashTmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $bashTmp | Out-Null
    Copy-Item -LiteralPath "$fixtureDir\*" -Destination $bashTmp -Recurse -Force
    Push-Location $bashTmp
    try {
        & bash $verifySH --detect-checks 2>&1 | Out-Null
        $bashChecks = (Get-Content -LiteralPath (Join-Path $bashTmp '.agentic' 'checks.generated.tsv') |
            Where-Object { $_ -and -not $_.StartsWith('#') } | Sort-Object) -join "`n"
    }
    finally { Pop-Location; Remove-Item -LiteralPath $bashTmp -Recurse -Force -ErrorAction SilentlyContinue }

    if ($psChecks -ne $bashChecks) {
        Write-Host "  DETECTION MISMATCH: $name"
        $failures++
    }
}

# ── Result ──────────────────────────────────────────────────────────────
if ($failures -gt 0) {
    Write-Error "$failures parity assertion(s) failed"
    exit 1
}
Write-Host 'All parity checks passed.'
exit 0
