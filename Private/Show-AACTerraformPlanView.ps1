function Show-AACTerraformPlanView {
    <#
    .SYNOPSIS
        Renders Get-AACTerraformPlan's result as a Spectre.Console view.
    .DESCRIPTION
        The plan file and Terraform version, Terraform's summary line
        (Plan: 3 to add, 1 to change, 2 to destroy), tiles per action, then
        a table per action - deletes, replacements, updates, creates,
        imports, moves, reads - with each resource's Azure name, resource
        group and location, why, and its attribute changes as Terraform
        writes them:

          + attribute = value                 added
          - attribute = value                 removed
          ~ attribute: before -> after        changed
          # forces replacement                after an attribute that does

        up to -MaxAttribute per resource; then the outputs, and what changed
        outside Terraform. Wrap the call in Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Plan,

        [int] $MaxAttribute = 25,

        [int] $MaxValueLength = 120
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Plan.Stats
    $info = $Plan.Info
    $colors = @{ Create = 'green3'; Update = 'orange1'; Replace = 'orchid'; Delete = 'red1'; Read = 'deepskyblue1'; Import = 'steelblue1'; Move = 'steelblue1'; Forget = 'grey70'; NoOp = 'grey50' }
    $symbols = @{ Create = '+'; Update = '~'; Replace = '-/+'; Delete = '-'; Read = '<='; Import = '<-'; Move = '->'; Forget = '.'; NoOp = ' ' }
    $order = @{ Delete = 0; Replace = 1; Update = 2; Create = 3; Import = 4; Move = 5; Read = 6; Forget = 7; NoOp = 8 }
    $titles = @{ Delete = 'Delete'; Replace = 'Replace'; Update = 'Update in place'; Create = 'Create'; Import = 'Import'; Move = 'Move'; Read = 'Read (data sources)'; Forget = 'Forget (removed from state, not destroyed)'; NoOp = 'No change' }
    $short = {
        param([string] $Text)
        if ($null -eq $Text) { return '' }
        $flat = $Text -replace '\s*\r?\n\s*', ' '
        if ($flat.Length -gt $MaxValueLength) { $flat.Substring(0, $MaxValueLength) + '...' } else { $flat }
    }
    $value = {
        param([string] $Text)
        if ($Text -in '(sensitive)', '(known after apply)') { "[grey58 italic]$Text[/]" } else { "[white]$(& $escape (& $short $Text))[/]" }
    }
    $line = {
        param($Attribute)
        $name = & $escape $Attribute.Attribute
        $text = switch ($Attribute.Change) {
            'Added' { "[green3]+[/] $name = $(& $value $Attribute.After)" }
            'Removed' { "[red1]-[/] $name = $(& $value $Attribute.Before)" }
            'Reordered' { "[orange1]~[/] $name [grey58](the same elements, in another order)[/]" }
            'Reformatted' { "[orange1]~[/] $name [grey58](the same JSON, formatted differently)[/]" }
            default {
                if ($null -eq $Attribute.Before) { "[green3]+[/] $name = $(& $value $Attribute.After)" }
                else { "[orange1]~[/] $name`: $(& $value $Attribute.Before) [grey58]$($glyph.Arrow)[/] $(& $value $Attribute.After)" }
            }
        }
        if ($Attribute.ForcesReplacement) { $text += ' [red1 bold]# forces replacement[/]' }
        $text
    }
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
    $describe = {
        param($Change)
        $text = "[bold]$(& $escape $Change.Address)[/]"
        $facts = @($(if ($Change.Mode -eq 'data') { "data $($Change.Type)" } else { $Change.Type }), $Change.ResourceName, $Change.ResourceGroup, $Change.Location) | Where-Object { $_ }
        if ($facts) { $text += "`n[grey58]$(& $escape ($facts -join " $($glyph.Dot) "))[/]" }
        if ($Change.Deposed) { $text += "`n[orchid]deposed object $(& $escape $Change.Deposed)[/]" }
        if ($Change.PreviousAddress) { $text += "`n[steelblue1]moved from $(& $escape $Change.PreviousAddress)[/]" }
        if ($Change.Importing) { $text += "`n[steelblue1]imported$(if ($Change.ResourceId) { ": $(& $escape $Change.ResourceId)" })[/]" }
        if ($Change.Reason) { $text += "`n[grey70 italic]$(& $escape $Change.Reason)[/]" }
        if ($Change.ReplaceOrder) { $text += "`n[grey50]$(& $escape $Change.ReplaceOrder)[/]" }
        $text
    }
    $changeLines = {
        param($Change, [int] $Max)
        $attributes = @($Change.Attributes)
        if (-not $attributes.Count) { return '[grey50]no attribute changes[/]' }
        $lines = @($attributes | Select-AACFirst $Max | ForEach-Object { & $line $_ })
        if ($attributes.Count -gt $Max) { $lines += "[grey50]... and $($attributes.Count - $Max) more: -ExpandAttribute, -CsvPath or -HtmlPath lists them all[/]" }
        $lines -join "`n"
    }

    # --- The plan, and Terraform's summary ---------------------------------------------------------------
    $facts = [System.Collections.Generic.List[string]]::new()
    $facts.Add("[white]$(& $escape (Split-Path -Path $info.Path -Leaf))[/]")
    if ($info.TerraformVersion) { $facts.Add("Terraform v$(& $escape $info.TerraformVersion)") }
    if ($info.Timestamp) { $facts.Add("planned $(& $escape $info.Timestamp)") }
    foreach ($key in @($Plan.Detail.Keys | Where-Object { $_ -in 'Actions', 'Addresses', 'Resource types' })) { $facts.Add("$(& $escape $key): $(& $escape $Plan.Detail[$key])") }
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    $summary = "[bold]Plan:[/] [green3]$($stats.ToAdd) to add[/], [orange1]$($stats.ToChange) to change[/], [red1]$($stats.ToDestroy) to destroy[/]"
    if ($stats.Import) { $summary += ", [steelblue1]$($stats.Import) to import[/]" }
    if ($stats.Forget) { $summary += ", [grey70]$($stats.Forget) to forget[/]" }
    Write-AACMarkup "$summary."
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Create; Caption = 'create'; Color = $colors.Create }
        @{ Value = '{0:N0}' -f $stats.Update; Caption = 'update in place'; Color = $colors.Update }
        @{ Value = '{0:N0}' -f $stats.Replace; Caption = 'replace'; Color = $colors.Replace }
        @{ Value = '{0:N0}' -f $stats.Delete; Caption = 'delete'; Color = $colors.Delete }
        @{ Value = '{0:N0}' -f ($stats.Import + $stats.Move); Caption = 'import / move'; Color = $colors.Import }
        @{ Value = '{0:N0}' -f $stats.Read; Caption = 'data sources read'; Color = $colors.Read }
        @{ Value = '{0:N0}' -f $stats.Outputs; Caption = 'outputs changing'; Color = 'grey85' }
        @{ Value = '{0:N0}' -f $stats.Drift; Caption = 'changed outside Terraform'; Color = 'yellow' }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()
    foreach ($notice in @($Plan.Notice | Where-Object { $_ })) { Write-AACMarkup "[deepskyblue1]i[/] [grey70]$(& $escape $notice)[/]" }
    if (@($Plan.Notice).Count) { [Spectre.Console.AnsiConsole]::WriteLine() }

    # --- A table per action ------------------------------------------------------------------------------------
    $resources = @($Plan.Selected | Where-Object { $_.Source -eq 'Plan' -and $_.Mode -ne 'output' })
    foreach ($group in @($resources | Group-Object -Property Action | Sort-Object -Property @{ Expression = { $order[$_.Name] ?? 9 } })) {
        $action = $group.Name
        $color = $colors[$action] ?? 'grey70'
        $table = & $newTable "[bold $color]$(& $escape $symbols[$action]) $(& $escape ($titles[$action] ?? $action))[/] [grey58]$($glyph.Dot) $($group.Count) resource(s)[/]" $color @('Resource', 'Changes')
        foreach ($change in $group.Group) {
            & $addRow $table @((& $describe $change), (& $changeLines $change $MaxAttribute))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Outputs ---------------------------------------------------------------------------------------------
    $outputs = @($Plan.Selected | Where-Object { $_.Mode -eq 'output' })
    if ($outputs.Count) {
        $table = & $newTable "[bold grey85]$($glyph.Bullet) Outputs[/] [grey58]$($glyph.Dot) $($outputs.Count) changing[/]" 'grey50' @('Output', 'Change')
        foreach ($change in $outputs) {
            $text = if (@($change.Attributes).Count) { @($change.Attributes | ForEach-Object { & $line $_ }) -join "`n" } else { "[grey50]$($change.Action)[/]" }
            & $addRow $table @("[bold]$(& $escape $change.Name)[/]", $text)
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Drift --------------------------------------------------------------------------------------------------
    $drift = @($Plan.Selected | Where-Object { $_.Source -eq 'Drift' })
    if ($drift.Count) {
        $table = & $newTable "[bold yellow]$($glyph.Bullet) Changed outside Terraform[/] [grey58]$($glyph.Dot) since the last apply, $($drift.Count) resource(s)[/]" 'yellow' @('Resource', 'What changed')
        foreach ($change in $drift) {
            & $addRow $table @((& $describe $change), (& $changeLines $change 10))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    if (-not $resources.Count -and -not $outputs.Count -and -not $drift.Count -and -not $Plan.Filtered) {
        Show-AACCallout Success -Message '[bold green3]No changes.[/] [grey58]The infrastructure matches the configuration.[/]'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for one row per resource, -ExpandAttribute for one per attribute; -CsvPath or -HtmlPath for a report. Sensitive values are never shown.[/]'
}
