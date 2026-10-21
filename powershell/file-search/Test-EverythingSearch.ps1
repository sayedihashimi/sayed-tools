#Requires -Version 7.0
# Run with: pwsh -NoProfile -File ./Test-EverythingSearch.ps1
# Compiles a fake ES executable; no Everything installation or live index is required.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock] $Action, [string] $Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-True ($null -ne $caught) "Expected an error matching: $Pattern"
    Assert-True ($caught.Exception.Message -like $Pattern) "Unexpected error: $caught"
}

$wrapper = Join-Path $PSScriptRoot 'Search-EverythingFiles.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('file-search-tests-' + [guid]::NewGuid().ToString('N'))
$environmentNames = @('EVERYTHING_CLI_PATH', 'PATH', 'ProgramW6432', 'ProgramFiles',
    'ProgramFiles(x86)', 'LOCALAPPDATA', 'FILE_SEARCH_TEST_ROOT', 'FILE_SEARCH_TEST_MODE')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { throw 'Tests require the Windows .NET Framework C# compiler.' }
    $source = Join-Path $testRoot 'FakeES.cs'
    @"
using System;
using System.IO;
using System.Text;
class FakeES {
    static int Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("FILE_SEARCH_TEST_ROOT");
        File.WriteAllLines(Path.Combine(root, "arguments.txt"), args);
        string mode = Environment.GetEnvironmentVariable("FILE_SEARCH_TEST_MODE");
        if (mode == "failure") { Console.Error.WriteLine("mock IPC failure"); return 8; }
        int index = Array.IndexOf(args, "-export-txt");
        if (index < 0 || index + 1 >= args.Length) return 4;
        string[] files = mode == "empty" ? new string[0] : File.ReadAllLines(Path.Combine(root, "fixture-list.txt"));
        int pathIndex = Array.IndexOf(args, "-path");
        if (pathIndex >= 0) {
            string searchDirectory = args[pathIndex + 1];
            files = Array.FindAll(files, file => file.StartsWith(searchDirectory, StringComparison.OrdinalIgnoreCase));
        }
        File.WriteAllLines(args[index + 1], files, new UTF8Encoding(true));
        return 0;
    }
}
"@ | Set-Content -LiteralPath $source
    $cli = Join-Path $testRoot 'es.exe'
    $compilerOutput = & $compiler /nologo "/out:$cli" $source 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Mock CLI compilation failed: $compilerOutput" }
    $env:FILE_SEARCH_TEST_ROOT = $testRoot
    $env:FILE_SEARCH_TEST_MODE = ''
    $env:EVERYTHING_CLI_PATH = $null
    $first = Join-Path $testRoot 'sample with spaces.txt'
    $second = Join-Path $testRoot 'café.json'
    $missing = Join-Path $testRoot 'missing.txt'
    [IO.File]::WriteAllText($first, "First line`nNeedle value")
    [IO.File]::WriteAllText($second, 'needle value')
    [IO.File]::WriteAllLines((Join-Path $testRoot 'fixture-list.txt'), [string[]]@($first, $second, $missing))

    $query = '"C:\My Notes\" ext:txt | ext:json'
    $hits = @(& $wrapper needle $query -Extension .txt,json -EverythingCliPath $cli -TimeoutMilliseconds 1234)
    Assert-True ($hits.Count -eq 2 -and $hits[0] -eq $first -and $hits[1] -eq $second) 'Paths or Unicode were lost.'
    $arguments = [IO.File]::ReadAllLines((Join-Path $testRoot 'arguments.txt'))
    Assert-True ($arguments[6] -eq "file: ext:txt;json <$query>") 'Everything query quoting/grouping failed.'
    Assert-True ($arguments[4] -eq '1234') 'Timeout was not passed to ES.'
    Assert-True (-not (Test-Path -LiteralPath $arguments[1])) 'Temporary export was not removed.'

    $results = @(& $wrapper -EverythingQuery $query -Extension .txt,json -EverythingCliPath $cli)
    Assert-True ($results.Count -eq 3 -and $results[0] -eq $first -and $results[1] -eq $second -and $results[2] -eq $missing) 'Query-only mode must return raw Everything paths, including missing files.'
    $arguments = [IO.File]::ReadAllLines((Join-Path $testRoot 'arguments.txt'))
    Assert-True ($arguments[6] -eq "file: ext:txt;json <$query>") 'Query-only filters or quotes were lost.'
    Assert-True (-not (Test-Path -LiteralPath $arguments[1])) 'Query-only temporary export was not removed.'
    $results = @(& $wrapper -EverythingCliPath $cli -ShowMatches -Regex -CaseSensitive -WarnOnMissingFiles)
    Assert-True ($results.Count -eq 3 -and $results[0] -is [string]) 'No-argument search must return paths; content switches must not change the result type.'
    $arguments = [IO.File]::ReadAllLines((Join-Path $testRoot 'arguments.txt'))
    Assert-True ($arguments[6] -eq 'file:') 'No-filter search must query all indexed files.'
    Assert-Throws { & $wrapper -SearchText '' -EverythingCliPath $cli } '*SearchText*'

    # Directory scope must include descendants but exclude lookalike sibling folders.
    $scope = Join-Path $testRoot 'scoped café [notes]'
    $nested = Join-Path $scope 'nested'
    $sibling = $scope + '-old'
    $null = New-Item -ItemType Directory -Path $nested, $sibling
    $topFile = Join-Path $scope 'top.txt'
    $nestedFile = Join-Path $nested 'child.txt'
    $siblingFile = Join-Path $sibling 'outside.txt'
    foreach ($file in @($topFile, $nestedFile, $siblingFile)) { [IO.File]::WriteAllText($file, 'Needle value') }
    $fixtureList = Join-Path $testRoot 'fixture-list.txt'
    [IO.File]::WriteAllLines($fixtureList, [string[]]@($topFile, $nestedFile, $siblingFile, $first))
    try {
        $results = @(& $wrapper -SearchDirectory $scope -Extension txt -EverythingQuery 'top | child' -EverythingCliPath $cli)
        Assert-True ($results.Count -eq 2 -and $results[0] -eq $topFile -and $results[1] -eq $nestedFile) 'Directory scope must include children and exclude similarly named siblings.'
        $arguments = [IO.File]::ReadAllLines((Join-Path $testRoot 'arguments.txt'))
        $pathIndex = [Array]::IndexOf($arguments, '-path')
        Assert-True ($pathIndex -ge 0 -and $arguments[$pathIndex + 1] -eq ($scope + '\')) 'Directory argument lost spaces, Unicode, brackets, or its trailing separator.'
        Assert-True ($arguments[6] -eq 'file: ext:txt <top | child>') 'Directory filter must combine with extension and grouped query filters.'
        Assert-True (-not (Test-Path -LiteralPath $arguments[1])) 'Scoped export was not removed.'
        $relativeScope = [IO.Path]::GetRelativePath($PWD.Path, $scope)
        $results = @(& $wrapper needle -SearchDirectory $relativeScope -EverythingCliPath $cli)
        Assert-True ($results.Count -eq 2 -and $results[1] -eq $nestedFile) 'Relative directory or scoped content search failed.'
        $driveRoot = [IO.Path]::GetPathRoot($scope)
        $null = & $wrapper -SearchDirectory $driveRoot -EverythingCliPath $cli
        $arguments = [IO.File]::ReadAllLines((Join-Path $testRoot 'arguments.txt'))
        Assert-True ($arguments[[Array]::IndexOf($arguments, '-path') + 1] -eq $driveRoot) 'Drive root was incorrectly normalized.'
        Assert-Throws { & $wrapper -SearchDirectory (Join-Path $testRoot 'no-such-directory') -EverythingCliPath (Join-Path $testRoot 'no-cli.exe') } '*Search directory was not found*SearchDirectory*'
        Assert-Throws { & $wrapper -SearchDirectory $topFile -EverythingCliPath $cli } '*not a directory*'
        Assert-Throws { & $wrapper -SearchDirectory '' -EverythingCliPath $cli } '*SearchDirectory*'
    }
    finally {
        [IO.File]::WriteAllLines($fixtureList, [string[]]@($first, $second, $missing))
    }

    $warnings = @()
    $matches = @(& $wrapper '^Needle' -EverythingCliPath $cli -Regex -CaseSensitive -ShowMatches -WarnOnMissingFiles -WarningVariable warnings -WarningAction SilentlyContinue)
    Assert-True ($matches.Count -eq 1 -and $matches[0].LineNumber -eq 2 -and $matches[0].PSTypeNames[0] -eq 'FileSearch.Match') 'Content switches or match objects failed.'
    Assert-True ($warnings.Count -eq 1) 'Missing-file warnings were not forwarded.'

    $env:EVERYTHING_CLI_PATH = $cli
    Assert-True (@(& $wrapper needle).Count -eq 2) 'Environment configuration failed.'
    $env:EVERYTHING_CLI_PATH = Join-Path $testRoot 'not-installed.exe'
    Assert-True (@(& $wrapper needle -EverythingCliPath $cli).Count -eq 2) 'Explicit path must override environment configuration.'
    Assert-Throws { & $wrapper needle } '*Configured Everything CLI was not found*'
    $env:EVERYTHING_CLI_PATH = $null
    $env:PATH = $testRoot
    Assert-True (@(& $wrapper needle).Count -eq 2) 'PATH discovery failed.'

    # Isolate default discovery from any real Everything installation on this machine.
    $env:PATH = ''
    foreach ($name in @('ProgramW6432','ProgramFiles','ProgramFiles(x86)','LOCALAPPDATA')) {
        [Environment]::SetEnvironmentVariable($name, $testRoot, 'Process')
    }
    $install = Join-Path $testRoot 'Everything'
    New-Item -ItemType Directory -Path $install | Out-Null
    Copy-Item -LiteralPath $cli -Destination (Join-Path $install 'es.exe')
    Assert-True (@(& $wrapper needle).Count -eq 2) 'Default install discovery failed.'
    Remove-Item -LiteralPath (Join-Path $install 'es.exe')
    Assert-Throws { & $wrapper needle -NoAutoInstall } '*Everything CLI (es.exe) was not found*Download*'

    # Exercise automatic installation through the real ZIP/extraction code with a fake download.
    $script:fakeArchive = Join-Path $testRoot 'download.zip'
    $zip = [IO.Compression.ZipFile]::Open($script:fakeArchive, [IO.Compression.ZipArchiveMode]::Create)
    try { $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $cli, 'es.exe') }
    finally { $zip.Dispose() }
    $downloadState = @{ Count = 0; Fail = $true; Path = $null; Uri = $null; Archive = $script:fakeArchive }
    Set-Item -Path Function:Invoke-WebRequest -Value ({
        param($Uri, $OutFile, $TimeoutSec)
        $downloadState.Count++
        $downloadState.Path = $OutFile
        $downloadState.Uri = $Uri
        if ($downloadState.Fail) { throw 'Simulated network failure' }
        Copy-Item -LiteralPath $downloadState.Archive -Destination $OutFile -Force
    }.GetNewClosure())
    Assert-Throws { & $wrapper needle } '*Could not install Everything CLI*Simulated network failure*EverythingCliPath*'
    Assert-True (-not (Test-Path -LiteralPath $downloadState.Path)) 'Failed download was not cleaned up.'
    $downloadState.Fail = $false
    Assert-True (@(& $wrapper needle).Count -eq 2) 'Automatic installation did not continue the content search.'
    $managedCli = Join-Path $testRoot 'sayed-tools\EverythingCLI\es.exe'
    Assert-True (Test-Path -LiteralPath $managedCli) 'Managed CLI was not installed.'
    Assert-True ($downloadState.Uri -like 'https://www.voidtools.com/ES-1.1.0.38.*.zip') 'Installer must use the pinned official HTTPS download.'
    Assert-True (-not (Test-Path -LiteralPath $downloadState.Path)) 'Successful download was not cleaned up.'
    $downloadCount = $downloadState.Count
    Assert-True (@(& $wrapper needle).Count -eq 2) 'Installed CLI was not reused.'
    Assert-True ($downloadState.Count -eq $downloadCount) 'Installed CLI was unnecessarily downloaded again.'
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path $managedCli) -Filter '*.tmp').Count -eq 0) 'Staged executable leaked.'
    Remove-Item -LiteralPath $managedCli
    [IO.File]::WriteAllText($script:fakeArchive, 'invalid ZIP')
    Assert-Throws { & $wrapper needle } '*Could not install Everything CLI*'
    Assert-True (-not (Test-Path -LiteralPath $managedCli)) 'Corrupt download was published as es.exe.'
    Assert-True (-not (Test-Path -LiteralPath $downloadState.Path)) 'Corrupt archive was not cleaned up.'
    Remove-Item -LiteralPath Function:\Invoke-WebRequest

    $env:FILE_SEARCH_TEST_MODE = 'empty'
    Assert-True (@(& $wrapper needle -EverythingCliPath $cli).Count -eq 0) 'Empty results must produce no objects.'
    Assert-True (@(& $wrapper -Extension txt -EverythingCliPath $cli).Count -eq 0) 'Empty query-only results must produce no objects.'
    $env:FILE_SEARCH_TEST_MODE = 'failure'
    Assert-Throws { & $wrapper needle -EverythingCliPath $cli } '*exit code 8*Everything is running*mock IPC failure*'
    $arguments = [IO.File]::ReadAllLines((Join-Path $testRoot 'arguments.txt'))
    Assert-True (-not (Test-Path -LiteralPath $arguments[1])) 'Temporary export leaked after ES failed.'
    Assert-Throws { & $wrapper needle -EverythingCliPath $cli -Extension 'txt|exe' } '*Extension*'
    $help = Get-Help $wrapper -Full
    Assert-True ($help.Synopsis -like 'Finds files with Everything*' -and $help.examples.example.Count -eq 7) 'Comment-based help was not discovered.'
    'PASS: directory scope/validation, optional content search, raw index results, query/argument handling, content options, Unicode paths, config precedence, PATH/default discovery, missing CLI, automatic installation/reuse/failures, empty results, ES failure, cleanup, validation, and help.'
}
finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    # Only remove this test's unique directory under the resolved system temp folder.
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedTestRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedTestRoot).StartsWith('file-search-tests-')) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
