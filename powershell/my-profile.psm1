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

function Open-Github(){
    [cmdletbinding()]
    param(
        $path = $pwd
    )
    process{
        $path = (Get-FullPathNormalized -path $path)
        $pattern = 'origin\tgit@github.com:([a-zA-S-.]+)/([a-zA-Z-]+)\.git.*(fetch\))'
        Push-Location -LiteralPath $path
        $gitremotes = git remote -v
        $res = [Regex]::Matches($gitremotes, $pattern)
        if($res -ne $null){
            if($res.Count -gt 1){
                $res = $res[0]
            }

            $username = $res.Groups[1].Value
            $reponame = $res.Groups[2].Value

            # https://github.com/sayedihashimi/sayed-tools
            $repourl = 'https://github.com/{0}/{1}' -f $username, $reponame

            if($isLinuxOrMac){
                open $repourl
            }
            else{
                start $repourl
            }

            'https://github.com/{0}/{1}' -f $username, $reponame | Write-Host
        }
    }
    End{
        Pop-Location
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

function Get-FilesCreatedBetweenDates{
    [cmdletbinding()]
    param(
        [datetime]$startDate,
        [datetime]$endDate,
        [string]$path,
        [string]$include
    )
    process{
        Get-ChildItem -Path $path $include -Recurse -File|? {$_.LastWriteTime -lt $endDate }|? {$_.LastWriteTime -gt $startDate} | Select Fullname ,LASTWRITETIME | Sort-Object -Property LASTWRITETIME -Descending 
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
            $cliptemp = (& pbpaste)
            $cliptemp = $cliptemp.Trim()
            $cliptemp | pbcopy
#            & pbpaste|pbcopy

            ' ✓ Clipboard converted to plain text' | Write-Output
        }
    }

    function VSMac-CleanLogFolder{
        [cmdletbinding()]
        param(
            [string]$logRootFolderPath = '~/Library/Logs/VisualStudio/',
            
            [ValidateSet('7.0','8.0')]
            [string]$version = '8.0'
        )
        process{
            $logFolderPath = (Join-Path -Path $logRootFolderPath -ChildPath $version)

            if(test-path $logFolderPath){
                $files = (Get-ChildItem -Path $logFolderPath -Filter '*.log').FullName
                "Deleting files:`n" + ($files -join "`n") | Write-Output
                Remove-Item -LiteralPath $files
            }
            else{
                "Log folder not found at $logFolderPath" | Write-Warning
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
            [string]$logRootFolderPath = '~/Library/Logs/VisualStudio/',

            [ValidateSet('7.0','8.0')]
            [string]$version = '8.0',

            [string]$filename,
            [string]$resultFolderPath = '~/Library/Logs/VisualStudio/'
        )
        process{
            if([string]::IsNullOrEmpty($filename)){
                $dateStr = ((Get-Date).ToString('yyyy.MM.dd.ss.ff'))
                $filename = ("ide-{0}-log-{1}.zip" -f $version, $dateStr)
            }

            $destArchivePath = (Join-Path -Path $resultFolderPath -ChildPath $filename)

            $logFolderPath = (Join-Path -Path $logRootFolderPath -ChildPath $version)

            if(Test-Path $logFolderPath){
                Compress-Archive -Path $logFolderPath -DestinationPath $destArchivePath
                $destArchivePath | Write-Output
            }
            else{
                "Log folder not found at $logFolderPath" | Write-Warning
            }
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


InitalizeEnv