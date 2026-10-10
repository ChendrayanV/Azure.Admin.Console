function Read-AACSelection {
    <#
    .SYNOPSIS
        Asks the operator to pick one or more items from a list - a
        Spectre.Console selection prompt, moved with the arrow keys - and
        returns the chosen ones.
    .DESCRIPTION
        -Multiple: a check list (space to toggle, Enter to accept), at least
        one item required. Otherwise a single choice. Items are shown with
        -Label (a script block on each item; the item as text by default).

        Only at an interactive console: in a script, a CI job or with
        redirected output there is no one to ask, so it stops with -Hint
        (what to pass instead) rather than waiting forever.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter(Mandatory)]
        [object[]] $Item,

        [scriptblock] $Label = { param($It) [string]$It },

        [switch] $Multiple,

        [string] $Hint = 'Pass the values as parameters instead.'
    )

    if (-not [Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive -or [Console]::IsInputRedirected) {
        throw "There's no interactive console to ask in. $Hint"
    }
    # Labels must be unique for the prompt to map back to the items.
    $byLabel = [ordered]@{}
    foreach ($it in $Item) {
        $text = [string](& $Label $it)
        $n = 2
        $unique = $text
        while ($byLabel.Contains($unique)) { $unique = "$text ($n)"; $n++ }
        $byLabel[$unique] = $it
    }
    $console = [Spectre.Console.AnsiConsole]::Console
    if ($Multiple) {
        $prompt = [Spectre.Console.MultiSelectionPrompt[string]]::new()
        $prompt.Title = $Title
        $prompt.PageSize = 15
        $prompt.Required = $true
        $prompt.InstructionsText = '[grey58](space to choose, enter to accept)[/]'
        foreach ($text in $byLabel.Keys) { $null = $prompt.AddChoice([Spectre.Console.Markup]::Escape($text)) }
        $chosen = @($prompt.Show($console))
    }
    else {
        $prompt = [Spectre.Console.SelectionPrompt[string]]::new()
        $prompt.Title = $Title
        $prompt.PageSize = 15
        foreach ($text in $byLabel.Keys) { $null = $prompt.AddChoice([Spectre.Console.Markup]::Escape($text)) }
        $chosen = @($prompt.Show($console))
    }
    # Back from the escaped text to the items.
    foreach ($text in $byLabel.Keys) { if ($chosen -contains [Spectre.Console.Markup]::Escape($text)) { $byLabel[$text] } }
}
