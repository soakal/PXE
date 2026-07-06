# PXEForge Operator Guide

Standalone PXE imaging appliance automation for a Windows 10/11 Pro host.  
Serves SmartDeploy SmartPE via iVentoy. This guide covers a first-time install
through a successful PXE boot of a target laptop.

---

## Prerequisites

Meet every item on this list **before** running any script.

### Operating System

- Windows 10 version 1809 (OS build 17763) or later, or Windows 11 Pro.
  The setup preflight checks the build number and exits 2 if it is too old.
- PowerShell 5.1 (ships with Windows 10/11 — no separate install needed).
- Administrator rights. Every script in this repo must be run from an
  elevated PowerShell session ("Run as Administrator"). Scripts exit 4
  if elevation is missing.

### Storage

- A **D: data volume** must be present and formatted. The default share root
  is `D:\SDShare`. If D: is absent, setup exits 3 (missing dependency).
- **Site-specific note:** On the work PC, `C:` is the OS drive and `D:` is
  the data drive. SmartDeploy data is already stored in `D:\SmartDeploy`.
  See the Configure section for the decision on whether to point
  `Share.Path` at `D:\SmartDeploy` directly or keep a separate `D:\SDShare`
  mirror destination.

### iVentoy 1.0.37

Download the 64-bit iVentoy zip for Windows. The file must be placed at
this exact path before running `setup.ps1`:

```
C:\ProgramData\PXEForge\iventoy_64.zip
```

This is the `IVentoy.ZipPath` value from `src\config.psd1`. If the file is
missing when setup runs, setup logs a warning and skips iVentoy extraction
(exit 0 — not fatal), but the iVentoy service will not be installed.

### SmartDeploy SmartPE ISO

You need a SmartPE ISO generated from the SmartDeploy console. Exactly one
ISO must be placed in `C:\iVentoy\iso` (the `IVentoy.IsoDir`) before
`validate.ps1` will pass its ISO-count check.

### TinyPXE Server (fallback path only)

Skip this if you plan to use iVentoy exclusively — the normal path for most
deployments. This prerequisite applies only when iVentoy's DHCP cannot
coexist with your network, or when Secure Boot rejects iVentoy's boot chain.

TinyPXE Server is a lightweight TFTP/DHCP server by Erwan Labalec. Download
the TinyPXE Server zip from the official site at erwan.labalec.fr/tinypxe,
then extract it to `C:\TinyPXE` before running `pxe-fallback.ps1`:

```powershell
Expand-Archive -Path "$env:USERPROFILE\Downloads\tinypxe.zip" `
    -DestinationPath 'C:\TinyPXE' -Force
