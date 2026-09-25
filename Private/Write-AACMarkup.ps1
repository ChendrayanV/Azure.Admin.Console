function Write-AACMarkup {
    <#
    .SYNOPSIS
        Writes Spectre.Console markup text directly to the console.
    .DESCRIPTION
        A thin wrapper around [Spectre.Console.AnsiConsole]::MarkupLine()/Markup().
        This is a genuine side-effecting .NET call (both methods return void), so
        unlike a cmdlet that returns a renderable object on the pipeline, calling
        this always writes to the console immediately regardless of what any
        caller does with the enclosing function's own return value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Message,

        [switch] $NoNewline
    )

    process {
        if ($NoNewline) {
            [Spectre.Console.AnsiConsole]::Markup($Message)
        }
        else {
            [Spectre.Console.AnsiConsole]::MarkupLine($Message)
        }
    }
}
