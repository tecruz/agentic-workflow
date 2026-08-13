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
    [switch] $EmitChecks
)

$script:Failed = $false
$script:Ran = 0
$script:RanRequired = $false
$script:Blocked = $false
$script:Detected = $false

function Test-Command {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Check {
    param(
        [string] $Requirement,
        [string] $Id,
        [string] $Cwd,
        [string] $Exe,
        [string[]] $ArgsList
    )

    # A working directory must resolve to an existing directory, or the check
    # is BLOCKED (never PASS). Test-Path alone is unreliable for broken symbolic
    # links on some platforms, so confirm the physically resolved path exists.
    # The cwd is relative to the project root (PowerShell's current location),
    # not the .NET process working directory that GetFullPath would otherwise use.
    $cwdAbsolute = Join-Path (Get-Location).Path $Cwd
    try {
        $resolvedCwdPath = Resolve-PhysicalPath $cwdAbsolute
    }
    catch {
        $resolvedCwdPath = $null
    }
    if (-not $resolvedCwdPath -or -not [System.IO.Directory]::Exists($resolvedCwdPath)) {
        if ($Requirement -eq 'required') { $script:Blocked = $true }
        Write-Host "  BLOCKED: working directory '$Cwd' does not exist or cannot be used"
        return
    }

    $resolvedExe = $null
    if ($Exe -match '[/\\]') {
        # A path-qualified executable is resolved ONLY against the configured
        # path. Never fall back to a same-named command on PATH when the
        # configured path is missing: that could run an unrelated executable
        # and falsely report PASS. A missing configured path is BLOCKED below.
        $candidate = Join-Path $Cwd $Exe
        if (Test-Path -LiteralPath $candidate) {
            $resolvedExe = (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    else {
        # Bare executable names may be resolved from PATH.
        $found = Get-Command $Exe -ErrorAction SilentlyContinue
        if ($found) { $resolvedExe = $found.Source }
    }

    if (-not $resolvedExe) {
        if ($Requirement -eq 'required') {
            $script:Blocked = $true
            Write-Host "  BLOCKED: executable '$Exe' was not found"
        }
        else {
            Write-Host "  skip (optional): executable '$Exe' was not found"
        }
        return
    }

    Write-Host ""
    Write-Host "==> [$Id] $Exe $($ArgsList -join ' ')"

    $script:Ran++
    if ($Requirement -eq 'required') { $script:RanRequired = $true }

    Push-Location $Cwd
    try {
        & $resolvedExe @ArgsList
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($code -ne 0) {
        if ($Requirement -eq 'required') {
            $script:Failed = $true
        }
        else {
            Write-Host "  WARNING: optional check '$Id' failed"
        }
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

function Get-DetectedChecks {
    [string[]] $lines = @()

    if (Test-Path -LiteralPath package.json) {
        Write-Host "Detected: Node.js project (package.json)"
        if (Test-Path -LiteralPath pnpm-lock.yaml) {
            $lines += "required`ttest`t.`tpnpm`ttest"
            $lines += "required`tlint`t.`tpnpm`tlint"
        }
        elseif (Test-Path -LiteralPath yarn.lock) {
            $lines += "required`ttest`t.`tyarn`ttest"
            $lines += "required`tlint`t.`tyarn`tlint"
        }
        elseif (Test-Path -LiteralPath bun.lockb) {
            $lines += "required`ttest`t.`tbun`ttest"
            $lines += "required`tlint`t.`tbun`trun`tlint"
        }
        else {
            $lines += "required`ttest`t.`tnpm`ttest"
            $lines += "required`tlint`t.`tnpm`trun`tlint`t--if-present"
        }
    }

    if (Test-Path -LiteralPath Cargo.toml) {
        Write-Host "Detected: Rust project (Cargo.toml)"
        $lines += "required`ttest`t.`tcargo`ttest"
        $lines += "required`tlint`t.`tcargo`tclippy`t--`t-D`twarnings"
    }

    if ((Test-Path -LiteralPath pyproject.toml) -or (Test-Path -LiteralPath requirements.txt)) {
        Write-Host "Detected: Python project (pyproject.toml / requirements.txt)"
        if (Test-Path -LiteralPath poetry.lock) {
            $lines += "required`ttest`t.`tpoetry`trun`tpytest"
            $lines += "required`tlint`t.`tpoetry`trun`truff`tcheck`t."
        }
        elseif (Test-Path -LiteralPath uv.lock) {
            $lines += "required`ttest`t.`tuv`trun`tpytest"
            $lines += "required`tlint`t.`tuv`trun`truff`tcheck`t."
        }
        else {
            $lines += "required`ttest`t.`tpytest"
            $lines += "required`tlint`t.`truff`tcheck`t."
        }
    }

    if (Test-Path -LiteralPath go.mod) {
        Write-Host "Detected: Go project (go.mod)"
        $lines += "required`ttest`t.`tgo`ttest`t./..."
        $lines += "required`tlint`t.`tgo`tvet`t./..."
    }

    if (Test-Path -LiteralPath pom.xml) {
        Write-Host "Detected: Maven project (pom.xml)"
        if (Test-Path -LiteralPath ./mvnw) {
            $lines += "required`ttest`t.`t./mvnw`ttest"
            $lines += "required`tlint`t.`t./mvnw`tcheckstyle:check"
        }
        else {
            $lines += "required`ttest`t.`tmvn`ttest"
            $lines += "required`tlint`t.`tmvn`tcheckstyle:check"
        }
    }
    elseif ((Test-Path -LiteralPath build.gradle) -or (Test-Path -LiteralPath build.gradle.kts)) {
        Write-Host "Detected: Gradle project (build.gradle)"
        if (Test-Path -LiteralPath ./gradlew) {
            $lines += "required`ttest`t.`t./gradlew`ttest"
            $lines += "required`tlint`t.`t./gradlew`tcheck"
        }
        else {
            $lines += "required`ttest`t.`tgradle`ttest"
            $lines += "required`tlint`t.`tgradle`tcheck"
        }
    }

    if ((Get-ChildItem -Path . -Filter *.sln -File -ErrorAction SilentlyContinue) -or
        (Get-ChildItem -Path . -Filter *.csproj -File -ErrorAction SilentlyContinue)) {
        Write-Host "Detected: .NET project (*.sln / *.csproj)"
        $lines += "required`ttest`t.`tdotnet`ttest"
        $lines += "required`tlint`t.`tdotnet`tformat`t--verify-no-changes"
    }

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
        $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
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
            Write-Host "ERROR: .agentic/checks.tsv line $lineNum has fewer than 4 fields."
            exit 1
        }
        $requirement = $fields[0]
        $id = $fields[1]
        $cwd = $fields[2]
        $exe = $fields[3]

        if ($requirement -ne 'required' -and $requirement -ne 'optional') {
            Write-Host "ERROR: .agentic/checks.tsv line $lineNum has invalid requirement '$requirement' (expected 'required' or 'optional')."
            exit 1
        }
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($cwd) -or [string]::IsNullOrWhiteSpace($exe)) {
            Write-Host "ERROR: .agentic/checks.tsv line $lineNum has empty check ID, working directory, or executable."
            exit 1
        }
        if ($seenIds.ContainsKey($id)) {
            Write-Host "ERROR: .agentic/checks.tsv line $lineNum has duplicate check ID '$id'."
            exit 1
        }
        $seenIds[$id] = $true

        $targetCwd = Join-Path $rootPath $cwd
        try {
            $resolvedCwd = Resolve-PhysicalPath $targetCwd
            $resolvedRoot = Resolve-PhysicalPath $rootPath
        }
        catch {
            Write-Host "ERROR: .agentic/checks.tsv line $lineNum working directory '$cwd' cannot be resolved ($($_.Exception.Message))."
            exit 1
        }
        # Confinement requires an exact match or root followed by the directory
        # separator; a sibling path sharing the root's name prefix must not pass.
        $resolvedRootTrimmed = $resolvedRoot.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $rootPrefix = $resolvedRootTrimmed + [System.IO.Path]::DirectorySeparatorChar
        $insideRoot =
            $resolvedCwd.Equals($resolvedRootTrimmed, [System.StringComparison]::OrdinalIgnoreCase) -or
            $resolvedCwd.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $insideRoot) {
            Write-Host "ERROR: .agentic/checks.tsv line $lineNum working directory '$cwd' escapes project root."
            exit 1
        }
    }
}

$checksPath = ".agentic/checks.tsv"
$checksDefined = $false
if (Test-Path -LiteralPath $checksPath) {
    $checksDefined = @(Get-Content -LiteralPath $checksPath | Where-Object { $_ -notmatch '^\s*(#|$)' }).Count -gt 0
}

if ($EmitChecks) {
    Get-DetectedChecks
    exit 0
}

if ($checksDefined) {
    Test-ChecksTsvValidation -FilePath $checksPath
    Write-Host "Using project checks: $checksPath"
    $script:Detected = $true
    Get-Content -LiteralPath $checksPath | ForEach-Object {
        if ($_ -match '^\s*(#|$)') { return }
        Invoke-TsvLine -Line $_
    }
}
else {
    if (Test-Path -LiteralPath $checksPath) {
        Write-Host "Note: $checksPath defines no checks; falling back to auto-detection."
    }
    Write-Host "Auto-detecting project stack (no checks.tsv)..."
    $detectedChecks = @(Get-DetectedChecks)
    if ($detectedChecks.Count -gt 0) {
        $script:Detected = $true
        foreach ($line in $detectedChecks) { Invoke-TsvLine -Line $line }
    }
}

Write-Host ""
# Priority: a real failure beats a blocked check; a blocked required check
# beats "PASS" because not every required check ran, so "all passed" cannot
# be claimed.
if ($script:Failed) {
    Write-Host "VERIFICATION FAILED: $($script:Ran) check(s) ran, at least one required check failed."
    exit 1
}
if ($script:Blocked) {
    Write-Host "VERIFICATION BLOCKED: $($script:Ran) check(s) ran; required tooling was unavailable."
    exit 2
}
if ($script:RanRequired) {
    Write-Host "VERIFICATION PASSED: $($script:Ran) check(s) ran."
    exit 0
}
if ($script:Detected) {
    Write-Host "VERIFICATION BLOCKED: $($script:Ran) check(s) ran; required tooling was unavailable."
    exit 2
}
Write-Host "VERIFICATION UNSUPPORTED: no supported project or check configuration found."
exit 3
