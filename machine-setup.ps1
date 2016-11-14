[cmdletbinding()]
param()

$global:machinesetupconfig = @{
    MachineSetupConfigFolder = (Join-Path $env:temp 'SayedHaMachineSetup')
    BaseChocoPackages = @(
        'boxstarter',
        'git.install',
        'googlechrome',
        'firefox',
        '1password',
        'notepadplusplus.install',
        'conemu'
    )
    BaseRepos = @(
        'git@github.com:sayedihashimi/sayed-tools.git',
        'git@github.com:sayedihashimi/pshelpers.git',
        'git@github.com:dahlbyk/posh-git.git'
    )
    SecondaryChocoPackages = @(
        'p4merge',
        'f.lux',
        '7zip.install ',
        'paint.net',
        'pdfcreator',
        'sublimetext3',
        'fiddler4',
        'gimp',
        'linqpad4',
        'kdiff3',
        'balsamiqmockups3',
        'adobe-creative-cloud',
        'inkscape',
        'visualstudiocode',
        'yeoman',
        'spotify',
        'everything',
        'markdownpad2',
        'snagit',
        'kindle'
    )
    WallpaperUrl = 'https://dl.dropboxusercontent.com/u/40134810/wallpaper/checking-out-the-view.jpg'
}

function InternalGet-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}

$scriptDir = ((InternalGet-ScriptDirectory) + "\")

if([string]::IsNullOrWhiteSpace($Global:dropboxhome)){
    if(-not ([string]::IsNullOrWhiteSpace($env:dropboxhome))){
        $Global:dropboxhome = $env:dropboxhome
    }
    else{
        $Global:dropboxhome = 'c:\data\dropbox'
    }
}

if([string]::IsNullOrWhiteSpace($Global:codehome)){
    if(-not ([string]::IsNullOrWhiteSpace($env:codehome))){
        $Global:codehome = $env:codehome
    }
    else{
        $Global:codehome = 'c:\data\mycode'
    }
}

function EnsureFolderExists{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$path
    )
    process{
        foreach($p in $path){
            if(-not [string]::IsNullOrWhiteSpace($p) -and (-not (Test-Path $p))){
                New-Item -Path $p -ItemType Directory
            }
        }
    }
}

function IsCommandAvailable{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        $command
    )
    process{
        $foundcmd = (get-command choco.exe -ErrorAction SilentlyContinue)
        [bool]$isinstalled = ($foundcmd -ne $null)

        # return the value
        $isinstalled
    }
}

function GetCommandFullpath{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$command
    )
    process{
        (get-command $command).Source
    }
}

function InstallChoclatey{
    [cmdletbinding()]
    param()
    process{
        iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex
        # restart the console to get the changes
        RestartThisScript
    }
}

function RestartThisScript{
    [cmdletbinding()]
    param()
    process{
        @'
************************************
Restarting the script
************************************
'@ | Write-Output

        powershell.exe -ExecutionPolicy RemoteSigned -File $($MyInvocation.ScriptName) -NoExit
    }
}

function InstallWithChoco{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [array]$packages
    )
    process{
        foreach($pkg in $packages){
            choco install $pkg -y
        }
    }
}

function InstallBaseApps{
    [cmdletbinding()]
    param()
    process{
        $Global:machinesetupconfig.BaseChocoPackages | InstallWithChoco
        # need to relaunch for Boxstarter
        RestartThisScript
    }
}

function InstallSecondaryApps{
    [cmdletbinding()]
    param()
    process{
        $Global:machinesetupconfig.SecondaryChocoPackages | InstallWithChoco
    }
}

function EnsureBaseReposCloned{
    [cmdletbinding()]
    param()
    process{
        foreach($repo in $global:machinesetupconfig.BaseRepos){
            if(-not [string]::IsNullOrWhiteSpace($repo)){
                $reponame = $repo.Substring($repo.LastIndexOf('/')+1,($repo.LastIndexOf('.git') - ($repo.LastIndexOf('/')+1)))

                # if the folder is not on disk clone the repo
                $dest = (Join-Path $Global:codehome $reponame)
                if(-not (Test-Path $dest)){
                    Push-Location
                    try{
                        Set-Location $Global:codehome
                        git clone $repo
                    }
                    finally{
                        Pop-Location
                    }
                }
            }
        }
    }
}

function IsRunningAsAdmin{
    [cmdletbinding()]
    param()
    process{
        [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
    }
}

function ConfigureConsole{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$conemuxmlurl = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/dotfiles/ConEmu.xml',
        [Parameter(Position=1)]
        [string]$conemulocalpath = (Join-Path $env:APPDATA 'conemu.xml')
    )
    process{
        EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($conemulocalpath))
        Invoke-WebRequest -Uri $conemuxmlurl -OutFile $conemulocalpath
    }
}

