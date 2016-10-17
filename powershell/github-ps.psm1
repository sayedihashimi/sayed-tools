[cmdletbinding()]
param()

function CloneRepo{
    [cmdletbinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$user,

        [ValidateNotNullOrEmpty()]
        [string]$repo,

        [ValidateSet('ssh','https')]
        [string]$method = 'ssh'
    )
    process{
        # ssh pattern git@github.com:sayedihashimi/aspnettemplates.git
        # https pattern https://github.com/sayedihashimi/aspnettemplates.git

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

        & cmd.exe /C "git clone $url 2>&1"
        $gitexitcode = $LASTEXITCODE
        if($LASTEXITCODE -ne 0){
            throw $Error[0]
        }
    }
}