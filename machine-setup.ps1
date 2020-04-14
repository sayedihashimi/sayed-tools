[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [bool]$runscript = $true
)

function New-ObjectFromProperties{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.Collections.IDictionary]$properties
    )
    process{
        if($properties -ne $null){
            # create and return the object
            New-Object -TypeName psobject -Property $properties
        }
    }
}
set-alias -Name newobj -Value New-ObjectFromProperties   

$global:machinesetupconfig = @{
    MachineSetupConfigFolder = (Join-Path $env:temp 'SayedHaMachineSetup')
    MachineSetupAppsFolder = (Join-Path $env:temp 'SayedHaMachineSetup\apps')
    BaseChocoPackages = @(
        'boxstarter',
        'boxstarter.winconfig'
        'git.install',
        'googlechrome',
        'firefox',
        '1password',
        'notepadplusplus.install',
        'conemu'
        '7zip.install '
    )
    BaseRepos = @(
        (newobj @{
                SSH = 'git@github.com:sayedihashimi/sayed-tools.git'
                HTTPS = 'https://github.com/sayedihashimi/sayed-tools.git' })

        (newobj @{
                SSH = 'git@github.com:sayedihashimi/pshelpers.git'
                HTTPS = 'https://github.com/sayedihashimi/pshelpers.git' }),

        (newobj @{
                SSH = 'git@github.com:dahlbyk/posh-git.git'
                HTTPS = 'git@github.com:dahlbyk/posh-git.git' })
    )
    SecondaryChocoPackages = @(
        'p4merge',
        'f.lux',        
        #'paint.net',
        'sublimetext3',
        'fiddler4',
        #'gimp',
        #'linqpad4',
        'kdiff3',
        'balsamiqmockups3',
        #'adobe-creative-cloud',
        #'inkscape',
        'visualstudiocode',
        # spotify needs to be installed as normal user
        # 'spotify',
        'everything',
        #'markdownpad2',
        #'snagit',
        'kindle',
        'dropbox'
    )
    WallpaperUrl = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/powershell/checking-out-the-view.jpg'
}

function InstallPrompt{
    PowerShellGet\Install-Module -Name PSReadLine -AllowPrerelease -Scope CurrentUser -Force -SkipPublisherCheck
    PowerShellGet\Install-Module posh-git -Scope CurrentUser -AllowPrerelease -Force
    PowerShellGet\Install-Module posh-git -Scope CurrentUser
    PowerShellGet\Install-Module oh-my-posh -Scope CurrentUser
}

#// 'https://dl.dropboxusercontent.com/u/40134810/wallpaper/checking-out-the-view.jpg'
function InternalGet-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}

$scriptDir = ((InternalGet-ScriptDirectory) + "\")

<#
.SYNOPSIS
    Can be used to convert a relative path (i.e. .\project.proj) to a full path.
#>
function Get-Fullpath{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline = $true)]
        $path,

        $workingDir = ($pwd)
    )
    process{
        $fullPath = $path
        $oldPwd = $pwd

        Push-Location
        Set-Location $workingDir
        [Environment]::CurrentDirectory = $pwd
        $fullPath = ([System.IO.Path]::GetFullPath($path))
        
        Pop-Location
        [Environment]::CurrentDirectory = $oldPwd

        return $fullPath
    }
}

if([string]::IsNullOrWhiteSpace($Global:dropboxhome)){
    if(-not ([string]::IsNullOrWhiteSpace($env:dropboxhome))){
        $Global:dropboxhome = $env:dropboxhome
    }

    if([string]::IsNullOrWhiteSpace($Global:dropboxhome)){
        $Global:dropboxhome = 'c:\data\dropbox'
    }
}

if([string]::IsNullOrWhiteSpace($Global:codehome)){
    if(-not ([string]::IsNullOrWhiteSpace($env:codehome))){
        $Global:codehome = $env:codehome
    }

    if([string]::IsNullOrWhiteSpace($Global:codehome)){
        $Global:codehome = 'c:\data\mycode'
    }
}

