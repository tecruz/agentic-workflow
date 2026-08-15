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
    is already present). Files no longer managed (e.g. deselected tool
    adapters) are pruned; v1.0 legacy files are reported.

.PARAMETER Prune
    Remove obsolete framework files recorded by a previous install: managed
    files unchanged since install, managed blocks of deselected merge files,
    and v1.0 legacy files. Modified files are preserved as conflicts.

.PARAMETER Uninstall
    Remove the framework installation: managed files unchanged since install,
    managed blocks from merge files, the install manifest, and v1.0 legacy
    files. Project-owned seed files and custom merge content are preserved.

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

[CmdletBinding()]
param(
    [string] $Target = ".",
    [switch] $Help,
    [switch] $Plan,
    [switch] $Update,
    [switch] $Prune,
    [switch] $Uninstall,
    [switch] $Backup,
    [string] $Tools = "claude,gemini,aider",
    [switch] $GenerateChecks,
    [switch] $RegenerateChecks,
    [switch] $DetectChecks,
    [switch] $AcceptDetectedChecks,
    [switch] $ReplaceChecks,
    [switch] $ReplaceManaged,
    [switch] $Force
)

$ErrorActionPreference = "Stop"

if ($Help) {
    # Explicit usage summary so the installer never runs on -Help.
    Write-Host @"
install.ps1 — Install the Universal Agentic Development Protocol into a project.

Usage:
  ./install.ps1 [-Target <dir>] [options]

  -Target <dir>          Project directory to install into (default: current).
  -Tools <list>          Comma-separated adapters: claude,gemini,aider,all.
                         Default: claude,gemini,aider. AGENTS.md is always
                         installed; other tools read AGENTS.md natively.
  -Update                Update an existing install (default when a manifest
                         exists). Deselected adapters and renamed framework
                         files are pruned; v1.0 legacy files are reported.
  -Prune                 Remove obsolete framework files recorded by a previous
                         install plus v1.0 legacy files. Modified files are
                         preserved as conflicts.
  -Uninstall             Remove the framework: managed files, managed blocks
                         from merge files, the manifest, and v1.0 legacy files.
                         Project-owned seeds and custom merge content remain.
  -Plan                  Show what would be done without changing anything.
  -Backup                Back up files to .agentic-backup/ before modifying.
  -GenerateChecks        Write .agentic/checks.tsv from the detected stack.
  -DetectChecks          Write .agentic/checks.generated.tsv candidate.
  -AcceptDetectedChecks  Validate and promote the reviewed candidate.
  -ReplaceManaged        Replace modified framework-managed files.
  -ReplaceChecks         Overwrite a project-owned .agentic/checks.tsv.
  -Help                  Show this usage summary.
"@
    exit 0
}

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

# v1.0 shipped per-tool adapter files that were removed in 2.x (AGENTS.md is
# the single canonical protocol). On update they are only reported; -Prune and
# -Uninstall remove the files. Legacy directories can hold user settings, so
# they are always report-only and never auto-removed.
$LegacyFiles = @(
    ".cursorrules",
    ".windsurfrules",
    ".clinerules",
    "CONVENTIONS.md",
    ".github/copilot-instructions.md"
)
$LegacyDirs = @(
    ".cursor",
    ".windsurf",
    "Memory"
)

$script:BackupDir = $null
$script:ManifestTmp = [System.IO.Path]::GetTempFileName()
$script:SnapDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-snap-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:SnapDir -Force | Out-Null
$script:Changed = New-Object System.Collections.Generic.List[string]
$script:BackupExisted = Test-Path -LiteralPath (Join-Path $TargetDir ".agentic-backup")

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
    Snapshot-File ".agentic-backup/$flat"
    Copy-Item -LiteralPath $src -Destination (Join-Path $script:BackupDir $flat) -Force
    Write-Host "  backup $RelativePath -> .agentic-backup/$flat"
}

