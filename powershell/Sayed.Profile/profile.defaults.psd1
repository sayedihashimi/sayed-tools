@{
    ThemeName = '1_shell'
    ThemePath = ''
    PredictionSource = 'HistoryAndPlugin'
    PredictionViewStyle = 'InlineView'
    MaximumHistoryCount = 10000
    EnablePrompt = $true
    EnableZoxide = $true
    EnableDotnetCompletions = $true
    EnableCustomModules = $true
    # Sets WEZTERM_CONFIG_FILE (Windows user variable) if it isn't already set.
    EnableWezTermConfig = $true
    # Empty means the repo's dotfiles/wezterm.lua.
    WezTermConfigPath = ''
    InitialDirectory = ''
    ExtraPaths = @()
    CustomModuleNames = @('sayedha-pshelpers', 'github-ps', 'nuget-powershell')
    CustomModulePaths = @()
}
