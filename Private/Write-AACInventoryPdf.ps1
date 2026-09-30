function Write-AACInventoryPdf {
    <#
    .SYNOPSIS
        Writes the tenant inventory (ConvertTo-AACInventory) as a landscape A4
        PDF report.
    .DESCRIPTION
        1. Summary: title, scope, tiles (management groups, subscriptions,
           resource groups, resources, types, locations).
        2. Hierarchy: the tree down to resource groups, indented, with each
           level's counts; empty resource groups in amber.
        3. Security (with Defender for Cloud data): each subscription's secure
           score, the controls with the most to gain, and the unhealthy
           recommendations, most severe first - scores coloured Good (70%+)
           green, Fair (40-69%) amber, Poor red; severities High red, Medium
           amber, Low blue.
        4. Cost (with Get-AACInventory -Cost): totals per currency, each
           subscription's cost month to date and last month (or why it
           couldn't be read), the resource groups and resources that cost
           the most this month, and the deleted resources' costs.
        5. Insights (with Get-AACInventory -Insight): the estate's mix as
           tables of counts and shares (VM sizes, operating systems, power
           states, Azure and Arc, storage replication, database tiers, tag
           coverage), what needs attention with its cost, the fullest
           subnets and the VPN and ExpressRoute connections.
        6. Subscriptions, resource groups, and resources by type.
        7. Every resource (name, type, resource group, subscription, location,
           SKU) - up to -MaxResources; the HTML report and CSV have them all.

        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Inventory,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [int] $MaxResources = 5000
    )

    $items = @($Inventory.Items)
    $stats = $Inventory.Stats
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($stats.Resources) resources in $($stats.Subscriptions) subscriptions" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $number = { param($Cell, $Value) $p = $Cell.AddParagraph(('{0:N0}' -f [double]$Value)); $p.Format.Alignment = $right }
    $security = [bool]$stats.HasSecurity
    $blue = [MigraDoc.DocumentObjectModel.Color]::Parse('#0369A1')
    $scoreColor = { param($Score) if ($null -eq $Score) { $colors.Muted } elseif ($Score -ge 70) { $pdf.Tone.Good.Solid } elseif ($Score -ge 40) { $pdf.Tone.Warn.Solid } else { $pdf.Tone.Bad.Solid } }
    $severityColor = @{ High = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Low = $blue; Healthy = $pdf.Tone.Good.Solid; Moderate = $pdf.Tone.Warn.Solid }
    # A score as a bold coloured percentage; findings as coloured H / M / L counts.
    $addScore = {
        param($Cell, $Score)
        if ($null -eq $Score) { return }
        $p = $Cell.AddParagraph("$Score%")
        $p.Format.Alignment = $right
        $p.Format.Font.Name = 'Segoe UI Semibold'
        $p.Format.Font.Color = & $scoreColor $Score
    }
    $addFindings = {
        param($Cell, $Item)
        $p = $Cell.AddParagraph()
        $p.Format.Alignment = $right
        foreach ($level in @(@('High', 'H'), @('Medium', 'M'), @('Low', 'L'))) {
            $count = [int]$Item.($level[0])
            if (-not $count) { continue }
            $text = $p.AddFormattedText("$($level[1])$count ")
            $text.Color = $severityColor[$level[0]]
            $text.Bold = $true
        }
    }

    # --- 1. Summary -----------------------------------------------------------------------------
    & $pdf.AddTitle "Tenant inventory · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) {
        $facts['Azure account'] = [string]$script:AACSession.Account
        $facts['Tenant'] = [string]$script:AACSession.TenantId
    }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        if ($security -and $null -ne $stats.SecureScore) { @{ Value = "$($stats.SecureScore)%"; Label = "secure score ($($stats.Rating.ToLowerInvariant()))"; Color = (& $scoreColor $stats.SecureScore) } }
        if ($security) { @{ Value = $stats.High; Label = 'high-severity findings'; Color = $(if ($stats.High) { $pdf.Tone.Bad.Solid } else { $pdf.Tone.Good.Solid }) } }
        @{ Value = $stats.ManagementGroups; Label = 'management groups' }
        @{ Value = $stats.Subscriptions; Label = 'subscriptions' }
        @{ Value = $stats.ResourceGroups; Label = 'resource groups' }
        @{ Value = $stats.Resources; Label = 'resources' }
        if (-not $security) { @{ Value = $stats.Types; Label = 'resource types' } }
        if (-not $security) { @{ Value = $stats.Locations; Label = 'locations' } }
    )
    $tiles = & $pdf.NewTable @(1..$tileData.Count | ForEach-Object { $pdf.PageWidth / $tileData.Count })
    $tiles.TopPadding = & $pt 8
    $tiles.BottomPadding = & $pt 8
    $tileRow = $tiles.AddRow()
    for ($i = 0; $i -lt $tileData.Count; $i++) {
        $cell = $tileRow.Cells[$i]
        $cell.Shading.Color = $colors.Panel
        $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
        $cell.Borders.Left.Color = $colors.White
        $value = $cell.AddParagraph($(if ($tileData[$i].Value -is [string]) { $tileData[$i].Value } else { '{0:N0}' -f $tileData[$i].Value }))
        if ($tileData[$i].Contains('Color')) { $value.Format.Font.Color = $tileData[$i].Color }
        $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $value.Format.Font.Size = 18
        $value.Format.Font.Name = 'Segoe UI Semibold'
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }
    if ($stats.EmptyGroups) {
        $note = $section.AddParagraph("$($stats.EmptyGroups) resource group(s) have no resources - shown in amber below.")
        $note.Format.Font.Color = $colors.Amber
        $note.Format.SpaceBefore = & $pt 6
    }

    # --- 2. The hierarchy, down to resource groups ----------------------------------------------------
    $section.AddParagraph('Hierarchy', 'Heading2') | Out-Null
    $levelLabel = @{ Tenant = 'Tenant'; ManagementGroup = 'Management group'; Subscription = 'Subscription'; ResourceGroup = 'Resource group' }
    $tree = if ($security) { & $pdf.NewTable @(7.4, 2.9, 5.2, 2.2, 2.4, 2.0, 1.8, 2.2) } else { & $pdf.NewTable @(9.0, 3.2, 6.2, 2.4, 2.6, 2.3) }
    & $pdf.AddHeaderRow $tree @(@('Name', 'Level', 'Detail', 'Subscriptions', 'Resource groups', 'Resources') + $(if ($security) { @('Score', 'Findings') } else { @() })) @(3, 4, 5, 6, 7)
    foreach ($item in @($items | Where-Object Level -NotIn 'Resource', 'DeletedResources')) {
        $row = & $pdf.AddBodyRow $tree
        $name = $row.Cells[0].AddParagraph($item.Name)
        $name.Format.LeftIndent = [MigraDoc.DocumentObjectModel.Unit]::FromCentimeter([Math]::Min(6, 0.45 * $item.Depth))
        if ($item.Level -ne 'ResourceGroup') { $name.Format.Font.Name = 'Segoe UI Semibold' }
        $row.Cells[1].AddParagraph($levelLabel[$item.Level]).Format.Font.Color = $colors.Muted
        $what = switch ($item.Level) {
            'Subscription' { (@($item.SubscriptionId, $item.State) | Where-Object { $_ }) -join ' · ' }
            'ResourceGroup' { (@($item.Location, $item.TopTypes) | Where-Object { $_ }) -join ' · ' }
            default { '' }
        }
        $detailText = $row.Cells[2].AddParagraph($what)
        $detailText.Format.Font.Size = 7.5
        $detailText.Format.Font.Color = $colors.Muted
        if ($item.Level -in 'Tenant', 'ManagementGroup') { & $number $row.Cells[3] $item.Subscriptions }
        if ($item.Level -ne 'ResourceGroup') { & $number $row.Cells[4] $item.ResourceGroups }
        & $number $row.Cells[5] $item.Resources
        if ($security) {
            & $addScore $row.Cells[6] $item.SecureScore
            & $addFindings $row.Cells[7] $item
        }
        if ($item.Level -eq 'ResourceGroup' -and $item.Resources -eq 0) {
            foreach ($cell in $row.Cells) { foreach ($paragraph in $cell.Elements) { $paragraph.Format.Font.Color = $colors.Amber } }
        }
    }

    # --- 3. Security (Defender for Cloud) --------------------------------------------------------------
    if ($security) {
        $section.AddPageBreak()
        $section.AddParagraph('Security posture', 'Heading2') | Out-Null
        $note = $section.AddParagraph('Microsoft Defender for Cloud. Secure score: Defender''s own for subscriptions (added up for management groups and the tenant); for resource groups and resources, the share of their assessed recommendations that are healthy. Good 70% or more, Fair 40-69%, Poor under 40%.')
        $note.Format.Font.Size = 8
        $note.Format.Font.Color = $colors.Muted
        $note.Format.SpaceAfter = & $pt 6
        $table = & $pdf.NewTable @(8.0, 7.0, 2.6, 3.0, 1.8, 1.8, 1.9)
        & $pdf.AddHeaderRow $table @('Subscription', 'Management group', 'Secure score', 'Points', 'High', 'Medium', 'Low') @(2, 3, 4, 5, 6)
        foreach ($item in @($items | Where-Object Level -EQ 'Subscription' | Sort-Object -Property @{ Expression = { if ($null -eq $_.SecureScore) { 999 } else { $_.SecureScore } } }, Name)) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Name) | Out-Null
            $row.Cells[1].AddParagraph($item.ManagementGroup) | Out-Null
            if ($null -ne $item.SecureScore) { & $addScore $row.Cells[2] $item.SecureScore } else { $row.Cells[2].AddParagraph('no data').Format.Font.Color = $colors.Muted }
            if ($item.ScorePoints) {
                $pointsText = $row.Cells[3].AddParagraph($item.ScorePoints)
                $pointsText.Format.Alignment = $right
                $pointsText.Format.Font.Color = $colors.Muted
            }
            foreach ($level in @(@(4, 'High'), @(5, 'Medium'), @(6, 'Low'))) {
                $count = [int]$item.($level[1])
                $p = $row.Cells[$level[0]].AddParagraph("$count")
                $p.Format.Alignment = $right
                if ($count) { $p.Format.Font.Color = $severityColor[$level[1]]; $p.Format.Font.Name = 'Segoe UI Semibold' } else { $p.Format.Font.Color = $colors.Muted }
            }
        }

        $gain = @($Inventory.Controls | Where-Object { $_.PotentialIncrease -gt 0 } | Sort-Object -Property @{ Expression = 'PotentialIncrease'; Descending = $true }, Control)
        if ($gain.Count) {
            $section.AddParagraph('Security controls with the most to gain', 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(10.0, 6.4, 2.4, 3.3, 4.0)
            & $pdf.AddHeaderRow $table @('Control', 'Subscription', 'Score', 'Unhealthy resources', 'Potential increase') @(2, 3, 4)
            foreach ($control in $gain) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($control.Control) | Out-Null
                $row.Cells[1].AddParagraph($control.SubscriptionName) | Out-Null
                & $addScore $row.Cells[2] $control.Score
                & $number $row.Cells[3] $control.UnhealthyResources
                $p = $row.Cells[4].AddParagraph("+$($control.PotentialIncrease)%")
                $p.Format.Alignment = $right
                $p.Format.Font.Name = 'Segoe UI Semibold'
                $p.Format.Font.Color = $(if ($control.PotentialIncrease -ge 5) { $pdf.Tone.Bad.Solid } elseif ($control.PotentialIncrease -ge 2) { $pdf.Tone.Warn.Solid } else { $blue })
            }
        }

        $findings = @($Inventory.Recommendations | Select-Object -First 2000)
        if ($findings.Count) {
            $section.AddParagraph("Unhealthy recommendations$(if ($findings.Count -lt $Inventory.Recommendations.Count) { " (the first $($findings.Count) of $($Inventory.Recommendations.Count))" })", 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(1.9, 9.6, 4.8, 3.6, 3.8, 2.4)
            & $pdf.AddHeaderRow $table @('Severity', 'Recommendation', 'Resource', 'Resource group', 'Subscription', 'User impact')
            foreach ($finding in $findings) {
                $row = & $pdf.AddBodyRow $table
                $severity = $row.Cells[0].AddParagraph($finding.Severity)
                $severity.Format.Font.Name = 'Segoe UI Semibold'
                if ($severityColor.Contains($finding.Severity)) { $severity.Format.Font.Color = $severityColor[$finding.Severity] }
                $row.Cells[1].AddParagraph($finding.Recommendation) | Out-Null
                $row.Cells[2].AddParagraph($finding.Resource) | Out-Null
                $row.Cells[3].AddParagraph($finding.ResourceGroup) | Out-Null
                $row.Cells[4].AddParagraph($finding.SubscriptionName) | Out-Null
                $impact = $row.Cells[5].AddParagraph($finding.Impact)
                if ($severityColor.Contains($finding.Impact)) { $impact.Format.Font.Color = $severityColor[$finding.Impact] }
            }
        }
    }

    # --- 4. Cost (Cost Management) ----------------------------------------------------------------------
    if ($stats.HasCost) {
        $section.AddPageBreak()
        $section.AddParagraph('Cost', 'Heading2') | Out-Null
        $note = $section.AddParagraph('Azure Cost Management: actual cost month to date and last month, in each subscription''s billing currency - never converted. Deleted resources: costs of resources no longer in Azure, and charges not tied to a resource.')
        $note.Format.Font.Size = 8
        $note.Format.Font.Color = $colors.Muted
        $note.Format.SpaceAfter = & $pt 6
        $money = { param($Cell, $Value, [string] $Currency, [switch] $Bold) $p = $Cell.AddParagraph(('{0:N2} {1}' -f [double]$Value, $Currency).Trim()); $p.Format.Alignment = $right; if ($Bold) { $p.Format.Font.Name = 'Segoe UI Semibold' }; if ([double]$Value -eq 0) { $p.Format.Font.Color = $colors.Muted } }
        if (@($stats.Cost).Count) {
            $table = & $pdf.NewTable @(4.0, 5.0, 5.0)
            & $pdf.AddHeaderRow $table @('Currency', 'Month to date', 'Last month') @(1, 2)
            foreach ($total in @($stats.Cost)) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($total.Currency) | Out-Null
                & $money $row.Cells[1] $total.MonthToDate $total.Currency -Bold
                & $money $row.Cells[2] $total.LastMonth $total.Currency
            }
        }
        else {
            $section.AddParagraph('Cost Management reports no cost for this scope this month or last.').Format.Font.Color = $colors.Muted
        }

        $section.AddParagraph('By subscription', 'Heading3') | Out-Null
        $table = & $pdf.NewTable @(7.0, 6.0, 3.6, 3.6, 5.3)
        & $pdf.AddHeaderRow $table @('Subscription', 'Management group', 'Month to date', 'Last month', 'Cost data') @(2, 3)
        foreach ($item in @($items | Where-Object Level -EQ 'Subscription' | Sort-Object -Property @{ Expression = { [double]$_.CostMonthToDate }; Descending = $true }, Name)) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Name) | Out-Null
            $row.Cells[1].AddParagraph($item.ManagementGroup) | Out-Null
            if ($item.CostStatus -in 'OK', 'No cost') {
                & $money $row.Cells[2] $item.CostMonthToDate $item.Currency -Bold
                & $money $row.Cells[3] $item.CostLastMonth $item.Currency
            }
            $status = $row.Cells[4].AddParagraph($item.CostStatus)
            $status.Format.Font.Size = 7.5
            $status.Format.Font.Color = $(if ($item.CostStatus -eq 'OK') { $pdf.Tone.Good.Solid } elseif ($item.CostStatus -eq 'No cost') { $colors.Muted } else { $colors.Amber })
        }

        $spenders = @(
            @{ Title = 'Resource groups that cost the most this month'; Rows = @($items | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.CostMonthToDate -gt 0 } | Sort-Object -Property CostMonthToDate -Descending | Select-Object -First 20); Columns = @('Resource group', 'Subscription', 'Resources'); Widths = @(8.0, 6.5, 2.5) }
            @{ Title = 'Resources that cost the most this month'; Rows = @($Inventory.TopSpend); Columns = @('Resource', 'Resource group', 'Type'); Widths = @(6.0, 5.0, 6.0) }
            @{ Title = 'Deleted resources'; Rows = @($items | Where-Object Level -EQ 'DeletedResources' | Sort-Object -Property CostMonthToDate -Descending); Columns = @('Subscription', 'Management group', ''); Widths = @(8.0, 8.99, 0.01) }
        )
        foreach ($list in $spenders) {
            if (-not $list.Rows.Count) { continue }
            $section.AddParagraph($list.Title, 'Heading3') | Out-Null
            $table = & $pdf.NewTable @($list.Widths + @(3.6, 3.6))
            & $pdf.AddHeaderRow $table @($list.Columns + @('Month to date', 'Last month')) @(3, 4)
            foreach ($item in $list.Rows) {
                $row = & $pdf.AddBodyRow $table
                $cells = switch ($item.Level) {
                    'ResourceGroup' { @($item.Name, $item.SubscriptionName, ('{0:N0}' -f $item.Resources)) }
                    'Resource' { @($item.Name, $item.ResourceGroup, ($item.Type -replace '^microsoft\.', '')) }
                    default { @($item.SubscriptionName, $item.ManagementGroup, '') }
                }
                for ($i = 0; $i -lt 3; $i++) { $row.Cells[$i].AddParagraph([string]$cells[$i]) | Out-Null }
                & $money $row.Cells[3] $item.CostMonthToDate $item.Currency -Bold
                & $money $row.Cells[4] $item.CostLastMonth $item.Currency
            }
        }
    }

    # --- Insights (Get-AACInventory -Insight) -----------------------------------------------------------
    $insight = $Inventory['Insight']
    if ($insight) {
        $istats = $insight.Stats
        $section.AddPageBreak()
        $section.AddParagraph('Insights', 'Heading2') | Out-Null
        $summary = $section.AddParagraph(('{0:N0} Azure VMs ({1:N0} running, {2:N0} deallocated, {3:N0} stopped but billed) and {4:N0} Azure Arc servers. {5:N0} item(s) need attention{6}.' -f $istats.AzureVms, $istats.Running, $istats.Deallocated, $istats.StoppedBilled, $istats.ArcServers, $istats.Findings, $(if ($null -ne $istats.WasteCost) { (', costing {0:N2} {1} this month' -f $istats.WasteCost, $istats.WasteCurrency) } else { '' })))
        $summary.Format.SpaceAfter = & $pt 6
        # Each breakdown as a small table - two side by side.
        $titles = [ordered]@{ VmSizes = 'VM sizes'; OsVersions = 'Operating systems'; PowerStates = 'VM power states'; Hybrid = 'Azure and Azure Arc'; StorageReplication = 'Storage replication'; DatabaseTiers = 'Database tiers' }
        $present = @($titles.Keys | Where-Object { @($insight.Breakdowns[$_]).Count })
        $half = ($pdf.PageWidth - 1.0) / 2
        for ($i = 0; $i -lt $present.Count; $i += 2) {
            $pair = $section.AddTable()
            $pair.AddColumn([MigraDoc.DocumentObjectModel.Unit]::FromCentimeter($half + 0.5)) | Out-Null
            $pair.AddColumn([MigraDoc.DocumentObjectModel.Unit]::FromCentimeter($half + 0.5)) | Out-Null
            $pairRow = $pair.AddRow()
            for ($j = 0; $j -lt 2 -and $i + $j -lt $present.Count; $j++) {
                $key = $present[$i + $j]
                $slices = @($insight.Breakdowns[$key])
                $total = 0; foreach ($slice in $slices) { $total += $slice.Value }
                $cell = $pairRow.Cells[$j]
                $heading = $cell.AddParagraph($titles[$key]); $heading.Format.Font.Name = 'Segoe UI Semibold'; $heading.Format.SpaceAfter = & $pt 2
                $inner = $cell.Elements.AddTable()
                $inner.Borders.Width = 0
                $inner.AddColumn([MigraDoc.DocumentObjectModel.Unit]::FromCentimeter($half - 4.2)) | Out-Null
                $inner.AddColumn([MigraDoc.DocumentObjectModel.Unit]::FromCentimeter(1.8)) | Out-Null
                $inner.AddColumn([MigraDoc.DocumentObjectModel.Unit]::FromCentimeter(1.8)) | Out-Null
                foreach ($slice in @($slices | Select-Object -First 12)) {
                    $line = $inner.AddRow()
                    $line.Cells[0].AddParagraph([string]$slice.Label) | Out-Null
                    $n = $line.Cells[1].AddParagraph(('{0:N0}' -f $slice.Value)); $n.Format.Alignment = $right
                    $share = $line.Cells[2].AddParagraph($(if ($total) { '{0:N0}%' -f (100 * $slice.Value / $total) } else { '' })); $share.Format.Alignment = $right; $share.Format.Font.Color = $colors.Muted
                }
            }
            $section.AddParagraph().Format.SpaceAfter = & $pt 4
        }
        if (@($insight.Breakdowns.TagCoverage).Count) {
            $section.AddParagraph($(if (@($istats.RequiredTags).Count) { "Required tags ($($istats.TagCompliant) of $($istats.Resources) resources have them all)" } else { 'Tag coverage (the most used tags)' }), 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(10.0, 4.0, 4.0)
            & $pdf.AddHeaderRow $table @('Tag', 'Resources with it', 'Share') @(1, 2)
            foreach ($tag in @($insight.Breakdowns.TagCoverage)) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph([string]$tag.Label) | Out-Null
                & $number $row.Cells[1] $tag.Resources
                $share = $row.Cells[2].AddParagraph("$($tag.Value)%"); $share.Format.Alignment = $right; $share.Format.Font.Name = 'Segoe UI Semibold'
                $share.Format.Font.Color = $(if ($tag.Value -ge 90) { $pdf.Tone.Good.Solid } elseif ($tag.Value -ge 60) { $pdf.Tone.Warn.Solid } else { $pdf.Tone.Bad.Solid })
            }
        }
        $attention = @($insight.Findings)
        $section.AddParagraph("Needs attention ($($attention.Count))", 'Heading3') | Out-Null
        if ($attention.Count) {
            $table = & $pdf.NewTable @(1.8, 4.4, 5.2, 4.6, 7.6, 2.4)
            & $pdf.AddHeaderRow $table @('Severity', 'Finding', 'Resource', 'Where', 'Detail', 'Cost (month)') @(5)
            foreach ($finding in $attention) {
                $row = & $pdf.AddBodyRow $table
                $severity = $row.Cells[0].AddParagraph($finding.Severity); $severity.Format.Font.Name = 'Segoe UI Semibold'
                $severity.Format.Font.Color = $(switch ($finding.Severity) { 'High' { $pdf.Tone.Bad.Solid } 'Medium' { $pdf.Tone.Warn.Solid } default { $blue } })
                $row.Cells[1].AddParagraph($finding.Finding) | Out-Null
                $row.Cells[2].AddParagraph($finding.Resource) | Out-Null
                $row.Cells[3].AddParagraph((@($finding.ResourceGroup, $finding.SubscriptionName) | Where-Object { $_ }) -join ' / ').Format.Font.Color = $colors.Muted
                $detailText = $row.Cells[4].AddParagraph($finding.Detail); $detailText.Format.Font.Size = 7.5
                if ($null -ne $finding.CostMonthToDate) { $cost = $row.Cells[5].AddParagraph(('{0:N2} {1}' -f $finding.CostMonthToDate, $finding.Currency).Trim()); $cost.Format.Alignment = $right }
            }
        }
        else { $section.AddParagraph('Nothing: no unattached disks, unused public IPs or NICs, billed stopped VMs, classic resources, full subnets or connections down.').Format.Font.Color = $colors.Muted }
        $fullest = @($insight.Subnets | Where-Object { $null -ne $_.UsedPercent } | Select-Object -First 25)
        if ($fullest.Count) {
            $section.AddParagraph('The fullest subnets', 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(6.0, 5.0, 3.6, 2.2, 2.2, 2.2, 5.0)
            & $pdf.AddHeaderRow $table @('Virtual network', 'Subnet', 'Prefix', 'Used', 'Usable', 'Used (%)', 'Subscription') @(3, 4, 5)
            foreach ($subnet in $fullest) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($subnet.VirtualNetwork) | Out-Null
                $row.Cells[1].AddParagraph($subnet.Subnet) | Out-Null
                $row.Cells[2].AddParagraph($subnet.Prefix).Format.Font.Size = 7.5
                & $number $row.Cells[3] $subnet.Used
                & $number $row.Cells[4] $subnet.Usable
                $used = $row.Cells[5].AddParagraph("$($subnet.UsedPercent)%"); $used.Format.Alignment = $right
                if ($subnet.UsedPercent -ge 80) { $used.Format.Font.Color = $pdf.Tone.Bad.Solid; $used.Format.Font.Name = 'Segoe UI Semibold' }
                $row.Cells[6].AddParagraph($subnet.SubscriptionName) | Out-Null
            }
        }
        if (@($insight.Connections).Count) {
            $section.AddParagraph('VPN and ExpressRoute', 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(6.0, 4.6, 3.0, 7.4, 5.0)
            & $pdf.AddHeaderRow $table @('Connection', 'Kind', 'Status', 'Detail', 'Subscription')
            foreach ($link in $insight.Connections) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($link.Name) | Out-Null
                $row.Cells[1].AddParagraph($link.Kind) | Out-Null
                $status = $row.Cells[2].AddParagraph($link.Status); $status.Format.Font.Name = 'Segoe UI Semibold'
                $status.Format.Font.Color = $(if ($link.Status -in 'Connected', 'Provisioned') { $pdf.Tone.Good.Solid } else { $pdf.Tone.Bad.Solid })
                $row.Cells[3].AddParagraph($link.Detail).Format.Font.Size = 7.5
                $row.Cells[4].AddParagraph($link.SubscriptionName) | Out-Null
            }
        }
    }

    # --- 6. Subscriptions, resource groups, resource types ---------------------------------------------
    $subscriptions = @($items | Where-Object Level -EQ 'Subscription')
    if ($subscriptions.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Subscriptions', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(6.0, 6.8, 2.2, 5.0, 2.6, 2.4)
        & $pdf.AddHeaderRow $table @('Subscription', 'Subscription ID', 'State', 'Management group', 'Resource groups', 'Resources') @(4, 5)
        foreach ($item in $subscriptions) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Name) | Out-Null
            $row.Cells[1].AddParagraph($item.SubscriptionId).Format.Font.Size = 7.5
            $row.Cells[2].AddParagraph($item.State) | Out-Null
            $row.Cells[3].AddParagraph($item.ManagementGroup) | Out-Null
            & $number $row.Cells[4] $item.ResourceGroups
            & $number $row.Cells[5] $item.Resources
        }
    }
    $groups = @($items | Where-Object Level -EQ 'ResourceGroup' | Sort-Object -Property SubscriptionName, Name)
    if ($groups.Count) {
        $section.AddParagraph('Resource groups', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(6.0, 5.0, 3.0, 2.2, 8.8)
        & $pdf.AddHeaderRow $table @('Resource group', 'Subscription', 'Location', 'Resources', 'Most common types') @(3)
        foreach ($item in $groups) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Name) | Out-Null
            $row.Cells[1].AddParagraph($item.SubscriptionName) | Out-Null
            $row.Cells[2].AddParagraph($item.Location) | Out-Null
            & $number $row.Cells[3] $item.Resources
            $types = $row.Cells[4].AddParagraph($(if ($item.Resources -eq 0) { 'empty' } else { $item.TopTypes }))
            $types.Format.Font.Size = 7.5
            $types.Format.Font.Color = $(if ($item.Resources -eq 0) { $colors.Amber } else { $colors.Muted })
        }
    }
    $resources = @($items | Where-Object Level -EQ 'Resource')
    if ($resources.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Resources by type', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(12.0, 3.0, 3.0)
        & $pdf.AddHeaderRow $table @('Type', 'Resources', 'Share') @(1, 2)
        foreach ($type in @($resources | Group-Object -Property Type | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($type.Name) | Out-Null
            & $number $row.Cells[1] $type.Count
            $share = $row.Cells[2].AddParagraph(('{0:N1}%' -f (100 * $type.Count / $resources.Count)))
            $share.Format.Alignment = $right
            $share.Format.Font.Color = $colors.Muted
        }

        # --- 7. Every resource -----------------------------------------------------------------------
        $section.AddPageBreak()
        $shown = @($resources | Sort-Object -Property SubscriptionName, ResourceGroup, Type, Name | Select-Object -First $MaxResources)
        $section.AddParagraph("Resources$(if ($shown.Count -lt $resources.Count) { " (the first $('{0:N0}' -f $shown.Count) of $('{0:N0}' -f $resources.Count); the HTML report and CSV have them all)" })", 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(6.2, 6.4, 4.6, 4.2, 2.4, 2.6)
        & $pdf.AddHeaderRow $table @('Resource', 'Type', 'Resource group', 'Subscription', 'Location', 'SKU')
        foreach ($item in $shown) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Name) | Out-Null
            $row.Cells[1].AddParagraph($item.Type).Format.Font.Size = 7.5
            $row.Cells[2].AddParagraph($item.ResourceGroup) | Out-Null
            $row.Cells[3].AddParagraph($item.SubscriptionName) | Out-Null
            $row.Cells[4].AddParagraph($item.Location) | Out-Null
            $row.Cells[5].AddParagraph($item.Sku) | Out-Null
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
