#Requires -Version 5.1

<#
.SYNOPSIS
    Watchdog for the PXEForge council loop - drives unattended Claude Code iterations.

.DESCRIPTION
    Invokes claude.exe headless once per iteration with the Arbiter prompt. Stops on:
    STOP file at repo root, loop-state.json status of AWAITING_HUMAN or blocked,
    -MaxIterations reached, or repeated CLI failures. Model comes from
    .claude/settings.json - deliberately NOT passed via --model (CLI flag would
    override the Opus pin).

.PARAMETER MaxIterations
    Hard iteration ceiling. Default 25.

.PARAMETER FailureLimit
    Consecutive claude.exe non-zero exits before aborting. Default 3.

.EXAMPLE
    .\run-loop.ps1 -MaxIterations 25
.EXAMPLE
    .\run-loop.ps1 -MaxIterations 5 -Verbose   # short supervised shakedown run
.NOTES
    Author: Brian | Version: 1.0.0 | No elevation required (loop never mutates host).
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 200)]
    [int]$MaxIterations = 25,

    [ValidateRange(1, 10)]
    [int]$FailureLimit = 3,

    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $LogPath) {
    $LogPath = Join-Path $PSScriptRoot ("loop-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
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

function Test-Prerequisites {
    if (-not (Get-Command 'claude' -ErrorAction SilentlyContinue)) {
        throw 'claude CLI not found in PATH. Exit code 3.'
    }
    if (-not (Test-Path (Join-Path $PSScriptRoot 'CLAUDE.md'))) {
        throw 'CLAUDE.md missing - run from the PXEForge repo root.'
    }
}

function Get-LoopStatus {
    $statePath = Join-Path $PSScriptRoot 'loop-state.json'
    if (-not (Test-Path $statePath)) { return 'active' }
    try { (Get-Content $statePath -Raw | ConvertFrom-Json).status } catch { 'active' }
}

$arbiterPrompt = @'
You are the Arbiter. Read CLAUDE.md and loop-state.json. Execute exactly ONE council
iteration: dispatch the engineer subagent on the current work item, then the realist
subagent on the diff, run Invoke-Pester -CI and Invoke-ScriptAnalyzer, and merge only
if the full checklist passes. Update loop-state.json and append one entry to
docs/loop-journal.md. If the current milestone is complete, advance to the next.
If M5 completes, set status AWAITING_HUMAN and stop.
'@

try {
    Write-Log "=== PXEForge loop watchdog v1.0.0 started (max $MaxIterations iterations) ==="
    Test-Prerequisites
    Push-Location $PSScriptRoot

    $failures = 0
    for ($i = 1; $i -le $MaxIterations; $i++) {

        if (Test-Path (Join-Path $PSScriptRoot 'STOP')) {
            Write-Log 'STOP file found - halting.' 'WARN'; break
        }
        $status = Get-LoopStatus
        if ($status -in @('AWAITING_HUMAN', 'blocked')) {
            Write-Log "loop-state status is '$status' - halting for operator." 'SUCCESS'; break
        }

        Write-Log "-- Iteration $i / $MaxIterations --"
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & claude -p $arbiterPrompt --permission-mode acceptEdits 2>&1 |
            Tee-Object -FilePath $LogPath -Append | Out-Host
        $ErrorActionPreference = $prevEAP

        if ($LASTEXITCODE -ne 0) {
            $failures++
            Write-Log "claude exited $LASTEXITCODE (consecutive failures: $failures)" 'ERROR'
            if ($failures -ge $FailureLimit) { throw "Aborting after $FailureLimit consecutive CLI failures." }
            Start-Sleep -Seconds 30
        } else {
            $failures = 0
        }
    }

    Write-Log "=== Watchdog finished. Final status: $(Get-LoopStatus) ===" 'SUCCESS'
    exit 0

} catch {
    Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
    exit 1

} finally {
    Pop-Location -ErrorAction SilentlyContinue
}
