[cmdletbinding()]
param(
    [string[]]$projFiles = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe"
)

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
            $timetaken = Measure-Command -Expression { &"C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe" $filepath --% /m /clp:v=m;Summary }
            
            @{
                'ProjectFile' = $filepath
                'Build (seconds)' = $timetaken
            }
        }
        #$timetaken = Measure-Command -Expression { &"C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\15.0\Bin\MSBuild.exe" --% "C:\Users\sayedha\source\repos\WebApplication20\WebApplication20\WebApplication20.csproj" /m /clp:v=m;Summary }
        #$timetaken.TotalSeconds
    }
}


GetBuildTime -projFile $projFiles