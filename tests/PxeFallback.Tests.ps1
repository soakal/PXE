#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# M4 gate: pxe-fallback.ps1 — Secure-Boot-safe TinyPXE fallback module.
# All host-mutating cmdlets are MOCKED; call counts are asserted where behavior matters.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:FallbackPath = Join-Path $PSScriptRoot '..\src\pxe-fallback.ps1'
    $script:ConfigPath   = Join-Path $PSScriptRoot '..\src\config.psd1'
}

# ── Scaffold contract ─────────────────────────────────────────────────────────
Describe 'Scaffold contract — pxe-fallback' {
    It 'pxe-fallback.ps1 parses without syntax errors' {
        $tokens = $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:FallbackPath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'pxe-fallback.ps1 declares SupportsShouldProcess' {
        (Get-Content $script:FallbackPath -Raw) | Should -Match 'SupportsShouldProcess'
    }

    It 'pxe-fallback.ps1 contains no hardcoded IP addresses' {
        (Get-Content $script:FallbackPath -Raw) | Should -Not -Match '\b\d{1,3}(\.\d{1,3}){3}\b'
    }

    It 'config.psd1 TinyPxe block has all required keys' {
        $cfg = Import-PowerShellDataFile -Path $script:ConfigPath
        $cfg.TinyPxe                    | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.InstallRoot        | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.Exe                | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.ConfigFile         | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.TftpRoot           | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.ServiceName        | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.BcdPath            | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.BootWim            | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.SourceEfi          | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.SourceSdi          | Should -Not -BeNullOrEmpty
        $cfg.TinyPxe.BootTimeout        | Should -BeGreaterThan 0
    }
}

# ── Invoke-BcdEdit ────────────────────────────────────────────────────────────
Describe 'Invoke-BcdEdit' {
    BeforeAll {
        . $script:FallbackPath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
    }

    It 'is defined as a function that accepts an Arguments parameter' {
        $fn = Get-Command -Name Invoke-BcdEdit -CommandType Function
        $fn                             | Should -Not -BeNullOrEmpty
        $fn.Parameters.ContainsKey('Arguments') | Should -BeTrue
    }
}

# ── Copy-SecureBootFiles ──────────────────────────────────────────────────────
Describe 'Copy-SecureBootFiles' {
    BeforeAll {
        . $script:FallbackPath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
        Mock New-Item        {}
        Mock Copy-Item       {}
    }

    BeforeEach {
        # Default: nothing exists yet (fresh state).
        Mock Test-Path { $false }
    }

    It 'creates both directories and copies both files on a fresh system' {
        Copy-SecureBootFiles
        # TftpRoot + Boot subdir = 2 dirs
        Should -Invoke New-Item   -Exactly 2 -Scope It
        # bootmgfw.efi + boot.sdi = 2 files
        Should -Invoke Copy-Item  -Exactly 2 -Scope It
    }

    It 'calls Test-Path for each destination (4 checks: 2 dirs + 2 files)' {
        Copy-SecureBootFiles
        Should -Invoke Test-Path -Exactly 4 -Scope It
    }

    It 'skips all New-Item and Copy-Item calls when everything already exists (idempotency)' {
        Mock Test-Path { $true }
        Copy-SecureBootFiles
        Copy-SecureBootFiles
        Should -Invoke New-Item  -Exactly 0 -Scope It
        Should -Invoke Copy-Item -Exactly 0 -Scope It
    }

    It 'skips only the EFI copy when bootmgfw.efi destination already exists' {
        $script:SdiDest = Join-Path (Join-Path $script:Config.TinyPxe.TftpRoot 'Boot') 'boot.sdi'
        # Dirs exist, EFI file exists, SDI file does not.
        Mock Test-Path { $true }  -ParameterFilter { $Path -ne $script:SdiDest }
        Mock Test-Path { $false } -ParameterFilter { $Path -eq $script:SdiDest }
        Copy-SecureBootFiles
        # Only the SDI file should be copied.
        Should -Invoke Copy-Item -Exactly 1 -Scope It
    }
}

# ── New-BcdStore ──────────────────────────────────────────────────────────────
Describe 'New-BcdStore' {
    BeforeAll {
        . $script:FallbackPath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
        $script:CannedGuid   = '{11111111-2222-3333-4444-555555555555}'
        $script:CannedOutput = "The entry $($script:CannedGuid) was successfully created."
    }

    BeforeEach {
        # Default: BCD file does not exist (fresh).
        Mock Test-Path { $false }
        # The osloader /create call returns a canned GUID; all other calls return ''.
        Mock Invoke-BcdEdit { $script:CannedOutput } -ParameterFilter { $Arguments -contains 'osloader' }
        Mock Invoke-BcdEdit { '' }
    }

    It 'calls Invoke-BcdEdit 0 times when BCD file already exists (idempotency)' {
        Mock Test-Path { $true }
        New-BcdStore
        Should -Invoke Invoke-BcdEdit -Exactly 0 -Scope It
    }

    It 'logs "BCD already configured" when BCD file already exists' {
        Mock Test-Path { $true }
        New-BcdStore
        # Write-Log at INFO level calls Write-Host without a colour filter.
        Should -Invoke Write-Host -Times 1 -Scope It -ParameterFilter {
            $Object -match 'BCD already configured'
        }
    }

    It 'calls Invoke-BcdEdit exactly 14 times on a fresh BCD store' {
        # 1 createstore + 3 ramdiskoptions + 1 osloader create + 6 osloader sets + 3 bootmgr = 14
        New-BcdStore
        Should -Invoke Invoke-BcdEdit -Exactly 14 -Scope It
    }

    It 'threads the parsed osloader GUID into subsequent /set calls' {
        New-BcdStore
        Should -Invoke Invoke-BcdEdit -Times 1 -Scope It -ParameterFilter {
            $Arguments -contains $script:CannedGuid
        }
    }

    It 'logs ERROR and returns without completing the sequence when GUID cannot be parsed' {
        # Override the osloader mock so it returns no GUID.
        Mock Invoke-BcdEdit { '' } -ParameterFilter { $Arguments -contains 'osloader' }
        Mock Invoke-BcdEdit { '' }
        New-BcdStore
        Should -Invoke Write-Host -Times 1 -Scope It -ParameterFilter {
            $ForegroundColor -eq 'Red'
        }
    }

    It 'does not call Invoke-BcdEdit after GUID parse failure' {
        Mock Invoke-BcdEdit { '' } -ParameterFilter { $Arguments -contains 'osloader' }
        Mock Invoke-BcdEdit { '' }
        New-BcdStore
        # createstore + ramdiskoptions (3) + osloader create (1) = 5 calls before the parse attempt.
        # After failure the function returns, so calls 6-14 must NOT happen.
        # Fewer than 14 total calls confirms the early return.
        Should -Invoke Invoke-BcdEdit -Times 5 -Exactly -Scope It
    }
}

# ── Write-TinyPxeConfig — Lan mode ───────────────────────────────────────────
Describe 'Write-TinyPxeConfig' {
    BeforeAll {
        # Dot-source with default (Lan) mode.
        . $script:FallbackPath
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
        Mock Set-Content     {}
        Mock Get-Content     { '' }
    }

    BeforeEach {
        # Default: config file does not exist (fresh).
        Mock Test-Path { $false }
    }

    It 'calls Set-Content exactly once on a fresh system (Lan mode)' {
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 1 -Scope It
    }

    It 'writes ProxyDHCP=1 for Lan mode' {
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 1 -Scope It -ParameterFilter {
            $Value -contains 'ProxyDHCP=1'
        }
    }

    It 'writes the Lan mode marker in the config content' {
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 1 -Scope It -ParameterFilter {
            ($Value -join "`n") -match 'PXEForge-Mode=Lan'
        }
    }

    It 'writes TftpRoot from config (no hardcoded path)' {
        $script:ExpectedRoot = $script:Config.TinyPxe.TftpRoot
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 1 -Scope It -ParameterFilter {
            ($Value -join "`n") -match [regex]::Escape($script:ExpectedRoot)
        }
    }

    It 'skips Set-Content when config file already contains Lan mode marker (idempotency)' {
        Mock Test-Path   { $true }
        Mock Get-Content { "ProxyDHCP=1`n; PXEForge-Mode=Lan" }
        Write-TinyPxeConfig
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 0 -Scope It
    }

    It 'rewrites config when file exists but contains a different mode marker' {
        Mock Test-Path   { $true }
        # File was written for Field mode; now running in Lan mode.
        Mock Get-Content { "ProxyDHCP=0`n; PXEForge-Mode=Field" }
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 1 -Scope It
    }
}

# ── Write-TinyPxeConfig — Field mode ─────────────────────────────────────────
Describe 'Write-TinyPxeConfig — Field mode' {
    BeforeAll {
        # Dot-source explicitly with Field mode so $Mode is 'Field' in scope.
        . $script:FallbackPath -Mode 'Field'
        Mock Write-Host      {}
        Mock Add-Content     {}
        Mock Test-IsElevated { $true }
        Mock Set-Content     {}
        Mock Get-Content     { '' }
    }

    BeforeEach {
        Mock Test-Path { $false }
    }

    It 'writes ProxyDHCP=0 for Field mode' {
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 1 -Scope It -ParameterFilter {
            $Value -contains 'ProxyDHCP=0'
        }
    }

    It 'writes the Field mode marker in the config content' {
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 1 -Scope It -ParameterFilter {
            ($Value -join "`n") -match 'PXEForge-Mode=Field'
        }
    }

    It 'skips Set-Content when config file already contains Field mode marker (idempotency)' {
        Mock Test-Path   { $true }
        Mock Get-Content { "ProxyDHCP=0`n; PXEForge-Mode=Field" }
        Write-TinyPxeConfig
        Write-TinyPxeConfig
        Should -Invoke Set-Content -Exactly 0 -Scope It
    }
}

# ── Install-PxeFallback ───────────────────────────────────────────────────────
Describe 'Install-PxeFallback' {
    BeforeAll {
        . $script:FallbackPath
        Mock Write-Host          {}
        Mock Add-Content         {}
        Mock Test-IsElevated     { $true }
        # Mock the orchestrated sub-functions so they don't exercise their own mocks here.
        Mock Copy-SecureBootFiles {}
        Mock New-BcdStore         {}
        Mock Write-TinyPxeConfig  {}
        Mock New-Service           {}
    }

    BeforeEach {
        # Default: service does not yet exist.
        Mock Get-Service {}
    }

    It 'calls Copy-SecureBootFiles exactly once' {
        Install-PxeFallback
        Should -Invoke Copy-SecureBootFiles -Exactly 1 -Scope It
    }

    It 'calls New-BcdStore exactly once' {
        Install-PxeFallback
        Should -Invoke New-BcdStore -Exactly 1 -Scope It
    }

    It 'calls Write-TinyPxeConfig exactly once' {
        Install-PxeFallback
        Should -Invoke Write-TinyPxeConfig -Exactly 1 -Scope It
    }

    It 'calls New-Service exactly once when service does not exist' {
        Install-PxeFallback
        Should -Invoke New-Service -Exactly 1 -Scope It
    }

    It 'calls Get-Service exactly once to check for an existing registration' {
        Install-PxeFallback
        Should -Invoke Get-Service -Exactly 1 -Scope It
    }

    It 'does not call New-Service when service is already registered (idempotency)' {
        Mock Get-Service { [PSCustomObject]@{ Name = $script:Config.TinyPxe.ServiceName } }
        Install-PxeFallback
        Install-PxeFallback
        Should -Invoke New-Service -Exactly 0 -Scope It
    }

    It 'still calls each orchestration step even when the service already exists' {
        Mock Get-Service { [PSCustomObject]@{ Name = $script:Config.TinyPxe.ServiceName } }
        Install-PxeFallback
        Should -Invoke Copy-SecureBootFiles -Exactly 1 -Scope It
        Should -Invoke New-BcdStore         -Exactly 1 -Scope It
        Should -Invoke Write-TinyPxeConfig  -Exactly 1 -Scope It
    }
}
