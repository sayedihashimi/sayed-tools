[cmdletbinding()]
param()

$global:MacProfileSettings = New-Object PSObject -Property @{
    HomeDir = $env:HOME
    ModulesToLoad = @(
        (get-item (join-path -Path $global:codehome 'sayed-tools/powershell/github-ps.psm1' -ErrorAction SilentlyContinue)).FullName
        (get-item (join-path -Path $global:codehome 'sayed-tools/powershell/sayed-tools.psm1' -ErrorAction SilentlyContinue)).FullName
        (get-item (join-path $Global:dropboxpath 'Personal/PcSettings/Powershell/sayed-profile-xplat.psm1' -ErrorAction SilentlyContinue)).FullName        
    )
}

function Set-InitialPath{
    [cmdletbinding()]
    param()
    process{
        if(test-path $global:codehome){
            Push-Location
            Set-Location -Path $global:codehome
        }
    }
}

function Import-MyModules{
    [cmdletbinding()]
    param()
    process{
        [bool]$allImported = $true
        foreach ($modpath in $global:MacProfileSettings.ModulesToLoad) {
            if(Test-Path $modpath){
                'Importing module from [{0}]' -f $modpath | Write-Host
                Import-Module $modpath -Global -DisableNameChecking | Write-Verbose
            }
            else{
                $allImported = $false
                'Module not found at [{0}]' -f $modpath | Write-Output
            }
        }

        # return true if all imported
        $allImported
    }
}

<#
[string[]]$modsToLoad = @(
    (join-path -Path $global:codehome 'sayed-tools/powershell/github-ps.psm1' -ErrorAction SilentlyContinue)
    (join-path -Path $global:codehome 'sayed-tools/powershell/sayed-tools.psm1' -ErrorAction SilentlyContinue)
    (join-path $Global:dropboxpath 'Personal/PcSettings/Powershell/sayed-profile-xplat.psm1' -ErrorAction SilentlyContinue)
    # (join-path $Global:dropboxpath 'Personal/PcSettings/Powershell/sayed-profile.psm1' -ErrorAction SilentlyContinue)
)

foreach ($modpath in $modsToLoad) {
    if(Test-Path $modpath){
        'Importing module from [{0}]' -f $modpath | Write-Host
        Import-Module $modpath -Global -DisableNameChecking
    }
    else{
        'Module not found at [{0}]' -f $modpath | Write-Output
    }
}
#>

function clip{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object]$inObj
    )
    process{
        if($inObj -ne $null){
            $inObj | pbcopy
        }
    }
}

function Ensure-GitConfigExists{
    [cmdletbinding()]
    param(
        [string]$gitconfigpath = ([System.IO.Path]::GetFullPath((join-path $global:MacProfileSettings.HomeDir .gitconfig -ErrorAction SilentlyContinue)))
    )
    process{
        if(-not ([string]::IsNullOrWhiteSpace($gitconfigpath)) -and (-not (test-path $gitconfigpath))) {
            Sayed-ConfigureGit
        }
    } 
}

#### Start script

Set-InitialPath
if( (Import-MyModules) -eq $true){
    Ensure-GitConfigExists
}
