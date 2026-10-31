# Run in a disposable pwsh -NoProfile process. No provisioning or network access.
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$modulePath = Join-Path $PSScriptRoot '../Sayed.Profile.psd1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('sayed-profile-test-' + [guid]::NewGuid())
$originalPath = $env:PATH
$originalModules = $env:PSModulePath
$originalLocation = Get-Location
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Get-FunctionText($File, $Name) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $true)
    Assert ($null -ne $fn) "Function not found: $Name"
    $fn.Extent.Text
}
try {
    New-Item -ItemType Directory $tempRoot | Out-Null
    $allFiles = @(Get-ChildItem (Join-Path $repo 'powershell/Sayed.Profile') -Recurse -File | Where-Object Extension -In '.ps1', '.psm1', '.psd1') + @(
        (Get-Item (Join-Path $repo 'machine-setup-new.ps1'))
        (Get-Item (Join-Path $repo 'powershell/profile.ps1'))
        (Get-Item (Join-Path $repo 'powershell/shared/Paths.ps1'))
        (Get-Item (Join-Path $repo 'powershell/sayed-tools/sayed-tools.psm1'))
    )
    foreach ($file in $allFiles) {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert (-not $errors) "Syntax errors: $($file.FullName): $errors"
    }
    Import-Module $modulePath -DisableNameChecking
    $module = Get-Module Sayed.Profile
    Assert ($env:PSModulePath -eq $originalModules) 'Import changed PSModulePath'
    Assert ($env:PATH -eq $originalPath) 'Import changed PATH'
    Assert (@(Get-SayedProfileStatus).Count -eq 0) 'Import initialized the profile'
    Assert (-not (Get-Command Get-SayedNativeScript -ErrorAction SilentlyContinue)) 'Private helper was exported'
    # Stub Claude so launcher checks never start a real session.
    Assert ((Get-Command Start-MyClaude).Name -ceq 'Start-MyClaude') 'Claude launcher export or casing is incorrect'
    $claudeRoot = Join-Path $tempRoot 'claude project [fixture]'
    $featureDir = Join-Path $claudeRoot 'features/my-feature/subdir'
    $workstreamDir = Join-Path $claudeRoot 'docs'
    New-Item -ItemType Directory -Path $featureDir, $workstreamDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $claudeRoot '.claude-project') ''
    $initDir = Join-Path $tempRoot 'init project [fixture]'
    New-Item -ItemType Directory -Path $initDir | Out-Null
    $marker = Init-MyClaudeProject -Path $initDir
    Assert ($marker.Name -eq '.claude-project') 'Claude initializer returned the wrong marker'
    Assert ((Get-Content -LiteralPath $marker.FullName -Raw).Contains('Do not delete')) 'Claude marker reminder is missing'
    $notesDir = 'C:\data\Dropbox\sayedha-notes\jetbrains\JetBrains'
    $localSettingsPath = Join-Path $initDir '.claude/settings.local.json'
    $localSettings = Get-Content -LiteralPath $localSettingsPath -Raw | ConvertFrom-Json -AsHashtable
    Assert (@($localSettings.permissions.additionalDirectories) -ceq $notesDir) 'Claude initializer did not create local settings'
    Set-Content -LiteralPath $localSettingsPath '{ "model": "keep", "permissions": { "allow": ["Read"], "additionalDirectories": ["C:\\other"] } }'
    $null = Init-MyClaudeProject -Path $initDir
    $null = Init-MyClaudeProject -Path $initDir
    $localSettings = Get-Content -LiteralPath $localSettingsPath -Raw | ConvertFrom-Json -AsHashtable
    Assert ($localSettings.model -eq 'keep' -and @($localSettings.permissions.allow) -ceq 'Read') 'Claude initializer lost existing local settings'
    Assert ((@($localSettings.permissions.additionalDirectories) -join '|') -ceq "C:\other|$notesDir") 'Claude initializer did not add the notes directory exactly once'
    Set-Content -LiteralPath $marker.FullName 'preserve existing marker'
    $feature = New-MyClaudeFeature 'my new feature' -Path $initDir
    Assert ($feature.FullName -eq (Join-Path $initDir 'features/my new feature')) 'Feature initializer returned the wrong folder'
    Assert (Test-Path -LiteralPath (Join-Path $feature.FullName '.claude-project') -PathType Leaf) 'Feature initializer did not run imc'
    Assert (Test-Path -LiteralPath (Join-Path $feature.FullName '.claude/settings.local.json') -PathType Leaf) 'Feature initializer did not create local settings'
    $null = New-MyClaudeFeature 'my new feature' -Path $initDir
    $failed = $false
    try { New-MyClaudeFeature '../escape' -Path $initDir } catch { $failed = $true }
    Assert ($failed -and -not (Test-Path -LiteralPath (Join-Path $initDir 'escape'))) 'Feature initializer accepted a path as the name'
    Push-Location -LiteralPath $initDir
    try {
        $null = Init-MyClaudeProject
        Assert ((Get-Content -LiteralPath $marker.FullName -Raw).Trim() -eq 'preserve existing marker') 'Claude initializer overwrote an existing marker'
        Remove-Item -LiteralPath $marker.FullName
        $null = Init-MyClaudeProject
        Assert (Test-Path -LiteralPath $marker.FullName -PathType Leaf) 'Claude initializer did not use the current directory'
        Remove-Item -LiteralPath $marker.FullName
        New-Item -ItemType Directory -Path $marker.FullName | Out-Null
        $failed = $false
        try { Init-MyClaudeProject } catch { $failed = $true }
        Assert $failed 'Claude initializer accepted a directory as the marker'
    }
    finally { Pop-Location }
    function global:claude {
        $global:ClaudeFixtureCall = @{ Arguments = @($args); Location = (Get-Location).ProviderPath }
        if ($global:ClaudeFixtureThrow) { throw 'simulated Claude failure' }
    }
    try {
        foreach ($case in @(
            @{ Directory = $featureDir; Context = 'features/my-feature/subdir'; Feature = $true }
            @{ Directory = $workstreamDir; Context = 'docs'; Feature = $false }
            @{ Directory = $claudeRoot; Context = '.'; Feature = $false }
        )) {
            Set-Location -LiteralPath $case.Directory
            $stackBefore = (Get-Location -Stack).Count
            Start-MyClaude
            Assert ($global:ClaudeFixtureCall.Location -eq $claudeRoot) 'Claude launched outside the project root'
            $arguments = $global:ClaudeFixtureCall.Arguments
            $expectedArgumentCount = if ($case.Feature) { 5 } else { 4 }
            Assert ($arguments.Count -eq $expectedArgumentCount -and $arguments[0] -eq '--append-system-prompt') 'Claude prompt argument was split or incorrect'
            Assert ($arguments[2] -ceq '--name' -and $arguments[3] -ceq (Split-Path -Leaf $case.Directory)) 'Claude session was not named after the current folder'
            if ($case.Feature) {
                Assert ($arguments[4] -ceq "/work-on-feature `"$($case.Context)`"") 'Claude feature skill was not passed as the initial message'
            }
            Assert ($arguments[1].Contains("'$($case.Context)'")) 'Claude relative context is incorrect'
            Assert ($arguments[1].Contains('work-on-feature') -eq $case.Feature) 'Claude selected the wrong prompt'
            Assert ((Get-Location).ProviderPath -eq $case.Directory) 'Claude launcher did not restore location'
            Assert ((Get-Location -Stack).Count -eq $stackBefore) 'Claude launcher leaked a location stack entry'
            Start-MyClaude -Resume
            $resumeArguments = $global:ClaudeFixtureCall.Arguments
            Assert ($resumeArguments.Count -eq 3 -and $resumeArguments[2] -ceq '--resume') 'Resume must forward --resume without an initial feature command'
            Assert ($resumeArguments[0] -ceq '--append-system-prompt' -and $resumeArguments[1] -ceq $arguments[1]) 'Resume changed the Claude context'
            Assert ($global:ClaudeFixtureCall.Location -eq $claudeRoot) 'Resume launched outside the project root'
            Assert ((Get-Location).ProviderPath -eq $case.Directory) 'Resume did not restore location'
            Assert ((Get-Location -Stack).Count -eq $stackBefore) 'Resume leaked a location stack entry'
            Start-MyClaude -Resume 'session-123'
            $sessionArguments = $global:ClaudeFixtureCall.Arguments
            Assert ($sessionArguments.Count -eq 4 -and $sessionArguments[2] -ceq '--resume' -and $sessionArguments[3] -ceq 'session-123') 'Resume must forward the session ID'
            Assert ($global:ClaudeFixtureCall.Location -eq $claudeRoot) 'Resume with session ID launched outside the project root'
        }
        $global:ClaudeFixtureThrow = $true
        $failed = $false
        try { Start-MyClaude } catch { $failed = $_.Exception.Message -eq 'simulated Claude failure' }
        Assert $failed 'Claude failure was swallowed'
        Assert ((Get-Location).ProviderPath -eq $claudeRoot) 'Claude failure did not restore location'
        $global:ClaudeFixtureThrow = $false
        Set-Content -LiteralPath (Join-Path $workstreamDir '.custom-marker') ''
        Set-Location -LiteralPath $workstreamDir
        Start-MyClaude -MarkerFile '.custom-marker'
        Assert ($global:ClaudeFixtureCall.Location -eq $workstreamDir) 'Custom Claude marker was ignored'
        Set-Content -LiteralPath (Join-Path $workstreamDir '.claude-project') ''
        Start-MyClaude
        Assert ($global:ClaudeFixtureCall.Location -eq $workstreamDir) 'Nearest Claude project root was ignored'
        $global:ClaudeFixtureCall = $null
        $failed = $false
        try { Start-MyClaude -MarkerFile '.missing-marker' } catch { $failed = $_.Exception.Message -like 'Could not find a Claude project root.*' }
        Assert ($failed -and $null -eq $global:ClaudeFixtureCall) 'Missing Claude marker did not prevent launch'
    }
    finally {
        Set-Location -LiteralPath $originalLocation.Path
        Remove-Item Function:\claude -ErrorAction SilentlyContinue
        Remove-Variable ClaudeFixtureCall, ClaudeFixtureThrow -Scope Global -ErrorAction SilentlyContinue
    }
    function global:git { throw 'Profile startup must not configure Git.' }
    function global:winget { throw 'Profile startup must not install software.' }
    Initialize-SayedProfile -Configuration @{ Interactive = $false; EnableCustomModules = $false }
    Assert ((Get-Alias smc).Definition -ceq 'Start-MyClaude') 'Claude launcher alias is incorrect'
    Assert ((Get-Alias imc).Definition -ceq 'Init-MyClaudeProject') 'Claude initializer alias is incorrect'
    Assert ((Get-Alias nmf).Definition -ceq 'New-MyClaudeFeature') 'Claude feature alias is incorrect'
    $aliasTable = Get-SayedProfileAlias | Out-String -Width 300
    Assert ($aliasTable -match '\bsmc\s+Start-MyClaude\s+Sayed\.Profile' -and $aliasTable -notmatch '\bgcb\b') 'Profile alias table is incorrect'
    Assert ((Get-Alias cdcp).Definition -ceq 'Enter-MyClaudeProjects') 'Claude projects alias is incorrect'
    Assert (-not (Get-SayedProfileStatus | Where-Object Status -EQ Failed)) 'Core initialization failed'
    $firstCount = @(Get-SayedProfileStatus).Count
    $firstModules = $env:PSModulePath
    $stack = (Get-Location -Stack).Count
    Initialize-SayedProfile
    Assert (@(Get-SayedProfileStatus).Count -eq $firstCount) 'Repeated initialization ran again'
    Initialize-SayedProfile -Force -Configuration @{ Interactive = $false; EnableCustomModules = $false }
    Assert ($env:PSModulePath -eq $firstModules) 'Repeated initialization duplicated module paths'
    Assert ((Get-Location -Stack).Count -eq $stack) 'Initialization leaked a location stack entry'
    Assert ((Get-Location).Path -eq $originalLocation.Path) 'Initialization changed directory'
    $invalidRejected = $false
    try { Initialize-SayedProfile -Force -Configuration @{ TypoSetting = $true } }
    catch { $invalidRejected = $true }
    Assert $invalidRejected 'Unknown configuration setting was accepted'
    $localSettings = Join-Path $tempRoot 'settings.psd1'
    Set-Content $localSettings "@{ ThemeName = 'local-theme'; PredictionViewStyle = 'ListView' }"
    $merged = & $module { param($path) Get-SayedProfileConfiguration -ConfigurationPath $path -Overrides @{ ThemeName = 'explicit-theme' } } $localSettings
    Assert ($merged.ThemeName -eq 'explicit-theme' -and $merged.PredictionViewStyle -eq 'ListView') 'Configuration precedence failed'
    $resolved = @(Resolve-FullPath @($tempRoot, $repo))
    Assert ($resolved.Count -eq 2 -and $resolved[0] -eq $tempRoot -and $resolved[1] -eq $repo) 'Array path resolution failed'
    $one = Join-Path $tempRoot 'tools'; $two = Join-Path $tempRoot 'tools-extra'
    New-Item -ItemType Directory $one, $two | Out-Null
    $env:PATH = $two
    Add-Path @($one, $tempRoot)
    $entries = @($env:PATH -split [IO.Path]::PathSeparator)
    Assert ($entries.Count -eq 3 -and $one -in $entries -and $tempRoot -in $entries) 'PATH additions lost entries or used substring matching'
    Add-Path @($one, $tempRoot)
    Assert (@($env:PATH -split [IO.Path]::PathSeparator).Count -eq 3) 'PATH addition duplicated entries'
    $env:PATH = $originalPath
    Add-AliasForTool @{ alias = 'sayed-test-alias'; path = @((Join-Path $tempRoot 'missing.exe'), ($PSHOME + '/pwsh.exe')) }
    Assert ((Get-Alias sayed-test-alias).Definition -eq ($PSHOME + '/pwsh.exe')) 'Alias fallback failed'

    # Both modules in one directory must load, and the first directory must win.
    $rootA = Join-Path $tempRoot 'modules-a'; $rootB = Join-Path $tempRoot 'modules-b'
    New-Item -ItemType Directory $rootA, $rootB | Out-Null
    Set-Content (Join-Path $rootA 'ProfileFixtureOne.psm1') "function Get-ProfileFixtureOne { 'first' }"
    Set-Content (Join-Path $rootB 'ProfileFixtureOne.psm1') "function Get-ProfileFixtureOne { 'second' }"
    Set-Content (Join-Path $rootA 'ProfileFixtureTwo.psm1') "function Get-ProfileFixtureTwo { 'two' }"
    Initialize-SayedProfile -Force -Configuration @{ Interactive = $false; CustomModuleNames = @('ProfileFixtureOne', 'ProfileFixtureTwo'); CustomModulePaths = @($rootA, $rootB) }
    Assert ((Get-ProfileFixtureOne) -eq 'first') 'Module search precedence failed'
    Assert ((Get-ProfileFixtureTwo) -eq 'two') 'Multiple modules in one directory did not load'

    # Deterministic fault injection: no actual prompt, terminal, or network needed.
    & $module {
        $script:Events = [Collections.Generic.List[string]]::new()
        function script:Initialize-SayedReadLine { $script:Events.Add('ReadLine'); throw 'simulated rendering failure' }
        function script:Initialize-SayedZoxide { $script:Events.Add('Zoxide'); throw 'simulated missing zoxide' }
        function script:Initialize-SayedDotnetCompletions { $script:Events.Add('Dotnet'); throw 'simulated missing SDK' }
        function script:Initialize-SayedPrompt { $script:Events.Add('Prompt') }
    }
    Initialize-SayedProfile -Force -Configuration @{ Interactive = $true; EnableCustomModules = $false } -WarningVariable failures -WarningAction SilentlyContinue
    $events = & $module { $script:Events.ToArray() }
    Assert (($events -join ',') -eq 'ReadLine,Zoxide,Dotnet,Prompt') 'A failed component stopped later initialization'
    Assert (@(Get-SayedProfileStatus | Where-Object Status -EQ Failed).Count -eq 3) 'Failure details were not retained'

    # Existing configured themes work even when package enumeration is unavailable.
    $theme = Join-Path $tempRoot 'theme.omp.json'
    Set-Content $theme '{}'
    $foundTheme = & $module { param($theme) $script:Settings.ThemePath = $theme; Find-SayedTheme } $theme
    Assert ($foundTheme -eq $theme) 'Explicit theme lookup failed'
    $themeFolder = Join-Path $tempRoot 'themes'; New-Item -ItemType Directory $themeFolder | Out-Null
    Set-Content (Join-Path $themeFolder '1_shell.omp.json') '{}'
    $previousThemes = $env:POSH_THEMES_PATH
    try {
        $env:POSH_THEMES_PATH = $themeFolder
        $foundTheme = & $module { $script:Settings.ThemePath = ''; Find-SayedTheme }
        Assert ($foundTheme -eq (Join-Path $themeFolder '1_shell.omp.json')) 'Theme environment fallback failed'
    }
    finally { $env:POSH_THEMES_PATH = $previousThemes }

    # Native script stdout must exclude diagnostic stderr, with exit codes enforced.
    $ok = Join-Path $tempRoot 'ok.ps1'
    Set-Content $ok '[Console]::Error.WriteLine("diagnostic"); Write-Output "valid script"; exit 0'
    $native = & $module { param($exe, $file) Get-SayedNativeScript $exe @('-NoProfile', '-File', $file) } (Join-Path $PSHOME 'pwsh.exe') $ok
    Assert ($native -eq 'valid script') 'Native stderr contaminated executable script'
    foreach ($body in @('exit 0', '[Console]::Error.WriteLine("failed"); exit 2')) {
        Set-Content $ok $body
        $rejected = $false
        try { & $module { param($exe, $file) Get-SayedNativeScript $exe @('-NoProfile', '-File', $file) } (Join-Path $PSHOME 'pwsh.exe') $ok }
        catch { $rejected = $true }
        Assert $rejected 'Empty or unsuccessful native script was accepted'
    }

    # Extract setup definitions only: never execute its provisioning entry point.
    $setup = Join-Path $repo 'machine-setup-new.ps1'
    foreach ($name in @('Get-Fullpath', 'Add-Path', 'ConfigurePowershell', 'LoadModules')) { . ([scriptblock]::Create((Get-FunctionText $setup $name))) }
    $global:sayedhaToolsFolderPath = $repo
    $global:pcSettingsDirPath = $null
    $destination = Join-Path $tempRoot 'profile-directory/profile.ps1'
    ConfigurePowershell -psProfilePath $destination
    Assert ((Get-Content $destination -Raw) -eq (Get-Content (Join-Path $repo 'powershell/profile.ps1') -Raw)) 'Setup did not install the repository bootstrap'
    Set-Content $destination 'existing profile'
    ConfigurePowershell -psProfilePath $destination
    Assert ((Get-Content $destination -Raw).Trim() -eq 'existing profile') 'Setup overwrote an existing profile'
    $explicit = Join-Path $tempRoot 'explicit-profile.ps1'
    ConfigurePowershell -psProfilePath $explicit -sourceProfilePath $destination
    Assert ((Get-Content $explicit -Raw).Trim() -eq 'existing profile') 'Explicit setup profile source stopped working'
    $realRepo = $global:sayedhaToolsFolderPath
    try {
        $global:sayedhaToolsFolderPath = Join-Path $tempRoot 'uncloned-repo'
        $global:pcSettingsDirPath = Join-Path $tempRoot 'old-settings'
        $oldSource = Join-Path $global:pcSettingsDirPath 'powershell/sayed-profile-script-current.ps1'
        New-Item -ItemType Directory (Split-Path $oldSource) -Force | Out-Null
        Set-Content $oldSource 'legacy fallback'
        $fallbackDestination = Join-Path $tempRoot 'fallback-profile.ps1'
        ConfigurePowershell -psProfilePath $fallbackDestination
        Assert ((Get-Content $fallbackDestination -Raw).Trim() -eq 'legacy fallback') 'Setup Dropbox fallback stopped working'
    }
    finally { $global:sayedhaToolsFolderPath = $realRepo }
    LoadModules 4>$null 6>$null
    Assert ($null -ne (Get-Command Sayed-ConfigureGit)) 'Setup helper API is unavailable'
    $env:PATH = $two
    Add-Path @($one, $tempRoot)
    Assert (@($env:PATH -split [IO.Path]::PathSeparator).Count -eq 3) 'Setup PATH helper lost additions'
    # Exercise real orchestration with provisioning commands replaced by inert stubs.
    foreach ($name in @('RunTask', 'ConfigureMachine')) { . ([scriptblock]::Create((Get-FunctionText $setup $name))) }
    $script:SetupEvents = [Collections.Generic.List[string]]::new()
    $global:machinesetupconfig = @{ MachineSetupAppsFolder = $tempRoot }
    function EnsureFolderExists { param($path) }
    foreach ($name in @('Install-WingetApps', 'Install-NpmGlobalPackages', 'Install-Prompt', 'ConfigureGit', 'EnsureBaseReposCloned', 'ConfigurePowershell', 'ConfigureConsole', 'LoadModules', 'ConfigureWindows')) {
        Set-Item -Path "Function:$name" -Value ([scriptblock]::Create("[void]`$script:SetupEvents.Add('$name')"))
    }
    ConfigureMachine
    Assert (($script:SetupEvents -join ',') -eq 'Install-WingetApps,Install-NpmGlobalPackages,Install-Prompt,ConfigureGit,EnsureBaseReposCloned,ConfigurePowershell,ConfigureConsole,LoadModules,ConfigureWindows') 'Setup orchestration changed or skipped tasks'
    Write-Host 'PASS: parsing, import purity, repeatability, paths, aliases, module discovery, failure isolation, themes, native scripts, and setup compatibility.'
}
finally {
    Remove-Item Function:\git, Function:\winget -ErrorAction SilentlyContinue
    $env:PATH = $originalPath
    $env:PSModulePath = $originalModules
    Set-Location -LiteralPath $originalLocation.Path
    # Only remove this test's uniquely named directory beneath the OS temp directory.
    if ($tempRoot -and (Split-Path $tempRoot -Leaf) -like 'sayed-profile-test-*' -and (Split-Path $tempRoot -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\', '/')) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