function ConfigureGit{
    [cmdletbinding()]
    param(
        [string]$sshdownloadurl = $env:machinesetupsshurl,
        [string]$machinesetuppwd = $env:machinesetuppassword
    )
    process{
        # copy .gitconfig from dropbox to documents
        $documentspath = ([Environment]::GetFolderPath("MyDocuments"))
        if( ([string]::IsNullOrWhiteSpace($documentspath)) -or (-not (test-path $documentspath))){
            'Documents folder not found at [{0}]' -f $documentspath |Write-Error
            break
        }

        $gitconfigurl = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/dotfiles/.gitconfig'
        $gitconfigsource=(GetLocalFileFor -filename '.gitconfig' -downloadUrl $gitconfigurl)
        $destgitconfig = (Join-Path $documentspath '.gitconfig')
        if(-not (Test-Path $destgitconfig)){
            '.gitconfig not found at [{0}] copying from [{1}]' -f $destgitconfig,$gitconfigsource | Write-Verbose
            Copy-Item -Path $gitconfigsource -Destination $destgitconfig
        }

        # copy ssh keys to documents folder        
        $destsshpath = (Join-Path $env:USERPROFILE '.ssh')
        if(-not (Test-Path $destsshpath)){           
            if([string]::IsNullOrWhiteSpace($sshdownloadurl) -or [string]::IsNullOrWhiteSpace($machinesetuppwd)){
                 $msg = 'The .ssh url or the machine setup password is empty. Check 1Password for the values and assign env vars, and restart this script'
            }

            $sshzip = (GetLocalFileFor -downloadUrl $sshdownloadurl -filename '.ssh.7z')
            $7zipexe = (join-path $env:ProgramFiles '7-Zip\7z.exe')
            if(-not (Test-Path -Path $7zipexe -PathType Leaf) ){
                throw ('7zip not found at [{0}]' -f $7zipexe)
            }
            EnsureFolderExists -path $destsshpath
            & $7zipexe e "-p$machinesetuppwd" "-o$destsshpath" $sshzip
        }
    }
}

function GetLocalFileFor{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$filename
    )
    process{
        $expectedPath = (Join-Path $global:machinesetupconfig.MachineSetupConfigFolder $filename)
        
        if(-not (test-path $expectedPath)){
            # download the file
            EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($expectedPath)) | out-null            
            Invoke-WebRequest -Uri $downloadUrl -OutFile $expectedPath | out-null
        }

        if(-not (test-path $expectedPath)){
            throw ('Unable to download file from [{0}] to [{1}]' -f $downloadUrl, $expectedPath)
        }

        $expectedPath
    }
}

function ConfigurePowershell{
    [cmdletbinding()]
    param(
        [string]$psProfilePath = $profile,
        [string]$sourceProfilePath,
        [string]$profileDownloadurl = 'https://dl.dropboxusercontent.com/u/40134810/sayed-profile-script-current.ps1'
    )
    process{
        if([string]::IsNullOrWhiteSpace($sourceProfilePath)){
            $sourceProfilePath = (GetLocalFileFor -downloadUrl $profileDownloadurl -filename sayed-profile-script-current.ps1)
        }

        # copy profile to $PROFILE if not exist
        $destprofile = $profile
        if(-not (Test-Path $destprofile)){
               'PowerShell profile not found at [{0}] copying from [{1}]' -f $sourcesshpath, $destsshpath | Write-Verbose
               # use -Force because the folder may need to get created as well
               Copy-Item -Path $sourceProfilePath -Destination $destprofile -Force
        }
    }
}

function EnsurePhotoViewerRegkeyAdded{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$photoviewerregkeypath,

        [Parameter(Position=1)]
        [string]$photoviewhasrunpath = (Join-Path $global:machinesetupconfig.MachineSetupConfigFolder 'photoviewerreg.hasrun'),

        [Parameter(Position=3)]
        [string]$photoviewerregdownloadurl = 'https://dl.dropboxusercontent.com/u/40134810/PcSettings/photo-viewer.reg'
    )
    process{
        if(-not (Test-Path $photoviewhasrunpath)){
            if([string]::IsNullOrWhiteSpace($photoviewerregkeypath)){
                $photoviewerregkeypath = (GetLocalFileFor -downloadUrl $photoviewerregdownloadurl -filename 'photo-viewer.reg')
            }
            
            # run the .reg key and then create the .hasrun file
            $errorCountBefore = $Error.Count
            & $photoviewerregkeypath
            $errorCountAfter = $Error.Count
            
            if($errorCountBefore -eq $errorCountAfter){
                'reg key has been added'
            }

            CreateDummyFile -filepath $photoviewhasrunpath
            # there is
        }
    }
}

