[cmdletbinding()]
param()

$templateInfo = New-Object -TypeName psobject -Property @{
    Name = 'appveyor.ps1'
    Type = 'ItemTemplate'
}
$templateInfo | add-sourcefile -sourceFiles 'appveyor.ps1'
Set-TemplateInfo -templateInfo $templateInfo

$templateInfo = New-Object -TypeName psobject -Property @{
    Name = 'appveyor.yml'
    Type = 'ItemTemplate'
}
$templateInfo | add-sourcefile -sourceFiles 'appveyor.yml'
Set-TemplateInfo -templateInfo $templateInfo

$templateInfo = New-Object -TypeName psobject -Property @{
    Name = 'build.ps1'
    Type = 'ItemTemplate'
}
$templateInfo | add-sourcefile -sourceFiles 'build.ps1'
Set-TemplateInfo -templateInfo $templateInfo

$templateInfo = New-Object -TypeName psobject -Property @{
    Name = '.gitattributes'
    Type = 'ItemTemplate'
}
$templateInfo | add-sourcefile -sourceFiles 'gitattributes.txt' -destFiles {'.gitattributes'}
Set-TemplateInfo -templateInfo $templateInfo

$templateInfo = New-Object -TypeName psobject -Property @{
    Name = 'nuspec'
    Type = 'ItemTemplate'
}
$templateInfo | add-sourcefile -sourceFiles 'sample.nuspec' -destFiles {"$ItemName.nuspec"}
Set-TemplateInfo -templateInfo $templateInfo









<#
$templateInfo | update-filename (
    ,('controller.js', {"$ItemName.js"})
)#>
