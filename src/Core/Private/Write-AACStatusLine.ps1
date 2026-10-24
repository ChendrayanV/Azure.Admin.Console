function Write-AACStatusLine {
    <#
    .SYNOPSIS
        Writes one status line to the console: the state's symbol, the
        message, and a grey detail.
    .DESCRIPTION
          ✓ Disconnected admin@contoso.com.
          ⚠ The security recommendations couldn't be read  Forbidden
          ✗ 3 resources are unavailable  Resource Health

        The symbol and its colour come from Get-AACStatus, so a status line
        looks the same in every command. The message and the detail are
        plain text (escaped); -Markup takes the message as Spectre.Console
        markup instead.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Success', 'Warning', 'Failed', 'InProgress', 'Info')]
        [string] $Status,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()]
        [string] $Message,

        [string] $Detail,

        # Spaces before the symbol.
        [int] $Indent = 0,

        [switch] $Markup
    )

    $state = Get-AACStatus $Status
    $text = if ($Markup) { $Message } else { [Spectre.Console.Markup]::Escape($Message) }
    $tone = if ($Status -eq 'Info') { 'grey70' } else { 'white' }
    $line = "$(' ' * $Indent)$($state.Markup) [$tone]$text[/]"
    if ($Detail) { $line += "  [grey58]$([Spectre.Console.Markup]::Escape($Detail))[/]" }
    [Spectre.Console.AnsiConsole]::MarkupLine($line)
}
