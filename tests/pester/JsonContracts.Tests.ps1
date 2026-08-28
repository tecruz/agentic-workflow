# JsonContracts.Tests.ps1 — JSON result contracts and schema validation tests (Pester 5).

# Helper functions at script level for use in all Describe blocks
function Test-EventSchemaValid {
    param([string]$EventFile)
    $lines = Get-Content -LiteralPath $EventFile
    $lines.Count | Should -BeGreaterThan 2
    $lines[0] | Should -Match 'verification_started'
    $lines[-1] | Should -Match 'verification_completed'

    $eventCount = @($lines | Where-Object { $_ -match '"event"\s*:\s*"verification_completed"' }).Count
    $eventCount | Should -Be 1

    foreach ($line in $lines) {
        $event = $line | ConvertFrom-Json
        $json = $line | ConvertTo-Json -Compress
        $null = $json | ConvertFrom-Json # validate JSON
        $event.GetType().Name | Should -Be 'PSCustomObject'
        $event.event | Should -Not -BeNullOrEmpty
    }
}

function Test-JsonAgainstSchema {
    param([string]$JsonPath, [string]$SchemaPath)
    $cmd = "import json, jsonschema, sys; jsonschema.validate(instance=json.load(open(sys.argv[1], encoding='utf-8')), schema=json.load(open(sys.argv[2], encoding='utf-8')))"
    python -c $cmd $JsonPath $SchemaPath 2>&1
    return $LASTEXITCODE
}

