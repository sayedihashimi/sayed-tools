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
    InitialDirectory = ''
    ExtraPaths = @()
    CustomModuleNames = @('sayedha-pshelpers', 'github-ps', 'nuget-powershell')
    CustomModulePaths = @()
}
