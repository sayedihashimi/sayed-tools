[cmdletbinding()]
param()

<#
.SYNOPSIS
    You can add this to you build script to ensure that psbuild is available before calling
    Invoke-MSBuild. If psbuild is not available locally it will be downloaded automatically.
#>
function EnsurePsbuildInstlled{
    [cmdletbinding()]
    param(
        # TODO: Change to master when 1.1.9 gets there
        [string]$psbuildInstallUri = 'https://raw.githubusercontent.com/ligershark/psbuild/dev/src/GetPSBuild.ps1',

        [System.Version]$minVersion = (New-Object -TypeName 'system.version' -ArgumentList '1.1.9.1')
    )
    process{
        # see if there is already a version loaded
        $psbuildNeedsInstall = $true
        [System.Version]$installedVersion = $null
        try{
            Import-Module psbuild -ErrorAction SilentlyContinue | Out-Null
            $installedVersion = Get-PSBuildVersion
        }
        catch{
            $installedVersion = $null
        }

        if( ($installedVersion -ne $null) -and ($installedVersion.CompareTo($minVersion) -ge 0) ){
            'Skipping psbuild install because version [{0}] detected' -f $installedVersion.ToString() | Write-Verbose
        }
        else{
            'Installing psbuild from [{0}]' -f $psbuildInstallUri | Write-Verbose
            (new-object Net.WebClient).DownloadString($psbuildInstallUri) | iex

            # make sure it's loaded and throw if not
            if(-not (Get-Command "Invoke-MsBuild" -errorAction SilentlyContinue)){
                throw ('Unable to install/load psbuild from [{0}]' -f $psbuildInstallUri)
            }
        }
    }
}

function EnsureFileReplacerInstlled{
    [cmdletbinding()]
    param()
    begin{
        EnsurePsbuildInstlled
        Import-NuGetPowershell
    }
    process{
        if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
            $fpinstallpath = (Get-NuGetPackage -name file-replacer -version '0.4.0-beta' -binpath)
            if(-not (Test-Path $fpinstallpath)){ throw ('file-replacer folder not found at [{0}]' -f $fpinstallpath) }
            Import-Module (Join-Path $fpinstallpath 'file-replacer.psm1') -DisableNameChecking
        }

        # make sure it's loaded and throw if not
        if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
            throw ('Unable to install/load file-replacer')
        }
    }
}

function Ensure-DirectoryExists{
    param([Parameter(Position=0)][System.IO.DirectoryInfo]$path)
    process{
        if($path -ne $null){
            if(-not (Test-Path $path.FullName)){
                New-Item -Path $path.FullName -ItemType Directory
            }
        }
    }
}

function Update-FilesWithCommitId{
    [cmdletbinding()]
    param(
        [string]$commitId = ($env:APPVEYOR_REPO_COMMIT),

        [System.IO.DirectoryInfo]$dirToUpdate = ($outputroot),

        [Parameter(Position=2)]
        [string]$filereplacerVersion = '0.4.0-beta'
    )
    begin{
        EnsureFileReplacerInstlled
    }
    process{
        if([string]::IsNullOrEmpty($commitId)){
            try{
                $commitstr = (& git log --format="%H" -n 1)
                if($commitstr -match '\b[0-9a-f]{5,40}\b'){
                    $commitId = $commitstr
                }
            }
            catch{
                # do nothing
            }
        }

        if(![string]::IsNullOrWhiteSpace($commitId)){
            'Updating commitId from [{0}] to [{1}]' -f '$(COMMIT_ID)',$commitId | Write-Verbose

            $folder = $dirToUpdate
            $include = '*.nuspec'
            # In case the script is in the same folder as the files you are replacing add it to the exclude list
            $exclude = "$($MyInvocation.MyCommand.Name);"
            $replacements = @{
                '$(COMMIT_ID)'="$commitId"
            }
            Replace-TextInFolder -folder $folder -include $include -exclude $exclude -replacements $replacements | Write-Verbose
            'Replacement complete' | Write-Verbose
        }
    }
}

function Get-VisualStudioGitAttributes{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.IO.FileInfo[]]$destination = (join-path $PWD '.gitattributes'),
        $sourceUri = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/.gitattributes'
        
    )
    process{
        $webresult = (Invoke-WebRequest -Uri $sourceUri).Content

        if(-not [string]::IsNullOrEmpty($destination)){
            foreach($dest in $destination){
               $dest = (Get-NormalizedPath -path $dest)

                if(([System.IO.FileInfo]$dest).Attributes -match 'Directory'){
                    $dest = (Join-Path $dest '.gitattributes')
                }
                $webresult | Out-File $dest -Encoding ascii
            }
        }
        else{
                # return the result as a string
                $webresult
        }
    }    
}

function Get-VisualStudioGitIgnore{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [System.IO.FileInfo[]]$destination = (join-path $PWD '.gitignore'),
        $sourceUri = 'https://raw.githubusercontent.com/github/gitignore/master/VisualStudio.gitignore'
        
    )
    process{
        $webresult = (Invoke-WebRequest -Uri $sourceUri).Content

        if(-not [string]::IsNullOrEmpty($destination)){
            foreach($dest in $destination){
               $dest = (Get-NormalizedPath -path $dest)

                if(([System.IO.FileInfo]$dest).Attributes -match 'Directory'){
                    $dest = (Join-Path $dest '.gitignore')
                }
                $webresult | Out-File $dest -Encoding ascii
            }
        }
        else{
            # return the result as a string
                $webresult
        }
    }
}

