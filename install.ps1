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

.PARAMETER PruneUnverifiedLegacy
    Remove v1.0 legacy files whose content cannot be proven to be framework
    material. Every such file is backed up to .agentic-backup/ first. Without
    this flag unverifiable legacy files are preserved as conflicts.

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
    [switch] $PruneUnverifiedLegacy,
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
  -PruneUnverifiedLegacy Remove v1.0 legacy files whose content cannot be
                         proven framework material. Backs each up first.
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

# Path semantics must match the underlying filesystem: PowerShell's default
# comparison operators are case-insensitive, which is correct on Windows but
# unsafe on a case-sensitive Unix filesystem (a forged ".agentic/version" row
# must never be treated as the canonical ".agentic/VERSION"). Every path-keyed
# comparison, set, and dictionary below uses these instead.
$script:PathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
$script:PathComparer = if ($IsWindows) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
# Manifest category labels are fixed ASCII tokens ("managed"/"merge"/"seed");
# they are always compared case-sensitively, on every platform.
$script:CategoryComparison = [System.StringComparison]::Ordinal
$script:CategoryComparer = [System.StringComparer]::Ordinal

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
    ".agentic/profiles/README.md",
    ".agentic/profiles/prototype.md",
    ".agentic/profiles/standard.md",
    ".agentic/profiles/high-assurance.md",
    ".agentic/scripts/verify.sh",
    ".agentic/scripts/verify.ps1",
    ".agentic/scripts/validate-task.sh",
    ".agentic/scripts/validate-task.ps1",
    ".agentic/templates/FEATURE_SPEC.md",
    ".agentic/templates/BUG_REPORT.md",
    ".agentic/templates/REFACTOR_PLAN.md",
    ".agentic/templates/task.md",
    ".agentic/templates/checks.tsv",
    ".agentic/tasks/README.md",
    ".agentic/decisions/README.md",
    ".agentic/schemas/verification-result-v1.schema.json",
    ".agentic/schemas/task-validation-result-v1.schema.json"
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
# -Uninstall remove a legacy file only when its content can be proven to be a
# v1.0 framework artifact (see Test-LegacyOwned). Legacy directories can hold
# user settings, so they are always report-only and never auto-removed.
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

# SHA-256 of the exact v1.0 shipped content (bytes of the v1.0.0 release).
# A checksum match proves the file is untouched framework material. Content
# that does not match byte-for-byte (for example after line-ending conversion)
# still matches the framework signature via Test-LegacyOwned.
function Get-LegacyV10Checksum {
    param([string] $RelativePath)
    switch ($RelativePath) {
        ".cursorrules" { return "010c2059541568ccf8fb7cb09792f741810814d98534b0bc2bc186124187a0a7" }
        ".windsurfrules" { return "3d5dd1201a4cd96808da9099eeed85f310d41b00b7661e14e1e132b70651c1c8" }
        ".clinerules" { return "af90e132e56e8a782a16e6ec5a622564af639fae3f4e075b082c93e73628c099" }
        "CONVENTIONS.md" { return "b6e8886439aee9e5a34c10d67536dc5a75cc2e548c2914ed4ae5946e15b3ea20" }
        ".github/copilot-instructions.md" { return "3f99180659e22a3bf7a707cb36e39bd41e033b217576193aab101279fe5ceda2" }
    }
    return $null
}

# Canonical path -> category registry, built independent of the current tool
# selection so that deselected adapters remain validatable (a deselected
# CLAUDE.md must still be recognized and pruned safely). The category recorded
# in the manifest must match exactly: a known path carrying the wrong valid
# category is tampering (e.g. CLAUDE.md recorded as managed would let prune
# delete the entire file instead of only its managed block). Legacy paths and
# the manifest itself are deliberately absent: they are never legitimate
# managed / merge / seed records.
$MergePaths = @("AGENTS.md", "CLAUDE.md", "GEMINI.md")
$SeedPaths = @(".agentic/ARCHITECTURE.md", ".agentic/STATUS.md", ".agentic/checks.tsv")
$ManagedPaths = @()
foreach ($f in $ManagedFiles) {
    if ($f -notin $ManagedPaths) { $ManagedPaths += $f }
}
if (".aider.conf.yml" -notin $ManagedPaths) { $ManagedPaths += ".aider.conf.yml" }

# Comparer-backed sets for category membership and duplicate detection. Built
# once here so every manifest validation and prune decision uses the same
# platform-appropriate comparison instead of PowerShell's default
# case-insensitive -in / -eq operators.
$script:MergePathSet = [System.Collections.Generic.HashSet[string]]::new($script:PathComparer)
$script:SeedPathSet = [System.Collections.Generic.HashSet[string]]::new($script:PathComparer)
$script:ManagedPathSet = [System.Collections.Generic.HashSet[string]]::new($script:PathComparer)
foreach ($p in $MergePaths)   { $script:MergePathSet.Add($p) | Out-Null }
foreach ($p in $SeedPaths)    { $script:SeedPathSet.Add($p) | Out-Null }
foreach ($p in $ManagedPaths) { $script:ManagedPathSet.Add($p) | Out-Null }

