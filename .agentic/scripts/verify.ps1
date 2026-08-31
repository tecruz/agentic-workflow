#Requires -Version 7.0
<#
.SYNOPSIS
    verify.ps1 - Universal project verification script.

.DESCRIPTION
    Verifies a project using an explicit state model that cannot report false
    success:

      PASS        (exit 0)  At least one required check ran and all passed.
      FAIL        (exit 1)  A required check ran and failed.
      BLOCKED     (exit 2)  A project or check configuration was found, but the
                            required tooling/configuration was unavailable.
      UNSUPPORTED (exit 3)  No supported project or check configuration found.

    Invariant: PASS is impossible unless at least one required check actually
    ran.

    Checks are read from .agentic/checks.tsv (project-owned, authoritative)
    when that file defines at least one check. Otherwise the stack is
    auto-detected as a bootstrap mechanism only. Every command is executed as
    an argument array - never via Invoke-Expression.

    checks.tsv format (tab-separated; lines starting with `#` are comments):

      requirement<TAB>check-id<TAB>working-dir<TAB>executable<TAB>args...

      required<TAB>test<TAB>.<TAB>pnpm<TAB>test
      required<TAB>lint<TAB>.<TAB>pnpm<TAB>lint
      optional<TAB>format<TAB>.<TAB>pnpm<TAB>format:check

.PARAMETER EmitChecks
    Print the auto-detected checks.tsv and exit without running anything.

.EXAMPLE
    ./.agentic/scripts/verify.ps1
.EXAMPLE
    ./.agentic/scripts/verify.ps1 -EmitChecks
#>

param(
    [switch] $EmitChecks,
    [switch] $ExplainDetection,
    [switch] $DetectChecks,
    [string] $ValidateChecks,
    [ValidateSet('Text', 'Json')]
    [string] $Format = 'Text',
    [string] $Events = $null,
    [switch] $EventsForce
)

# JSON stdout and event streams are mutually exclusive output modes.
# Each output is reliable independently; combined use could produce
# contradictory terminal event vs process exit. Reject at parse time.
if ($Format -eq 'Json' -and $Events) {
    [Console]::Error.WriteLine("ERROR: -Format Json and -Events cannot be used together.")
    [Console]::Error.WriteLine("Use JSON stdout OR an event stream, not both.")
    exit 1
}

$script:Failed = $false
$script:Ran = 0
$script:RanRequired = $false
$script:Blocked = $false
$script:Detected = $false
$script:CheckResults = @()

function Write-Log {
    param([string] $Message)
    if ($Format -eq 'Json') {
        [Console]::Error.WriteLine($Message)
    }
    else {
        Write-Host $Message
    }
}

function Output-VerificationJson {
    param([string] $ResultStr, [int] $ExitCode)
    $passedCount = @($script:CheckResults | Where-Object { $_.status -eq 'PASS' }).Count
    # failed counts failed REQUIRED checks only; optional failures are reported
    # separately in optional_failed so a PASS run with a failing optional check
    # stays schema-valid (exit 0 requires failed = 0).
    $failedCount = @($script:CheckResults | Where-Object { $_.status -eq 'FAIL' -and $_.requirement -eq 'required' }).Count
    $optionalFailedCount = @($script:CheckResults | Where-Object { $_.status -eq 'FAIL' -and $_.requirement -eq 'optional' }).Count
    $blockedCount = @($script:CheckResults | Where-Object { $_.status -eq 'BLOCKED' }).Count
    $optionalSkipped = @($script:CheckResults | Where-Object { $_.status -eq 'SKIPPED_OPTIONAL' }).Count
    $requiredRun = @($script:CheckResults | Where-Object { $_.requirement -eq 'required' -and $_.status -in @('PASS', 'FAIL') }).Count
    $checksRun = @($script:CheckResults | Where-Object { $_.status -in @('PASS', 'FAIL') }).Count

    $resultObject = [ordered]@{
        schema_version   = 1
        protocol_version = "1.7.0"
        kind             = "verification_result"
        result           = $ResultStr
        exit_code        = $ExitCode
        source           = if ($checksDefined) { "checks_tsv" } else { "auto_detected" }
        summary          = [ordered]@{
            checks_defined   = $script:CheckResults.Count
            checks_run       = $checksRun
            required_run     = $requiredRun
            passed           = $passedCount
            failed           = $failedCount
            optional_failed  = $optionalFailedCount
            blocked          = $blockedCount
            optional_skipped = $optionalSkipped
        }
        checks           = $script:CheckResults
    }
    [Console]::Out.WriteLine(($resultObject | ConvertTo-Json -Depth 10 -Compress))
}

function Write-VerificationEvent {
    param([System.Collections.Specialized.IOrderedDictionary] $Event)
    # Single choke point for the JSONL events stream: keeps serialization
    # (ConvertTo-Json) and newline handling identical for every event type.
    if ($Events) {
        try {
            [System.IO.File]::AppendAllText($Events, ($Event | ConvertTo-Json -Compress) + "`n", [System.Text.UTF8Encoding]::new($false))
        }
        catch {
            [Console]::Error.WriteLine("ERROR: failed to write event to stream.")
            exit 1
        }
    }
}

function Complete-Verification {
    # Single finalization path: first appends terminal event to event stream,
    # then emits JSON result (if requested), then exits with state-model code.
    # This ensures the event stream is complete before the JSON document is exposed.
    param([string] $ResultStr, [int] $ExitCode)
    try {
        Write-VerificationEvent ([ordered]@{
            event     = "verification_completed"
            result    = $ResultStr
            exit_code = $ExitCode
        })
    }
    catch {
        [Console]::Error.WriteLine("ERROR: failed to finalize verification event stream.")
        exit 1
    }
    if ($Format -eq 'Json') { 
        try {
            Output-VerificationJson $ResultStr $ExitCode
        }
        catch {
            [Console]::Error.WriteLine("ERROR: failed to write JSON verification result.")
            exit 1
        }
    }
    exit $ExitCode
}

# Path semantics must match the underlying filesystem (case-insensitive on
# Windows, case-sensitive on Unix), so confinement and duplicate-ID checks use
# these instead of PowerShell's default case-insensitive operators.
$script:VerifierPathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
$script:VerifierPathComparer = if ($IsWindows) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}