# Transactional safety: every file about to be modified is snapshotted first;
# if the install fails partway through, Restore-PreviousState returns the
# target to its prior state instead of leaving a partial installation behind.
function Snapshot-File {
    param([string] $RelativePath)
    $dst = Join-Path $TargetDir $RelativePath
    $snap = Join-Path $script:SnapDir ((ConvertTo-PortablePath $RelativePath).Replace('/', '_'))
    # First snapshot wins: a path modified more than once in one transaction
    # must always be rolled back to its state before the transaction began.
    if ((Test-Path -LiteralPath $snap) -or
        (Test-Path -LiteralPath "$snap.present") -or
        (Test-Path -LiteralPath "$snap.absent")) { return }
    if (Test-Path -LiteralPath $dst) {
        Copy-Item -LiteralPath $dst -Destination $snap -Force
        [System.IO.File]::WriteAllText("$snap.present", "", [System.Text.UTF8Encoding]::new($false))
    }
    else {
        [System.IO.File]::WriteAllText("$snap.absent", "", [System.Text.UTF8Encoding]::new($false))
    }
    $script:Changed.Add($RelativePath)
}

function Restore-PreviousState {
    Write-Host "ERROR: installation failed; restoring '$TargetDir' to its prior state."
    foreach ($rel in $script:Changed) {
        $dst = Join-Path $TargetDir $rel
        $snap = Join-Path $script:SnapDir ((ConvertTo-PortablePath $rel).Replace('/', '_'))
        if (Test-Path -LiteralPath "$snap.present") {
            Copy-Item -LiteralPath $snap -Destination $dst -Force
        }
        else {
            Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath "$dst.agentic-tmp" -Force -ErrorAction SilentlyContinue
    }
    # A failed fresh install can leave behind directories that did not exist
    # before (e.g. .agentic/). Remove any directory that became empty only
    # because of this transaction, walking up toward the project root.
    foreach ($rel in $script:Changed) {
        $dir = Split-Path -Parent (Join-Path $TargetDir $rel)
        while ($dir -and -not $dir.Equals($TargetDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($script:BackupDir -and $script:BackupExisted -and $dir.Equals($script:BackupDir, [System.StringComparison]::OrdinalIgnoreCase)) { break }
            try { [System.IO.Directory]::Delete($dir, $false) }
            catch { break }
            $parent = Split-Path -Parent $dir
            if (-not $parent -or $parent.Equals($dir, [System.StringComparison]::OrdinalIgnoreCase)) { break }
            $dir = $parent
        }
    }
    if ($script:BackupDir -and -not $script:BackupExisted) {
        Remove-Item -Recurse -Force $script:BackupDir -ErrorAction SilentlyContinue
    }
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
        Snapshot-File $RelativePath
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "  copy   $RelativePath (create)"
        Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $dst)
        return
    }

    if ($script:ReplaceManaged) {
        if ($script:Plan) { Write-Host "  copy   $RelativePath (replace: -ReplaceManaged)"; return }
        Snapshot-File $RelativePath
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
            Snapshot-File $RelativePath
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Host "  update $RelativePath (unchanged since last install)"
            Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $dst)
        }
        else {
            if ($script:Plan) { Write-Host "  conflict $RelativePath (modified since install; candidate: $RelativePath.new)"; return }
            Snapshot-File $RelativePath
            Snapshot-File "$RelativePath.new"
            Copy-Item -LiteralPath $src -Destination "$dst.new" -Force
            Write-Host "  conflict $RelativePath (modified since install; wrote $RelativePath.new)"
            Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $src)
        }
    }
    else {
        if ($script:Plan) { Write-Host "  conflict $RelativePath (pre-existing; candidate: $RelativePath.new)"; return }
        Snapshot-File $RelativePath
        Snapshot-File "$RelativePath.new"
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
    Snapshot-File $RelativePath
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
        Snapshot-File $RelativePath
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Write-Utf8NoBom $dst $srcContent
        Write-Host "  merge  $RelativePath (create)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
        return
    }

    $existing = Get-Content -Raw -LiteralPath $dst
    $startCount = ([regex]::Matches($existing, [regex]::Escape($StartMarker))).Count
    $endCount = ([regex]::Matches($existing, [regex]::Escape($EndMarker))).Count
    $startIdx = $existing.IndexOf($StartMarker)
    $endIdx = if ($startIdx -ge 0) { $existing.IndexOf($EndMarker, $startIdx) } else { -1 }

    if ($startCount -gt 1 -or $endCount -gt 1 -or (($startCount -eq 1 -and $endCount -eq 0) -or ($startCount -eq 0 -and $endCount -eq 1) -or ($startCount -eq 1 -and $endCount -eq 1 -and $endIdx -le $startIdx))) {
        if ($script:Plan) { Write-Host "  conflict $RelativePath (malformed merge markers)"; return }
        Snapshot-File $RelativePath
        Snapshot-File "$RelativePath.new"
        Copy-Item -LiteralPath $src -Destination "$dst.new" -Force
        Write-Host "  conflict $RelativePath (malformed merge markers detected; wrote $RelativePath.new)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $src)
        return
    }

    if ($startIdx -ge 0 -and $endIdx -gt $startIdx) {
        if ($script:Plan) { Write-Host "  merge  $RelativePath (update managed block, preserve custom content)"; return }
        Snapshot-File $RelativePath
        if ($Backup) { Backup-File $RelativePath }
        $newContent = $existing.Substring(0, $startIdx) + $srcContent + "`n" + $existing.Substring($endIdx + $EndMarker.Length)
        Write-Utf8NoBom $dst $newContent
        Write-Host "  merge  $RelativePath (managed block updated, custom content preserved)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($existing)) {
        if ($script:Plan) { Write-Host "  merge  $RelativePath (insert managed block above existing content)"; return }
        Snapshot-File $RelativePath
        if ($Backup) { Backup-File $RelativePath }
        $newContent = $srcContent + "`n`n---`n`n" + $existing.TrimStart()
        Write-Utf8NoBom $dst $newContent
        Write-Host "  merge  $RelativePath (managed block inserted, existing content preserved)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
    }
    else {
        if ($script:Plan) { Write-Host "  merge  $RelativePath (create)"; return }
        Snapshot-File $RelativePath
        Write-Utf8NoBom $dst $srcContent
        Write-Host "  merge  $RelativePath (create)"
        Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
    }
}

