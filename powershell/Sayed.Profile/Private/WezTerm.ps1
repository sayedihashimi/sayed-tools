function Get-SayedWezTermKeys {
    <#
    .SYNOPSIS
    Shows the custom key and mouse bindings in the WezTerm config file.
    .DESCRIPTION
    Reads config.keys and config.mouse_bindings from ~/.wezterm.lua and shows a
    table of the shortcuts. The description comes from the '--' comment above
    each binding. WezTerm's built-in default bindings are not listed.
    .PARAMETER Path
    The WezTerm config file to read. Defaults to $env:WEZTERM_CONFIG_FILE, or
    ~/.wezterm.lua when that isn't set.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $(if ($env:WEZTERM_CONFIG_FILE) { $env:WEZTERM_CONFIG_FILE } else { Join-Path $HOME '.wezterm.lua' })
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Warning "WezTerm config file not found at '$Path'."
        return
    }
    $bindings = @(Get-SayedWezTermBinding -Text (Get-Content -LiteralPath $Path -Raw))
    if ($bindings.Count -eq 0) {
        Write-Warning "No custom key or mouse bindings found in '$Path'."
        return
    }
    $bindings | Format-Table -AutoSize -Wrap -Property @(
        'Type'
        @{ Name = 'Shortcut'; Expression = { "$($PSStyle.Bold)$($PSStyle.Foreground.Cyan)$($_.Shortcut)$($PSStyle.Reset)" } }
        'Action'
        'Description'
    )
}

function Initialize-SayedWezTermConfig {
    # Points WezTerm at the repo's config by setting WEZTERM_CONFIG_FILE once.
    # An existing value is never changed, so a machine can override it.
    # Only the saved value counts: WezTerm sets WEZTERM_CONFIG_FILE in every shell
    # it starts (to the file it loaded), so the process value is no signal.
    param(
        [string]$Path,
        [EnvironmentVariableTarget]$Target = $script:WezTermConfigTarget
    )
    if (-not $IsWindows) { return }
    $name = 'WEZTERM_CONFIG_FILE'
    $saved = [Environment]::GetEnvironmentVariable($name, $Target)
    if (-not $saved) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "WezTerm config not found at '$Path'." }
        $saved = (Resolve-Path -LiteralPath $Path).ProviderPath
        [Environment]::SetEnvironmentVariable($name, $saved, $Target)
        Write-Host "Set $name to '$saved'. Restart WezTerm to use it." -ForegroundColor DarkGray
    }
    # Keep WezTerm's value (the file it actually loaded) when it set one.
    if (-not [Environment]::GetEnvironmentVariable($name)) { [Environment]::SetEnvironmentVariable($name, $saved) }
}

function Get-SayedWezTermBinding {
    # Parses the key and mouse binding tables out of WezTerm Lua config text.
    param([AllowEmptyString()][string]$Text)

    # The leader key is shown so 'Leader+X' shortcuts make sense.
    $leader = [regex]::Match($Text, '(?m)^[ \t]*(?:config\.)?leader[ \t]*=[ \t]*\{')
    if ($leader.Success) {
        $open = $leader.Index + $leader.Length - 1
        $entry = $Text.Substring($open, (Find-SayedLuaTableEnd -Text $Text -Open $open) - $open + 1)
        [pscustomobject]@{
            Type        = 'Leader'
            Shortcut    = Format-SayedWezTermKey $entry
            Action      = 'Leader'
            Description = Get-SayedLuaCommentAbove -Text $Text -Index $leader.Index
        }
    }

    foreach ($table in @(
            @{ Type = 'Key'; Pattern = '(?m)^[ \t]*(?:config\.)?keys[ \t]*=[ \t]*\{' }
            @{ Type = 'Mouse'; Pattern = '(?m)^[ \t]*(?:config\.)?mouse_bindings[ \t]*=[ \t]*\{' }
        )) {
        $match = [regex]::Match($Text, $table.Pattern)
        if (-not $match.Success) { continue }
        $open = $match.Index + $match.Length - 1
        $close = Find-SayedLuaTableEnd -Text $Text -Open $open
        $tableComment = Get-SayedLuaCommentAbove -Text $Text -Index $match.Index
        $entries = @(Get-SayedLuaTableEntry -Text $Text -Open $open -Close $close)
        foreach ($entry in $entries) {
            $description = $entry.Comment
            # A comment above the whole table describes it when it has one entry.
            if (-not $description -and $entries.Count -eq 1) { $description = $tableComment }
            $shortcut = if ($table.Type -eq 'Key') { Format-SayedWezTermKey $entry.Text } else { Format-SayedWezTermMouse $entry.Text }
            [pscustomobject]@{
                Type        = $table.Type
                Shortcut    = $shortcut
                Action      = Format-SayedWezTermAction $entry.Text
                Description = $description
            }
        }
    }
}

