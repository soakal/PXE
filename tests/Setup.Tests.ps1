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

Describe 'Install-ServiceAccount' {
    BeforeAll {
        . $script:SetupPath
        Mock Write-Host   {}
        Mock Add-Content  {}
        Mock New-LocalUser {}
    }

    BeforeEach {
        Mock Get-LocalUser {}
    }

    It 'calls New-LocalUser exactly once when account does not exist' {
        Install-ServiceAccount
        Should -Invoke New-LocalUser -Exactly 1 -Scope It
    }

    It 'calls Get-LocalUser exactly once per run' {
        Install-ServiceAccount
        Should -Invoke Get-LocalUser -Exactly 1 -Scope It
    }

    It 'does not call New-LocalUser when account already exists (idempotency)' {
        Mock Get-LocalUser { [PSCustomObject]@{ Name = $script:Config.Share.ServiceAccount } }
        Install-ServiceAccount
        Install-ServiceAccount
        Should -Invoke New-LocalUser -Exactly 0 -Scope It
    }
}

Describe 'Install-ImageShare' {
    BeforeAll {
        . $script:SetupPath
        Mock Write-Host   {}
        Mock Add-Content  {}
        Mock New-Item     {}
        Mock New-SmbShare {}
        Mock Get-Acl      {
            $ds = [PSCustomObject]@{ Access = @() }
            $ds | Add-Member -MemberType ScriptMethod -Name 'AddAccessRule' -Value { param($r) }
            $ds
        }
        Mock Set-Acl      {}
    }

    BeforeEach {
        Mock Test-Path    { $false }
        Mock Get-SmbShare {}
    }

    It 'creates base dir, all subdirs, the share, and applies ACL when nothing exists' {
        Install-ImageShare
        # 1 base dir + 3 subdirs (Images, Platform Packs, Answer Files)
        Should -Invoke New-Item     -Exactly 4 -Scope It
        Should -Invoke New-SmbShare -Exactly 1 -Scope It
        Should -Invoke Set-Acl      -Exactly 1 -Scope It
    }

    It 'skips New-Item, New-SmbShare, and Set-Acl when everything already configured (idempotency)' {
        Mock Test-Path    { $true }
        Mock Get-SmbShare { [PSCustomObject]@{ Name = $script:Config.Share.Name } }
        Mock Get-Acl      {
            $account = $script:Config.Share.ServiceAccount
            $ds = [PSCustomObject]@{
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $account }
                        FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
                        AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    }
                )
            }
            $ds | Add-Member -MemberType ScriptMethod -Name 'AddAccessRule' -Value { param($r) }
            $ds
        }
        Install-ImageShare
        Install-ImageShare
        Should -Invoke New-Item     -Exactly 0 -Scope It
        Should -Invoke New-SmbShare -Exactly 0 -Scope It
        Should -Invoke Set-Acl      -Exactly 0 -Scope It
    }

    It 'applies NTFS ACL when rule is not yet present (share exists, empty DACL)' {
        Mock Test-Path    { $true }
        Mock Get-SmbShare { [PSCustomObject]@{ Name = $script:Config.Share.Name } }
        Install-ImageShare
        Should -Invoke Set-Acl -Exactly 1 -Scope It
    }

    It 'calls Get-Acl exactly once per run' {
        Install-ImageShare
        Should -Invoke Get-Acl -Exactly 1 -Scope It
    }
}

Describe 'Install-FirewallRules' {
    BeforeAll {
        . $script:SetupPath
        Mock Write-Host          {}
        Mock Add-Content         {}
        Mock New-NetFirewallRule {}
    }

    BeforeEach {
        Mock Get-NetFirewallRule {}
    }

    It 'creates all 5 firewall rules when none exist (3 UDP + 1 TCP + 1 loopback)' {
        Install-FirewallRules
        Should -Invoke New-NetFirewallRule -Exactly 5 -Scope It
    }

    It 'checks existence of each rule exactly once' {
        Install-FirewallRules
        Should -Invoke Get-NetFirewallRule -Exactly 5 -Scope It
    }

    It 'creates no rules when all already exist (idempotency)' {
        Mock Get-NetFirewallRule { [PSCustomObject]@{ Name = 'exists' } }
        Install-FirewallRules
        Install-FirewallRules
        Should -Invoke New-NetFirewallRule -Exactly 0 -Scope It
    }
}

