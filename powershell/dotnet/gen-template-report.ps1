[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [string[]]$searchTerm = @('template','templates')
)

function InternalGet-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}

$scriptDir = ((InternalGet-ScriptDirectory) + "\")

[string]$ignoreFilePath = (join-path $scriptDir 'template.ignore.txt')

if(-not (test-path $ignoreFilePath)){
    thorw ('template ignore fild not found at: [0]' -f $ignoreFilePath)
}

[string[]]$packagesToExclude = (Get-Content $ignoreFilePath)

$global:machinesetupconfig = @{
    MachineSetupConfigFolder = (Join-Path $env:temp 'SayedHaMachineSetup')
    MachineSetupAppsFolder = (Join-Path $env:temp 'SayedHaMachineSetup\apps')
    RemoteFiles = (join-path $env:temp 'SayedHaMachineSetup\remotefiles')
}

function Get7ZipPath{
    [cmdletbinding()]
    param()
    process{
        (join-path $env:ProgramFiles '7-Zip\7z.exe')
    }
}

function EnsureFolderExists{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$path
    )
    process{
        foreach($p in $path){
            if(-not [string]::IsNullOrWhiteSpace($p) -and (-not (Test-Path $p))){
                New-Item -Path $p -ItemType Directory
            }
        }
    }
}

function GetLocalFileFor{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename
    )
    process{
        $expectedPath = (Join-Path $global:machinesetupconfig.RemoteFiles $filename)
        
        if(-not (test-path $expectedPath)){
            # download the file
            EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($expectedPath)) | out-null            
            Invoke-WebRequest -Uri $downloadUrl -OutFile $expectedPath | out-null
        }

        if(-not (test-path $expectedPath)){
            throw ('Unable to download file from [{0}] to [{1}]' -f $downloadUrl, $expectedPath)
        }

        $expectedPath
    }
}

function ExtractRemoteZip{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$filename
    )
    process{
        $zippath = GetLocalFileFor -downloadUrl $downloadUrl -filename $filename
        $expectedFolderpath = (join-path -Path ($global:machinesetupconfig.MachineSetupConfigFolder) ('apps\{0}\' -f $filename))

        if(-not (test-path $expectedFolderpath)){
            EnsureFolderExists -path $expectedFolderpath | Write-Verbose
            # extract the folder to the directory
            & (Get7ZipPath) x -y "-o$expectedFolderpath" "$zippath" | Write-Verbose
        }        

        # return the path to the folder
        $expectedFolderpath
    }
}

function GetTemplatesToCheck(){
    [cmdletbinding()]
    param(
        [string[]]$searchTerm =@('template','templates')
    )
    process{
        $allResults = @()
        foreach($st in $searchTerm){
        
            $result = (&(get-nuget) list -NonInteractive -Prerelease $st|%{$res = ($_.split(' '));if( ($res -ne $null) -and ($res.length -gt 1)) {
                    @{
                        'Name'=$res[0]
                        'Version'=$res[1]
                        'DownloadUrl' = ('http://www.nuget.org/api/v2/package/{0}/{1}' -f $res[0],$res[1])
                    }}})

            if($LASTEXITCODE -eq 0){
                $allResults += $result
            }
            else{
                throw ('Unknown error: ' + $Error[0])
            }
        }

        $filteredResults = @()
        foreach($pkg in $allResults){
            if(-not ($packagesToExclude.Contains($pkg.Name) )) {
                $filteredResults += $pkg
            }
        }

        $filteredResults
    }
}

function Get-PackageDownloadStats(){
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object[]]$package,
        [string]$urlformat = 'http://www.nuget.org/packages/{0}/'
    )
    process{
        # $html = (Invoke-WebRequest -Uri 'http://www.nuget.org/packages/SlowCheetah/').rawcontent
        foreach($pkgobj in $package){
            [string]$pkgname = $pkgobj.Name
            [int]$dlcount = -1;
            [string]$packageurl = ($urlformat -f $pkgname)
            [string]$html = ((Invoke-WebRequest -Uri $packageurl -ErrorAction SilentlyContinue).rawcontent)
            if(-not([string]::IsNullOrWhiteSpace($html))) {
                $htmllines = $html.split("`n")
                $dlstring = (((( $htmllines|Select-String '<p class="stat-label">Downloads</p>' -SimpleMatch -Context 1))) | Select-Object -ExpandProperty Context | Select-Object -ExpandProperty PreContext)
                if($dlstring -match '<p class="stat-number">([0-9,]+)<\/p>'){
                    $dlcount = ($Matches[1])
                }
                $downloadUrl = $pkgobj.DownloadUrl
                <#    
                [string]$downloadUrl = $null
                try{
                    $downloadUrl = ( $htmllines|Select-String '<a href="([^\"]+)" title=\"Download the raw nupkg file."').Matches.Groups[1].value                    
                }
                catch{
                    $downloadUrl = $null
                }
                #>
            }

            New-Object -TypeName psobject -Property @{
                'Name'=$pkgname
                'DownloadCount'=$dlcount
                'Downloadurl'=$downloadUrl
                'Version'=$pkgobj.Version
            }
        }
    }
}