Test-Path 'C:\TinyPXE\pxesrv.exe'   # must return True before running pxe-fallback.ps1
```

`pxe-fallback.ps1` registers a Windows service pointing at
`C:\TinyPXE\pxesrv.exe`. If that file is absent when the script runs,
the `New-Service` call will fail with a "binary path not found" error.

### Network

- LAN mode (default): your existing DHCP server (e.g., a UDM Pro Max) continues
  to serve IPs. iVentoy runs in ExternalNet mode and does not conflict.
- Field mode: bring a dedicated staging switch. iVentoy will hand out IPs
  on the isolated network. No DHCP server on that switch.

---

## Install

### 1. Clone the repo

Open an elevated PowerShell prompt, then:

```powershell
git clone https://github.com/soakal/PXE.git C:\PXEForge
```

Files land under `C:\PXEForge\`. The two directories you use directly are
`C:\PXEForge\src\` (scripts and config) and `C:\PXEForge\docs\` (this guide).

### 2. Place the iVentoy zip

Before running setup, copy the iVentoy 1.0.37 zip to:

```
C:\ProgramData\PXEForge\iventoy_64.zip
```

Create the `C:\ProgramData\PXEForge\` folder if it does not exist:

```powershell
New-Item -Path 'C:\ProgramData\PXEForge' -ItemType Directory -Force
```

### 3. Run setup.ps1

From an **elevated** PowerShell prompt:

```powershell
Set-Location C:\PXEForge\src
.\setup.ps1
```

This is the LAN-mode default. For Field mode see the Setup section.

#### Expected console output (first run)

```
[2026-07-06 09:15:00] [INFO] === PXEForge setup v0.1.0 started (Mode: Lan) ===
[2026-07-06 09:15:00] [INFO] Checking prerequisites...
[2026-07-06 09:15:00] [INFO] Elevation confirmed.
[2026-07-06 09:15:00] [INFO] PowerShell 5.1 — satisfied.
[2026-07-06 09:15:00] [INFO] OS build 22621 — supported.
[2026-07-06 09:15:00] [INFO] Data volume D: present.
[2026-07-06 09:15:00] [INFO] iVentoy installer found at 'C:\ProgramData\PXEForge\iventoy_64.zip'.
[2026-07-06 09:15:00] [SUCCESS] All prerequisites satisfied.
[2026-07-06 09:15:01] [INFO] Service account 'sddeploy' created.
[2026-07-06 09:15:01] [INFO] Created directory 'D:\SDShare'.
[2026-07-06 09:15:01] [INFO] Created subdirectory 'D:\SDShare\Images'.
[2026-07-06 09:15:01] [INFO] Created subdirectory 'D:\SDShare\Platform Packs'.
[2026-07-06 09:15:01] [INFO] Created subdirectory 'D:\SDShare\Answer Files'.
[2026-07-06 09:15:01] [INFO] SMB share 'SDShare' created (ReadAccess: sddeploy).
[2026-07-06 09:15:01] [INFO] NTFS ACL applied: 'sddeploy' ReadAndExecute on 'D:\SDShare'.
[2026-07-06 09:15:02] [INFO] Firewall rule 'PXEForge-UDP-67' created.
[2026-07-06 09:15:02] [INFO] Firewall rule 'PXEForge-UDP-68' created.
[2026-07-06 09:15:02] [INFO] Firewall rule 'PXEForge-UDP-69' created.
[2026-07-06 09:15:02] [INFO] Firewall rule 'PXEForge-TCP-16000' created.
[2026-07-06 09:15:02] [INFO] Firewall rule 'PXEForge-TCP-26000-loopback' created (loopback-only).
[2026-07-06 09:15:02] [INFO] AC standby disabled (timeout=0).
[2026-07-06 09:15:02] [INFO] DC standby disabled (timeout=0).
[2026-07-06 09:15:02] [INFO] Hibernate disabled.
[2026-07-06 09:15:03] [INFO] iVentoy extracted to 'C:\iVentoy'.
[2026-07-06 09:15:03] [WARN] iVentoy config.dat not found at 'C:\iVentoy\iventoy-1.0.37\data\config.dat'. Run iVentoy interactively once (elevated): launch iVentoy_64.exe, set Server IP, IP pool, DHCP mode (ProxyNet), UEFI boot file (snp.efi), click Start to confirm RUNNING, then close. This creates data\config.dat. Re-run setup.ps1 after that.
[2026-07-06 09:15:03] [SUCCESS] === Completed successfully ===
```

`setup.ps1` exits 0 even when service registration is skipped — only the
`data\config.dat` precondition determines whether the service is registered.
After running iVentoy interactively (see
[iVentoy auto-start on boot](#iventoy-auto-start-on-boot) in the Setup section),
re-run `setup.ps1` to register the service:

```
[2026-07-06 09:16:00] [INFO] === PXEForge setup v0.1.0 started (Mode: Lan) ===
...
[2026-07-06 09:16:00] [INFO] iVentoy service 'iVentoy' already installed — skipping.
```

Or on the second invocation before any service has been registered but after
`config.dat` exists:

```
[2026-07-06 09:16:00] [INFO] iVentoy install root 'C:\iVentoy' already populated — skipping extraction.
[2026-07-06 09:16:00] [INFO] DhcpMode configured as 'ExternalNet' (informational) — effective mode is read from config.dat by the service at startup.
[2026-07-06 09:16:00] [INFO] iVentoy service 'iVentoy' registered (-Service -R, start=Automatic).
[2026-07-06 09:16:00] [SUCCESS] === Completed successfully ===
```

#### Expected output (idempotent re-run)

Running `setup.ps1` a second time is safe. Every task that is already
configured logs "already configured — skipping" and exits 0:

```
[2026-07-06 09:20:00] [INFO] === PXEForge setup v0.1.0 started (Mode: Lan) ===
[2026-07-06 09:20:00] [INFO] Checking prerequisites...
[2026-07-06 09:20:00] [INFO] Elevation confirmed.
...
[2026-07-06 09:20:00] [SUCCESS] All prerequisites satisfied.
[2026-07-06 09:20:00] [INFO] 'sddeploy' service account already configured — skipping.
[2026-07-06 09:20:00] [INFO] Directory 'D:\SDShare' already exists — skipping.
[2026-07-06 09:20:00] [INFO] SMB share 'SDShare' already configured — skipping.
[2026-07-06 09:20:00] [INFO] NTFS ACL already configured — skipping.
[2026-07-06 09:20:00] [INFO] Firewall rule 'PXEForge-UDP-67' already exists — skipping.
...
[2026-07-06 09:20:00] [INFO] Sleep already disabled — skipping.
[2026-07-06 09:20:00] [INFO] iVentoy service 'iVentoy' already installed — skipping.
[2026-07-06 09:20:00] [SUCCESS] === Completed successfully ===
```

### Exit codes

All scripts use these exit codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Runtime failure |
| 2 | Bad input (wrong param value or bad config) |
| 3 | Missing dependency (e.g., D: drive absent) |
| 4 | Not elevated (not running as Administrator) |

### Log files

Every run writes a timestamped log to `C:\ProgramData\PXEForge\Logs\`.
File names follow the pattern `setup-20260706-091500.log`. The same
`[yyyy-MM-dd HH:mm:ss] [LEVEL] message` format is written to both the
console and the log file.

---

## Setup

### LAN mode (default)

Use LAN mode on your normal office or home network where an existing DHCP
server (such as a UDM Pro Max) is already handing out IPs. iVentoy runs
in **ProxyNet** DHCP mode (configured interactively — see
[iVentoy auto-start on boot](#iventoy-auto-start-on-boot) below) with
UEFI boot file `snp.efi`. The `-Mode Lan` flag is informational; it is
logged but does not control the service binary flags or the iVentoy DHCP
mode, which are stored in `C:\iVentoy\iventoy-1.0.37\data\config.dat`.

```powershell
# From an elevated PowerShell prompt in C:\PXEForge\src\:
.\setup.ps1
# or explicitly:
.\setup.ps1 -Mode Lan
```

### Field mode

Use Field mode when you are deploying on an isolated staging switch with
no external DHCP server. iVentoy is configured for `DHCPServer` mode via
the iVentoy GUI (saved to `data\config.dat`) and hands out IP addresses
on that isolated network. The `-Mode Field` flag is informational.

```powershell
.\setup.ps1 -Mode Field
```

If iVentoy is already installed (e.g., you re-run setup.ps1),
the service registration is skipped (idempotent). The effective iVentoy DHCP
mode and boot file come from `data\config.dat` set during interactive setup —
not from the `-Mode` parameter. To change the DHCP mode, re-run iVentoy
interactively, update the settings, restart the service.

### Choosing between LAN and Field

| Scenario | Mode |
|----------|------|
| Office or home network, UDM Pro Max or similar handles DHCP | Lan (default) |
| Dedicated imaging bench with its own switch, no upstream DHCP | Field |
| Isolated staging environment, on-site deployment with no network infrastructure | Field |

### iVentoy auto-start on boot

Before `setup.ps1` can register the iVentoy Windows service, iVentoy must be
run interactively at least once to create its configuration file at
`C:\iVentoy\iventoy-1.0.37\data\config.dat`. The vendor's `InstallService.bat`
has the same requirement — it aborts if `config.dat` is absent. If `setup.ps1`
reaches the service registration step and `config.dat` does not exist, it logs a
WARN and skips registration (exit 0 — not fatal). Re-run `setup.ps1` after the
interactive step below.

**Step 1 — Run iVentoy interactively (one-time):**

From an elevated PowerShell prompt:

```powershell
& 'C:\iVentoy\iventoy-1.0.37\iVentoy_64.exe'
```

In the iVentoy GUI:

1. Set **Server IP** to the host's static LAN IP address.
2. Set the **IP pool** to a range that does not overlap the LAN DHCP pool (the
   UDM Pro Max hands out its own range — use a non-overlapping range here).
3. Set **DHCP mode** to **ProxyNet** (the proven working mode for LAN operation
   with a UDM Pro Max or similar router handling existing DHCP).
4. Set **UEFI boot file** to `snp.efi`.
5. Click **Start** and confirm the status shows **RUNNING**.
6. Close the iVentoy window.

This writes all parameters to `C:\iVentoy\iventoy-1.0.37\data\config.dat`. The
service reads this file at startup and serves headless — no GUI window, starts
before login.

> **Note on DhcpMode config key:** `DhcpMode` in `config.psd1` defaults to
> `ExternalNet` and is informational only — it is logged during setup but NOT
> passed to the service binary. The service always registers with flags
> `-Service -R` (per vendor `InstallService.bat`). Set the actual DHCP mode
> (ProxyNet for LAN) in the iVentoy GUI, not via `-Mode`.

**Step 2 — Register the service:**

After `config.dat` exists, re-run `setup.ps1` from an elevated prompt:

```powershell
Set-Location C:\PXEForge\src
.\setup.ps1
```

`setup.ps1` detects `config.dat`, registers the service with vendor-correct flags
(`"C:\iVentoy\iventoy-1.0.37\iVentoy_64.exe" -Service -R`, `start=Automatic`),
and the service starts automatically at boot before login with no window.

Alternatively, use the vendor's `InstallService.bat` directly (elevated):

```powershell
& 'C:\iVentoy\iventoy-1.0.37\InstallService.bat'
```

**Step 3 — Verify after reboot:**

```powershell
# Confirm service is running:
Get-Service iVentoy