Describe 'Disable-HostSleep' {
    BeforeAll {
        . $script:SetupPath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Invoke-PowerCfg {}
    }

    It 'calls Invoke-PowerCfg 4 times when sleep is not disabled (1 query + 3 mutations)' {
        Mock Invoke-PowerCfg {
            'Current AC Power Setting Index: 0x0000001e'
            'Current DC Power Setting Index: 0x0000001e'
        } -ParameterFilter { $Arguments -contains '/query' }
        Disable-HostSleep
        Should -Invoke Invoke-PowerCfg -Exactly 4 -Scope It
    }

    It 'skips mutations when sleep is already disabled (idempotency)' {
        Mock Invoke-PowerCfg {
            'Current AC Power Setting Index: 0x00000000'
            'Current DC Power Setting Index: 0x00000000'
        } -ParameterFilter { $Arguments -contains '/query' }
        Disable-HostSleep
        Disable-HostSleep
        Should -Invoke Invoke-PowerCfg -Exactly 0 -Scope It -ParameterFilter { $Arguments -contains '/change' }
    }
}

Describe 'Install-IVentoyService' {
    BeforeAll {
        . $script:SetupPath
        Mock Write-Host     {}
        Mock Add-Content    {}
        Mock Expand-Archive {}
        Mock New-Service    {}
        Mock Get-ChildItem  {
            [PSCustomObject]@{
                FullName = Join-Path (Join-Path $script:Config.IVentoy.InstallRoot 'iventoy-1.0.37') 'iVentoy_64.exe'
            }
        } -ParameterFilter { $Filter -eq 'iVentoy_64.exe' }
        $script:InstallRoot = $script:Config.IVentoy.InstallRoot
    }

    BeforeEach {
        Mock Test-Path   { $true }
        Mock Get-Service {}
    }

    It 'warns and skips when zip is not present' {
        Mock Test-Path { $false }
        Install-IVentoyService
        Should -Invoke Expand-Archive -Exactly 0 -Scope It
        Should -Invoke New-Service    -Exactly 0 -Scope It
    }

    It 'extracts archive and registers service on first install' {
        # zip exists; install root does not yet exist
        Mock Test-Path { $false } -ParameterFilter { $Path -eq $script:InstallRoot }
        Install-IVentoyService
        Should -Invoke Expand-Archive -Exactly 1 -Scope It
        Should -Invoke New-Service    -Exactly 1 -Scope It
    }

    It 'skips extraction when install root already populated' {
        # both zip and installRoot exist, service absent
        Install-IVentoyService
        Should -Invoke Expand-Archive -Exactly 0 -Scope It
        Should -Invoke New-Service    -Exactly 1 -Scope It
    }

    It 'skips extraction and registration when service already installed (idempotency)' {
        Mock Get-Service { [PSCustomObject]@{ Name = $script:Config.IVentoy.ServiceName } }
        Install-IVentoyService
        Install-IVentoyService
        Should -Invoke Expand-Archive -Exactly 0 -Scope It
        Should -Invoke New-Service    -Exactly 0 -Scope It
    }

    It 'registers service with BinaryPathName containing iVentoy_64.exe' {
        # install root already exists; service absent — triggers New-Service
        Install-IVentoyService
        Should -Invoke New-Service -Exactly 1 -Scope It `
            -ParameterFilter { $BinaryPathName -like '*iVentoy_64.exe*' }
    }
}