function Add-Path{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$pathToAdd,

        [System.EnvironmentVariableTarget]$envTarget = [System.EnvironmentVariableTarget]::Process,

        [bool]$alsoAddToProcess = $true
    )
    process{
        [string]$existingPath = ([System.Environment]::GetEnvironmentVariable('path',$envTarget))
        
        [string]$existingPathLower = $existingPath.ToLowerInvariant()
        
        foreach($path in $pathToAdd){
            if(-not ([string]::IsNullOrWhiteSpace($path))){
                [string]$fullpath = (Get-Fullpath -path $path)
                if(test-path -path $fullpath){
                    $trimmed = $fullpath.TrimEnd('\')
                    
                    # don't add if it's already included
                    if(-not ($existingPathLower.Contains($trimmed.ToLowerInvariant()))){
                        $newPath = ('{0};{1}' -f $existingPath,$trimmed)
                        [System.Environment]::SetEnvironmentVariable('path',$newPath,$envTarget)
                    }

                    if( ($alsoAddToProcess -eq $true) -and ($envTarget -ne [System.EnvironmentVariableTarget]::Process) ){
                        [string]$oldprocesspath = [System.Environment]::GetEnvironmentVariable('path',[System.EnvironmentVariableTarget]::Process)
                        $oldprocesspathlower = $oldprocesspath.ToLowerInvariant()
                        if(-not $oldprocesspathlower.Contains($trimmed.ToLowerInvariant())){
                            $newprocesspath = ('{0};{1}' -f $existingPath,$trimmed)
                            [System.Environment]::SetEnvironmentVariable('path',$newprocesspath,[System.EnvironmentVariableTarget]::Process)
                        }
                    }
                }
                else{
                    'Not adding to path because the path was not found [{0}], fullpath=[{1}]' -f $path,$fullpath | Write-Warning
                }
            }
        }
    }
}

function Get7ZipPath{
    [cmdletbinding()]
    param()
    process{
        (join-path $env:ProgramFiles '7-Zip\7z.exe')
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

        powershell.exe -NoExit -ExecutionPolicy RemoteSigned -File $($MyInvocation.ScriptName)
        break
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
        [string]$pkgsbefore = ((choco list --local-only) -join ';')
        $Global:machinesetupconfig.BaseChocoPackages | InstallWithChoco
        [string]$pkgsafter = ((choco list --local-only) -join ';')
        
        if(-not ([string]::Equals($pkgsbefore,$pkgsafter,[System.StringComparison]::OrdinalIgnoreCase)) ){
            Add-Path -pathToAdd "$env:ProgramFiles\Git\bin" -envTarget User
            RestartThisScript
        }
    }
}

function ConfigureFirefox{
    [cmdletbinding()]
    param(
        [string]$downloadRootUrl = 'https://dl.dropboxusercontent.com/u/40134810/PcSettings/firefox/',
        [string]$destFolder = "$env:ProgramFiles\Mozilla Firefox\defaults\pref\"
    )
    process{
        # TODO: Configure google as default search
        $files = @(
            @{
                Filename = 'autoconfig.js'
                SourceUrl = ('{0}autoconfig.js' -f $downloadRootUrl)
                DestPath = (join-path $destFolder 'autoconfig.js' )
            }
            @{
                Filename = 'mozilla.cfg'
                SourceUrl = ('{0}mozilla.cfg' -f $downloadRootUrl)
                DestPath = (join-path $destFolder 'mozilla.cfg' )
            }
        )

        foreach($f in $files){
            if(-not (test-path $f.DestPath)){
                $tf = (GetLocalFileFor -downloadUrl ($f.SourceUrl) -filename ($f.Filename))
                EnsureFolderExists([System.IO.Path]::GetDirectoryName($f.DestPath))
                Copy-Item -Path $tf -Destination $f.DestPath
            }
        }

    }
}

function InstallSecondaryApps{
    [cmdletbinding()]
    param()
    process{
        $Global:machinesetupconfig.SecondaryChocoPackages | InstallWithChoco

        EnsureFolderExists ($global:machinesetupconfig.MachineSetupAppsFolder)
        EnsureInstalled-MarkdownPad

        # TODO: Need to find a more generic way of doing this.
        $pathPartsToAdd = @(
            "$env:ProgramFiles\Git\bin"
            "${env:ProgramFiles(x86)}\Perforce"
            (Join-Path $Global:machinesetupconfig.MachineSetupAppsFolder 'markdownpad2-portable')
        )
        
        $pathPartsToAdd | %{
            $current = $_
            if(Test-Path $current){
                add-path -pathToAdd $current -envTarget User
            }
        }
    }
}