# Returns the one legitimate category for a canonical manifest path, or $null
# when the path is not a framework-managed path at all. Membership uses the
# platform path comparer (Ordinal on Unix, OrdinalIgnoreCase on Windows) so a
# case-different path is never confused with a canonical framework path.
function Test-ManifestCategory {
    param([string] $RelativePath)
    $rel = ConvertTo-PortablePath $RelativePath
    if ($script:MergePathSet.Contains($rel))   { return "merge" }
    if ($script:SeedPathSet.Contains($rel))    { return "seed" }
    if ($script:ManagedPathSet.Contains($rel)) { return "managed" }
    return $null
}

$script:BackupDir = $null
# Scratch files are created lazily and only in a non-plan run: -Plan must
# never create snapshots or manifest scratch files, byte-for-byte read-only.
$script:ManifestTmp = $null
$script:SnapDir = $null
$script:TmpFiles = New-Object System.Collections.Generic.List[string]
$script:Changed = New-Object System.Collections.Generic.List[string]
$script:BackupExisted = Test-Path -LiteralPath (Join-Path $TargetDir ".agentic-backup")
$script:MergeStartIndex = -1
$script:MergeEndIndex = -1
if (-not $Plan) {
    $script:ManifestTmp = [System.IO.Path]::GetTempFileName()
    $script:SnapDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agentic-snap-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:SnapDir -Force | Out-Null
}

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
            if ($fields.Count -ge 3 -and $script:PathComparer.Equals((ConvertTo-PortablePath $fields[0]), $rel)) { return $fields[2] }
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
    }
    $flat = (ConvertTo-PortablePath $RelativePath).Replace('/', '_')
    Snapshot-File ".agentic-backup/$flat"
    Copy-AgenticFile $src ".agentic-backup/$flat"
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
        # Never restore through a path that now escapes the project (e.g. a
        # symlink/junction planted mid-transaction): skip it rather than write
        # outside. Restore-AgenticFile / Remove-AgenticFile recheck confinement
        # immediately before the operation and report failure.
        $dst = Join-Path $TargetDir $rel
        $snap = Join-Path $script:SnapDir ((ConvertTo-PortablePath $rel).Replace('/', '_'))
        if (Test-Path -LiteralPath "$snap.present") {
            if (-not (Restore-AgenticFile $snap $rel)) { continue }
        }
        else {
            if (-not (Remove-AgenticFile $rel)) { continue }
        }
    }
    # A failed fresh install can leave behind directories that did not exist
    # before (e.g. .agentic/). Remove any directory that became empty only
    # because of this transaction, walking up toward the project root.
    foreach ($rel in $script:Changed) {
        $dir = Split-Path -Parent (Join-Path $TargetDir $rel)
        while ($dir -and -not $dir.Equals($TargetDir, $script:PathComparison)) {
            if ($script:BackupDir -and $script:BackupExisted -and $dir.Equals($script:BackupDir, $script:PathComparison)) { break }
            Remove-AgenticEmptyDirectory $dir
            $parent = Split-Path -Parent $dir
            if (-not $parent -or $parent.Equals($dir, $script:PathComparison)) { break }
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

# Creates an unpredictable scratch file path next to $PrefixPath (same
# filesystem, so the final Move-Item is atomic) and records it for cleanup.
# Never a predictable ".agentic-tmp" name: concurrent installs cannot clobber
# each other, and a pre-existing "*.agentic-tmp" file is never touched.
function New-Tmp {
    param([string] $PrefixPath)
    $tmp = $null
    do {
        $tmp = $PrefixPath + "." + [System.IO.Path]::GetRandomFileName()
    } while (Test-Path -LiteralPath $tmp)
    $script:TmpFiles.Add($tmp)
    return $tmp
}

# Final rename for every staged write. The scratch file is destination-local
# (same filesystem) so this is a single atomic step; when the rename fails the
# temporary is removed immediately so a randomized scratch file containing
# project or framework content can never be left behind.
function Move-TempIntoPlace {
    param([string] $Temp, [string] $Destination)
    try {
        Move-Item -LiteralPath $Temp -Destination $Destination -Force
    }
    catch {
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Write-AgenticFile {
    param([string] $RelativePath, [string] $Content)
    if (-not (Assert-SafeDestination $RelativePath)) {
        Write-Host "ERROR: refusing to write '$RelativePath': destination is not safely inside the project root."
        throw "unsafe destination"
    }
    $dst = Join-Path $TargetDir $RelativePath
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = New-Tmp $dst
    [System.IO.File]::WriteAllText($tmp, $Content, [System.Text.UTF8Encoding]::new($false))
    Move-TempIntoPlace $tmp $dst
}

function Write-AgenticLines {
    param([string] $RelativePath, [string[]] $Lines)
    if (-not (Assert-SafeDestination $RelativePath)) {
        Write-Host "ERROR: refusing to write '$RelativePath': destination is not safely inside the project root."
        throw "unsafe destination"
    }
    $dst = Join-Path $TargetDir $RelativePath
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = New-Tmp $dst
    [System.IO.File]::WriteAllLines($tmp, $Lines, [System.Text.UTF8Encoding]::new($false))
    Move-TempIntoPlace $tmp $dst
}

# Atomic install write: asserts the destination is safe, then copies $Source
# onto a scratch file created next to the destination (same filesystem, so the
# final rename is a single atomic step). An interrupted copy can never expose a
# partially written destination, and a pre-existing destination is only ever
# replaced by rename. On Unix the source's permission bits are reapplied to the
# scratch file, so an installed `.agentic/scripts/verify.sh` keeps its
# executable bit. $RelativePath is relative to $TargetDir.
function Copy-AgenticFile {
    param([string] $Source, [string] $RelativePath)
    if (-not (Assert-SafeDestination $RelativePath)) {
        Write-Host "ERROR: refusing to write '$RelativePath': destination is not safely inside the project root."
        throw "unsafe destination"
    }
    $dst = Join-Path $TargetDir $RelativePath
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = New-Tmp $dst
    Copy-Item -LiteralPath $Source -Destination $tmp -Force
    if (-not $IsWindows) {
        $mode = (Get-Item -LiteralPath $Source -Force).UnixFileMode
        if ($null -ne $mode) {
            [System.IO.File]::SetUnixFileMode($tmp, $mode)
        }
    }
    Move-TempIntoPlace $tmp $dst
}

# Guarded removal: refuses a destination whose final component is a symlink or
# whose nearest existing ancestor resolves physically outside the project root.
# Used by prune, uninstall, legacy cleanup, and rollback. A missing destination
# is a no-op success (rm -f semantics), so rollback can remove a path that was
# created and then torn down within the same failed transaction.
function Remove-AgenticFile {
    param([string] $RelativePath)
    if (-not (Assert-SafeDestination $RelativePath)) {
        Write-Host "ERROR: refusing to remove '$RelativePath': destination is not safely inside the project root."
        return $false
    }
    $path = Join-Path $TargetDir $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return $true }
    try {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    }
    catch {
        Write-Host "ERROR: failed to remove '$RelativePath': $($_.Exception.Message)"
        return $false
    }
    return -not (Test-Path -LiteralPath $path)
}

# Atomic rollback restore: stages the snapshot next to the destination and
# renames it into place, preserving the snapshot's Unix mode (snapshot copies
# keep source modes, so rollback repairs both contents and executable bits).
# Never snapshots or backs up again, so it is safe to call from rollback.
function Restore-AgenticFile {
    param([string] $Snapshot, [string] $RelativePath)
    if (-not (Assert-SafeDestination $RelativePath)) { return $false }
    $dst = Join-Path $TargetDir $RelativePath
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = New-Tmp $dst
    try {
        Copy-Item -LiteralPath $Snapshot -Destination $tmp -Force
        if (-not $IsWindows) {
            $mode = (Get-Item -LiteralPath $Snapshot -Force).UnixFileMode
            if ($null -ne $mode) {
                [System.IO.File]::SetUnixFileMode($tmp, $mode)
            }
        }
        Move-TempIntoPlace $tmp $dst
    }
    catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }
    return $true
}

# Removes one empty directory, but only after confirming its physical location
# stays inside the project root and that it is not itself a reparse point, so a
# linked directory can never be emptied from outside. Never touches a
# non-empty directory (rmdir semantics).
function Remove-AgenticEmptyDirectory {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.PSIsContainer) { return }
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return }
    try {
        $resolved = Resolve-PhysicalPath $Path
        $resolvedRoot = Resolve-PhysicalPath $TargetDir
    }
    catch { return }
    $rootTrimmed = $resolvedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $rootTrimmed + [System.IO.Path]::DirectorySeparatorChar
    $insideRoot = $resolved.Equals($rootTrimmed, $script:PathComparison) -or
        $resolved.StartsWith($rootPrefix, $script:PathComparison)
    if (-not $insideRoot) { return }
    if (@([System.IO.Directory]::GetFileSystemEntries($Path)).Count -gt 0) { return }
    try { [System.IO.Directory]::Delete($Path, $false) }
    catch { }
}

