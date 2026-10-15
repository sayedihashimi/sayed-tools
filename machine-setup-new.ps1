[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [bool]$initializeScript = $true,

    [Parameter(Position=1)]
    [string]$pcSettingsDirPath,

    [Parameter(Position=2)]
    [string]$pathToSettingsVhdxFile,

    [Parameter(Position=3)]
    [securestring]$settingsVhdxFilePassword,

    [Parameter(Position=4)]
    [string]$settingsVhdxDriveLetter = "X"
)

#region Global Variables
$global:pcSettingsDirPath = $pcSettingsDirPath
$global:pathToSettingsVhdxFile = $pathToSettingsVhdxFile
[securestring]$global:settingsVhdxFilePassword = $settingsVhdxFilePassword
$global:settingsVhdxDriveLetter = $settingsVhdxDriveLetter
$global:tempdir = "C:\temp\machine-setup"
$global:tempSettingsVhdxFile = (Join-Path $global:tempdir 'settings.vhdx')
$global:gitexepath = "C:\Program Files\Git\bin\git.exe"
$global:p4mergepath = "C:\Program Files\Perforce\p4merge.exe"
$global:ps7Exepath = "C:\Program Files\PowerShell\7\pwsh.exe"
$global:mountedVhdx = $false
$global:codehome = 'c:\data\mycode'

if ([string]::IsNullOrWhiteSpace($global:codehome)) {
    '$global:codehome is empty, it is required' | Write-Error
    return
}

$global:sayedhaToolsFolderPath = Join-Path $global:codehome 'sayed-tools'
#endregion

#region Script Directory
function InternalGet-ScriptDirectory {
    Split-Path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}

$scriptDir = ((InternalGet-ScriptDirectory) + "\")
#endregion

#region Utility Functions
function Get-Fullpath {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $path,
        $workingDir = ($pwd)
    )
    process {
        $oldDirectory = [Environment]::CurrentDirectory
        Push-Location
        try {
            Set-Location -LiteralPath $workingDir -ErrorAction Stop
            [Environment]::CurrentDirectory = $pwd.ProviderPath
            [System.IO.Path]::GetFullPath($path)
        }
        finally {
            Pop-Location
            [Environment]::CurrentDirectory = $oldDirectory
        }
    }
}

function Add-Path {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)][string[]]$pathToAdd,
        [EnvironmentVariableTarget]$envTarget = [EnvironmentVariableTarget]::Process,
        [bool]$alsoAddToProcess = $true,
        [switch]$persist = $false
    )
    process {
        if ($persist -and $env:OS -ne 'Windows_NT') { throw 'Persistent machine PATH changes require Windows.' }
        $targets = @($envTarget)
        if ($alsoAddToProcess) { $targets += [EnvironmentVariableTarget]::Process }
        if ($persist) { $targets += [EnvironmentVariableTarget]::Machine }
        foreach ($item in $pathToAdd) {
            if ([string]::IsNullOrWhiteSpace($item)) { continue }
            $directory = Get-Fullpath $item
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) { Write-Warning "PATH directory not found: $directory"; continue }
            $separator = [IO.Path]::PathSeparator
            $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
            foreach ($target in ($targets | Select-Object -Unique)) {
                $current = [Environment]::GetEnvironmentVariable('PATH', $target)
                $entries = @($current -split [regex]::Escape([string]$separator) | Where-Object { $_ })
                $found = $false
                foreach ($entry in $entries) {
                    if ([string]::Equals($entry.TrimEnd('\', '/'), $directory.TrimEnd('\', '/'), $comparison)) { $found = $true; break }
                }
                if (-not $found) {
                    [Environment]::SetEnvironmentVariable('PATH', ((@($entries) + $directory) -join $separator), $target)
                }
            }
        }
    }
}

function Get7ZipPath {
    [cmdletbinding()]
    param()
    process {
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe')
    }
}

function EnsureFolderExists {
    [cmdletbinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [string[]]$path
    )
    process {
        foreach ($p in $path) {
            if (-not [string]::IsNullOrWhiteSpace($p) -and (-not (Test-Path $p))) {
                New-Item -Path $p -ItemType Directory
            }
        }
    }
}

function IsCommandAvailable {
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        $command
    )
    process {
        $foundcmd = (Get-Command $command -ErrorAction SilentlyContinue)
        [bool]($null -ne $foundcmd)
    }
}

