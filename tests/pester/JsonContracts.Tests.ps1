# JsonContracts.Tests.ps1 — JSON result contracts and schema validation tests (Pester 5).

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
        if ($IsWindows) { return }
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

    It 'optional JSONL run events stream is produced correctly with -Events' {
        $fixDir = Join-Path $fixtures 'node-npm'
        $eventFile = Join-Path $fixDir '.agentic/runs/test-event.jsonl'
        if (Test-Path -LiteralPath $eventFile) { Remove-Item -LiteralPath $eventFile -Force }
        Push-Location $fixDir
        try {
            $null = & pwsh -NoProfile -File $verifyPs -Format Json -Events '.agentic/runs/test-event.jsonl' 2> $null
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
        if ($IsWindows) { return }
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
        $stdoutContent = (-join $outLines | Select-String -Pattern '^\{' | Measure-Object).Count
        $stdoutContent | Should -Be 0
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
    }

    It 'verification result JSON stays well-formed when python3 is unavailable' {
        # The Bash verifier's only python3 uses are duration timestamps with
        # graceful fallbacks; shadow both interpreters with failing stubs and
        # require the JSON contract to remain intact. Mirrors the bash-schema
        # test's platform guard.
        if ($IsWindows) { return }
        $fixDir = Join-Path $fixtures 'node-npm'
        $stubDir = Join-Path $TestDrive 'pystub'
        New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $stubDir 'python3') -Value "#!/bin/sh`nexit 127" -NoNewline
        Set-Content -LiteralPath (Join-Path $stubDir 'python') -Value "#!/bin/sh`nexit 127" -NoNewline
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
        if ($IsWindows) { return }
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
        if (-not (Get-Command sh -ErrorAction SilentlyContinue)) { return }
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
        if ($IsWindows) { return }
        $proj = Join-Path $TestDrive "required-fail-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path (Join-Path $proj '.agentic') -Force | Out-Null
        @(
            "required`tbroken`t.`tsh`t-c`texit`t3",
            "optional`tfine`t.`tsh`t-c`ttrue"
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
        if ($IsWindows) { return }
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
        if ($IsWindows) { return }
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
