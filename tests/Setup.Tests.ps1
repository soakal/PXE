#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Starter suite — the loop expands this per milestone. Host-mutating cmdlets are
# ALWAYS mocked; asserting call counts is mandatory where behavior matters.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:SetupPath  = Join-Path $PSScriptRoot '..\src\setup.ps1'
    $script:ConfigPath = Join-Path $PSScriptRoot '..\src\config.psd1'
}

Describe 'Test-Prerequisites' {
    BeforeAll {
        # Dot-source loads functions without triggering Main (guarded by InvocationName check).
        . $script:SetupPath
        # Silence console + log writes throughout the entire Describe.
        Mock Write-Host  {}
        Mock Add-Content {}
    }

    BeforeEach {
        # Default: everything passes.
        Mock Test-IsElevated { $true }
        Mock Get-CimInstance { [PSCustomObject]@{ BuildNumber = '26100' } }
        Mock Test-Path       { $true }
    }

    It 'does not throw when all conditions are met' {
        { Test-Prerequisites } | Should -Not -Throw
    }

    It 'calls Get-CimInstance exactly once per run' {
        Test-Prerequisites
        Should -Invoke Get-CimInstance -Exactly 1 -Scope It
    }

    It 'calls Test-Path at least twice (drive + zip) per run' {
        Test-Prerequisites
        Should -Invoke Test-Path -Times 2 -Scope It
    }

    It 'throws a NOT_ELEVATED error when the process is not elevated' {
        Mock Test-IsElevated { $false }
        { Test-Prerequisites } | Should -Throw '*PREREQ:NOT_ELEVATED*'
    }

    It 'calls Test-IsElevated exactly once per run' {
        Test-Prerequisites
        Should -Invoke Test-IsElevated -Exactly 1 -Scope It
    }

    It 'throws a BAD_INPUT error when OS build is below 17763' {
        Mock Get-CimInstance { [PSCustomObject]@{ BuildNumber = '10240' } }
        { Test-Prerequisites } | Should -Throw '*PREREQ:BAD_INPUT*'
    }

    It 'throws a MISSING_DEP error when the data volume is absent' {
        # Drive-root calls match '^[A-Za-z]:$'; all other Test-Path calls fall through to
        # the parameterless fallback (which returns $true — zip present, no extra noise).
        Mock Test-Path { $false } -ParameterFilter { $Path -match '^[A-Za-z]:$' }
        { Test-Prerequisites } | Should -Throw '*PREREQ:MISSING_DEP*'
    }

    It 'does not throw when iVentoy zip is missing' {
        # Drive exists; zip does not.
        Mock Test-Path { $true }  -ParameterFilter { $Path -match '^[A-Za-z]:$' }
        Mock Test-Path { $false } -ParameterFilter { $Path -notmatch '^[A-Za-z]:$' }
        { Test-Prerequisites } | Should -Not -Throw
    }

    It 'logs a WARN (yellow) when iVentoy zip is missing' {
        Mock Test-Path { $true }  -ParameterFilter { $Path -match '^[A-Za-z]:$' }
        Mock Test-Path { $false } -ParameterFilter { $Path -notmatch '^[A-Za-z]:$' }
        Test-Prerequisites
        # Write-Log calls Write-Host with -ForegroundColor Yellow for WARN level.
        Should -Invoke Write-Host -Times 1 -Scope It -ParameterFilter { $ForegroundColor -eq 'Yellow' }
    }
}

Describe 'Scaffold contract' {
    It 'setup.ps1 parses without errors' {
        $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($SetupPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
    It 'setup.ps1 declares SupportsShouldProcess' {
        (Get-Content $SetupPath -Raw) | Should -Match 'SupportsShouldProcess'
    }
    It 'config.psd1 imports and has required blocks' {
        $cfg = Import-PowerShellDataFile -Path $ConfigPath
        $cfg.IVentoy.Version   | Should -Be '1.0.37'
        $cfg.Share.Path        | Should -Be 'D:\SDShare'
        $cfg.IVentoy.DhcpMode  | Should -BeIn @('ExternalNet', 'DHCPServer')
    }
    It 'no hardcoded IP addresses in scripts outside config.psd1' {
        Get-ChildItem (Join-Path $PSScriptRoot '..\src') -Filter *.ps1 | ForEach-Object {
            (Get-Content $_.FullName -Raw) | Should -Not -Match '\b\d{1,3}(\.\d{1,3}){3}\b'
        }
    }
}
