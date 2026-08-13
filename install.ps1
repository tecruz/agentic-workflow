#Requires -Version 7.0
<#
.SYNOPSIS
    install.ps1 — Install the Universal Agentic Development Protocol into a project.

.DESCRIPTION
    File ownership model:

      managed   Framework files. On update they are replaced only when unchanged
                since the last install; if the adopter modified them, a conflict
                is reported and a `.new` candidate is written. --ReplaceManaged
                forces replacement. Project-owned files are never touched.
      seed      Project-owned templates (ARCHITECTURE.md, checks.tsv, STATUS.md,
                task/decision files). Never overwritten after creation.
      merge     AGENTS.md / CLAUDE.md / GEMINI.md. A bounded managed block is
                added or updated; any other content in the file is preserved.

.PARAMETER Target
    Project directory to install into (default: current directory).

.PARAMETER Plan
    Show what would be done without changing anything.

.PARAMETER Update
    Update an existing installation (the default whenever an install manifest
    is already present).

.PARAMETER Backup
    Back up files to .agentic-backup/ before modifying.

.PARAMETER Tools
    Comma-separated tool adapters: claude,gemini,aider,all.
    Default: claude,gemini,aider. AGENTS.md is always installed; other tools
    read AGENTS.md natively.

.PARAMETER GenerateChecks
    Write .agentic/checks.tsv from the detected stack.

.PARAMETER ReplaceManaged
    Replace framework-managed files even when the adopter modified them.
    Never touches project-owned files.

.PARAMETER Force
    Deprecated alias for -ReplaceManaged.

.EXAMPLE
    ./install.ps1 -Target C:\projects\my-app
.EXAMPLE
    ./install.ps1 -Target C:\projects\my-app -Plan
.EXAMPLE
    ./install.ps1 -Target C:\projects\my-app -GenerateChecks -Tools all
#>

param(
    [string] $Target = ".",
    [switch] $Plan,
    [switch] $Update,
    [switch] $Backup,
    [string] $Tools = "claude,gemini,aider",
    [switch] $GenerateChecks,
    [switch] $ReplaceManaged,
    [switch] $Force
)

$ErrorActionPreference = "Stop"

if ($Force) { $ReplaceManaged = $true }

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProtocolVersion = (Get-Content -Raw -LiteralPath (Join-Path $SourceDir ".agentic\VERSION")).Trim()

if (-not (Test-Path -LiteralPath $Target)) {
    Write-Host "Error: target directory '$Target' does not exist."
    exit 1
}
$TargetDir = (Resolve-Path -LiteralPath $Target).Path

$ToolsList = @()
if ($Tools -eq "all") {
    $ToolsList = @("claude", "gemini", "aider")
}
else {
    $ToolsList = @($Tools -split ',')
}
foreach ($t in $ToolsList) {
    if ($t -notin @("claude", "gemini", "aider")) {
        Write-Host "Error: unknown tool '$t' (expected claude, gemini, aider, or all)."
        exit 2
    }
}

$StartMarker = '<!-- @@AGENTIC-PROTOCOL-START@@ -->'
$EndMarker = '<!-- @@AGENTIC-PROTOCOL-END@@ -->'

# Framework-managed files: replaced on update when unchanged, or via
# -ReplaceManaged. Never project memory/architecture/tasks/decisions.
$ManagedFiles = @(
    ".agentic/VERSION",
    ".agentic/WORKFLOW.md",
    ".agentic/rules/01-general-principles.md",
    ".agentic/rules/02-code-quality.md",
    ".agentic/rules/03-testing-verification.md",
    ".agentic/rules/04-git-conventions.md",
    ".agentic/rules/05-security-safety.md",
    ".agentic/scripts/verify.sh",
    ".agentic/scripts/verify.ps1",
    ".agentic/templates/FEATURE_SPEC.md",
    ".agentic/templates/BUG_REPORT.md",
    ".agentic/templates/REFACTOR_PLAN.md",
    ".agentic/templates/checks.tsv",
    ".agentic/tasks/README.md",
    ".agentic/decisions/README.md"
)

# Seed-once, project-owned: never overwritten after creation.
$SeedFiles = @(
    ".agentic/ARCHITECTURE.md",
    ".agentic/STATUS.md"
)

# Merge-managed: bounded managed block is added/updated, other content preserved.
$MergeFiles = @("AGENTS.md")

foreach ($t in $ToolsList) {
    switch ($t) {
        "claude" { $MergeFiles += "CLAUDE.md" }
        "gemini" { $MergeFiles += "GEMINI.md" }
        "aider"  { $ManagedFiles += ".aider.conf.yml" }
    }
}

$script:BackupDir = $null
$script:ManifestTmp = [System.IO.Path]::GetTempFileName()

