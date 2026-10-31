function Import-SayedCustomModules {
    $roots = @($script:Settings.CustomModulePaths) + @(
        (Join-Path $script:Settings.DropboxHome 'Personal/PcSettings/Powershell/CustomModules')
        (Join-Path $script:Settings.CodeHome 'pshelpers')
        (Join-Path $script:Settings.CodeHome 'sayed-tools/powershell')
        (Join-Path $script:Settings.CodeHome 'nuget-powershell')
        $script:Settings.CodeHome
    )
    foreach ($name in $script:Settings.CustomModuleNames) {
        $moduleName = $name
        Invoke-SayedProfileStep "Module:$name" {
            $candidate = $null
            foreach ($root in $roots) {
                $path = Join-Path $root "$moduleName.psm1"
                if (Test-Path -LiteralPath $path -PathType Leaf) { $candidate = $path; break }
            }
            if (-not $candidate) { throw "Optional module '$moduleName' was not found." }
            if (-not (Get-Module | Where-Object Path -EQ $candidate)) {
                Import-Module -Name $candidate -Global -DisableNameChecking -ErrorAction Stop
            }
        }
    }
}

function Get-SayedProfileAlias {
    <#
    .SYNOPSIS
    Shows the aliases defined by this profile and the modules it loads.
    #>
    [CmdletBinding()]
    param()

    $modules = @('Sayed.Profile', 'sayed-tools')
    if ($script:Settings) { $modules += $script:Settings.CustomModuleNames }
    Get-Alias | Where-Object ModuleName -In $modules | Sort-Object Name |
        Select-Object Name, Definition, @{ Name = 'Module'; Expression = { $_.ModuleName } } |
        Format-Table -AutoSize -Wrap
}

function Initialize-SayedToolAliases {
    Set-Alias -Name smc -Value Start-MyClaude -Scope Global
    Set-Alias -Name imc -Value Init-MyClaudeProject -Scope Global
    Set-Alias -Name nmf -Value New-MyClaudeFeature -Scope Global
    Set-Alias -Name cdcp -Value Enter-MyClaudeProjects -Scope Global
    if (-not $IsWindows) { return }
    $code = $script:Settings.CodeHome
    $kdiff = @((Get-Command kdiff3.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source))
    foreach ($root in @("$env:LOCALAPPDATA/Programs", "$env:USERPROFILE/AppData/Local/Programs", $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) { $kdiff += Join-Path $root 'KDiff3/bin/kdiff3.exe'; $kdiff += Join-Path $root 'KDiff3/kdiff3.exe' }
    }
    Add-AliasForTool @(
        @{ alias = @('sef', 'Search-EverythingFiles'); path = @(Join-Path $script:ModuleRoot '../file-search/Search-EverythingFiles.ps1') }
        @{ alias = 'buildAhk'; path = @(Join-Path $code 'autohotkeyscripts/visual-studio/2024.04.16.build.demo.ahk') }
        @{ alias = 'ps99Gui'; path = @(Join-Path $code 'autohotkeyscripts/ps99/gui.ahk') }
        @{ alias = 'np'; path = @("$env:ProgramFiles/Notepad++/notepad++.exe") }
        @{ alias = 'p4merge'; path = @("$env:ProgramFiles/Perforce/p4merge.exe") }
        @{ alias = 'kdiff'; path = @($kdiff | Where-Object { $_ }) }
    )
}