function ConfigureApps{
    [cmdletbinding()]
    param()
    process{
        ConfigureFirefox
    }
}

function ConfigureVisualStudio{
    [cmdletbinding()]
    param()
    process{
        # copy snippets
        CopyVisualStudioSnippets
    }
}

function CopyVisualStudioSnippets{
    [cmdletbinding()]
    param(
        $snippetSourcePath = (Join-Path $Global:codehome 'sayed-tools\snippets')
    )
    process{
        if(test-path -Path $snippetSourcePath -PathType Container){
            [string[]]$snippetsToCopy = (Get-ChildItem -Path $snippetSourcePath *.snippet -File).FullName
            [string]$docspath = [Environment]::GetFolderPath("MyDocuments")
            [string[]]$pathsToCopyTo ="$docspath\Visual Studio 2017\Code Snippets\Visual C#\My Code Snippets",
                                      "$docspath\Visual Studio 2015\Code Snippets\Visual C#\My Code Snippets",
                                      "$docspath\Visual Studio 2013\Code Snippets\Visual C#\My Code Snippets"
            foreach($p in $pathsToCopyTo){
                EnsureFolderExists -path $p
                foreach($file in $snippetsToCopy){
                    [string]$destpath = (Join-Path $p (get-item -Path $file).name)
                    if(-not (test-path -Path $destpath)){
                        Copy-Item -LiteralPath $file -Destination $destpath
                    }
                }
            }    
        }
        else{
            'Snippet source dir not found at [{0}]' -f $snippetSourcePath | Write-Warning
        }
    }
}

function EnsureInstalled-MarkdownPad{
    [cmdletbinding()]
    param(
        [string]$markdownpaddownloadurl = 'http://markdownpad.com/download/markdownpad2-portable.zip',
        [string]$exerelpath = 'markdownpad2-portable\MarkdownPad2.exe'
    )
    process{
        $expectedPath = (Join-Path $Global:machinesetupconfig.MachineSetupAppsFolder $exerelpath)
        if(test-path $expectedPath){
            $mkzip = (GetLocalFileFor -downloadUrl $markdownpaddownloadurl -filename 'markdownpad2-portable.zip')
            $installFolder = $Global:machinesetupconfig.MachineSetupAppsFolder
            & (Get7ZipPath) x -y "-o$installFolder" "$mkzip"
            # pin to start menu
            PinToStartmenu -pathtopin $expectedPath
            # add to path
            Add-Path -pathToAdd $expectedPath
        }
    }
}