function ConvertTo-PortablePath {
    param([string] $Path)
    return $Path.Replace('\', '/')
}

function Get-FileChecksum {
    param([string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-ManifestChecksum {
    param([string] $RelativePath)
    $rel = ConvertTo-PortablePath $RelativePath
    $mf = Join-Path $TargetDir ".agentic\install-manifest.tsv"
    if (Test-Path -LiteralPath $mf) {
        foreach ($line in Get-Content -LiteralPath $mf) {
            $fields = $line -split "`t"
            if ($fields.Count -ge 3 -and (ConvertTo-PortablePath $fields[0]) -eq $rel) { return $fields[2] }
        }
    }
    return $null
}

function Add-ManifestEntry {
    param([string] $RelativePath, [string] $Category, [string] $Checksum)
    Add-Content -LiteralPath $script:ManifestTmp -Value ("{0}`t{1}`t{2}" -f (ConvertTo-PortablePath $RelativePath), $Category, $Checksum)
}

function Backup-File {
    param([string] $RelativePath)
    $src = Join-Path $TargetDir $RelativePath
    if (-not $script:BackupDir) {
        $script:BackupDir = Join-Path $TargetDir ".agentic-backup"
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }
    $flat = (ConvertTo-PortablePath $RelativePath).Replace('/', '_')
    Copy-Item -LiteralPath $src -Destination (Join-Path $script:BackupDir $flat) -Force
    Write-Host "  backup $RelativePath -> .agentic-backup/$flat"
}

function Write-Utf8NoBom {
    param([string] $Path, [string] $Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Install-Managed {
    param([string] $RelativePath)
    $src = Join-Path $SourceDir $RelativePath
    $dst = Join-Path $TargetDir $RelativePath

    if (-not (Test-Path -LiteralPath $dst)) {
        if ($script:Plan) { Write-Host "  copy   $RelativePath (create)"; return }
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "  copy   $RelativePath (create)"
        Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $dst)
        return
    }

    if ($script:ReplaceManaged) {
        if ($script:Plan) { Write-Host "  copy   $RelativePath (replace: -ReplaceManaged)"; return }
        if ($Backup) { Backup-File $RelativePath }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "  copy   $RelativePath (replaced: -ReplaceManaged)"
        Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $dst)
        return
    }

    $prev = Read-ManifestChecksum $RelativePath
    if ($prev) {
        $cur = Get-FileChecksum $dst
        if ($prev -eq $cur) {
            if ($script:Plan) { Write-Host "  update $RelativePath (unchanged since last install)"; return }
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Host "  update $RelativePath (unchanged since last install)"
            Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $dst)
        }
        else {
            if ($script:Plan) { Write-Host "  conflict $RelativePath (modified since install; candidate: $RelativePath.new)"; return }
            Copy-Item -LiteralPath $src -Destination "$dst.new" -Force
            Write-Host "  conflict $RelativePath (modified since install; wrote $RelativePath.new)"
            Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $src)
        }
    }
    else {
        if ($script:Plan) { Write-Host "  conflict $RelativePath (pre-existing; candidate: $RelativePath.new)"; return }
        Copy-Item -LiteralPath $src -Destination "$dst.new" -Force
        Write-Host "  conflict $RelativePath (pre-existing; wrote $RelativePath.new; use -ReplaceManaged to overwrite)"
        Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $src)
    }
}

function Install-Seed {
    param(
        [string] $RelativePath,
        [string] $SourcePath = $null
    )
    $src = if ($SourcePath) { $SourcePath } else { Join-Path $SourceDir $RelativePath }
    $dst = Join-Path $TargetDir $RelativePath

    if (Test-Path -LiteralPath $dst) {
        if ($script:Plan) { Write-Host "  skip   $RelativePath (project-owned; never overwritten)"; return }
        Write-Host "  skip   $RelativePath (project-owned; never overwritten)"
        Add-ManifestEntry $RelativePath "seed" (Get-FileChecksum $dst)
        return
    }
    if ($script:Plan) { Write-Host "  seed   $RelativePath (create)"; return }
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  seed   $RelativePath (create)"
    Add-ManifestEntry $RelativePath "seed" (Get-FileChecksum $dst)
}

# checks.tsv is special: on a fresh install it seeds the generic template from
# .agentic/templates/checks.tsv, unless -GenerateChecks already produced a
# stack-generated file. Existing files are always treated as project-owned.
function Install-CheckList {
    $rel = ".agentic/checks.tsv"
    $dst = Join-Path $TargetDir $rel
    if (Test-Path -LiteralPath $dst) {
        if ($script:Plan) { Write-Host "  skip   $rel (project-owned; never overwritten)"; return }
        Write-Host "  skip   $rel (project-owned; never overwritten)"
        Add-ManifestEntry $rel "seed" (Get-FileChecksum $dst)
        return
    }
    Install-Seed -RelativePath $rel -SourcePath (Join-Path $SourceDir ".agentic\templates\checks.tsv")
}

function Install-Merge {
    param([string] $RelativePath)
    $src = Join-Path $SourceDir $RelativePath
    $dst = Join-Path $TargetDir $RelativePath
    $srcContent = (Get-Content -Raw -LiteralPath $src).TrimEnd()

    if (-not (Test-Path -LiteralPath $dst)) {
        if ($script:Plan) { Write-Host "  merge  $RelativePath (create)"; return }
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Write-Utf8NoBom $dst $srcContent
        Write-Host "  merge  $RelativePath (create)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
        return
    }

    $existing = Get-Content -Raw -LiteralPath $dst
    $startIdx = $existing.IndexOf($StartMarker)
    $endIdx = if ($startIdx -ge 0) { $existing.IndexOf($EndMarker, $startIdx) } else { -1 }

    if ($startIdx -ge 0 -and $endIdx -gt $startIdx) {
        if ($script:Plan) { Write-Host "  merge  $RelativePath (update managed block, preserve custom content)"; return }
        if ($Backup) { Backup-File $RelativePath }
        $newContent = $existing.Substring(0, $startIdx) + $srcContent + "`n" + $existing.Substring($endIdx + $EndMarker.Length)
        Write-Utf8NoBom $dst $newContent
        Write-Host "  merge  $RelativePath (managed block updated, custom content preserved)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($existing)) {
        if ($script:Plan) { Write-Host "  merge  $RelativePath (insert managed block above existing content)"; return }
        if ($Backup) { Backup-File $RelativePath }
        $newContent = $srcContent + "`n`n---`n`n" + $existing.TrimStart()
        Write-Utf8NoBom $dst $newContent
        Write-Host "  merge  $RelativePath (managed block inserted, existing content preserved)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
    }
    else {
        if ($script:Plan) { Write-Host "  merge  $RelativePath (create)"; return }
        Write-Utf8NoBom $dst $srcContent
        Write-Host "  merge  $RelativePath (create)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
    }
}

function New-Checks {
    $dst = Join-Path $TargetDir ".agentic\checks.tsv"
    if ((Test-Path -LiteralPath $dst) -and (-not $script:ReplaceManaged)) {
        Write-Host "  skip   .agentic/checks.tsv (already exists; use -ReplaceManaged to overwrite)"
        return
    }
    if ($script:Plan) { Write-Host "  gen    .agentic/checks.tsv (from detected stack)"; return }

    $verify = Join-Path $SourceDir ".agentic\scripts\verify.ps1"
    $checks = @()
    Push-Location $TargetDir
    try {
        $checks = @(& $verify -EmitChecks 2>$null)
    }
    finally {
        Pop-Location
    }
    if ($checks.Count -eq 0) {
        Write-Host "  note   no stack detected; .agentic/checks.tsv not generated"
        return
    }
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $header = @(
        "# .agentic/checks.tsv — project-owned verification checks (authoritative)."
        "# Auto-generated by install.ps1 -GenerateChecks. Edit to match your definition of done."
    )
    [System.IO.File]::WriteAllLines($dst, ($header + $checks), [System.Text.UTF8Encoding]::new($false))
    Write-Host "  gen    .agentic/checks.tsv (from detected stack)"
}

function Write-Manifest {
    if ($script:Plan) { return }
    $mf = Join-Path $TargetDir ".agentic\install-manifest.tsv"
    $parent = Split-Path -Parent $mf
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $lines = @(
        "# agentic-workflow install manifest (auto-generated)"
        "# path<TAB>category<TAB>sha256"
        $ProtocolVersion
    )
    $lines += Get-Content -LiteralPath $script:ManifestTmp
    [System.IO.File]::WriteAllLines($mf, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Assert-NotPartial {
    $missing = $false
    if (-not (Test-Path -LiteralPath (Join-Path $TargetDir "AGENTS.md"))) {
        Write-Host "ERROR: AGENTS.md was not installed into '$TargetDir'."
        $missing = $true
    }
    foreach ($t in $ToolsList) {
        $rel = switch ($t) {
            "claude" { "CLAUDE.md" }
            "gemini" { "GEMINI.md" }
            "aider"  { ".aider.conf.yml" }
            default  { $null }
        }
        if ($rel -and -not (Test-Path -LiteralPath (Join-Path $TargetDir $rel))) {
            Write-Host "WARNING: tool '$t' was requested but '$rel' is not present" +
                " (a pre-existing file may have conflicted; review '$rel.new')."
        }
    }
    if ($missing) { exit 1 }
}

Write-Host "Installing Universal Agentic Development Protocol v$ProtocolVersion"
Write-Host "  from: $SourceDir"
Write-Host "  into: $TargetDir"
Write-Host "  tools: $($ToolsList -join ',')"
if ($Plan) { Write-Host "  mode: plan (dry run, nothing will be modified)" }
elseif ($Update) { Write-Host "  mode: update" }
Write-Host ""

foreach ($rel in $ManagedFiles) { Install-Managed $rel }
if ($GenerateChecks) { New-Checks }
foreach ($rel in $SeedFiles)    { Install-Seed $rel }
Install-CheckList
foreach ($rel in $MergeFiles)   { Install-Merge $rel }

Write-Manifest

if ($Plan) {
    Write-Host ""
    Write-Host "Plan complete — nothing was modified. Re-run without -Plan to apply."
    exit 0
}

Write-Host ""
Assert-NotPartial
Write-Host "Done. Review any '.new' conflict candidates, then commit the installed files."
Write-Host "Next: fill in .agentic/ARCHITECTURE.md for this project, and run ./.agentic/scripts/verify.ps1."