function Get-NormalizedPath{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$path,
        [string]$rootPath = $pwd
    )
    process{
        foreach($p in $path){
            $result = $p
            if(-not ([System.IO.Path]::IsPathRooted($p))){
                $result = (Join-Path $rootPath $p)
            }

            if($result -ne $null){
                $result = [System.IO.Path]::GetFullPath($result)
                $result = $result.Trim().TrimEnd([System.IO.Path]::DirectorySeparatorChar).TrimEnd([System.IO.Path]::AltDirectorySeparatorChar)
            }
            # return result
            $result
        }
    }
}

function New-SnippetObj{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$title,

        [Parameter(Position=1,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$description,

        [Parameter(Position=2,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$text
    )
    process{
        New-Object -TypeName psobject -Property @{
            Title = $title
            Description = $description
            Text = $text
        }
    }
}

$cmd = Get-Command -Name 'Get-IseSnippet' -ErrorAction SilentlyContinue
if($cmd -eq $null){
    function Get-IseSnippet{
        [cmdletbinding()]
        [OutputType([System.IO.FileInfo])]
        param(
            $snippetPath = (Join-Path (Split-Path $profile.CurrentUserCurrentHost) "Snippets")
        )
        process{
            if (Test-Path $snippetPath)
            {
                dir $snippetPath
            }
        }
    }
}

$cmd = Get-Command -Name 'New-IseSnippet' -ErrorAction SilentlyContinue
if($cmd -eq $null){
    function New-IseSnippet{
        [CmdletBinding()]
        param(

            [Parameter(Mandatory=$true, Position=0)]
            [String]
            $Title,

            [Parameter(Mandatory=$true, Position=1)]
            [String]
            $Description,

            [Parameter(Mandatory=$true, Position=2)]
            [String]
            $Text,

            [String]
            $Author,

            [Int32]
            [ValidateRange(0, [Int32]::MaxValue)]
            $CaretOffset = 0,

            [Switch]
            $Force
        )

        Begin
        {
            $snippetPath = Join-Path (Split-Path $profile.CurrentUserCurrentHost) "Snippets"

            if($Text.IndexOf("]]>") -ne -1)
            {
                throw [Microsoft.PowerShell.Host.ISE.SnippetStrings]::SnippetsNoCloseCData -f "Text","]]>"
            }

            if (-not (Test-Path $snippetPath))
            {
                $null = mkdir $snippetPath
            }
        }

        End
        {
            $snippet = @"
    <?xml version='1.0' encoding='utf-8' ?>
        <Snippets  xmlns='http://schemas.microsoft.com/PowerShell/Snippets'>
            <Snippet Version='1.0.0'>
                <Header>
                    <Title>$([System.Security.SecurityElement]::Escape($Title))</Title>
                    <Description>$([System.Security.SecurityElement]::Escape($Description))</Description>
                    <Author>$([System.Security.SecurityElement]::Escape($Author))</Author>
                    <SnippetTypes>
                        <SnippetType>Expansion</SnippetType>
                    </SnippetTypes>
                </Header>

                <Code>
                    <Script Language='PowerShell' CaretOffset='$CaretOffset'>
                        <![CDATA[$Text]]>
                    </Script>
                </Code>

        </Snippet>
    </Snippets>

"@

            $pathCharacters = '/\`*?[]:><"|.';
            $fileName=new-object text.stringBuilder
            for($ix=0; $ix -lt $Title.Length; $ix++)
            {
                $titleChar=$Title[$ix]
                if($pathCharacters.IndexOf($titleChar) -ne -1)
                {
                    $titleChar = "_"
                }

                $null = $fileName.Append($titleChar)
            }

            $params = @{
                FilePath = "$snippetPath\$fileName.snippets.ps1xml";
                Encoding = "UTF8"
            }

            if ($Force)
            {
                $params["Force"] = $true
            }
            else
            {
                $params["NoClobber"] = $true
            }

            $snippet | Out-File @params

            $psise.CurrentPowerShellTab.Snippets.Load($params["FilePath"])
        }
    }
}

function Open-StartupFolder{
    [cmdletbinding()]
    param()
    process{
        start 'shell:startup'
    }
}

<#
.SYNOPSIS 
This will inspect the nuspec file and return the value for the Version element.
#>
<#
function GetExistingVersion{
    [cmdletbinding()]
    param(
        [ValidateScript({test-path $_ -PathType Leaf})]
        $nuspecFile = (Join-Path $scriptDir 'mutant-chicken.nuspec')
    )
    process{
        ([xml](Get-Content $nuspecFile)).package.metadata.version
    }
}

function SetVersion{
    [cmdletbinding()]
    param(
        [Parameter(Position=1,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$newversion,

        [Parameter(Position=2)]
        [ValidateNotNullOrEmpty()]
        [string]$oldversion = (GetExistingVersion),

        [Parameter(Position=3)]
        [string]$filereplacerVersion = '0.4.0-beta'
    )
    begin{
        EnsureFileReplacerInstlled
    }
    process{
        $folder = $scriptDir
        $include = '*.nuspec;*.ps*1'
        # In case the script is in the same folder as the files you are replacing add it to the exclude list
        $exclude = "$($MyInvocation.MyCommand.Name);"
        $exclude += ';build.ps1'
        $replacements = @{
            "$oldversion"="$newversion"
        }
        Replace-TextInFolder -folder $folder -include $include -exclude $exclude -replacements $replacements | Write-Verbose

        # update the .psd1 file if there is one
        $replacements = @{
            ($oldversion.Replace('-beta','.1'))=($newversion.Replace('-beta','.1'))
        }
        Replace-TextInFolder -folder $folder -include '*.psd1' -exclude $exclude -replacements $replacements | Write-Verbose
        'Replacement complete' | Write-Verbose
    }
}
#>