function EnsureBaseReposCloned{
    [cmdletbinding()]
    param()
    process{
        foreach($repo in $global:machinesetupconfig.BaseRepos){
            if($repo -ne $null){
            # if(-not [string]::IsNullOrWhiteSpace($repo)){
                $sshurl = $repo.SSH
                $httpsurl = $repo.HTTPS

                if([string]::IsNullOrWhiteSpace($sshurl)){
                    continue
                }

                $reponame = $sshurl.Substring($sshurl.LastIndexOf('/')+1,($sshurl.LastIndexOf('.git') - ($sshurl.LastIndexOf('/')+1)))

                # if the folder is not on disk clone the repo
                $dest = (Join-Path $Global:codehome $reponame)
                if(-not (Test-Path $dest)){
                    Push-Location
                    try{
                        Set-Location $Global:codehome

                        $sshfolder = (Join-Path $env:USERPROFILE '.ssh')
                        # clone with ssh if the .ssh folder exists, otherwise with https
                        if( test-path $sshfolder){
                            'Cloning repo [{0}] with ssh because the .ssh folder was found at [{1}]' -f $reponame, $sshfolder | Write-Verbose
                            & git.exe clone $sshurl    
                        }
                        else{
                            'Cloning repo [{0}] with https because the .ssh folder was not found at [{1}]' -f $reponame, $sshfolder | Write-Verbose
                            & git.exe clone $httpsurl
                        }
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
                 throw $msg
            }

            $sshzip = (GetLocalFileFor -downloadUrl $sshdownloadurl -filename '.ssh.7z')
            $7zipexe = (Get7ZipPath)
            if(-not (Test-Path -Path $7zipexe -PathType Leaf) ){
                throw ('7zip not found at [{0}]' -f $7zipexe)
            }
            EnsureFolderExists -path $destsshpath
            & $7zipexe e -y "-p$machinesetuppwd" "-o$destsshpath" $sshzip
        }

        Add-Path -pathToAdd "$env:ProgramFiles\Git\bin" -envTarget User
    }
}

function GetLocalFileFor{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1,Mandatory=$true)]
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

function ExtractRemoteZip{
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
        $zippath = GetLocalFileFor -downloadUrl $downloadUrl -filename $filename
        $expectedFolderpath = (join-path -Path ($global:machinesetupconfig.MachineSetupConfigFolder) ('apps\{0}\' -f $filename))

        if(-not (test-path $expectedFolderpath)){
            EnsureFolderExists -path $expectedFolderpath | Write-Verbose
            # extract the folder to the directory
            & (Get7ZipPath) x -y "-o$expectedFolderpath" "$zippath" | Write-Verbose
        }        

        # return the path to the folder
        $expectedFolderpath
    }
}

function ExtractLocalZip{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$filepath
    )
    process{
        $filename = [System.IO.Path]::GetFilename($filepath)
        #$zippath = GetLocalFileFor -downloadUrl $downloadUrl -filename $filename
        $expectedFolderpath = (join-path -Path ($global:machinesetupconfig.MachineSetupConfigFolder) ('apps\{0}\' -f $filename))

        if(-not (test-path $expectedFolderpath)){
            EnsureFolderExists -path $expectedFolderpath | Write-Verbose
            # extract the folder to the directory
            & (Get7ZipPath) x -y "-o$expectedFolderpath" "$filepath" | Write-Verbose
        }        

        # return the path to the folder
        $expectedFolderpath
    }
}

function ConfigurePowershell{
    [cmdletbinding()]
    param(
        [string]$psProfilePath = $profile,
        [string]$sourceProfilePath,
        [string]$profileDownloadurl = 'https://www.dropbox.com/s/k1i3pkxzk2njvd5/sayed-profile-script-current.ps1?dl=0'
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
        [string]$photoviewerregdownloadurl = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/powershell/photo-viewer.reg'
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
            'Pin to taskbar with command: [{0} /pinsm {1}]' -f $pinTov2,$path | Write-Verbose
            & $pinTov2 /pintb $path
        }
    }
}

function PinToStartmenu{
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
            'Pin to startmenu with command: [{0} /pinsm {1}]' -f $pinTov2,$path | Write-Verbose
            & $pinTov2 /pinsm $path
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

function ConfigureWindows{
    [cmdletbinding()]
    param()
    begin{
        LoadBoxstarter
    }
    process{
        RunTask @(
            {Set-WindowsExplorerOptions -EnableShowFileExtensions},
            {Enable-RemoteDesktop},

            {AddFonts},
            {DisableScreenSaver},
            {
                $wppath = (GetLocalFileFor -downloadUrl $global:machinesetupconfig.WallpaperUrl -filename 'wp-view.jpg')
                Update-wallpaper -path $wppath -Style 'Fit'
            },

            {InstallPaintDotNet}   
        )

        # TODO: update mouse pointer speed

        # TODO: update mouse pointer to show when CTRL is clicked
    }
}

# http://www.getpaint.net/doc/latest/UnattendedInstallation.html
function InstallPaintDotNet(){
    [cmdletbinding()]
    param(
        [string]$downloadUrl = 'http://www.dotpdn.com/files/paint.net.4.0.13.install.zip',
        [string]$filename = 'paint.net.4.0.13.install.zip',
        [string]$installerRelPath = 'paint.net.4.0.13.install.exe'
    )
    process{        
        $extractfolder = ExtractRemoteZip -downloadUrl $downloadUrl -filename $filename
        $foo = 'bar'

        $installerexe = Join-Path $extractfolder $installerRelPath

        & $installerexe /auto DESKTOPSHORTCUT 1


    }
}

function DisableScreenSaver(){
    [cmdletbinding()]
    param(
        [string]$screenSaverDownloadUrl = 'https://github.com/sayedihashimi/sayed-tools/raw/master/contrib/ScreenSaverBlocker.exe'
    )
    process{
        'Copying ScreenSaverBlocker.exe to startup folder' | Write-Verbose
        $localexe = (GetLocalFileFor -downloadUrl $screenSaverDownloadUrl -filename 'ScreenSaverBlocker.exe')
        [string]$destPath = ("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ScreenSaverBlocker.exe")
        if(-not (test-path $destPath)){
            EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($destPath))
            Copy-Item -LiteralPath $localexe -Destination $destPath
            start $localexe
        }
    }
}

$global:machinesetupuserconfig = @{
    AddFontScriptUrl = 'powershell/Add-Font.ps1'
    Fonts = @(
        @{
            Filename = join-path -Path $scriptDir 'powershell/fonts/source-sans-pro-2.020R-ro-1.075R-it.zip'
            #DownloadUrl = 'https://github.com/adobe-fonts/source-sans-pro/archive/2.020R-ro/1.075R-it.zip'
            RelpathToFontsFolder = 'source-sans-pro-2.020R-ro-1.075R-it/TTF'
        }
        @{
            Filename = join-path -Path $scriptDir 'powershell/fonts/source-code-pro-2.030R-ro-1.050R-it.zip'
            #DownloadUrl = 'https://github.com/adobe-fonts/source-code-pro/archive/2.030R-ro/1.050R-it.zip'
            RelpathToFontsFolder = 'source-code-pro-2.030R-ro-1.050R-it/TTF'
        }
    )
}

function AddFonts{
    [cmdletbinding()]
    param(
        [Parameter(Position=1)]
        [string]$addFonthasrunpath = (Join-Path $global:machinesetupconfig.MachineSetupConfigFolder 'addfonts.hasrun'),

        [Parameter(Position=2)]
        [string]$addFontScriptUrl = ($global:machinesetupuserconfig.AddFontScriptUrl)
    )
    process{
        if(-not (test-path -path $addFonthasrunpath)){
            # get the Add-Font script
            $addFontScriptPath = (GetLocalFileFor -downloadUrl $addFontScriptUrl -filename 'add-font.ps1')

            foreach($font in $global:machinesetupuserconfig.Fonts){
                # extract it
                $extractfolder = ExtractLocalZip -filepath $font.Filename #ExtractRemoteZip -downloadUrl $font.Downloadurl -filename $font.Filename
                $pathtofiles = (join-path $extractfolder $font.RelpathToFontsFolder)
                if(test-path $pathtofiles){
                    # call the Add-Font script
                    Invoke-Expression "& `"$addFontScriptPath`" $pathtofiles"
                }
                else{
                    'Font files folder [{0}] found in extracted zip [{1}]' -f $pathtofiles, $extractfolder | Write-Warning
                }
            }

            CreateDummyFile -filepath $addFonthasrunpath
        }
        else{
            'Skipping font additions because of file [{0}]' -f $addFonthasrunpath | Write-Verbose 
        }
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

function RunTask{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [ScriptBlock[]]$task
    )
    process{
        foreach($t in $task){
            if($t -eq $null){
                continue
            }

            try{
                . $t
            }
            catch{
                'Error in task execution of [{0}]' -f $t | Write-Warning
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
        EnsureFolderExists ($global:machinesetupconfig.MachineSetupAppsFolder)

        InstallBaseApps
        
        RunTask @(
            {EnsurePhotoViewerRegkeyAdded},
            {ConfigureTaskBar},

            {ConfigureConsole},
            {ConfigureGit},
            {ConfigurePowershell},

            {EnsureBaseReposCloned},
            {LoadModules},
            {InstallSecondaryApps},

            {ConfigureWindows},
            {ConfigureVisualStudio},
            {ConfigureApps}            
        )
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
    if($runscript -eq $true){
        ConfigureMachine
    }
}
finally{
    Pop-Location
}

# TODO:
# Remove dependency on boxstarter
# Update firefox to not check default browser
# Update firefox to set google as default search
