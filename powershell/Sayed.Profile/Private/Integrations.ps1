function Get-SayedNativeScript {
    param([string]$Command, [string[]]$Arguments)
    $exe = Get-Command $Command -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $diagnostics = [IO.Path]::GetTempFileName()
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $exe.Source @Arguments 2> $diagnostics
        $exitCode = $LASTEXITCODE
        $detail = (Get-Content -LiteralPath $diagnostics -Raw -ErrorAction SilentlyContinue)
        if ($exitCode -ne 0) { throw "$Command exited with code ${exitCode}: $detail" }
        $text = $output -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($text)) { throw "$Command returned an empty initialization script. $detail" }
        if ($detail) { Write-Verbose $detail }
        return $text
    }
    finally { Remove-Item -LiteralPath $diagnostics -Force -ErrorAction SilentlyContinue }
}

function Find-SayedTheme {
    if ($script:Settings.ThemePath) {
        if (-not (Test-Path -LiteralPath $script:Settings.ThemePath -PathType Leaf)) { throw "Theme not found: $($script:Settings.ThemePath)" }
        return $script:Settings.ThemePath
    }
    $name = $script:Settings.ThemeName + '.omp.json'
    $paths = @()
    if ($env:POSH_THEMES_PATH) { $paths += Join-Path $env:POSH_THEMES_PATH $name }
    if ($env:LOCALAPPDATA) { $paths += Join-Path $env:LOCALAPPDATA "Programs/oh-my-posh/themes/$name" }
    $theme = $paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($theme) { return $theme }
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            foreach ($package in (Get-AppxPackage -Name ohmyposh.cli -ErrorAction Stop | Sort-Object { [version]$_.Version } -Descending)) {
                $candidate = Join-Path $package.InstallLocation "themes/$name"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            }
        }
        catch { Write-Verbose "Package theme discovery failed: $($_.Exception.Message)" }
    }
    throw "Local theme '$name' was not found. Set ThemePath or POSH_THEMES_PATH."
}

function Initialize-SayedPrompt {
    $env:POSH_UPDATE_NOTICE = 'false'
    $theme = Find-SayedTheme
    $initScript = Get-SayedNativeScript oh-my-posh @('init', 'pwsh', '--config', $theme)
    Invoke-Expression -Command $initScript -ErrorAction Stop
}

function Initialize-SayedZoxide {
    $initScript = Get-SayedNativeScript zoxide @('init', '--cmd', 'z', 'powershell')
    Invoke-Expression -Command $initScript -ErrorAction Stop
}

function Initialize-SayedDotnetCompletions {
    $initScript = Get-SayedNativeScript dotnet @('completions', 'script', 'pwsh')
    Invoke-Expression -Command $initScript -ErrorAction Stop
}