function Skip-SayedLuaToken {
    # Returns the index after the string or comment starting at $Index, or -1.
    param([string]$Text, [int]$Index)
    $c = $Text[$Index]
    if ($c -eq '-' -and $Index + 1 -lt $Text.Length -and $Text[$Index + 1] -eq '-') {
        if ($Index + 3 -lt $Text.Length -and $Text.Substring($Index + 2, 2) -eq '[[') {
            $end = $Text.IndexOf(']]', $Index + 4)
            return $(if ($end -lt 0) { $Text.Length } else { $end + 2 })
        }
        $end = $Text.IndexOf("`n", $Index)
        return $(if ($end -lt 0) { $Text.Length } else { $end })
    }
    if ($c -eq "'" -or $c -eq '"') {
        $i = $Index + 1
        while ($i -lt $Text.Length -and $Text[$i] -ne $c) {
            if ($Text[$i] -eq '\') { $i++ }
            $i++
        }
        return $i + 1
    }
    -1
}

function Find-SayedLuaTableEnd {
    # Returns the index of the '}' that closes the '{' at $Open.
    param([string]$Text, [int]$Open)
    $depth = 0
    $i = $Open
    while ($i -lt $Text.Length) {
        $skip = Skip-SayedLuaToken -Text $Text -Index $i
        if ($skip -ge 0) { $i = $skip; continue }
        if ($Text[$i] -eq '{') { $depth++ }
        elseif ($Text[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $i } }
        $i++
    }
    throw 'WezTerm config has an unclosed table.'
}

function Get-SayedLuaTableEntry {
    # Returns each '{ ... }' entry directly inside a table, with its comment.
    param([string]$Text, [int]$Open, [int]$Close)
    $comments = [Collections.Generic.List[string]]::new()
    $last = $null
    $i = $Open + 1
    while ($i -lt $Close) {
        $c = $Text[$i]
        if ($c -eq '-' -and $Text[$i + 1] -eq '-') {
            $end = Skip-SayedLuaToken -Text $Text -Index $i
            $comment = ($Text.Substring($i, $end - $i) -replace '^--(\[\[)?|\]\]$', '').Trim()
            # A comment on the same line as an entry describes that entry, and
            # replaces a group comment above it.
            $sameLine = $last -and $Text.Substring($last.End, $i - $last.End) -notmatch "`n"
            if ($sameLine) { if ($comment) { $last.Comment = $comment } }
            elseif ($comment) { $comments.Add($comment) }
            $i = $end
            continue
        }
        $skip = Skip-SayedLuaToken -Text $Text -Index $i
        if ($skip -ge 0) { $i = $skip; continue }
        if ($c -eq '{') {
            $end = Find-SayedLuaTableEnd -Text $Text -Open $i
            $last = [pscustomobject]@{ Text = $Text.Substring($i, $end - $i + 1); Comment = ($comments -join ' '); End = $end + 1 }
            $last
            $comments.Clear()
            $i = $end + 1
            continue
        }
        $i++
    }
}

function Get-SayedLuaCommentAbove {
    # Returns the '--' comment lines directly above the line containing $Index.
    param([string]$Text, [int]$Index)
    $lines = $Text.Substring(0, $Index) -split '\r?\n'
    $comment = [Collections.Generic.List[string]]::new()
    for ($n = $lines.Count - 2; $n -ge 0; $n--) {
        if ($lines[$n] -notmatch '^\s*--(.*)$') { break }
        $comment.Insert(0, $Matches[1].Trim())
    }
    $comment -join ' '
}

function Get-SayedLuaField {
    param([string]$Entry, [string]$Name)
    if ($Entry -match "\b$Name\s*=\s*(['`"])(.*?)\1") { return $Matches[2] }
    if ($Entry -match "\b$Name\s*=\s*([\w.]+)") { return $Matches[1] }
}

