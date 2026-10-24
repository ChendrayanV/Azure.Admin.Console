function Write-AACRule {
    <#
    .SYNOPSIS
        Writes a Spectre.Console horizontal rule directly to the console.
    #>
    [CmdletBinding()]
    param(
        [string] $Title,

        [string] $Color = 'deepskyblue3_1'
    )

    $rule = [Spectre.Console.Rule]::new()
    if ($Title) {
        $rule.Title = $Title
    }
    $rule.Style = [Spectre.Console.Style]::Parse($Color)
    [Spectre.Console.AnsiConsole]::Write($rule)
}