# Confirm ports are active:
Get-NetUDPEndpoint -LocalPort 67,69 -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 16000 -State Listen

# Run full health validation:
Set-Location C:\PXEForge\src
.\validate.ps1
```

After reboot the `iVentoy` service shows `Running`. UDP 67/69 and TCP 16000
should have active listeners. TCP 26000 (management UI) is idle unless the
GUI is open — that is normal.

> **iVentoy version upgrade:** A version upgrade installs a new
> `iventoy-<ver>\` subfolder. The old service registration points at the old
> exe path and is no longer valid. Re-run the interactive step and re-run
> `setup.ps1` (after removing the old service: `sc.exe delete iVentoy`) to
> register the new path.

---

## Configure

### config.psd1 keys

All configuration lives in `C:\PXEForge\src\config.psd1`. Edit this file
before your first run if any default does not match your environment.
**Never hardcode values in scripts** — the scripts read exclusively from
this file.

#### IVentoy section

| Key | Purpose | Default | When to change |
|-----|---------|---------|----------------|
| `Version` | iVentoy version string (informational, used in log warnings) | `1.0.37` | Only when upgrading iVentoy |
| `InstallRoot` | Directory iVentoy is extracted into | `C:\iVentoy` | If you need iVentoy on a different drive |
| `IsoDir` | Directory iVentoy scans for ISOs to serve | `C:\iVentoy\iso` | If you change InstallRoot |
| `ZipPath` | Full path where setup expects the downloaded iVentoy zip | `C:\ProgramData\PXEForge\iventoy_64.zip` | If you store the zip elsewhere; must match your actual download location |
| `HttpPort` | TCP port for iVentoy's HTTP API | `16000` | If another service binds 16000 |
| `UiPort` | TCP port for iVentoy's management UI (loopback-only firewall rule) | `26000` | If another service binds 26000 |
| `DhcpMode` | iVentoy DHCP mode (informational — logged during setup; the effective mode is saved in `data\config.dat` via the iVentoy GUI at interactive setup time) | `ExternalNet` | Does not control the service binary flags (which are always `-Service -R`). Change the actual DHCP mode via the iVentoy GUI: use ProxyNet for LAN operation, DHCPServer for an isolated Field switch. |
| `ServiceName` | Windows service name for iVentoy | `iVentoy` | Rarely — must match what iVentoy registers |

#### Share section

| Key | Purpose | Default | When to change |
|-----|---------|---------|----------------|
| `Path` | Filesystem path for the SMB share root | `D:\SDShare` | **Work PC (office):** if SmartDeploy data is already at `D:\SmartDeploy`, either point this to `D:\SmartDeploy` directly and skip the sync step, or leave the default and let robocopy mirror into `D:\SDShare`. See note below. |
| `Name` | SMB share name as it appears on the network | `SDShare` | If your imaging environment expects a different share name |
| `ServiceAccount` | Local Windows account with read-only SMB+NTFS access | `sddeploy` | If your security policy requires a different account name |
| `SubDirs` | Subdirectories created under `Path` | `Images`, `Platform Packs`, `Answer Files` | Add subdirectories if your SmartDeploy deployment requires them |

**Work PC note on `Share.Path`:** At home the source is on Unraid
(`\\SOURCE-SERVER\SmartDeploy`) and the data is mirrored locally into
`D:\SDShare`. At the office the data is already on D: (`D:\SmartDeploy`).
You have two options:

- Option A (recommended for the office): change `Share.Path` to
  `D:\SmartDeploy`. Setup creates the share pointing directly at the
  existing data. Skip `sync-images.ps1` — there is nothing to mirror.
- Option B: leave `Share.Path = D:\SDShare` and run `sync-images.ps1 -Force`
  to copy from... wherever the office source is. This makes sense only if
  you have a Sync.Source UNC path reachable at the office.

#### Sync section

| Key | Purpose | Default | When to change |
|-----|---------|---------|----------------|
| `Source` | UNC path of the SmartDeploy source share (robocopy origin) | `\\SOURCE-SERVER\SmartDeploy` | Change to the UNC path reachable from the office, or leave it if you chose Option A above and do not sync |
| `Include` | Folder names to sync from Source into Share.Path | `Images`, `Platform Packs` | Add folders if you need to mirror additional SmartDeploy directories |

#### Firewall section

| Key | Purpose | Default | When to change |
|-----|---------|---------|----------------|
| `RulePrefix` | Prefix for all Windows Firewall rule names created by setup | `PXEForge` | If your organization's naming policy requires a different prefix |
| `UdpPorts` | UDP ports opened inbound | `67`, `68`, `69` (DHCP/TFTP) | Only if your iVentoy version uses non-standard ports |
| `TcpPorts` | TCP ports opened inbound | `16000` (iVentoy HTTP API) | If you changed HttpPort |

#### LogDir

| Key | Purpose | Default | When to change |
|-----|---------|---------|----------------|
| `LogDir` | Directory where all scripts write timestamped log files | `C:\ProgramData\PXEForge\Logs` | If your policy requires logs on a different volume |

#### TinyPxe section

TinyPxe settings apply only when you run `pxe-fallback.ps1`. They are
not used by `setup.ps1`.

| Key | Purpose | Default | When to change |
|-----|---------|---------|----------------|
| `InstallRoot` | Root directory for TinyPXE Server | `C:\TinyPXE` | If you install TinyPXE on a different drive |
| `Exe` | Full path to pxesrv.exe | `C:\TinyPXE\pxesrv.exe` | If you change InstallRoot |
| `ConfigFile` | Full path to TinyPXE's config.ini | `C:\TinyPXE\config.ini` | If you change InstallRoot |
| `TftpRoot` | Directory TinyPXE serves files from over TFTP | `C:\TinyPXE\files` | If you change InstallRoot |
| `ServiceName` | Windows service name for TinyPXE | `TinyPXE` | Rarely |
| `BcdPath` | Path to the BCD store, relative to TftpRoot | `Boot\BCD` | Rarely — the BCD path must match what TinyPXE and bootmgfw.efi expect |
| `BootWim` | Path to boot.wim, relative to TftpRoot | `Boot\boot.wim` | When you update the SmartPE WIM |
| `SourceEfi` | Source of the Microsoft-signed bootmgfw.efi (copied from the host OS) | `C:\Windows\Boot\EFI\bootmgfw.efi` | Only if the host OS does not have this file at the standard location |
| `SourceSdi` | Source of boot.sdi (copied from the host OS) | `C:\Windows\Boot\DVD\EFI\en-US\boot.sdi` | Only if the host OS does not have this file at the standard location |
| `BootTimeout` | Seconds before the BCD boot manager auto-selects the default entry | `5` | Increase if technicians need more time at the boot menu |

### Script parameters

Every script accepts `-ConfigPath` and `-LogPath` to override the default
locations. This is useful for testing with an alternate config or for
redirecting logs.

#### setup.ps1

```powershell
# Parameters: -Mode, -ConfigPath, -LogPath

