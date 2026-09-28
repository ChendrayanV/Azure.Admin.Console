function Get-AACGlyph {
    <#
    .SYNOPSIS
        The symbols the console views use - bullet, separator, arrow,
        chevron, tick - in Unicode when the console can show them, and as
        ASCII when it can't.
    .DESCRIPTION
        A console whose output encoding isn't UTF-8 (Windows consoles often
        default to code page 437 or 850) turns characters it doesn't have,
        such as '●' or '→', into '?'. Spectre.Console already falls back to
        ASCII for its own borders, bars and spinners in that case (its
        Profile.Capabilities.Unicode is false); this does the same for the
        module's own symbols, so the views read cleanly in any console:

          Name      Unicode   ASCII
          Bullet    ●         *
          Dot       ·         -
          Arrow     →         ->
          Chevron   ›         >
          Tick      ✓         +
          Cross     ✗         x

        Returns a hashtable, e.g. $glyph = Get-AACGlyph; "$($glyph.Dot)".
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ([Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode) {
        @{ Bullet = [string][char]0x25CF; Dot = [string][char]0x00B7; Arrow = [string][char]0x2192; Chevron = [string][char]0x203A; Tick = [string][char]0x2713; Cross = [string][char]0x2717 }
    }
    else {
        @{ Bullet = '*'; Dot = '-'; Arrow = '->'; Chevron = '>'; Tick = '+'; Cross = 'x' }
    }
}