function CreateDummyFile {
    [cmdletbinding()]
    param(
        [string[]]$filepath
    )
    process {
        foreach ($path in $filepath) {
            if ((-not ([string]::IsNullOrWhiteSpace($path))) -and (-not (Test-Path -Path $path))) {
                EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($path))
                Set-Content -Value 'empty file' -Path $path
            }
        }
    }
}

function IsRunningAsAdmin {
    [cmdletbinding()]
    param()
    process {
        [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
    }
}
#endregion

#region Configuration
$global:machinesetupconfig = @{
    MachineSetupConfigFolder = (Join-Path $env:temp 'SayedHaMachineSetup')
    MachineSetupAppsFolder   = (Join-Path $env:temp 'SayedHaMachineSetup\apps')
    BaseRepos                = @(
        @{ SSH = 'git@github.com:sayedihashimi/sayed-tools.git';       HTTPS = 'https://github.com/sayedihashimi/sayed-tools.git' }
        @{ SSH = 'git@github.com:sayedihashimi/sayedha.commands.git';  HTTPS = 'https://github.com/sayedihashimi/sayedha.commands.git' }
        @{ SSH = 'git@github.com:sayedihashimi/pshelpers.git';         HTTPS = 'https://github.com/sayedihashimi/pshelpers.git' }
    )
    WallpaperUrl      = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/powershell/checking-out-the-view.jpg'
    WallpaperFilepath = (Join-Path -Path $global:sayedhaToolsFolderPath 'powershell/checking-out-the-view.jpg')
}

# Winget apps to install: ID => display name (for logging)
$global:wingetApps = [ordered]@{
    'Google.Chrome'              = 'Google Chrome'
    'Git.Git'                    = 'Git'
    'Mozilla.Firefox'            = 'Mozilla Firefox'
    'Notepad++.Notepad++'        = 'Notepad++'
    'Maximus5.ConEmu'            = 'ConEmu'
    '7zip.7zip'                  = '7-Zip'
    'Perforce.P4Merge'           = 'P4Merge'
    'KDE.KDiff3'                 = 'KDiff3'
    'Balsamiq.Wireframes'        = 'Balsamiq Wireframes'
    'voidtools.Everything'       = 'Everything'
    'dotPDN.PaintDotNet'         = 'Paint.NET'
    'AutoHotkey.AutoHotkey'      = 'AutoHotkey'
    'Microsoft.PowerToys'        = 'PowerToys'
    'Microsoft.VisualStudioCode' = 'VS Code'
    'Winamp.Winamp'              = 'Winamp'
    'OBSProject.OBSStudio'       = 'OBS Studio'
    'JanDeDobbeleer.OhMyPosh'    = 'Oh My Posh'
    'ajeetdsouza.zoxide'        = 'zoxide'
    'OpenJS.NodeJS.LTS'          = 'Node.js LTS (includes npm)'
    'SublimeHQ.SublimeText.4'   = 'Sublime Text'
    'Microsoft.VisualStudioCode.Insiders' = 'VS Code Insiders'
    'TechSmith.Snagit.2023'      = 'Snagit 2023'
}

$global:machinesetupuserconfig = @{
    AddFontScriptUrl = Join-Path $global:sayedhaToolsFolderPath 'powershell/Add-Font.ps1'
    Fonts            = @(
        @{
            Filename            = Join-Path -Path $global:sayedhaToolsFolderPath 'powershell/fonts/source-sans-pro-2.020R-ro-1.075R-it.zip'
            RelpathToFontsFolder = 'source-sans-pro-2.020R-ro-1.075R-it/TTF'
        }
        @{
            Filename            = Join-Path -Path $global:sayedhaToolsFolderPath 'powershell/fonts/source-code-pro-2.030R-ro-1.050R-it.zip'
            RelpathToFontsFolder = 'source-code-pro-2.030R-ro-1.050R-it/TTF'
        }
    )
}
#endregion

#region Parameter Prompting
function Prompt-ForParameters {
    [cmdletbinding()]
    param()
    process {
        if ([string]::IsNullOrEmpty($global:pcSettingsDirPath)) {
            $global:pcSettingsDirPath = Read-Host -Prompt 'Path to pcsettings folder'
            $global:pcSettingsDirPath = $global:pcSettingsDirPath.Trim('"').Trim("'")
        }

        if ([string]::IsNullOrEmpty($global:pathToSettingsVhdxFile)) {
            $expectedPath = Get-FullPath (Join-Path -Path $global:pcSettingsDirPath 'sayedha-settings.vhdx')
            if (Test-Path $expectedPath) {
                $global:pathToSettingsVhdxFile = $expectedPath
            }
            else {
                'Settings VHDX not found at "{0}", prompting for the path' -f $expectedPath | Write-Output
                $global:pathToSettingsVhdxFile = Read-Host -Prompt 'Enter the path to the settings.vhdx file'
                $global:pathToSettingsVhdxFile = $global:pathToSettingsVhdxFile.Trim('"').Trim("'")
            }
        }

        if (-not $settingsVhdxFilePassword) {
            $global:settingsVhdxFilePassword = Read-Host -Prompt 'Enter the password for the settings.vhdx file' -AsSecureString
        }

        if (-not (Test-Path $global:pcSettingsDirPath)) {
            'pcsettings folder not found at "{0}"' -f $global:pcSettingsDirPath | Write-Error
        }
        if (-not (Test-Path $global:pathToSettingsVhdxFile)) {
            'VHDX file not found at "{0}"' -f $global:pathToSettingsVhdxFile | Write-Error
        }
    }
}
#endregion

#region Winget Installation
function Install-Winget {
    [cmdletbinding()]
    param()
    process {
        $progressPreference = 'silentlyContinue'
        Write-Host "Installing WinGet PowerShell module from PSGallery..."
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
        Write-Host "Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet..."
        Repair-WinGetPackageManager
        Write-Host "Done."
    }
}

function Install-WingetApp {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$id,

        [string]$name
    )
    process {
        $displayName = if ($name) { $name } else { $id }
        Write-Host "Installing $displayName..." -ForegroundColor Cyan

        $result = winget install -e --id $id --source winget --accept-source-agreements --accept-package-agreements 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-Host "  ✓ $displayName installed successfully" -ForegroundColor Green
        }
        elseif ($result -match 'already installed') {
            Write-Host "  ✓ $displayName is already installed" -ForegroundColor DarkGreen
        }
        else {
            Write-Host "  ✗ $displayName install failed (exit code: $exitCode)" -ForegroundColor Yellow
            $result | Write-Verbose
        }
    }
}

