#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Finds files with Everything and optionally searches their text content.
.DESCRIPTION
    Exports a temporary file list using es.exe and delegates content searching to
    Search-Files.ps1 when SearchText is supplied. Otherwise returns Everything's file
    paths directly without reading file contents. Deletes the list afterward.
    Everything must be running.
    Installs ES automatically from voidtools.com if it cannot be found, unless
    -NoAutoInstall is used. The Everything desktop application must already be running.
    Searches text regardless of extension; does not extract text from binary formats.
.PARAMETER SearchText
    Optional text to find inside files. Literal unless -Regex is used.
    When omitted, returns the Everything file paths without content filtering.
    Use the named -EverythingQuery parameter for query-only searches; the first
    positional argument remains SearchText for compatibility.
.PARAMETER EverythingQuery
    Optional Everything query, such as 'ext:md;txt' or '"C:\My Notes\" ext:md'.
    Combined with -Extension when both are supplied. Defaults to all indexed files.
.PARAMETER Extension
    One or more extensions, with or without a leading dot, such as md,txt.
.PARAMETER SearchDirectory
    Existing top-level directory to search, including all subdirectories.
    Accepts absolute or relative filesystem paths. Combined with Extension and
    EverythingQuery. When omitted, searches all indexed directories.
.PARAMETER EverythingCliPath
    Full path to es.exe. Defaults to EVERYTHING_CLI_PATH when set. Otherwise searches
    PATH, this script's directory, Program Files, and per-user Everything locations.
    An invalid configured path produces an error instead of falling back.
.PARAMETER NoAutoInstall
    Return setup instructions when ES is missing instead of downloading it.
    Automatic installation uses LOCALAPPDATA\sayed-tools\EverythingCLI; no admin rights needed.
.PARAMETER TimeoutMilliseconds
    Time to wait for Everything's database to load. Defaults to 10000 milliseconds.
.PARAMETER CaseSensitive
    Make the content match case-sensitive. Only applies when SearchText is supplied.
.PARAMETER Regex
    Treat SearchText as a regular expression. Only applies when SearchText is supplied.
.PARAMETER ShowMatches
    Return Path, LineNumber, and Line objects for each matching line.
    Only applies when SearchText is supplied.
.PARAMETER WarnOnMissingFiles
    Warn about indexed files that no longer exist during content searching.
    Only applies when SearchText is supplied; query-only results reflect the index.
.EXAMPLE
    ./Search-EverythingFiles.ps1 "license sales" -Extension md,txt
.EXAMPLE
    ./Search-EverythingFiles.ps1 "Rider" '"C:\My Notes\" ext:md'
.EXAMPLE
    ./Search-EverythingFiles.ps1 '^TODO:' -Extension cs,ps1 -Regex -ShowMatches
.EXAMPLE
    ./Search-EverythingFiles.ps1 "Rider" -Extension md -EverythingCliPath C:\Tools\Everything\es.exe
.EXAMPLE
    ./Search-EverythingFiles.ps1 -EverythingQuery '"C:\My Notes\"' -Extension md,txt
.EXAMPLE
    ./Search-EverythingFiles.ps1 -SearchDirectory 'C:\My Notes' -Extension md,txt
