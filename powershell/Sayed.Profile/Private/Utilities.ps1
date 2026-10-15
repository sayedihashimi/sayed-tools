$isLinuxOrMac = $IsLinux -or $IsMacOS
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

function RunScriptIfExists{
    [cmdletbinding()]
    param(
        [string]$scriptpath,
        [string]$missingMessage = 'script not found at [{0}]'
    )
    process{
        if(Test-Path $scriptpath -PathType Leaf){
            . $scriptpath
        }
        else{
            $missingMessage -f $scriptpath | Write-Warning
        }
    }
}

function glog {
    & git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative
  }

# python.exe must be on the path for this to work.
function Start-WebServer{
    [cmdletbinding()]
    param(
        [string] $runFolder = $pwd,
        [int] $port = 8000,
        [string] $pythonCommand = "python"
    )
    process{
        # python -m http.server 8000
        # https://gist.github.com/magnetikonline/f880b0cb063c54568ade7073f935bbd1
        $cmdargs = @(
            "-m",
            "http.server",
            $port
        )
        Push-Location -LiteralPath $runFolder
        try { & $pythonCommand @cmdargs }
        finally { Pop-Location }
    }
}

function Start-MyHomepage{
  [cmdletbinding()]
  param()
  process{
    $path = (join-path $codeHome myhomepage/run-local.ps1)
    &$path
  }
}