# ---------------------------------------------------------------------------
# Migration, pruning, and uninstall. A previous install is described by the
# on-disk manifest; a file is obsolete when it is no longer in the desired set
# (for example a deselected tool adapter). Managed files are pruned only when
# unchanged since the recorded checksum; merge files are pruned by stripping
# the marker-delimited managed block and removing the file only if that leaves
# nothing behind. Seeds are project-owned and never pruned.
# ---------------------------------------------------------------------------

# Entries (path<TAB>category<TAB>sha256) recorded by a previous install.
function Get-PreviousManifestEntries {
    $mf = Join-Path $TargetDir ".agentic\install-manifest.tsv"
    if (-not (Test-Path -LiteralPath $mf)) { return }
    foreach ($line in Get-Content -LiteralPath $mf) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
        $fields = $line -split "`t"
        if ($fields.Count -ge 3) {
            [pscustomobject]@{
                Path     = ConvertTo-PortablePath $fields[0]
                Category = $fields[1]
                Checksum = $fields[2]
            }
        }
    }
}

# True when $RelativePath is part of the current desired set (including the
# seeded .agentic/checks.tsv, recorded under seed by Install-CheckList).
function Test-DesiredFile {
    param([string] $RelativePath)
    $rel = ConvertTo-PortablePath $RelativePath
    if ($rel -eq ".agentic/checks.tsv") { return $true }
    foreach ($r in @($ManagedFiles + $SeedFiles + $MergeFiles)) {
        if ((ConvertTo-PortablePath $r) -eq $rel) { return $true }
    }
    return $false
}

function Test-BlankFile {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    return [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue))
}

