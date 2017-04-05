[cmdletbinding()]
param()

function GetTemplatesToCheck(){
    [cmdletbinding()]
    param(
        $searchUrl = ''
    )
    process{

    }
}

<#
.SYNOPSIS
    This will return nuget from the $cachePath. If it is not there then it
    will automatically be downloaded before the call completes.
#>
function Get-Nuget{
    [cmdletbinding()]
    param(
        $toolsDir = '~/.sayedtools/',
        $nugetDownloadUrl = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
    )
    process{
        if(!(Test-Path $toolsDir)){
            New-Item -Path $toolsDir -ItemType Directory | out-null
        }

        $nugetDestPath = Join-Path -Path $toolsDir -ChildPath nuget.exe

        if(!(Test-Path $nugetDestPath)){
            'Downloading nuget.exe' | Write-Verbose
            Invoke-WebRequest -Uri $nugetDownloadUrl -OutFile $nugetDestPath | out-null
            
            # (New-Object System.Net.WebClient).DownloadFile($nugetDownloadUrl, $nugetDestPath) | Out-Null

            # double check that is was written to disk
            if(!(Test-Path $nugetDestPath)){
                throw 'unable to download nuget'
            }
        }

        # return the path of the file
        (get-item $nugetDestPath).FullName
    }
}



try{

    Get-Nuget

}
catch{
    $_.Exception | Write-Error
}