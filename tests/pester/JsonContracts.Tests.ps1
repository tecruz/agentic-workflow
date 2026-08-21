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
}