# LAN mode (default):
.\setup.ps1

# Field mode (iVentoy hands out IPs on an isolated switch):
.\setup.ps1 -Mode Field

# Preview what would happen without making any changes:
.\setup.ps1 -WhatIf

# Override config and log locations:
.\setup.ps1 -ConfigPath 'C:\PXEForge\src\config.psd1' -LogPath 'D:\Logs\setup-custom.log'
```

The `-Mode` parameter accepts `Lan` (default) or `Field`. It is informational —
logged during setup but no longer controls the iVentoy service binary flags (those
are always `-Service -R`, per vendor `InstallService.bat`). The effective DHCP mode
and UEFI boot file are set via the iVentoy GUI and stored in `data\config.dat`
(use ProxyNet + snp.efi for LAN operation).

#### sync-images.ps1

```powershell
# Parameters: -Force, -ConfigPath, -LogPath

# Mirror images from Sync.Source to Share.Path (destructive /MIR — requires -Force):
.\sync-images.ps1 -Force

# Preview what robocopy would do without running it:
.\sync-images.ps1 -WhatIf

# Override config path:
.\sync-images.ps1 -Force -ConfigPath 'C:\PXEForge\src\config.psd1'
```

The `-Force` switch is required to proceed past the ShouldProcess gate.
Without it (or without `-WhatIf`), the script logs a warning and exits 0
without touching any files. This is intentional — robocopy `/MIR` deletes
files from the destination that are absent from the source, so the
destructive operation must be explicit.

#### validate.ps1

```powershell
# Parameters: -ConfigPath, -LogPath

