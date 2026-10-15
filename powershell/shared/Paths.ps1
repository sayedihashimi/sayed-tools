function Resolve-FullPath {
    [CmdletBinding()]
    param([Parameter(Position=0, ValueFromPipeline=$true)][string[]]$path)
    process {
        foreach ($item in $path) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($item)
            }
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
            $directory = Resolve-FullPath $item
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
