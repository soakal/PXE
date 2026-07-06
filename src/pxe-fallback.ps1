#Requires -Version 5.1

<#
.SYNOPSIS
    Configures a Tiny PXE Server fallback module for Secure-Boot-safe PXE imaging.

.DESCRIPTION
    Fallback PXE path for isolated staging environments where iVentoy DHCP is
    unavailable (e.g. a dedicated staging switch). Serves Microsoft-signed
    bootmgfw.efi over TFTP, which reads a BCD store that ramdisk-boots the
    SmartPE boot.wim. Avoids unsigned iPXE/wimboot that Secure Boot rejects.
    Idempotent: existing state is detected and skipped. Run twice, get the same
    result with "already configured" log entries and exit 0.

.PARAMETER Mode
    Lan (default): proxy DHCP — coexists with the existing network DHCP server.
    Field: full DHCP — TinyPXE hands out IPs on an isolated staging switch.

.PARAMETER ConfigPath
    Path to config.psd1. Defaults to config.psd1 in the same directory as this script.

.PARAMETER LogPath
    Path to the log file. Defaults to a timestamped file under config.LogDir.

.EXAMPLE
    .\pxe-fallback.ps1 -WhatIf
.EXAMPLE
    .\pxe-fallback.ps1 -Mode Field
.NOTES
    Author: Brian (via PXEForge council loop) | Version: 0.1.0-M4
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
    $LogPath = Join-Path $script:Config.LogDir ("pxe-fallback-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
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

# ── bcdedit.exe wrapper — mock this in tests; never call bcdedit.exe directly in tests ──
function Invoke-BcdEdit {
    [CmdletBinding()]
    param([string[]]$Arguments)
    $out = & bcdedit.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit.exe exited ${LASTEXITCODE}: $($out -join ' ')"
    }
    $out
}

function Copy-SecureBootFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $tftpRoot  = $script:Config.TinyPxe.TftpRoot
    $bootDir   = Join-Path $tftpRoot 'Boot'
    $destEfi   = Join-Path $tftpRoot 'bootmgfw.efi'
    $destSdi   = Join-Path $bootDir  'boot.sdi'
    $sourceEfi = $script:Config.TinyPxe.SourceEfi
    $sourceSdi = $script:Config.TinyPxe.SourceSdi

    if (-not (Test-Path -Path $tftpRoot)) {
        if ($PSCmdlet.ShouldProcess($tftpRoot, 'Create TFTP root directory')) {
            New-Item -Path $tftpRoot -ItemType Directory -Force | Out-Null
            Write-Log "Created TFTP root '$tftpRoot'." 'INFO'
        }
    } else {
        Write-Log "TFTP root '$tftpRoot' already exists — skipping." 'INFO'
    }

    if (-not (Test-Path -Path $bootDir)) {
        if ($PSCmdlet.ShouldProcess($bootDir, 'Create Boot subdirectory')) {
            New-Item -Path $bootDir -ItemType Directory -Force | Out-Null
            Write-Log "Created Boot subdir '$bootDir'." 'INFO'
        }
    } else {
        Write-Log "Boot subdir '$bootDir' already exists — skipping." 'INFO'
    }

    if (-not (Test-Path -Path $destEfi)) {
        if ($PSCmdlet.ShouldProcess($destEfi, 'Copy signed bootmgfw.efi')) {
            Copy-Item -Path $sourceEfi -Destination $destEfi
            Write-Log "Copied bootmgfw.efi to '$destEfi'." 'INFO'
        }
    } else {
        Write-Log "bootmgfw.efi already present at '$destEfi' — skipping." 'INFO'
    }

    if (-not (Test-Path -Path $destSdi)) {
        if ($PSCmdlet.ShouldProcess($destSdi, 'Copy boot.sdi')) {
            Copy-Item -Path $sourceSdi -Destination $destSdi
            Write-Log "Copied boot.sdi to '$destSdi'." 'INFO'
        }
    } else {
        Write-Log "boot.sdi already present at '$destSdi' — skipping." 'INFO'
    }
}

