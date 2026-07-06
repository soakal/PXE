# PreToolUse hook — blocks host-mutating commands during the council loop.
# Claude Code passes tool input as JSON on stdin. Exit 2 = block (stderr shown to model).
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }
$cmd = $payload.tool_input.command
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

$denyPatterns = @(
    'New-SmbShare', 'Remove-SmbShare', 'Grant-SmbShareAccess',
    'New-LocalUser', 'Remove-LocalUser', 'Add-LocalGroupMember',
    'New-NetFirewallRule', 'Remove-NetFirewallRule',
    '\bnetsh\b', '\bsc\.exe\b', '\bsc\s+(create|delete|config)\b',
    '\bpowercfg\b', '\bicacls\b',
    'New-Service', 'Set-Service', 'Start-Service', 'Stop-Service',
    'Remove-Item\s+.*-Recurse\s+.*(C:\\(?!Users\\Brian\\Documents\\PXEForge)|D:\\)',
    '\breg(\.exe)?\s+(add|delete)\b', 'Set-ItemProperty\s+.*HKLM',
    '\bshutdown\b', 'Restart-Computer'
)

foreach ($p in $denyPatterns) {
    if ($cmd -match $p) {
        [Console]::Error.WriteLine("BLOCKED by PXEForge contract: command matches deny pattern '$p'. Host mutation is forbidden during the loop - mock it in Pester instead. See CLAUDE.md Hard Rules.")
        exit 2
    }
}
exit 0
