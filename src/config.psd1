@{
    # ── PXE / iVentoy ─────────────────────────────────────
    IVentoy = @{
        Version     = '1.0.37'
        InstallRoot = 'C:\iVentoy'
        IsoDir      = 'C:\iVentoy\iso'
        # Operator must download iVentoy zip and place it here before running setup.ps1
        ZipPath     = 'C:\ProgramData\PXEForge\iventoy_64.zip'
        HttpPort    = 16000
        UiPort      = 26000          # firewall rule scoped to loopback only
        DhcpMode    = 'ExternalNet'  # LAN default; 'DHCPServer' for isolated field mode
        ServiceName = 'iVentoy'
    }

    # ── Image share ───────────────────────────────────────
    Share = @{
        Path           = 'D:\SDShare'
        Name           = 'SDShare'
        ServiceAccount = 'sddeploy'   # local, read-only SMB + NTFS
        SubDirs        = @('Images', 'Platform Packs', 'Answer Files')
    }

    # ── Image sync (Unraid → local share) ─────────────────
    Sync = @{
        Source  = '\\argyle-unraid\SmartDeploy'
        Include = @('Images', 'Platform Packs')
        # robocopy /MIR — destructive on destination; script must gate first run
    }

    # ── Firewall ──────────────────────────────────────────
    Firewall = @{
        RulePrefix = 'PXEForge'
        UdpPorts   = @(67, 68, 69)
        TcpPorts   = @(16000)
    }

    # ── Logging ───────────────────────────────────────────
    LogDir = 'C:\ProgramData\PXEForge\Logs'

    # ── TinyPXE fallback (M4) ─────────────────────────────
    # Used when iVentoy DHCP is unavailable (e.g. isolated staging switch).
    # Serves Microsoft-signed bootmgfw.efi over TFTP so Secure Boot is satisfied.
    TinyPxe = @{
        InstallRoot = 'C:\TinyPXE'
        Exe         = 'C:\TinyPXE\pxesrv.exe'
        ConfigFile  = 'C:\TinyPXE\config.ini'
        TftpRoot    = 'C:\TinyPXE\files'
        ServiceName = 'TinyPXE'
        BcdPath     = 'Boot\BCD'           # relative to TftpRoot
        BootWim     = 'Boot\boot.wim'      # relative to TftpRoot; ramdisk source
        SourceEfi   = 'C:\Windows\Boot\EFI\bootmgfw.efi'
        SourceSdi   = 'C:\Windows\Boot\DVD\EFI\en-US\boot.sdi'
        BootTimeout = 5                    # seconds; BCD bootmgr timeout
    }
}
