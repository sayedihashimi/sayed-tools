# run the build script
$scriptDir = split-path -parent $MyInvocation.MyCommand.Definition

$genTemplatePath = (Join-Path $scriptDir 'powershell\dotnet\gen-template-report.ps1')

& $genTemplatePath -publishJsonReport