function New-BcdStore {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $tftpRoot = $script:Config.TinyPxe.TftpRoot
    $bcdFile  = Join-Path $tftpRoot $script:Config.TinyPxe.BcdPath
    $bootWim  = $script:Config.TinyPxe.BootWim
    # BCD device paths must start with backslash; config value may or may not have one.
    $wimPath  = '\' + $bootWim.TrimStart('\')

    if (Test-Path -Path $bcdFile) {
        Write-Log 'BCD already configured — skipping.' 'INFO'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($bcdFile, 'Build Secure-Boot BCD store')) {
        return
    }

    # 1. Create the BCD store file.
    Invoke-BcdEdit @('/createstore', $bcdFile)
    Write-Log "BCD store created at '$bcdFile'." 'INFO'

    # 2. Configure ramdisk options (SDI boot device/path — BCD-internal literals).
    Invoke-BcdEdit @('/store', $bcdFile, '/create', '{ramdiskoptions}', '/d', 'Ramdisk Options')
    Invoke-BcdEdit @('/store', $bcdFile, '/set', '{ramdiskoptions}', 'ramdisksdidevice', 'boot')
    Invoke-BcdEdit @('/store', $bcdFile, '/set', '{ramdiskoptions}', 'ramdisksdipath', '\Boot\boot.sdi')
    Write-Log 'Ramdisk options configured.' 'INFO'

    # 3. Create the OS loader entry and capture the new GUID.
    $osOutput = Invoke-BcdEdit @('/store', $bcdFile, '/create', '/d', 'SmartPE', '/application', 'osloader')
    $combined = ($osOutput -join ' ')
    if (-not ($combined -match '\{[0-9a-fA-F-]+\}')) {
        Write-Log 'Failed to parse osloader GUID from bcdedit output.' 'ERROR'
        return
    }
    $guid = $Matches[0]
    Write-Log "Osloader GUID: $guid" 'INFO'

    # 4. Set OS loader properties (winload.efi path and \windows are BCD-internal WinPE constants).
    Invoke-BcdEdit @('/store', $bcdFile, '/set', $guid, 'device',     "ramdisk=[boot]$wimPath,{ramdiskoptions}")
    Invoke-BcdEdit @('/store', $bcdFile, '/set', $guid, 'osdevice',   "ramdisk=[boot]$wimPath,{ramdiskoptions}")
    Invoke-BcdEdit @('/store', $bcdFile, '/set', $guid, 'path',       '\windows\system32\boot\winload.efi')
    Invoke-BcdEdit @('/store', $bcdFile, '/set', $guid, 'systemroot', '\windows')
    Invoke-BcdEdit @('/store', $bcdFile, '/set', $guid, 'detecthal',  'yes')
    Invoke-BcdEdit @('/store', $bcdFile, '/set', $guid, 'winpe',      'yes')
    Write-Log 'OS loader entry configured.' 'INFO'

    # 5. Create boot manager and point it at the OS loader.
    Invoke-BcdEdit @('/store', $bcdFile, '/create', '{bootmgr}', '/d', 'Windows Boot Manager')
    Invoke-BcdEdit @('/store', $bcdFile, '/set', '{bootmgr}', 'default', $guid)
    Invoke-BcdEdit @('/store', $bcdFile, '/set', '{bootmgr}', 'timeout', [string]$script:Config.TinyPxe.BootTimeout)
    Write-Log 'Boot manager configured.' 'SUCCESS'
}

function Write-TinyPxeConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $configFile = $script:Config.TinyPxe.ConfigFile
    $tftpRoot   = $script:Config.TinyPxe.TftpRoot
    $modeMarker = "PXEForge-Mode=$Mode"

    # Idempotency: skip if the file already contains this mode's marker.
    if (Test-Path -Path $configFile) {
        $existing = Get-Content -Path $configFile -Raw
        if ($existing -match [regex]::Escape($modeMarker)) {
            Write-Log "TinyPXE config already written for mode '$Mode' — skipping." 'INFO'
            return
        }
    }

    if ($Mode -eq 'Lan') {
        $proxyLine = 'ProxyDHCP=1'
        Write-Log "Writing TinyPXE config (Lan / proxyDHCP mode)." 'INFO'
    } else {
        $proxyLine = 'ProxyDHCP=0'
        Write-Log "Writing TinyPXE config (Field / full-DHCP mode)." 'INFO'
    }

    $lines = @(
        '[TFTP]',
        "RootPath=$tftpRoot",
        'BootFile=bootmgfw.efi',
        '',
        '[DHCP]',
        $proxyLine,
        "; $modeMarker"
    )

    if ($PSCmdlet.ShouldProcess($configFile, 'Write TinyPXE config file')) {
        Set-Content -Path $configFile -Value $lines
        Write-Log "TinyPXE config written to '$configFile'." 'INFO'
    }
}

function Install-PxeFallback {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $serviceName = $script:Config.TinyPxe.ServiceName
    $exe         = $script:Config.TinyPxe.Exe

    Copy-SecureBootFiles
    New-BcdStore
    Write-TinyPxeConfig

    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-Log "TinyPXE service '$serviceName' already registered — skipping." 'INFO'
        return
    }

    if ($PSCmdlet.ShouldProcess($serviceName, 'Register TinyPXE Windows service')) {
        New-Service -Name $serviceName `
            -BinaryPathName "`"$exe`"" `
            -DisplayName 'TinyPXE Server (PXEForge fallback)' `
            -StartupType Automatic | Out-Null
        Write-Log "TinyPXE service '$serviceName' registered." 'INFO'
    }
}

# ── Main ── (only runs when executed, not when dot-sourced by Pester)
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-IsElevated)) {
        Write-Log 'This script must be run as Administrator (Run as Administrator).' 'ERROR'
        exit 4
    }
    try {
        Write-Log "=== PXEForge pxe-fallback v0.1.0 started (Mode: $Mode) ==="
        Install-PxeFallback
        Write-Log '=== Completed successfully ===' 'SUCCESS'
        exit 0
    } catch {
        Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
        exit 1
    }
}
