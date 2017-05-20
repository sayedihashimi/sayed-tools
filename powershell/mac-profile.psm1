[cmdletbinding()]
param()

function Get-FullPathNormalized{
    [cmdletbinding()]
    param (
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]] $path
    )
    process {
        foreach($p in $path){
            if(-not ([string]::IsNullOrWhiteSpace($p))){
                $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
            }
        }
    }
}

$global:MacProfileSettings = New-Object PSObject -Property @{
    HomeDir = $env:HOME
    ModulesToLoad = @(
        (Get-FullPathNormalized (join-path -Path $global:codehome 'sayed-tools/powershell/github-ps.psm1' -ErrorAction SilentlyContinue))
        (Get-FullPathNormalized (join-path -Path $global:codehome 'sayed-tools/powershell/sayed-tools.psm1' -ErrorAction SilentlyContinue))
        (Get-FullPathNormalized (join-path $global:codehome 'sayed-tools/powershell/sayed-profile-xplat.psm1' -ErrorAction SilentlyContinue))
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
        'Importing modules...' | Write-Verbose
        [bool]$allImported = $true
        foreach ($modpath in $global:MacProfileSettings.ModulesToLoad) {
            if(Test-Path $modpath){
                'Importing module from [{0}]' -f $modpath | Write-Verbose
                Import-Module $modpath -Global -DisableNameChecking | Write-Verbose
            }
            else{
                $allImported = $false
                'Module not found at [{0}]' -f $modpath | Write-Host
            }
        }

        # return true if all imported
        $allImported
    }
}

function clip{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object[]]$inObj
    )
    begin{
        [object[]]$toProcess = @()
    }
    process{
        $toProcess += $_
    }
    end{
        if($toProcess -ne $null){
            $toProcess | Out-String | pbcopy
        }
    }
}

function Ensure-GitConfigExists{
    [cmdletbinding()]
    param(
        [string]$gitconfigpath = (Get-FullPathNormalized (join-path $global:MacProfileSettings.HomeDir .gitconfig -ErrorAction SilentlyContinue))
    )
    process{
        if(-not ([string]::IsNullOrWhiteSpace($gitconfigpath)) -and (-not (test-path $gitconfigpath))) {
            Sayed-ConfigureGit
        }
    } 
}

function SayedConfigureSaveMachineInfoJob{
    [cmdletbinding()]
    param(
        [int]$sleepSeconds = (5*60)
    )
    process{
        [string]$machineName = (Get-MachineName)
        [string]$outfilepath = (Get-FullPathNormalized -path (Join-Path $Global:dropboxpath ('Personal/PcSettings/Powershell/MachineInfo/{0}.txt' -f $machineName)))
        # create a script block that will run every 5 min
        [scriptblock]$saveMachineScript = {
            [bool]$continueScript = $true

            if($continueScript -eq $true){
                try{
                    'Saving machine info to file [{0}]' -f $outfilepath | Write-Verbose
                    Save-MachineInfo -outfile $outfilepath

                    'Sleeping for [{0}] seconds' -f $sleepSeconds | Write-Verbose
                    Start-Sleep -Seconds $sleepSeconds
                }
                catch{
                    Write-Output -InputObject $_.Exception
                }
            }
        }

        & $saveMachineScript
    }
}

# This is the function that the profile script should call
function InitalizeEnv{
    [cmdletbinding()]
    param()
    process{

        Set-InitialPath
        if( (Import-MyModules) -eq $true){
            Ensure-GitConfigExists
        }
        else{
            'Missing at least 1 module.' | Write-Host -ForegroundColor Cyan
        }
    }
}
InitalizeEnv