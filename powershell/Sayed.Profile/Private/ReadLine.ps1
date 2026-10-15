function Initialize-SayedReadLine(){
    Import-Module PSReadLine -ErrorAction Stop
    # Enhanced PowerShell Experience
    # Enhanced PSReadLine Configuration
    $PSReadLineOptions = @{
        EditMode = 'Windows'
        HistoryNoDuplicates = $true
        HistorySearchCursorMovesToEnd = $true
        Colors = @{
            Command = '#87CEEB'  # SkyBlue (pastel)
            Parameter = '#98FB98'  # PaleGreen (pastel)
            Operator = '#FFB6C1'  # LightPink (pastel)
            Variable = '#DDA0DD'  # Plum (pastel)
            String = '#FFDAB9'  # PeachPuff (pastel)
            Number = '#B0E0E6'  # PowderBlue (pastel)
            Type = '#F0E68C'  # Khaki (pastel)
            Comment = '#D3D3D3'  # LightGray (pastel)
            Keyword = '#8367c7'  # Violet (pastel)
            Error = '#FF6347'  # Tomato (keeping it close to red for visibility)
        }
        PredictionSource = $script:Settings.PredictionSource
        MaximumHistoryCount = $script:Settings.MaximumHistoryCount
        # Inline suggestions avoid list redraw artifacts with multiline prompts.
        PredictionViewStyle = $script:Settings.PredictionViewStyle
        BellStyle = 'None'
    }
    Set-PSReadLineOption @PSReadLineOptions

    # Custom key handlers
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
    Set-PSReadLineKeyHandler -Chord 'Ctrl+w' -Function BackwardDeleteWord
    Set-PSReadLineKeyHandler -Chord 'Alt+d' -Function DeleteWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
    Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo

    # Custom functions for PSReadLine
    Set-PSReadLineOption -AddToHistoryHandler {
        param($line)
        $sensitive = @('password', 'secret', 'token', 'apikey', 'connectionstring')
        $hasSensitive = $sensitive | Where-Object { $line -match $_ }
        return ($null -eq $hasSensitive)
    }

    if (Get-Command Set-PredictionSource_Override -ErrorAction SilentlyContinue) { Set-PredictionSource_Override }
}
