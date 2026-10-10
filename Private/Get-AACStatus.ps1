function Get-AACStatus {
    <#
    .SYNOPSIS
        The module's one vocabulary for a state - its colour, symbol and
        word - so every command shows success, warnings, failures, work in
        progress and information the same way.
    .DESCRIPTION
          Status      Colour         Symbol (Unicode / ASCII)   Word
          Success     green3         ✓  /  +                     OK
          Warning     orange1        ⚠  /  !                     Warning
          Failed      red1           ✗  /  x                     Failed
          InProgress  deepskyblue1   ↻  /  ~                     In progress
          Info        grey70         ℹ  /  i                     Note

        The symbols are Get-AACGlyph's: Unicode when the console can show
        it, ASCII when it can't (a console on code page 437 or 850), so the
        status reads the same in any terminal - and its word goes with it, so
        nothing depends on colour alone.

        Returns @{ Name; Color; Glyph; Label; Markup } - Markup is the
        symbol in its colour, ready for Spectre.Console markup.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Success', 'Warning', 'Failed', 'InProgress', 'Info')]
        [string] $Status
    )

    $glyph = Get-AACGlyph
    $spec = @{
        Success    = @{ Color = 'green3'; Glyph = $glyph.Tick; Label = 'OK' }
        Warning    = @{ Color = 'orange1'; Glyph = $glyph.Warn; Label = 'Warning' }
        Failed     = @{ Color = 'red1'; Glyph = $glyph.Cross; Label = 'Failed' }
        InProgress = @{ Color = 'deepskyblue1'; Glyph = $glyph.Spin; Label = 'In progress' }
        Info       = @{ Color = 'grey70'; Glyph = $glyph.Info; Label = 'Note' }
    }[$Status]
    @{ Name = $Status; Color = $spec.Color; Glyph = $spec.Glyph; Label = $spec.Label; Markup = "[$($spec.Color)]$([Spectre.Console.Markup]::Escape($spec.Glyph))[/]" }
}
