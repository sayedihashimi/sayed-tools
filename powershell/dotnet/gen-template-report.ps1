[cmdletbinding()]
param()

function GetTemplatesToCheck(){
    [cmdletbinding()]
    param(
        [string]$searchTerm = 'template'
    )
    process{
        # $packages = (&(get-nuget) list slowcheetah|%{$res = ($_.split(' '));if( ($res -ne $null) -and ($res.length -gt 1)){@{'Name'=$res[0];'Version'=$res[1]}}})
        # (&(get-nuget) list slowcheetah|%{$res = ($_.split(' '));if( ($res -ne $null) -and ($res.length -gt 1)){@{'Name'=$res[0];'Version'=$res[1]}}})|%{$_.Name}

        $result = (&(get-nuget) list $searchTerm|%{$res = ($_.split(' '));if( ($res -ne $null) -and ($res.length -gt 1)) {
                @{
                    'Name'=$res[0]
                    'Version'=$res[1]
                    'DownloadUrl' = ('http://www.nuget.org/api/v2/package/{0}/{1}' -f $res[0],$res[1])
                }}})

        if($LASTEXITCODE -eq 0){
            # return the result
            $result
        }
        else{
            throw ('Unknown error: ' + $Error[0])
        }
    }
}

function Get-PackageDownloadStats(){
    [cmdletbinding()]
    param(
        [string[]]$packageName,
        [string]$urlformat = 'http://www.nuget.org/packages/{0}/'
    )
    process{
        # $html = (Invoke-WebRequest -Uri 'http://www.nuget.org/packages/SlowCheetah/').rawcontent
        foreach($pkg in $packageName){
            [int]$dlcount = -1;
            [string]$url = ($urlformat -f $pkg)
            [string]$html = ((Invoke-WebRequest -Uri $url -ErrorAction SilentlyContinue).rawcontent)
            if(-not([string]::IsNullOrWhiteSpace($html))) {
                $htmllines = $html.split("`n")
                $dlstring = (((( $htmllines|Select-String '<p class="stat-label">Downloads</p>' -SimpleMatch -Context 1))) | Select-Object -ExpandProperty Context | Select-Object -ExpandProperty PreContext)
                if($dlstring -match '<p class="stat-number">([0-9,]+)<\/p>'){
                    $dlcount = ($Matches[1])
                }

                [string]$downloadUrl = $null
                try{
                    $downloadUrl = ( $htmllines|Select-String '<a href="([^\"]+)" title=\"Download the raw nupkg file."').Matches.Groups[1].value                    
                }
                catch{
                    $downloadUrl = $null
                }
            }

            New-Object -TypeName psobject -Property @{
                'Name'=$pkg
                'DownloadCount'=$dlcount
                'Downloadurl'=$downloadUrl
            }
        }
    }
}

function Get-TemplateReport{
    [cmdletbinding()]
    param(
        [string]$searchTerm = 'template'       
    )
    process{
        #$templates = GetTemplatesToCheck -searchTerm $searchTerm

        $pkgs = (GetTemplatesToCheck -searchTerm $searchTerm |
                    ForEach-Object { 
                        Get-PackageDownloadStats -packageName $_ })





        # download each template
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