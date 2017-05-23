[cmdletbinding()]
param()

function Test-IsWindows{
    [cmdletbinding()]
    param()
    process{
        -not ($IsLinux -or $IsOSX)
    }
}
New-Alias -Name IsWindows -Value Test-IsWindows

function Test-IsLinuxOrMac{
    [cmdletbinding()]
    param()
    process{
        ($IsLinux -or $IsOSX)
    }
}
New-Alias -Name IsLinuxOrMac -Value Test-IsLinuxOrMac

$Global:isLinuxOrMac = (Test-IsLinuxOrMac)

function Test-Command{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [string]$command
    )
    process{
        [bool]$exists = $false
        try{
            if( (get-command $command -ErrorAction SilentlyContinue)) {
                $exists = $true
            }
        }
        catch{
            $exists = $false
        }

        $exists
    }
}
Set-Alias -Name CommandExists -Value Test-Command

function Test-Alias{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$name
    )
    process{
        foreach($n in $name){
            if( (Get-Alias -Name $n -ErrorAction SilentlyContinue) ){
                $true
            }
            else{
                $false
            }
        }
    }
}

<#
.SYNOPSIS
    You can add this to you build script to ensure that psbuild is available before calling
    Invoke-MSBuild. If psbuild is not available locally it will be downloaded automatically.
#>
function Resolve-FullPath{
    [cmdletbinding()]
    param
    (
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]] $path
    )
    process{
        foreach($p in $path){
            if(-not ([string]::IsNullOrWhiteSpace($p))){
                $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
            }
        }
    }
}
New-Alias -Name GetFullPath -Value Resolve-FullPath
New-Alias -Name Get-NormalizedPath -Value Resolve-FullPath
New-Alias -Name Get-FullPathNormalized -Value Resolve-FullPath
New-Alias -Name Get-Fullpath -Value Resolve-FullPath

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

function Get-MachineName{
    [cmdletbinding()]
    param()
    process{
        if($isLinuxOrMac){
            scutil --get LocalHostName
        }
        else{
            $env:ComputerName
        }
    }
}

function Get-IPInfo{
    [cmdletbinding()]
    param()
    process{
        if($isLinuxOrMac){
            ifconfig | grep inet
        }
        else{
            ipconfig
        }
    }
}
if($isLinuxOrMac){
    Set-Alias -Name ipconfig -Value Get-IPInfo
}

function Save-MachineInfo{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$outfile
    )
    process{
        $fullpath = (Get-NormalizedPath -Path $outfile)

        if(-not ([string]::IsNullOrWhiteSpace($fullpath))){
            $dir = Split-Path -Path $fullpath -Parent
            if(-not (Test-Path -Path $dir)){
                New-Item -Path $dir -ItemType Directory
            }

            Get-IPInfo | Out-File -FilePath $fullpath -Encoding ascii
        }
    }
}

function SayedConfigureSaveMachineInfoJob{
    [cmdletbinding()]
    param(
        [int]$sleepSeconds = (60),
        [string]$pathToCheck = (Get-FullPathNormalized -path (Join-Path $Global:dropboxhome 'Personal/PcSettings/Powershell/MachineInfo/create.txt')),
        [string]$toolsModulePath = $PSCommandPath,
        [switch]$asJob
    )
    process{
        [string]$machineName = (Get-MachineName)
        [string]$outfilepath = (Get-FullPathNormalized -path (Join-Path $Global:dropboxhome ('Personal/PcSettings/Powershell/MachineInfo/{0}.txt' -f $machineName)))
# create a script block that will run every 5 min
        [scriptblock]$saveMachineScript = {
            [cmdletbinding()]
            param(
                [Parameter(Mandatory = $true,Position=0)]
                [string]$machineName,
                [Parameter(Mandatory = $true,Position=1)]
                [string]$outfilepath,
                [Parameter(Mandatory = $true,Position=2)]
                [int]$sleepSeconds,
                [Parameter(Mandatory = $true,Position=3)]
                [string]$keyFilePath,
                [Parameter(Mandatory = $true,Position=4)]
                [string]$toolsModulePath
            )

            if( (get-command -Name Save-MachineInfo -ErrorAction SilentlyContinue) -eq $null){
                Import-Module $toolsModulePath -Global -DisableNameChecking
            }

            [bool]$continueScript = $true

            while($continueScript -eq $true){
                try{
                    if(Test-Path $keyFilePath){
                        'Saving machine info to file [{0}]' -f $outfilepath | Write-Output
                        Save-MachineInfo -outfile $outfilepath
                    }
                    else{
                        'Skipping, no file found at [{0}]' -f $keyFilePath | Write-Output
                    }
                }
                catch{
                    Write-Output -InputObject $_.Exception
                }

                'Sleeping for [{0}] seconds' -f $sleepSeconds | Write-Verbose
                Start-Sleep -Seconds $sleepSeconds
            }
            
        }
        if($asJob -eq $true){
            'Starting SaveMachineInfo as Job' | Write-Output
            Start-Job -ScriptBlock $saveMachineScript -Name 'SaveMachineInfo' -ArgumentList @($machineName,$outfilepath,$sleepSeconds,$pathToCheck,$toolsModulePath)
        }
        else{
            'Starting SaveMachineInfo as script' | Write-Output
            & $saveMachineScript $machineName $outfilepath $sleepSeconds $pathToCheck $toolsModulePath
        }
    }
}