function Install-Managed {
    param([string] $RelativePath)
    $src = Join-Path $SourceDir $RelativePath
    $dst = Join-Path $TargetDir $RelativePath

    if (-not (Test-Path -LiteralPath $dst)) {
        if ($script:Plan) { Write-Host "  copy   $RelativePath (create)"; return }
        Snapshot-File $RelativePath
        Copy-AgenticFile $src $RelativePath
        Write-Host "  copy   $RelativePath (create)"
        Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $dst)
        return
    }

    if ($script:ReplaceManaged) {
        if ($script:Plan) { Write-Host "  copy   $RelativePath (replace: -ReplaceManaged)"; return }
        Snapshot-File $RelativePath
        if ($Backup) { Backup-File $RelativePath }
        Copy-AgenticFile $src $RelativePath
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
            Copy-AgenticFile $src $RelativePath
            Write-Host "  update $RelativePath (unchanged since last install)"
            Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $dst)
        }
        else {
            if ($script:Plan) { Write-Host "  conflict $RelativePath (modified since install; candidate: $RelativePath.new)"; return }
            Snapshot-File $RelativePath
            Snapshot-File "$RelativePath.new"
            Copy-AgenticFile $src "$RelativePath.new"
            Write-Host "  conflict $RelativePath (modified since install; wrote $RelativePath.new)"
            Add-ManifestEntry $RelativePath "managed" (Get-FileChecksum $src)
        }
    }
    else {
        if ($script:Plan) { Write-Host "  conflict $RelativePath (pre-existing; candidate: $RelativePath.new)"; return }
        Snapshot-File $RelativePath
        Snapshot-File "$RelativePath.new"
        Copy-AgenticFile $src "$RelativePath.new"
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
    Copy-AgenticFile $src $RelativePath
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

    switch (Get-MergeState $RelativePath) {
        "absent" {
            if ($script:Plan) { Write-Host "  merge  $RelativePath (create)"; return }
            Snapshot-File $RelativePath
            Copy-AgenticFile $src $RelativePath
            Write-Host "  merge  $RelativePath (create)"
            Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
        }
        "empty" {
            if ($script:Plan) { Write-Host "  merge  $RelativePath (create)"; return }
            Snapshot-File $RelativePath
            Copy-AgenticFile $src $RelativePath
            Write-Host "  merge  $RelativePath (create)"
            Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
        }
        "malformed" {
            if ($script:Plan) { Write-Host "  conflict $RelativePath (malformed merge markers)"; return }
            Snapshot-File $RelativePath
            Snapshot-File "$RelativePath.new"
            Copy-AgenticFile $src "$RelativePath.new"
            Write-Host "  conflict $RelativePath (malformed merge markers detected; wrote $RelativePath.new)"
            Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $src)
        }
        "plain" {
            if ($script:Plan) { Write-Host "  merge  $RelativePath (insert managed block above existing content)"; return }
            Snapshot-File $RelativePath
            if ($Backup) { Backup-File $RelativePath }
            $existing = Get-Content -Raw -LiteralPath $dst
            $newContent = $srcContent + "`n`n---`n`n" + $existing.TrimStart()
            Write-AgenticFile $RelativePath $newContent
            Write-Host "  merge  $RelativePath (managed block inserted, existing content preserved)"
            Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
        }
        "valid" {
            if ($script:Plan) { Write-Host "  merge  $RelativePath (update managed block, preserve custom content)"; return }
            Snapshot-File $RelativePath
            if ($Backup) { Backup-File $RelativePath }
            $existing = Get-Content -Raw -LiteralPath $dst
            $newContent = $existing.Substring(0, $script:MergeStartIndex) +
                $srcContent + "`n" + $existing.Substring($script:MergeEndIndex + $EndMarker.Length)
            Write-AgenticFile $RelativePath $newContent
            Write-Host "  merge  $RelativePath (managed block updated, custom content preserved)"
            Add-ManifestEntry $RelativePath "merge" (Get-FileChecksum $dst)
        }
    }
}

