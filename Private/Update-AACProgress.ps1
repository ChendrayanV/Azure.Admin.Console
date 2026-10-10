function Update-AACProgress {
    <#
    .SYNOPSIS
        Adds or moves on a task in the Invoke-AACProgress display that is
        running - and does nothing when none is.
    .DESCRIPTION
        Tasks are named by -Id; the first call with an Id adds the task (as a
        new line, under those already there), later calls update it:

          Update-AACProgress -Id 'read' -Description 'Reading the estate' -Total 3
          Update-AACProgress -Id 'read' -Increment 1 -Description 'Reading subscription names'
          Update-AACProgress -Id 'read' -Complete -Description 'Read 1,204 resources'

        -Indeterminate shows a sweeping bar for work whose size isn't known;
        giving -Total later turns it into a normal bar. -Complete fills the
        bar and stops the task's clock.

        Test files run outside this module, so they reach it through the
        module object, e.g.

          & (Get-Module Azure.Admin.Console) { param($p) Update-AACProgress @p } @{ Id = 'x'; Increment = 1 }

        When the tests run under plain Invoke-Pester (no display), every call
        is a no-op, so they need no checks of their own. Without an
        interactive terminal, -Complete with a -Description writes that
        description as a plain line instead.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Moves a line of the progress display; nothing outside the console changes.')]
    param(
        [Parameter(Mandatory)]
        [string] $Id,

        # Plain text; markup characters are escaped.
        [string] $Description,

        [double] $Total,

        [double] $Increment,

        [switch] $Indeterminate,

        [switch] $Complete
    )

    if ($script:AACProgressPlain) {
        if ($Complete -and $Description) {
            Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($Description))[/]"
        }
        return
    }

    $context = $script:AACProgressContext
    if (-not $context) {
        return
    }

    # Cut to the width the display has for it (Invoke-AACProgress), so the other columns keep theirs.
    $fit = {
        param([string] $Text)
        $width = $script:AACProgressDescriptionWidth
        if ($width -and $Text.Length -gt $width) {
            $more = if ([Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode) { [string][char]0x2026 } else { '...' }
            $Text = $Text.Substring(0, $width - $more.Length).TrimEnd() + $more
        }
        [Spectre.Console.Markup]::Escape($Text)
    }
    $task = $script:AACProgressTasks[$Id]
    if (-not $task) {
        $text = if ($Description) { $Description } else { $Id }
        $task = $context.AddTask((& $fit $text), $true, 1)
        $task.IsIndeterminate = $true
        $script:AACProgressTasks[$Id] = $task
    }
    elseif ($Description) {
        $task.Description = & $fit $Description
    }

    if ($PSBoundParameters.ContainsKey('Total')) {
        $task.MaxValue = [Math]::Max(1, $Total)
        $task.IsIndeterminate = $false
    }
    if ($Indeterminate) {
        $task.IsIndeterminate = $true
    }
    if ($Increment) {
        $task.Increment($Increment)
    }
    if ($Complete) {
        $task.IsIndeterminate = $false
        $task.Value = $task.MaxValue
        $task.StopTask()
    }
}
