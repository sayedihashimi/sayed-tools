$script:ModuleRoot = $PSScriptRoot
$script:Initialized = $false
$script:StartupStatus = [Collections.Generic.List[object]]::new()
foreach ($file in @('Configuration', 'Utilities', 'Modules', 'ReadLine', 'Integrations', 'Startup', 'Claude', 'WezTerm')) {
    . (Join-Path $PSScriptRoot "Private/$file.ps1")
}
# The manifest defines the public interface. Importing defines commands only.
