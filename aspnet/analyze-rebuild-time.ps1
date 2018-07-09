[cmdletbinding()]
param(
    [string[]]$projFiles = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe"
)

function InternalGet-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}

$scriptDir = ((InternalGet-ScriptDirectory) + "\")

function Get-Fullpath{
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline = $true)]
        $path,

        $workingDir = ($pwd)
    )
    process{
        $fullPath = $path
        $oldPwd = $pwd

        Push-Location
        Set-Location $workingDir
        [Environment]::CurrentDirectory = $pwd
        $fullPath = ([System.IO.Path]::GetFullPath($path))
        
        Pop-Location
        [Environment]::CurrentDirectory = $oldPwd

        return $fullPath
    }
}

function GetBuildTime{
    [cmdletbinding()]
    param(
        [string[]]$projFile
    )
    process{
        foreach($proj in $projFile){
            $filepath = (Get-fullpath -path $proj)
            $timetaken = Measure-Command -Expression {
                &"C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe" $filepath --% /m /clp:v=m;Summary 
            }
            
            @{
                'ProjectFile' = $filepath
                'Build (seconds)' = $timetaken
            }
        }
        #$timetaken = Measure-Command -Expression { &"C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe" --% "C:\Users\sayedha\source\repos\WebApplication20\WebApplication20\WebApplication20.csproj" /m /clp:v=m;Summary }
        #$timetaken.TotalSeconds
    }
}

function UpdateCodeFile{
    [cmdletbinding()]
    param(
        [string]$projectFile = (get-fullpath (join-path $scriptDir 'rebuild\src\Wap01\Wap01.csproj')),
        [string]$codeFileRelpath = 'Controllers\HomeController.cs',
        [string]$regex = 'int foo = (\d);'
    )
    process{
        $codeFileFullpath = (Get-Fullpath (Join-Path -Path ([IO.Path]::GetDirectoryName($projectFile)) -ChildPath $codeFileRelpath))
        if(-not (test-path $codeFileFullpath)){
            throw ('Couldn''t code file at: [{0}]' -f $codeFileFullpath)
        }

        [int]$newInt = Get-Random
        $filecontent = get-content $codeFileFullpath
        if($filecontent -match $regex){
            $filecontent -replace $regex, "int foo = $newInt;" | set-content $codeFileFullpath
        }
        <#
           $content = Get-Content $file
            if ( $content -match "^$key\s*=" ) {
                $content -replace "^$key\s*=.*", "$key = $value" |
                Set-Content $file     
            } else {
                Add-Content $file "$key = $value"
            }
        #>

    }
}

GetBuildTime -projFile $projFiles