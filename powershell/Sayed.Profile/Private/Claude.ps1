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
    Get-Item -LiteralPath $markerPath -ErrorAction Stop
}

function Start-MyClaude {
    <#
    .SYNOPSIS
    Starts Claude at the nearest project root with the current directory as context.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$MarkerFile = '.claude-project',
        [switch]$Resume
    )

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
Do not modify files during initialization.
"@
    }
    else {
        @"
The current workstream for this session is '$relativePath'.
Use this directory as the active workstream context.
Load relevant project-level knowledge.
Do not modify files during initialization.
"@
    }

    Write-Host "Claude project: $projectRoot" -ForegroundColor Cyan
    Write-Host "Active context: $relativePath" -ForegroundColor Green

    Push-Location -LiteralPath $projectRoot -ErrorAction Stop
    try {
        $claudeArguments = @('--append-system-prompt', $prompt)
        if ($isFeature) {
            $initialPrompt = "/work-on-feature `"$relativePath`""
            $claudeArguments += $initialPrompt
        }
        if ($Resume) {
            $claudeArguments += '--resume'
        }
        claude @claudeArguments
    }
    finally {
        Pop-Location
    }
}
