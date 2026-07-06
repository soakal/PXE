#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# M3 gate: validate.ps1 — five health checks, each with PASS and FAIL branches.
# All query cmdlets are mocked; call counts asserted where behavior matters.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:ValidatePath = Join-Path $PSScriptRoot '..\src\validate.ps1'
    $script:ConfigPath   = Join-Path $PSScriptRoot '..\src\config.psd1'
}

# ── Check 1: Ports listening ──────────────────────────────────────────────────
Describe 'Test-PortsListening' {
    BeforeAll {
        . $script:ValidatePath
        Mock Write-Host           {}
        Mock Add-Content          {}
        Mock Test-IsElevated      { $true }
        Mock Get-NetUDPEndpoint   { [PSCustomObject]@{ LocalPort = 0 } }
        Mock Get-NetTCPConnection { [PSCustomObject]@{ LocalPort = 0; State = 'Listen' } }
    }

    It 'returns true when all UDP and TCP ports have listeners (PASS)' {
        Test-PortsListening | Should -BeTrue
    }

    It 'calls Get-NetUDPEndpoint once per configured UDP port (67, 68, 69)' {
        Test-PortsListening
        Should -Invoke Get-NetUDPEndpoint -Exactly 3 -Scope It
    }

    It 'calls Get-NetTCPConnection once per configured TCP port (16000)' {
        Test-PortsListening
        Should -Invoke Get-NetTCPConnection -Exactly 1 -Scope It
    }

    It 'returns false when a UDP port is not listening (FAIL)' {
        Mock Get-NetUDPEndpoint {}
        Test-PortsListening | Should -BeFalse
    }

    It 'logs an ERROR when a UDP port is not listening' {
        Mock Get-NetUDPEndpoint {}
        Test-PortsListening
        Should -Invoke Write-Host -Times 3 -Scope It -ParameterFilter { $ForegroundColor -eq 'Red' }
    }

    It 'returns false when the TCP port is not listening (FAIL)' {
        Mock Get-NetTCPConnection {}
        Test-PortsListening | Should -BeFalse
    }

    It 'logs an ERROR when the TCP port is not listening' {
        Mock Get-NetTCPConnection {}
        Test-PortsListening
        Should -Invoke Write-Host -Times 1 -Scope It -ParameterFilter { $ForegroundColor -eq 'Red' }
    }
}

# ── Check 2: ACL audit ────────────────────────────────────────────────────────
Describe 'Test-AclAudit' {
    BeforeAll {
        . $script:ValidatePath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
    }

    It 'returns true when the service account ACE is present (PASS)' {
        Mock Get-Acl {
            $account = $script:Config.Share.ServiceAccount
            [PSCustomObject]@{
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $account }
                        FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
                        AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    }
                )
            }
        }
        Test-AclAudit | Should -BeTrue
    }

    It 'returns false when the ACL has no matching ACE (FAIL)' {
        Mock Get-Acl {
            [PSCustomObject]@{ Access = @() }
        }
        Test-AclAudit | Should -BeFalse
    }

    It 'calls Get-Acl exactly once per run' {
        Mock Get-Acl { [PSCustomObject]@{ Access = @() } }
        Test-AclAudit
        Should -Invoke Get-Acl -Exactly 1 -Scope It
    }
}

# ── Check 3: Service state ────────────────────────────────────────────────────
Describe 'Test-ServiceState' {
    BeforeAll {
        . $script:ValidatePath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
    }

    It 'returns true when the service exists and is Running (PASS)' {
        Mock Get-Service { [PSCustomObject]@{ Name = $script:Config.IVentoy.ServiceName; Status = 'Running' } }
        Test-ServiceState | Should -BeTrue
    }

    It 'returns false when the service is not found (FAIL)' {
        Mock Get-Service {}
        Test-ServiceState | Should -BeFalse
    }

    It 'returns false when the service is Stopped (FAIL)' {
        Mock Get-Service { [PSCustomObject]@{ Name = $script:Config.IVentoy.ServiceName; Status = 'Stopped' } }
        Test-ServiceState | Should -BeFalse
    }

    It 'calls Get-Service exactly once per run' {
        Mock Get-Service { [PSCustomObject]@{ Name = $script:Config.IVentoy.ServiceName; Status = 'Running' } }
        Test-ServiceState
        Should -Invoke Get-Service -Exactly 1 -Scope It
    }
}