# ---------------------------------------------------------------------------
# Shared merge-marker parsing. Both Install-Merge and the prune/uninstall path
# classify a merge file the same way so their behavior can never diverge:
#   absent    file does not exist
#   empty     file exists but has no non-whitespace content
#   plain     file has content but no framework markers
#   valid     exactly one start + one end marker, end after start
#   malformed any other marker arrangement (never rewritten in place)
# Get-MergeState sets $script:MergeStartIndex / $script:MergeEndIndex to the
# character offsets of the first start/end marker for a valid block.
# ---------------------------------------------------------------------------
function Get-MergeState {
    param([string] $RelativePath)
    $dst = Join-Path $TargetDir $RelativePath
    if (-not (Test-Path -LiteralPath $dst)) { return "absent" }
    $existing = Get-Content -Raw -LiteralPath $dst
    $startMatches = [regex]::Matches($existing, [regex]::Escape($StartMarker))
    $endMatches = [regex]::Matches($existing, [regex]::Escape($EndMarker))
    $startCount = $startMatches.Count
    $endCount = $endMatches.Count
    $firstStart = $startMatches | Select-Object -First 1
    $firstEnd = $endMatches | Select-Object -First 1
    $script:MergeStartIndex = if ($firstStart) { $firstStart.Index } else { -1 }
    $script:MergeEndIndex = if ($firstEnd) { $firstEnd.Index } else { -1 }
    $malformed = $startCount -gt 1 -or $endCount -gt 1 -or
        ($startCount -eq 1 -and $endCount -eq 0) -or
        ($startCount -eq 0 -and $endCount -eq 1) -or
        ($startCount -eq 1 -and $endCount -eq 1 -and $script:MergeEndIndex -le $script:MergeStartIndex)
    if ($malformed) { return "malformed" }
    if ($startCount -eq 1 -and $endCount -eq 1) { return "valid" }
    if ([string]::IsNullOrWhiteSpace($existing)) { return "empty" }
    return "plain"
}