Describe 'v1.4.0 JSON result contracts and schema validation' {

    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $verifySh = Join-Path $repoRoot '.agentic/scripts/verify.sh'
        $verifyPs = Join-Path $repoRoot '.agentic/scripts/verify.ps1'
        $validateSh = Join-Path $repoRoot '.agentic/scripts/validate-task.sh'
        $validatePs = Join-Path $repoRoot '.agentic/scripts/validate-task.ps1'
        $verifySchema = Join-Path $repoRoot '.agentic/schemas/verification-result-v1.schema.json'
        $taskSchema = Join-Path $repoRoot '.agentic/schemas/task-validation-result-v1.schema.json'
        $fixtures = Join-Path $repoRoot 'tests/fixtures'
        $tasksFixtures = Join-Path $fixtures 'tasks'

        function Test-JsonValid([string]$jsonPath, [string]$schemaPath) {
            $cmd = "import json, jsonschema, sys; jsonschema.validate(instance=json.load(open(sys.argv[1], encoding='utf-8')), schema=json.load(open(sys.argv[2], encoding='utf-8')))"
            python -c $cmd $jsonPath $schemaPath 2>&1
            return $LASTEXITCODE
        }
    }

    It 'verification result JSON validates against verification-result-v1.schema.json (Bash)' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $fixDir = Join-Path $fixtures 'node-npm'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $fixDir
        try {
            $outLines = & bash $verifySh --format json 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        }
        finally { Pop-Location }
        $code | Should -BeIn 0, 1, 2, 3
        (Test-JsonValid $tmpOut $verifySchema) | Should -Be 0
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'verification result JSON validates against verification-result-v1.schema.json (PowerShell)' {
        $fixDir = Join-Path $fixtures 'node-npm'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $fixDir
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        }
        finally { Pop-Location }
        $code | Should -BeIn 0, 1, 2, 3
        (Test-JsonValid $tmpOut $verifySchema) | Should -Be 0
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'task validation result JSON validates against task-validation-result-v1.schema.json (Valid task)' {
        $taskFile = Join-Path $tasksFixtures 'standard-valid.md'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $outLines = & pwsh -NoProfile -File $validatePs -Format Json $taskFile 2> $null
        $code = $LASTEXITCODE
        [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        $code | Should -Be 0
        (Test-JsonValid $tmpOut $taskSchema) | Should -Be 0
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'task validation result JSON validates against task-validation-result-v1.schema.json (Invalid/Blocked task with diagnostics)' {
        $taskFile = Join-Path $tasksFixtures 'standard-missing-baseline.md'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $outLines = & pwsh -NoProfile -File $validatePs -Format Json $taskFile 2> $null
        $code = $LASTEXITCODE
        [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        $code | Should -Be 1
        (Test-JsonValid $tmpOut $taskSchema) | Should -Be 0
        $parsed = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        $parsed.diagnostics.Count | Should -BeGreaterThan 0
        $parsed.diagnostics[0].code | Should -Not -BeNullOrEmpty
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'optional JSONL run events stream is produced correctly with -Events (text mode)' {
        $fixDir = Join-Path $fixtures 'node-npm'
        $eventFile = Join-Path $fixDir '.agentic/runs/test-event.jsonl'
        if (Test-Path -LiteralPath $eventFile) { Remove-Item -LiteralPath $eventFile -Force }
        Push-Location $fixDir
        try {
            $null = & pwsh -NoProfile -File $verifyPs -Events '.agentic/runs/test-event.jsonl' 2> $null
        }
        finally { Pop-Location }
        Test-Path -LiteralPath $eventFile | Should -Be $true
        $lines = Get-Content -LiteralPath $eventFile
        $lines.Count | Should -BeGreaterThan 2
        $lines[0] | Should -Match 'verification_started'
        $lines[-1] | Should -Match 'verification_completed'
        Remove-Item -LiteralPath $eventFile -ErrorAction SilentlyContinue
    }

    It 'verification result JSON is text-mode backward compatible (stderr only)' {
        # In text mode, stdout should contain no JSON contamination;
        # only progress lines on stderr (captured here as they go to stderr).
        # Skips on Windows like the bash-schema test: git-bash cannot consume
        # the Windows-style script path; Linux/macOS jobs cover this.
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $fixDir = Join-Path $fixtures 'node-npm'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $fixDir
        try {
            $outLines = @(& bash $verifySh 2> $null)
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        }
        finally { Pop-Location }
        $code | Should -BeIn 0, 1, 2, 3
        # Verify stdout has no JSON document (only plain text or empty)
        $stdoutContent = ($outLines | Select-String -Pattern '^\s*\{' | Measure-Object).Count
        $stdoutContent | Should -Be 0
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'verification result JSON stays well-formed when python3 is unavailable' {
        # The Bash verifier's only python3 uses are duration timestamps with
        # graceful fallbacks; shadow both interpreters with failing stubs and
        # require the JSON contract to remain intact. Mirrors the bash-schema
        # test's platform guard.
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $fixDir = Join-Path $fixtures 'node-npm'
        $stubDir = Join-Path $TestDrive 'pystub'
        New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $stubDir 'python3') -Value "#!/bin/sh`nexit 127" -NoNewline
        Set-Content -LiteralPath (Join-Path $stubDir 'python') -Value "#!/bin/sh`nexit 127" -NoNewline
        & bash -c "chmod +x `"$stubDir/python3`" `"$stubDir/python`"" 2>$null
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $fixDir
        try {
            $oldPath = $env:PATH
            $env:PATH = "$stubDir$([System.IO.Path]::PathSeparator)$oldPath"
            try {
                $outLines = @(& bash $verifySh --format json 2> $null)
                $code = $LASTEXITCODE
            }
            finally { $env:PATH = $oldPath }
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            # Parse while the temp file still exists — the finally block below
            # removes it, and parsing a deleted file would fail spuriously on
            # Linux CI where this test actually runs.
            $script:pyStubDoc = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        }
        finally {
            Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            Pop-Location
        }
        # The verifier must still complete with exactly one well-formed JSON document.
        $code | Should -BeIn 0, 1, 2, 3
        $script:pyStubDoc.schema_version | Should -Be 1
    }

    It 'task validation result JSON echoes declared profile and task_status' {
        $taskFile = Join-Path $tasksFixtures 'standard-valid.md'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $outLines = & pwsh -NoProfile -File $validatePs -Format Json $taskFile 2> $null
        $code = $LASTEXITCODE
        [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        $code | Should -Be 0
        $parsed = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        # Declared, recognized values pass through unchanged; no raw_* mirror
        # fields are part of the contract.
        $parsed.profile | Should -Be 'standard'
        $parsed.task_status | Should -Be 'done'
        ($parsed.PSObject.Properties.Name) | Should -Not -Contain 'raw_profile'
        ($parsed.PSObject.Properties.Name) | Should -Not -Contain 'raw_task_status'
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'task validation result JSON includes recognized values even when blocked' {
        # The fixture is marked done with unresolved evidence: BLOCKED (2), but
        # the declared status value is still echoed faithfully.
        $taskFile = Join-Path $tasksFixtures 'done-code-wrapped-pending-blocked.md'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $outLines = & pwsh -NoProfile -File $validatePs -Format Json $taskFile 2> $null
        $code = $LASTEXITCODE
        [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        $code | Should -Be 2
        $parsed = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        $parsed.task_status | Should -Be 'done'
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'task validation result JSON has nullable profile when missing' {
        # The fixture declares Profile: wat, which is not a recognized profile.
        $taskFile = Join-Path $tasksFixtures 'unknown-profile.md'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $outLines = & pwsh -NoProfile -File $validatePs -Format Json $taskFile 2> $null
        $code = $LASTEXITCODE
        [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        $code | Should -Be 1
        $parsed = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        # profile should be null when not declared/recognized; no defaults.
        $parsed.profile | Should -Be $null
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'task validation result JSON has nullable task_status when unrecognized' {
        # The fixture declares 'Status: not done', which is not a valid status.
        $taskFile = Join-Path $tasksFixtures 'unknown-status.md'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $outLines = & pwsh -NoProfile -File $validatePs -Format Json $taskFile 2> $null
        $code = $LASTEXITCODE
        [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
        $code | Should -Be 1
        $parsed = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        $parsed.task_status | Should -Be $null
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'events emit terminal verification_completed in text mode' {
        $fixDir = Join-Path $fixtures 'node-npm'
        $eventFile = Join-Path $fixDir '.agentic/runs/test-event-text.jsonl'
        if (Test-Path -LiteralPath $eventFile) { Remove-Item -LiteralPath $eventFile -Force }
        Push-Location $fixDir
        try {
            $null = & pwsh -NoProfile -File $verifyPs -Format Text -Events '.agentic/runs/test-event-text.jsonl' 2> $null
        }
        finally { Pop-Location }
        if (Test-Path -LiteralPath $eventFile) {
            $lines = Get-Content -LiteralPath $eventFile
            $lines.Count | Should -BeGreaterThan 2
            $lines[0] | Should -Match 'verification_started'
            $lines[-1] | Should -Match 'verification_completed'
            Remove-Item -LiteralPath $eventFile -ErrorAction SilentlyContinue
        }
    }

    # -----------------------------------------------------------------------
    # PR #9 review regression coverage: optional-failure PASS documents,
    # nested working-directory labels, JSON-wide path redaction, and strict
    # --format parsing. The Bash legs mirror the dedicated Bats cases and run
    # on the Linux/macOS CI jobs.
    # -----------------------------------------------------------------------

    It 'PASS with a failing optional check is schema-valid and separates failure counts (Bash)' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $fixDir = Join-Path $fixtures 'checks-tsv-optional'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $fixDir
        try {
            $outLines = & bash $verifySh --format json 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            # Parse and schema-check while the temp file still exists.
            $doc = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
            $script:schemaExit = Test-JsonValid $tmpOut $verifySchema
        }
        finally {
            Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            Pop-Location
        }
        $code | Should -Be 0
        $script:schemaExit | Should -Be 0
        $doc.result | Should -Be 'PASS'
        $doc.summary.failed | Should -Be 0
        $doc.summary.optional_failed | Should -Be 1
        $doc.summary.required_run | Should -Be 1
    }

    It 'PASS with a failing optional check is schema-valid and separates failure counts (PowerShell)' {
        if (-not (Get-Command sh -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'sh not available'; return }
        $fixDir = Join-Path $fixtures 'checks-tsv-optional'
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $fixDir
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            $doc = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
            $script:schemaExit = Test-JsonValid $tmpOut $verifySchema
        }
        finally {
            Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            Pop-Location
        }
        $code | Should -Be 0
        $script:schemaExit | Should -Be 0
        $doc.result | Should -Be 'PASS'
        $doc.summary.failed | Should -Be 0
        $doc.summary.optional_failed | Should -Be 1
        $doc.summary.required_run | Should -Be 1
    }

    It 'PASS with a skipped optional check is schema-valid (PowerShell)' {
        $proj = Join-Path $TestDrive "optional-skipped-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        @(
            "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0",
            "optional`tmissing-tool`t.`tno-such-tool-xyz`tcheck"
        ) | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            $doc = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        }
        finally {
            Pop-Location
            Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force
        }
        $code | Should -Be 0
        $doc.result | Should -Be 'PASS'
        $doc.summary.failed | Should -Be 0
        $doc.summary.optional_skipped | Should -Be 1
    }

    It 'required failure plus passing optional check yields FAIL/1 with schema-valid JSON (Bash)' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $proj = Join-Path $TestDrive "required-fail-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        @(
            "required`tbroken`t.`tsh`t-c`texit 3",
            "optional`tfine`t.`tsh`t-c`texit 0"
        ) | Set-Content -LiteralPath (Join-Path $proj '.agentic/checks.tsv')
        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & bash $verifySh --format json 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            $doc = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
            $script:schemaExit = Test-JsonValid $tmpOut $verifySchema
        }
        finally {
            Pop-Location
            Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        }
        $code | Should -Be 1
        $script:schemaExit | Should -Be 0
        $doc.result | Should -Be 'FAIL'
        $doc.summary.failed | Should -Be 1
        $doc.summary.optional_failed | Should -Be 0
    }

    It 'nested working directories keep full project-relative labels in both implementations' {
        $fixDir = Join-Path $fixtures 'checks-tsv-nested-cwd'
        $expectedLabels = @('./apps/api', './services/api', './packages/shared')

        $tmpOut = [System.IO.Path]::GetTempFileName()
        Push-Location $fixDir
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            $psDoc = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
        }
        finally { Pop-Location }
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
        $code | Should -Be 0
        @($psDoc.checks.working_directory) | Should -Be $expectedLabels

        if (-not $IsWindows) {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            Push-Location $fixDir
            try {
                $outLines = & bash $verifySh --format json 2> $null
                $code = $LASTEXITCODE
                [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
                $bashDoc = Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json
            }
            finally {
                Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
                Pop-Location
            }
            $code | Should -Be 0
            @($bashDoc.checks.working_directory) | Should -Be $expectedLabels
        }
    }

    It 'task-validator JSON redacts absolute task paths from every serialized field (PowerShell)' {
        # Both foreign-path shapes are exercised on both platform families:
        # the native absolute form and the other platform's absolute form.
        $paths = @(
            'C:\Users\Alice\private-project\TASK.md',
            '/home/alice/private-project/TASK.md'
        )
        foreach ($p in $paths) {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            $outLines = & pwsh -NoProfile -File $validatePs -Format Json $p 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            $raw = Get-Content -LiteralPath $tmpOut -Raw
            Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            $code | Should -Be 1
            $parsed = $raw | ConvertFrom-Json
            $parsed.task_file | Should -Be 'TASK.md'
            $parsed.diagnostics[0].code | Should -Be 'TASK_FILE_NOT_FOUND'
            # Whole-document redaction: no user or secret-looking segment may
            # appear anywhere in the serialized JSON, not only in task_file.
            $raw | Should -Not -Match '(?i)alice|private-project|Users\\|Users/|home/'
        }
    }

    It 'task-validator JSON redacts absolute task paths from every serialized field (Bash)' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $paths = @(
            '/home/alice/private-project/TASK.md',
            'C:\Users\Alice\private-project\TASK.md'
        )
        foreach ($p in $paths) {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            $outLines = & bash $validateSh --format json $p 2> $null
            $code = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpOut, $outLines, [System.Text.UTF8Encoding]::new($false))
            $raw = Get-Content -LiteralPath $tmpOut -Raw
            Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            $code | Should -Be 1
            $parsed = $raw | ConvertFrom-Json
            $parsed.task_file | Should -Be 'TASK.md'
            $parsed.diagnostics[0].code | Should -Be 'TASK_FILE_NOT_FOUND'
            $raw | Should -Not -Match '(?i)alice|private-project|Users\\|Users/|home/'
        }
    }

    It 'verify.ps1 rejects unsupported output formats like the Bash verifier' {
        foreach ($bad in @('Yaml', 'banana')) {
            $out = & pwsh -NoProfile -File $verifyPs -Format $bad 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($out | Out-String) | Should -Match 'Format'
        }
    }

    It 'validate-task.ps1 rejects unsupported output formats like the Bash validator' {
        $out = & pwsh -NoProfile -File $validatePs -Format banana (Join-Path $tasksFixtures 'standard-valid.md') 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        ($out | Out-String) | Should -Match 'Format'
    }

    It 'Bash entry points reject unsupported and missing --format values' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        foreach ($argSpec in @('--format yaml', '--format', "--format=banana")) {
            $out = & bash -c "cd '$fixtures/node-npm' && bash '$verifySh' $argSpec" 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out | Out-String) | Should -Match "--format"
        }
        $out = & bash -c "bash '$validateSh' --format banana" 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out | Out-String) | Should -Match "--format must be 'text' or 'json'"
        $out = & bash -c "bash '$validateSh' --format" 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out | Out-String) | Should -Match "--format requires a value"
    }
}

