function ConvertTo-AACJsonMarkup {
    <#
    .SYNOPSIS
        Colours JSON text as Spectre.Console markup: property names, strings,
        numbers, true/false and null each in their own colour, the
        punctuation grey.
    .DESCRIPTION
          names     deepskyblue1     "location":
          strings   darkseagreen2    "westeurope"
          numbers   mediumpurple2    42
          booleans  gold1            true
          null      grey50 italic    null
          { } [ ] , grey50

        The text is tokenised, not parsed, so it keeps its own layout;
        everything is escaped, so a '[' inside a value stays text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $pattern = '(?<string>"(?:\\.|[^"\\])*")(?<colon>\s*:)?|(?<number>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(?<bool>\btrue\b|\bfalse\b)|(?<null>\bnull\b)|(?<punct>[{}\[\],])'
    $out = [System.Text.StringBuilder]::new()
    $at = 0
    foreach ($m in [regex]::Matches($Json, $pattern)) {
        if ($m.Index -gt $at) { $null = $out.Append((& $escape $Json.Substring($at, $m.Index - $at))) }
        if ($m.Groups['string'].Success) {
            $color = if ($m.Groups['colon'].Success) { 'deepskyblue1' } else { 'darkseagreen2' }
            $null = $out.Append("[$color]$(& $escape $m.Groups['string'].Value)[/]")
            if ($m.Groups['colon'].Success) { $null = $out.Append("[grey50]$(& $escape $m.Groups['colon'].Value)[/]") }
        }
        elseif ($m.Groups['number'].Success) { $null = $out.Append("[mediumpurple2]$($m.Value)[/]") }
        elseif ($m.Groups['bool'].Success) { $null = $out.Append("[gold1]$($m.Value)[/]") }
        elseif ($m.Groups['null'].Success) { $null = $out.Append('[grey50 italic]null[/]') }
        else { $null = $out.Append("[grey50]$(& $escape $m.Value)[/]") }
        $at = $m.Index + $m.Length
    }
    if ($at -lt $Json.Length) { $null = $out.Append((& $escape $Json.Substring($at))) }
    $out.ToString()
}