# True when removing the managed block from $RelativePath would leave no
# non-whitespace content behind. Read-only: lets -Plan report the would-be
# outcome without modifying the file.
function Test-MergeRemainderBlank {
    param([string] $RelativePath)
    $state = Get-MergeState $RelativePath
    if ($state -ne "valid") { return $false }
    $existing = Get-Content -Raw -LiteralPath (Join-Path $TargetDir $RelativePath)
    $remainder = $existing.Substring(0, $script:MergeStartIndex) +
        $existing.Substring($script:MergeEndIndex + $EndMarker.Length)
    return [string]::IsNullOrWhiteSpace($remainder)
}

# ---------------------------------------------------------------------------
# Previous-manifest validation. The manifest is the record of what this
# installer may later prune or replace; it is never trusted implicitly. A
# malformed entry hard-fails the run before anything is written, so a tampered
# or adversarial manifest can never steer the installer into removing files
# outside its documented scope.
# ---------------------------------------------------------------------------

# Follows every path segment so a symlink/junction inside the project that
# points outside resolves to its physical target, not its lexical path.
function Resolve-PhysicalPath {
    param([string] $Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    $current = $root
    $parts = $full.Substring($root.Length) -split '[/\\]' | Where-Object { $_ -ne '' }
    $maxHops = 32
    foreach ($part in $parts) {
        $current = Join-Path $current $part
        $seen = [System.Collections.Generic.HashSet[string]]::new($script:PathComparer)
        $hops = 0
        while ($true) {
            $key = [System.IO.Path]::GetFullPath($current)
            if (-not $seen.Add($key)) {
                throw "symbolic-link cycle detected while resolving '$Path'"
            }
            if ($hops -gt $maxHops) {
                throw "symbolic-link chain exceeds $maxHops hops while resolving '$Path'"
            }
            $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
            if (-not $item -or [string]::IsNullOrEmpty($item.Target)) { break }
            $hops++
            if ([System.IO.Path]::IsPathRooted($item.Target)) {
                $current = $item.Target
            }
            else {
                $parent = [System.IO.Path]::GetDirectoryName($current)
                if ([string]::IsNullOrEmpty($parent)) {
                    $parent = [System.IO.Path]::GetPathRoot($current)
                }
                $current = Join-Path $parent $item.Target
            }
        }
    }
    return [System.IO.Path]::GetFullPath($current)
}

# Lexical checks: a valid manifest path is relative, has no empty / "." / ".."
# segments, no drive-letter prefix, no backslashes, and no control characters.
function Test-LexicalManifestPath {
    param([string] $Path)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    if ($Path.Contains('\\')) { return $false }
    if ($Path -match '[\x00-\x1f\x7f]') { return $false }
    $p = ConvertTo-PortablePath $Path
    if ($p.StartsWith('/')) { return $false }
    if ($p -match '^[A-Za-z]:') { return $false }
    foreach ($seg in $p.Split('/')) {
        if ([string]::IsNullOrEmpty($seg) -or $seg -eq '.' -or $seg -eq '..') { return $false }
    }
    return $true
}

# True when $RelativePath stays physically at or beneath the physical project
# root. A symlinked directory inside the project that points outside, or a
# final component that is a symlink to an outside path, fails confinement.
# Paths whose parent does not exist cannot escape and are accepted.
function Test-PhysicalWithinRoot {
    param([string] $RelativePath)
    $full = Join-Path $TargetDir $RelativePath
    $parent = Split-Path -Parent $full
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    $isLink = $null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    if (-not ((Test-Path -LiteralPath $parent -PathType Container) -or $isLink)) { return $true }
    try {
        $resolved = Resolve-PhysicalPath $full
        $resolvedRoot = Resolve-PhysicalPath $TargetDir
    }
    catch { return $false }
    $rootTrimmed = $resolvedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $rootTrimmed + [System.IO.Path]::DirectorySeparatorChar
    return $resolved.Equals($rootTrimmed, $script:PathComparison) -or $resolved.StartsWith($rootPrefix, $script:PathComparison)
}

# Central write-confinement predicate. Returns $false for a destination
# $TargetDir/$rel when:
#   - the final component exists as a symlink/junction (a write would follow
#     it, and an in-project link is still an unexpected indirection for a
#     framework file), or
#   - the nearest existing ancestor resolves physically outside the project
#     root (e.g. .agentic -> /outside, even when the leaf does not exist yet).
# Paths whose ancestors do not exist cannot escape and are accepted.
function Assert-SafeDestination {
    param([string] $RelativePath)
    if ([string]::IsNullOrEmpty($RelativePath)) { return $false }
    $full = Join-Path $TargetDir $RelativePath
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return $false
    }
    $leaf = $full
    while (-not (Test-Path -LiteralPath $leaf)) {
        $parent = Split-Path -Parent $leaf
        if ([string]::IsNullOrEmpty($parent) -or $parent.Equals($leaf, $script:PathComparison)) { break }
        $leaf = $parent
    }
    try {
        $resolved = Resolve-PhysicalPath $leaf
        $resolvedRoot = Resolve-PhysicalPath $TargetDir
    }
    catch { return $false }
    $rootTrimmed = $resolvedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $rootTrimmed + [System.IO.Path]::DirectorySeparatorChar
    return $resolved.Equals($rootTrimmed, $script:PathComparison) -or $resolved.StartsWith($rootPrefix, $script:PathComparison)
}