function CreateDummyFile{
    [cmdletbinding()]
    param(
        [string[]]$filepath
    )
    process{
        foreach($path in $filepath){            
            if( (-not ([string]::IsNullOrWhiteSpace($path)) ) -and (-not (Test-Path -Path $path)) ){
                EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($path));
                Set-Content -Value 'empty file' -Path $path
            }
        }
    }
}

function GetPinToTaskbarTool{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$downloadUrl = 'https://github.com/sayedihashimi/sayed-tools/raw/master/contrib/PinTo10v2.exe'
    )
    process{
        # see if the file has already been downloaded
        [string]$expectedPath = (join-path $global:machinesetupconfig.MachineSetupConfigFolder 'PinTo10v2.exe')
        if(-not (test-path $expectedPath)){
            'Downloading PinToTaskbar from [{0}] to [{1}]' -f $downloadUrl,$expectedPath | Write-Verbose
            # make sure the directory exists
            EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($expectedPath)) | write-verbose
            # download the file
            Invoke-WebRequest -Uri $downloadUrl -OutFile $expectedPath | write-verbose
        }

        if(-not (test-path $expectedPath)){
            $msg = 'Unable to download PinToTaskbar from [{0}] to [{1}]' -f $downloadUrl,$expectedPath
            throw $msg 
        }

        $expectedPath
    }
}

# https://connect.microsoft.com/PowerShell/feedback/details/1609288/pin-to-taskbar-no-longer-working-in-windows-10
function PinToTaskbar{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$pathtopin,

        [Parameter(Position=0)]
        [string]$pinTov2 = (GetPinToTaskbarTool)
    )
    process{        
        if(-not (Test-Path $pinTov2)){
            'PinTo10v2.exe not found at [{0}]' -f $pinTov2 | Write-Error
            break
        }

        foreach($path in $pathtopin){
            & $pinTov2 /pintb $path
        }
    }
}

function ConfigureTaskBar{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$configuretaskbarhasrunpath = (Join-Path $global:machinesetupconfig.MachineSetupConfigFolder 'configtaskbar.hasrun')
    )
    process{
        if(-not (Test-Path $configuretaskbarhasrunpath)){
            $itemstopin = @(
                "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
                "$env:ProgramFiles\ConEmu\ConEmu64.exe"
            )

            foreach($pi in $itemstopin){
                if (test-path $pi) {
                    PinToTaskbar -pathtopin $pi
                }
            }

            CreateDummyFile -filepath $configuretaskbarhasrunpath
        }
    }
}

function ConfigureWindowsExplorer{
    [cmdletbinding()]
    param()
    begin{
        LoadBoxstarter
    }
    process{
        # show file extensions
        Set-WindowsExplorerOptions -EnableShowFileExtensions

        # try to update the wallpaper
        try{
            $wppath = (GetLocalFileFor -downloadUrl $global:machinesetupconfig.WallpaperUrl -filename 'wp-view.jpg')
            Update-wallpaper -path $wppath -Style 'Fit'
        }
        catch{
            $_ | Write-Warning
        }

        # update mouse pointer speed

        # update mouse pointer to show when CTRL is clicked
    }
}

function LoadBoxstarter{
    [cmdletbinding()]
    param()
    process{
        Import-Module Boxstarter.WinConfig
    }
}

function LoadModules{
    [cmdletbinding()]
    param()
    process{
        $modstoload = @("$global:codeHome\sayed-tools\powershell\sayed-tools.psm1")
        foreach($mod in $modstoload){
            if(test-path $mod -PathType Leaf){
                'Loading module from [{0}]' -f $mod| Write-Verbose
                Import-Module $mod -Global -DisableNameChecking
            }
            else{
                'Module file not found at [{0}]' -f $mod | Write-Warning
            }
        }
    }
}

function ConfigureMachine{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        $codehome = $Global:codehome
    )
    process{
        # check to see that Choclatey is installed

        if(-not (IsCommandAvailable -command choco.exe)){
            InstallChoclatey
            #"`r`nERROR: Choclatey is not installed, install and rerun this script" | Write-Error
            #throw
        }

        EnsureFolderExists $codehome

        InstallBaseApps
        
        Enable-RemoteDesktop
        EnsurePhotoViewerRegkeyAdded
        ConfigureTaskBar        

        ConfigureConsole
        ConfigureGit
        ConfigurePowershell

        EnsureBaseReposCloned
        LoadModules
        InstallSecondaryApps

        ConfigureWindowsExplorer

        try{
            #Install-WindowsUpdate
        }
        catch{
            $_ | Write-Warning
        }
    }
}


#########################################
# Begin script
#########################################
if(-not (IsRunningAsAdmin)) {
    'This script needs to be run as an administrator' | Write-Error
    throw
}

Push-Location
try{
    Set-Location $scriptDir
    ConfigureMachine
}
finally{
    Pop-Location
}