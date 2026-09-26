# PXEForge Runbook

## Start the loop
```powershell
cd C:\Users\Brian\Documents\PXEForge
.\run-loop.ps1 -MaxIterations 25
```
Stop it anytime: `New-Item STOP` at repo root, or Ctrl+C the watchdog.

## After M5 completes (loop writes AWAITING_HUMAN)
1. Follow docs/user-guide.md verbatim — unclear or wrong steps are findings too.
2. Media Wizard → ISO boot media → drop ISO in the real, version-coupled
   directory `C:\iVentoy\iventoy-<version>\iso\` (not `C:\iVentoy\iso` —
   that's a fallback default; see docs/user-guide.md Prerequisites). One or
   more ISOs is fine.
3. `.\src\validate.ps1`
4. Test laptop: PXE boot → SmartPE → unattended deploy. Test with the
   laptop's real Secure Boot setting (do not turn it OFF for the test —
   turning it off proves nothing about whether Secure Boot itself would
   have blocked the boot in normal use).
5. Log findings as issues in loop-journal.md; restart loop if fixes needed.

## Recurring
- After every SmartDeploy console upgrade: regenerate ISO, replace in iso\.
- After image refresh on Unraid: `.\src\sync-images.ps1`.