# Removes the marker-delimited managed block from a merge file. Returns $true
# on success; $false when the markers are malformed (never rewritten).
function Remove-MergeBlock {
    param([string] $RelativePath)
    $dst = Join-Path $TargetDir $RelativePath
    $existing = Get-Content -Raw -LiteralPath $dst
    $startIdx = $existing.IndexOf($StartMarker)
    $endIdx = if ($startIdx -ge 0) { $existing.IndexOf($EndMarker, $startIdx) } else { -1 }
    if ($startIdx -lt 0 -or $endIdx -le $startIdx) { return $false }
    $newContent = $existing.Substring(0, $startIdx) + $existing.Substring($endIdx + $EndMarker.Length)
    Snapshot-File $RelativePath
    if ($Backup) { Backup-File $RelativePath }
    Write-Utf8NoBom $dst $newContent
    return $true
}

# Removes a single obsolete entry.
function Invoke-PruneEntry {
    param(
        [string] $RelativePath,
        [string] $Category,
        [string] $Checksum
    )
    $dst = Join-Path $TargetDir $RelativePath
    switch ($Category) {
        "seed" {
            return
        }
        "merge" {
            if (Test-Path -LiteralPath $dst) {
                if (Remove-MergeBlock $RelativePath) {
                    if (Test-BlankFile $dst) {
                        if ($script:Plan) { Write-Host "  prune  $RelativePath (managed block removed; file would be empty)"; return }
                        Snapshot-File $RelativePath
                        if ($Backup) { Backup-File $RelativePath }
                        Remove-Item -LiteralPath $dst -Force
                        Write-Host "  prune  $RelativePath (managed block removed; file removed)"
                    }
                    else {
                        Write-Host "  prune  $RelativePath (managed block removed; custom content preserved)"
                    }
                }
                else {
                    Write-Host "  conflict $RelativePath (malformed merge markers; not pruned)"
                }
            }
        }
        "managed" {
            if (-not (Test-Path -LiteralPath $dst)) {
                Write-Host "  note   $RelativePath (already absent; nothing to prune)"
                return
            }
            $cur = Get-FileChecksum $dst
            if ($Checksum -eq $cur) {
                if ($script:Plan) { Write-Host "  prune  $RelativePath (unchanged since install)"; return }
                Snapshot-File $RelativePath
                if ($Backup) { Backup-File $RelativePath }
                Remove-Item -LiteralPath $dst -Force
                Write-Host "  prune  $RelativePath (unchanged since install)"
            }
            else {
                Write-Host "  conflict $RelativePath (modified since install; preserved)"
            }
        }
    }
}

# v1.0 adapter files are removed only by explicit -Prune/-Uninstall.
function Invoke-PruneLegacy {
    foreach ($f in $LegacyFiles) {
        $path = Join-Path $TargetDir $f
        if (Test-Path -LiteralPath $path) {
            if ($script:Plan) { Write-Host "  prune  $f (legacy v1.0 artifact)"; continue }
            Snapshot-File $f
            if ($Backup) { Backup-File $f }
            Remove-Item -LiteralPath $path -Force
            Write-Host "  prune  $f (legacy v1.0 artifact)"
        }
    }
    foreach ($f in $LegacyDirs) {
        if (Test-Path -LiteralPath (Join-Path $TargetDir $f)) {
            Write-Host "  note   legacy directory $f/ left in place (may contain user settings); remove manually if unused"
        }
    }
}

# Reports v1.0 legacy artifacts without touching them (used on plain update).
function Invoke-ReportLegacy {
    foreach ($f in @($LegacyFiles + $LegacyDirs)) {
        if (Test-Path -LiteralPath (Join-Path $TargetDir $f)) {
            Write-Host "  note   legacy $f (v1.0 artifact; run -Prune to remove)"
        }
    }
}

# Prunes every previous-manifest entry that is no longer desired. Used both as
# the migration step of an update and by the standalone -Prune operation.
function Invoke-PruneObsolete {
    foreach ($e in Get-PreviousManifestEntries) {
        if (-not (Test-DesiredFile $e.Path)) {
            Invoke-PruneEntry $e.Path $e.Category $e.Checksum
        }
    }
}

