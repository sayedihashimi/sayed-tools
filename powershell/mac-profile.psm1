[cmdletbinding()]
param()

[string[]]$modsToImport = @(
    (Join-Path $Global:codehome 'sayed-tools/powershell/github-ps.psm1')
    (Join-Path $Global:codehome 'sayed-tools/powershell/sayed-tools.psm1')
)

function clip{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object]$inObj
    )
    process{
        if($inObj -ne $null){
            $inObj | pbcopy
        }
    }
}