# Run all five health checks (must be elevated):
.\validate.ps1

# Override log path:
.\validate.ps1 -LogPath 'D:\Logs\validate-custom.log'
```

No `-Mode` or `-Force` parameter. validate.ps1 is read-only — it never
changes state. Exit 0 means all five checks passed; exit 1 means at least
one failed.

#### pxe-fallback.ps1

```powershell
# Parameters: -Mode, -ConfigPath, -LogPath

# LAN mode (proxy DHCP, coexists with existing network DHCP):
.\pxe-fallback.ps1

# Field mode (TinyPXE serves full DHCP on an isolated switch):
.\pxe-fallback.ps1 -Mode Field

# Preview without changes:
.\pxe-fallback.ps1 -WhatIf

# Override config path:
.\pxe-fallback.ps1 -Mode Field -ConfigPath 'C:\PXEForge\src\config.psd1'
```

`pxe-fallback.ps1` is the fallback path for environments where iVentoy
DHCP is unavailable. The `-Mode` parameter controls whether TinyPXE writes
`ProxyDHCP=1` (Lan) or `ProxyDHCP=0` (Field) into its `config.ini`.

---

## First deployment

### Step 1: Confirm setup is complete

Run validate.ps1 from an elevated prompt to confirm all five checks pass:

```powershell
Set-Location C:\PXEForge\src
.\validate.ps1
```

#### Expected console output (all checks passing)

```
[2026-07-06 09:25:00] [INFO] === PXEForge validate started ===
[2026-07-06 09:25:00] [SUCCESS] PASS: UDP 67 is listening.
[2026-07-06 09:25:00] [SUCCESS] PASS: UDP 68 is listening.
[2026-07-06 09:25:00] [SUCCESS] PASS: UDP 69 is listening.
[2026-07-06 09:25:00] [SUCCESS] PASS: TCP 16000 is listening.
[2026-07-06 09:25:00] [SUCCESS] PASS: ACL on 'D:\SDShare' has ReadAndExecute Allow for 'sddeploy'.
[2026-07-06 09:25:00] [SUCCESS] PASS: Service 'iVentoy' is Running.
[2026-07-06 09:25:00] [SUCCESS] PASS: Exactly 1 ISO present in 'C:\iVentoy\iso'.
[2026-07-06 09:25:00] [SUCCESS] PASS: SMB share 'SDShare' exists and path resolves.
[2026-07-06 09:25:00] [SUCCESS] === All checks PASSED ===
```

If any check fails, the failing line reads `[ERROR] FAIL: ...` instead, for example:

```
[2026-07-06 09:25:00] [ERROR] FAIL: UDP 67 is not listening.
```

`validate.ps1` exits 0 only when all five checks emit PASS lines and the
final banner reads `=== All checks PASSED ===`. Any `[ERROR] FAIL:` line
means the script exits 1 — see the Troubleshooting section for the fix.

The five checks are:

1. **Ports listening** — UDP 67, 68, 69 and TCP 16000 have active listeners.
2. **ACL audit** — `D:\SDShare` has a ReadAndExecute Allow ACE for `sddeploy`.
3. **Service running** — the `iVentoy` service exists and its status is Running.
4. **ISO present** — exactly one `.iso` file exists in `C:\iVentoy\iso`.
5. **Share reachable** — the `SDShare` SMB share exists and its path resolves.

Exit 0 means all checks passed and the appliance is ready. Exit 1 means
one or more checks failed — read the log in `C:\ProgramData\PXEForge\Logs\`
for FAIL lines and see the Troubleshooting section.

### Step 2: Place the SmartPE ISO

Place exactly one SmartPE ISO in:

```
C:\iVentoy\iso\
```

Keep exactly one ISO there. iVentoy will serve whichever file it finds.
`validate.ps1` enforces the one-ISO rule — if there are zero or more than
one ISO files, check 4 fails.

### Step 3: Start the iVentoy service

If the service is not already running (validate check 3 will catch this):

```powershell
Start-Service -Name 'iVentoy'
```

You can also open iVentoy's management UI at `http://127.0.0.1:26000` from
the host machine (the firewall rule for port 26000 is scoped to loopback only).

