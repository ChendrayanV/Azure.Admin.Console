function Show-AACAdvisorTable {
    <#
    .SYNOPSIS
        Renders AAC.AdvisorRecommendation objects as colour-coded
        Spectre.Console tables, one per Advisor category.
    .DESCRIPTION
        Each category gets its own rounded table, bordered in the category's
        colour, titled with its counts and estimated savings:

          ╭──────── ● Cost · 12 recommendations · 12 resources · USD 6,738 / month ────────╮
          │ Impact │ Recommendation            │ Resource        │ Subscription · RG │ Savings / retirement │
          │  HIGH  │ Right-size underused VMs  │ vm-app-15       │ sub-dev · rg-app  │ USD 262.50 / mo      │
          │        │                           │ virtualMachines │                   │                      │
          │        │                           │ vm-app-30       │ sub-prod · rg-app │ USD 525.00 / mo      │
          ...

        Rows are grouped by recommendation: the impact badge (HIGH on red,
        MEDIUM on orange, LOW on grey) and the recommendation text appear on
        a group's first row only, with an empty row between groups. Savings
        are green; a retirement date is red within 90 days (or past), orange
        within 180 days and gold after that. Postponed and dismissed
        recommendations are marked in orange under the resource.

        The objects must arrive sorted by category, impact and problem, as
        Get-AACAdvisorRecommendation returns them. Output goes straight to
        the Spectre console, so wrap the call in Invoke-AACPagedOutput to
        page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Recommendation
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    # Unicode symbols, or ASCII in a console that isn't UTF-8.
    $glyph = Get-AACGlyph
    $categories = [ordered]@{
        Cost                  = @{ Label = 'Cost'; Color = 'green3' }
        Security              = @{ Label = 'Security'; Color = 'indianred1' }
        Reliability           = @{ Label = 'Reliability'; Color = 'deepskyblue1' }
        OperationalExcellence = @{ Label = 'Operational excellence'; Color = 'mediumpurple2' }
        Performance           = @{ Label = 'Performance'; Color = 'gold1' }
    }
    $badge = @{
        High   = '[bold white on red3] HIGH [/]'
        Medium = '[bold black on orange1] MEDIUM [/]'
        Low    = '[black on grey70] LOW [/]'
    }
    $today = (Get-Date).Date

    $savingsText = {
        param($Items)
        (@($Items | Where-Object { $null -ne $_.MonthlySavings }) |
            Group-Object -Property SavingsCurrency |
            Sort-Object -Property Name |
            ForEach-Object { ('{0} {1:N0}' -f $_.Name, ($_.Group | Measure-Object -Property MonthlySavings -Sum).Sum).Trim() }) -join ' + '
    }
    $resourceKey = { if ($_.ResourceId) { $_.ResourceId.ToLowerInvariant() } else { $_.ResourceName } }

    # Categories in the portal's order, then anything unexpected.
    $groups = @($Recommendation | Group-Object -Property Category | Sort-Object {
            $index = @($categories.Keys).IndexOf($_.Name)
            if ($index -lt 0) { 99 } else { $index }
        })

    foreach ($group in $groups) {
        $style = $categories[$group.Name]
        if (-not $style) { $style = @{ Label = $group.Name; Color = 'grey70' } }
        $color = $style.Color
        $items = @($group.Group)

        $title = [System.Collections.Generic.List[string]]::new()
        $title.Add("[bold $color]$($glyph.Bullet) $(& $escape $style.Label)[/]")
        $title.Add("$($items.Count) recommendation$(if ($items.Count -ne 1) { 's' })")
        $resourceCount = @($items | ForEach-Object $resourceKey | Select-Object -Unique).Count
        $title.Add("$resourceCount resource$(if ($resourceCount -ne 1) { 's' })")
        $saving = & $savingsText $items
        if ($saving) { $title.Add("[green3]$(& $escape $saving) / month[/]") }

        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($color)
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new(($title -join " [grey58]$($glyph.Dot)[/] "))

        $addColumn = {
            param([string] $Header, [switch] $NoWrap, [int] $Width = 0)
            $column = [Spectre.Console.TableColumn]::new("[grey62]$Header[/]")
            $column.NoWrap = [bool]$NoWrap
            if ($Width -gt 0) { $column.Width = $Width }
            $table.AddColumn($column) | Out-Null
        }
        & $addColumn 'Impact' -NoWrap -Width 8
        & $addColumn 'Recommendation'
        & $addColumn 'Resource'
        & $addColumn 'Subscription / resource group'
        & $addColumn 'Savings / retirement' -Width 24

        $previousKey = $null
        foreach ($item in $items) {
            $key = "$($item.Impact)|$($item.Problem)"
            $firstInGroup = $key -ne $previousKey
            if ($firstInGroup -and $null -ne $previousKey) {
                [Spectre.Console.TableExtensions]::AddEmptyRow($table) | Out-Null
            }
            $previousKey = $key

            $impactCell = if ($firstInGroup) { $(if ($badge.ContainsKey([string]$item.Impact)) { $badge[[string]$item.Impact] } else { "[grey70]$(& $escape $item.Impact)[/]" }) } else { '' }
            $problemCell = if ($firstInGroup) { "[white]$(& $escape $item.Problem)[/]" } else { '' }

            $resourceLines = [System.Collections.Generic.List[string]]::new()
            $resourceLines.Add("[bold]$(& $escape $(if ($item.ResourceName) { $item.ResourceName } else { '-' }))[/]")
            if ($item.ResourceType) { $resourceLines.Add("[grey50]$(& $escape ($item.ResourceType -split '/')[-1])[/]") }
            if ($item.Status -and $item.Status -ne 'Active') {
                $until = if ($item.SuppressionExpires) { " until $($item.SuppressionExpires.ToString('d MMM yyyy'))" } else { '' }
                $resourceLines.Add("[italic orange1]$(& $escape ([string]$item.Status).ToLowerInvariant())$until[/]")
            }

            $where = if ($item.SubscriptionName) { $item.SubscriptionName } else { $item.SubscriptionId }
            if ($item.ResourceGroup) { $where = "$where $($glyph.Dot) $($item.ResourceGroup)" }

            $notes = [System.Collections.Generic.List[string]]::new()
            if ($null -ne $item.MonthlySavings) {
                $notes.Add("[green3]$(& $escape (('{0} {1:N2}' -f $item.SavingsCurrency, $item.MonthlySavings).Trim()))[/][grey58] / mo[/]")
            }
            elseif ($null -ne $item.AnnualSavings) {
                $notes.Add("[green3]$(& $escape (('{0} {1:N2}' -f $item.SavingsCurrency, $item.AnnualSavings).Trim()))[/][grey58] / yr[/]")
            }
            if ($item.RetirementDate) {
                $days = [int][Math]::Floor(($item.RetirementDate.Date - $today).TotalDays)
                $dateColor = if ($days -lt 90) { 'bold red1' } elseif ($days -lt 180) { 'orange1' } else { 'gold1' }
                $when = if ($days -lt 0) { 'retired' } else { "$days days" }
                $notes.Add("[$dateColor]$($item.RetirementDate.ToString('d MMM yyyy'))[/] [grey58]($when)[/]")
                if ($item.RetiringFeature) { $notes.Add("[grey58]$(& $escape $item.RetiringFeature)[/]") }
            }

            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@(
                    [Spectre.Console.Markup]::new($impactCell)
                    [Spectre.Console.Markup]::new($problemCell)
                    [Spectre.Console.Markup]::new(($resourceLines -join "`n"))
                    [Spectre.Console.Markup]::new("[grey70]$(& $escape $where)[/]")
                    [Spectre.Console.Markup]::new($(if ($notes.Count) { $notes -join "`n" } else { '[grey42]-[/]' }))
                )) | Out-Null
        }

        [Spectre.Console.AnsiConsole]::WriteLine()
        [Spectre.Console.AnsiConsole]::Write($table)
    }
}