# Rewrites the manifest without the pruned entries (standalone -Prune path;
# the update path rebuilds the manifest from this install's records instead).
function Write-PruneManifest {
    if ($script:Plan) { return }
    $mf = Join-Path $TargetDir ".agentic\install-manifest.tsv"
    if (-not (Test-Path -LiteralPath $mf)) { return }
    Snapshot-File ".agentic/install-manifest.tsv"
    $lines = @(
        "# agentic-workflow install manifest (auto-generated)"
        "# path<TAB>category<TAB>sha256"
        $ProtocolVersion
    )
    foreach ($e in Get-PreviousManifestEntries) {
        if (Test-DesiredFile $e.Path) {
            $lines += ("{0}`t{1}`t{2}" -f $e.Path, $e.Category, $e.Checksum)
        }
    }
    [System.IO.File]::WriteAllLines($mf, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Uninstall {
    Write-Host ""
    Write-Host "Uninstalling Universal Agentic Development Protocol v$ProtocolVersion"
    Write-Host "  from: $TargetDir"
    Write-Host "  preserving project-owned seed files and custom merge content"
    Write-Host ""
    foreach ($e in Get-PreviousManifestEntries) {
        Invoke-PruneEntry $e.Path $e.Category $e.Checksum
    }
    Invoke-PruneLegacy
    $mf = Join-Path $TargetDir ".agentic\install-manifest.tsv"
    if (Test-Path -LiteralPath $mf) {
        if ($script:Plan) { Write-Host "  prune  .agentic/install-manifest.tsv"; return }
        Snapshot-File ".agentic/install-manifest.tsv"
        Remove-Item -LiteralPath $mf -Force
        Write-Host "  prune  .agentic/install-manifest.tsv"
    }
    if ($script:Plan) {
        Write-Host "  note   empty framework directories under .agentic/ would be removed"
    }
    else {
        # Seed files keep .agentic/ and its project-owned contents alive; only
        # directories emptied by managed-file removal are cleaned up. Remove
        # deepest-first so nested empty directories are also cleaned.
        Get-ChildItem -LiteralPath (Join-Path $TargetDir ".agentic") -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1) } |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
    }
}

function Invoke-CheckedScript {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [string] $Description
    )

    & $Action
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $Description"
    }
}

function New-Checks {
    $rel = ".agentic/checks.tsv"
    $dst = Join-Path $TargetDir $rel
    if ((Test-Path -LiteralPath $dst) -and (-not $RegenerateChecks) -and (-not $ReplaceChecks)) {
        if ($script:Plan) { Write-Host "  skip   $rel (project-owned; use -RegenerateChecks to overwrite)"; return }
        Write-Host "  skip   $rel (project-owned; use -ReplaceChecks to overwrite)"
        return
    }
    if ($script:Plan) { Write-Host "  gen    $rel (from detected stack)"; return }

    # Detection creates, replaces, or removes the generated candidate; snapshot
    # it before detection so a failed install restores a reviewed candidate (or
    # removes a freshly generated one) exactly as it was before this run.
    Snapshot-File ".agentic/checks.generated.tsv"
    $verify = Join-Path $SourceDir ".agentic\scripts\verify.ps1"
    Push-Location $TargetDir
    try {
        Invoke-CheckedScript { & $verify -DetectChecks } "verify.ps1 -DetectChecks"
    }
    finally {
        Pop-Location
    }
    $gen = Join-Path $TargetDir ".agentic/checks.generated.tsv"
    if (-not (Test-Path -LiteralPath $gen)) {
        Write-Host "  note   no stack detected; $rel not generated"
        return
    }
    Push-Location $TargetDir
    try {
        Invoke-CheckedScript { & $verify -ValidateChecks $gen } "verify.ps1 -ValidateChecks $gen"
    }
    finally {
        Pop-Location
    }
    Snapshot-File $rel
    if ($Backup -and (Test-Path -LiteralPath $dst)) { Backup-File $rel }
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $gen -Destination $dst -Force
    Write-Host "  gen    $rel (from detected stack)"
}

function Write-Manifest {
    if ($script:Plan) { return }
    Snapshot-File ".agentic/install-manifest.tsv"
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
    if ($missing) { throw "AGENTS.md was not installed into '$TargetDir'." }
}

