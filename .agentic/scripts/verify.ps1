#Requires -Version 7.0
<#
.SYNOPSIS
    verify.ps1 — Universal project verification script.
.DESCRIPTION
    Auto-detects the project stack and runs its native test + lint commands.
    Implements the detection matrix from AGENTS.md (Section 5).
.EXAMPLE
    ./.agentic/scripts/verify.ps1   (run from the project root)
#>

$script:Failed = $false
$script:Detected = $false

function Invoke-Step {
    param([string[]] $Command)
    Write-Host ""
    Write-Host "==> $($Command -join ' ')"
    & $Command[0] $Command[1..($Command.Length - 1)]
    if ($LASTEXITCODE -ne 0) { $script:Failed = $true }
}

function Test-Command {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# --- Node.js / JavaScript / TypeScript ---
if (Test-Path package.json) {
    $script:Detected = $true
    Write-Host "Detected: Node.js project (package.json)"
    if (Test-Command npm) {
        Invoke-Step @("npm", "test")
        Invoke-Step @("npm", "run", "lint", "--if-present")
    }
}

# --- Rust ---
if (Test-Path Cargo.toml) {
    $script:Detected = $true
    Write-Host "Detected: Rust project (Cargo.toml)"
    if (Test-Command cargo) {
        Invoke-Step @("cargo", "test")
        Invoke-Step @("cargo", "clippy", "--", "-D", "warnings")
    }
}

# --- Python ---
if ((Test-Path pyproject.toml) -or (Test-Path requirements.txt)) {
    $script:Detected = $true
    Write-Host "Detected: Python project (pyproject.toml / requirements.txt)"
    if (Test-Command pytest) { Invoke-Step @("pytest") }
    if (Test-Command ruff)   { Invoke-Step @("ruff", "check", ".") }
}

# --- Go ---
if (Test-Path go.mod) {
    $script:Detected = $true
    Write-Host "Detected: Go project (go.mod)"
    if (Test-Command go) {
        Invoke-Step @("go", "test", "./...")
        Invoke-Step @("go", "vet", "./...")
    }
}

# --- Java / JVM ---
if (Test-Path pom.xml) {
    $script:Detected = $true
    Write-Host "Detected: Maven project (pom.xml)"
    if (Test-Command mvn) { Invoke-Step @("mvn", "test") }
}
elseif ((Test-Path build.gradle) -or (Test-Path build.gradle.kts)) {
    $script:Detected = $true
    Write-Host "Detected: Gradle project (build.gradle)"
    if (Test-Path ./gradlew) {
        Invoke-Step @("./gradlew", "test")
        Invoke-Step @("./gradlew", "check")
    }
}

# --- .NET ---
if ((Get-ChildItem -Filter *.sln -ErrorAction SilentlyContinue) -or (Get-ChildItem -Filter *.csproj -ErrorAction SilentlyContinue)) {
    $script:Detected = $true
    Write-Host "Detected: .NET project (*.sln / *.csproj)"
    if (Test-Command dotnet) { Invoke-Step @("dotnet", "test") }
}

Write-Host ""
if (-not $script:Detected) {
    Write-Host "No known project manifest detected. Nothing to verify."
    exit 0
}

if ($script:Failed) {
    Write-Host "VERIFICATION FAILED — see output above."
    exit 1
}

Write-Host "VERIFICATION PASSED."