# Validates the on-disk install manifest when one exists; throws on any
# malformed entry. Read-only, so it also runs under -Plan.
function Assert-PreviousManifestValid {
    $mf = Join-Path $TargetDir ".agentic\install-manifest.tsv"
    if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) { return }
    $lineNum = 0
    $seen = [System.Collections.Generic.HashSet[string]]::new($script:PathComparer)
    $first = $true
    foreach ($rawLine in Get-Content -LiteralPath $mf) {
        $lineNum++
        $line = $rawLine.TrimEnd("`r")
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }
        if ($first) {
            $first = $false
            if ($line -notmatch '^\d+\.\d+\.\d+$') {
                Write-Host "ERROR: install manifest line $lineNum is not a valid version header ('$line')."
                throw "invalid install manifest"
            }
            continue
        }
        $fields = $line -split "`t"
        if ($fields.Count -ne 3) {
            Write-Host "ERROR: install manifest line $lineNum is malformed (expected path<TAB>category<TAB>sha256)."
            throw "invalid install manifest"
        }
        $p = $fields[0]; $c = $fields[1]; $s = $fields[2]
        if ([string]::IsNullOrWhiteSpace($p) -or [string]::IsNullOrWhiteSpace($c) -or [string]::IsNullOrWhiteSpace($s)) {
            Write-Host "ERROR: install manifest line $lineNum is malformed (expected path<TAB>category<TAB>sha256)."
            throw "invalid install manifest"
        }
        $validCategory = $false
        foreach ($known in @("managed", "merge", "seed")) {
            if ($script:CategoryComparer.Equals($c, $known)) { $validCategory = $true; break }
        }
        if (-not $validCategory) {
            Write-Host "ERROR: install manifest line $lineNum has invalid category '$c' for '$p'."
            throw "invalid install manifest"
        }
        if ($s -notmatch '^[0-9a-f]{64}$') {
            Write-Host "ERROR: install manifest line $lineNum has invalid checksum for '$p'."
            throw "invalid install manifest"
        }
        if (-not (Test-LexicalManifestPath $p)) {
            Write-Host "ERROR: install manifest line $lineNum has invalid path '$p'."
            throw "invalid install manifest"
        }
        $norm = ConvertTo-PortablePath $p
        if (-not $seen.Add($norm)) {
            Write-Host "ERROR: install manifest line $lineNum has duplicate path '$p'."
            throw "invalid install manifest"
        }
        $expected = Test-ManifestCategory $p
        if (-not $expected) {
            Write-Host "ERROR: install manifest line $lineNum records path '$p', which is not a framework-managed path."
            throw "invalid install manifest"
        }
        if (-not $script:CategoryComparer.Equals($c, $expected)) {
            Write-Host "ERROR: install manifest line $lineNum records category '$c' for '$p'; expected '$expected'."
            throw "invalid install manifest"
        }
        if (-not (Test-PhysicalWithinRoot $p)) {
            Write-Host "ERROR: install manifest line $lineNum path '$p' escapes the project root."
            throw "invalid install manifest"
        }
    }
    if ($first) {
        Write-Host "ERROR: install manifest '$mf' contains no version header."
        throw "invalid install manifest"
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
    if ($script:PathComparer.Equals($rel, ".agentic/checks.tsv")) { return $true }
    foreach ($r in @($ManagedFiles + $SeedFiles + $MergeFiles)) {
        if ($script:PathComparer.Equals((ConvertTo-PortablePath $r), $rel)) { return $true }
    }
    return $false
}

function Test-BlankFile {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    return [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue))
}

