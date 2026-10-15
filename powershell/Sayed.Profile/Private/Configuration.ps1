function Get-SayedProfileConfiguration {
    param([hashtable]$Overrides = @{}, [string]$ConfigurationPath)
    $settings = Import-PowerShellDataFile (Join-Path $script:ModuleRoot 'profile.defaults.psd1')
    $settings.CodeHome = Split-Path (Split-Path (Split-Path $script:ModuleRoot))
    if ($global:codehome) { $settings.CodeHome = $global:codehome }
    $settings.DropboxHome = if ($global:DropboxHome) { $global:DropboxHome } elseif ($IsWindows) { 'C:\data\Dropbox' } else { Join-Path $HOME 'data/Dropbox' }
    $settings.Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal
    if (-not $ConfigurationPath) { $ConfigurationPath = Join-Path $script:ModuleRoot 'profile.local.psd1' }
    if (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf) {
        $local = Import-PowerShellDataFile -LiteralPath $ConfigurationPath -ErrorAction Stop
        foreach ($key in $local.Keys) {
            if (-not $settings.ContainsKey($key)) { throw "Unknown profile setting '$key'." }
            $settings[$key] = $local[$key]
        }
    }
    foreach ($key in $Overrides.Keys) {
        if (-not $settings.ContainsKey($key)) { throw "Unknown profile setting '$key'." }
        $settings[$key] = $Overrides[$key]
    }
    if ($settings.PredictionViewStyle -notin @('InlineView', 'ListView')) { throw 'Invalid PredictionViewStyle.' }
    if ($settings.PredictionSource -notin @('None', 'History', 'Plugin', 'HistoryAndPlugin')) { throw 'Invalid PredictionSource.' }
    return $settings
}