######################################
# Windows specific below
######################################
if(Test-IsWindows){
    <#
    .SYNOPSIS
        You can add this to you build script to ensure that psbuild is available before calling
        Invoke-MSBuild. If psbuild is not available locally it will be downloaded automatically.
    #>
    function EnsurePsbuildInstlled{
        [cmdletbinding()]
        param(
            # TODO: Change to master when 1.1.9 gets there
            [string]$psbuildInstallUri = 'https://raw.githubusercontent.com/ligershark/psbuild/dev/src/GetPSBuild.ps1',

            [System.Version]$minVersion = (New-Object -TypeName 'system.version' -ArgumentList '1.1.9.1')
        )
        process{
            # see if there is already a version loaded
            $psbuildNeedsInstall = $true
            [System.Version]$installedVersion = $null
            try{
                Import-Module psbuild -ErrorAction SilentlyContinue | Out-Null
                $installedVersion = Get-PSBuildVersion
            }
            catch{
                $installedVersion = $null
            }

            if( ($installedVersion -ne $null) -and ($installedVersion.CompareTo($minVersion) -ge 0) ){
                'Skipping psbuild install because version [{0}] detected' -f $installedVersion.ToString() | Write-Verbose
            }
            else{
                'Installing psbuild from [{0}]' -f $psbuildInstallUri | Write-Verbose
                (new-object Net.WebClient).DownloadString($psbuildInstallUri) | iex

                # make sure it's loaded and throw if not
                if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
                    throw ('Unable to install/load psbuild from [{0}]' -f $psbuildInstallUri)
                }
            }
        }
    }

    function EnsureFileReplacerInstlled{
        [cmdletbinding()]
        param()
        begin{
            EnsurePsbuildInstlled
            Import-NuGetPowershell
        }
        process{
            if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
                $fpinstallpath = (Get-NuGetPackage -name file-replacer -version '0.4.0-beta' -binpath)
                if(-not (Test-Path $fpinstallpath)){ throw ('file-replacer folder not found at [{0}]' -f $fpinstallpath) }
                Import-Module (Join-Path $fpinstallpath 'file-replacer.psm1') -DisableNameChecking
            }

            # make sure it's loaded and throw if not
            if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
                throw ('Unable to install/load file-replacer')
            }
        }
    }

    function Update-FilesWithCommitId{
        [cmdletbinding()]
        param(
            [string]$commitId = ($env:APPVEYOR_REPO_COMMIT),

            [System.IO.DirectoryInfo]$dirToUpdate = ($outputroot),

            [Parameter(Position=2)]
            [string]$filereplacerVersion = '0.4.0-beta'
        )
        begin{
            EnsureFileReplacerInstlled
        }
        process{
            if([string]::IsNullOrEmpty($commitId)){
                try{
                    $commitstr = (& git log --format="%H" -n 1)
                    if($commitstr -match '\b[0-9a-f]{5,40}\b'){
                        $commitId = $commitstr
                    }
                }
                catch{
                    # do nothing
                }
            }

            if(![string]::IsNullOrWhiteSpace($commitId)){
                'Updating commitId from [{0}] to [{1}]' -f '$(COMMIT_ID)',$commitId | Write-Verbose

                $folder = $dirToUpdate
                $include = '*.nuspec'
                # In case the script is in the same folder as the files you are replacing add it to the exclude list
                $exclude = "$($MyInvocation.MyCommand.Name);"
                $replacements = @{
                    '$(COMMIT_ID)'="$commitId"
                }
                Replace-TextInFolder -folder $folder -include $include -exclude $exclude -replacements $replacements | Write-Verbose
                'Replacement complete' | Write-Verbose
            }
        }
    }

    function Open-StartupFolder{
        [cmdletbinding()]
        param()
        process{
            start 'shell:startup'
        }
    }
    # taken from http://www.theagreeablecow.com/2014/09/set-desktop-wallpaper-using-powershell.html
    Function Update-Wallpaper {
        Param(
            [Parameter(Mandatory=$true)]
            $Path,
            
            [ValidateSet('Center','Stretch','Fill','Tile','Fit')]
            $Style = 'Fit'
        )
        if(-not (test-path -Path $Path -PathType Leaf)){
            'File not found at [{0}]' -f $Path | Write-error
            break
        }
        Try {
            if (-not ([System.Management.Automation.PSTypeName]'Wallpaper.Setter').Type) {
                Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            using Microsoft.Win32;
            namespace Wallpaper {
                public enum Style : int {
                    Center, Stretch, Fill, Fit, Tile
                }
                public class Setter {
                    public const int SetDesktopWallpaper = 20;
                    public const int UpdateIniFile = 0x01;
                    public const int SendWinIniChange = 0x02;
                    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
                    private static extern int SystemParametersInfo (int uAction, int uParam, string lpvParam, int fuWinIni);
                    public static void SetWallpaper ( string path, Wallpaper.Style style ) {
                        SystemParametersInfo( SetDesktopWallpaper, 0, path, UpdateIniFile | SendWinIniChange );
                        RegistryKey key = Registry.CurrentUser.OpenSubKey("Control Panel\\Desktop", true);
                        switch( style ) {
                            case Style.Tile :
                                key.SetValue(@"WallpaperStyle", "0") ; 
                                key.SetValue(@"TileWallpaper", "1") ; 
                                break;
                            case Style.Center :
                                key.SetValue(@"WallpaperStyle", "0") ; 
                                key.SetValue(@"TileWallpaper", "0") ; 
                                break;
                            case Style.Stretch :
                                key.SetValue(@"WallpaperStyle", "2") ; 
                                key.SetValue(@"TileWallpaper", "0") ;
                                break;
                            case Style.Fill :
                                key.SetValue(@"WallpaperStyle", "10") ; 
                                key.SetValue(@"TileWallpaper", "0") ; 
                                break;
                            case Style.Fit :
                                key.SetValue(@"WallpaperStyle", "6") ; 
                                key.SetValue(@"TileWallpaper", "0") ; 
                                break;
}
                        key.Close();
                    }
                }
            }
"@ -ErrorAction Stop 
                } 
            } 
            Catch {
                Write-Warning -Message "Wallpaper not changed because $($_.Exception.Message)"
            }
        [Wallpaper.Setter]::SetWallpaper( $Path, $Style )
    }


}

