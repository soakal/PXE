#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Starter suite — the loop expands this per milestone. Host-mutating cmdlets are
# ALWAYS mocked; asserting call counts is mandatory where behavior matters.

BeforeAll {
    $script:SetupPath  = Join-Path $PSScriptRoot '..\src\setup.ps1'
    $script:ConfigPath = Join-Path $PSScriptRoot '..\src\config.psd1'
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