### Step 4: Secure Boot and the signed boot chain

iVentoy serves ISO images over HTTP. The target laptop's UEFI firmware
performs a PXE boot, fetches the bootloader over TFTP, and chainloads
into iVentoy's boot environment, which then presents the ISO menu.

If the target laptop has Secure Boot enabled, iVentoy must serve a
Microsoft-signed bootloader. iVentoy 1.0.37 includes a signed chain;
confirm Secure Boot is enabled or disabled in UEFI settings according to
your SmartDeploy environment's requirements.

If iVentoy's boot chain is rejected by Secure Boot, fall back to the
TinyPXE path (see Troubleshooting — Secure Boot rejecting the PXE bootloader).
Before going there, confirm TinyPXE Server is installed at
`C:\TinyPXE\pxesrv.exe` (see Prerequisites — TinyPXE Server). `pxe-fallback.ps1`
copies `bootmgfw.efi` from `C:\Windows\Boot\EFI\bootmgfw.efi` (a Microsoft-signed
binary that ships with Windows) and builds a BCD store pointing at
`boot.wim`. Since `bootmgfw.efi` is signed by Microsoft, Secure Boot
accepts it without any key enrollment. Note that the script stages the signed
boot files but not the SmartPE WIM — you must place `boot.wim` manually at
`C:\TinyPXE\files\Boot\boot.wim` before starting the TinyPXE service (the
full procedure is in the Troubleshooting section).

### Step 5: PXE-boot the target laptop

1. On the target laptop, enter UEFI settings (usually F2, Del, or F10 at
   POST) and confirm:
   - Boot mode: UEFI (not Legacy/CSM)
   - PXE/Network Boot: enabled
   - Secure Boot: enabled or disabled per your SmartDeploy guidance
2. Select "Network Boot" or "PXE Boot" from the boot menu (usually F12 at POST).
3. The laptop sends a DHCP Discover. In LAN mode your UDM Pro Max responds;
   iVentoy sees the PXE flag and offers the boot file. In Field mode
   iVentoy responds to the Discover directly.
4. iVentoy transfers the boot payload over TFTP/HTTP and the laptop boots
   into the iVentoy menu.
5. Select the SmartPE ISO from the menu. SmartPE loads and the SmartDeploy
   imaging wizard appears.

---

## Troubleshooting

### No PXE offer — target does not boot from network

**Symptom:** Target laptop times out waiting for a DHCP response or shows
"PXE-E32: TFTP open timeout."

**Cause and diagnostic:**

```powershell
# Check that iVentoy is running:
Get-Service -Name 'iVentoy'

# Check that UDP 67/68/69 are open in the firewall:
Get-NetFirewallRule -Name 'PXEForge-UDP-67','PXEForge-UDP-68','PXEForge-UDP-69' |
    Select-Object Name, Enabled, Action

# Check that something is listening on UDP 67:
Get-NetUDPEndpoint -LocalPort 67 -ErrorAction SilentlyContinue
```

**Fix:**

- If the `iVentoy` service is stopped: `Start-Service -Name 'iVentoy'`
- If firewall rules are missing: re-run `.\setup.ps1` (idempotent; it will
  recreate missing rules).
- If you are in LAN mode and the UDM Pro Max is also responding to the PXE
  request but providing no PXE boot file, confirm iVentoy is configured in
  **ProxyNet** mode with UEFI boot file **snp.efi** (the proven working
  configuration). The service binary path ends in `-Service -R`; the effective
  DHCP mode comes from `C:\iVentoy\iventoy-1.0.37\data\config.dat`. Verify the
  registered binary path:
  ```powershell
  Get-WmiObject Win32_Service -Filter "Name='iVentoy'" | Select-Object PathName
  ```
  To change the DHCP mode, re-run iVentoy interactively, update ProxyNet/snp.efi
  settings, click Start to confirm RUNNING, then restart the service.
- If you need iVentoy to be the sole DHCP server (isolated switch), configure
  `DHCPServer` mode in the iVentoy GUI (saved to `config.dat`), then restart the
  service. If reinstalling the service: `sc.exe delete iVentoy` then re-run
  `.\setup.ps1` (after creating a new `config.dat` via interactive setup).
- If iVentoy DHCP cannot coexist with your network, use the TinyPXE fallback:
  `.\pxe-fallback.ps1 -Mode Field`

### Share unreachable — SmartDeploy cannot see images

**Symptom:** SmartPE imaging wizard cannot find images on `\\<hostname>\SDShare`.

**Cause and diagnostic:**

