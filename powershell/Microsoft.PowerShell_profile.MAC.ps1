[cmdletbinding()]
param()

[string]$global:dropboxpath = (get-item '~/Dropbox/' -ErrorAction SilentlyContinue).FullName
[string]$global:dropboxhome = $global:dropboxpath
[string]$global:codehome = (get-item (Join-path ~ mycode) -ErrorAction SilentlyContinue).FullName
[string]$macProfilePath = (get-item (Join-Path $global:codehome sayed-tools/powershell/my-profile.psm1) -ErrorAction SilentlyContinue).FullName

if(test-path $global:dropboxpath){
    'dropboxpath: [{0}]' -f $global:dropboxpath | Write-Verbose
}
else{
    'dropbox path not found at [{0}]' -f $global:dropboxpath | Write-Warning
}

if(test-path $global:codehome){
    'dropboxpath: [{0}]' -f $global:codehome | Write-Verbose
}
else{
    'codehome path not found at [{0}]' -f $global:codehome | Write-Warning
}

if(Test-Path $macProfilePath){
    'Importing macProfile from [{0}]' -f $macProfilePath | Write-Output
    Import-Module $macProfilePath -Global -DisableNameChecking

    InitalizeEnv
}
else{
    'mac profile module not found at [{0}]' -f $macProfilePath | Write-Warning
}
