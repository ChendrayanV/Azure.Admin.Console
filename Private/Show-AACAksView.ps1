function Show-AACAksView {
    <#
    .SYNOPSIS
        Renders Invoke-AACAksAssessment's result as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (clusters, nodes, WAF score, findings by severity,
        out of support, policy violations, PSRule failures); the clusters
        with their version and support, WAF score per pillar and findings;
        the pillars as a bar chart; the High and Medium findings with what to
        do; policy violations by namespace; and, for up to -Detail clusters,
        each one in detail - node pools, versions and the failed checks.
        Wrap the call in Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Scope,

        [int] $Detail = 3
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Assessment.Stats
    $policy = $Assessment.Policy
    $color = @{ High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1'; Info = 'grey62' }
    $scoreColor = { param($Score) if ($null -eq $Score) { 'grey50' } elseif ($Score -ge 80) { 'green3' } elseif ($Score -ge 60) { 'orange1' } else { 'red1' } }
    $score = { param($Score) if ($null -eq $Score) { '[grey50]-[/]' } else { "[$(& $scoreColor $Score)]$Score%[/]" } }
    $newTable = {
        param([string] $TitleText, [string[]] $Headers, [string[]] $Right = @())
        $t = [Spectre.Console.Table]::new(); $t.Border = [Spectre.Console.TableBorder]::Rounded; $t.BorderStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1'); $t.Expand = $true
        if ($TitleText) { $t.Title = [Spectre.Console.TableTitle]::new($TitleText) }
        foreach ($header in $Headers) { $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]"); if ($header -in $Right) { $column.Alignment = [Spectre.Console.Justify]::Right }; $t.AddColumn($column) | Out-Null }
        $t
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    foreach ($line in @($Assessment['Notices'])) { Write-AACMarkup "[orange1]$(& $escape $line)[/]" }
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Clusters; Caption = "clusters, $('{0:N0}' -f $stats.Nodes) nodes"; Color = 'deepskyblue1' }
        @{ Value = $(if ($null -ne $stats.WafScore) { "$($stats.WafScore)%" } else { '-' }); Caption = 'WAF checks passed'; Color = (& $scoreColor $stats.WafScore) }
        @{ Value = '{0:N0}' -f $stats.High; Caption = 'high findings'; Color = $(if ($stats.High) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Medium; Caption = 'medium findings'; Color = $(if ($stats.Medium) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.OutOfSupport; Caption = 'out of support'; Color = $(if ($stats.OutOfSupport) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.PSRuleFailed; Caption = 'PSRule failed'; Color = $(if ($stats.PSRuleFailed) { 'orange1' } else { 'green3' }) }
        if ($policy) { @{ Value = '{0:N0}' -f $policy.Stats.Violations; Caption = 'policy violations'; Color = $(if ($policy.Stats.Violations) { 'orange1' } else { 'green3' }) } }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    $table = & $newTable "[bold]$($glyph.Bullet) Clusters[/] [grey58]$($glyph.Dot) most at risk first[/]" @('Cluster', 'Version', 'Nodes', 'Network / API', 'Rel.', 'Sec.', 'Cost', 'Ops', 'Perf.', 'Findings') @('Nodes')
    foreach ($c in $Assessment.Clusters) {
        $counts = @(foreach ($level in 'High', 'Medium', 'Low') { if ($c.$level) { "[$($color[$level])]$($level.Substring(0, 1))$($c.$level)[/]" } })
        & $addRow $table @(
            "[bold]$(& $escape $c.Name)[/]`n[grey50]$(& $escape $c.ResourceGroup) $($glyph.Dot) $(& $escape $c.Subscription)[/]"
            "$(& $escape $c.Version)`n[$(if ($c.Support -like 'Out*') { 'red1' } elseif ($c.Support -eq 'Preview') { 'orange1' } else { 'green3' })]$(& $escape $c.Support)[/]$(if ($c.Upgrade) { "`n[grey50]$($glyph.Arrow) $(& $escape $c.Upgrade)[/]" })"
            "$($c.Nodes)`n[grey50]max $($c.MaxNodes)[/]"
            "[grey85]$(& $escape $c.Network)[/]`n[grey50]$(& $escape $c.ApiServer)[/]"
            (& $score $c.Reliability); (& $score $c.Security); (& $score $c.CostOptimization); (& $score $c.OperationalExcellence); (& $score $c.PerformanceEfficiency)
            $(if ($counts) { $counts -join ' ' } else { "[green3]$($glyph.Tick)[/]" })
        )
    }
    [Spectre.Console.AnsiConsole]::Write($table)
    [Spectre.Console.AnsiConsole]::WriteLine()
    $bars = @($Assessment.Pillars | Where-Object { $null -ne $_.Score } | ForEach-Object { @{ Label = $_.Pillar; Value = $_.Score } })
    if ($bars.Count) { Show-AACBarChart -Item $bars -Title 'Well-Architected checks passed per pillar (%)'; [Spectre.Console.AnsiConsole]::WriteLine() }

    $serious = @($Assessment.Findings | Where-Object { $_.Severity -in 'High', 'Medium' })
    if ($serious.Count) {
        Write-AACMarkup "[bold]$($glyph.Bullet) Findings[/] [grey58]$($glyph.Dot) High and Medium, $($serious.Count) in all[/]"
        foreach ($f in $serious | Select-Object -First 40) {
            Write-AACMarkup "  [$($color[$f.Severity])]$($f.Severity.ToUpperInvariant().PadRight(6))[/] [white]$(& $escape $f.Cluster)[/] [grey62]$(& $escape $f.Check)[/] [grey42]$(& $escape $f.Pillar) $($glyph.Dot) $(& $escape $f.Source)[/]"
            Write-AACMarkup "         [grey85]$(& $escape $f.Detail)[/]"
            if ($f.Recommendation) { Write-AACMarkup "         [grey50]$($glyph.Arrow) $(& $escape $f.Recommendation)[/]" }
        }
        if ($serious.Count -gt 40) { Write-AACMarkup "  [grey50]... and $($serious.Count - 40) more: -HtmlPath has them all.[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    if ($policy -and @($policy.ByNamespace).Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Azure Policy for Kubernetes by namespace[/] [grey58]$($glyph.Dot) $($policy.Stats.Violations) violation(s), $($policy.Stats.Workloads) workload(s)[/]" @('Namespace', 'Violations', 'Workloads', 'Under Deny', 'Policies violated') @('Violations', 'Workloads', 'Under Deny')
        foreach ($row in $policy.ByNamespace | Select-Object -First 15) { & $addRow $table @("[white]$(& $escape $row.Namespace)[/]", "$($row.Violations)", "$($row.Workloads)", $(if ($row.Deny) { "[red1]$($row.Deny)[/]" } else { '0' }), "[grey70]$(& $escape $row.PolicyNames)[/]") }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    if (@($Assessment.Clusters).Count -le $Detail) {
        foreach ($c in $Assessment.Clusters) {
            Write-AACRule -Title "[bold]$(& $escape $c.Name)[/] [grey58]Kubernetes $(& $escape $c.Version)[/]" -Color 'grey50'
            $table = & $newTable '[bold]Node pools[/]' @('Pool', 'Size', 'Nodes', 'Autoscale', 'Zones', 'Version / image', 'OS disk') @('Nodes')
            foreach ($pool in @($Assessment.NodePools | Where-Object ClusterId -EQ $c.ResourceId)) {
                & $addRow $table @("[white]$(& $escape $pool.Pool)[/] [grey50]$(& $escape $pool.Mode)[/]", "$(& $escape $pool.VmSize)`n[grey50]$(& $escape $pool.OsSku)[/]", "$($pool.Nodes)", "$(& $escape $pool.Autoscale)$(if ($pool.Autoscale -eq 'Yes') { " [grey50]$($pool.Min)-$($pool.Max)[/]" })", $(if ($pool.Zones) { & $escape $pool.Zones } else { '[orange1]none[/]' }), "$(& $escape $pool.Version)`n[grey50]image $(if ($null -ne $pool.NodeImageAge) { "$($pool.NodeImageAge) days old" } else { '?' })[/]", (& $escape $pool.OsDiskType))
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            $failed = @($Assessment.Checks | Where-Object { $_.ClusterId -eq $c.ResourceId -and $_.Status -eq 'Fail' })
            Write-AACMarkup "[grey58]Well-Architected:[/] $(@($Assessment.Checks | Where-Object { $_.ClusterId -eq $c.ResourceId -and $_.Status -eq 'Pass' }).Count) passed, [orange1]$($failed.Count) failed[/]$(if ($failed.Count) { ": $(& $escape ((@($failed | ForEach-Object Check)) -join '; '))" })"
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    else {
        Write-AACMarkup '[grey42]-Name shows a cluster in detail; -HtmlPath or -PdfPath has every cluster, setting and check.[/]'
    }
    Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath writes a CSV per table.[/]'
}