# ── Check 4: At least one ISO present ────────────────────────────────────────
Describe 'Test-IsoPresent' {
    BeforeAll {
        . $script:ValidatePath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
    }

    It 'returns true when exactly one ISO is present (PASS)' {
        Mock Get-ChildItem {
            [PSCustomObject]@{ Name = 'SmartPE.iso'; FullName = (Join-Path $script:Config.IVentoy.IsoDir 'SmartPE.iso') }
        }
        Test-IsoPresent | Should -BeTrue
    }

    It 'returns false when no ISOs are present (FAIL — 0 ISOs)' {
        Mock Get-ChildItem {}
        Test-IsoPresent | Should -BeFalse
    }

    It 'returns true when more than one ISO is present (PASS — 2 ISOs)' {
        Mock Get-ChildItem {
            @(
                [PSCustomObject]@{ Name = 'SmartPE.iso' },
                [PSCustomObject]@{ Name = 'SmartPE-old.iso' }
            )
        }
        Test-IsoPresent | Should -BeTrue
    }

    It 'calls Get-ChildItem exactly once per run' {
        Mock Get-ChildItem {}
        Test-IsoPresent
        Should -Invoke Get-ChildItem -Exactly 1 -Scope It
    }
}

# ── Check 5: Share reachable ──────────────────────────────────────────────────
Describe 'Test-ShareReachable' {
    BeforeAll {
        . $script:ValidatePath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
    }

    It 'returns true when the share exists and its path resolves (PASS)' {
        Mock Get-SmbShare { [PSCustomObject]@{ Name = $script:Config.Share.Name; Path = $script:Config.Share.Path } }
        Mock Test-Path    { $true }
        Test-ShareReachable | Should -BeTrue
    }

    It 'returns false when the share is not found (FAIL)' {
        Mock Get-SmbShare {}
        Test-ShareReachable | Should -BeFalse
    }

    It 'returns false when the share exists but its path does not resolve (FAIL)' {
        Mock Get-SmbShare { [PSCustomObject]@{ Name = $script:Config.Share.Name; Path = $script:Config.Share.Path } }
        Mock Test-Path    { $false }
        Test-ShareReachable | Should -BeFalse
    }

    It 'calls Get-SmbShare exactly once per run' {
        Mock Get-SmbShare {}
        Test-ShareReachable
        Should -Invoke Get-SmbShare -Exactly 1 -Scope It
    }
}

# ── Invoke-Validate aggregation ───────────────────────────────────────────────
Describe 'Invoke-Validate' {
    BeforeAll {
        . $script:ValidatePath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
    }

    It 'returns true when all five checks pass' {
        Mock Get-NetUDPEndpoint   { [PSCustomObject]@{ LocalPort = 0 } }
        Mock Get-NetTCPConnection { [PSCustomObject]@{ LocalPort = 0; State = 'Listen' } }
        Mock Get-Acl              {
            $account = $script:Config.Share.ServiceAccount
            [PSCustomObject]@{
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $account }
                        FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
                        AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    }
                )
            }
        }
        Mock Get-Service          { [PSCustomObject]@{ Name = $script:Config.IVentoy.ServiceName; Status = 'Running' } }
        Mock Get-ChildItem        {
            [PSCustomObject]@{ Name = 'SmartPE.iso'; FullName = (Join-Path $script:Config.IVentoy.IsoDir 'SmartPE.iso') }
        }
        Mock Get-SmbShare         { [PSCustomObject]@{ Name = $script:Config.Share.Name; Path = $script:Config.Share.Path } }
        Mock Test-Path            { $true }

        Invoke-Validate | Should -BeTrue
    }

    It 'returns false when any check fails (service stopped)' {
        Mock Get-NetUDPEndpoint   { [PSCustomObject]@{ LocalPort = 0 } }
        Mock Get-NetTCPConnection { [PSCustomObject]@{ LocalPort = 0; State = 'Listen' } }
        Mock Get-Acl              {
            $account = $script:Config.Share.ServiceAccount
            [PSCustomObject]@{
                Access = @(
                    [PSCustomObject]@{
                        IdentityReference = [PSCustomObject]@{ Value = $account }
                        FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
                        AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
                    }
                )
            }
        }
        # Service fails.
        Mock Get-Service          { [PSCustomObject]@{ Name = $script:Config.IVentoy.ServiceName; Status = 'Stopped' } }
        Mock Get-ChildItem        {
            [PSCustomObject]@{ Name = 'SmartPE.iso'; FullName = (Join-Path $script:Config.IVentoy.IsoDir 'SmartPE.iso') }
        }
        Mock Get-SmbShare         { [PSCustomObject]@{ Name = $script:Config.Share.Name; Path = $script:Config.Share.Path } }
        Mock Test-Path            { $true }

        Invoke-Validate | Should -BeFalse
    }
}

# ── Scaffold contract — validate ──────────────────────────────────────────────
Describe 'Scaffold contract — validate' {
    It 'validate.ps1 parses without syntax errors' {
        $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ValidatePath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'validate.ps1 contains no hardcoded IP addresses' {
        (Get-Content $script:ValidatePath -Raw) | Should -Not -Match '\b\d{1,3}(\.\d{1,3}){3}\b'
    }

    It 'validate.ps1 does not declare SupportsShouldProcess (read-only script)' {
        (Get-Content $script:ValidatePath -Raw) | Should -Not -Match 'SupportsShouldProcess'
    }
}
