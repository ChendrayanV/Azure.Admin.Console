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

    $order = @{ Tenant = 0; ManagementGroup = 1; Subscription = 2; ResourceGroup = 3; Resource = 4 }
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
            'Resource' {
                "[green3]$(& $escape $Node.DisplayName)[/] [grey58]$(& $escape ($Node.Type -replace '^microsoft\.', ''))$(if ($Node.Location) { " $($glyph.Dot) $(& $escape $Node.Location)" })$(if ($Node.Sku) { " $($glyph.Dot) $(& $escape $Node.Sku)" })[/]"
            }
        }
    }

    $withPosture = { param($Node) (& $label $Node) + (& $posture $Node) }
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
        foreach ($finding in @($high | Select-Object -First 10)) {
            Write-AACMarkup "  [red1]H[/] [white]$(& $escape $finding.Resource)[/] [grey50]$(& $escape $finding.ResourceGroup)[/]  [grey70]$(& $escape $finding.Recommendation)[/]"
        }
        if ($high.Count -gt 10) { Write-AACMarkup "  [grey58]... and $($high.Count - 10) more: -HtmlPath or -PdfPath lists them all.[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if ($stats.HasSecurity) {
        Write-AACMarkup "[grey42]Secure score: Defender for Cloud's for subscriptions (added up for management groups and the tenant); for resource groups and resources, the share of their assessed recommendations that are healthy. Good 70%+, Fair 40-69%, Poor under 40%.[/]"
    }
    if ($stats.EmptyGroups) {
        Write-AACMarkup "[orange1]![/] [grey58]$($stats.EmptyGroups) resource group(s) have no resources.[/]"
    }
    foreach ($notice in @($Inventory.Notice | Where-Object { $_ })) {
        Write-AACMarkup "[grey58]$(& $escape $notice)[/]"
    }
    Write-AACMarkup "[grey42]-Depth Resource lists every resource; add -PassThru (or pipe the command) for the objects; -CsvPath, -PdfPath or -HtmlPath for a report.[/]"
}
