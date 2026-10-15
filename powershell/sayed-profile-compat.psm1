# Compatibility shim for the former Dropbox sayed-profile.psm1.
$toolsRoot = if ($env:SAYED_TOOLS_ROOT) { $env:SAYED_TOOLS_ROOT } elseif ($global:codehome) { Join-Path $global:codehome 'sayed-tools' } elseif ($IsWindows) { 'C:\data\mycode\sayed-tools' } else { Join-Path $HOME 'data/mycode/sayed-tools' }
Import-Module (Join-Path $toolsRoot 'powershell/Sayed.Profile/Sayed.Profile.psd1') -Global -DisableNameChecking -ErrorAction Stop
