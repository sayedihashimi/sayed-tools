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
        [string]$gitconfigpath # = (Get-FullPathNormalized (join-path $global:MyProfileSettings.HomeDir .gitconfig -ErrorAction SilentlyContinue))
    )
    process{
        $expectedPath = Get-FullPathNormalized -path "~/.gitconfig"
        if(-not (test-path -Path $expectedPath)){
            Sayed-ConfigureGit
        }
    } 
}

function Configure-DotnetTabCompletion(){
    [cmdletbinding()]
    param()
    process{
        # from https://github.com/dotnet/command-line-api/blob/main/src/System.CommandLine.Suggest/dotnet-suggest-shim.ps1
        # dotnet suggest shell start
        $availableToComplete = (dotnet-suggest list) | Out-String
        $availableToCompleteArray = $availableToComplete.Split([Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries) 

        Register-ArgumentCompleter -Native -CommandName $availableToCompleteArray -ScriptBlock {
            param($commandName, $wordToComplete, $cursorPosition)
            $fullpath = (Get-Command $wordToComplete.CommandElements[0]).Source

            $arguments = $wordToComplete.Extent.ToString().Replace('"', '\"')
            dotnet-suggest get -e $fullpath --position $cursorPosition -- "$arguments" | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }
$env:DOTNET_SUGGEST_SCRIPT_VERSION = "1.0.0"
# dotnet suggest script end
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


function ImportSayedTools{
    [cmdletbinding()]
    param(
        $toolsmodpath = (join-path $codehome 'sayed-tools\powershell\sayed-tools.psm1')
    )
    process{
        if(test-path $toolsmodpath){
            Import-Module $toolsmodpath -Global -DisableNameChecking | Write-Verbose
            # return true to indicate success
            $true
        }
        else{
            'sayed-tools not found at [{0}]' -f $toolsmodpath | Write-Warning
            # return false to indicate not-successful
            $false
        }
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

function Load-CustomModules2{
    $customModsPath = @()
    if(-not ([string]::IsNullOrWhiteSpace($dropboxPsHome))){
        $customModsPath += (Join-Path -path $dropboxPsHome -ChildPath 'CustomModules')
    }
    if(-not([string]::IsNullOrWhiteSpace($codeHome))){
        $customModsPath += (Join-Path -Path $codeHome -ChildPath 'pshelpers')
        $customModsPath += (Join-Path -Path $codeHome -ChildPath 'sayed-tools\powershell')
        $customModsPath += (Join-Path -Path $codeHome -ChildPath 'nuget-powershell')
        $customModsPath += $codeHome
    }

    # custom mods folder found
    $modulesToLoad = @()
    $modulesToLoad += 'sayedha-pshelpers'
    $modulesToLoad += 'github-ps'
    $modulesToLoad += 'nuget-powershell'

    foreach($p in $customModsPath){
        foreach($modToLoad in $modulesToLoad){
            $modFullPath = (Join-Path -Path $p -ChildPath ("{0}.psm1" -f $modToLoad))

            if(Test-Path($modFullPath)){
                if(Get-Module $modToLoad){
                    Remove-Module $modToLoad
                }

                "Loading module [{0}] from [{1}]" -f $modToLoad, $modFullPath | Write-Verbose
                Import-Module $modFullPath -DisableNameChecking -PassThru -Global | Out-Null

                # first module found wins
                break
            }
            else{
                "Unable to find module at [{0}]" -f $modFullPath | Write-Verbose
            }
        }
    }
}
function Add-GitToPath{
    [cmdletbinding()]
    param(
        [string[]]$pathsToTry
    )
    process{       
        if($IsWindows){
            if( ($pathsToTry -eq $null) -or ($pathsToTry.Length -le 0)){
                $pathsToTry=@()
                $pathsToTry += "${env:ProgramFiles}\git\bin"
                $pathsToTry += "${env:ProgramFiles(x86)}\git\bin"
            }
        }
        else{
            if( ($pathsToTry -eq $null) -or ($pathsToTry.Length -le 0)){
                $pathsToTry=@()
                $pathsToTry += "/usr/bin/git"
            }
        }
        foreach($path in $pathsToTry){
            if(Test-Path -Path $path){
                'found git at [{0}]' -f $path | Write-Verbose
                Add-Path $path

                # Set-Alias git ("$path\git.exe")

                return $true
            }
        }

        return $false
    }
}
function glog {
    & git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative
  }
function Sayed-ConfigureTools(){
    if(-not $isLinuxOrMac){
        "Configuring tools" | Write-Verbose
        $toolsToConfigure = @(
            @{ "alias"="msb","msbuild"; "path"="${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin","$netFx4Path\msbuild.exe" },
            @{ 'alias'='dev16';'path'="${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Preview\Common7\IDE\devenv.exe"},
            @{ 'alias'='dev16-ga';'path'="${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\devenv.exe"},
            @{ "alias"="iisexpress"; "path"="${env:ProgramFiles(x86)}\IIS Express\iisexpress.exe" },
            @{ "alias"="msdeploy","msd";"path"="$env:ProgramFiles\IIS\Microsoft Web Deploy V3\msdeploy.exe" },
            @{ "alias"="np";"path"="$env:ProgramFiles\Notepad++\notepad++.exe" },
            @{ "alias"="p4merge"; "path"="$env:ProgramFiles\Perforce\p4merge.exe","$env:ProgramFiles\Perforce\p4merge.exe" },
            @{ "alias"="handle"; "path"="$dropBoxHome\Tools\SysinternalsSuite\handle.exe" },
            @{ "alias"="kdiff"; "path"="$env:ProgramFiles\KDiff3\kdiff3.exe" },
            @{ "alias"="code"; "path"="$env:ProgramFiles\Microsoft VS Code\Code.exe"}
        )
        Add-AliasForTool -tool $toolsToConfigure
    }
}
function ConfigurePowerShellConsoleWindow(){    
    # confiure the window
    $pshost = get-host
    $pswindow = $pshost.ui.rawui

	# not supported on macOS
    if($IsWindows){
        $newsize = (Get-Host).UI.RawUI.BufferSize
        $newsize.Height = 20000
        (Get-Host).UI.RawUI.BufferSize = $newsize
    }
}



# Ensure that Meslo LGM NF Font is installed and the terminal is configured to use it.
function Configure-Posh{
    oh-my-posh init pwsh | Invoke-Expression
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/quick-term.omp.json" | Invoke-Expression
}

function Configure-PoshSettingsForTheme{
    [cmdletbinding()]
    param(
        [string]$themename
    )
    process{
        if([string]::Compare('Agnoster-sayedha',$themename,$true) -eq 0){
            #$ThemeSettings.PromptSymbols.StartSymbol = '%'
        }
    }
}

# python.exe must be on the path for this to work.
function Start-WebServer{
    [cmdletbinding()]
    param(
        [string] $runFolder = $pwd,
        [int] $port = 8000,
        [string] $pythonCommand = "python.exe"
    )
    process{
        # python -m http.server 8000
        # https://gist.github.com/magnetikonline/f880b0cb063c54568ade7073f935bbd1
        $cmdargs = @(
            "-m",
            "http.server",
            $port
        )
        $oldloc = get-location
        set-location -Path $runFolder
        & $pythonCommand $cmdargs
        set-location -Path $oldloc
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

        # Configure-DotnetTabCompletion
    }
}

function Sayed-InitailizeProfile{
    [cmdletbinding()]
    param()
    process{
        if(ImportSayedTools){
            if((Add-GitToPath)){
                Sayed-ConfigureGit
            }
            else {
                'git not found' | Write-Warning
            }

            'Importing tools' | Write-Output
            ConfigurePowerShellConsoleWindow
            Configure-Posh
            Load-CustomModules2
            Sayed-ConfigureTools

            SayedConfigureSaveMachineInfoJob -asJob
        }
        else{
            'Not importing tools...' | Write-Output
        }

        if(Test-path $codeHome){
            set-location $codeHome
        }
    }
}

InitalizeEnv
$machineProfilePath = (join-path $codehome machine-profile.ps1)
if(test-path $machineProfilePath){
    .$machineProfilePath
}