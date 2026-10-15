#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Searches a pre-built list of files of any extension for text and returns the full paths of files that contain it.

.DESCRIPTION
    Reads a text file containing one full file path per line (default: file-list.txt in the
    script's own folder) and searches each of those files for the supplied text.

    By default the search is a case-insensitive literal (non-regex) substring match, and only the
    full path of each matching file is written to the pipeline - so the output can be piped
    straight into other commands.

    Searches text content regardless of file extension; does not extract text from binary formats.
    Uses UTF-8 by default, with BOM detection for Unicode text files.

    Requires PowerShell 7+ (PowerShell Core).

.PARAMETER SearchText
    The text to look for inside each file. Treated as a literal string unless -Regex is used.

.PARAMETER ListPath
    Path to the text file holding the list of file paths, one per line.
    Defaults to 'file-list.txt' next to this script. Errors out if the file does not exist.

.PARAMETER CaseSensitive
    Make the match case-sensitive.

.PARAMETER Regex
    Treat SearchText as a regular expression instead of a literal string.

.PARAMETER ShowMatches
    Emit rich objects (Path, LineNumber, Line) for every matching line instead of one path per file.

.PARAMETER WarnOnMissingFiles
    Write a warning for any path in the list that no longer exists. Missing files are skipped silently otherwise.

.EXAMPLE
    ./Search-Files.ps1 -SearchText "dotUltimate"

.EXAMPLE
    ./Search-Files.ps1 "license sales" -CaseSensitive

.EXAMPLE
    ./Search-Files.ps1 -SearchText '^#\s+Roadmap' -Regex -ShowMatches

.EXAMPLE
    ./Search-Files.ps1 -SearchText "Rider" -ListPath D:\lists\other-files.txt
#>


[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $SearchText,

    [Parameter(Position = 1)]
    [string] $ListPath = (Join-Path $PSScriptRoot 'file-list.txt'),

    [switch] $CaseSensitive,

    [switch] $Regex,

    [switch] $ShowMatches,

    [switch] $WarnOnMissingFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Validate the list file -------------------------------------------------
if (-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) {
    Write-Error "File list not found: '$ListPath'. Provide a valid path via -ListPath." `
        -Category ObjectNotFound -ErrorAction Continue
    exit 1
}

$ListPath = (Resolve-Path -LiteralPath $ListPath).Path

# --- Load the paths ---------------------------------------------------------
$paths = @(Get-Content -LiteralPath $ListPath |
    ForEach-Object { $_.Trim().Trim('"') } |
    Where-Object { $_ -and -not $_.StartsWith('#') })

if ($paths.Count -eq 0) {
    Write-Warning "No file paths found in '$ListPath'."
    return
}

Write-Verbose "Searching $($paths.Count) file(s) listed in '$ListPath' for '$SearchText'."

# Display -ShowMatches results as a list so long paths don't crowd out the matched line,
# while still emitting real objects for downstream piping.
$formatFile = Join-Path $PSScriptRoot 'FileSearch.Format.ps1xml'
if ($ShowMatches -and (Test-Path -LiteralPath $formatFile -PathType Leaf)) {
    Update-FormatData -PrependPath $formatFile -ErrorAction SilentlyContinue
}

# --- Search -----------------------------------------------------------------
$selectStringArgs = @{
    Pattern       = $SearchText
    SimpleMatch   = -not $Regex
    CaseSensitive = [bool]$CaseSensitive
    Encoding      = 'utf8'
}
if (-not $ShowMatches) { $selectStringArgs['List'] = $true }   # stop at first hit per file

$missingCount = 0
$matchedCount = 0

foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $missingCount++
        if ($WarnOnMissingFiles) { Write-Warning "Missing file: $path" }
        continue
    }

    try {
        $hits = Select-String -LiteralPath $path @selectStringArgs
    }
    catch {
        Write-Warning "Could not read '$path': $($_.Exception.Message)"
        continue
    }

    if (-not $hits) { continue }

    if ($ShowMatches) {
        $matchedCount++
        foreach ($hit in $hits) {
            [pscustomobject]@{
                PSTypeName = 'FileSearch.Match'
                Path       = $hit.Path
                LineNumber = $hit.LineNumber
                Line       = $hit.Line.Trim()
            }
        }
    }
    else {
        $matchedCount++
        $path
    }
}

Write-Verbose "Done. $matchedCount file(s) matched; $missingCount listed path(s) no longer exist."
