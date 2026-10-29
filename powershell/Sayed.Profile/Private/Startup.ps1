function Invoke-SayedProfileStep {
    param([string]$Name, [scriptblock]$Action)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $result = [pscustomobject]@{ Component = $Name; Status = 'Ready'; DurationMs = 0; Message = ''; ErrorRecord = $null }
    $location = Get-Location
    try {
        $ErrorActionPreference = 'Stop'
        & $Action | Out-Null
    }
    catch {
        $result.Status = 'Failed'
        $result.Message = $_.Exception.Message.Trim()
        $result.ErrorRecord = $_
        $summary = ($result.Message -split '\r?\n')[0]
        Write-Warning "Profile [$Name]: $summary" -WarningAction Continue
    }
    finally {
        Set-Location -LiteralPath $location.Path
        $result.DurationMs = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)
        $script:StartupStatus.Add($result)
        Write-Verbose "$Name : $($result.Status) ($($result.DurationMs) ms)"
    }
}

function Get-SayedProfileStatus {
    [CmdletBinding()]
    param()
    $script:StartupStatus.ToArray()
}

function Initialize-SayedProfile {
    [CmdletBinding()]
    param([hashtable]$Configuration = @{}, [string]$ConfigurationPath, [switch]$Force)
    if ($script:Initialized -and -not $Force) { Write-Verbose 'Profile is already initialized. Use -Force to reconfigure.'; return }
    $script:StartupStatus.Clear()
    $script:Settings = Get-SayedProfileConfiguration -Overrides $Configuration -ConfigurationPath $ConfigurationPath
    # Retain legacy variable names for existing helper modules and machine overrides.
    $global:codehome = $script:Settings.CodeHome
    $global:DropboxHome = $script:Settings.DropboxHome
    $global:dropboxPsHome = Join-Path $global:DropboxHome 'Personal/PcSettings/Powershell'
    $global:isLinuxOrMac = $IsLinux -or $IsMacOS
    $global:MyProfileSettings = [pscustomobject]@{ HomeDir = $HOME; ModulesToLoad = @() }
    $global:sayedssettings = [pscustomobject]@{ ProfileScript = Join-Path $script:ModuleRoot '../profile.ps1' }
    Invoke-SayedProfileStep 'Tools' {
        if (Get-Module sayed-tools) { return }
        Import-Module (Join-Path $script:ModuleRoot '../sayed-tools/sayed-tools.psd1') -Global -DisableNameChecking -ErrorAction Stop
    }
    Invoke-SayedProfileStep 'Paths' {
        $moduleRoot = Split-Path $script:ModuleRoot
        $entries = @($env:PSModulePath -split [IO.Path]::PathSeparator)
        if ($moduleRoot.TrimEnd('\', '/') -notin @($entries | ForEach-Object { $_.TrimEnd('\', '/') })) {
            $env:PSModulePath = (@($entries) + $moduleRoot) -join [IO.Path]::PathSeparator
        }
        foreach ($path in (@(Join-Path $script:Settings.CodeHome '../tools') + $script:Settings.ExtraPaths)) {
            if (Test-Path -LiteralPath $path -PathType Container) { Add-Path -pathToAdd $path }
        }
    }
    if ($script:Settings.EnableCustomModules) { Import-SayedCustomModules }
    Invoke-SayedProfileStep 'Aliases' { Initialize-SayedToolAliases }
    if ($script:Settings.Interactive) {
        Invoke-SayedProfileStep 'ReadLine' { Initialize-SayedReadLine }
        if ($script:Settings.EnableZoxide) { Invoke-SayedProfileStep 'Zoxide' { Initialize-SayedZoxide } }
        if ($script:Settings.EnableDotnetCompletions) { Invoke-SayedProfileStep 'DotnetCompletions' { Initialize-SayedDotnetCompletions } }
        # Prompt initialization runs last so earlier components cannot reset its handlers.
        if ($script:Settings.EnablePrompt) { Invoke-SayedProfileStep 'Prompt' { Initialize-SayedPrompt } }
    }
    else {
        $script:StartupStatus.Add([pscustomobject]@{ Component = 'Interactive'; Status = 'Skipped'; DurationMs = 0; Message = 'Interactive terminal features disabled.'; ErrorRecord = $null })
    }
    if ($script:Settings.InitialDirectory) { Set-Location -LiteralPath $script:Settings.InitialDirectory -ErrorAction Stop }
    $script:Initialized = $true
}

# Compatibility entry points used by older Dropbox profiles.
function Sayed-InitailizeProfile { [CmdletBinding()] param(); Initialize-SayedProfile }
function InitalizeEnv { [CmdletBinding()] param(); Initialize-SayedProfile }
function reload-profile {
    . $PROFILE
    # $PROFILE's Import-Module keeps the loaded copy, so load edits from disk and
    # initialize through the new module; commands called here resolve to this old one.
    $module = Import-Module (Join-Path $script:ModuleRoot 'Sayed.Profile.psd1') -Global -Force -DisableNameChecking -PassThru
    & $module { Initialize-SayedProfile -Force }
}
