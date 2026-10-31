function Init-MyClaudeProject {
    <#
    .SYNOPSIS
    Ensures a directory contains the Claude project marker without changing existing files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = '.'
    )

    $directory = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($directory.PSProvider.Name -ne 'FileSystem' -or -not $directory.PSIsContainer) {
        throw 'Init-MyClaudeProject requires an existing filesystem directory.'
    }

    $markerPath = Join-Path $directory.FullName '.claude-project'
    if (Test-Path -LiteralPath $markerPath -PathType Container) {
        throw "The Claude project marker path is a directory: '$markerPath'."
    }
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        # CreateNew prevents overwriting a marker created by another process.
        $stream = [System.IO.File]::Open($markerPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        try {
            $content = [System.Text.Encoding]::UTF8.GetBytes("Do not delete this file. It marks the Claude project root for Start-MyClaude.`n")
            $stream.Write($content, 0, $content.Length)
        }
        finally {
            $stream.Dispose()
        }
    }
    Add-MyClaudeAdditionalDirectory -ProjectRoot $directory.FullName -Directory 'C:\data\Dropbox\sayedha-notes\jetbrains\JetBrains'
    Get-Item -LiteralPath $markerPath -ErrorAction Stop
}

function New-MyClaudeFeature {
    <#
    .SYNOPSIS
    Creates features/<Name> and initializes it as a Claude project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [ValidateNotNullOrEmpty()]
        [string]$Path = '.'
    )

    if ($Name -in '.', '..' -or $Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Invalid feature name: '$Name'."
    }
    $directory = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($directory.PSProvider.Name -ne 'FileSystem' -or -not $directory.PSIsContainer) {
        throw 'New-MyClaudeFeature requires an existing filesystem directory.'
    }

    # New-Item -Force creates missing parents and keeps existing folders.
    $featureDir = New-Item -ItemType Directory -Path (Join-Path $directory.FullName "features/$Name") -Force -ErrorAction Stop
    $null = Init-MyClaudeProject -Path $featureDir.FullName
    $featureDir
}

function Add-MyClaudeAdditionalDirectory {
    # Adds a directory to permissions.additionalDirectories in .claude/settings.local.json, keeping other settings.
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Directory
    )

    $settingsDir = Join-Path $ProjectRoot '.claude'
    $settingsPath = Join-Path $settingsDir 'settings.local.json'
    if (Test-Path -LiteralPath $settingsPath -PathType Container) {
        throw "The Claude local settings path is a directory: '$settingsPath'."
    }

    $settings = $null
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $json = Get-Content -LiteralPath $settingsPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($json)) {
            $settings = ConvertFrom-Json -InputObject $json -AsHashtable -ErrorAction Stop
        }
    }
    if ($null -eq $settings) { $settings = [ordered]@{} }
    if ($settings -isnot [System.Collections.IDictionary]) {
        throw "Claude local settings must be a JSON object: '$settingsPath'."
    }

    # Equivalent to ensuring $.permissions.additionalDirectories contains $Directory.
    if ($null -eq $settings['permissions']) { $settings['permissions'] = [ordered]@{} }
    $permissions = $settings['permissions']
    if ($permissions -isnot [System.Collections.IDictionary]) {
        throw "'permissions' in '$settingsPath' must be a JSON object."
    }
    $directories = @($permissions['additionalDirectories'] | Where-Object { $null -ne $_ })
    if ($directories -contains $Directory) {
        return
    }
    $permissions['additionalDirectories'] = @($directories) + $Directory

    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    Set-Content -LiteralPath $settingsPath -Value (ConvertTo-Json -InputObject $settings -Depth 100) -Encoding utf8NoBOM
}

function Start-MyClaude {
    <#
    .SYNOPSIS
    Starts Claude at the nearest project root with the current directory as context.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$MarkerFile = '.claude-project',
        [switch]$Resume,
        # Lets `smc -Resume <id>` bind the ID here instead of to MarkerFile.
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId
    )

    if ($SessionId) {
        $Resume = $true
    }

    $currentLocation = Get-Location
    if ($currentLocation.Provider.Name -ne 'FileSystem') {
        throw 'Start-MyClaude requires a filesystem directory.'
    }
    $currentDir = $currentLocation.ProviderPath
    $directory = Get-Item -LiteralPath $currentDir -ErrorAction Stop

    # Walk up the directory tree to find the nearest project root.
    while ($null -ne $directory) {
        $markerPath = Join-Path $directory.FullName $MarkerFile
        if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
            break
        }
        $directory = $directory.Parent
    }

    if ($null -eq $directory) {
        throw "Could not find a Claude project root. Missing '$MarkerFile' in parent directories."
    }

    $projectRoot = $directory.FullName
    $relativePath = [System.IO.Path]::GetRelativePath($projectRoot, $currentDir).Replace('\', '/')
    $isFeature = $relativePath -like 'features/*'

    $prompt = if ($isFeature) {
        @"
The active feature for this session is '$relativePath'.

Follow the instructions in the work-on-feature skill.
Load relevant feature-level and project-level knowledge.
Save feature knowledge in '$relativePath' and project-wide knowledge in 'memory/'.
Do not modify files during initialization.
"@
    }
    else {
        $knowledgeRule = if ($relativePath -eq '.') {
            "Save knowledge files in the project's 'memory/' directory."
        }
        else {
            "This directory holds authored deliverables only. Save knowledge files in the project's 'memory/' directory, never in '$relativePath'."
        }
        @"
The current workstream for this session is '$relativePath'.
Use this directory as the active workstream context.
$knowledgeRule
Load relevant project-level knowledge.
Do not modify files during initialization.
"@
    }

    Write-Host "Claude project: $projectRoot" -ForegroundColor Cyan
    Write-Host "Active context: $relativePath" -ForegroundColor Green

    Push-Location -LiteralPath $projectRoot -ErrorAction Stop
    try {
        $claudeArguments = @('--append-system-prompt', $prompt)
        if (-not $Resume) {
            # Resumed sessions keep their existing name.
            $claudeArguments += '--name', (Split-Path -Leaf $currentDir)
        }
        if ($isFeature -and -not $Resume) {
            $initialPrompt = "/work-on-feature `"$relativePath`""
            $claudeArguments += $initialPrompt
        }
        if ($Resume) {
            $claudeArguments += '--resume'
            if ($SessionId) {
                $claudeArguments += $SessionId
            }
        }
        claude @claudeArguments
    }
    finally {
        Pop-Location
    }
}

function Enter-MyClaudeProjects {
    <#
    .SYNOPSIS
    Changes to the Claude projects folder in Dropbox.
    #>
    [CmdletBinding()]
    param()

    $path = Join-Path $script:Settings.DropboxHome 'sayedha-notes/jetbrains/JetBrains/_claude-code-projects'
    Set-Location -LiteralPath $path -ErrorAction Stop
}
