# PXEForge — Build Contract

Standalone PXE imaging appliance automation for a Windows 10/11 Pro host serving
SmartDeploy SmartPE via iVentoy. This repo builds the **automation around the box**
(setup, image sync, validation) — never the box itself during the loop.

## Council Loop Protocol

Three roles per iteration:

1. **Arbiter** (this session — Opus): reads loop-state.json, picks the next work item
   from the active milestone, dispatches the Engineer, then dispatches the Realist on
   the resulting diff. Merges only when both gates pass. Updates loop-state.json and
   appends to docs/loop-journal.md.
2. **Engineer** (subagent, Sonnet): implements exactly one work item. Writes code +
   matching Pester tests. No scope creep.
3. **Realist** (subagent, Sonnet): reviews `git diff` against this contract. Verdict:
   APPROVE or REJECT with specific line-level reasons. Checks especially for
   host-mutation during tests, missing mocks, hardcoded config, and scope drift.

Arbiter merge checklist (all required):
- [ ] `Invoke-Pester -CI` green
- [ ] `Invoke-ScriptAnalyzer -Path src -Recurse -Severity Error` returns nothing
- [ ] Realist verdict is APPROVE
- [ ] Diff touches only files owned by the current milestone
- [ ] Commit message: `M<n>: <work item> [council-approved]`

## Hard Rules

- **NEVER execute host-mutating commands during the loop.** All of these are
  mocked in tests, never run: `New-SmbShare`, `Remove-SmbShare`, `New-LocalUser`,
  `New-NetFirewallRule`, `netsh`, `sc.exe`, `powercfg`, `icacls`, service
  install/start, anything writing outside the repo tree. A PreToolUse hook enforces
  this; do not attempt to bypass it.
- All configuration lives in `src/config.psd1`. Zero hardcoded IPs, paths, ports,
  or account names in any script.
- Every script: PS 5.1 compatible, `Set-StrictMode -Version Latest`,
  `$ErrorActionPreference = 'Stop'`, `[CmdletBinding(SupportsShouldProcess)]` on
  state-changing scripts, dual-channel Write-Log, exit codes 0/1/2/3/4
  (success/failure/bad input/missing dep/not elevated).
- setup.ps1 must be idempotent: run twice → identical end state, second run logs
  "already configured" skips, exit 0.
- Pester 5 syntax only. Every mock asserts call count where behavior matters.

## Configuration Defaults (config.psd1)

- DhcpMode: `ExternalNet` (LAN mode, UDM Pro Max keeps DHCP). `-Mode Field`
  switches to `DHCPServer` (isolated switch, iVentoy hands out IPs).
- SharePath: `D:\SDShare`, service account `sddeploy` (read-only SMB + NTFS).
- iVentoy: v1.0.37, install root `C:\iVentoy`, ISO dir `C:\iVentoy\iso`,
  ports UDP 67-69, TCP 16000 (HTTP), TCP 26000 (UI, loopback-only firewall rule).
- SyncSource: `\\argyle-unraid\SmartDeploy` → robocopy mirror of Images\ and
  Platform Packs\ into SharePath. /MIR is destructive on the destination —
  sync-images.ps1 must require -Confirm or -Force for the first mirror.

## Milestones

| M | Deliverable | Gate |
|---|-------------|------|
| M1 | config.psd1 complete + setup.ps1 skeleton (params, elevation check, logging, preflight, empty task functions) | Pester + PSSA |
| M2 | setup.ps1 full implementation: share + ACLs, sddeploy account, firewall rules, powercfg, iVentoy extract + service registration | Mocked Pester incl. idempotency test (invoke functions twice against mocked state) |
| M3 | sync-images.ps1 + validate.ps1 (ports listening, ACL audit, service state, exactly one ISO present, share reachable) | Mocked Pester |
| M4 | Tiny PXE Server fallback module (Secure-Boot-safe: bootmgfw.efi + BCD chain). Do NOT start before M3 is merged. | Pester |
| M5 | **User documentation** — `docs/user-guide.md` written for an operator who has never seen this repo. Required sections: 1) Prerequisites (OS, D: volume, iVentoy 1.0.37 zip, SmartDeploy ISO media); 2) Install (extract, git, run setup.ps1 step-by-step with expected output); 3) Setup (LAN vs Field mode, when to use each, exact commands); 4) Configure (every config.psd1 key: purpose, default, when to change it; every script parameter with an example invocation); 5) First deployment walkthrough (ISO placement, Secure Boot, PXE boot, SmartPE); 6) Troubleshooting (no PXE offer, share unreachable, service won't start, port conflicts); 7) Maintenance (ISO regen after console upgrades, image sync). Exact commands with real paths throughout — no "navigate to" hand-waving. | Doc-coverage test (every config.psd1 key and every script param appears in the guide) + Realist review |
| M6 | **Manual — human only.** Brian follows docs/user-guide.md verbatim on the Pro box, PXE-boots a test laptop. Any step where the guide was unclear or wrong is itself a finding. The loop stops at M5 and writes `AWAITING_HUMAN` to loop-state.json. | Human sign-off |

## Loop State

`loop-state.json` at repo root: `{ "milestone": "M1", "workItem": "...", "iteration": 0, "status": "active|blocked|AWAITING_HUMAN" }`
Stop immediately if a file named `STOP` exists at repo root.

## Model Roles

- Arbiter: `claude-opus-4-8` (pinned in .claude/settings.json — never pass --model on the CLI, it overrides this)
- Engineer / Realist subagents: `claude-sonnet-4-6` (pinned in agent frontmatter)