function Test-Command {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-CwdDisplay {
    # Redacts a check's working directory for observable JSON output: project
    # root becomes '.', paths under it become './<relative>', and anything
    # else (defensive fallback) degrades to its basename so an absolute
    # user-home path can never leak into the result document.
    param([string] $Cwd)
    $root = [System.IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath((Join-Path $root $Cwd)).TrimEnd('\', '/')
    if ($full -eq $root) { return '.' }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($root + $sep, $script:VerifierPathComparison)) {
        return './' + $full.Substring($root.Length + 1).Replace('\', '/')
    }
    return [System.IO.Path]::GetFileName($full)
}

# On Windows, extensionless executables (e.g. bats) are POSIX shell scripts that
# cannot be launched via CreateProcess. Returns @{ Bash; Script } (with the script
# path converted to /mnt/c/... form for WSL bash) when routing through bash applies,
# or $null when it does not. Prefers Git Bash, which handles Windows paths natively.
function Get-ExtensionlessBashLauncher {
    param([string] $Path)
    if (-not $IsWindows) { return $null }
    if ([System.IO.Path]::GetExtension($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $bash = $null
    foreach ($p in @('C:\Program Files\Git\bin\bash.exe', 'C:\Program Files\Git\usr\bin\bash.exe')) {
        if (Test-Path -LiteralPath $p) { $bash = $p; break }
    }
    if (-not $bash) {
        $found = Get-Command bash -ErrorAction SilentlyContinue
        if ($found) { $bash = $found.Source }
    }
    if (-not $bash) { return $null }
    $script = $Path
    if ($bash -like '*System32*bash.exe*') {
        if ($Path -match '^([A-Za-z]):(.*)') {
            $script = "/mnt/$($matches[1].ToLowerInvariant())$($matches[2] -replace '\\', '/')"
        }
    }
    return @{ Bash = $bash; Script = $script }
}

function Invoke-Check {
    param(
        [string] $Requirement,
        [string] $Id,
        [string] $Cwd,
        [string] $Exe,
        [string[]] $ArgsList
    )

    $cwdDisplay = Get-CwdDisplay $Cwd

    $cwdAbsolute = Join-Path (Get-Location).Path $Cwd
    try {
        $resolvedCwdPath = Resolve-PhysicalPath $cwdAbsolute
    }
    catch {
        $resolvedCwdPath = $null
    }
    if (-not $resolvedCwdPath -or -not [System.IO.Directory]::Exists($resolvedCwdPath)) {
        if ($Requirement -eq 'required') { $script:Blocked = $true }
        Write-Log "  BLOCKED: working directory '$Cwd' does not exist or cannot be used"
        $st = if ($Requirement -eq 'required') { 'BLOCKED' } else { 'SKIPPED_OPTIONAL' }
        $script:CheckResults += [ordered]@{
            id                = $Id
            requirement       = $Requirement
            status            = $st
            working_directory = $cwdDisplay
            exit_code         = $null
            duration_ms       = 0
            reason_code       = 'WORKING_DIR_MISSING'
        }
        if ($Events) {
            Write-VerificationEvent ([ordered]@{
                event             = "check_completed"
                check_id          = $Id
                status            = $st
                exit_code         = $null
                duration_ms       = 0
                working_directory = $cwdDisplay
                reason_code       = 'WORKING_DIR_MISSING'
            })
        }
        return
    }

    $resolvedExe = $null
    if ($Exe -match '[/\\]') {
        $candidate = Join-Path $Cwd $Exe
        if (Test-Path -LiteralPath $candidate) {
            $resolvedExe = (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    else {
        $found = Get-Command $Exe -ErrorAction SilentlyContinue
        if ($found) { $resolvedExe = $found.Source }
    }

    if (-not $resolvedExe) {
        if ($Requirement -eq 'required') {
            $script:Blocked = $true
            Write-Log "  BLOCKED: executable '$Exe' was not found"
        }
        else {
            Write-Log "  skip (optional): executable '$Exe' was not found"
        }
        $st = if ($Requirement -eq 'required') { 'BLOCKED' } else { 'SKIPPED_OPTIONAL' }
        $script:CheckResults += [ordered]@{
            id                = $Id
            requirement       = $Requirement
            status            = $st
            working_directory = $cwdDisplay
            exit_code         = $null
            duration_ms       = 0
            reason_code       = 'EXECUTABLE_MISSING'
        }
        if ($Events) {
            Write-VerificationEvent ([ordered]@{
                event             = "check_completed"
                check_id          = $Id
                status            = $st
                exit_code         = $null
                duration_ms       = 0
                working_directory = $cwdDisplay
                reason_code       = 'EXECUTABLE_MISSING'
            })
        }
        return
    }

    Write-Log ""
    Write-Log "==> [$Id] $Exe $($ArgsList -join ' ')"

    $script:Ran++
    if ($Requirement -eq 'required') { $script:RanRequired = $true }

    if ($Events) {
        Write-VerificationEvent ([ordered]@{
            event             = "check_started"
            check_id          = $Id
            working_directory = $cwdDisplay
        })
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location $Cwd
    $code = $null
    $prevEAP = $ErrorActionPreference
    $launcher = Get-ExtensionlessBashLauncher -Path $resolvedExe
    if ($launcher) {
        $invocationExe = $launcher.Bash
        $invocationArgs = @('--', $launcher.Script) + @($ArgsList)
    }
    else {
        $invocationExe = $resolvedExe
        $invocationArgs = @($ArgsList)
        # A bare `bash` on Windows frequently resolves to the WSL launcher
        # (C:\Windows\System32\bash.exe), which costs seconds per invocation.
        # Prefer Git Bash when installed; it handles Windows paths natively.
        if ($IsWindows -and $resolvedExe -like '*\System32\bash.exe') {
            foreach ($gb in @('C:\Program Files\Git\bin\bash.exe', 'C:\Program Files\Git\usr\bin\bash.exe')) {
                if (Test-Path -LiteralPath $gb) { $invocationExe = $gb; break }
            }
        }
    }
    try {
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = $null
        $prevErrorCount = $Error.Count
        if ($Format -eq 'Json') {
            & $invocationExe @invocationArgs 2>&1 | ForEach-Object { [Console]::Error.WriteLine($_) }
        }
        else {
            & $invocationExe @invocationArgs
        }
        $code = $LASTEXITCODE
        if ($null -eq $code) {
            # A launch that never produced a native process leaves $LASTEXITCODE
            # untouched (null after the reset): count errors first, then treat a
            # silent no-op Windows launch as a failure, never as success.
            if ($Error.Count -gt $prevErrorCount) { $code = 1 }
            elseif ($IsWindows -and $null -eq [System.IO.Path]::GetExtension($resolvedExe)) { $code = 1 }
            else { $code = 0 }
        }
    }
    catch {
        $code = 1
        Write-Log "  ERROR: failed to execute '$Exe': $($_.Exception.Message)"
    }
    finally {
        $ErrorActionPreference = $prevEAP
        Pop-Location
    }
    $sw.Stop()
    $durationMs = [int]$sw.ElapsedMilliseconds

    $checkFailed = ($code -ne 0)
    $st = if ($checkFailed) { 'FAIL' } else { 'PASS' }
    if ($checkFailed) {
        if ($Requirement -eq 'required') {
            $script:Failed = $true
        }
        else {
            Write-Log "  WARNING: optional check '$Id' failed"
        }
    }
    $reasonCode = if ($checkFailed) { 'CHECK_FAILED' } else { $null }
    $script:CheckResults += [ordered]@{
        id                = $Id
        requirement       = $Requirement
        status            = $st
        working_directory = $cwdDisplay
        exit_code         = $code
        duration_ms       = $durationMs
        reason_code       = $reasonCode
    }
    if ($Events) {
        Write-VerificationEvent ([ordered]@{
            event             = "check_completed"
            check_id          = $Id
            status            = $st
            exit_code         = $code
            duration_ms       = $durationMs
            working_directory = $cwdDisplay
            reason_code       = $reasonCode
        })
    }
}

function Invoke-TsvLine {
    param([string] $Line)
    $fields = $Line -split "`t"
    if ($fields.Count -lt 4) { return }
    $requirement = $fields[0]
    $id = $fields[1]
    $cwd = $fields[2]
    $exe = $fields[3]
    $args = if ($fields.Count -gt 4) { $fields[4..($fields.Count - 1)] } else { @() }
    Invoke-Check -Requirement $requirement -Id $id -Cwd $cwd -Exe $exe -ArgsList $args
}

function Get-GradleCommand {
    # Wrapper-enabled Gradle projects ship both platform scripts; the platform
    # script must be selected so the emitted contract runs under the shell that
    # will execute it (gradlew.bat under PowerShell on Windows).
    if ($IsWindows -and (Test-Path -LiteralPath '.\gradlew.bat')) {
        return '.\gradlew.bat'
    }
    if (Test-Path -LiteralPath './gradlew') {
        return './gradlew'
    }
    return 'gradle'
}

function Get-MavenCommand {
    if ($IsWindows -and (Test-Path -LiteralPath '.\mvnw.cmd')) {
        return '.\mvnw.cmd'
    }
    if (Test-Path -LiteralPath './mvnw') {
        return './mvnw'
    }
    return 'mvn'
}

function Test-PackageScript {
    # Returns true when the package.json at $Path declares a script named $Name.
    # The scripts block is located textually (no JSON parser), matching the
    # Bash detector so both implementations stay in parity.
    param([string] $Path, [string] $Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $raw = Get-Content -Raw -LiteralPath $Path
    $block = [regex]::Match($raw, '"scripts"\s*:\s*\{(.+?)\}').Groups[1].Value
    return -not [string]::IsNullOrEmpty($block) -and ($block -match ("`"$([regex]::Escape($Name))`"\s*:"))
}

function Test-RuffConfig {
    # Returns true when the directory $Path contains a Ruff configuration
    # (pyproject `[tool.ruff]`, `ruff.toml`, or `.ruff.toml`). A Python project
    # without one has not adopted Ruff, so `ruff check` would only produce a
    # false BLOCKED/FAIL later.
    param([string] $Path)
    $pyproject = Join-Path $Path 'pyproject.toml'
    if (Test-Path -LiteralPath $pyproject) {
        if ((Get-Content -LiteralPath $pyproject -ErrorAction SilentlyContinue) -match '^\[tool\.ruff') { return $true }
    }
    return (Test-Path -LiteralPath (Join-Path $Path 'ruff.toml')) -or
           (Test-Path -LiteralPath (Join-Path $Path '.ruff.toml'))
}

function Test-MavenCheckstyle {
    # The lint check is only emitted for Maven projects that configured it.
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue) -match 'checkstyle'
}

function Expand-WorkspacePattern {
    # Expands a workspace pattern (literal or glob) to existing directories.
    # Globs use Get-ChildItem with nullglob semantics; `**` enables recursion.
    param([string] $Pattern)
    $pat = $Pattern.Trim().TrimStart('./').TrimEnd('/','\')
    if (-not $pat) { return @() }
    if ($pat -match "[\t\n\r\x1f\p{Cc}]") { return @() }
    $excludedNames = @('node_modules','target','build','.venv','.git')
    if ($pat.Contains('*')) {
        if ($pat.Contains('**')) {
            $idx = $pat.IndexOf('**')
            $basePart = $pat.Substring(0, $idx).TrimEnd('/', '\')
            if ([string]::IsNullOrEmpty($basePart)) { $basePart = '.' }
            $results = @()
            try {
                $allDirs = Get-ChildItem -Path $basePart -Directory -Recurse -ErrorAction SilentlyContinue
                foreach ($d in $allDirs) {
                    $full = $d.FullName
                    $root = (Get-Location).Path
                    try { $rel = [System.IO.Path]::GetRelativePath($root, $full) } catch { $rel = $d.Name }
                    $rel = $rel.Replace('\','/')
                    if ($rel -match "[\t\n\r\x1f\p{Cc}]") { continue }
                    $bn = $d.Name
                    if ($excludedNames -contains $bn) { continue }
                    if ($rel -eq $basePart) { continue }
                    if (-not $rel.StartsWith($basePart + "/") -and $rel -ne $basePart) {
                        # For pattern like "packages/**", basePart is "packages", rel must be under it
                        # For "**" at start, basePart is ".", all dirs qualify
                        if ($basePart -ne '.' -and -not $rel.StartsWith($basePart + "/")) { continue }
                    }
                    $results += $rel
                }
            } catch {}
            return $results
        } else {
            $results = @()
            try {
                $matched = Get-ChildItem -Path $pat -Directory -ErrorAction SilentlyContinue
                foreach ($m in $matched) {
                    $full = $m.FullName
                    $root = (Get-Location).Path
                    try { $rel = [System.IO.Path]::GetRelativePath($root, $full) } catch { $rel = $m.Name }
                    $rel = $rel.Replace('\','/')
                    if ($rel -match "[\t\n\r\x1f\p{Cc}]") { continue }
                    if ($excludedNames -contains $m.Name) { continue }
                    $results += $rel
                }
            } catch {}
            return $results
        }
    } else {
        if (Test-Path -LiteralPath $pat -PathType Container) {
            $bn = Split-Path -Leaf $pat
            if ($excludedNames -contains $bn) { return @() }
            if ($pat -match "[\t\n\r\x1f\p{Cc}]") { return @() }
            return @($pat)
        }
        return @()
    }
}

function Get-DetectedChecks {
    [string[]] $lines = @()
    $script:WorkspaceLines = $lines
    $script:SeenPackages = @()
    $script:ExcludedDirs = @()
    function Emit-PackageChecks {
        param([string]$Dir)
        $dir = $Dir.TrimEnd('/','\').TrimStart('./')
        if (-not $dir) { return }
        if ($dir -match "[\t\n\r\x1f\p{Cc}]") { return }
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return }
        $bn = Split-Path -Leaf $dir
        if ($bn -in @('node_modules','target','build','.venv','.git')) { return }
        if ($script:SeenPackages -contains $dir) { return }
        if ($script:ExcludedDirs -contains $dir) { return }
        $script:SeenPackages += $dir
        $prefix = $dir.Replace('/','-').Replace('\','-')
        if (Test-Path -LiteralPath (Join-Path $dir 'package.json')) {
            Write-Log "Detected: Workspace Node.js project ($dir)"
            if (Test-Path -LiteralPath (Join-Path $dir 'pnpm-lock.yaml')) {
                $script:WorkspaceLines += "required`t${prefix}-node-test`t${dir}`tpnpm`ttest"
                if (Test-PackageScript (Join-Path $dir 'package.json') 'lint') { $script:WorkspaceLines += "required`t${prefix}-node-lint`t${dir}`tpnpm`tlint" }
            } elseif (Test-Path -LiteralPath (Join-Path $dir 'yarn.lock')) {
                $script:WorkspaceLines += "required`t${prefix}-node-test`t${dir}`tyarn`ttest"
                if (Test-PackageScript (Join-Path $dir 'package.json') 'lint') { $script:WorkspaceLines += "required`t${prefix}-node-lint`t${dir}`tyarn`tlint" }
            } elseif ((Test-Path -LiteralPath (Join-Path $dir 'bun.lock')) -or (Test-Path -LiteralPath (Join-Path $dir 'bun.lockb'))) {
                $script:WorkspaceLines += "required`t${prefix}-node-test`t${dir}`tbun`ttest"
                if (Test-PackageScript (Join-Path $dir 'package.json') 'lint') { $script:WorkspaceLines += "required`t${prefix}-node-lint`t${dir}`tbun`trun`tlint" }
            } else {
                $script:WorkspaceLines += "required`t${prefix}-node-test`t${dir}`tnpm`ttest"
                $script:WorkspaceLines += "required`t${prefix}-node-lint`t${dir}`tnpm`trun`tlint`t--if-present"
            }
        }
        if (Test-Path -LiteralPath (Join-Path $dir 'go.mod')) {
            Write-Log "Detected: Workspace Go project ($dir)"
            $script:WorkspaceLines += "required`t${prefix}-go-test`t${dir}`tgo`ttest`t./..."
            $script:WorkspaceLines += "required`t${prefix}-go-vet`t${dir}`tgo`tvet`t./..."
        }
        if (Test-Path -LiteralPath (Join-Path $dir 'Cargo.toml')) {
            Write-Log "Detected: Workspace Rust project ($dir)"
            $script:WorkspaceLines += "required`t${prefix}-rust-test`t${dir}`tcargo`ttest"
            $script:WorkspaceLines += "required`t${prefix}-rust-clippy`t${dir}`tcargo`tclippy`t--`t-D`twarnings"
        }
        if ((Test-Path -LiteralPath (Join-Path $dir 'pyproject.toml')) -or (Test-Path -LiteralPath (Join-Path $dir 'requirements.txt'))) {
            Write-Log "Detected: Workspace Python project ($dir)"
            if (Test-Path -LiteralPath (Join-Path $dir 'poetry.lock')) {
                $script:WorkspaceLines += "required`t${prefix}-python-test`t${dir}`tpoetry`trun`tpytest"
                if (Test-RuffConfig $dir) { $script:WorkspaceLines += "required`t${prefix}-python-ruff`t${dir}`tpoetry`trun`truff`tcheck`t." }
            } elseif (Test-Path -LiteralPath (Join-Path $dir 'uv.lock')) {
                $script:WorkspaceLines += "required`t${prefix}-python-test`t${dir}`tuv`trun`tpytest"
                if (Test-RuffConfig $dir) { $script:WorkspaceLines += "required`t${prefix}-python-ruff`t${dir}`tuv`trun`truff`tcheck`t." }
            } else {
                $script:WorkspaceLines += "required`t${prefix}-python-test`t${dir}`tpytest"
                if (Test-RuffConfig $dir) { $script:WorkspaceLines += "required`t${prefix}-python-ruff`t${dir}`truff`tcheck`t." }
            }
        }
        if (Test-Path -LiteralPath (Join-Path $dir 'pom.xml')) {
            Write-Log "Detected: Workspace Maven project ($dir)"
            if (Test-Path -LiteralPath (Join-Path $dir 'mvnw')) { $mvn = './mvnw' } elseif (Test-Path -LiteralPath (Join-Path $dir 'mvnw.cmd')) { $mvn = './mvnw.cmd' } else { $mvn = 'mvn' }
            $script:WorkspaceLines += "required`t${prefix}-maven-test`t${dir}`t${mvn}`ttest"
            if (Test-MavenCheckstyle (Join-Path $dir 'pom.xml')) { $script:WorkspaceLines += "required`t${prefix}-maven-lint`t${dir}`t${mvn}`tcheckstyle:check" }
        }
        if ((Test-Path -LiteralPath (Join-Path $dir 'build.gradle')) -or (Test-Path -LiteralPath (Join-Path $dir 'build.gradle.kts'))) {
            Write-Log "Detected: Workspace Gradle project ($dir)"
            $isAndroid = $false
            $gradleText = ''
            if (Test-Path -LiteralPath (Join-Path $dir 'build.gradle')) { $gradleText += Get-Content -LiteralPath (Join-Path $dir 'build.gradle') -Raw -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath (Join-Path $dir 'build.gradle.kts')) { $gradleText += Get-Content -LiteralPath (Join-Path $dir 'build.gradle.kts') -Raw -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath (Join-Path $dir 'AndroidManifest.xml')) { $isAndroid = $true }
            if ($gradleText -match 'com\.android|org\.jetbrains\.kotlin\.android') { $isAndroid = $true }
            if ($isAndroid) {
                if (Test-Path -LiteralPath (Join-Path $dir 'gradlew.bat')) { $gradleCmd = './gradlew.bat' } elseif (Test-Path -LiteralPath (Join-Path $dir 'gradlew')) { $gradleCmd = './gradlew' } else { $gradleCmd = 'gradle' }
                $script:WorkspaceLines += "required`t${prefix}-android-unit`t${dir}`t${gradleCmd}`ttest"
                $script:WorkspaceLines += "required`t${prefix}-android-lint`t${dir}`t${gradleCmd}`tlint"
                $script:WorkspaceLines += "required`t${prefix}-android-build`t${dir}`t${gradleCmd}`tassembleDebug"
                $script:WorkspaceLines += "optional`t${prefix}-android-device`t${dir}`t${gradleCmd}`tconnectedCheck"
            } else {
                if (Test-Path -LiteralPath (Join-Path $dir 'gradlew.bat')) { $gradleCmd = './gradlew.bat' } elseif (Test-Path -LiteralPath (Join-Path $dir 'gradlew')) { $gradleCmd = './gradlew' } else { $gradleCmd = 'gradle' }
                $script:WorkspaceLines += "required`t${prefix}-gradle-test`t${dir}`t${gradleCmd}`ttest"
                $script:WorkspaceLines += "required`t${prefix}-gradle-lint`t${dir}`t${gradleCmd}`tcheck"
            }
        }
        if ((Get-ChildItem -Path $dir -Filter *.sln -File -ErrorAction SilentlyContinue) -or (Get-ChildItem -Path $dir -Filter *.csproj -File -ErrorAction SilentlyContinue)) {
            Write-Log "Detected: Workspace .NET project ($dir)"
            $script:WorkspaceLines += "required`t${prefix}-dotnet-test`t${dir}`tdotnet`ttest"
            $script:WorkspaceLines += "required`t${prefix}-dotnet-lint`t${dir}`tdotnet`tformat`t--verify-no-changes"
        }
    }

    if (Test-Path -LiteralPath package.json) {
        Write-Log "Detected: Node.js project (package.json)"
        if (Test-Path -LiteralPath pnpm-lock.yaml) {
            $lines += "required`tnode-test`t.`tpnpm`ttest"
            if (Test-PackageScript 'package.json' 'lint') {
                $lines += "required`tnode-lint`t.`tpnpm`tlint"
            }
        }
        elseif (Test-Path -LiteralPath yarn.lock) {
            $lines += "required`tnode-test`t.`tyarn`ttest"
            if (Test-PackageScript 'package.json' 'lint') {
                $lines += "required`tnode-lint`t.`tyarn`tlint"
            }
        }
        elseif ((Test-Path -LiteralPath bun.lock) -or (Test-Path -LiteralPath bun.lockb)) {
            $lines += "required`tnode-test`t.`tbun`ttest"
            if (Test-PackageScript 'package.json' 'lint') {
                $lines += "required`tnode-lint`t.`tbun`trun`tlint"
            }
        }
        else {
            $lines += "required`tnode-test`t.`tnpm`ttest"
            $lines += "required`tnode-lint`t.`tnpm`trun`tlint`t--if-present"
        }
    }

    if (Test-Path -LiteralPath Cargo.toml) {
        Write-Log "Detected: Rust project (Cargo.toml)"
        $lines += "required`trust-test`t.`tcargo`ttest"
        $lines += "required`trust-clippy`t.`tcargo`tclippy`t--`t-D`twarnings"
    }

    if ((Test-Path -LiteralPath pyproject.toml) -or (Test-Path -LiteralPath requirements.txt)) {
        Write-Log "Detected: Python project (pyproject.toml / requirements.txt)"
        if (Test-Path -LiteralPath poetry.lock) {
            $lines += "required`tpython-test`t.`tpoetry`trun`tpytest"
            if (Test-RuffConfig '.') {
                $lines += "required`tpython-ruff`t.`tpoetry`trun`truff`tcheck`t."
            }
        }
        elseif (Test-Path -LiteralPath uv.lock) {
            $lines += "required`tpython-test`t.`tuv`trun`tpytest"
            if (Test-RuffConfig '.') {
                $lines += "required`tpython-ruff`t.`tuv`trun`truff`tcheck`t."
            }
        }
        else {
            $lines += "required`tpython-test`t.`tpytest"
            if (Test-RuffConfig '.') {
                $lines += "required`tpython-ruff`t.`truff`tcheck`t."
            }
        }
    }

    if (Test-Path -LiteralPath go.mod) {
        Write-Log "Detected: Go project (go.mod)"
        $lines += "required`tgo-test`t.`tgo`ttest`t./..."
        $lines += "required`tgo-vet`t.`tgo`tvet`t./..."
    }

    if (Test-Path -LiteralPath pom.xml) {
        Write-Log "Detected: Maven project (pom.xml)"
        $mavenCmd = Get-MavenCommand
        $lines += "required`tmaven-test`t.`t$mavenCmd`ttest"
        if (Test-MavenCheckstyle 'pom.xml') {
            $lines += "required`tmaven-lint`t.`t$mavenCmd`tcheckstyle:check"
        }
    }
    elseif ((Test-Path -LiteralPath build.gradle) -or (Test-Path -LiteralPath build.gradle.kts)) {
        $isAndroid = $false
        $gradleText = ''
        if (Test-Path -LiteralPath build.gradle) { $gradleText += Get-Content -LiteralPath build.gradle -Raw -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath build.gradle.kts) { $gradleText += Get-Content -LiteralPath build.gradle.kts -Raw -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath AndroidManifest.xml) { $isAndroid = $true }
        if ($gradleText -match 'com\.android|org\.jetbrains\.kotlin\.android') { $isAndroid = $true }

        if ($isAndroid) {
            Write-Log "Detected: Android / Kotlin Gradle project (build.gradle)"
            $gradleCmd = Get-GradleCommand
            $lines += "required`tandroid-unit`t.`t$gradleCmd`ttest"
            $lines += "required`tandroid-lint`t.`t$gradleCmd`tlint"
            $lines += "required`tandroid-build`t.`t$gradleCmd`tassembleDebug"
            $lines += "optional`tandroid-device`t.`t$gradleCmd`tconnectedCheck"
        }
        else {
            Write-Log "Detected: Gradle project (build.gradle)"
            $gradleCmd = Get-GradleCommand
            $lines += "required`tgradle-test`t.`t$gradleCmd`ttest"
            $lines += "required`tgradle-lint`t.`t$gradleCmd`tcheck"
        }
    }

    if ((Get-ChildItem -Path . -Filter *.sln -File -ErrorAction SilentlyContinue) -or
        (Get-ChildItem -Path . -Filter *.csproj -File -ErrorAction SilentlyContinue)) {
        Write-Log "Detected: .NET project (*.sln / *.csproj)"
        $lines += "required`tdotnet-test`t.`tdotnet`ttest"
        $lines += "required`tdotnet-lint`t.`tdotnet`tformat`t--verify-no-changes"
    }

    # Sync root checks to workspace script vars
    $script:WorkspaceLines = $lines

    # pnpm-workspace.yaml
    if (Test-Path -LiteralPath 'pnpm-workspace.yaml') {
        Write-Log "Detected: pnpm workspace (pnpm-workspace.yaml)"
        $pnpmIncludes = @()
        $pnpmExcludes = @()
        $inPkg = $false
        $raw = Get-Content -LiteralPath 'pnpm-workspace.yaml' -ErrorAction SilentlyContinue
        foreach ($line in $raw) {
            if ($line -match '^\s*packages\s*:') { $inPkg = $true; continue }
            if ($inPkg) {
                if ($line -match '^\s*(#|$)') { continue }
                if ($line -match '^\s*-\s*(.*)') {
                    $pat = $Matches[1].Trim()
                    $pat = $pat.Split('#')[0].Trim()
                    $pat = $pat.Trim("'").Trim('"')
                    if (-not $pat) { continue }
                    if ($pat.StartsWith('!')) { $pnpmExcludes += $pat.Substring(1) } else { $pnpmIncludes += $pat }
                } elseif ($line -match '^\S') { break }
            }
        }
        foreach ($pat in $pnpmExcludes) {
            $expanded = Expand-WorkspacePattern -Pattern $pat
            foreach ($d in $expanded) { if (-not ($script:ExcludedDirs -contains $d)) { $script:ExcludedDirs += $d } }
        }
        foreach ($pat in $pnpmIncludes) {
            $expanded = Expand-WorkspacePattern -Pattern $pat
            foreach ($d in $expanded) { Emit-PackageChecks -Dir $d }
        }
    }

    # package.json workspaces (npm / yarn)
    if (Test-Path -LiteralPath 'package.json') {
        try {
            $json = Get-Content -LiteralPath 'package.json' -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -ne $json -and $null -ne $json.workspaces) {
                Write-Log "Detected: npm/yarn workspaces (package.json)"
                $patterns = @()
                $ws = $json.workspaces
                if ($ws -is [Array]) {
                    $patterns = $ws
                } elseif ($ws -is [PSCustomObject]) {
                    if ($null -ne $ws.packages) { $patterns = $ws.packages }
                }
                foreach ($pat in $patterns) {
                    if (-not $pat) { continue }
                    $patStr = [string]$pat
                    if ($patStr.StartsWith('!')) {
                        $p2 = $patStr.Substring(1)
                        $expanded = Expand-WorkspacePattern -Pattern $p2
                        foreach ($d in $expanded) { if (-not ($script:ExcludedDirs -contains $d)) { $script:ExcludedDirs += $d } }
                    } else {
                        $expanded = Expand-WorkspacePattern -Pattern $patStr
                        foreach ($d in $expanded) { Emit-PackageChecks -Dir $d }
                    }
                }
            }
        } catch {}
    }

    # Cargo workspace
    if ((Test-Path -LiteralPath 'Cargo.toml') -and ((Get-Content -LiteralPath 'Cargo.toml' -Raw -ErrorAction SilentlyContinue) -match '(?m)^\[workspace\]')) {
        Write-Log "Detected: Cargo workspace (Cargo.toml)"
        $cargoLines = Get-Content -LiteralPath 'Cargo.toml' -ErrorAction SilentlyContinue
        $inWs = $false
        $wsBuilder = ""
        foreach ($l in $cargoLines) {
            if ($l -match '^\[workspace\]') { $inWs = $true; continue }
            if ($inWs -and $l -match '^\[.*\]') { break }
            if ($inWs) { $wsBuilder += $l + "`n" }
        }
        $wsSection = $wsBuilder
        if ($wsSection) {
            $mEx = [regex]::Match($wsSection, 'exclude\s*=\s*\[(.*?)\]', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($mEx.Success) {
                $exContent = $mEx.Groups[1].Value
                $exMatches = [regex]::Matches($exContent, '"([^"]*)"')
                foreach ($mm in $exMatches) {
                    $pat = $mm.Groups[1].Value
                    $expanded = Expand-WorkspacePattern -Pattern $pat
                    foreach ($d in $expanded) { if (-not ($script:ExcludedDirs -contains $d)) { $script:ExcludedDirs += $d } }
                }
            }
            $mMem = [regex]::Match($wsSection, 'members\s*=\s*\[(.*?)\]', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($mMem.Success) {
                $memContent = $mMem.Groups[1].Value
                $memMatches = [regex]::Matches($memContent, '"([^"]*)"')
                foreach ($mm in $memMatches) {
                    $pat = $mm.Groups[1].Value
                    $expanded = Expand-WorkspacePattern -Pattern $pat
                    foreach ($d in $expanded) { Emit-PackageChecks -Dir $d }
                }
            }
        }
    }

    # Maven multi-module
    if ((Test-Path -LiteralPath 'pom.xml') -and ((Get-Content -LiteralPath 'pom.xml' -Raw -ErrorAction SilentlyContinue) -match '<modules>')) {
        Write-Log "Detected: Maven multi-module (pom.xml)"
        $pomRaw = Get-Content -LiteralPath 'pom.xml' -Raw -ErrorAction SilentlyContinue
        $modMatches = [regex]::Matches($pomRaw, '<module>([^<]+)</module>')
        foreach ($mm in $modMatches) {
            $mod = $mm.Groups[1].Value.Trim().TrimStart('./').TrimEnd('/')
            if (-not $mod) { continue }
            $expanded = Expand-WorkspacePattern -Pattern $mod
            foreach ($d in $expanded) { Emit-PackageChecks -Dir $d }
        }
    }

    # Gradle settings
    foreach ($gradleFile in @('settings.gradle','settings.gradle.kts')) {
        if (Test-Path -LiteralPath $gradleFile) {
            Write-Log "Detected: Gradle workspace ($gradleFile)"
            $incLines = Get-Content -LiteralPath $gradleFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*include' }
            foreach ($line in $incLines) {
                $qMatches = [regex]::Matches($line, "['`"]([^'`"]+)['`"]")
                foreach ($qm in $qMatches) {
                    $inc = $qm.Groups[1].Value
                    $pat = $inc.TrimStart(':').Replace(':','/').Trim()
                    if (-not $pat) { continue }
                    $expanded = Expand-WorkspacePattern -Pattern $pat
                    foreach ($d in $expanded) { Emit-PackageChecks -Dir $d }
                }
            }
        }
    }

    foreach ($base in @('apps', 'services', 'packages', 'modules')) {
        if (Test-Path -LiteralPath $base -PathType Container) {
            $subs = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue
            foreach ($sub in $subs) {
                $subName = $sub.Name
                if ($subName -match "[\t\n\r\x1f\p{Cc}]") { continue }
                if ($subName -in @('node_modules', 'target', 'build', '.venv')) { continue }
                $subRel = "$base/$subName"
                Emit-PackageChecks -Dir $subRel
            }
        }
    }

    $lines = $script:WorkspaceLines
    return $lines
}

function Resolve-PhysicalPath {
    param([string] $Path)
    # Follows every path segment so a symlink/junction inside the project that
    # points outside resolves to its physical target, not its lexical path.
    # A relative link target is resolved against the link's parent directory,
    # and a per-chain visited set plus a hop cap make link cycles fail
    # deterministically instead of looping forever.
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    $current = $root
    $parts = $full.Substring($root.Length) -split '[/\\]' | Where-Object { $_ -ne '' }
    $maxHops = 32
    foreach ($part in $parts) {
        $current = Join-Path $current $part
        $seen = [System.Collections.Generic.HashSet[string]]::new($script:VerifierPathComparer)
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

# Write-confinement for the generated-candidate write (mirrors verify.sh's
# safe_detect_destination). Returns $false when the final component exists as a
# symlink/junction, or when the nearest existing ancestor resolves physically
# outside the current directory (the project root the verifier runs from), so
# an outside-pointing `.agentic` link can never redirect the candidate write,
# replacement, or stale-candidate removal.
function Assert-VerifierDestination {
    param([string] $RelativePath)
    $root = (Get-Location).Path
    $full = Join-Path $root $RelativePath
    $leaf = $full
    while (-not (Test-Path -LiteralPath $leaf)) {
        $parent = Split-Path -Parent $leaf
        if ([string]::IsNullOrEmpty($parent) -or $parent.Equals($leaf, $script:VerifierPathComparison)) { break }
        $leaf = $parent
    }
    $item = Get-Item -LiteralPath $leaf -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $false }
    try {
        $resolved = Resolve-PhysicalPath $leaf
        $resolvedRoot = Resolve-PhysicalPath $root
    }
    catch { return $false }
    $rootTrimmed = $resolvedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $rootTrimmed + [System.IO.Path]::DirectorySeparatorChar
    return $resolved.Equals($rootTrimmed, $script:VerifierPathComparison) -or
        $resolved.StartsWith($rootPrefix, $script:VerifierPathComparison)
}

# Destination policy for the JSONL events stream: a relative path inside
# .agentic/runs/ whose nearest existing ancestor physically resolves inside
# the project root and whose existing leaf is not a symlink/junction. Lexical
# checks first (absolute paths, '..' segments, prefix), then the physical
# confinement shared with the generated-candidate write.
function Test-EventsDestination {
    param([string] $Destination)
    if ([System.IO.Path]::IsPathRooted($Destination)) { return $false }
    $normalized = ($Destination -replace '\\', '/') -replace '^\./', ''
    if (-not $normalized.StartsWith('.agentic/runs/')) { return $false }
    foreach ($segment in $normalized.Split('/')) {
        if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..') { return $false }
    }
    return (Assert-VerifierDestination $normalized)
}

# Create the events stream with exactly one verification_started object as its
# first line. The file is built in an unpredictable scratch name next to the
# destination and moved into place atomically, so a crashed run can never
# truncate an existing stream before its replacement is complete.
function Initialize-EventsStream {
    if (-not (Test-EventsDestination $Events)) {
        [Console]::Error.WriteLine("ERROR: events destination must be a relative path inside .agentic/runs/. '$Events' is not allowed.")
        exit 1
    }
    if (-not $EventsForce -and (Test-Path -LiteralPath $Events)) {
        [Console]::Error.WriteLine("ERROR: refusing to overwrite existing event file '$Events'. Use -EventsForce to overwrite.")
        exit 1
    }
    $eventDir = Split-Path -Parent $Events
    if ($eventDir) { New-Item -ItemType Directory -Path $eventDir -Force | Out-Null }
    # .NET file APIs ignore PowerShell's current location, so the scratch path
    # is made absolute against it before writing.
    $scratchAbsolute = Join-Path (Get-Location).Path (Join-Path $eventDir ('.verify-events.' + [System.IO.Path]::GetRandomFileName()))
    $startLine = ([ordered]@{ event = "verification_started" } | ConvertTo-Json -Compress) + "`n"
    [System.IO.File]::WriteAllText($scratchAbsolute, $startLine, [System.Text.UTF8Encoding]::new($false))
    try {
        if ($EventsForce) {
            Move-Item -LiteralPath $scratchAbsolute -Destination $Events -Force -ErrorAction Stop
        }
        else {
            Move-Item -LiteralPath $scratchAbsolute -Destination $Events -ErrorAction Stop
        }
        if (-not (Test-Path -LiteralPath $Events -PathType Leaf)) {
            throw "Event stream promotion produced no destination file."
        }
    }
    catch {
        [Console]::Error.WriteLine("ERROR: failed to initialize event stream.")
        exit 1
    }
    finally {
        if (Test-Path -LiteralPath $scratchAbsolute) {
            Remove-Item -LiteralPath $scratchAbsolute -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-ChecksTsvValidation {
    param([string] $FilePath)
    $lines = Get-Content -LiteralPath $FilePath
    $lineNum = 0
    $seenIds = @{}
    $rootPath = (Get-Location).Path

    foreach ($rawLine in $lines) {
        $lineNum++
        if ([string]::IsNullOrWhiteSpace($rawLine) -or $rawLine.TrimStart().StartsWith('#')) {
            continue
        }
        $fields = $rawLine -split "`t"
        if ($fields.Count -lt 4) {
            throw ".agentic/checks.tsv line $lineNum has fewer than 4 fields."
        }
        if ($rawLine.EndsWith("`t")) {
            throw ".agentic/checks.tsv line $lineNum has trailing tab (empty trailing field)."
        }
        $requirement = $fields[0]
        $id = $fields[1]
        $cwd = $fields[2]
        $exe = $fields[3]

        if ($requirement -ne 'required' -and $requirement -ne 'optional') {
            throw ".agentic/checks.tsv line $lineNum has invalid requirement '$requirement' (expected 'required' or 'optional')."
        }
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($cwd) -or [string]::IsNullOrWhiteSpace($exe)) {
            throw ".agentic/checks.tsv line $lineNum has empty check ID, working directory, or executable."
        }
        if ($seenIds.ContainsKey($id)) {
            throw ".agentic/checks.tsv line $lineNum has duplicate check ID '$id'."
        }
        $seenIds[$id] = $true

        $targetCwd = Join-Path $rootPath $cwd
        try {
            $resolvedCwd = Resolve-PhysicalPath $targetCwd
            $resolvedRoot = Resolve-PhysicalPath $rootPath
        }
        catch {
            throw ".agentic/checks.tsv line $lineNum working directory '$cwd' cannot be resolved ($($_.Exception.Message))."
        }
        # Confinement requires an exact match or root followed by the directory
        # separator; a sibling path sharing the root's name prefix must not pass.
        $resolvedRootTrimmed = $resolvedRoot.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $rootPrefix = $resolvedRootTrimmed + [System.IO.Path]::DirectorySeparatorChar
        $insideRoot =
            $resolvedCwd.Equals($resolvedRootTrimmed, $script:VerifierPathComparison) -or
            $resolvedCwd.StartsWith($rootPrefix, $script:VerifierPathComparison)
        if (-not $insideRoot) {
            throw ".agentic/checks.tsv line $lineNum working directory '$cwd' escapes project root."
        }
    }
}

# --events is independent of --format: events are emitted in both modes.
# The stream is initialized later, after contract validation succeeds and just
# before checks run, so every stream that is created always ends with exactly
# one terminal verification_completed event.

$checksPath = ".agentic/checks.tsv"
$checksDefined = $false
if (Test-Path -LiteralPath $checksPath) {
    $checksDefined = @(Get-Content -LiteralPath $checksPath | Where-Object { $_ -notmatch '^\s*(#|$)' }).Count -gt 0
}

if ($EmitChecks) {
    Get-DetectedChecks
    exit 0
}

if ($PSBoundParameters.ContainsKey('ValidateChecks')) {
    if ([string]::IsNullOrWhiteSpace($ValidateChecks)) {
        Write-Log "ERROR: --validate-checks requires a file path."
        exit 1
    }
    if (-not (Test-Path -LiteralPath $ValidateChecks)) {
        Write-Log "ERROR: file '$ValidateChecks' does not exist."
        exit 1
    }
    try {
        Test-ChecksTsvValidation -FilePath $ValidateChecks
    }
    catch {
        Write-Log "ERROR: $_"
        exit 1
    }
    Write-Log "Checks file '$ValidateChecks' is valid."
    exit 0
}

if ($ExplainDetection) {
    Write-Log "=== Project Detection Explanation ==="
    $null = Get-DetectedChecks
    exit 0
}

if ($DetectChecks) {
    $genFile = ".agentic/checks.generated.tsv"
    if (-not (Assert-VerifierDestination $genFile)) {
        Write-Log "ERROR: refusing to write '$genFile': destination is not safely inside the project root."
        exit 1
    }
    $null = New-Item -ItemType Directory -Path ".agentic" -Force
    $checks = @(Get-DetectedChecks)
    if ($checks.Count -eq 0) {
        Remove-Item -LiteralPath $genFile -Force -ErrorAction SilentlyContinue
        Write-Log "No stack detected. Removed stale candidate '$genFile'."
        exit 0
    }
    # The scratch file is created next to the candidate (same filesystem), so
    # the final Move-Item is a single atomic rename instead of a cross-device
    # copy-and-delete from the system temp directory. The path must be absolute
    # (resolved against the verifier's location) because .NET file APIs ignore
    # PowerShell's current location.
    $genDir = (Resolve-Path -LiteralPath ".agentic").Path
    $tmp = Join-Path $genDir ("checks.generated.tsv." + [System.IO.Path]::GetRandomFileName())
    $content = @(
        "# .agentic/checks.generated.tsv — candidate verification contract.",
        "# Auto-generated by detection workflow. Review assumptions and promote to .agentic/checks.tsv"
    ) + $checks
    [System.IO.File]::WriteAllLines($tmp, $content, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $genFile) {
        if (Test-Path -LiteralPath $genFile -PathType Container) {
            Write-Log "ERROR: generated candidate exists and is a directory: $genFile"
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            exit 1
        }
        if (-not (Test-Path -LiteralPath $genFile -PathType Leaf)) {
            Write-Log "ERROR: generated candidate exists and is not a regular file: $genFile"
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            exit 1
        }
    }
    try {
        Test-ChecksTsvValidation -FilePath $tmp
        Move-Item -LiteralPath $tmp -Destination $genFile -Force
        Write-Log "Candidate contract written to $genFile"
    }
    catch {
        Write-Log "ERROR: Generated checks failed validation: $_"
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        exit 1
    }
    exit 0
}

if ($checksDefined) {
    # Contract validation happens before the events stream is created, so a
    # malformed project contract can never leave a started-but-unterminated
    # event file behind.
    try {
        Test-ChecksTsvValidation -FilePath $checksPath
    }
    catch {
        Write-Log "ERROR: $_"
        exit 1
    }
}
else {
    if (Test-Path -LiteralPath $checksPath) {
        Write-Log "Note: $checksPath defines no checks; falling back to auto-detection."
    }
    Write-Log "Auto-detecting project stack (no checks.tsv)..."
    $detectedChecks = @(Get-DetectedChecks)
    if ($detectedChecks.Count -gt 0) {
        $tmp = [System.IO.Path]::GetTempFileName()
        [System.IO.File]::WriteAllLines($tmp, $detectedChecks, [System.Text.UTF8Encoding]::new($false))
        try {
            Test-ChecksTsvValidation -FilePath $tmp
        }
        catch {
            Write-Log "ERROR: Auto-detected checks failed validation: $_"
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            exit 1
        }
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
}

# The events stream starts only now — after every early-exit mode and after
# contract validation succeeded — so any stream that exists is guaranteed to
# receive exactly one terminal verification_completed event below.
if ($Events) { Initialize-EventsStream }

if ($checksDefined) {
    Write-Log "Using project checks: $checksPath"
    $script:Detected = $true
    Get-Content -LiteralPath $checksPath | ForEach-Object {
        if ($_ -match '^\s*(#|$)') { return }
        Invoke-TsvLine -Line $_
    }
}
elseif ($detectedChecks -and $detectedChecks.Count -gt 0) {
    $script:Detected = $true
    foreach ($line in $detectedChecks) { Invoke-TsvLine -Line $line }
}

Write-Log ""
# Priority: a real failure beats a blocked check; a blocked required check
# beats "PASS" because not every required check ran, so "all passed" cannot
# be claimed.
if ($script:Failed) {
    Write-Log "VERIFICATION FAILED: $($script:Ran) check(s) ran, at least one required check failed."
    Complete-Verification "FAIL" 1
}
if ($script:Blocked) {
    Write-Log "VERIFICATION BLOCKED: $($script:Ran) check(s) ran; required tooling was unavailable."
    Complete-Verification "BLOCKED" 2
}
if ($script:RanRequired) {
    Write-Log "VERIFICATION PASSED: $($script:Ran) check(s) ran."
    Complete-Verification "PASS" 0
}
if ($script:Detected) {
    Write-Log "VERIFICATION BLOCKED: $($script:Ran) check(s) ran; required tooling was unavailable."
    Complete-Verification "BLOCKED" 2
}
Write-Log "VERIFICATION UNSUPPORTED: no supported project or check configuration found."
Complete-Verification "UNSUPPORTED" 3

