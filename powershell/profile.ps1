# Copy this entry point to $PROFILE. Set SAYED_TOOLS_ROOT for a different checkout.
try {
    $toolsRoot = if ($env:SAYED_TOOLS_ROOT) { $env:SAYED_TOOLS_ROOT } elseif ($IsWindows) { 'C:\data\mycode\sayed-tools' } else { Join-Path $HOME 'data/mycode/sayed-tools' }
    if (-not $global:DropboxHome) { $global:DropboxHome = if ($IsWindows) { 'C:\data\Dropbox' } else { Join-Path $HOME 'data/Dropbox' } }
    if (-not $global:codehome) { $global:codehome = Split-Path $toolsRoot }
    $machineName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName }
    $machineEnvironment = Join-Path $global:DropboxHome "Personal/PcSettings/Powershell/$machineName/sayed-env.ps1"
    if (Test-Path -LiteralPath $machineEnvironment -PathType Leaf) {
        try { . $machineEnvironment }
        catch { Write-Warning "Machine environment: $($_.Exception.Message)" -WarningAction Continue }
    }
    if (-not $env:SAYED_TOOLS_ROOT) { $toolsRoot = Join-Path $global:codehome 'sayed-tools' }
    Import-Module (Join-Path $toolsRoot 'powershell/Sayed.Profile/Sayed.Profile.psd1') -Global -DisableNameChecking -ErrorAction Stop
    $machineProfile = Join-Path $global:codehome 'machine-profile.ps1'
    if (Test-Path -LiteralPath $machineProfile -PathType Leaf) {
        try { . $machineProfile }
        catch { Write-Warning "Machine profile: $($_.Exception.Message)" -WarningAction Continue }
    }
    Initialize-SayedProfile
}
catch { Write-Warning "Profile bootstrap: $($_.Exception.Message)" -WarningAction Continue }
