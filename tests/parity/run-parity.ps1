# run-parity.ps1 — cross-language validator parity + golden expectations.
#   For every task fixture, requires the PowerShell validator and the Bash
#   validator to each match the golden expectation (exit code and message) in
#   task-expectations.tsv, then compares the two detection contracts on every
#   golden fixture. Matching the same golden file proves each validator is
#   correct against the expected classification — not merely that the two
#   implementations agree with each other. Runs once instead of per-OS
#   per-framework.
param()

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtures = Join-Path $repoRoot 'tests' 'fixtures' 'tasks'
$goldenFile = Join-Path $repoRoot 'tests' 'parity' 'task-expectations.tsv'
$validatePS = Join-Path $repoRoot '.agentic' 'scripts' 'validate-task.ps1'
$validateSH = Join-Path $repoRoot '.agentic' 'scripts' 'validate-task.sh'
$verifyPS   = Join-Path $repoRoot '.agentic' 'scripts' 'verify.ps1'
$verifySH   = Join-Path $repoRoot '.agentic' 'scripts' 'verify.sh'

if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: bash not available'
    exit 0
}
if (-not (Test-Path -LiteralPath $goldenFile)) {
    Write-Error "golden expectations not found: $goldenFile"
    exit 2
}

# Load golden expectations: fixture-name -> @{ Code; Message }
$script:golden = @{}
foreach ($line in Get-Content -LiteralPath $goldenFile) {
    if (-not $line -or $line.TrimStart().StartsWith('#')) { continue }
    $parts = $line -split "`t", 3
    if ($parts.Count -lt 3) { continue }
    $script:golden[$parts[0]] = @{ Code = [int]$parts[1]; Message = $parts[2].Trim() }
}

$script:failures = 0

function Invoke-GoldenCheck([string]$lang, [string]$validator) {
    Write-Host "=== Task fixture golden expectations ($lang) ==="
    foreach ($f in Get-ChildItem -LiteralPath $fixtures -Filter *.md) {
        $name = $f.Name
        $expect = $script:golden[$name]
        if ($null -eq $expect) {
            Write-Host "  NO GOLDEN ENTRY: $name"
            $script:failures++
            continue
        }
        if ($lang -eq 'pwsh') {
            $out = (pwsh -NoProfile -File $validator $f.FullName 2>&1 | Out-String).Trim()
            $code = $LASTEXITCODE
        }
        else {
            $out = (bash $validator $f.FullName 2>&1 | Out-String).Trim()
            $code = $LASTEXITCODE
        }
        if ($code -ne $expect.Code) {
            Write-Host "  CODE MISMATCH ($lang): $name  expected=$($expect.Code) got=$code"
            $script:failures++
        }
        elseif ($out -ne $expect.Message) {
            Write-Host "  MESSAGE MISMATCH ($lang): $name"
            Write-Host "    expected: $($expect.Message)"
            Write-Host "    got:      $out"
            $script:failures++
        }
    }
}

# ── 1. Task fixture golden expectations ─────────────────────────────────
Invoke-GoldenCheck 'pwsh' $validatePS
Invoke-GoldenCheck 'bash' $validateSH

# ── 2. Detection parity ────────────────────────────────────────────────
Write-Host '=== Detection parity ==='

$golden = Join-Path $repoRoot 'tests' 'fixtures' 'golden'

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
        $script:failures++
    }
}

# ── Result ──────────────────────────────────────────────────────────────
if ($script:failures -gt 0) {
    Write-Error "$($script:failures) parity assertion(s) failed"
    exit 1
}
Write-Host 'All parity checks passed.'
exit 0
