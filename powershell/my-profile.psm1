[cmdletbinding()]
param()

$isLinuxOrMac = ($IsLinux -or $IsMacOS -or $IsOSX)

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

$global:MyProfileSettings = New-Object PSObject -Property @{
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
        foreach ($modpath in $global:MyProfileSettings.ModulesToLoad) {
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

if($isLinuxOrMac){
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

    function Convert-ClipboardToPlainText{
        [cmdletbinding()]
        param()
        process{
            & pbpaste|pbcopy
            ' ✓ Clipboard converted to plain text' | Write-Output
        }
    }

    function VSMac-CleanLogFolder{
        [cmdletbinding()]
        param(
            [string]$logFolderPath = '~/Library/Logs/VisualStudio/7.0'
        )
        process{
            if(test-path $logFolderPath){
                $files = (Get-ChildItem -Path $logFolderPath -Filter '*.log').FullName
                "Deleting files:`n" + ($files -join "`n") | Write-Output
                Remove-Item -LiteralPath $files
            }
        }
    }

    function VSMac-OpenLogFolder{
        [cmdletbinding()]
        param(
            [string]$logFolderPath = '~/Library/Logs/VisualStudio/'
        )
        process{
            open $logFolderPath
        }
    }

    function VSMac-CompressLogs{
        [cmdletbinding()]
        param(
            [string]$logFolderPath = '~/Library/Logs/VisualStudio/7.0',
            [string]$destArchivePath = ('~/Library/Logs/VisualStudio/ide-log-'+(Get-Date).ToString('yyyy.MM.dd.ss.ff') + '.zip')
        )
        process{
            Compress-Archive -Path $logFolderPath -DestinationPath $destArchivePath

            $destArchivePath | Write-Output
        }
    }

    function VSMac-OpenTelemetryLogsFolder{
        [cmdletbinding()]
        param(
            [string]$tempfolder = ([System.IO.Path]::GetTempPath())
        )
        process{
            [string]$telfolder =(Get-FullPathNormalized (Join-Path -Path $tempfolder -ChildPath 'VSTelemetryLog'))
            if(test-path $telfolder){
                open $telfolder
            }
            else{
                "Telemetry folder not found at '$telfolder'" | Write-Output
            }
        }
    }

    function VSMac-ClearTelemetryLogs{
        [cmdletbinding()]
        param(
            [string]$telfolder = (Get-FullPathNormalized ("{0}/VSTelemetryLog" -f ([System.IO.Path]::GetTempPath())) )
        )
        process{
            if(test-path $telfolder){
                $files = Get-ChildItem $telfolder *.txt | Select-Object -ExpandProperty fullname 
                foreach($file in $files) {
                    if(test-path $file) {
                        "Removing file '$file'" | Write-Output
                        Remove-Item $file
                    }
                }
            }
        }
    }

    function VSMac-EnableTelemetryFilelogger{
        [cmdletbinding()]
        param(
            [string]$vstelfolderpath = (get-fullpathnormalized '~/VSTelemetry/'),
            [string]$filename = 'channels.json'
        )
        process{
            [string]$filecontents = @'
{
    "fileLogger": "enabled"
}
'@
            # if the folder doesn't exist create it
            if(!(Test-Path -LiteralPath $vstelfolderpath)){
                New-Item -LiteralPath $vstelfolderpath -ItemType Directory
            }
            $filepath = (Get-FullPathNormalized (Join-Path -Path $vstelfolderpath -ChildPath $filename))
            "Creating tel file at '$filepath' " | Write-Output
            $filecontents | Out-File -LiteralPath $filepath

        }
    }

    function VSMac-DisableTelemetryLogging{
        [cmdletbinding()]
        param(
            [string]$vstelfolderpath = (get-fullpathnormalized '~/VSTelemetry/'),
            [string]$filename = 'channels.json'
        )
        process{
            $filepath = (Get-FullPathNormalized (Join-Path -Path $vstelfolderpath -ChildPath $filename))
            if(test-path -LiteralPath $filepath){
                "Removing config file at '$filepath'" | Write-Output
                Remove-Item -LiteralPath $filepath
            }
        }
    }

    function VSMac-OpenTelemetryConfigFolder{
        [cmdletbinding()]
        param(
            [string]$vstelfolderpath = (get-fullpathnormalized '~/VSTelemetry/')
        )
        process{
            if(test-path $vstelfolderpath){
                open ($vstelfolderpath)
            }
            else{
                "Tel config folder not found at '$vstelfolderpath'" |Write-Output
            }
        }
    }

}

function Ensure-GitConfigExists{
    [cmdletbinding()]
    param(
        [string]$gitconfigpath = (Get-FullPathNormalized (join-path $global:MyProfileSettings.HomeDir .gitconfig -ErrorAction SilentlyContinue))
    )
    process{
        if(-not ([string]::IsNullOrWhiteSpace($gitconfigpath)) -and (-not (test-path $gitconfigpath))) {
            Sayed-ConfigureGit
        }
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