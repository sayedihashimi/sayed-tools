# File search

Requires PowerShell 7+. Searches text regardless of extension. PDF, Word, and
other binary formats require separate text extraction.

## Search with Everything

Install and run [Everything](https://www.voidtools.com/). If the ES CLI cannot be found,
the wrapper automatically downloads ES 1.1.0.38 from the official [downloads site](https://www.voidtools.com/downloads/)
for your Windows architecture and installs it to `%LOCALAPPDATA%\sayed-tools\EverythingCLI\es.exe`.
No administrator rights or PATH changes are needed. Future calls reuse the installed copy.
Use `-NoAutoInstall` to require manual installation instead. Download failures include manual setup instructions.
This installs only ES; the Everything desktop application must already be installed and running.
The desktop application's Everything.exe is separate from es.exe.

```powershell
# Return Everything file paths without searching their contents.
./Search-EverythingFiles.ps1 -Extension md,txt
./Search-EverythingFiles.ps1 -EverythingQuery '"C:\My Notes\" ext:md'

# Find files whose contents contain the supplied text.
./Search-EverythingFiles.ps1 'license sales' -Extension md,txt
./Search-EverythingFiles.ps1 'Rider' '"C:\My Notes\" ext:md'
./Search-EverythingFiles.ps1 '^TODO:' -Extension cs,ps1 -Regex -ShowMatches
Get-Help ./Search-EverythingFiles.ps1 -Full
```

`-EverythingQuery` accepts Everything search syntax. `-Extension` accepts multiple
extensions, with or without leading dots. Omit both to search all indexed files.
Omit `-SearchText` to return indexed file paths directly, without opening the files
or checking whether they still exist. Use named `-EverythingQuery` for query-only
searches: the first positional argument still means SearchText. With SearchText,
content options match Search-Files.ps1; results are matching paths, or objects with
Path, LineNumber, and Line with `-ShowMatches`. Content switches are ignored when
SearchText is omitted.

Configure the CLI for one call:

```powershell
./Search-EverythingFiles.ps1 'Rider' -Extension md -EverythingCliPath 'C:\Tools\Everything\es.exe'
```

Or configure it for the current session and persist it for future sessions:

```powershell
$env:EVERYTHING_CLI_PATH = 'C:\Tools\Everything\es.exe'
[Environment]::SetEnvironmentVariable('EVERYTHING_CLI_PATH', $env:EVERYTHING_CLI_PATH, 'User')
```

Resolution order: explicit `-EverythingCliPath`, EVERYTHING_CLI_PATH, es.exe on PATH,
then this script's directory, the managed per-user installation, and Everything/Everything 1.5a folders under Program
Files (including x86) and LocalAppData (including Programs). An invalid configured
path produces an error so a stale setting is visible.

The wrapper uses ES `-export-txt` with a UTF-8 BOM, waits up to 10 seconds for the
index (`-TimeoutMilliseconds` changes this), and returns the temporary list or
searches its contents using Search-Files.ps1. It deletes the list even on failure. It does not modify
file-list.txt. See the [official ES reference](https://www.voidtools.com/support/everything/command_line_interface/).

## Search an existing path list

```powershell
./Search-Files.ps1 'Rider' -ListPath ./file-list.txt
Get-Help ./Search-Files.ps1 -Full
```

The list must contain one full file path per line; it is not a CSV parser. Blank
lines and lines starting with # are ignored. The default is file-list.txt beside
the script. SearchFiles.cs provides the parallel C# version (requires the .NET 10
SDK): `dotnet run SearchFiles.cs -- 'Rider' --list file-list.txt`.

## Verification

Run `pwsh -NoProfile -File ./Test-EverythingSearch.ps1` on Windows. The tests
compile a fake ES executable using the Windows .NET Framework compiler; they
do not require Everything or query your live index.

