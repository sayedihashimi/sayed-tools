
[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [string]$outputPath
)

if([string]::IsNullOrWhiteSpace($outputPath)) {
    $outputPath # = (Join-Path $pwd 'help-output')
}

[object[]]$commandsToRun = @(
    @{'command'='dotnet'},
    @{'command'='dotnet';'Cargs'=@('-h')},
    @{'command'='dotnet';'Cargs'=@('new')},
    @{'command'='dotnet';'CArgs'=@('new','-h')},
    @{'command'='dotnet';'CArgs'=@('new','-l')},
    @{'command'='dotnet';'CArgs'=@('new','web','-h')},
    @{'command'='dotnet';'CArgs'=@('new','mvc','-h')}
)

# $commands | % { & ($_.command) ($_.CArgs) }

[int]$runDnCommandIndex = 0
function RunDnCommand{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object[]]$command,

        [Parameter(Position=1)]
        [string]$outputFolder = $pwd
    )
    process{
        $runDnCommandIndex++
        foreach($dnCommand in $command){
            if($dnCommand -ne $null){
                $actualCommand = ($dnCommand.command)
                
                if(-not ([string]::IsNullOrWhiteSpace($actualCommand))){
                    $cmdArgs = ($dnCommand.CArgs)
                    [string]$cmdText = ($actualCommand, ( $cmdArgs -join ' ' ))
                    [string]$filename = ( "{0}.{1}.cmd.txt" -f $runDnCommandIndex, $cmdText)
                    [string]$destPath = (Join-Path -Path $outputFolder -ChildPath $filename)
                    'Command: "{0}" dest: "{1}"' -f $cmdText,$destPath | Write-Output
                    & ($actualCommand) ($cmdArgs) *> $destPath

                    # Get-Content -Path $destPath | Write-Output
                }
            }
        }
    }
}

$outputPath = (Join-Path -Path $pwd -ChildPath 'help-output')

@'
pwd: [{0}]
$outputPath [{1}]
'@ -f $pwd,$outputPath | Write-Host -ForegroundColor Yellow


$commandsToRun | RunDnCommand -outputFolder $outputPath