# Removes the marker-delimited managed block from a merge file. Returns $true
# on success; $false when the markers are malformed (never rewritten). Shares
# the same merge classification as Install-Merge via Get-MergeState.
function Remove-MergeBlock {
    param([string] $RelativePath)
    if ((Get-MergeState $RelativePath) -ne "valid") { return $false }
    $dst = Join-Path $TargetDir $RelativePath
    $existing = Get-Content -Raw -LiteralPath $dst
    $newContent = $existing.Substring(0, $script:MergeStartIndex) +
        $existing.Substring($script:MergeEndIndex + $EndMarker.Length)
    Snapshot-File $RelativePath
    if ($Backup) { Backup-File $RelativePath }
    Write-AgenticFile $RelativePath $newContent
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
                switch (Get-MergeState $RelativePath) {
                    "empty" {
                        if ($script:Plan) { Write-Host "  prune  $RelativePath (empty file)"; return }
                        Snapshot-File $RelativePath
                        if ($Backup) { Backup-File $RelativePath }
                        if (-not (Remove-AgenticFile $RelativePath)) { throw "refusing to remove '$RelativePath': destination is not safely inside the project root" }
                        Write-Host "  prune  $RelativePath (empty file)"
                    }
                    "plain" {
                        Write-Host "  note   $RelativePath (no managed block found; custom content preserved)"
                    }
                    "malformed" {
                        Write-Host "  conflict $RelativePath (malformed merge markers; not pruned)"
                    }
                    "valid" {
                        if ($script:Plan) {
                            if (Test-MergeRemainderBlank $RelativePath) {
                                Write-Host "  prune  $RelativePath (managed block removed; file would be empty)"
                            }
                            else {
                                Write-Host "  prune  $RelativePath (managed block removed; custom content preserved)"
                            }
                            return
                        }
                        if (Remove-MergeBlock $RelativePath) {
                            if (Test-BlankFile $dst) {
                                Snapshot-File $RelativePath
                                if ($Backup) { Backup-File $RelativePath }
                                if (-not (Remove-AgenticFile $RelativePath)) { throw "refusing to remove '$RelativePath': destination is not safely inside the project root" }
                                Write-Host "  prune  $RelativePath (managed block removed; file removed)"
                            }
                            else {
                                Write-Host "  prune  $RelativePath (managed block removed; custom content preserved)"
                            }
                        }
                    }
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
                if (-not (Remove-AgenticFile $RelativePath)) { throw "refusing to remove '$RelativePath': destination is not safely inside the project root" }
                Write-Host "  prune  $RelativePath (unchanged since install)"
            }
            else {
                Write-Host "  conflict $RelativePath (modified since install; preserved)"
            }
        }
    }
}

# A legacy file is "owned" when its content can be proven to be v1.0
# framework material: byte-for-byte equal to the shipped v1.0 content, or
# carrying the framework signature text. A manifest record is never sufficient
# on its own: anything else may be a user-created file and is preserved as a
# conflict unless -PruneUnverifiedLegacy (which backs it up first) is given.
function Test-LegacyOwned {
    param([string] $RelativePath)
    $path = Join-Path $TargetDir $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $expected = Get-LegacyV10Checksum $RelativePath
    if ($expected -and (Get-FileChecksum $path) -eq $expected) { return $true }
    $content = Get-Content -Raw -LiteralPath $path -ErrorAction SilentlyContinue
    if ($content -match '@@AGENTIC-PROTOCOL-|Universal Agentic Development Protocol|\.agentic/Memory/') { return $true }
    return $false
}

