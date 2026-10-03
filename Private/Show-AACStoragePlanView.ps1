function Show-AACStoragePlanView {
    <#
    .SYNOPSIS
        Renders Deploy-AACStorageAccount's plan and gates as a
        Spectre.Console view.
    .DESCRIPTION
        The account and scope; Terraform's kind of summary line; every change
        with its properties (+ create, ~ update, - delete, ! can't change in
        place, ? couldn't be read), and drift; the policy assignments that
        apply to storage; the gates by outcome (Blocks, Breaks, Changes,
        Audit, Warn, Pass), each block with its fix; how to fix the failing
        PSRule rules - a configuration snippet with every setting that fixes
        one, and what to do for the others - or the fixes -UseSuggestedFix
        applied; and the decision: blocked, nothing to do, or ready.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Deployment,

        [int] $MaxProperty = 30
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $changes = @($Deployment.Changes)
    $short = { param([string] $Text) $flat = $Text -replace '\s*\r?\n\s*', ' '; if ($flat.Length -gt 110) { $flat.Substring(0, 110) + '...' } else { $flat } }
    $newTable = {
        param([string] $Title, [string] $Color, [string[]] $Columns)
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($Color)
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new($Title)
        foreach ($column in $Columns) { $table.AddColumn([Spectre.Console.TableColumn]::new("[grey62]$column[/]")) | Out-Null }
        $table
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }
    $write = { param($Table) [Spectre.Console.AnsiConsole]::Write($Table); [Spectre.Console.AnsiConsole]::WriteLine() }
    $count = { param([string] $Action) @($changes | Where-Object Action -EQ $Action).Count }
    $style = @{ Create = @('+', 'green3'); Update = @('~', 'orange1'); Delete = @('-', 'red1'); Replace = @('!', 'red1'); Unknown = @('?', 'grey58'); Drift = @('*', 'yellow') }

    Write-AACMarkup "[grey58][white]$(& $escape $Deployment.Name)[/] $($glyph.Dot) $(& $escape $Deployment.ResourceGroupName) $($glyph.Dot) subscription $(& $escape $Deployment.SubscriptionId) $($glyph.Dot) $(& $escape $Deployment.Location)[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()
    $line = "[bold]Plan:[/] [green3]$(& $count 'Create') to create[/], [orange1]$(& $count 'Update') to update[/], [red1]$(& $count 'Delete') to delete[/], [grey58]$(& $count 'NoChange') unchanged[/]"
    if (& $count 'Replace') { $line += ", [red1 bold]$(& $count 'Replace') can't change in place[/]" }
    if (& $count 'Drift') { $line += ", [yellow]$(& $count 'Drift') not in the configuration[/]" }
    Write-AACMarkup "$line."
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- Changes ------------------------------------------------------------------------------------------------------
    $shown = @($changes | Where-Object Action -NE 'NoChange')
    if ($shown.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Changes[/] [grey58]$($glyph.Dot) in apply order[/]" 'grey42' @('', 'Resource', 'What changes')
        foreach ($item in $shown) {
            $symbol = $style[$item.Action]
            $lines = @(foreach ($difference in @($item.Differences) | Select-AACFirst $MaxProperty) {
                    $name = & $escape $difference.Property
                    if ($item.Action -eq 'Create') { "[green3]+[/] $name = [white]$(& $escape (& $short $difference.Desired))[/]" }
                    elseif ($item.Action -eq 'Delete') { "[red1]-[/] $name" }
                    else { "$(if ($difference.Immutable) { '[red1]![/]' } else { '[orange1]~[/]' }) $name`: [white]$(& $escape (& $short $difference.Current))[/] [grey58]$($glyph.Arrow)[/] [white]$(& $escape (& $short $difference.Desired))[/]$(if ($difference.Immutable) { ' [red1 bold]can''t change in place[/]' })" }
                })
            if (@($item.Differences).Count -gt $MaxProperty) { $lines += "[grey50]... and $(@($item.Differences).Count - $MaxProperty) more[/]" }
            if ($item.Reason) { $lines += "[grey58]$(& $escape $item.Reason)[/]" }
            & $addRow $table @("[bold $($symbol[1])]$(& $escape $symbol[0])[/]", "[bold]$(& $escape $item.Resource)[/]`n[grey50]$(& $escape $item.Action)[/]", ($lines -join "`n"))
        }
        & $write $table
    }

    # --- Policy assignments ------------------------------------------------------------------------------------------
    $policies = @($Deployment.Policies)
    if ($policies.Count) {
        $table = & $newTable "[bold mediumpurple2]$($glyph.Bullet) Azure Policy assigned here for storage[/] [grey58]$($glyph.Dot) $($policies.Count)[/]" 'mediumpurple2' @('Assignment', 'Effect', 'Assigned at', 'Applies to')
        foreach ($policy in $policies) {
            $effect = [string]$policy.Effect
            $color = if ($effect -match 'Deny') { 'red1' } elseif ($effect -match 'Modify|Append|DeployIfNotExists') { 'deepskyblue1' } elseif ($effect -match 'Audit') { 'orange1' } else { 'grey70' }
            & $addRow $table @("[bold]$(& $escape $policy.Assignment)[/]$(if ($policy.Enforcement -eq 'DoNotEnforce') { "`n[grey50](not enforced)[/]" })", "[$color]$(& $escape $effect)[/]", "[grey70]$(& $escape $policy.Scope)[/]", "[grey70]$(& $escape (& $short $policy.ResourceType))[/]")
        }
        & $write $table
    }

    # --- Gates ----------------------------------------------------------------------------------------------------------
    $outcomes = [ordered]@{ Blocks = 'red1'; Breaks = 'orange1'; Changes = 'deepskyblue1'; Audit = 'yellow'; Warn = 'orange1'; Info = 'grey70'; Pass = 'green3' }
    $gates = @($Deployment.Gates | Sort-Object { @($outcomes.Keys).IndexOf($_.Outcome) }, Gate, Resource)
    if ($gates.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Gates[/] [grey58]$($glyph.Dot) name, immutable properties, Azure Policy, PSRule[/]" 'grey42' @('Outcome', 'Gate', 'Resource', 'Detail')
        foreach ($item in $gates) {
            $what = "$(if ($item.Item) { "[bold]$(& $escape $item.Item)[/]`n" })[grey70]$(& $escape $item.Detail)[/]"
            if ($item.PSObject.Properties['Fix'] -and $item.Fix) { $what += "`n[springgreen3]Fix:[/] [white]$(& $escape $item.Fix)[/]" }
            & $addRow $table @("[bold $($outcomes[$item.Outcome])]$(& $escape $item.Outcome)[/]$(if ($item.Severity) { "`n[grey50]$(& $escape $item.Severity)[/]" })", (& $escape $item.Gate), (& $escape $item.Resource), $what)
        }
        & $write $table
    }

    # --- How to fix the failing PSRule rules ------------------------------------------------------------------------------
    # The settings as a .psd1 snippet, in the configuration's own names.
    $psd1 = {
        param($Value, [int] $Depth = 0)
        $pad = '    ' * ($Depth + 1)
        if ($Value -is [System.Collections.IDictionary]) { return "@{`n$(@(foreach ($key in $Value.Keys) { "$pad$key = $(& $psd1 $Value[$key] ($Depth + 1))" }) -join "`n")`n$('    ' * $Depth)}" }
        if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) { return "@($(@(foreach ($item in $Value) { & $psd1 $item ($Depth + 1) }) -join ', '))" }
        if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
        if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return [string]$Value }
        "'$(([string]$Value) -replace "'", "''")'"
    }
    $applied = @($Deployment.FixesApplied)
    $automatic = @($Deployment.Fixes | Where-Object Kind -EQ 'Auto')
    $manual = @($Deployment.Fixes | Where-Object Kind -EQ 'Manual')
    if ($applied.Count) {
        $snippet = & $psd1 (Set-AACStorageConfigurationFix -Configuration ([ordered]@{}) -Fix $applied)
        Show-AACPanel -Header 'Suggested fixes applied to this run' -Content "[grey70]The plan above uses these settings (-UseSuggestedFix) and was checked again. Put them in your configuration so the next run has them:[/]`n[white]$(& $escape $snippet)[/]" -BorderColor 'springgreen3' -AllowMarkup
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    elseif ($automatic.Count -or $manual.Count) {
        $lines = [System.Collections.Generic.List[string]]::new()
        if ($automatic.Count) {
            $lines.Add("[bold]Add to the configuration[/] [grey58](or run again with -UseSuggestedFix):[/]")
            $lines.Add("[white]$(& $escape (& $psd1 (Set-AACStorageConfigurationFix -Configuration ([ordered]@{}) -Fix $automatic)))[/]")
        }
        foreach ($fix in $manual) { $lines.Add("[orange1]$($glyph.Bullet)[/] [bold]$(& $escape $fix.Rule)[/]: [grey70]$(& $escape $fix.Advice)[/]") }
        $lines.Add('[grey50]A rule that does not apply to this account can be excluded on purpose: -ExcludeRule <rule>.[/]')
        Show-AACPanel -Header 'How to fix the failing PSRule rules' -Content ($lines -join "`n") -BorderColor 'orange1' -AllowMarkup
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- The decision ---------------------------------------------------------------------------------------------------
    $blocks = @($gates | Where-Object Outcome -In 'Blocks', 'Breaks').Count
    $breaks = @($gates | Where-Object Outcome -EQ 'Breaks').Count
    $byPolicy = @($gates | Where-Object Outcome -EQ 'Changes').Count
    $summary = "Blocks $(@($gates | Where-Object Outcome -EQ 'Blocks').Count) $($glyph.Dot) breaks standards $breaks $($glyph.Dot) changed by policy $byPolicy $($glyph.Dot) $($Deployment.Writes) change(s) to apply"
    if ($blocks) { Show-AACPanel -Content "[bold red1]Blocked[/] [grey70]- nothing will be written$(if ($breaks) { ': fix the failing PSRule rules (above), or exclude one that does not apply' }).[/]`n[grey58]$(& $escape $summary)[/]" -BorderColor 'red1' -AllowMarkup }
    elseif (-not $Deployment.Writes) { Show-AACPanel -Content "[bold green3]No changes.[/] [grey70]The account matches the configuration.[/]`n[grey58]$(& $escape $summary)[/]" -BorderColor 'green3' -AllowMarkup }
    else { Show-AACPanel -Content "[bold]Ready to apply.[/]`n[grey58]$(& $escape $summary)[/]" -BorderColor 'springgreen3' -AllowMarkup }
    [Spectre.Console.AnsiConsole]::WriteLine()
}