```powershell
# Confirm the share exists:
Get-SmbShare -Name 'SDShare'

# Confirm sddeploy account exists:
Get-LocalUser -Name 'sddeploy'

# Confirm the NTFS ACL has sddeploy with read access:
(Get-Acl -Path 'D:\SDShare').Access |
    Where-Object { $_.IdentityReference -like '*sddeploy*' }

# From the target laptop (once it has an IP), test the share:
# In SmartPE open a command prompt and run:
# net use \\<pxeforge-host>\SDShare /user:sddeploy
```

**Fix:**

- If the share is missing: re-run `.\setup.ps1` (idempotent).
- If sddeploy account is missing: re-run `.\setup.ps1`.
- If images are absent from `D:\SDShare\Images\`: run
  `.\sync-images.ps1 -Force` (from the home network where
  `\\SOURCE-SERVER\SmartDeploy` is reachable), or copy images manually to
  `D:\SDShare\Images\`.
- If you changed `Share.Path` to `D:\SmartDeploy`: confirm the ACL on that
  path includes sddeploy ReadAndExecute.

### Service won't start — iVentoy or TinyPXE

**Symptom:** `Start-Service -Name 'iVentoy'` or `Start-Service -Name 'TinyPXE'`
throws an error or the service status remains Stopped.

**Diagnostic:**

```powershell
# Check service registration:
Get-Service -Name 'iVentoy'
Get-Service -Name 'TinyPXE'

# View the binary path registered:
Get-WmiObject Win32_Service -Filter "Name='iVentoy'" | Select-Object PathName
Get-WmiObject Win32_Service -Filter "Name='TinyPXE'" | Select-Object PathName

# Check Windows event log for service failure:
Get-EventLog -LogName System -Source 'Service Control Manager' -Newest 20 |
    Where-Object { $_.Message -like '*iVentoy*' -or $_.Message -like '*TinyPXE*' }
```

**Fix:**

- If the binary path does not exist (iVentoy was not extracted), confirm
  `C:\iVentoy\iventoy.exe` (or the exe found during extraction) is present.
  If missing, delete the service (`sc.exe delete iVentoy`) and re-run
  `.\setup.ps1` with the zip in place.
- If TinyPXE is not installed at `C:\TinyPXE\pxesrv.exe`, download the
  TinyPXE Server zip from erwan.labalec.fr/tinypxe (by Erwan Labalec) and
  extract it:
  ```powershell
  Expand-Archive -Path "$env:USERPROFILE\Downloads\tinypxe.zip" `
      -DestinationPath 'C:\TinyPXE' -Force
  Test-Path 'C:\TinyPXE\pxesrv.exe'   # must return True
  ```
  Then run `.\pxe-fallback.ps1`.
- If pxesrv.exe exists but the service does not start, check that
  `C:\TinyPXE\config.ini` was written (use `Get-Content C:\TinyPXE\config.ini`)
  and that the TftpRoot `C:\TinyPXE\files\` exists and contains `bootmgfw.efi`.

### Service installed but iVentoy not serving (only port 26000 active)

**Symptom:** `Get-Service iVentoy` shows Running but
`Get-NetTCPConnection -LocalPort 16000 -State Listen` returns nothing and UDP
67/69 have no listeners. Port 26000 may be active. `validate.ps1` reports FAIL
on port checks.

**Cause:** `data\config.dat` was saved while iVentoy was in a Stopped state,
or holds a stale Server IP that does not match the host's current NIC address.
The service starts but cannot bind to the configured IP.

**Fix:**

1. Re-run iVentoy interactively from an elevated prompt:
   ```powershell
   & 'C:\iVentoy\iventoy-1.0.37\iVentoy_64.exe'
   ```
2. Verify **Server IP** matches the host's current static LAN IP.
3. Confirm **DHCP mode** is **ProxyNet** and **UEFI boot file** is `snp.efi`.
4. Click **Start** and confirm **RUNNING**.
5. Close the GUI (this saves `config.dat`).
6. Restart the service:
   ```powershell
   Restart-Service -Name 'iVentoy'
   ```
7. Re-run validation:
   ```powershell
   Set-Location C:\PXEForge\src
   .\validate.ps1
   ```

If the service is not yet installed (setup.ps1 skipped registration because
`config.dat` was absent): complete the interactive step above to create
`config.dat`, then re-run `.\setup.ps1`.

### Port conflicts — 16000, 26000, 67-69 already in use

**Symptom:** iVentoy service starts but PXE does not work, or `validate.ps1`
reports FAIL on port checks.

**Diagnostic:**

```powershell
# Find what is binding UDP 67, 68, or 69:
Get-NetUDPEndpoint -LocalPort 67,68,69

# Find what is binding TCP 16000 or 26000:
Get-NetTCPConnection -LocalPort 16000,26000 -State Listen

# Map PIDs to process names:
Get-NetTCPConnection -LocalPort 16000 -State Listen |
    ForEach-Object { Get-Process -Id $_.OwningProcess }
