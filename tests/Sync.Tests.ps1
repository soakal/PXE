#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# M3 gate: sync-images.ps1 — robocopy gate logic and exit-code mapping.
# Host-mutating cmdlets and robocopy are ALWAYS mocked; call counts asserted.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:SyncPath   = Join-Path $PSScriptRoot '..\src\sync-images.ps1'
    $script:ConfigPath = Join-Path $PSScriptRoot '..\src\config.psd1'
}

Describe 'Sync-Images' {
    BeforeAll {
        # Dot-source loads functions; Main guard prevents execution.
        . $script:SyncPath
        Mock Write-Host        {}
        Mock Add-Content       {}
        Mock Test-IsElevated   { $true }
        # Default: robocopy succeeds (exit code 0 = no files copied/changed, still success).
        Mock Invoke-Robocopy { return 0 }
    }

    It 'calls Invoke-Robocopy once per Include folder when -Force is set' {
        Sync-Images -Force
        # Config.Sync.Include = @('Images', 'Platform Packs') — 2 folders.
        Should -Invoke Invoke-Robocopy -Exactly 2 -Scope It
    }

    It 'does not call Invoke-Robocopy when gate is not passed (-WhatIf)' {
        Sync-Images -WhatIf
        Should -Invoke Invoke-Robocopy -Exactly 0 -Scope It
    }

    It 'logs a WARN when gate is not passed (-WhatIf)' {
        Sync-Images -WhatIf
        Should -Invoke Write-Host -Times 1 -Scope It -ParameterFilter { $ForegroundColor -eq 'Yellow' }
    }

    It 'returns cancelled when gate is not passed (-WhatIf)' {
        $result = Sync-Images -WhatIf
        $result | Should -Be 'cancelled'
    }

    It 'returns ok when all robocopy calls exit with code <= 7' {
        Mock Invoke-Robocopy { return 7 }
        $result = Sync-Images -Force
        $result | Should -Be 'ok'
    }

    It 'returns failed when robocopy exits with code >= 8' {
        Mock Invoke-Robocopy { return 8 }
        $result = Sync-Images -Force
        $result | Should -Be 'failed'
    }

    It 'logs an ERROR for each folder when robocopy exits >= 8' {
        Mock Invoke-Robocopy { return 8 }
        Sync-Images -Force
        # Both folders fail → 2 ERROR-level Write-Host calls (ForegroundColor Red).
        Should -Invoke Write-Host -Times 2 -Scope It -ParameterFilter { $ForegroundColor -eq 'Red' }
    }

    It 'logs a SUCCESS for each folder when robocopy exits <= 7' {
        Mock Invoke-Robocopy { return 0 }
        Sync-Images -Force
        Should -Invoke Write-Host -Times 2 -Scope It -ParameterFilter { $ForegroundColor -eq 'Green' }
    }
}

Describe 'Scaffold contract — sync-images' {
    It 'sync-images.ps1 parses without syntax errors' {
        $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:SyncPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'sync-images.ps1 declares SupportsShouldProcess' {
        (Get-Content $script:SyncPath -Raw) | Should -Match 'SupportsShouldProcess'
    }

    It 'sync-images.ps1 contains no hardcoded IP addresses' {
        (Get-Content $script:SyncPath -Raw) | Should -Not -Match '\b\d{1,3}(\.\d{1,3}){3}\b'
    }
}