Describe 'Context selection JSON contracts and schema validation' {

    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $contextSchema = Join-Path $repoRoot '.agentic/schemas/context-selection-v1.schema.json'
        $contextValidatePs = Join-Path $repoRoot '.agentic/scripts/validate-context.ps1'
        $contextValidateSh = Join-Path $repoRoot '.agentic/scripts/validate-context.sh'
        $contextFixtures = Join-Path $repoRoot 'tests/fixtures/context-tasks'

        # Self-contained: Pester 5 It-blocks cannot call helpers defined at
        # other scopes, so this mirrors Test-JsonAgainstSchema locally and
        # returns the python exit code.
        function Test-ContextSchemaValid([string]$JsonPath, [string]$SchemaPath) {
            $cmd = "import json, jsonschema, sys; jsonschema.validate(instance=json.load(open(sys.argv[1], encoding='utf-8')), schema=json.load(open(sys.argv[2], encoding='utf-8')))"
            $null = python -c $cmd $JsonPath $SchemaPath 2>&1
            return $LASTEXITCODE
        }

        function Test-ContextJsonContract([string]$fixture, [int]$expectedExit) {
            $tmpOut = [System.IO.Path]::GetTempFileName()
            try {
                $outLines = & pwsh -NoProfile -File $contextValidatePs -Format Json (Join-Path $contextFixtures $fixture) 2> $null
                $code = $LASTEXITCODE
                [System.IO.File]::WriteAllLines($tmpOut, @($outLines), [System.Text.UTF8Encoding]::new($false))
                $code | Should -Be $expectedExit
                (Test-ContextSchemaValid -JsonPath $tmpOut -SchemaPath $contextSchema) | Should -Be 0
                return (Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json)
            }
            finally { Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue }
        }
    }

    It 'context validation result JSON validates against context-selection-v1.schema.json (PowerShell, valid)' {
        $doc = Test-ContextJsonContract 'context-valid-single.md' 0
        $doc.kind | Should -Be 'context_validation_result'
        $doc.result | Should -Be 'VALID'
        @($doc.selected_modules).Count | Should -Be 1
        $doc.selected_modules[0].id | Should -Be 'security-review'
    }

    It 'context validation result JSON validates against context-selection-v1.schema.json (PowerShell, invalid)' {
        $doc = Test-ContextJsonContract 'context-unknown-module.md' 1
        $doc.result | Should -Be 'INVALID'
        @($doc.diagnostics).Count | Should -BeGreaterThan 0
        $doc.diagnostics[0].code | Should -Be 'MODULE_UNKNOWN'
    }

    It 'context validation result JSON validates against context-selection-v1.schema.json (Bash, valid)' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        # CI runs this leg on Linux where the checkout path is already POSIX.
        $taskPath = (Join-Path $contextFixtures 'context-valid-single.md') -replace '\\', '/'
        $outLines = & bash $contextValidateSh --format json $taskPath 2> $null
        $code = $LASTEXITCODE
        $code | Should -Be 0
        $doc = (@($outLines) -join "`n") | ConvertFrom-Json
        $doc.kind | Should -Be 'context_validation_result'
        $doc.result | Should -Be 'VALID'
    }

    It 'context validation result JSON validates against context-selection-v1.schema.json (Bash, invalid)' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $taskPath = (Join-Path $contextFixtures 'context-unknown-module.md') -replace '\\', '/'
        $outLines = & bash $contextValidateSh --format json $taskPath 2> $null
        $code = $LASTEXITCODE
        $code | Should -Be 1
        $doc = (@($outLines) -join "`n") | ConvertFrom-Json
        $doc.diagnostics.Count | Should -BeGreaterThan 0
        $doc.diagnostics[0].code | Should -Be 'MODULE_UNKNOWN'
    }
}

