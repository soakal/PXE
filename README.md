# PXEForge

Council-loop-built automation for a standalone SmartDeploy PXE appliance
(iVentoy on Windows 10/11 Pro). Arbiter: Opus 4.8. Engineer/Realist: Sonnet 4.6.

## Bootstrap
```powershell
Expand-Archive pxeforge-bundle.zip -DestinationPath $env:USERPROFILE\Documents
cd $env:USERPROFILE\Documents\PXEForge
git init && git add -A && git commit -m "M0: scaffold [council-approved]"
.\run-loop.ps1 -MaxIterations 5 -Verbose   # supervised shakedown first
```
See docs/runbook.md for the full operating procedure and CLAUDE.md for the contract.
