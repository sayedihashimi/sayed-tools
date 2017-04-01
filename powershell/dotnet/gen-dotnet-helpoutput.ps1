
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
    @{'command'='dotnet';'Cargs'=@('--version')},
    @{'command'='dotnet';'Cargs'=@('-h')},

    @{'command'='dotnet';'CArgs'=@('build','-h')},
    @{'command'='dotnet';'CArgs'=@('clean','-h')},
    @{'command'='dotnet';'CArgs'=@('restore','-h')}
    @{'command'='dotnet';'CArgs'=@('publish','-h')},
    @{'command'='dotnet';'CArgs'=@('test','-h')},
    @{'command'='dotnet';'CArgs'=@('pack','-h')},
    @{'command'='dotnet';'CArgs'=@('migrate','-h')},

    @{'command'='dotnet';'Cargs'=@('new')},
    @{'command'='dotnet';'CArgs'=@('new','-h')},
    @{'command'='dotnet';'CArgs'=@('new','-l')},
    @{'command'='dotnet';'CArgs'=@('new','classlib','-h')}
    @{'command'='dotnet';'CArgs'=@('new','mstest','-h')}
    @{'command'='dotnet';'CArgs'=@('new','xunit','-h')}
    @{'command'='dotnet';'CArgs'=@('new','web','-h')},
    @{'command'='dotnet';'CArgs'=@('new','mvc','-h')}
    @{'command'='dotnet';'CArgs'=@('new','webapi','-h')}
    @{'command'='dotnet';'CArgs'=@('new','sln','-h')}

    @{'command'='dotnet-new3'},
    @{'command'='dotnet-new3';'CArgs'=@('-h')},
    @{'command'='dotnet-new3';'CArgs'=@('-l')},
    @{'command'='dotnet-new3';'CArgs'=@('console','-h')}
    @{'command'='dotnet-new3';'CArgs'=@('classlib','-h')}
    @{'command'='dotnet-new3';'CArgs'=@('mstest','-h')}
    @{'command'='dotnet-new3';'CArgs'=@('xunit','-h')}
    @{'command'='dotnet-new3';'CArgs'=@('web','-h')},
    @{'command'='dotnet-new3';'CArgs'=@('mvc','-h')}
    @{'command'='dotnet-new3';'CArgs'=@('webapi','-h')}
    @{'command'='dotnet-new3';'CArgs'=@('sln','-h')}
)


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
                $actualCommand = ($dnCommand.command).Trim()
                if( ('dotnet-new3'.Equals($actualCommand)) -and (-not(get-alias 'dotnet-new3')) ){
                    'dotnet-new3 not found skipping' | Write-Verbose
                    continue
                }


                if(-not ([string]::IsNullOrWhiteSpace($actualCommand))){
                    $cmdArgs = ($dnCommand.CArgs)
                    #[string]$cmdText = ($actualCommand, ( $cmdArgs -join ' ' ))


                    [string]$cmdText = $actualCommand.Trim()
                    if($cmdArgs -ne $null -and ($cmdArgs.length -gt 0)) {
                        $cmdText = ($actualCommand, ( $cmdArgs -join ' ' ))
                    }


                    [string]$filename = ( "{0}.{1}.cmd.txt" -f $runDnCommandIndex, $cmdText)
                    [string]$destPath = (Join-Path -Path $outputFolder -ChildPath $filename)
                    'Command: "{0}" dest: "{1}"' -f $cmdText,$destPath | Write-Verbose
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

if(-not ([string]::IsNullOrWhiteSpace($outputPath))){
    Get-ChildItem $outputPath -File | Remove-Item

    $commandsToRun | RunDnCommand -outputFolder $outputPath
}
else{
    'outputpath was empty' | Write-Error
}
