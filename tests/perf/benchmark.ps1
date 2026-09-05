#Requires -Version 7.0
<#
.SYNOPSIS
    Measures verifier overhead on a synthetic large checks.tsv contract
    (default 300 checks, all no-ops). Reports contract-validation and
    full-run timings for the PowerShell verifier.

.DESCRIPTION
    Dev-only quality gate: this script is NOT part of .agentic/checks.tsv.

.EXAMPLE
    tests/perf/benchmark.ps1 300
#>
param([int] $N = 300)

$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '../..'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("agentic-perf-" + [System.IO.Path]::GetRandomFileName())
try {
    New-Item -ItemType Directory -Path (Join-Path $work '.agentic') -Force | Out-Null
    $noopExe, $noopArgs = if ($IsWindows) { 'cmd', "`t/c exit 0" } else { 'true', '' }
    # Rows use a literal tab separator (backtick-t), never spaces.
    $lines = foreach ($i in 1..$N) { "required" + "`t" + ("perf-{0:0000}" -f $i) + "`t" + "." + "`t" + $noopExe + $noopArgs }
    [System.IO.File]::WriteAllLines((Join-Path $work '.agentic/checks.tsv'), $lines, [System.Text.UTF8Encoding]::new($false))
    Copy-Item (Join-Path $root '.agentic/scripts/verify.ps1') (Join-Path $work 'verify.ps1')
    Push-Location $work
    try {
        $t0 = [System.Diagnostics.Stopwatch]::StartNew()
        & (Join-Path $work 'verify.ps1') -ValidateChecks (Join-Path $work '.agentic/checks.tsv') *> $null
        $validateMs = $t0.ElapsedMilliseconds
        $t0.Restart()
        & (Join-Path $work 'verify.ps1') *> $null
        $textMs = $t0.ElapsedMilliseconds
        # JSON mode writes via [Console]::Out, which bypasses in-process
        # redirection by design (stdout isolation). Run it as a child
        # process with a native handle redirect so the benchmark stays
        # quiet; the one process spawn is constant overhead, noted here.
        $pwshExe = (Get-Process -Id $PID).Path
        $jsonOut = Join-Path $work 'bench-json.out'
        $t0.Restart()
        $proc = Start-Process $pwshExe -ArgumentList '-NoProfile', '-File', (Join-Path $work 'verify.ps1'), '-Format', 'Json' -WorkingDirectory $work -RedirectStandardOutput $jsonOut -RedirectStandardError (Join-Path $work 'bench-json.err') -PassThru -Wait
        if ($proc.ExitCode -ne 0) { throw "benchmark JSON run exited $($proc.ExitCode)" }
        $jsonMs = $t0.ElapsedMilliseconds
    }
    finally { Pop-Location }
    "checks`tvalidate_ms`tfull_text_ms`tfull_json_ms"
    "$N`t$validateMs`t$textMs`t$jsonMs"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
