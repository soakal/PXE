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

function Install-ServiceAccount   { [CmdletBinding(SupportsShouldProcess)] param() throw 'Not implemented — M2' }
function Install-ImageShare       { [CmdletBinding(SupportsShouldProcess)] param() throw 'Not implemented — M2' }
function Install-FirewallRules    { [CmdletBinding(SupportsShouldProcess)] param() throw 'Not implemented — M2' }
function Disable-HostSleep        { [CmdletBinding(SupportsShouldProcess)] param() throw 'Not implemented — M2' }
function Install-IVentoyService   { [CmdletBinding(SupportsShouldProcess)] param() throw 'Not implemented — M2' }

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
