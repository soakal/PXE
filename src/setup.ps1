#Requires -Version 5.1

<#
.SYNOPSIS
    Configures a Windows 10/11 Pro host as a standalone SmartDeploy PXE appliance (iVentoy).

.DESCRIPTION
    Idempotent. Creates the SDShare SMB share + read-only service account, opens
    firewall ports, disables sleep, extracts iVentoy and registers it as a service.
    Safe to re-run: existing state is detected and skipped. See CLAUDE.md — this
    script is implemented by the council loop across milestones M1-M2.

.PARAMETER Mode
    Lan (default): iVentoy in ExternalNet DHCP mode alongside the existing DHCP server.
    Field: iVentoy runs its own DHCP server for an isolated staging switch.

.EXAMPLE
    .\setup.ps1 -WhatIf
.EXAMPLE
    .\setup.ps1 -Mode Field
.NOTES
    Author: Brian (via PXEForge council loop) | Version: 0.1.0-M1
    Tested: pending M5 hardware validation
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('Lan', 'Field')]
    [string]$Mode = 'Lan',

    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),

    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Config = Import-PowerShellDataFile -Path $ConfigPath
if (-not $LogPath) {
    $LogPath = Join-Path $script:Config.LogDir ("setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [Parameter(Position = 1)][ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO'
    )
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'ERROR'   { Write-Host $entry -ForegroundColor Red }
        'WARN'    { Write-Host $entry -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry }
    }
    Add-Content -Path $LogPath -Value $entry -ErrorAction SilentlyContinue
}

function Test-IsElevated {
    # Wrapped so Pester can mock it without touching .NET reflection directly.
    [CmdletBinding()]
    param()
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()

    Write-Log 'Checking prerequisites...'

    # 1. Elevation
    if (-not (Test-IsElevated)) {
        throw 'PREREQ:NOT_ELEVATED: This script must be run as Administrator (Run as Administrator).'
    }
    Write-Log 'Elevation confirmed.' 'INFO'

    # 2. PowerShell version >= 5.1
    $minVersion = [Version]'5.1'
    if ($PSVersionTable.PSVersion -lt $minVersion) {
        throw ('PREREQ:BAD_INPUT: PowerShell {0} or later is required (found {1}).' -f $minVersion, $PSVersionTable.PSVersion)
    }
    Write-Log ('PowerShell {0} — satisfied.' -f $PSVersionTable.PSVersion) 'INFO'

    # 3. OS build guard: Win10 1809 (17763) or Win11 (22000+)
    $os    = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    if ($build -lt 17763) {
        throw ('PREREQ:BAD_INPUT: Unsupported OS build {0}. Windows 10 1809 (build 17763) or later is required.' -f $build)
    }
    Write-Log ('OS build {0} — supported.' -f $build) 'INFO'

    # 4. Data volume present (drive that hosts the configured share path)
    $drive = Split-Path -Qualifier $script:Config.Share.Path
    if (-not (Test-Path -Path $drive)) {
        throw ('PREREQ:MISSING_DEP: Data volume ''{0}'' is not present. Attach and format the data drive, then re-run.' -f $drive)
    }
    Write-Log ('Data volume {0} present.' -f $drive) 'INFO'

    # 5. iVentoy install media — missing is a deferred-operator condition, not fatal
    $zipPath = $script:Config.IVentoy.ZipPath
    if (-not (Test-Path -Path $zipPath)) {
        Write-Log ('iVentoy installer not found at ''{0}''. Download iVentoy {1} zip and place it there before the M2 tasks run.' -f $zipPath, $script:Config.IVentoy.Version) 'WARN'
    } else {
        Write-Log ('iVentoy installer found at ''{0}''.' -f $zipPath) 'INFO'
    }

    Write-Log 'All prerequisites satisfied.' 'SUCCESS'
}

# ── PowerCfg wrapper — mock this in tests; never call powercfg.exe directly ──
function Invoke-PowerCfg {
    [CmdletBinding()]
    param([string[]]$Arguments)
    & powercfg.exe @Arguments
}