```

**Fix:**

- UDP 67/68 conflict: another DHCP server is running on this host (e.g.,
  Windows DHCP Server role). Disable it or stop it before iVentoy can use
  those ports. In LAN mode iVentoy listens passively for PXE flags in
  DHCP traffic (ProxyNet mode), so a conflict here usually means iVentoy is
  configured to `DHCPServer` mode in `config.dat` when it should be `ProxyNet`.
  Re-run iVentoy interactively to correct the mode in `config.dat`, then
  restart the service.
- TCP 16000 conflict: change `IVentoy.HttpPort` in `config.psd1`, update the
  `Firewall.TcpPorts` list to match, and re-run `.\setup.ps1`.
- TCP 26000 conflict: change `IVentoy.UiPort` in `config.psd1` and re-run
  `.\setup.ps1`.

### Secure Boot rejecting the PXE bootloader

**Symptom:** Target boots from network, shows a Secure Boot violation or
simply reboots without presenting the iVentoy menu.

**Fix:** Use the TinyPXE fallback, which serves `bootmgfw.efi` — the
Microsoft-signed Windows boot manager, already present on the host at
`C:\Windows\Boot\EFI\bootmgfw.efi`. Because Microsoft's key is in every
UEFI Secure Boot trust database, no key enrollment is needed.

**Step 1 — Install TinyPXE Server** (skip if already done in Prerequisites):

Download the TinyPXE Server zip from erwan.labalec.fr/tinypxe (by Erwan
Labalec) and extract it:

```powershell
Expand-Archive -Path "$env:USERPROFILE\Downloads\tinypxe.zip" `
    -DestinationPath 'C:\TinyPXE' -Force
Test-Path 'C:\TinyPXE\pxesrv.exe'   # must return True
```

**Step 2 — Configure the fallback:**

```powershell
Set-Location C:\PXEForge\src
.\pxe-fallback.ps1 -Mode Field
```

This copies `bootmgfw.efi` and `boot.sdi` from the host Windows installation
into the TFTP root (`C:\TinyPXE\files\`; `boot.sdi` lands under `\Boot`),
builds the BCD store, writes
`C:\TinyPXE\config.ini`, and registers the TinyPXE Windows service. It does
NOT copy `boot.wim`.

**Step 3 — Stage the SmartPE WIM** (required — `pxe-fallback.ps1` does not do this):

The BCD store built by `pxe-fallback.ps1` directs the target to ramdisk-boot
from `\Boot\boot.wim` (relative to TFTP root `C:\TinyPXE\files\`). The
script stages the Microsoft-signed boot files (`bootmgfw.efi`, `boot.sdi`)
but not the operator-supplied WIM payload. Without `boot.wim` at that path,
the target chainloads `bootmgfw.efi`, reads the BCD, then fails to locate
the ramdisk image and presents a WinPE boot error.

Obtain a SmartPE `boot.wim` from the SmartDeploy console
(Deployments > Create Media > WIM / PXE boot file), then place it:

```powershell
# The Boot subdirectory is created by pxe-fallback.ps1; if you are staging
# boot.wim before running the script, create it manually:
New-Item -Path 'C:\TinyPXE\files\Boot' -ItemType Directory -Force | Out-Null
# Copy the exported SmartPE boot.wim:
Copy-Item -Path 'C:\path\to\exported\boot.wim' `
    -Destination 'C:\TinyPXE\files\Boot\boot.wim'
# Verify:
Test-Path 'C:\TinyPXE\files\Boot\boot.wim'   # must return True
```

**Step 4 — Start the service:**

```powershell
Start-Service -Name 'TinyPXE'
```

Then re-attempt PXE boot on the target.

---

## Maintenance

### Regenerate SmartPE after SmartDeploy console upgrades

When you upgrade the SmartDeploy console, the version of SmartPE on your
existing ISO may no longer match. Regenerate the ISO from the SmartDeploy
console (Deployments > Create Media > SmartPE ISO), then:

1. Delete the old ISO from `C:\iVentoy\iso\`.
2. Copy the new ISO into `C:\iVentoy\iso\`.
3. Confirm exactly one `.iso` file is present:
   ```powershell
   Get-ChildItem 'C:\iVentoy\iso' -Filter '*.iso'
   ```
4. Restart the iVentoy service so it picks up the new file:
   ```powershell
   Restart-Service -Name 'iVentoy'
   ```
5. Run `.\validate.ps1` to confirm ISO check passes (exit 0).

If you are using the TinyPXE fallback and updated the SmartPE WIM, copy
the new `boot.wim` to `C:\TinyPXE\files\Boot\boot.wim` and restart
`TinyPXE`:

```powershell
Restart-Service -Name 'TinyPXE'
```

### Refresh images from Unraid (home network only)

When SmartDeploy images or Platform Packs are updated on Unraid, sync
the local share:

```powershell
# From an elevated prompt on the home network (\\SOURCE-SERVER reachable):
Set-Location C:\PXEForge\src
.\sync-images.ps1 -Force
```

This runs `robocopy /MIR` for each folder listed in `Sync.Include`
(`Images` and `Platform Packs`). `/MIR` is destructive on the destination:
files present in `D:\SDShare\Images\` that are absent from
`\\SOURCE-SERVER\SmartDeploy\Images\` will be deleted. The `-Force` switch
is required precisely because of this destructive behavior — it cannot run
unattended without it.

After sync completes, run `.\validate.ps1` to confirm the share is still
reachable and the service is still running.

**At the office:** If `Share.Path` points directly at `D:\SmartDeploy`
(Option A from the Configure section), there is no sync step. Images are
already in place. Skip this step.

---

*Generated by the PXEForge council loop — M5 documentation milestone.*