function Install-WingetApps {
    [cmdletbinding()]
    param()
    process {
        Write-Host "`n=== Installing Winget Apps ===" -ForegroundColor Magenta

        foreach ($entry in $global:wingetApps.GetEnumerator()) {
            Install-WingetApp -id $entry.Key -name $entry.Value
        }

        # Add git and p4merge to the PATH
        if (Test-Path $global:gitexepath) {
            Add-Path -pathToAdd ([System.IO.Path]::GetDirectoryName($global:gitexepath)) -envTarget User
        }
        if (Test-Path $global:p4mergepath) {
            Add-Path -pathToAdd ([System.IO.Path]::GetDirectoryName($global:p4mergepath)) -envTarget User
        }

        Write-Host "=== Winget Apps Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region npm Global Packages
function Install-NpmGlobalPackages {
    [cmdletbinding()]
    param()
    process {
        Write-Host "`n=== Installing npm Global Packages ===" -ForegroundColor Magenta

        # Refresh PATH so npm is available after Node.js install
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

        if (IsCommandAvailable 'npm') {
            Write-Host "Installing GitHub Copilot CLI..." -ForegroundColor Cyan
            npm install -g @githubnext/github-copilot-cli
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ GitHub Copilot CLI installed successfully" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ GitHub Copilot CLI install failed" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  npm not found in PATH, skipping npm global packages" -ForegroundColor Yellow
        }

        Write-Host "=== npm Global Packages Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region Prompt / Shell Setup
function Install-Prompt {
    [cmdletbinding()]
    param()
    process {
        Write-Host "`n=== Configuring Shell Prompt ===" -ForegroundColor Magenta

        # PSReadLine
        if (-not (Get-Module -ListAvailable -Name PSReadLine)) {
            Write-Host "Installing PSReadLine..." -ForegroundColor Cyan
            PowerShellGet\Install-Module -Name PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck
        }
        else {
            Write-Host "  ✓ PSReadLine already installed" -ForegroundColor DarkGreen
        }

        # Oh My Posh should already be installed via winget, just update
        if (IsCommandAvailable 'oh-my-posh') {
            Write-Host "Installing Meslo font via Oh My Posh..." -ForegroundColor Cyan
            oh-my-posh font install meslo
        }
        else {
            Write-Host "  oh-my-posh not found in PATH, skipping font install" -ForegroundColor Yellow
        }

        Write-Host "=== Shell Prompt Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region File Download & Extraction
function GetLocalFileFor {
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,

        [Parameter(Position=2)]
        [string]$downloadRootDir = $global:machinesetupconfig.MachineSetupConfigFolder
    )
    process {
        $expectedPath = (Join-Path $downloadRootDir $filename)

        if (-not (Test-Path $expectedPath)) {
            EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($expectedPath)) | Out-Null
            'Downloading file "{0}"' -f $downloadUrl | Write-Output
            Invoke-WebRequest -Uri $downloadUrl -OutFile $expectedPath | Out-Null
        }

        if (-not (Test-Path $expectedPath)) {
            throw ('Unable to download file from [{0}] to [{1}]' -f $downloadUrl, $expectedPath)
        }

        $expectedPath
    }
}

function ExtractLocalZip {
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$filepath
    )
    process {
        $filename = [System.IO.Path]::GetFilename($filepath)
        $expectedFolderpath = (Join-Path -Path ($global:machinesetupconfig.MachineSetupConfigFolder) ('apps\{0}\' -f $filename))

        if (-not (Test-Path $expectedFolderpath)) {
            EnsureFolderExists -path $expectedFolderpath | Write-Verbose
            $sevenZip = Get7ZipPath
            if (Test-Path $sevenZip) {
                & $sevenZip x -y "-o$expectedFolderpath" "$filepath" | Write-Verbose
            }
            else {
                # Fallback to built-in Expand-Archive
                Write-Verbose "7-Zip not found, using Expand-Archive"
                Expand-Archive -Path $filepath -DestinationPath $expectedFolderpath -Force
            }
        }

        $expectedFolderpath
    }
}
#endregion

#region VHD Mount/Unmount
function Mount-SettingsVirtualHardDrive {
    [cmdletbinding()]
    param()
    process {
        $driveLetter = "{0}:" -f $global:settingsVhdxDriveLetter
        if (Test-Path $driveLetter) {
            'Settings drive already mounted' | Write-Output
            return
        }

        if (Test-Path ($global:pathToSettingsVhdxFile)) {
            if ([string]::IsNullOrWhiteSpace($global:settingsVhdxFilePassword)) {
                '** Settings VHDX file password not provided' | Write-Warning
                return
            }
            if ([string]::IsNullOrWhiteSpace($global:settingsVhdxDriveLetter)) {
                $settingsVhdxDriveLetter = 'X'
            }

            'Copying settings VHDX to temp folder to mount it' | Write-Output
            EnsureFolderExists -path $global:tempdir
            Copy-Item -LiteralPath $global:pathToSettingsVhdxFile -Destination $global:tempSettingsVhdxFile -Force

            'Mounting virtual hard drive at "{0}"' -f $global:tempSettingsVhdxFile | Write-Output
            @"
select vdisk file="{0}"
attach vdisk
select volume 1
assign letter={1}
"@ -f $global:tempSettingsVhdxFile, $settingsVhdxDriveLetter | diskpart

            Start-Sleep -Seconds 5
            $volume = Get-BitLockerVolume -MountPoint $driveLetter
            'Unlocking settings drive with BitLocker' | Write-Output
            Unlock-BitLocker -MountPoint $volume.MountPoint -Password $global:settingsVhdxFilePassword
            $global:mountedVhdx = $true
        }
        else {
            '** Settings VHDX file not found at {0}' -f $global:pathToSettingsVhdxFile | Write-Warning
        }
    }
}

function Unmount-SettingsVirtualHardDrive {
    [cmdletbinding()]
    param()
    process {
        if ($global:mountedVhdx -ne $true) {
            return
        }

        if (Test-Path ($global:tempSettingsVhdxFile)) {
            @"
select vdisk file="{0}"
detach vdisk
"@ -f $global:tempSettingsVhdxFile | diskpart
        }
        else {
            'Unable to dismount VHDX. File not found at "{0}"' -f $global:tempSettingsVhdxFile | Write-Output
        }
    }
}
#endregion

#region Git Configuration
function ConfigureGit {
    [cmdletbinding()]
    param()
    process {
        Write-Host "`n=== Configuring Git ===" -ForegroundColor Magenta

        $sshfolderpath = "$HOME\.ssh"
        if (-not (Test-Path $sshfolderpath -PathType Container)) {
            Mount-SettingsVirtualHardDrive
            'Copying .ssh folder to "{0}"' -f $sshfolderpath | Write-Output
            Copy-Item -Path "X:\.ssh" -Destination $sshfolderpath -Recurse -Force
        }
        else {
            '.ssh folder exists at "{0}", not copying' -f $sshfolderpath | Write-Output
        }

        if (-not (Test-Path -Path "$HOME\.gitconfig")) {
            'Copying .gitconfig to "{0}"' -f "$HOME\.gitconfig" | Write-Output
            Copy-Item -LiteralPath "X:\.gitconfig" -Destination "$HOME\.gitconfig" -Force
        }
        else {
            '.gitconfig exists at "{0}", not copying' -f "$HOME\.gitconfig" | Write-Output
        }

        Start-Sleep -Seconds 2
        Unmount-SettingsVirtualHardDrive

        Write-Host "=== Git Configuration Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region Repo Cloning
function EnsureBaseReposCloned {
    [cmdletbinding()]
    param()
    process {
        Write-Host "`n=== Cloning Base Repos ===" -ForegroundColor Magenta

        foreach ($repo in $global:machinesetupconfig.BaseRepos) {
            if ($null -eq $repo) { continue }

            $sshurl = $repo.SSH
            $httpsurl = $repo.HTTPS

            if ([string]::IsNullOrWhiteSpace($sshurl)) { continue }

            $reponame = $sshurl.Substring(
                $sshurl.LastIndexOf('/') + 1,
                ($sshurl.LastIndexOf('.git') - ($sshurl.LastIndexOf('/') + 1))
            )

            $dest = (Join-Path $global:codehome $reponame)
            if (-not (Test-Path $dest)) {
                Push-Location
                try {
                    Set-Location $global:codehome
                    $sshfolder = (Join-Path $env:USERPROFILE '.ssh')

                    if (Test-Path $sshfolder) {
                        'Cloning [{0}] with SSH' -f $reponame | Write-Output
                        & $global:gitexepath clone $sshurl
                    }
                    else {
                        'Cloning [{0}] with HTTPS' -f $reponame | Write-Output
                        & $global:gitexepath clone $httpsurl
                    }
                }
                finally {
                    Pop-Location
                }
            }
            else {
                '  ✓ {0} already cloned' -f $reponame | Write-Host -ForegroundColor DarkGreen
            }
        }

        Write-Host "=== Repo Cloning Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region Console Configuration
function ConfigureConsole {
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$conemuxmlSourceFile = (Get-Fullpath (Join-Path -path $global:sayedhaToolsFolderPath 'dotfiles/ConEmu.xml')),
        [Parameter(Position=1)]
        [string]$conemulocalpath = (Join-Path $env:APPDATA 'conemu.xml')
    )
    process {
        Write-Host "`n=== Configuring Console ===" -ForegroundColor Magenta

        EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($conemulocalpath))
        if (Test-Path $conemuxmlSourceFile) {
            if (-not (Test-Path $conemulocalpath)) {
                Copy-Item -LiteralPath $conemuxmlSourceFile -Destination $conemulocalpath -Force
                Write-Host "  ✓ ConEmu config copied" -ForegroundColor Green
            }
            else {
                Write-Host "  ✓ ConEmu config already exists" -ForegroundColor DarkGreen
            }
        }
        else {
            'ConEmu config file not found at "{0}"' -f $conemuxmlSourceFile | Write-Warning
        }

        # Terminal-Icons module
        if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
            Write-Host "Installing Terminal-Icons module..." -ForegroundColor Cyan
            Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -SkipPublisherCheck
        }
        else {
            Write-Host "  ✓ Terminal-Icons already installed" -ForegroundColor DarkGreen
        }
        Import-Module -Name Terminal-Icons

        Write-Host "=== Console Configuration Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region PowerShell Profile
function ConfigurePowershell {
    [cmdletbinding()]
    param(
        [string]$psProfilePath = $profile,
        [string]$sourceProfilePath
    )
    process {
        Write-Host "`n=== Configuring PowerShell Profile ===" -ForegroundColor Magenta

        if ([string]::IsNullOrWhiteSpace($sourceProfilePath)) {
            $sourceProfilePath = Join-Path $global:sayedhaToolsFolderPath 'powershell/profile.ps1'
            if (-not (Test-Path -LiteralPath $sourceProfilePath -PathType Leaf) -and $global:pcSettingsDirPath) {
                $sourceProfilePath = Join-Path $global:pcSettingsDirPath 'powershell/sayed-profile-script-current.ps1'
            }
        }

        if (-not (Test-Path $psProfilePath)) {
            if (Test-Path $sourceProfilePath) {
                'Copying PowerShell profile to [{0}]' -f $psProfilePath | Write-Output
                $profileDirectory = Split-Path -Parent $psProfilePath
                if ($profileDirectory -and -not (Test-Path -LiteralPath $profileDirectory)) {
                    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
                }
                Copy-Item -Path $sourceProfilePath -Destination $psProfilePath -Force
                Write-Host "  ✓ Profile copied" -ForegroundColor Green
            }
            else {
                'Source profile not found at [{0}]' -f $sourceProfilePath | Write-Warning
            }
        }
        else {
            Write-Host "  ✓ PowerShell profile already exists" -ForegroundColor DarkGreen
        }

        Write-Host "=== PowerShell Profile Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region Windows Settings
function Update-WindowsSettings {
    [cmdletbinding()]
    param()
    process {
        Write-Host "`n=== Updating Windows Settings ===" -ForegroundColor Magenta

        Write-Host "  Enabling show hidden files"
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Hidden -Value 1

        Write-Host "  Enabling show file extensions"
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideFileExt -Value 0

        Write-Host "  Turning off system sounds"
        Set-ItemProperty -Path "HKCU:\AppEvents\Schemes" -Name "Scheme" -Value ".None"

        Write-Host ""
        Write-Host "** Manual steps needed:" -ForegroundColor Yellow
        Write-Host "    - Show mouse pointer when CTRL is clicked"
        Write-Host "    - Mouse movement speed"
        Write-Host "    - Pin apps to taskbar (Firefox, Chrome, ConEmu, etc.)"

        Write-Host "=== Windows Settings Complete ===`n" -ForegroundColor Magenta
    }
}
#endregion

#region Font Installation
function AddFonts {
    [cmdletbinding()]
    param(
        [Parameter(Position=1)]
        [string]$addFonthasrunpath = (Join-Path $global:machinesetupconfig.MachineSetupConfigFolder 'addfonts.hasrun'),

        [Parameter(Position=2)]
        [string]$addFontScriptPath = ($global:machinesetupuserconfig.AddFontScriptUrl)
    )
    process {
        if (-not (Test-Path -path $addFonthasrunpath)) {
            if (Test-Path $addFontScriptPath) {
                Write-Host "Installing fonts..." -ForegroundColor Cyan
                foreach ($font in $global:machinesetupuserconfig.Fonts) {
                    $extractfolder = ExtractLocalZip -filepath $font.Filename
                    $pathtofiles = (Join-Path $extractfolder $font.RelpathToFontsFolder)
                    if (Test-Path $pathtofiles) {
                        Invoke-Expression "& `"$addFontScriptPath`" $pathtofiles"
                    }
                    else {
                        'Font files folder [{0}] not found in extracted zip [{1}]' -f $pathtofiles, $extractfolder | Write-Warning
                    }
                }
                CreateDummyFile -filepath $addFonthasrunpath
            }
            else {
                'Add-Font.ps1 not found at "{0}"' -f $addFontScriptPath | Write-Warning
            }
        }
        else {
            'Skipping font additions (already done)' -f $addFonthasrunpath | Write-Verbose
        }
    }
}
#endregion

#region Wallpaper
function Set-Wallpaper {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$path,
        [string]$style = 'Fit'
    )
    process {
        # Use the Update-Wallpaper function if it's available from sayed-tools module
        if (IsCommandAvailable 'Update-Wallpaper') {
            Update-Wallpaper -path $path -Style $style
        }
        else {
            Write-Host "  Update-Wallpaper not available, setting wallpaper via registry" -ForegroundColor Yellow
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $path
            # Notify the system of the change
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
            [Wallpaper]::SystemParametersInfo(0x0014, 0, $path, 0x01 -bor 0x02) | Out-Null
        }
    }
}
#endregion

#region Configure Windows (combined)
function ConfigureWindows {
    [cmdletbinding()]
    param()
    process {
        RunTask @(
            { Update-WindowsSettings },
            { AddFonts },
            {
                if (Test-Path ($global:machinesetupconfig.WallpaperFilepath)) {
                    Write-Host "Setting wallpaper..." -ForegroundColor Cyan
                    Set-Wallpaper -path ($global:machinesetupconfig.WallpaperFilepath) -style 'Fit'
                }
                else {
                    'Wallpaper file not found at "{0}"' -f ($global:machinesetupconfig.WallpaperFilepath) | Write-Warning
                }
            }
        )
    }
}
#endregion

#region Module Loading
function LoadModules {
    [cmdletbinding()]
    param()
    process {
        $modulePath = Join-Path $global:sayedhaToolsFolderPath 'powershell/sayed-tools/sayed-tools.psd1'
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $modulePath = Join-Path $global:sayedhaToolsFolderPath 'powershell/sayed-tools.psd1'
        }
        $modstoload = @($modulePath)
        foreach ($mod in $modstoload) {
            if (Test-Path $mod -PathType Leaf) {
                'Loading module from "{0}"' -f $mod | Write-Output
                Import-Module -Name ((Resolve-Path -Path $mod).Path) -Global -DisableNameChecking -Force -Verbose
            }
            else {
                'Module file not found at [{0}]' -f $mod | Write-Warning
            }
        }
    }
}
#endregion

#region Task Runner
function RunTask {
    [cmdletbinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [ScriptBlock[]]$task
    )
    process {
        foreach ($t in $task) {
            if ($null -eq $t) { continue }

            try {
                . $t
            }
            catch {
                'Error in task execution of [{0}]' -f $t | Write-Warning
                Write-Host ("Exception: $($_.Exception.Message)") -ForegroundColor Red
                if ($_.InvocationInfo) {
                    Write-Host ("At: $($_.InvocationInfo.PositionMessage)") -ForegroundColor Yellow
                }
            }
        }
    }
}
#endregion

#region Script Restart
function RestartThisScript {
    [cmdletbinding()]
    param()
    process {
        Write-Host "`n************************************" -ForegroundColor Cyan
        Write-Host "Restarting the script under PowerShell 7" -ForegroundColor Cyan
        Write-Host "************************************`n" -ForegroundColor Cyan

        & $global:ps7Exepath -NoExit -ExecutionPolicy RemoteSigned -File $($MyInvocation.ScriptName) `
            -initializeScript:$false `
            -pcSettingsDirPath:$global:pcSettingsDirPath `
            -settingsVhdxFilePassword $global:settingsVhdxFilePassword `
            -settingsVhdxDriveLetter:$global:settingsVhdxDriveLetter
        break
    }
}
#endregion

#region Initialization
function Initialize-Script {
    [cmdletbinding()]
    param()
    process {
        if ($initializeScript) {
            if (-not (IsCommandAvailable -command winget.exe)) {
                Install-Winget
            }

            if (-not (Test-Path $global:ps7Exepath)) {
                Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
                winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
            }

            if ($PSVersionTable.PSVersion.Major -lt 7) {
                if (Test-Path $global:ps7Exepath) {
                    'PowerShell 7 found at [{0}]' -f $global:ps7Exepath | Write-Output
                    RestartThisScript
                }
                else {
                    'PowerShell 7 not found at [{0}]' -f $global:ps7Exepath | Write-Error
                }
            }
        }
        else {
            'Skipping initialization because $initializeScript is false' | Write-Output
        }
    }
}
#endregion

#region Main Orchestration
function ConfigureMachine {
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        $codehome = $global:codehome
    )
    process {
        EnsureFolderExists $codehome
        EnsureFolderExists ($global:machinesetupconfig.MachineSetupAppsFolder)

        Install-WingetApps
        Install-NpmGlobalPackages
        Install-Prompt

        RunTask @(
            { ConfigureGit },
            { EnsureBaseReposCloned },
            { ConfigurePowershell },
            { ConfigureConsole },
            { LoadModules },
            { ConfigureWindows }
        )

        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host " Machine setup complete!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green
    }
}
#endregion

#########################################
# Begin script
#########################################
if (-not (IsRunningAsAdmin)) {
    Write-Error 'This script needs to be run as an administrator'
    throw
}

Prompt-ForParameters
Initialize-Script

Push-Location
try {
    Set-Location $scriptDir
    ConfigureMachine
}
finally {
    Pop-Location
}