# v1.0 adapter files are removed only by explicit -Prune/-Uninstall, and only
# when owned (or with an explicit backup under -PruneUnverifiedLegacy).
function Invoke-PruneLegacy {
    foreach ($f in $LegacyFiles) {
        $path = Join-Path $TargetDir $f
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if (Test-LegacyOwned $f) {
            if ($script:Plan) { Write-Host "  prune  $f (legacy v1.0 artifact)"; continue }
            Snapshot-File $f
            if ($Backup) { Backup-File $f }
            if (-not (Remove-AgenticFile $f)) { throw "refusing to remove '$f': destination is not safely inside the project root" }
            Write-Host "  prune  $f (legacy v1.0 artifact)"
        }
        elseif ($PruneUnverifiedLegacy) {
            if ($script:Plan) { Write-Host "  prune  $f (unverified legacy artifact; would back up to .agentic-backup first)"; continue }
            Snapshot-File $f
            Backup-File $f
            if (-not (Remove-AgenticFile $f)) { throw "refusing to remove '$f': destination is not safely inside the project root" }
            Write-Host "  prune  $f (unverified legacy artifact; backed up)"
        }
        else {
            Write-Host "  conflict $f (content could not be verified as a v1.0 framework artifact; preserved; use -PruneUnverifiedLegacy to remove)"
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
    Write-AgenticLines ".agentic/install-manifest.tsv" $lines
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
        if (-not (Remove-AgenticFile ".agentic/install-manifest.tsv")) { throw "refusing to remove '.agentic/install-manifest.tsv': destination is not safely inside the project root" }
        Write-Host "  prune  .agentic/install-manifest.tsv"
    }
    if ($script:Plan) {
        Write-Host "  note   empty framework directories under .agentic/ would be removed"
    }
    else {
        # Seed files keep .agentic/ and its project-owned contents alive; only
        # directories emptied by managed-file removal are cleaned up. The
        # confinement guard rejects a linked .agentic so enumeration never
        # descends into an external tree.
        if (Assert-SafeDestination ".agentic") {
            Get-ChildItem -LiteralPath (Join-Path $TargetDir ".agentic") -Directory -Recurse -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object { Remove-AgenticEmptyDirectory $_.FullName }
        }
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

# Runs stack detection and writes (or, when nothing is detected, removes)
# .agentic/checks.generated.tsv through the confined destination-local atomic
# primitives. The verifier's own -DetectChecks mode is deliberately not invoked
# for the write: it uses New-Item/Remove-Item/Move-Item on system-temp paths
# that are neither confined to the project root nor destination-local.
# Detection output is captured on stdout (-EmitChecks) and staged next to the
# candidate, validated, then renamed into place.
function Write-GeneratedCandidate {
    $genRel = ".agentic/checks.generated.tsv"
    if (-not (Assert-SafeDestination $genRel)) {
        Write-Host "ERROR: refusing to write '$genRel': destination is not safely inside the project root."
        throw "unsafe destination"
    }
    $dst = Join-Path $TargetDir $genRel
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp = New-Tmp $dst
    $verify = Join-Path $SourceDir ".agentic\scripts\verify.ps1"
    $detection = @()
    $emitExit = 0
    Push-Location $TargetDir
    try {
        $detection = @(& $verify -EmitChecks)
        $emitExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($emitExit -ne 0) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "verify.ps1 -EmitChecks failed with exit code $emitExit"
    }
    if ($detection.Count -gt 0) {
        $lines = @(
            "# .agentic/checks.generated.tsv — candidate verification contract."
            "# Auto-generated by detection workflow. Review assumptions and promote to .agentic/checks.tsv"
        ) + $detection
        [System.IO.File]::WriteAllLines($tmp, $lines, [System.Text.UTF8Encoding]::new($false))
        Push-Location $TargetDir
        try {
            Invoke-CheckedScript { & $verify -ValidateChecks $tmp } "verify.ps1 -ValidateChecks $tmp"
        }
        catch {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            throw
        }
        finally {
            Pop-Location
        }
        Move-TempIntoPlace $tmp $dst
        Write-Host "Candidate contract written to $genRel"
    }
    else {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if (-not (Remove-AgenticFile $genRel)) {
            throw "Failed to remove stale generated candidate '$genRel'."
        }
        Write-Host "No stack detected. Removed stale candidate '$genRel'."
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
    Write-GeneratedCandidate
    $gen = Join-Path $TargetDir ".agentic/checks.generated.tsv"
    if (-not (Test-Path -LiteralPath $gen)) {
        Write-Host "  note   no stack detected; $rel not generated"
        return
    }
    Snapshot-File $rel
    if ($Backup -and (Test-Path -LiteralPath $dst)) { Backup-File $rel }
    Copy-AgenticFile $gen $rel
    Write-Host "  gen    $rel (from detected stack)"
}

function Write-Manifest {
    if ($script:Plan) { return }
    Snapshot-File ".agentic/install-manifest.tsv"
    $lines = @(
        "# agentic-workflow install manifest (auto-generated)"
        "# path<TAB>category<TAB>sha256"
        $ProtocolVersion
    )
    $lines += Get-Content -LiteralPath $script:ManifestTmp
    Write-AgenticLines ".agentic/install-manifest.tsv" $lines
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
    # The previous manifest is validated before anything else, in every mode
    # including -Plan: a tampered or adversarial manifest hard-fails the run
    # before any file is created, modified, or removed.
    Assert-PreviousManifestValid

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
        # Snapshot so a failed detection rolls the candidate back to its prior
        # state (or removes a freshly created one) instead of leaving a partial
        # file behind.
        Snapshot-File ".agentic/checks.generated.tsv"
        Write-GeneratedCandidate
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
        Copy-AgenticFile $gen $rel
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
    exit 0
}
catch {
    Write-Host "ERROR: installation failed: $($_.Exception.Message)"
    Restore-PreviousState
    exit 1
}
finally {
    if ($script:SnapDir) { Remove-Item -Recurse -Force $script:SnapDir -ErrorAction SilentlyContinue }
    if ($script:ManifestTmp) { Remove-Item -LiteralPath $script:ManifestTmp -Force -ErrorAction SilentlyContinue }
    foreach ($t in $script:TmpFiles) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue }
}