function Ensure-DirectoryExists{
    param([Parameter(Position=0)][System.IO.DirectoryInfo]$path)
    process{
        if($path -ne $null){
            if(-not (Test-Path $path.FullName)){
                New-Item -Path $path.FullName -ItemType Directory
            }
        }
    }
}


function Get-VisualStudioGitAttributes{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.IO.FileInfo[]]$destination = (join-path $PWD '.gitattributes'),
        $sourceUri = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/.gitattributes'
        
    )
    process{
        $webresult = (Invoke-WebRequest -Uri $sourceUri).Content

        if(-not [string]::IsNullOrEmpty($destination)){
            foreach($dest in $destination){
               $dest = (Get-NormalizedPath -path $dest)

                if( ((test-path $dest) -eq $true) -and (get-item $dest -ErrorAction SilentlyContinue).PSIsContainer -eq $true ){
                    $dest = (Join-Path $dest '.gitignore')
                }

                "dest: [$dest]" | Write-Verbose

                $webresult | Out-File $dest -Encoding ascii
            }
        }
        else{
                # return the result as a string
                $webresult
        }
    }    
}

function Get-VisualStudioGitIgnore{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.IO.FileInfo[]]$destination = (join-path $PWD '.gitignore'),
        $sourceUri = 'https://raw.githubusercontent.com/github/gitignore/master/VisualStudio.gitignore'
        
    )
    process{
        $webresult = (Invoke-WebRequest -Uri $sourceUri).Content

        if(-not [string]::IsNullOrEmpty($destination)){
            foreach($dest in $destination){
                $dest = (Get-NormalizedPath -path $dest)

                if( ((test-path $dest) -eq $true) -and (get-item $dest -ErrorAction SilentlyContinue).PSIsContainer -eq $true ){
                    $dest = (Join-Path $dest '.gitignore')
                }
                
                "dest: [$dest]" | Write-Verbose

                $webresult | Out-File $dest -Encoding ascii | Write-Verbose
            }
        }
        else{
            # return the result as a string
                $webresult
        }
    }
}

