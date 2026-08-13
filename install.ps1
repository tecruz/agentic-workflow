#Requires -Version 7.0
<#
.SYNOPSIS
    install.ps1 — Install the Universal Agentic Development Protocol into a project.
.DESCRIPTION
    Copies the protocol files (AGENTS.md, tool entry points, .agentic/) into a
    target project. Existing files are NEVER overwritten unless -Force is passed.
.PARAMETER Target
    Project directory to install into (default: current directory).
.PARAMETER Force
    Overwrite files that already exist in the target.
.EXAMPLE
    ./install.ps1 -Target C:\projects\my-app
.EXAMPLE
    ./install.ps1 -Target C:\projects\my-app -Force
#>

param(
    [string] $Target = ".",
    [switch] $Force
)

$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $Target)) {
    Write-Host "Error: target directory '$Target' does not exist."
    exit 1
}

$TargetDir = (Resolve-Path $Target).Path

# Files installed into every project. Repo meta files (README, LICENSE,
# .gitignore, the installers themselves) are intentionally excluded.
$RootFiles = @(
    "AGENTS.md",
    "CLAUDE.md",
    "GEMINI.md",
    "CONVENTIONS.md",
    ".cursorrules",
    ".windsurfrules",
    ".clinerules"
)

$NestedFiles = @(
    ".cursor/rules/agentic-protocol.mdc",
    ".windsurf/rules/agentic-protocol.md",
    ".github/copilot-instructions.md"
)

$script:Copied = 0
$script:Skipped = 0

function Copy-ProtocolFile {
    param([string] $RelativePath)

    $src = Join-Path $SourceDir $RelativePath
    $dst = Join-Path $TargetDir $RelativePath

    if ((Test-Path $dst) -and (-not $Force)) {
        Write-Host "  skip  $RelativePath (already exists; use -Force to overwrite)"
        $script:Skipped++
        return
    }

    $parent = Split-Path -Parent $dst
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  copy  $RelativePath"
    $script:Copied++
}

Write-Host "Installing Universal Agentic Development Protocol"
Write-Host "  from: $SourceDir"
Write-Host "  into: $TargetDir"
Write-Host ""

foreach ($f in $RootFiles)   { Copy-ProtocolFile $f }
foreach ($f in $NestedFiles) { Copy-ProtocolFile $f }

# Copy the .agentic directory tree (rules, memory, templates, scripts).
Get-ChildItem -Path (Join-Path $SourceDir ".agentic") -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($SourceDir.Length + 1)
    Copy-ProtocolFile $rel
}

Write-Host ""
Write-Host "Done: $($script:Copied) file(s) installed, $($script:Skipped) skipped."
Write-Host "Next: commit these files, then fill in .agentic/ARCHITECTURE.md for this project."
