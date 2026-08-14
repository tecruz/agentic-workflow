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
    [string] $ValidateChecks
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
            $lines += "required`tnode-test`t.`tpnpm`ttest"
            $lines += "required`tnode-lint`t.`tpnpm`tlint"
        }
        elseif (Test-Path -LiteralPath yarn.lock) {
            $lines += "required`tnode-test`t.`tyarn`ttest"
            $lines += "required`tnode-lint`t.`tyarn`tlint"
        }
        elseif (Test-Path -LiteralPath bun.lockb) {
            $lines += "required`tnode-test`t.`tbun`ttest"
            $lines += "required`tnode-lint`t.`tbun`trun`tlint"
        }
        else {
            $lines += "required`tnode-test`t.`tnpm`ttest"
            $lines += "required`tnode-lint`t.`tnpm`trun`tlint`t--if-present"
        }
    }

    if (Test-Path -LiteralPath Cargo.toml) {
        Write-Host "Detected: Rust project (Cargo.toml)"
        $lines += "required`trust-test`t.`tcargo`ttest"
        $lines += "required`trust-clippy`t.`tcargo`tclippy`t--`t-D`twarnings"
    }

    if ((Test-Path -LiteralPath pyproject.toml) -or (Test-Path -LiteralPath requirements.txt)) {
        Write-Host "Detected: Python project (pyproject.toml / requirements.txt)"
        if (Test-Path -LiteralPath poetry.lock) {
            $lines += "required`tpython-test`t.`tpoetry`trun`tpytest"
            $lines += "required`tpython-ruff`t.`tpoetry`trun`truff`tcheck`t."
        }
        elseif (Test-Path -LiteralPath uv.lock) {
            $lines += "required`tpython-test`t.`tuv`trun`tpytest"
            $lines += "required`tpython-ruff`t.`tuv`trun`truff`tcheck`t."
        }
        else {
            $lines += "required`tpython-test`t.`tpytest"
            $lines += "required`tpython-ruff`t.`truff`tcheck`t."
        }
    }

    if (Test-Path -LiteralPath go.mod) {
        Write-Host "Detected: Go project (go.mod)"
        $lines += "required`tgo-test`t.`tgo`ttest`t./..."
        $lines += "required`tgo-vet`t.`tgo`tvet`t./..."
    }

    if (Test-Path -LiteralPath pom.xml) {
        Write-Host "Detected: Maven project (pom.xml)"
        if (Test-Path -LiteralPath ./mvnw) {
            $lines += "required`tmaven-test`t.`t./mvnw`ttest"
            $lines += "required`tmaven-lint`t.`t./mvnw`tcheckstyle:check"
        }
        else {
            $lines += "required`tmaven-test`t.`tmvn`ttest"
            $lines += "required`tmaven-lint`t.`tmvn`tcheckstyle:check"
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
            Write-Host "Detected: Android / Kotlin Gradle project (build.gradle)"
            if (Test-Path -LiteralPath ./gradlew) {
                $lines += "required`tandroid-unit`t.`t./gradlew`ttest"
                $lines += "required`tandroid-lint`t.`t./gradlew`tlint"
                $lines += "required`tandroid-build`t.`t./gradlew`tassembleDebug"
                $lines += "optional`tandroid-device`t.`t./gradlew`tconnectedCheck"
            }
            else {
                $lines += "required`tandroid-unit`t.`tgradle`ttest"
                $lines += "required`tandroid-lint`t.`tgradle`tlint"
                $lines += "required`tandroid-build`t.`tgradle`tassembleDebug"
                $lines += "optional`tandroid-device`t.`tgradle`tconnectedCheck"
            }
        }
        else {
            Write-Host "Detected: Gradle project (build.gradle)"
            if (Test-Path -LiteralPath ./gradlew) {
                $lines += "required`tgradle-test`t.`t./gradlew`ttest"
                $lines += "required`tgradle-lint`t.`t./gradlew`tcheck"
            }
            else {
                $lines += "required`tgradle-test`t.`tgradle`ttest"
                $lines += "required`tgradle-lint`t.`tgradle`tcheck"
            }
        }
    }

    if ((Get-ChildItem -Path . -Filter *.sln -File -ErrorAction SilentlyContinue) -or
        (Get-ChildItem -Path . -Filter *.csproj -File -ErrorAction SilentlyContinue)) {
        Write-Host "Detected: .NET project (*.sln / *.csproj)"
        $lines += "required`tdotnet-test`t.`tdotnet`ttest"
        $lines += "required`tdotnet-lint`t.`tdotnet`tformat`t--verify-no-changes"
    }

    foreach ($base in @('apps', 'services', 'packages', 'modules')) {
        if (Test-Path -LiteralPath $base -PathType Container) {
            $subs = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue
            foreach ($sub in $subs) {
                $subName = $sub.Name
                if ($subName -match "[\t\n\r\u001f\p{Cc}]") { continue }
                if ($subName -in @('node_modules', 'target', 'build', '.venv')) { continue }
                $subRel = "$base/$subName"
                $prefix = "$base-$subName"

                if (Test-Path -LiteralPath (Join-Path $subRel 'package.json')) {
                    Write-Host "Detected: Nested Node.js project ($subRel)"
                    if (Test-Path -LiteralPath (Join-Path $subRel 'pnpm-lock.yaml')) {
                        $lines += "required`t${prefix}-node-test`t${subRel}`tpnpm`ttest"
                        $lines += "required`t${prefix}-node-lint`t${subRel}`tpnpm`tlint"
                    }
                    elseif (Test-Path -LiteralPath (Join-Path $subRel 'yarn.lock')) {
                        $lines += "required`t${prefix}-node-test`t${subRel}`tyarn`ttest"
                        $lines += "required`t${prefix}-node-lint`t${subRel}`tyarn`tlint"
                    }
                    elseif (Test-Path -LiteralPath (Join-Path $subRel 'bun.lockb')) {
                        $lines += "required`t${prefix}-node-test`t${subRel}`tbun`ttest"
                        $lines += "required`t${prefix}-node-lint`t${subRel}`tbun`trun`tlint"
                    }
                    else {
                        $lines += "required`t${prefix}-node-test`t${subRel}`tnpm`ttest"
                        $lines += "required`t${prefix}-node-lint`t${subRel}`tnpm`trun`tlint`t--if-present"
                    }
                }
                if (Test-Path -LiteralPath (Join-Path $subRel 'go.mod')) {
                    Write-Host "Detected: Nested Go project ($subRel)"
                    $lines += "required`t${prefix}-go-test`t${subRel}`tgo`ttest`t./..."
                    $lines += "required`t${prefix}-go-vet`t${subRel}`tgo`tvet`t./..."
                }
                if (Test-Path -LiteralPath (Join-Path $subRel 'Cargo.toml')) {
                    Write-Host "Detected: Nested Rust project ($subRel)"
                    $lines += "required`t${prefix}-rust-test`t${subRel}`tcargo`ttest"
                    $lines += "required`t${prefix}-rust-clippy`t${subRel}`tcargo`tclippy`t--`t-D`twarnings"
                }
                if ((Test-Path -LiteralPath (Join-Path $subRel 'pyproject.toml')) -or (Test-Path -LiteralPath (Join-Path $subRel 'requirements.txt'))) {
                    Write-Host "Detected: Nested Python project ($subRel)"
                    $lines += "required`t${prefix}-python-test`t${subRel}`tpytest"
                    $lines += "required`t${prefix}-python-ruff`t${subRel}`truff`tcheck`t."
                }
            }
        }
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
    $winPlatform = [bool]$IsWindows -or ($env:OS -eq 'Windows_NT')
    $pathComparer = if ($winPlatform) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    foreach ($part in $parts) {
        $current = Join-Path $current $part
        $seen = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
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
        $winPlatform = [bool]$IsWindows -or ($env:OS -eq 'Windows_NT')
        $pathComparison = if ($winPlatform) {
            [System.StringComparison]::OrdinalIgnoreCase
        }
        else {
            [System.StringComparison]::Ordinal
        }
        $insideRoot =
            $resolvedCwd.Equals($resolvedRootTrimmed, $pathComparison) -or
            $resolvedCwd.StartsWith($rootPrefix, $pathComparison)
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

if ($ValidateChecks) {
    if (-not (Test-Path -LiteralPath $ValidateChecks)) {
        Write-Host "ERROR: file '$ValidateChecks' does not exist."
        exit 1
    }
    Test-ChecksTsvValidation -FilePath $ValidateChecks
    Write-Host "Checks file '$ValidateChecks' is valid."
    exit 0
}

if ($ExplainDetection) {
    Write-Host "=== Project Detection Explanation ==="
    $null = Get-DetectedChecks
    exit 0
}

if ($DetectChecks) {
    $genFile = ".agentic/checks.generated.tsv"
    $null = New-Item -ItemType Directory -Path ".agentic" -Force
    $checks = @(Get-DetectedChecks)
    if ($checks.Count -eq 0) {
        Write-Host "No stack detected."
        exit 0
    }
    $tmp = [System.IO.Path]::GetTempFileName()
    $content = @(
        "# .agentic/checks.generated.tsv — candidate verification contract.",
        "# Auto-generated by detection workflow. Review assumptions and promote to .agentic/checks.tsv"
    ) + $checks
    [System.IO.File]::WriteAllLines($tmp, $content, [System.Text.UTF8Encoding]::new($false))
    try {
        Test-ChecksTsvValidation -FilePath $tmp
        Move-Item -LiteralPath $tmp -Destination $genFile -Force
        Write-Host "Candidate contract written to $genFile"
    }
    catch {
        Write-Host "ERROR: Generated checks failed validation: $_"
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        exit 1
    }
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
        $tmp = [System.IO.Path]::GetTempFileName()
        [System.IO.File]::WriteAllLines($tmp, $detectedChecks, [System.Text.UTF8Encoding]::new($false))
        try {
            Test-ChecksTsvValidation -FilePath $tmp
        }
        catch {
            Write-Host "ERROR: Auto-detected checks failed validation: $_"
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            exit 1
        }
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
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
