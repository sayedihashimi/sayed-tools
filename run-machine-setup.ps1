
# to run this script execute:
#  (new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/run-machine-setup.ps1") | iex

$runningAsAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")

if(-not $runningAsAdmin){
    throw 'Rerun this script as an admin'
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
# download the file and run it
$machineSetupUrl = 'https://raw.githubusercontent.com/sayedihashimi/sayed-tools/master/machine-setup.ps1'
$expectedFilepath = (join-path $env:TEMP 'SayedHamachineSetup\machine-setup.ps1')

if(test-path $expectedFilepath -PathType Leaf){
    Remove-Item -Path $expectedFilepath
}

if(-not (Test-Path $expectedFilepath)){
    New-Item -Path ([System.IO.Path]::GetDirectoryName($expectedFilepath)) -ItemType Directory
}

Invoke-WebRequest -Uri $machineSetupUrl -OutFile $expectedFilepath

. $expectedFilepath