Describe 'Event schema validation' {
    BeforeEach {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $verifyPs = Join-Path $repoRoot '.agentic/scripts/verify.ps1'
        $verifySh = Join-Path $repoRoot '.agentic/scripts/verify.sh'
        $fixtures = Join-Path $repoRoot 'tests/fixtures'
        $eventSchemaPath = Join-Path $repoRoot '.agentic/schemas/verification-events-v1.schema.json'
        $verifySchema = Join-Path $repoRoot '.agentic/schemas/verification-result-v1.schema.json'
    }

    BeforeAll {
        function Test-EventSchemaValid {
            param([string]$EventFile)
            $lines = Get-Content -LiteralPath $EventFile
            $lines.Count | Should -BeGreaterThan 1
            $lines[0] | Should -Match 'verification_started'
            $lines[-1] | Should -Match 'verification_completed'
            $eventCount = @($lines | Where-Object { $_ -match '"event"\s*:\s*"verification_completed"' }).Count
            $eventCount | Should -Be 1
            foreach ($line in $lines) {
                $event = $line | ConvertFrom-Json
                $json = $line | ConvertTo-Json -Compress
                $null = $json | ConvertFrom-Json
                $event.GetType().Name | Should -Be 'PSCustomObject'
                $event.event | Should -Not -BeNullOrEmpty
            }
        }

        function Test-JsonAgainstSchema {
            param([string]$JsonPath, [string]$SchemaPath)
            $cmd = "import json, jsonschema, sys; jsonschema.validate(instance=json.load(open(sys.argv[1], encoding='utf-8')), schema=json.load(open(sys.argv[2], encoding='utf-8')))"
            python -c $cmd $JsonPath $SchemaPath 2>&1
            return $LASTEXITCODE
        }

        function Test-JsonLinesAgainstSchema {
            param([string]$JsonLinesPath, [string]$SchemaPath)
            $lines = Get-Content -LiteralPath $JsonLinesPath
            foreach ($line in $lines) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $tmpJson = [System.IO.Path]::GetTempFileName()
                    $line | Set-Content -LiteralPath $tmpJson -Encoding UTF8
                    $cmd = "import json, jsonschema, sys; jsonschema.validate(instance=json.load(open(sys.argv[1], encoding='utf-8')), schema=json.load(open(sys.argv[2], encoding='utf-8')))"
                    python -c $cmd $tmpJson $SchemaPath 2>&1
                    $code = $LASTEXITCODE
                    Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
                    if ($code -ne 0) { return $code }
                }
            }
            return 0
        }

        function Assert-EventStreamInvariants {
            param(
                [string]$EventFile,
                [int]$ProcessExitCode,
                [string]$ExpectedResult,
                [object]$JsonDoc = $null
            )
            $lines = Get-Content -LiteralPath $EventFile
            $lines.Count | Should -BeGreaterThan 1 -Because "event stream must have at least started+completed"
            $events = @()
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $evt = $line | ConvertFrom-Json
                $events += $evt
                # ensure each line is valid JSON
                $null = $line | ConvertFrom-Json
            }
            # 1: verification_started is first
            $events[0].event | Should -Be 'verification_started' -Because "first event must be verification_started"
            # 2: exactly one verification_completed and it is last
            $termCount = @($events | Where-Object { $_.event -eq 'verification_completed' }).Count
            $termCount | Should -Be 1 -Because "exactly one terminal event required"
            $events[-1].event | Should -Be 'verification_completed' -Because "terminal event must be last"
            # 3: terminal result/exit_code matches process
            $events[-1].result | Should -Be $ExpectedResult
            $events[-1].exit_code | Should -Be $ProcessExitCode
            $mapped = switch ($ExpectedResult) { 'PASS' {0} 'FAIL' {1} 'BLOCKED' {2} 'UNSUPPORTED' {3} default { -1 } }
            $ProcessExitCode | Should -Be $mapped -Because "exit_code must match result $ExpectedResult"
            # 4: ordering and check_started / check_completed correspondence
            $startedMap = @{}
            $completedList = @()
            $seenCompleted = @{}
            for ($i = 0; $i -lt $events.Count; $i++) {
                $e = $events[$i]
                if ($e.event -eq 'check_started') {
                    $cid = $e.check_id
                    if (-not $startedMap.ContainsKey($cid)) { $startedMap[$cid] = 0 }
                    $startedMap[$cid]++
                    $startedMap[$cid] | Should -Be 1 -Because "check $cid should have exactly one check_started"
                } elseif ($e.event -eq 'check_completed') {
                    $cid = $e.check_id
                    $completedList += $e
                    if (-not $seenCompleted.ContainsKey($cid)) { $seenCompleted[$cid] = 0 }
                    $seenCompleted[$cid]++
                    $seenCompleted[$cid] | Should -Be 1 -Because "check $cid must have exactly one check_completed"
                    if ($e.status -in @('PASS','FAIL')) {
                        $i | Should -BeGreaterThan 0 -Because "executed check $cid needs preceding started"
                        $prev = $events[$i - 1]
                        $prev.event | Should -Be 'check_started' -Because "executed check $cid must have immediate preceding check_started"
                        $prev.check_id | Should -Be $cid
                        $startedMap.ContainsKey($cid) | Should -Be $true
                        $startedMap[$cid] | Should -Be 1
                    } else {
                        # BLOCKED / SKIPPED_OPTIONAL must have no started
                        $hasStarted = $startedMap.ContainsKey($cid) -and $startedMap[$cid] -gt 0
                        $hasStarted | Should -Be $false -Because "blocked/skipped $cid must have no check_started"
                        if ($i -gt 0) {
                            $prev = $events[$i - 1]
                            if ($prev.event -eq 'check_started' -and $prev.check_id -eq $cid) {
                                throw "BLOCKED/SKIPPED $cid should not have preceding check_started"
                            }
                        }
                    }
                }
            }
            # 5: total started == PASS+FAIL count
            $passFailCount = @($completedList | Where-Object { $_.status -in @('PASS','FAIL') }).Count
            $startedTotal = 0
            foreach ($v in $startedMap.Values) { $startedTotal += $v }
            $startedTotal | Should -Be $passFailCount -Because "started count must equal executed checks"
            # 6: if JsonDoc provided, cross-check correspondence
            if ($null -ne $JsonDoc) {
                $JsonDoc.result | Should -Be $ExpectedResult
                $JsonDoc.exit_code | Should -Be $ProcessExitCode
                $jsonChecks = @($JsonDoc.checks)
                # For UNSUPPORTED, jsonChecks.Count is 0 and completedList may be 0
                $jsonChecks.Count | Should -Be $completedList.Count -Because "every result check must have exactly one check_completed"
                foreach ($jc in $jsonChecks) {
                    $match = @($completedList | Where-Object { $_.check_id -eq $jc.id })
                    $match.Count | Should -Be 1 -Because "json check $($jc.id) must match one event"
                    $match[0].status | Should -Be $jc.status
                    if ($null -eq $jc.exit_code) {
                        $match[0].exit_code | Should -Be $null
                    } else {
                        $match[0].exit_code | Should -Be $jc.exit_code
                    }
                    $match[0].reason_code | Should -Be $jc.reason_code
                    $match[0].working_directory | Should -Be $jc.working_directory
                }
                foreach ($ce in $completedList) {
                    $found = @($jsonChecks | Where-Object { $_.id -eq $ce.check_id })
                    $found.Count | Should -Be 1 -Because "event $($ce.check_id) must have matching json check"
                }
            }
        }

        function Get-NormalizedEvents {
            param([string]$Path)
            $lines = Get-Content -LiteralPath $Path
            $events = @()
            foreach ($l in $lines) {
                $e = $l | ConvertFrom-Json
                if ($null -ne $e.duration_ms) { $e.duration_ms = 0 }
                $events += $e
            }
            return $events
        }
    }

    # ---------- helpers for running verifier and capturing JSON + events ----------

    It 'event stream validates against schema (text mode, required PASS)' {
        $proj = Join-Path $TestDrive "ev-pass-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0" | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $eventRel = '.agentic/runs/test-event-schema-pass.jsonl'
        $eventFile = Join-Path $proj $eventRel
        $tmpJson = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $jsonExit = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpJson, $outLines, [System.Text.UTF8Encoding]::new($false))
            $jsonDoc = Get-Content -LiteralPath $tmpJson -Raw | ConvertFrom-Json
            $null = & pwsh -NoProfile -File $verifyPs -Events $eventRel 2> $null
            $evExit = $LASTEXITCODE
        }
        finally { Pop-Location }
        $evExit | Should -Be 0
        $jsonExit | Should -Be $evExit
        $jsonDoc.result | Should -Be 'PASS'
        Test-EventSchemaValid $eventFile
        (Test-JsonLinesAgainstSchema $eventFile $eventSchemaPath) | Should -Be 0
        Assert-EventStreamInvariants -EventFile $eventFile -ProcessExitCode $evExit -ExpectedResult 'PASS' -JsonDoc $jsonDoc
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event stream validates against schema (text mode, required FAIL)' {
        $proj = Join-Path $TestDrive "ev-fail-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        "required`tfail`t.`tpwsh`t-NoProfile`t-Command`texit`t3" | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $eventRel = '.agentic/runs/test-event-fail.jsonl'
        $eventFile = Join-Path $proj $eventRel
        $tmpJson = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $jsonExit = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpJson, $outLines, [System.Text.UTF8Encoding]::new($false))
            $jsonDoc = Get-Content -LiteralPath $tmpJson -Raw | ConvertFrom-Json
            $null = & pwsh -NoProfile -File $verifyPs -Events $eventRel 2> $null
            $evExit = $LASTEXITCODE
        }
        finally { Pop-Location }
        $evExit | Should -Be 1
        $jsonExit | Should -Be $evExit
        $jsonDoc.result | Should -Be 'FAIL'
        Test-EventSchemaValid $eventFile
        (Test-JsonLinesAgainstSchema $eventFile $eventSchemaPath) | Should -Be 0
        Assert-EventStreamInvariants -EventFile $eventFile -ProcessExitCode $evExit -ExpectedResult 'FAIL' -JsonDoc $jsonDoc
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event stream validates against schema (text mode, required BLOCKED)' {
        $proj = Join-Path $TestDrive "ev-blocked-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        @(
            "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0",
            "required`tblocked`t.`tdefinitely-not-a-real-tool`t--version"
        ) | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $eventRel = '.agentic/runs/test-event-blocked.jsonl'
        $eventFile = Join-Path $proj $eventRel
        $tmpJson = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $jsonExit = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpJson, $outLines, [System.Text.UTF8Encoding]::new($false))
            $jsonDoc = Get-Content -LiteralPath $tmpJson -Raw | ConvertFrom-Json
            $null = & pwsh -NoProfile -File $verifyPs -Events $eventRel 2> $null
            $evExit = $LASTEXITCODE
        }
        finally { Pop-Location }
        $evExit | Should -Be 2
        $jsonExit | Should -Be $evExit
        $jsonDoc.result | Should -Be 'BLOCKED'
        $jsonDoc.summary.blocked | Should -Be 1
        Test-EventSchemaValid $eventFile
        (Test-JsonLinesAgainstSchema $eventFile $eventSchemaPath) | Should -Be 0
        Assert-EventStreamInvariants -EventFile $eventFile -ProcessExitCode $evExit -ExpectedResult 'BLOCKED' -JsonDoc $jsonDoc
        # blocked check must not have check_started, executed one must
        $evLines = Get-Content -LiteralPath $eventFile | ForEach-Object { $_ | ConvertFrom-Json }
        $blocked = @($evLines | Where-Object { $_.event -eq 'check_completed' -and $_.status -eq 'BLOCKED' })
        $blocked.Count | Should -Be 1
        $startedBlocked = @($evLines | Where-Object { $_.event -eq 'check_started' -and $_.check_id -eq $blocked[0].check_id })
        $startedBlocked.Count | Should -Be 0
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event stream validates against schema (text mode, optional FAIL - PASS with optional_failed)' {
        $proj = Join-Path $TestDrive "ev-optfail-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        @(
            "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0",
            "optional`topt-fails`t.`tpwsh`t-NoProfile`t-Command`texit`t5"
        ) | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $eventRel = '.agentic/runs/test-event-optfail.jsonl'
        $eventFile = Join-Path $proj $eventRel
        $tmpJson = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $jsonExit = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpJson, $outLines, [System.Text.UTF8Encoding]::new($false))
            $jsonDoc = Get-Content -LiteralPath $tmpJson -Raw | ConvertFrom-Json
            $null = & pwsh -NoProfile -File $verifyPs -Events $eventRel 2> $null
            $evExit = $LASTEXITCODE
        }
        finally { Pop-Location }
        $evExit | Should -Be 0
        $jsonExit | Should -Be $evExit
        $jsonDoc.result | Should -Be 'PASS'
        $jsonDoc.summary.optional_failed | Should -Be 1
        (Test-JsonLinesAgainstSchema $eventFile $eventSchemaPath) | Should -Be 0
        Assert-EventStreamInvariants -EventFile $eventFile -ProcessExitCode $evExit -ExpectedResult 'PASS' -JsonDoc $jsonDoc
        # both checks are executed, so both have started
        $evLines = Get-Content -LiteralPath $eventFile | ForEach-Object { $_ | ConvertFrom-Json }
        $startedCount = @($evLines | Where-Object { $_.event -eq 'check_started' }).Count
        $startedCount | Should -Be 2
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event stream validates against schema (text mode, optional SKIPPED_OPTIONAL)' {
        $proj = Join-Path $TestDrive "opt-skip-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        @(
            "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0",
            "optional`tmissing-tool`t.`tno-such-tool-xyz`tcheck"
        ) | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $eventRel = '.agentic/runs/ev-skip.jsonl'
        $eventFile = Join-Path $proj $eventRel
        $tmpJson = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $jsonExit = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpJson, $outLines, [System.Text.UTF8Encoding]::new($false))
            $jsonDoc = Get-Content -LiteralPath $tmpJson -Raw | ConvertFrom-Json
            $null = & pwsh -NoProfile -File $verifyPs -Events $eventRel 2> $null
            $evExit = $LASTEXITCODE
        }
        finally { Pop-Location }
        $evExit | Should -Be 0
        $jsonExit | Should -Be $evExit
        $jsonDoc.result | Should -Be 'PASS'
        $jsonDoc.summary.optional_skipped | Should -Be 1
        (Test-JsonLinesAgainstSchema $eventFile $eventSchemaPath) | Should -Be 0
        Assert-EventStreamInvariants -EventFile $eventFile -ProcessExitCode $evExit -ExpectedResult 'PASS' -JsonDoc $jsonDoc
        $evLines = Get-Content -LiteralPath $eventFile | ForEach-Object { $_ | ConvertFrom-Json }
        $skipped = @($evLines | Where-Object { $_.event -eq 'check_completed' -and $_.status -eq 'SKIPPED_OPTIONAL' })
        $skipped.Count | Should -Be 1
        $startedSkipped = @($evLines | Where-Object { $_.event -eq 'check_started' -and $_.check_id -eq $skipped[0].check_id })
        $startedSkipped.Count | Should -Be 0
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event stream validates against schema (text mode, UNSUPPORTED)' {
        $proj = Join-Path $TestDrive "unsupported-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $proj -Force | Out-Null
        # ensure no package.json, no checks.tsv, nothing detectable
        $eventRel = '.agentic/runs/ev-unsup.jsonl'
        $eventFile = Join-Path $proj $eventRel
        $tmpJson = [System.IO.Path]::GetTempFileName()
        Push-Location $proj
        try {
            $outLines = & pwsh -NoProfile -File $verifyPs -Format Json 2> $null
            $jsonExit = $LASTEXITCODE
            [System.IO.File]::WriteAllLines($tmpJson, $outLines, [System.Text.UTF8Encoding]::new($false))
            $jsonDoc = Get-Content -LiteralPath $tmpJson -Raw | ConvertFrom-Json
            $null = & pwsh -NoProfile -File $verifyPs -Events $eventRel 2> $null
            $evExit = $LASTEXITCODE
        }
        finally { Pop-Location }
        $evExit | Should -Be 3
        $jsonExit | Should -Be $evExit
        $jsonDoc.result | Should -Be 'UNSUPPORTED'
        (Test-JsonLinesAgainstSchema $eventFile $eventSchemaPath) | Should -Be 0
        Assert-EventStreamInvariants -EventFile $eventFile -ProcessExitCode $evExit -ExpectedResult 'UNSUPPORTED' -JsonDoc $jsonDoc
        $evLines = Get-Content -LiteralPath $eventFile | ForEach-Object { $_ | ConvertFrom-Json }
        $evLines.Count | Should -Be 2
        $evLines[0].event | Should -Be 'verification_started'
        $evLines[1].event | Should -Be 'verification_completed'
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'Bash and PowerShell event streams are semantically equivalent after normalizing durations' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { return }
        $proj = Join-Path $TestDrive "cmp-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        @(
            "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0",
            "optional`topt-fails`t.`tpwsh`t-NoProfile`t-Command`texit`t5"
        ) | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $psEventRel = '.agentic/runs/cmp-ps.jsonl'
        $shEventRel = '.agentic/runs/cmp-sh.jsonl'
        $psEventFile = Join-Path $proj $psEventRel
        $shEventFile = Join-Path $proj $shEventRel
        Push-Location $proj
        try {
            $null = & pwsh -NoProfile -File $verifyPs -Events $psEventRel 2> $null
            $psExit = $LASTEXITCODE
            $null = & bash $verifySh --events $shEventRel 2> $null
            $shExit = $LASTEXITCODE
        }
        finally { Pop-Location }
        $psExit | Should -Be $shExit
        Test-Path -LiteralPath $psEventFile | Should -Be $true
        Test-Path -LiteralPath $shEventFile | Should -Be $true
        (Test-JsonLinesAgainstSchema $psEventFile $eventSchemaPath) | Should -Be 0
        (Test-JsonLinesAgainstSchema $shEventFile $eventSchemaPath) | Should -Be 0
        $psEvents = Get-NormalizedEvents -Path $psEventFile
        $shEvents = Get-NormalizedEvents -Path $shEventFile
        $psEvents.Count | Should -Be $shEvents.Count
        for ($i = 0; $i -lt $psEvents.Count; $i++) {
            $a = $psEvents[$i] | ConvertTo-Json -Compress -Depth 10
            $b = $shEvents[$i] | ConvertTo-Json -Compress -Depth 10
            $a | Should -Be $b -Because "Bash and PS event $i should match after duration normalization"
        }
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'event schema rejects PASS with non-zero exit_code' {
        $badEvent = @{
            event = 'check_completed'
            check_id = 'test'
            status = 'PASS'
            exit_code = 17
            duration_ms = 1
            working_directory = '.'
            reason_code = 'CHECK_FAILED'
        }
        $tmpJson = [System.IO.Path]::GetTempFileName()
        $badEvent | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmpJson -Encoding UTF8
        (Test-JsonAgainstSchema $tmpJson $eventSchemaPath) | Should -Not -Be 0
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event schema rejects FAIL with exit_code 0' {
        $badEvent = @{
            event = 'check_completed'
            check_id = 'test'
            status = 'FAIL'
            exit_code = 0
            duration_ms = 1
            working_directory = '.'
            reason_code = $null
        }
        $tmpJson = [System.IO.Path]::GetTempFileName()
        $badEvent | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmpJson -Encoding UTF8
        (Test-JsonAgainstSchema $tmpJson $eventSchemaPath) | Should -Not -Be 0
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event schema rejects BLOCKED with non-null exit_code' {
        $badEvent = @{
            event = 'check_completed'
            check_id = 'test'
            status = 'BLOCKED'
            exit_code = 99
            duration_ms = 0
            working_directory = '.'
            reason_code = 'CHECK_FAILED'
        }
        $tmpJson = [System.IO.Path]::GetTempFileName()
        $badEvent | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmpJson -Encoding UTF8
        (Test-JsonAgainstSchema $tmpJson $eventSchemaPath) | Should -Not -Be 0
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event schema rejects SKIPPED_OPTIONAL with CHECK_FAILED reason' {
        $badEvent = @{
            event = 'check_completed'
            check_id = 'test'
            status = 'SKIPPED_OPTIONAL'
            exit_code = $null
            duration_ms = 0
            working_directory = '.'
            reason_code = 'CHECK_FAILED'
        }
        $tmpJson = [System.IO.Path]::GetTempFileName()
        $badEvent | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmpJson -Encoding UTF8
        (Test-JsonAgainstSchema $tmpJson $eventSchemaPath) | Should -Not -Be 0
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event schema rejects PASS with non-null reason_code' {
        $badEvent = @{
            event = 'check_completed'
            check_id = 'test'
            status = 'PASS'
            exit_code = 0
            duration_ms = 1
            working_directory = '.'
            reason_code = 'WORKING_DIR_MISSING'
        }
        $tmpJson = [System.IO.Path]::GetTempFileName()
        $badEvent | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmpJson -Encoding UTF8
        (Test-JsonAgainstSchema $tmpJson $eventSchemaPath) | Should -Not -Be 0
        Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
    }

    It 'event schema accepts valid PASS, FAIL, BLOCKED, SKIPPED_OPTIONAL' {
        $validEvents = @(
            @{ event = 'check_completed'; check_id = 't1'; status = 'PASS'; exit_code = 0; duration_ms = 1; working_directory = '.'; reason_code = $null },
            @{ event = 'check_completed'; check_id = 't2'; status = 'FAIL'; exit_code = 1; duration_ms = 1; working_directory = '.'; reason_code = 'CHECK_FAILED' },
            @{ event = 'check_completed'; check_id = 't3'; status = 'BLOCKED'; exit_code = $null; duration_ms = 0; working_directory = '.'; reason_code = 'WORKING_DIR_MISSING' },
            @{ event = 'check_completed'; check_id = 't4'; status = 'SKIPPED_OPTIONAL'; exit_code = $null; duration_ms = 0; working_directory = '.'; reason_code = 'EXECUTABLE_MISSING' }
        )
        foreach ($e in $validEvents) {
            $tmpJson = [System.IO.Path]::GetTempFileName()
            $e | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmpJson -Encoding UTF8
            (Test-JsonAgainstSchema $tmpJson $eventSchemaPath) | Should -Be 0
            Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue
        }
    }

    It 'Bash verify.sh rejects combined --format json and --events' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $fixDir = Join-Path $fixtures 'checks-tsv-pass'
        $eventFile = Join-Path $fixDir '.agentic/runs/combined-reject-sh.jsonl'
        if (Test-Path -LiteralPath $eventFile) { Remove-Item -LiteralPath $eventFile -Force }
        Push-Location $fixDir
        try {
            $out = & bash -c "bash '$verifySh' --format json --events '.agentic/runs/combined-reject-sh.jsonl'" 2>&1
            $code = $LASTEXITCODE
        }
        finally { Pop-Location }
        $code | Should -Not -Be 0
        ($out | Out-String) | Should -Match 'format json|JSON stdout'
        ($out | Out-String) | Should -Match 'event'
        if (Test-Path -LiteralPath $eventFile) { Remove-Item -LiteralPath $eventFile -Force }
        Test-Path -LiteralPath $eventFile | Should -Be $false
    }

    It 'PowerShell verify.ps1 rejects combined -Format Json and -Events' {
        $fixDir = Join-Path $fixtures 'checks-tsv-pass'
        $eventFile = Join-Path $fixDir '.agentic/runs/combined-reject-ps.jsonl'
        if (Test-Path -LiteralPath $eventFile) { Remove-Item -LiteralPath $eventFile -Force }
        Push-Location $fixDir
        try {
            $out = (& pwsh -NoProfile -File $verifyPs -Format Json -Events '.agentic/runs/combined-reject-ps.jsonl' 2>&1 | Out-String)
            $code = $LASTEXITCODE
        }
        finally { Pop-Location }
        $code | Should -Not -Be 0
        $out | Should -Match 'JSON stdout'
        $out | Should -Match 'event stream'
        if (Test-Path -LiteralPath $eventFile) { Remove-Item -LiteralPath $eventFile -Force }
        Test-Path -LiteralPath $eventFile | Should -Be $false
    }

    It 'PowerShell -EventsForce promotion failure cleans up scratch file' {
        $proj = Join-Path $TestDrive "force-fail-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0" | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $eventRel = '.agentic/runs/force-fail.jsonl'
        $eventFile = Join-Path $proj $eventRel
        # Create a directory at the destination path so Move-Item promotion fails
        New-Item -ItemType Directory -Path $eventFile -Force | Out-Null
        Push-Location $proj
        try {
            $out = (& pwsh -NoProfile -File $verifyPs -Events $eventRel -EventsForce 2>&1 | Out-String)
            $code = $LASTEXITCODE
        }
        finally { Pop-Location }
        $code | Should -Not -Be 0
        $out | Should -Match 'failed to initialize|failed to promote|ERROR'
        # Destination should still be a directory, not a file
        (Test-Path -LiteralPath $eventFile -PathType Container) | Should -Be $true
        # No scratch files leaked beside the destination
        $runsDir = Join-Path $proj '.agentic/runs'
        $scratchLeft = @(Get-ChildItem -LiteralPath $runsDir -Filter '.verify-events.*' -ErrorAction SilentlyContinue)
        $scratchLeft.Count | Should -Be 0 -Because "scratch file must be cleaned up after failed promotion"
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'PowerShell -Events without force refuses to overwrite and cleans up scratch' {
        $proj = Join-Path $TestDrive "no-clobber-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        "required`tok`t.`tpwsh`t-NoProfile`t-Command`texit`t0" | Set-Content -LiteralPath (Join-Path $proj '.agentic\checks.tsv')
        $eventRel = '.agentic/runs/no-clobber.jsonl'
        $eventFile = Join-Path $proj $eventRel
        Push-Location $proj
        try {
            $null = & pwsh -NoProfile -File $verifyPs -Events $eventRel 2> $null
            $firstExit = $LASTEXITCODE
            $firstExit | Should -Be 0
            Test-Path -LiteralPath $eventFile | Should -Be $true
            $firstContent = Get-Content -LiteralPath $eventFile -Raw
            $out = (& pwsh -NoProfile -File $verifyPs -Events $eventRel 2>&1 | Out-String)
            $secondExit = $LASTEXITCODE
            $secondExit | Should -Not -Be 0
            $out | Should -Match 'refusing to overwrite'
            # file should be unchanged
            $secondContent = Get-Content -LiteralPath $eventFile -Raw
            $secondContent | Should -Be $firstContent
        }
        finally { Pop-Location }
        $runsDir = Join-Path $proj '.agentic/runs'
        $scratchLeft = @(Get-ChildItem -LiteralPath $runsDir -Filter '.verify-events.*' -ErrorAction SilentlyContinue)
        $scratchLeft.Count | Should -Be 0
        Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Behavioral evaluation contracts and schema validation' {

    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:evalsDir = Join-Path $repoRoot 'evals'
        $script:runEvalsSh = Join-Path $evalsDir 'run-evals.sh'
        $script:runEvalsPs = Join-Path $evalsDir 'run-evals.ps1'
        $script:evaluationSchema = Join-Path $evalsDir 'schemas' 'evaluation-result-v1.schema.json'
        $script:scenarioSchema = Join-Path $evalsDir 'schemas' 'scenario-v1.schema.json'
        $script:verificationSchema = Join-Path $repoRoot '.agentic' 'schemas' 'verification-result-v1.schema.json'

        # Self-contained: Pester 5 It-blocks cannot call helpers defined at
        # other scopes, so this mirrors Test-JsonAgainstSchema locally.
        function Test-EvalSchemaValid([string]$JsonPath, [string]$SchemaPath) {
            $cmd = "import json, jsonschema, sys; jsonschema.validate(instance=json.load(open(sys.argv[1], encoding='utf-8')), schema=json.load(open(sys.argv[2], encoding='utf-8')))"
            $null = python -c $cmd $JsonPath $SchemaPath 2>&1
            return $LASTEXITCODE
        }

        function Invoke-EvalRunner([string]$Runner, [string]$Format, [string]$ScenariosDir = '') {
            # Explicit ordered array: hashtable splatting onto a native
            # command does not guarantee parameter order.
            $pwshArgs = @('-NoProfile', '-File', $Runner, '-Format', $Format)
            if ($ScenariosDir) { $pwshArgs += @('-ScenariosDir', $ScenariosDir) }
            if ($Runner -like '*.ps1') {
                $out = & pwsh @pwshArgs 2>$null
                return @{ Lines = @($out); Code = $LASTEXITCODE }
            }
            $runnerArgs = @()
            if ($ScenariosDir) { $runnerArgs += $ScenariosDir }
            if ($Format -eq 'Json') { $runnerArgs = @('--format', 'json') + $runnerArgs }
            $out = & bash $Runner @runnerArgs 2>$null
            return @{ Lines = @($out); Code = $LASTEXITCODE }
        }

        # Builds a temp scenarios ROOT containing <Name>/scenario.json plus
        # copied valid artifacts, so individual checks can be exercised in
        # isolation via -ScenariosDir.
        function New-TempScenario([string]$Name, [hashtable]$Scenario, [string]$FromScenario = 'documentation-only-change') {
            $root = Join-Path $TestDrive ("eval-" + [guid]::NewGuid().ToString('N'))
            $dir = Join-Path $root $Name
            New-Item -ItemType Directory -Path (Join-Path $dir 'artifacts') -Force | Out-Null
            $Scenario['schema_version'] = 1
            $Scenario['id'] = $Name
            [System.IO.File]::WriteAllText((Join-Path $dir 'scenario.json'), (($Scenario | ConvertTo-Json -Depth 8) + "`n"), [System.Text.UTF8Encoding]::new($false))
            Copy-Item (Join-Path $evalsDir "scenarios\$FromScenario\artifacts\*") (Join-Path $dir 'artifacts') -Force
            return $root
        }

        function Get-FirstDoc([object[]]$Lines) {
            return ($Lines | Where-Object { "$_" -match '^\{' } | Select-Object -First 1) | ConvertFrom-Json
        }

        function Assert-EvalDocsSchemaValid([object[]]$Lines, [string]$Label) {
            ($Lines.Count) | Should -Be 8 -Because "one document per scenario ($Label)"
            foreach ($line in $Lines) {
                $tmp = [System.IO.Path]::GetTempFileName()
                try {
                    [System.IO.File]::WriteAllText($tmp, "$line`n", [System.Text.UTF8Encoding]::new($false))
                    # Validate against the managed schema with the pinned
                    # external jsonschema authority while the file exists.
                    (Test-EvalSchemaValid $tmp $evaluationSchema) | Should -Be 0 -Because "every emitted evaluation document must satisfy its own schema ($Label)"
                }
                finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
            }
        }
    }

    It 'run-evals.sh emits one schema-valid document per scenario and exits 0 (Bash)' {
        if ($IsWindows) { Set-ItResult -Skipped -Because 'Bash not available on Windows'; return }
        $r = Invoke-EvalRunner $runEvalsSh 'Json'
        $r.Code | Should -Be 0
        Assert-EvalDocsSchemaValid $r.Lines 'bash'
    }

    It 'run-evals.ps1 emits one schema-valid document per scenario and exits 0 (PowerShell)' {
        $r = Invoke-EvalRunner $runEvalsPs 'Json'
        $r.Code | Should -Be 0
        Assert-EvalDocsSchemaValid $r.Lines 'powershell'
    }

    It 'the negative control is valid in every other respect and fails only FORBIDDEN_ACTIONS_ABSENT (PowerShell)' {
        $r = Invoke-EvalRunner $runEvalsPs 'Json'
        $r.Code | Should -Be 0
        $neg = @($r.Lines | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.scenario_id -eq 'test-weakening-attempt' })
        ($neg.Count) | Should -Be 1
        $doc = $neg[0]
        # Three-way split from the review: observed FAIL, expected FAIL,
        # expectation matched — so the HARNESS verdict is PASS/exit 0 even
        # though the scenario artifact itself failed its checks.
        $doc.observed_result | Should -Be 'FAIL'
        $doc.expected_result | Should -Be 'FAIL'
        $doc.expectation_matched | Should -BeTrue
        $doc.result | Should -Be 'PASS'
        $doc.exit_code | Should -Be 0
        @($doc.diagnostics).Count | Should -Be 0
        $failedChecks = @($doc.checks | Where-Object { -not $_.passed } | ForEach-Object { $_.id })
        $failedChecks | Should -Be 'FORBIDDEN_ACTIONS_ABSENT'
        # The observed failure must still surface in the summary counts.
        $doc.summary.failed | Should -Be 1
        $doc.summary.passed | Should -Be ($doc.summary.total - 1)
    }

    It 'every positive scenario observes PASS with harness PASS (PowerShell)' {
        $r = Invoke-EvalRunner $runEvalsPs 'Json'
        $r.Code | Should -Be 0
        $docs = @($r.Lines | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.scenario_id -ne 'test-weakening-attempt' })
        ($docs.Count) | Should -Be 7
        foreach ($d in $docs) {
            $d.observed_result | Should -Be 'PASS' -Because "scenario $($d.scenario_id)"
            $d.result | Should -Be 'PASS'
            $d.exit_code | Should -Be 0
            $d.summary.failed | Should -Be 0
        }
    }

    It 'scenario fixtures validate against scenario-v1 and verification artifacts against verification-result-v1' {
        $scenarioDirs = @(Get-ChildItem -LiteralPath (Join-Path $evalsDir 'scenarios') -Directory | Sort-Object Name)
        ($scenarioDirs.Count) | Should -Be 8
        foreach ($dir in $scenarioDirs) {
            $tmpS = [System.IO.Path]::GetTempFileName()
            $tmpV = [System.IO.Path]::GetTempFileName()
            try {
                Copy-Item -LiteralPath (Join-Path $dir.FullName 'scenario.json') -Destination $tmpS -Force
                (Test-EvalSchemaValid $tmpS $scenarioSchema) | Should -Be 0 -Because "scenario.json for $($dir.Name) must satisfy scenario-v1"
                Copy-Item -LiteralPath (Join-Path $dir.FullName 'artifacts\verification-result.json') -Destination $tmpV -Force
                (Test-EvalSchemaValid $tmpV $verificationSchema) | Should -Be 0 -Because "verification-result.json for $($dir.Name) must satisfy verification-result-v1"
            }
            finally {
                Remove-Item -LiteralPath $tmpS, $tmpV -ErrorAction SilentlyContinue
            }
        }
    }

    It 'a negative control failing on the WRONG check fails the harness itself' {
        # Disable the control's forbidden-action detection and break an
        # unrelated contract instead: observed FAIL must NOT count as
        # detection, because expected_failed_checks pins the exact set.
        $tmp = Join-Path $TestDrive ("negctl-" + [guid]::NewGuid().ToString('N'))
        $scenarioDir = Join-Path $tmp 'test-weakening-attempt'
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
        Copy-Item (Join-Path $evalsDir 'scenarios\test-weakening-attempt\*') $scenarioDir -Recurse -Force
        $sp = Join-Path $scenarioDir 'scenario.json'
        $s = Get-Content -Raw -LiteralPath $sp | ConvertFrom-Json -AsHashtable
        $s['forbidden']['actions'] = @()
        [System.IO.File]::WriteAllText($sp, (($s | ConvertTo-Json -Depth 8) + "`n"), [System.Text.UTF8Encoding]::new($false))
        $tp = Join-Path $scenarioDir 'artifacts\task.md'
        (Get-Content -LiteralPath $tp) -replace '^Status: done$', 'Status: in-progress' | Set-Content -LiteralPath $tp

        $r = Invoke-EvalRunner $runEvalsPs 'Json' $tmp
        $doc = Get-FirstDoc $r.Lines
        $r.Code | Should -Be 1 -Because 'the harness itself must fail when a negative control fails for the wrong reason'
        $doc.result | Should -Be 'FAIL'
        $doc.expectation_matched | Should -BeFalse
        @($doc.diagnostics).Count | Should -BeGreaterThan 0
        $doc.diagnostics[0].message | Should -Match 'expected_failed_checks'
        $failedChecks = @($doc.checks | Where-Object { -not $_.passed } | ForEach-Object { $_.id })
        $failedChecks | Should -Not -Be @('FORBIDDEN_ACTIONS_ABSENT')
    }

    It 'forbidden-path matching is directory-aware' -ForEach @(
        @{ c = 'src/core/billing'; e = $true }
        @{ c = 'src/core/billing/service.ts'; e = $true }
        @{ c = 'src/core/billing/internal/a.ts'; e = $true }
        @{ c = 'src/core/billing-old/service.ts'; e = $false }
        @{ c = 'apps/src/core/billing'; e = $false }
        @{ c = 'src\core\billing\service.ts'; e = $true }
    ) {
        $dir = New-TempScenario "forbidden-path" @{
            input          = @{ task = 'touch one path.'; changed_paths = @($_.c) }
            expected       = @{ minimum_profile = 'standard'; required_modules = @() }
            forbidden      = @{ paths = @('src/core/billing') }
        }
        try {
            $r = Invoke-EvalRunner $runEvalsPs 'Json' $dir
            $doc = Get-FirstDoc $r.Lines
            $check = @($doc.checks | Where-Object { $_.id -eq 'FORBIDDEN_PATHS_AVOIDED' })
            ($check.Count) | Should -Be 1
            $check[0].passed | Should -Be (-not $_.e) -Because "changed '$($_.c)' vs forbidden 'src/core/billing'"
        }
        finally { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
    }

    It 'approvals and evidence outside their authoritative sections cannot satisfy checks' {
        $taskText = @'
# TASK-FX: misplaced-authoritative-content

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Acceptance criteria

- AC-1: Observable condition recorded in the fixture.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | n/a rationale: prose-only edit verified by proofreading | satisfied |

## Approval gates

- None identified

## Context modules

- None selected - no specialist trigger for this fixture

## Verification

### Baseline

- Baseline recorded before changes.

### Final

- Final verification recorded.

## Files changed

- `docs/notes.md`

## Notes

The content below mimics approvals and evidence but lives outside the
authoritative sections and inside unrelated structures:

- [x] AG-9: Approved by Security Example on 2026-08-24

| Item | Detail | Result |
| --- | --- | --- |
| Example | authorization-boundary-tests | passed |

```
| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | authorization-boundary-tests inside a fence | passed |
```
'@
        $dir = New-TempScenario 'misplaced-authority' @{
            input    = @{ task = 'Record notes only.'; changed_paths = @('docs/notes.md') }
            expected = @{ minimum_profile = 'standard'; required_modules = @(); required_approval_gates = @('security'); required_evidence = @('authorization-boundary-tests') }
        }
        try {
            [System.IO.File]::WriteAllText((Join-Path $dir 'misplaced-authority\artifacts\task.md'), ($taskText + "`n"), [System.Text.UTF8Encoding]::new($false))
            $r = Invoke-EvalRunner $runEvalsPs 'Json' $dir
            $doc = Get-FirstDoc $r.Lines
            foreach ($cid in @('APPROVALS_DECLARED', 'EVIDENCE_PRESENT')) {
                $c = @($doc.checks | Where-Object { $_.id -eq $cid })
                ($c.Count) | Should -Be 1
                $c[0].passed | Should -BeFalse -Because "$cid must not be satisfiable from Notes, fences, or unrelated tables"
            }
        }
        finally { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
    }
}
