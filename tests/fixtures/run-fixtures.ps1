# run-fixtures.ps1 — smoke harness for verify.ps1.
#   exit-code assertions for the state-model fixtures,
#   --emit-checks detection assertions for the stack fixtures.
# usage: pwsh -NoProfile -File run-fixtures.ps1 <path-to-verify.ps1>
param([string] $Verify)

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fix = Join-Path $root "tests\fixtures"

$script:Failures = 0

function has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Check-Exe([string] $name) {
    # does the fixture's first check executable exist in this environment?
    $file = Join-Path $fix "$name\.agentic\checks.tsv"
    $line = Get-Content -LiteralPath $file | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1
    $exe = $line.Split("`t")[3]
    if ($exe.Contains('/')) { Test-Path -LiteralPath (Join-Path $fix "$name\$exe") } else { has $exe }
}

function Expect-Code([string] $name, [int] $expected) {
    $code = 0
    $absVerify = (Resolve-Path -LiteralPath $Verify).Path
    Push-Location (Join-Path $fix $name)
    try {
        $null = & pwsh -NoProfile -File $absVerify 2>&1
        $code = $LASTEXITCODE
    }
    finally { Pop-Location }
    $status = if ($code -eq $expected) { "OK" } else { "MISMATCH"; $script:Failures++ }
    "{0,-24} expected={1,-3} actual={2}  {3}" -f $name, $expected, $code, $status
}

function Expect-Detect([string] $name, [string[]] $tools) {
    $out = ""
    $absVerify = (Resolve-Path -LiteralPath $Verify).Path
    Push-Location (Join-Path $fix $name)
    try {
        $out = & pwsh -NoProfile -File $absVerify -EmitChecks 2>&1
    }
    finally { Pop-Location }
    $missing = 0
    if ($tools.Count -eq 1 -and $tools[0] -eq "__none__") {
        if ($out) { $missing = 1 }
    }
    else {
        foreach ($t in $tools) {
            if (($out | Out-String) -notmatch $t) { Write-Host "  $($name): did not emit $t"; $missing = 1 }
        }
    }
    $status = if ($missing -eq 0) { "OK" } else { "MISMATCH"; $script:Failures++ }
    "{0,-24} emit-checks       {1}" -f $name, $status
}

# State-model exit codes (executable availability makes them environment-aware).
Expect-Code "checks-tsv" 2
if (Check-Exe "checks-tsv-pass") { Expect-Code "checks-tsv-pass" 0 } else { Expect-Code "checks-tsv-pass" 2 }
if (Check-Exe "checks-tsv-fail") { Expect-Code "checks-tsv-fail" 1 } else { Expect-Code "checks-tsv-fail" 2 }
if (Check-Exe "checks-tsv-optional") { Expect-Code "checks-tsv-optional" 0 } else { Expect-Code "checks-tsv-optional" 2 }
Expect-Code "unsupported" 3
if (has npm) { Expect-Code "node-npm" 0 } else { Expect-Code "node-npm" 2 }
if (has npm) { Expect-Code "node-npm-fail" 1 } else { Expect-Code "node-npm-fail" 2 }

function Expect-Golden([string] $name) {
    # Exact golden contract: the sorted, comment-free emitted checks must equal
    # the checked-in golden file. Catches missing checks and unexpected extras.
    $gold = Join-Path $fix "golden\$name.tsv"
    $actual = ""
    $absVerify = (Resolve-Path -LiteralPath $Verify).Path
    Push-Location (Join-Path $fix $name)
    try {
        $actual = (& pwsh -NoProfile -File $absVerify -EmitChecks 2>&1 | Where-Object { $_ -and -not $_.StartsWith('Detected:') }) -join "`n"
    }
    finally { Pop-Location }
    $expected = Get-Content -LiteralPath $gold
    $actualSorted = ($actual -split "`n" | Where-Object { $_ -ne '' } | Sort-Object) -join "`n"
    $expectedSorted = ($expected | Sort-Object) -join "`n"
    $missing = 0
    if ($actualSorted -ne $expectedSorted) {
        Write-Host "  $($name): emitted contract differs from golden $gold"
        $missing = 1
    }
    $status = if ($missing -eq 0) { "OK" } else { "MISMATCH"; $script:Failures++ }
    "{0,-24} golden            {1}" -f $name, $status
}

# Stack detection via --emit-checks (deterministic).
Expect-Detect "node-bun" @("bun")
Expect-Detect "node-pnpm" @("pnpm")
Expect-Detect "python-uv" @("uv")
Expect-Detect "python-poetry" @("poetry")
Expect-Detect "dotnet-sln-only" @("dotnet")
Expect-Detect "dotnet-csproj-only" @("dotnet")
Expect-Detect "rust-cargo" @("cargo")
Expect-Detect "go-mod" @("go")
Expect-Detect "java-maven" @("mvn")
if ($IsWindows) {
    # both wrapper scripts are present; the Windows .cmd/.bat script must win
    Expect-Detect "java-maven-wrapper" @("mvnw.cmd")
    Expect-Detect "gradle-wrapper" @("gradlew.bat")
    Expect-Detect "android-gradle" @("gradlew.bat", "android-unit")
}
else {
    Expect-Detect "java-maven-wrapper" @("mvnw")
    Expect-Detect "gradle-wrapper" @("gradlew")
    Expect-Detect "android-gradle" @("gradlew", "android-unit")
}
Expect-Detect "monorepo" @("pnpm", "go")
Expect-Detect "polyglot-node-go" @("npm", "go")
Expect-Detect "nested-monorepo" @("npm", "go")
Expect-Detect "unsupported" @("__none__")

# Exact golden contracts for the deterministic fixtures (no platform-dependent
# wrapper selection). This is the same check the Bats/Pester suites run.
Get-ChildItem -LiteralPath (Join-Path $fix "golden") -Filter *.tsv | ForEach-Object {
    Expect-Golden ([System.IO.Path]::GetFileNameWithoutExtension($_.Name))
}

if ($script:Failures -gt 0) {
    Write-Error "$script:Failures fixture assertion(s) failed"
    exit 1
}
exit 0