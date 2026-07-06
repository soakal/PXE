#Requires -Version 5.1

<#
.SYNOPSIS
    Validates PXE appliance health: ports listening, ACLs, service state, ISO count, share reachable.

.DESCRIPTION
    Read-only post-setup health check. Runs five checks and exits 0 only if ALL pass.
    Logs PASS/FAIL per check. No state mutations — no ShouldProcess.
    Exit 0 = all healthy; exit 1 = one or more checks failed.

.PARAMETER ConfigPath
    Path to config.psd1. Defaults to config.psd1 in the same directory as this script.

.PARAMETER LogPath
    Path to the log file. Defaults to a timestamped file under config.LogDir.

.EXAMPLE
    .\validate.ps1
.NOTES
    Author: Brian (via PXEForge council loop) | Version: 0.1.0-M3
    Tested: pending M5 hardware validation
#>

[CmdletBinding()]
param(
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
    $LogPath = Join-Path $script:Config.LogDir ("validate-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
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

# Check 1: UDP and TCP ports have active listeners.
function Test-PortsListening {
    [CmdletBinding()]
    param()
    $passed = $true
    foreach ($port in $script:Config.Firewall.UdpPorts) {
        $ep = Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue
        if ($ep) {
            Write-Log "PASS: UDP $port is listening." 'SUCCESS'
        } else {
            Write-Log "FAIL: UDP $port is not listening." 'ERROR'
            $passed = $false
        }
    }
    foreach ($port in $script:Config.Firewall.TcpPorts) {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            Write-Log "PASS: TCP $port is listening." 'SUCCESS'
        } else {
            Write-Log "FAIL: TCP $port is not listening." 'ERROR'
            $passed = $false
        }
    }
    return $passed
}

# Check 2: Share root has ReadAndExecute Allow ACE for the service account.
function Test-AclAudit {
    [CmdletBinding()]
    param()
    $path    = $script:Config.Share.Path
    $account = $script:Config.Share.ServiceAccount
    $acl     = Get-Acl -Path $path
    $ace     = $acl.Access | Where-Object {
                   $_.IdentityReference.Value -like "*$account*" -and
                   ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadAndExecute) -and
                   $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow
               }
    if ($ace) {
        Write-Log "PASS: ACL on '$path' has ReadAndExecute Allow for '$account'." 'SUCCESS'
        return $true
    }
    Write-Log "FAIL: ACL on '$path' missing ReadAndExecute Allow for '$account'." 'ERROR'
    return $false
}

# Check 3: iVentoy service exists and is Running.
function Test-ServiceState {
    [CmdletBinding()]
    param()
    $name = $script:Config.IVentoy.ServiceName
    $svc  = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Log "PASS: Service '$name' is Running." 'SUCCESS'
        return $true
    }
    Write-Log "FAIL: Service '$name' is not running or not found." 'ERROR'
    return $false
}

# Check 4: At least one ISO is present in the iVentoy ISO directory.
function Test-IsoPresent {
    [CmdletBinding()]
    param()
    $isoDir = $script:Config.IVentoy.IsoDir
    $isos   = @(Get-ChildItem -Path $isoDir -Filter '*.iso' -ErrorAction SilentlyContinue)
    $count  = $isos.Count
    if ($count -ge 1) {
        Write-Log "PASS: $count ISO(s) present in '$isoDir'." 'SUCCESS'
        return $true
    }
    Write-Log "FAIL: No ISO present in '$isoDir' (expected at least 1)." 'ERROR'
    return $false
}

# Check 5: SMB share exists and its path resolves on the filesystem.
function Test-ShareReachable {
    [CmdletBinding()]
    param()
    $name  = $script:Config.Share.Name
    $share = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
    if (-not $share) {
        Write-Log "FAIL: SMB share '$name' not found." 'ERROR'
        return $false
    }
    if (Test-Path -Path $share.Path) {
        Write-Log "PASS: SMB share '$name' exists and path resolves." 'SUCCESS'
        return $true
    }
    Write-Log "FAIL: SMB share '$name' found but path '$($share.Path)' does not resolve." 'ERROR'
    return $false
}

# Runs all five checks; returns $true only when every check passes.
function Invoke-Validate {
    [CmdletBinding()]
    param()
    $allPassed = $true
    if (-not (Test-PortsListening)) { $allPassed = $false }
    if (-not (Test-AclAudit))       { $allPassed = $false }
    if (-not (Test-ServiceState))   { $allPassed = $false }
    if (-not (Test-IsoPresent))     { $allPassed = $false }
    if (-not (Test-ShareReachable)) { $allPassed = $false }
    return $allPassed
}

# ── Main ── (only runs when executed, not when dot-sourced by Pester)
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-IsElevated)) {
        Write-Log 'This script must be run as Administrator (Run as Administrator).' 'ERROR'
        exit 4
    }
    try {
        Write-Log '=== PXEForge validate started ==='
        if (Invoke-Validate) {
            Write-Log '=== All checks PASSED ===' 'SUCCESS'
            exit 0
        } else {
            Write-Log '=== One or more checks FAILED ===' 'ERROR'
            exit 1
        }
    } catch {
        Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
        exit 1
    }
}
