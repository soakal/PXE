# PXEForge Runbook

## Start the loop
```powershell
cd C:\Users\Brian\Documents\PXEForge
.\run-loop.ps1 -MaxIterations 25
```
Stop it anytime: `New-Item STOP` at repo root, or Ctrl+C the watchdog.

## After M5 completes (loop writes AWAITING_HUMAN)
1. Follow docs/user-guide.md verbatim — unclear or wrong steps are findings too.
2. Media Wizard → ISO boot media → drop ISO in C:\iVentoy\iso\ (keep exactly one).
3. `.\src\validate.ps1`
4. Test laptop: Secure Boot OFF → PXE boot → SmartPE → unattended deploy.
5. Log findings as issues in loop-journal.md; restart loop if fixes needed.

## Recurring
- After every SmartDeploy console upgrade: regenerate ISO, replace in iso\.
- After image refresh on Unraid: `.\src\sync-images.ps1`.
