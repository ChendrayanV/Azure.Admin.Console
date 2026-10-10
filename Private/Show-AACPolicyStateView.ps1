function Show-AACPolicyStateView {
    <#
    .SYNOPSIS
        Renders Get-AACPolicyState's result as a Spectre.Console view.
    .DESCRIPTION
        The scope, tiles (compliance, non-compliant and compliant resources,
        exempt, assignments, policies with non-compliant resources), then:
          Compliance by scope  each subscription, and each resource group,
                               least compliant first
          Assignments          least compliant first, with their scope and
                               enforcement
          Non-compliant        each policy with non-compliant resources and
                               every one of them (up to -MaxResource), most
                               first
        Compliance: 90% or more green, 70-89% amber, below red. Wrap the call
        in Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Compliance,

        [System.Collections.IDictionary] $Scope,

        [int] $MaxResource = 50
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Compliance.Stats
    $rateColor = { param($Rate) if ($null -eq $Rate) { 'grey50' } elseif ($Rate -ge 90) { 'green3' } elseif ($Rate -ge 70) { 'orange1' } else { 'red1' } }
    $rate = { param($Rate) if ($null -eq $Rate) { '[grey50]-[/]' } else { "[bold $(& $rateColor $Rate)]$Rate%[/]" } }
    $count = { param([int] $Value, [string] $Color) if ($Value -eq 0) { '[grey42]0[/]' } else { "[$Color]$('{0:N0}' -f $Value)[/]" } }
    $newTable = {
        param([string] $Title, [string] $Color, [object[]] $Columns)
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($Color)
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new($Title)
        foreach ($column in $Columns) {
            $spectre = [Spectre.Console.TableColumn]::new("[grey62]$($column[0])[/]")
            if ($column[1]) { $spectre.Alignment = [Spectre.Console.Justify]::Right; $spectre.NoWrap = $true }
            $table.AddColumn($spectre) | Out-Null
        }
        $table
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = $(if ($null -ne $stats.ComplianceRate) { "$($stats.ComplianceRate)%" } else { '-' }); Caption = ('resource compliance ({0:N0} of {1:N0})' -f $stats.CompliantCounted, $stats.Resources); Color = (& $rateColor $stats.ComplianceRate) }
        @{ Value = '{0:N0}' -f $stats.NonCompliant; Caption = 'non-compliant resources'; Color = $(if ($stats.NonCompliant) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Compliant; Caption = 'compliant resources'; Color = 'green3' }
        @{ Value = '{0:N0}' -f $stats.Exempt; Caption = 'exempt'; Color = 'grey70' }
        @{ Value = '{0:N0}' -f $stats.Assignments; Caption = 'assignments'; Color = 'mediumpurple2' }
        @{ Value = '{0:N0} / {1:N0}' -f $stats.NonCompliantInitiatives, $stats.Initiatives; Caption = 'non-compliant initiatives'; Color = $(if ($stats.NonCompliantInitiatives) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0} / {1:N0}' -f $stats.NonCompliantPolicies, $stats.Policies; Caption = 'non-compliant policies'; Color = $(if ($stats.NonCompliantPolicies) { 'orange1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()
    foreach ($notice in @($Compliance.Notice | Where-Object { $_ })) { Write-AACMarkup "[deepskyblue1]i[/] [grey70]$(& $escape $notice)[/]" }
    if (@($Compliance.Notice).Count) { [Spectre.Console.AnsiConsole]::WriteLine() }
    if (-not $stats.States) { return }

    # --- By scope: subscriptions, then resource groups ----------------------------------------------------
    foreach ($level in 'Subscription', 'ResourceGroup') {
        $rows = @($Compliance.Scopes | Where-Object Level -EQ $level)
        if (-not $rows.Count) { continue }
        $title = if ($level -eq 'Subscription') { 'Compliance by subscription' } else { 'Compliance by resource group' }
        $columns = [System.Collections.Generic.List[object]]::new()
        $columns.Add(@($(if ($level -eq 'Subscription') { 'Subscription' } else { 'Resource group' }), $false))
        if ($level -eq 'ResourceGroup') { $columns.Add(@('Subscription', $false)) }
        foreach ($name in 'Compliance', 'Non-compliant', 'Compliant', 'Exempt', 'Resources') { $columns.Add(@($name, $true)) }
        $table = & $newTable "[bold]$($glyph.Bullet) $title[/] [grey58]$($glyph.Dot) least compliant first[/]" 'grey42' $columns.ToArray()
        foreach ($item in $rows) {
            & $addRow $table @(
                "[bold]$(& $escape $item.Name)[/]"
                if ($level -eq 'ResourceGroup') { "[grey70]$(& $escape $item.SubscriptionName)[/]" }
                (& $rate $item.ComplianceRate)
                (& $count $item.NonCompliant 'red1'); (& $count $item.Compliant 'green3'); (& $count $item.Exempt 'grey70'); (& $count $item.Resources 'grey85')
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Assignments -----------------------------------------------------------------------------------------
    if ($Compliance.Assignments.Count) {
        $table = & $newTable "[bold mediumpurple2]$($glyph.Bullet) Assignments[/] [grey58]$($glyph.Dot) least compliant first[/]" 'mediumpurple2' @(@('Assignment', $false), @('Scope', $false), @('Compliance', $true), @('Non-compliant', $true), @('Compliant', $true), @('Policies failing', $true))
        foreach ($item in $Compliance.Assignments) {
            & $addRow $table @(
                "[bold]$(& $escape $item.Assignment)[/]$(if ($item.Enforcement -eq 'DoNotEnforce') { "`n[grey50](not enforced)[/]" })"
                "[grey70]$(& $escape $item.Scope)[/]"
                (& $rate $item.ComplianceRate)
                (& $count $item.NonCompliant 'red1'); (& $count $item.Compliant 'green3'); (& $count $item.NonCompliantPolicies 'orange1')
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Non-compliant resources, by policy ----------------------------------------------------------------------
    $bad = @($Compliance.States | Where-Object ComplianceState -EQ 'NonCompliant' | Group-Object -Property Policy | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
    if ($bad.Count) {
        $table = & $newTable "[bold red1]$($glyph.Bullet) Non-compliant resources by policy[/] [grey58]$($glyph.Dot) $($stats.NonCompliant) resource(s)[/]" 'red3' @(@('Policy', $false), @('Resources', $true), @('Where', $false))
        foreach ($policy in $bad) {
            $first = $policy.Group[0]
            $what = "[bold]$(& $escape $policy.Name)[/]"
            $context = @($(if ($first.PolicySet) { "in $($first.PolicySet)" }), $first.Assignment, $(if ($first.Effect) { "effect: $($first.Effect)" })) | Where-Object { $_ }
            if ($context) { $what += "`n[grey58]$(& $escape ($context -join " $($glyph.Dot) "))[/]" }
            $shown = @($policy.Group | Select-Object -First $MaxResource)
            $where = @($shown | ForEach-Object { "[white]$(& $escape $_.Resource)[/] [grey50]$(& $escape (@($_.ResourceGroup, $_.SubscriptionName) | Where-Object { $_ }) -join ' / ')[/]" })
            if ($policy.Count -gt $shown.Count) { $where += "[grey50]... and $($policy.Count - $shown.Count) more: -PassThru, -CsvPath or -HtmlPath lists them all[/]" }
            & $addRow $table @($what, "[bold]$($policy.Count)[/]", ($where -join "`n"))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    else {
        Show-AACCallout Success -Message '[bold green3]Every evaluated resource complies[/] [grey58]with every policy in this scope.[/]'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    Write-AACMarkup '[grey42]Compliance: (compliant + exempt + unknown + protected resources) / every resource evaluated, as the Azure portal counts it. Add -PassThru (or pipe the command) for every state; -CsvPath, -PdfPath or -HtmlPath for a report.[/]'
}