function Format-SayedWezTermMods {
    param([string]$Mods)
    $names = @{ ALT = 'Alt'; OPT = 'Alt'; META = 'Alt'; CTRL = 'Ctrl'; SHIFT = 'Shift'; SUPER = 'Win'; CMD = 'Win'; WIN = 'Win'; LEADER = 'Leader' }
    @($Mods -split '[|\s]+' | Where-Object { $_ -and $_ -ne 'NONE' } | ForEach-Object {
            $name = $names[$_.ToUpperInvariant()]
            if ($name) { $name } else { $_ }
        })
}

function Format-SayedWezTermKey {
    param([string]$Entry)
    $key = (Get-SayedLuaField $Entry 'key') -replace '^(phys|mapped|raw):', ''
    if ($key.Length -eq 1) { $key = $key.ToUpperInvariant() }
    (@(Format-SayedWezTermMods (Get-SayedLuaField $Entry 'mods')) + $key) -join '+'
}

function Format-SayedWezTermMouse {
    param([string]$Entry)
    $kind = 'Down'; $button = '?'; $streak = 1
    if ($Entry -match '\bevent\s*=\s*\{\s*(Down|Up|Drag)\s*=\s*\{([^}]*)\}') {
        $kind = $Matches[1]
        $details = $Matches[2]
        if ($details -match "\bbutton\s*=\s*['`"](\w+)['`"]") { $button = $Matches[1] }
        if ($details -match '\bstreak\s*=\s*(\d+)') { $streak = [int]$Matches[1] }
    }
    $click = switch ($streak) { 1 { 'Click' } 2 { 'Double-Click' } 3 { 'Triple-Click' } default { "$streak-Click" } }
    $gesture = switch ($kind) { 'Up' { "$button $click (release)" } 'Drag' { "$button Drag" } default { "$button $click" } }
    (@(Format-SayedWezTermMods (Get-SayedLuaField $Entry 'mods')) + $gesture) -join '+'
}

function Format-SayedWezTermAction {
    param([string]$Entry)
    # Only the first 'action =' counts; nested ones belong to the action's arguments.
    if ($Entry -match '\baction\s*=\s*(\S+)' -and $Matches[1] -like 'wezterm.action_callback*') { return 'Callback' }
    if ($Entry -match "\baction\s*=\s*(?:wezterm\.action|act)\.(\w+)(?:\s*\(?\s*(['`"])(.*?)\2)?") {
        $name = $Matches[1]; $argument = $Matches[3]
        # A table of plain values, like AdjustPaneSize { 'Left', 5 }, is shown inline.
        if (-not $argument -and $Entry -match "\baction\s*=\s*(?:wezterm\.action|act)\.$name\s*\{([^{}=]*)\}") {
            $argument = (($Matches[1] -split ',') | ForEach-Object { $_.Trim().Trim("'", '"') } | Where-Object { $_ }) -join ' '
        }
        return ($name, $argument | Where-Object { $_ }) -join ' '
    }
    if ($Entry -match '\baction\s*=\s*([^,\r\n]+)') { return $Matches[1].Trim() }
}