function New-LoremIpsum{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ParameterSetName='words')]
        [int]$numWords,
        [Parameter(Position=0,ParameterSetName='para')]
        [int]$numParagraphs,
        [Parameter(Position=0,ParameterSetName='bytes')]
        [int]$numBytes,
        [Parameter(Position=0,ParameterSetName='lists')]
        [int]$numLists
    )
    process{
        # http://www.lipsum.com/feed/xml?amount=1&what=words&start=yes&quot;
        [string]$baseUrl = 'http://www.lipsum.com/feed/xml?start=yes&quot;'
        [string]$result = ''
        [string]$what = ''
        [string]$count = ''
        
        if($numWords -gt 0){
            $what = 'words'
            $num = $numWords
        }
        elseif($numParagraphs -gt 0){
            $what = 'paras'
            $num = $numParagraphs
        }
        elseif($numBytes -gt 0){
            $what = 'bytes'
            $num = $numBytes
        }
        elseif($numLists -gt 0){
            $what = 'lists'
            $num = $numLists
        }
        else{
            throw ('numWords, numParagraphs, numBytes or numLists must be greater than 0')
        }

        $url = ('{0}&what={1}&amount={2}' -f $baseUrl,$what,$num)
        [xml]$result = Invoke-WebRequest -uri $url
        [string]$text = ($result.feed.lipsum.Trim("`n").Trim("`r").Trim())

        $text

        if( (CommandExists clip)){
            $text | clip
            "`r`n >>>>> generated content is on the clip board" | Write-Output

        }
    }
}
Set-Alias -Name LoremIpsum -Value New-LoremIpsum

function Install-PowerShellCookbook{
    [cmdletbinding()]
    param()
    process{
        Install-Module -Name PowerShellCookbook -Force
    }
}

function Sayed-ConfigureGit{
    [cmdletbinding()]
    param()
    process{
        & git config --global user.name 'Sayed Ibrahim Hashimi'
        & git config --global user.email 'sayed.hashimi@gmail.com'

        & git config --global color.status.changed "cyan normal bold"
        & git config --global color.status.untracked "cyan normal bold"
        & git config --global color.diff.old "red normal bold"
        & git config --global color.diff.new "green normal bold"

        & git config --global core.autocrlf "true"

        & git config --global push.default "matching"

        
        # TODO: Ensure this works for windows/mac before adding
        # & git config --global merge.keepBackup "false"
        # & git config --global merge.tool "p4merge"
        # & git config --global mergetool.p4merge.cmd 'p4merge.exe \"$BASE\" \"$LOCAL\" \"$REMOTE\" \"$MERGED\"'
        # & git config --global mergetool.p4merge.keepTemporaries 'false'
        # & git config --global mergetool.p4merge.trustExitCode 'false'
        # & git config --global mergetool.p4merge.keepBackup 'false'
    }
}