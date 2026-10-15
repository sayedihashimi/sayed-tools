# Compatibility import path. Call Initialize-SayedProfile after importing.
Import-Module (Join-Path $PSScriptRoot 'Sayed.Profile/Sayed.Profile.psd1') -Global -DisableNameChecking -ErrorAction Stop