if(-not $isLinuxOrMac){
    [string]$defaultVsLogsFolder = (join-path $env:temp VSLogs)
    function VS-CleanLogFolder{
        [cmdletbinding()]
        param(
            [string]$logRootFolderPath = $defaultVsLogsFolder
        )
        process{
            if(test-path $logRootFolderPath){
                $files = (Get-ChildItem -Path $logRootFolderPath -Filter '*.svclog').FullName
                "Deleting files:`n" + ($files -join "`n") | Write-Output
                Remove-Item -LiteralPath $files
            }
            else{
                "Log folder not found at $logRootFolderPath" | Write-Warning
            }
        }
    }

    function VS-OpenLogFolder{
        [cmdletbinding()]
        param(
            [string]$logFolderPath = $defaultVsLogsFolder
        )
        process{
            start $logFolderPath
        }
    }

    function VS-CompressLogs{
        [cmdletbinding()]
        param(
            [string]$logRootFolderPath = $defaultVsLogsFolder,

            [string]$filename,
            [string]$resultFolderPath = $defaultVsLogsFolder
        )
        process{
            if([string]::IsNullOrEmpty($filename)){
                $dateStr = ((Get-Date).ToString('yyyy.MM.dd.ss.ff'))
                $filename = ("vs-log-{0}.zip" -f $dateStr)
            }

            $destArchivePath = (Join-Path -Path $resultFolderPath -ChildPath $filename)

            $logFolderPath = (Join-Path -Path $logRootFolderPath -ChildPath $version)

            if(Test-Path $logFolderPath){
                Get-ChildItem $defaultVsLogsFolder -Recurse -Exclude *.zip|Compress-Archive -DestinationPath $destArchivePath
                $destArchivePath | Write-Output
            }
            else{
                "Log folder not found at $logFolderPath" | Write-Warning
            }
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

function ConfigureGit{
    [cmdletbinding()]
    param()
    process{
        $sshfolderpath = "$HOME\.ssh"
        test-path -Path "$HOME\.ssh" -PathType Container
        # check to see if the .gitconfig is already on disk, if so, skip all these steps
        if(-not (test-path $sshfolderpath -PathType Container)){
            Mount-SettingsVirtualHardDrive
            'Copying .ssh folder to "{0}"' -f $sshfolderpath | Write-Output
            Copy-Item -Path "X:\.ssh" -Destination $sshfolderpath -Recurse -Force
        }
        else{
            '.ssh folder exists at "{0}", not copying' -f $sshfolderpath | Write-Output
        }

        if(-not  (Test-Path -Path "$HOME\.gitconfig")){
            'Copying .gitconfig to "{0}"' -f "$HOME\.gitconfig" | Write-Output
            Copy-Item -LiteralPath "X:\.gitconfig" -Destination "$HOME\.gitconfig" -Force
        }
        else{
            '.gitconfig exists at "{0}", not copying' -f $sshfolderpath | Write-Output
        }
        # wait a bit to ensure the copy is complete
        Start-Sleep -Seconds 2
        Unmount-SettingsVirtualHardDrive
    }
}

##############################
# functions below based on https://github.com/ChrisTitusTech/powershell-profile/blob/main/Microsoft.PowerShell_profile.ps1
##############################
function Update-PowerShell {    
    try {
        Write-Host "Checking for PowerShell updates..." -ForegroundColor Cyan
        $updateNeeded = $false
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $gitHubApiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestReleaseInfo = Invoke-RestMethod -Uri $gitHubApiUrl -TimeoutSec 15
        $latestVersion = $latestReleaseInfo.tag_name.Trim('v')
        if ([version]$currentVersion -lt [version]$latestVersion) {
            $updateNeeded = $true
        }

        if ($updateNeeded) {
            Write-Host "Updating PowerShell..." -ForegroundColor Yellow
            Start-Process powershell.exe -ArgumentList "-NoProfile -Command winget upgrade Microsoft.PowerShell --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow
            Write-Host "PowerShell has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        } else {
            Write-Host "Your PowerShell is up to date." -ForegroundColor Green
        }
    } catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}
function Test-CommandExists {
    param($command)
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}
# Network Utilities
function Get-PubIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

# Open WinUtil full-release
function winutil {
    irm https://christitus.com/win | iex
}

function head {
  param($Path, $n = 10)
  Get-Content $Path -Head $n
}

function tail {
  param($Path, $n = 10, [switch]$f = $false)
  Get-Content $Path -Tail $n -Wait:$f
}

function touch($file) { "" | Out-File $file -Encoding ASCII }
function ff($name) {
    Get-ChildItem -recurse -filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "$($_.FullName)"
    }
}
function uptime {
    try {
        # find date/time format
        $dateFormat = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern
        $timeFormat = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.LongTimePattern

        # check powershell version
        if ($PSVersionTable.PSVersion.Major -eq 5) {
            $lastBoot = (Get-WmiObject win32_operatingsystem).LastBootUpTime
            $bootTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($lastBoot)

            # reformat lastBoot
            $lastBoot = $bootTime.ToString("$dateFormat $timeFormat")
        } else {
            # the Get-Uptime cmdlet was introduced in PowerShell 6.0
            $lastBoot = (Get-Uptime -Since).ToString("$dateFormat $timeFormat")
            $bootTime = [System.DateTime]::ParseExact($lastBoot, "$dateFormat $timeFormat", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        # Format the start time
        $formattedBootTime = $bootTime.ToString("dddd, MMMM dd, yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) + " [$lastBoot]"
        Write-Host "System started on: $formattedBootTime" -ForegroundColor DarkGray

        # calculate uptime
        $uptime = (Get-Date) - $bootTime

        # Uptime in days, hours, minutes, and seconds
        $days = $uptime.Days
        $hours = $uptime.Hours
        $minutes = $uptime.Minutes
        $seconds = $uptime.Seconds

        # Uptime output
        Write-Host ("Uptime: {0} days, {1} hours, {2} minutes, {3} seconds" -f $days, $hours, $minutes, $seconds) -ForegroundColor Blue

    } catch {
        Write-Error "An error occurred while retrieving system uptime."
    }
}

function IsAdmin{
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Quick Access to System Information
function sysinfo { Get-ComputerInfo }

# Networking Utilities
function flushdns {
	Clear-DnsClientCache
	Write-Host "DNS has been flushed"
}

# Clipboard Utilities
function copy { Set-Clipboard $args[0] }

function paste { Get-Clipboard }


