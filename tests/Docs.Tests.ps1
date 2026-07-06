#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# M5 gate: user-guide coverage. Skipped until the guide exists.

BeforeAll {
    $script:GuidePath  = Join-Path $PSScriptRoot '..\docs\user-guide.md'
    $script:ConfigPath = Join-Path $PSScriptRoot '..\src\config.psd1'
    $script:SrcDir     = Join-Path $PSScriptRoot '..\src'
}

Describe 'User guide coverage' -Skip:(-not (Test-Path (Join-Path $PSScriptRoot '..\docs\user-guide.md'))) {
    BeforeAll { $script:Guide = Get-Content $GuidePath -Raw }

    It 'documents every top-level and nested config.psd1 key' {
        $cfg = Import-PowerShellDataFile -Path $ConfigPath
        foreach ($section in $cfg.Keys) {
            $Guide | Should -Match ([regex]::Escape($section))
            if ($cfg[$section] -is [hashtable]) {
                foreach ($key in $cfg[$section].Keys) {
                    $Guide | Should -Match ([regex]::Escape($key))
                }
            }
        }
    }
    It 'documents every parameter of every src script' {
        Get-ChildItem $SrcDir -Filter *.ps1 | ForEach-Object {
            $tokens = $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
            $ast.ParamBlock.Parameters | ForEach-Object {
                $Guide | Should -Match ([regex]::Escape($_.Name.VariablePath.UserPath))
            }
        }
    }
    It 'contains all seven required sections' {
        foreach ($s in 'Prerequisites','Install','Setup','Configure','First deployment','Troubleshooting','Maintenance') {
            $Guide | Should -Match $s
        }
    }
}
