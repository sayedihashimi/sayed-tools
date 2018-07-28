[cmdletbinding()]
param()

function CloneRepo{
    [cmdletbinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Position=0)]
        [string]$user,

        [Parameter(Position=2)]
        [string]$repo,

        [Parameter(Position=3)]
        [string]$directory,

        [ValidateSet('ssh','https')]
        [Parameter(Position=4)]
        [string]$method = 'ssh'
    )
    process{
        # ssh pattern git@github.com:sayedihashimi/aspnettemplates.git
        # https pattern https://github.com/sayedihashimi/aspnettemplates.git

        if(-not ([string]::IsNullOrWhiteSpace($user)) -and ([string]::IsNullOrWhiteSpace($repo)) -and ($user.Contains('/'))){
            $parts = $user.split('/')
            if($parts.Length -eq 2){
                $user = $parts[0]
                $repo = $parts[1]
            }    
        }

        switch ($method){
            'ssh' {
                $url = ('git@github.com:{0}/{1}.git' -f $user, $repo)
            }

            'https' {
                $url = ('https://github.com/{0}/{1}.git' -f $user, $repo)
            }

            'default' {
                throw ('Unknown value for clone method [{0}]' -f $method)
            }
        }
        "CloneUrl: $url" | Write-Verbose
        $expectedPath = (Join-Path $pwd $repo)
        [string]$extraArgs = ''
        if(-not ([string]::IsNullOrWhiteSpace($directory))){
            $extraArgs = ("{0}" -f $directory)
            $expectedPath = (Join-Path $pwd $directory)
        }

        if( (CommandExists 'cmd.exe') ){
            & cmd.exe /C "git clone $url $extraArgs 2>&1"
        }
        else{
            # likely not running on windows
            & git clone $url $extraArgs 2>&1
        }
        $gitexitcode = $LASTEXITCODE
        if($LASTEXITCODE -ne 0){
            throw $Error[0]
        }

        
        
        if(Test-Path $expectedPath){
            Set-Location $expectedPath
        }
    }
}


function CommandExists(){
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [string]$command
    )
    process{
        [bool]$exists = $false
        try{
            if( (get-command $command -ErrorAction SilentlyContinue)) {
                $exists = $true
            }
        }
        catch{
            $exists = $false
        }

        $exists
    }
}