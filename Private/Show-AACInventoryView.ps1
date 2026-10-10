function Show-AACInventoryView {
    <#
    .SYNOPSIS
        Renders the tenant inventory (ConvertTo-AACInventory) as a
        Spectre.Console view: the scope, tiles, the hierarchy as a tree and
        the most common resource types.
    .DESCRIPTION
          Tenant  Contoso  · 3 subscriptions · 5 resource groups · 17 resources
          ├── MG  Platform  · 1 subscription · 6 resources
          │   └── MG  Connectivity
          │       └── SUB  sub-connectivity  11111111-... · Enabled · 1 RG · 6 resources
          │           └── RG  rg-hub  uksouth · 6 resources · publicipaddresses 2, ...
          └── SUB  sub-legacy ...

        -Depth stops the tree at management groups, subscriptions, resource
        groups (the default) or resources. Empty resource groups are amber.
        With Defender for Cloud data, each node shows its secure score in
        colour (Good green, Fair amber, Poor red) and its unhealthy findings
        by severity (H red, M amber, L blue); after the tree come the security
        controls with the most to gain and the High-severity recommendations.
        With cost (Get-AACInventory -Cost), a row of cost tiles - month to
        date and last month per currency - each node's cost month to date in
        green (or why it couldn't be read), a 'Deleted resources' line under
        a subscription with such costs, and the resources that cost the most
        this month.
        With insights (Get-AACInventory -Insight): tiles, the estate's mix as
        proportion charts (VM sizes, operating systems, power states, Azure
        and Arc, storage replication, database tiers), tag coverage, and
        what needs attention - unattached disks, unused public IPs and NICs,
        VMs stopped but billed, classic resources, nearly full subnets,
        connections down - with each one's cost this month when cost was
        read.
        In a console that isn't UTF-8 the tree is drawn in ASCII. Output goes
        straight to the Spectre console; wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Inventory,

        [ValidateSet('ManagementGroup', 'Subscription', 'ResourceGroup', 'Resource')]
        [string] $Depth = 'ResourceGroup',

        [System.Collections.IDictionary] $Scope
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Inventory.Stats
    $unicode = [Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    $ratingColor = @{ Good = 'green3'; Fair = 'orange1'; Poor = 'red1' }
    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.ManagementGroups; Caption = 'management groups'; Color = 'mediumpurple2' }
        @{ Value = '{0:N0}' -f $stats.Subscriptions; Caption = 'subscriptions'; Color = 'gold1' }
        @{ Value = '{0:N0}' -f $stats.ResourceGroups; Caption = 'resource groups'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.Resources; Caption = 'resources'; Color = 'green3' }
    )
    if ($stats.HasSecurity -and $null -ne $stats.SecureScore) {
        $tiles += @{ Value = "$($stats.SecureScore)%"; Caption = "secure score ($($stats.Rating.ToLowerInvariant()))"; Color = $ratingColor[$stats.Rating] }
        $tiles += @{ Value = '{0:N0}' -f $stats.High; Caption = 'high-severity findings'; Color = $(if ($stats.High) { 'red1' } else { 'green3' }) }
    }
    else {
        $tiles += @{ Value = '{0:N0}' -f $stats.Types; Caption = 'types'; Color = 'grey70' }
        $tiles += @{ Value = '{0:N0}' -f $stats.Locations; Caption = 'locations'; Color = 'grey70' }
    }
    Show-AACTileRow -Tile $tiles
    [Spectre.Console.AnsiConsole]::WriteLine()
    $money = { param($Value, [string] $Currency) ('{0:N2} {1}' -f [double]$Value, $Currency).Trim() }
    if ($stats.HasCost) {
        $costTiles = @(foreach ($total in @($stats.Cost | Select-Object -First 2)) {
                @{ Value = (& $money $total.MonthToDate $total.Currency); Caption = 'month to date'; Color = 'springgreen2' }
                @{ Value = (& $money $total.LastMonth $total.Currency); Caption = 'last month'; Color = 'deepskyblue1' }
            })
        $deletedItems = @($Inventory.Items | Where-Object Level -EQ 'DeletedResources')
        if ($deletedItems.Count -and @($stats.Cost).Count -eq 1) {
            $deletedTotal = 0.0
            foreach ($item in $deletedItems) { $deletedTotal += [double]$item.CostMonthToDate }
            $costTiles += @{ Value = (& $money $deletedTotal $stats.Cost[0].Currency); Caption = 'deleted resources this month'; Color = 'orange1' }
        }
        $unread = @($Inventory.Items | Where-Object { $_.Level -eq 'Subscription' -and $_.CostStatus -notin 'OK', 'No cost', '' }).Count
        if ($unread) { $costTiles += @{ Value = '{0:N0}' -f $unread; Caption = 'subscriptions without cost data'; Color = 'orange1' } }
        if ($costTiles.Count) {
            Show-AACTileRow -Tile $costTiles
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        else {
            Write-AACMarkup '[grey58]Cost Management reports no cost for this scope this month or last.[/]'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    $order = @{ Tenant = 0; ManagementGroup = 1; Subscription = 2; ResourceGroup = 3; DeletedResources = 3; Resource = 4 }
    $stop = $order[$Depth]
    $count = {
        param([int] $Value, [string] $One, [string] $Many)
        "[white]$('{0:N0}' -f $Value)[/] $(if ($Value -eq 1) { $One } else { $Many })"
    }
    # A node's security posture: its score in colour and its findings by severity.
    $posture = {
        param($Node)
        $parts = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $Node.SecureScore) { $parts.Add("[$($ratingColor[$Node.Rating])]$($Node.SecureScore)%[/]") }
        if ($Node.High) { $parts.Add("[red1]H$($Node.High)[/]") }
        if ($Node.Medium) { $parts.Add("[orange1]M$($Node.Medium)[/]") }
        if ($Node.Low) { $parts.Add("[deepskyblue1]L$($Node.Low)[/]") }
        if ($parts.Count) { '  ' + ($parts -join ' ') } else { '' }
    }
    $label = {
        param($Node)
        $name = "[bold]$(& $escape $Node.DisplayName)[/]"
        switch ($Node.Level) {
            'Tenant' {
                "[grey70 on grey23] TENANT [/] $name [grey50]$(& $escape $Node.Name)[/]  [grey58]$((@((& $count $Node.ManagementGroups 'management group' 'management groups'), (& $count $Node.Subscriptions 'subscription' 'subscriptions'), (& $count $Node.ResourceGroups 'resource group' 'resource groups'), (& $count $Node.Resources 'resource' 'resources'))) -join " $($glyph.Dot) ")[/]"
            }
            'ManagementGroup' {
                "[mediumpurple2]MG[/] $name [grey50]$(& $escape $Node.Name)[/]  [grey58]$((@((& $count $Node.Subscriptions 'subscription' 'subscriptions'), (& $count $Node.Resources 'resource' 'resources'))) -join " $($glyph.Dot) ")[/]"
            }
            'Subscription' {
                $state = if ($Node.State -and $Node.State -ne 'Enabled') { " [orange1]$(& $escape $Node.State)[/]" } else { '' }
                "[gold1]SUB[/] $name$state [grey50]$(& $escape $Node.SubscriptionId)[/]  [grey58]$((@((& $count $Node.ResourceGroups 'resource group' 'resource groups'), (& $count $Node.Resources 'resource' 'resources'))) -join " $($glyph.Dot) ")[/]"
            }
            'ResourceGroup' {
                if ($Node.Resources -eq 0) {
                    "[deepskyblue1]RG[/] [orange1]$(& $escape $Node.DisplayName)[/] [grey50]$(& $escape $Node.Location)[/]  [orange1]empty[/]"
                }
                else {
                    "[deepskyblue1]RG[/] $name [grey50]$(& $escape $Node.Location)[/]  [grey58]$(& $count $Node.Resources 'resource' 'resources')$(if ($Node.TopTypes) { " $($glyph.Dot) $(& $escape $Node.TopTypes)" })[/]"
                }
            }
            'DeletedResources' {
                "[orange1]DEL[/] [orange1]$(& $escape $Node.DisplayName)[/]  [grey58]$(& $escape $Node.Detail)[/]"
            }
            'Resource' {
                "[green3]$(& $escape $Node.DisplayName)[/] [grey58]$(& $escape ($Node.Type -replace '^microsoft\.', ''))$(if ($Node.Location) { " $($glyph.Dot) $(& $escape $Node.Location)" })$(if ($Node.Sku) { " $($glyph.Dot) $(& $escape $Node.Sku)" })[/]"
            }
        }
    }

    # A node's cost month to date (with -Cost): green, 'mixed' across
    # currencies, or why a subscription's couldn't be read.
    $spend = {
        param($Node)
        if (-not $stats.HasCost) { return '' }
        if ($Node.Level -eq 'Subscription' -and $Node.CostStatus -notin 'OK', 'No cost', '') { return "  [orange1]cost not read[/]" }
        if ($Node.Currency -eq 'mixed') { return "  [grey58]cost in several currencies[/]" }
        if ($Node.CostMonthToDate -gt 0 -or $Node.CostLastMonth -gt 0) {
            return "  [springgreen2]$(& $escape (& $money $Node.CostMonthToDate $Node.Currency))[/][grey50] MTD[/]$(if ($Node.Level -ne 'Resource') { "[grey42] $($glyph.Dot) last month $(& $escape (& $money $Node.CostLastMonth $Node.Currency))[/]" })"
        }
        if ($Node.Level -eq 'Subscription') { return '  [grey50]no cost[/]' }
        ''
    }
    $withPosture = { param($Node) (& $label $Node) + (& $spend $Node) + (& $posture $Node) }
    $tree = [Spectre.Console.Tree]::new([Spectre.Console.Markup]::new((& $withPosture $Inventory.Root)))
    $tree.Style = [Spectre.Console.Style]::Parse('grey42')
    if (-not $unicode) { $tree.Guide = [Spectre.Console.TreeGuide]::Ascii }
    $add = {
        param($Parent, $Node)
        foreach ($child in $Node.Children) {
            if ($order[$child.Level] -gt $stop) { continue }
            $childNode = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new((& $withPosture $child)))
            $Parent.Nodes.Add($childNode)
            & $add $childNode $child
        }
    }
    & $add $tree $Inventory.Root
    [Spectre.Console.AnsiConsole]::Write($tree)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # The most common resource types.
    $types = @($Inventory.Root.TypeCounts.GetEnumerator() | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, Name | Select-Object -First 10 | ForEach-Object {
            @{ Label = ($_.Name -replace '^microsoft\.', ''); Value = $_.Value }
        })
    if ($types.Count) {
        Show-AACBarChart -Item $types -Title 'Most common resource types'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    # Cost: the resources that cost the most this month.
    if ($stats.HasCost -and @($Inventory.TopSpend).Count) {
        $currency = @($stats.Cost)[0].Currency
        $bars = @($Inventory.TopSpend | Where-Object Currency -EQ $currency | Select-Object -First 10 | ForEach-Object { @{ Label = "$($_.Name) ($($_.ResourceGroup))"; Value = $_.CostMonthToDate } })
        if ($bars.Count) {
            Show-AACBarChart -Item $bars -Title "Top spend this month ($currency)" -Format 'N2'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    # --- Insights (Get-AACInventory -Insight) ------------------------------------------------------
    $insight = $Inventory['Insight']
    if ($insight) {
        $istats = $insight.Stats
        Write-AACRule -Title '[bold]Insights[/]' -Color 'grey50'
        Show-AACTileRow -Tile @(
            @{ Value = '{0:N0}' -f $istats.AzureVms; Caption = 'Azure VMs'; Color = 'deepskyblue1' }
            @{ Value = '{0:N0}' -f $istats.ArcServers; Caption = 'Azure Arc servers'; Color = 'mediumpurple2' }
            @{ Value = '{0:N0}' -f $istats.StoppedBilled; Caption = 'VMs stopped but billed'; Color = $(if ($istats.StoppedBilled) { 'orange1' } else { 'green3' }) }
            @{ Value = "$('{0:N0}' -f $istats.UnattachedDisks) ($('{0:N0}' -f $istats.UnattachedDiskGb) GB)"; Caption = 'unattached disks'; Color = $(if ($istats.UnattachedDisks) { 'orange1' } else { 'green3' }) }
            @{ Value = '{0:N0}' -f ($istats.UnusedPublicIps + $istats.UnusedNics); Caption = 'unused public IPs and NICs'; Color = $(if ($istats.UnusedPublicIps + $istats.UnusedNics) { 'orange1' } else { 'green3' }) }
            if ($null -ne $istats.WasteCost) { @{ Value = (& $money $istats.WasteCost $istats.WasteCurrency); Caption = 'their cost this month'; Color = 'red1' } }
            if ($istats.Classic) { @{ Value = '{0:N0}' -f $istats.Classic; Caption = 'classic resources (retired)'; Color = 'red1' } }
        )
        [Spectre.Console.AnsiConsole]::WriteLine()
        # The mix: each breakdown as one proportion bar (the top 8, the rest as 'other').
        $titles = [ordered]@{ VmSizes = 'VM sizes'; OsVersions = 'Operating systems'; PowerStates = 'VM power states'; Hybrid = 'Azure VMs and Azure Arc servers'; StorageReplication = 'Storage account replication'; DatabaseTiers = 'Database tiers' }
        foreach ($key in $titles.Keys) {
            $items = @($insight.Breakdowns[$key])
            if (-not $items.Count) { continue }
            $slices = [ordered]@{}
            foreach ($item in @($items | Select-Object -First 8)) { $slices[[string]$item.Label] = $item.Value }
            $rest = 0; foreach ($item in @($items | Select-Object -Skip 8)) { $rest += $item.Value }
            if ($rest) { $slices['other'] = $rest }
            $colors = @{}
            if ($key -eq 'PowerStates') { $colors = @{ 'Running' = 'green3'; 'Deallocated' = 'grey50'; 'Stopped (still billed)' = 'orange1' } }
            Show-AACBreakdownChart -Data $slices -Title $titles[$key] -Color $colors -Width 120
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        $coverage = @($insight.Breakdowns.TagCoverage)
        if ($coverage.Count) {
            $required = @($istats.RequiredTags).Count
            $bars = @($coverage | ForEach-Object { @{ Label = $_.Label; Value = $_.Value; Color = $(if ($_.Value -ge 90) { 'green3' } elseif ($_.Value -ge 60) { 'orange1' } else { 'red1' }) } })
            Show-AACBarChart -Item $bars -Title $(if ($required) { "Required tags: resources with each (%) $($glyph.Dot) $($istats.TagCompliant) of $($istats.Resources) have them all" } else { 'Tag coverage: resources with each of the most used tags (%)' })
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        # What needs attention.
        $attention = @($insight.Findings)
        if ($attention.Count) {
            $table = [Spectre.Console.Table]::new()
            $table.Border = [Spectre.Console.TableBorder]::Rounded
            $table.BorderStyle = [Spectre.Console.Style]::Parse('orange1')
            $table.Expand = $true
            $table.Title = [Spectre.Console.TableTitle]::new("[bold orange1]$($glyph.Bullet) Needs attention[/] [grey58]$($glyph.Dot) $($attention.Count) item(s)[/]")
            foreach ($header in 'Severity', 'Finding', 'Resource', 'Where', 'Detail', 'Cost this month') {
                $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
                if ($header -eq 'Cost this month') { $column.Alignment = [Spectre.Console.Justify]::Right; $column.NoWrap = $true }
                $table.AddColumn($column) | Out-Null
            }
            $severityColor = @{ High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1' }
            foreach ($finding in $attention) {
                $cells = @(
                    "[$($severityColor[$finding.Severity])]$(& $escape $finding.Severity)[/]"
                    "[bold]$(& $escape $finding.Finding)[/]"
                    "[white]$(& $escape $finding.Resource)[/]"
                    "[grey58]$(& $escape (@($finding.ResourceGroup, $finding.SubscriptionName) | Where-Object { $_ }) -join ' / ')[/]"
                    "[grey70]$(& $escape $finding.Detail)[/]"
                    $(if ($null -ne $finding.CostMonthToDate) { "[orange1]$(& $escape (& $money $finding.CostMonthToDate $finding.Currency))[/]" } else { '' })
                )
                [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        else {
            Write-AACMarkup "[green3]$($glyph.Bullet)[/] [grey70]Nothing needs attention: no unattached disks, unused public IPs or NICs, billed stopped VMs, classic resources, full subnets or connections down.[/]"
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        $links = @($insight.Connections)
        if ($links.Count) {
            Write-AACMarkup "[bold]$($glyph.Bullet) VPN and ExpressRoute[/]"
            foreach ($link in $links) {
                $ok = $link.Status -in 'Connected', 'Provisioned'
                Write-AACMarkup "  $(if ($ok) { "[green3]$($glyph.Bullet)[/]" } else { "[red1]$($glyph.Bullet)[/]" }) [white]$(& $escape $link.Name)[/] [grey58]$(& $escape $link.Kind) $($glyph.Dot) $(& $escape $link.Status) $($glyph.Dot) $(& $escape $link.Detail)[/]"
            }
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    # Security: the controls with the most to gain, and the High findings.
    $controls = @($Inventory.Controls | Where-Object { $_.PotentialIncrease -gt 0 } | Sort-Object -Property @{ Expression = 'PotentialIncrease'; Descending = $true }, Control | Select-Object -First 8)
    if ($controls.Count) {
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse('grey42')
        $table.Title = [Spectre.Console.TableTitle]::new("[bold]$($glyph.Bullet) Security controls with the most to gain[/] [grey58]$($glyph.Dot) potential secure score increase[/]")
        foreach ($header in 'Control', 'Subscription', 'Score', 'Unhealthy', 'Potential increase') {
            $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
            if ($header -in 'Score', 'Unhealthy', 'Potential increase') { $column.Alignment = [Spectre.Console.Justify]::Right }
            $table.AddColumn($column) | Out-Null
        }
        foreach ($control in $controls) {
            $rating = if ($null -eq $control.Score) { '' } elseif ($control.Score -ge 70) { 'Good' } elseif ($control.Score -ge 40) { 'Fair' } else { 'Poor' }
            $cells = @(
                [Spectre.Console.Markup]::new("[white]$(& $escape $control.Control)[/]")
                [Spectre.Console.Markup]::new("[grey70]$(& $escape $control.SubscriptionName)[/]")
                [Spectre.Console.Markup]::new($(if ($rating) { "[$($ratingColor[$rating])]$($control.Score)%[/]" } else { '' }))
                [Spectre.Console.Markup]::new("[grey70]$($control.UnhealthyResources)[/]")
                [Spectre.Console.Markup]::new("[bold $(if ($control.PotentialIncrease -ge 5) { 'red1' } elseif ($control.PotentialIncrease -ge 2) { 'orange1' } else { 'deepskyblue1' })]+$($control.PotentialIncrease)%[/]")
            )
            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]$cells) | Out-Null
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    $high = @($Inventory.Recommendations | Where-Object Severity -EQ 'High')
    if ($high.Count) {
        Write-AACMarkup "[bold red1]$($glyph.Bullet) High-severity findings ($($high.Count))[/]"
        foreach ($finding in $high) {
            Write-AACMarkup "  [red1]H[/] [white]$(& $escape $finding.Resource)[/] [grey50]$(& $escape $finding.ResourceGroup)[/]  [grey70]$(& $escape $finding.Recommendation)[/]"
        }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if ($stats.HasSecurity) {
        Write-AACMarkup "[grey42]Secure score: Defender for Cloud's for subscriptions (added up for management groups and the tenant); for resource groups and resources, the share of their assessed recommendations that are healthy. Good 70%+, Fair 40-69%, Poor under 40%.[/]"
    }
    if ($stats.HasCost) {
        Write-AACMarkup "[grey42]Cost: Cost Management's actual cost, month to date (MTD) and last month, in each subscription's billing currency - never converted. 'Deleted resources' are costs of resources no longer in Azure, and charges not tied to a resource.[/]"
    }
    if ($stats.EmptyGroups) {
        Write-AACStatusLine Warning "$($stats.EmptyGroups) resource group(s) have no resources."
    }
    foreach ($notice in @($Inventory.Notice | Where-Object { $_ })) {
        Write-AACMarkup "[grey58]$(& $escape $notice)[/]"
    }
    Write-AACMarkup "[grey42]-Depth Resource lists every resource; add -PassThru (or pipe the command) for the objects; -CsvPath, -PdfPath or -HtmlPath for a report.[/]"
}
