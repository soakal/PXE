#Requires -Version 5.1

<#
.SYNOPSIS
    Mirrors WIM images and Platform Packs from Unraid into the local SDShare using robocopy /MIR.

.DESCRIPTION
    Gates the destructive /MIR operation behind -Force or explicit confirmation.
    Each configured subfolder (Images, Platform Packs) is synced independently.
    robocopy exit codes 0-7 are success; 8+ are failure (script exits 1).

.PARAMETER Force
    Skip the ShouldProcess confirmation gate. Required for unattended/scheduled use.

.PARAMETER ConfigPath
    Path to config.psd1. Defaults to config.psd1 in the same directory as this script.

.PARAMETER LogPath
    Path to the log file. Defaults to a timestamped file under config.LogDir.

.EXAMPLE
    .\sync-images.ps1 -Force
.EXAMPLE
    .\sync-images.ps1 -WhatIf
.NOTES
    Author: Brian (via PXEForge council loop) | Version: 0.1.0-M3
    Tested: pending M5 hardware validation
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $script:Config = Import-PowerShellDataFile -Path $ConfigPath
} catch {
    if ($MyInvocation.InvocationName -ne '.') {
        Write-Host "[ERROR] Cannot load config '$ConfigPath': $($_.Exception.Message)"
        exit 2
    }
    throw
}
if (-not $LogPath) {
    $LogPath = Join-Path $script:Config.LogDir ("sync-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
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

# Robocopy wrapper — mock this in tests; never call robocopy.exe directly in tests.
function Invoke-Robocopy {
    [CmdletBinding()]
    param([string[]]$Arguments)
    & robocopy.exe @Arguments | Out-Null
    return $LASTEXITCODE
}

function Sync-Images {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([switch]$Force)

    $proceed = $Force.IsPresent -or $PSCmdlet.ShouldProcess(
        $script:Config.Sync.Source,
        'Mirror source into share using robocopy /MIR (DESTRUCTIVE on destination)'
    )

    if (-not $proceed) {
        Write-Log 'Sync gate not passed — use -Force or confirm interactively. No action taken.' 'WARN'
        return 'cancelled'
    }

    $failed = $false
    foreach ($folder in $script:Config.Sync.Include) {
        $src = Join-Path $script:Config.Sync.Source $folder
        $dst = Join-Path $script:Config.Share.Path $folder
        Write-Log "Syncing '$folder': $src -> $dst"
        $rc = Invoke-Robocopy -Arguments @($src, $dst, '/MIR')
        if ($rc -ge 8) {
            Write-Log "Robocopy failed for '$folder' (exit code $rc)." 'ERROR'
            $failed = $true
        } else {
            Write-Log "Sync complete for '$folder' (robocopy exit code $rc)." 'SUCCESS'
        }
    }

    if ($failed) { return 'failed' }
    return 'ok'
}

# ── Main ── (only runs when executed, not when dot-sourced by Pester)
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-IsElevated)) {
        Write-Log 'This script must be run as Administrator (Run as Administrator).' 'ERROR'
        exit 4
    }
    try {
        Write-Log '=== PXEForge sync-images started ==='
        $result = Sync-Images -Force:$Force
        if ($result -eq 'failed') {
            Write-Log 'One or more folders failed to sync.' 'ERROR'
            exit 1
        }
        Write-Log '=== Completed successfully ===' 'SUCCESS'
        exit 0
    } catch {
        Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
        exit 1
    }
}