function Install-ServiceAccount {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $account = $script:Config.Share.ServiceAccount
    if (Get-LocalUser -Name $account -ErrorAction SilentlyContinue) {
        Write-Log "'$account' service account already configured — skipping." 'INFO'
        return
    }

    if ($PSCmdlet.ShouldProcess($account, 'Create local service account')) {
        $chars  = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
        $secPwd = New-Object System.Security.SecureString
        1..24 | ForEach-Object { $secPwd.AppendChar($chars[(Get-Random -Maximum $chars.Length)]) }
        $secPwd.MakeReadOnly()
        New-LocalUser -Name $account -Password $secPwd `
            -PasswordNeverExpires -UserMayNotChangePassword `
            -Description 'PXEForge read-only share service account' | Out-Null
        Write-Log "Service account '$account' created." 'INFO'
    }
}

function Install-ImageShare {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $path    = $script:Config.Share.Path
    $name    = $script:Config.Share.Name
    $account = $script:Config.Share.ServiceAccount

    if (-not (Test-Path -Path $path)) {
        if ($PSCmdlet.ShouldProcess($path, 'Create share root directory')) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-Log "Created directory '$path'." 'INFO'
        }
    } else {
        Write-Log "Directory '$path' already exists — skipping." 'INFO'
    }

    foreach ($sub in $script:Config.Share.SubDirs) {
        $subPath = Join-Path $path $sub
        if (-not (Test-Path -Path $subPath)) {
            if ($PSCmdlet.ShouldProcess($subPath, 'Create subdirectory')) {
                New-Item -Path $subPath -ItemType Directory -Force | Out-Null
                Write-Log "Created subdirectory '$subPath'." 'INFO'
            }
        } else {
            Write-Log "Subdirectory '$subPath' already exists — skipping." 'INFO'
        }
    }

    if (Get-SmbShare -Name $name -ErrorAction SilentlyContinue) {
        Write-Log "SMB share '$name' already configured — skipping." 'INFO'
    } elseif ($PSCmdlet.ShouldProcess($name, 'Create SMB share')) {
        New-SmbShare -Name $name -Path $path -ReadAccess $account | Out-Null
        Write-Log "SMB share '$name' created (ReadAccess: $account)." 'INFO'
    }

    $acl         = Get-Acl -Path $path
    $existingAce = $acl.Access | Where-Object {
                       $_.IdentityReference.Value -like "*$account*" -and
                       ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadAndExecute) -and
                       $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow
                   }
    if ($existingAce) {
        Write-Log "NTFS ACL already configured — skipping." 'INFO'
    } elseif ($PSCmdlet.ShouldProcess($path, 'Apply NTFS read-only ACL')) {
        $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                   [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $rule    = New-Object System.Security.AccessControl.FileSystemAccessRule(
                       $account,
                       [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                       $inherit,
                       [System.Security.AccessControl.PropagationFlags]::None,
                       [System.Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
        Set-Acl -Path $path -AclObject $acl
        Write-Log "NTFS ACL applied: '$account' ReadAndExecute on '$path'." 'INFO'
    }
}

function Install-FirewallRules {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $prefix = $script:Config.Firewall.RulePrefix

    foreach ($port in $script:Config.Firewall.UdpPorts) {
        $ruleName = '{0}-UDP-{1}' -f $prefix, $port
        if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
            Write-Log "Firewall rule '$ruleName' already exists — skipping." 'INFO'
        } elseif ($PSCmdlet.ShouldProcess($ruleName, 'Create inbound UDP firewall rule')) {
            New-NetFirewallRule -Name $ruleName -DisplayName $ruleName `
                -Direction Inbound -Protocol UDP -LocalPort $port -Action Allow | Out-Null
            Write-Log "Firewall rule '$ruleName' created." 'INFO'
        }
    }

    foreach ($port in $script:Config.Firewall.TcpPorts) {
        $ruleName = '{0}-TCP-{1}' -f $prefix, $port
        if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
            Write-Log "Firewall rule '$ruleName' already exists — skipping." 'INFO'
        } elseif ($PSCmdlet.ShouldProcess($ruleName, 'Create inbound TCP firewall rule')) {
            New-NetFirewallRule -Name $ruleName -DisplayName $ruleName `
                -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
            Write-Log "Firewall rule '$ruleName' created." 'INFO'
        }
    }

    # UI management port — IPv4 loopback scope only (system constant, not a configurable address)
    $uiPort  = $script:Config.IVentoy.UiPort
    $uiRule  = '{0}-TCP-{1}-loopback' -f $prefix, $uiPort
    if (Get-NetFirewallRule -Name $uiRule -ErrorAction SilentlyContinue) {
        Write-Log "Firewall rule '$uiRule' already exists — skipping." 'INFO'
    } elseif ($PSCmdlet.ShouldProcess($uiRule, 'Create loopback-only TCP firewall rule')) {
        New-NetFirewallRule -Name $uiRule -DisplayName $uiRule `
            -Direction Inbound -Protocol TCP -LocalPort $uiPort `
            -RemoteAddress ([System.Net.IPAddress]::Loopback.ToString()) -Action Allow | Out-Null
        Write-Log "Firewall rule '$uiRule' created (loopback-only)." 'INFO'
    }
}

function Disable-HostSleep {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $queryOutput = (Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', 'SUB_SLEEP', 'STANDBYIDLE')) -join "`n"
    $acZero      = $queryOutput -match 'Current AC Power Setting Index:\s*0x00000000'
    $dcZero      = $queryOutput -match 'Current DC Power Setting Index:\s*0x00000000'
    if ($acZero -and $dcZero) {
        Write-Log 'Sleep already disabled — skipping.' 'INFO'
        return
    }

    if ($PSCmdlet.ShouldProcess('host power settings', 'Disable standby and hibernate')) {
        Invoke-PowerCfg -Arguments @('/change', 'standby-timeout-ac', '0')
        Write-Log 'AC standby disabled (timeout=0).' 'INFO'
        Invoke-PowerCfg -Arguments @('/change', 'standby-timeout-dc', '0')
        Write-Log 'DC standby disabled (timeout=0).' 'INFO'
        Invoke-PowerCfg -Arguments @('/hibernate', 'off')
        Write-Log 'Hibernate disabled.' 'INFO'
    }
}

function Install-IVentoyService {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $zipPath     = $script:Config.IVentoy.ZipPath
    $installRoot = $script:Config.IVentoy.InstallRoot
    $serviceName = $script:Config.IVentoy.ServiceName
    $dhcpMode    = if ($Mode -eq 'Field') { 'DHCPServer' } else { 'ExternalNet' }

    if (-not (Test-Path -Path $zipPath)) {
        Write-Log "iVentoy zip not found at '$zipPath' — skipping service installation." 'WARN'
        return
    }

    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-Log "iVentoy service '$serviceName' already installed — skipping." 'INFO'
        return
    }

    if (-not (Test-Path -Path $installRoot)) {
        if ($PSCmdlet.ShouldProcess($zipPath, 'Extract iVentoy archive')) {
            Expand-Archive -Path $zipPath -DestinationPath $installRoot -Force
            Write-Log "iVentoy extracted to '$installRoot'." 'INFO'
        }
    } else {
        Write-Log "iVentoy install root '$installRoot' already populated — skipping extraction." 'INFO'
    }

    $exePath = Get-ChildItem -Path $installRoot -Filter 'iventoy.exe' -Recurse `
        -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

    if (-not $exePath) {
        Write-Log "iVentoy executable not found under '$installRoot'." 'WARN'
        return
    }

    if ($PSCmdlet.ShouldProcess($serviceName, 'Register iVentoy Windows service')) {
        New-Service -Name $serviceName `
            -BinaryPathName "`"$exePath`" /mode $dhcpMode" `
            -DisplayName 'iVentoy PXE Server' `
            -StartupType Automatic | Out-Null
        Write-Log "iVentoy service '$serviceName' registered (DhcpMode: $dhcpMode)." 'INFO'
    }
}

# ── Main ── (only runs when executed, not when dot-sourced by Pester)
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Write-Log "=== PXEForge setup v0.1.0 started (Mode: $Mode) ==="
        Test-Prerequisites
        Install-ServiceAccount
        Install-ImageShare
        Install-FirewallRules
        Disable-HostSleep
        Install-IVentoyService
        Write-Log "=== Completed successfully ===" 'SUCCESS'
        exit 0
    } catch {
        Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
        switch -Wildcard ($_.Exception.Message) {
            'PREREQ:NOT_ELEVATED:*' { exit 4 }
            'PREREQ:MISSING_DEP:*'  { exit 3 }
            'PREREQ:BAD_INPUT:*'    { exit 2 }
            default                 { exit 1 }
        }
    }
}