.EXAMPLE
    ./Search-EverythingFiles.ps1 'Rider' -SearchDirectory 'C:\My Notes' -Extension md
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $SearchText,
    [Parameter(Position = 1)]
    [string] $EverythingQuery = '',
    [ValidatePattern('^\.?[\p{L}\p{N}_+-]+$')]
    [string[]] $Extension,
    [ValidateNotNullOrEmpty()]
    [string] $SearchDirectory,
    [string] $EverythingCliPath = $env:EVERYTHING_CLI_PATH,
    [switch] $NoAutoInstall,
    [ValidateRange(1, 2147483647)]
    [int] $TimeoutMilliseconds = 10000,
    [switch] $CaseSensitive,
    [switch] $Regex,
    [switch] $ShowMatches,
    [switch] $WarnOnMissingFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Install-EverythingCli {
    # Pin the official ES release so a new upstream release cannot silently change this tool.
    $version = '1.1.0.38'
    if (-not $IsWindows) { throw 'Automatic ES installation requires Windows. Configure -EverythingCliPath manually.' }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set. Configure -EverythingCliPath manually.' }
    $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $downloadArchitecture = switch ($architecture) {
        'X64' { 'x64' }
        'X86' { 'x86' }
        'Arm64' { 'ARM64' }
        'Arm' { 'ARM' }
        default { throw "Unsupported ES architecture '$architecture'. Configure -EverythingCliPath manually." }
    }
    $installDirectory = Join-Path $env:LOCALAPPDATA 'sayed-tools\EverythingCLI'
    $destination = Join-Path $installDirectory 'es.exe'
    if (Test-Path -LiteralPath $destination -PathType Leaf) { return $destination }
    $downloadUrl = "https://www.voidtools.com/ES-$version.$downloadArchitecture.zip"
    $archivePath = [IO.Path]::GetTempFileName()
    $stagedExecutable = $null
    try {
        Write-Information "Installing Everything CLI $version ($downloadArchitecture) to '$destination'." -InformationAction Continue
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -TimeoutSec 60
        # Extract only es.exe, rather than trusting arbitrary paths in the ZIP archive.
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $entries = @($archive.Entries | Where-Object { $_.FullName -ieq 'es.exe' })
            if ($entries.Count -ne 1 -or $entries[0].Length -lt 2) {
                throw 'The downloaded archive does not contain a valid es.exe entry.'
            }
            $null = New-Item -ItemType Directory -Path $installDirectory -Force
            $stagedExecutable = Join-Path $installDirectory ([guid]::NewGuid().ToString('N') + '.tmp')
            $inputStream = $entries[0].Open()
            try {
                $outputStream = [IO.File]::Create($stagedExecutable)
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
            }
            finally { $inputStream.Dispose() }
        }
        finally { $archive.Dispose() }
        $header = [IO.File]::OpenRead($stagedExecutable)
        try {
            if ($header.ReadByte() -ne 0x4D -or $header.ReadByte() -ne 0x5A) {
                throw 'The downloaded es.exe does not have a Windows executable header.'
            }
        }
        finally { $header.Dispose() }
        # Publish only a complete file. If another invocation installed it first, reuse it.
        try { [IO.File]::Move($stagedExecutable, $destination) }
        catch {
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw }
        }
        return $destination
    }
    catch {
        throw "Could not install Everything CLI from '$downloadUrl': $($_.Exception.Message) Download ES manually from https://www.voidtools.com/downloads/ and set -EverythingCliPath or EVERYTHING_CLI_PATH. Use -NoAutoInstall to disable automatic installation."
    }
    finally {
        Remove-Item -LiteralPath $archivePath -ErrorAction SilentlyContinue
        if ($stagedExecutable -and (Test-Path -LiteralPath $stagedExecutable)) {
            Remove-Item -LiteralPath $stagedExecutable -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-EverythingCli {
    param([string] $ConfiguredPath)
    $setup = 'Download the ES command-line tool from https://www.voidtools.com/downloads/ ' +
        'and extract es.exe. Pass -EverythingCliPath "C:\Tools\Everything\es.exe", ' +
        'set $env:EVERYTHING_CLI_PATH to its full path, or add its directory to PATH. ' +
        'Everything.exe is the desktop app, not the ES CLI. Everything must also be running.'
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($ConfiguredPath)
        if (-not (Test-Path -LiteralPath $expandedPath -PathType Leaf)) {
            throw "Configured Everything CLI was not found at '$ConfiguredPath'. $setup"
        }
        return (Resolve-Path -LiteralPath $expandedPath).ProviderPath
    }
    $command = Get-Command es.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    $candidates = @(
        Join-Path $PSScriptRoot 'es.exe'
        if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'sayed-tools\EverythingCLI\es.exe' }
        foreach ($root in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if ($root) {
                Join-Path $root 'Everything\es.exe'
                Join-Path $root 'Everything 1.5a\es.exe'
                Join-Path $root 'Programs\Everything\es.exe'
                Join-Path $root 'Programs\Everything 1.5a\es.exe'
            }
        }
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    if (-not $NoAutoInstall) { return Install-EverythingCli }
    throw "Everything CLI (es.exe) was not found. $setup"
}

$resolvedSearchDirectory = $null
if ($PSBoundParameters.ContainsKey('SearchDirectory')) {
    if (-not (Test-Path -LiteralPath $SearchDirectory -PathType Container)) {
        throw "Search directory was not found or is not a directory: '$SearchDirectory'. Provide an existing folder via -SearchDirectory."
    }
    $resolved = Resolve-Path -LiteralPath $SearchDirectory
    if ($resolved.Provider.Name -ne 'FileSystem') {
        throw "SearchDirectory must be a filesystem directory: '$SearchDirectory'."
    }
    # A trailing separator excludes similarly named sibling directories (Notes vs Notes-Old).
    $resolvedSearchDirectory = $resolved.ProviderPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
}

$cli = Resolve-EverythingCli $EverythingCliPath
$queryParts = @('file:')
if ($Extension) {
    $extensions = @($Extension | ForEach-Object { $_.TrimStart('.') } | Select-Object -Unique)
    $queryParts += 'ext:' + ($extensions -join ';')
}
if (-not [string]::IsNullOrWhiteSpace($EverythingQuery)) {
    # Group OR expressions so they cannot bypass the file/extension filters.
    $queryParts += "<$EverythingQuery>"
}
$query = $queryParts -join ' '
Write-Verbose "Everything CLI: $cli; query: $query"
$listPath = [IO.Path]::GetTempFileName()
$process = $null
try {
    # Pass arguments directly, preserving quotes and operators without shell evaluation.
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $cli
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-export-txt', $listPath, '-utf8-bom', '-timeout',
            $TimeoutMilliseconds.ToString(), '-search', $query)) {
        $startInfo.ArgumentList.Add($argument)
    }
    if ($resolvedSearchDirectory) {
        $startInfo.ArgumentList.Add('-path')
        $startInfo.ArgumentList.Add($resolvedSearchDirectory)
    }
    try {
        $process = [Diagnostics.Process]::Start($startInfo)
    }
    catch {
        throw "Could not start Everything CLI '$cli'. Check -EverythingCliPath or EVERYTHING_CLI_PATH. $($_.Exception.Message)"
    }
    # Drain both streams concurrently to avoid blocking on a full output buffer.
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $outputText = $stdout.GetAwaiter().GetResult()
    $errorText = $stderr.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) {
        throw "Everything CLI failed (exit code $($process.ExitCode)). Ensure Everything is running and its index is ready, and install the current ES CLI from https://www.voidtools.com/downloads/. $errorText $outputText"
    }
    if ((Get-Item -LiteralPath $listPath).Length -eq 0 -or
        -not (Get-Content -LiteralPath $listPath -TotalCount 1)) {
        Write-Verbose 'Everything returned no files.'
        return
    }
    if (-not $PSBoundParameters.ContainsKey('SearchText')) {
        # Return the index results as-is, including files that have since moved or disappeared.
        Get-Content -LiteralPath $listPath -Encoding utf8
        return
    }
    $searchArgs = @{
        SearchText = $SearchText
        ListPath = $listPath
        CaseSensitive = $CaseSensitive
        Regex = $Regex
        ShowMatches = $ShowMatches
        WarnOnMissingFiles = $WarnOnMissingFiles
    }
    & (Join-Path $PSScriptRoot 'Search-Files.ps1') @searchArgs
}
finally {
    if ($null -ne $process) { $process.Dispose() }
    Remove-Item -LiteralPath $listPath -ErrorAction SilentlyContinue
}
