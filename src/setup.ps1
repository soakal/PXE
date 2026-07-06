#Requires -Version 5.1
#Requires -RunAsAdministrator

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
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO'
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

function Test-Prerequisites {
    # M1: OS build guard (Win10 1809+ / Win11), PS version, D: volume present,
    # iVentoy zip present or download deferred to operator. Implemented by loop.
    throw 'Not implemented — M1 work item'
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
        exit 1
    }
}