function Find-TemplateFilesUnderPath{
    [cmdletbinding()]
    param(
        [string[]]$path
    )
    process{
        foreach($pathToCheck in $path){
            if( -not ([string]::IsNullOrWhiteSpace($pathToCheck))){
                [string[]]$templateFiles = (Get-ChildItem $pathToCheck .template.config -Directory -Recurse|%{Get-ChildItem (get-item ($_).fullname) template.json -File}).FullName
            }
            # return the result
            $templateFiles
        }
    }
}

function Test-PathContainsTemplate(){
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$pathToCheck
    )
    process{
        if(test-path $pathToCheck){
            # if the folder contains a template return the path, otherwise return nothing.
            #[string[]]$templateFiles = (Get-ChildItem $pathToCheck .template.config -Directory -Recurse|%{Get-ChildItem (get-item ($_).fullname) template.json -File})
            [string[]]$templateFiles = Find-TemplateFilesUnderPath -path $pathToCheck
            if( ($templateFiles -ne $null) -and ($templateFiles.Length -gt 0)){
                # return the folder path
                $true
            }
            else{
                $false
            }
        }
    }
}

function Find-PathContainingTemplate(){
    [cmdletbinding()]
    param(
        [Parameter(Position=1,ValueFromPipeline)]
        [string[]]$pathToCheck
    )
    process{
        foreach($folderpath in $pathToCheck){
            # if the folder contains a template return the path, otherwise return nothing.
            $templateFiles = (Get-ChildItem $path .template.config -Directory -Recurse|%{Get-ChildItem (get-item ($_).fullname) template.json -File})
            if($templateFiles -ne $null -and ($templateFiles.Length -gt 0)){

                # return the folder path
                $folderpath
            }
        }
    }
}

function Get-TemplateReport{
    [cmdletbinding()]
    param(
        [string[]]$searchTerm = @('template','templates')       
    )
    process{
        # list of templates to check
        [int]$index = 0
        $searchResults = GetTemplatesToCheck -searchTerm $searchTerm
        $pkgs = ($searchResults |
                    ForEach-Object {
                        Write-Progress -Activity 'Finding templates' -PercentComplete ( (++$index)/($searchResults.length)*100 ) -Status ('{0} of {1}' -f $index,$searchResults.Length)
                        Get-PackageDownloadStats -package $_ })
        
        [object[]]$foundTemplatePackages = @()
        [string[]]$pathsToCheck = @()
        # download packages locally and get path to installed location
        $index = 0
        $totalNum = $pkgs.length
        foreach($pkg in $pkgs){
            Write-Progress -Activity 'Gathring template data' -PercentComplete ( (++$index)/$totalNum*100  ) -Status ('{0} of {1}' -f $index,$totalNum)



            $filename = '{0}-{1}.nupkg' -f $pkg.Name,$pkg.Version
            $extractpath = ExtractRemoteZip -downloadUrl $pkg.DownloadUrl -filename $filename
            'extractpath: {0}' -f $extractpath | Write-Verbose
            # $pathsToCheck += $extractpath
            if( (Test-PathContainsTemplate -pathToCheck $extractpath) -eq $true){
                $pkg
            }
        }

        # $foundTemplatePackages
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

function Get-JsonObjectFromTemplateFile{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$templateFilePath
    )
    process{
        foreach($path in $templateFilePath){
            if(test-path -Path $path){
                try{
                    ConvertFrom-Json([System.IO.File]::ReadAllText($path))
                }
                catch{
                    'Unable to convert file [{0}] to json object. Error: {1}' -f $path,$_.Exception | Write-Verbose
                }
            }
        }
    }
}

try{
    $global:foundpackages = @()
    $global:foundpackages += ( Get-TemplateReport -searchTerm $searchTerm )

    $uResults = $Global:foundpackages|Select-Object -Unique -Property Name,DownloadCount|Sort-Object -Property DownloadCount -Descending
    $totalDownload = ($uResults|Measure-Object -Property DownloadCount -Sum).Sum

    ' --- template report ---' | Write-Output
    $uResults | Select-Object -Property Name,DownloadCount,@{Name='Percent overall';Expression={'{0:P1}' -f ($_.DownloadCount/$totalDownload)}}

    '---------------------------------' | Write-Output
    "Total downloads: $totalDownload" | Write-Output

    # not working for some reason
    # " --- overall ---`n" | Write-Output
    # $uResults.DownloadCount|Measure-Object -Sum -Average -Maximum -Minimum

    $extractPath = $global:machinesetupconfig.MachineSetupAppsFolder
    $templateFiles = Find-TemplateFilesUnderPath -path $extractPath

    $templateFiles | Get-JsonObjectFromTemplateFile | Select-Object -Property author,name,identity,classifications,@{Name='Parameters';Expression={$_.symbols}} | Sort-Object -Property author | fl
}
catch{
    $_.Exception | Write-Error
}