Write-Host "Installing Universal Agentic Development Protocol v$ProtocolVersion"
Write-Host "  from: $SourceDir"
Write-Host "  into: $TargetDir"
Write-Host "  tools: $($ToolsList -join ',')"
if ($Plan) { Write-Host "  mode: plan (dry run, nothing will be modified)" }
elseif ($Update) { Write-Host "  mode: update" }
Write-Host ""

try {
    if ($Prune) {
        Invoke-PruneObsolete
        Invoke-PruneLegacy
        Write-PruneManifest
        Write-Host ""
        Write-Host "Prune complete. Seeds and project-owned files were preserved."
        exit 0
    }

    if ($Uninstall) {
        Invoke-Uninstall
        Write-Host ""
        Write-Host "Uninstall complete. Project-owned seed files (.agentic/ARCHITECTURE.md,"
        Write-Host "STATUS.md, checks.tsv, tasks/, decisions/) were left in place."
        exit 0
    }

    if ($DetectChecks) {
        if ($Plan) {
            Write-Host "=== Project Detection Explanation (Plan) ==="
            $verify = Join-Path $SourceDir ".agentic\scripts\verify.ps1"
            Push-Location $TargetDir
            try { & $verify -ExplainDetection } finally { Pop-Location }
            Write-Host "  gen    .agentic/checks.generated.tsv (from detected stack)"
            exit 0
        }
        $verify = Join-Path $SourceDir ".agentic\scripts\verify.ps1"
        Push-Location $TargetDir
        try { Invoke-CheckedScript { & $verify -DetectChecks } "verify.ps1 -DetectChecks" } finally { Pop-Location }
        exit 0
    }

    if ($AcceptDetectedChecks) {
        $gen = Join-Path $TargetDir ".agentic/checks.generated.tsv"
        $rel = ".agentic/checks.tsv"
        $dst = Join-Path $TargetDir $rel
        if (-not (Test-Path -LiteralPath $gen)) {
            Write-Host "Error: '$gen' does not exist. Run with -DetectChecks first."
            exit 1
        }
        if ((Test-Path -LiteralPath $dst) -and (-not $ReplaceChecks)) {
            if ($Plan) {
                Write-Host "  skip   $rel (project-owned; use -ReplaceChecks to overwrite)"
                exit 0
            }
            Write-Host "Error: '$dst' already exists. Use -ReplaceChecks to overwrite."
            exit 1
        }
        if ($Plan) {
            Write-Host "  promote $gen -> $rel"
            exit 0
        }
        $verify = Join-Path $SourceDir ".agentic\scripts\verify.ps1"
        Push-Location $TargetDir
        try { Invoke-CheckedScript { & $verify -ValidateChecks $gen } "verify.ps1 -ValidateChecks $gen" } finally { Pop-Location }

        Snapshot-File $rel
        if ($Backup -and (Test-Path -LiteralPath $dst)) { Backup-File $rel }
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $tmp = "$dst.agentic-tmp"
        Copy-Item -LiteralPath $gen -Destination $tmp -Force
        Move-Item -LiteralPath $tmp -Destination $dst -Force
        Write-Host "  promoted '$gen' to '$rel'"
        exit 0
    }

    foreach ($rel in $ManagedFiles) { Install-Managed $rel }
    if ($GenerateChecks) { New-Checks }
    foreach ($rel in $SeedFiles)    { Install-Seed $rel }
    Install-CheckList
    foreach ($rel in $MergeFiles)   { Install-Merge $rel }

    # Migration step of an update: files recorded by a previous install that are
    # no longer part of the desired set (deselected adapters, renamed framework
    # files) are pruned before the manifest is rewritten. Legacy v1.0 artifacts
    # are only reported here; -Prune/-Uninstall remove them explicitly.
    Invoke-PruneObsolete
    Invoke-ReportLegacy

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
}
catch {
    Write-Host "ERROR: installation failed: $($_.Exception.Message)"
    Restore-PreviousState
    exit 1
}
finally {
    Remove-Item -Recurse -Force $script:SnapDir -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:ManifestTmp -Force -ErrorAction SilentlyContinue
}