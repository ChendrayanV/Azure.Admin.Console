function Write-AACAksPdf {
    <#
    .SYNOPSIS
        Writes Invoke-AACAksAssessment's report as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: the scope, tiles, the clusters with their WAF scores,
           the pillars.
        2. Findings, most severe first.
        3. Azure Policy: by namespace, by policy, by cluster.
        4. A section per cluster (a bookmark each): its settings by area,
           node pools, versions, failed checks and PSRule failures.
        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [ValidateRange(10, 5000)]
        [int] $RowLimit = 300
    )

    $stats = $Assessment.Stats
    $policy = $Assessment.Policy
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($stats.Clusters) AKS clusters" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $tone = @{ High = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Fail = $pdf.Tone.Bad.Solid; Pass = $pdf.Tone.Good.Solid; 'Out of support' = $pdf.Tone.Bad.Solid; 'Out of support (LTS only)' = $pdf.Tone.Bad.Solid; deny = $pdf.Tone.Bad.Solid }
    $table = {
        # Rows of objects, the properties to show (label = property), and the share of the width each gets.
        param([object[]] $Rows, [System.Collections.Specialized.OrderedDictionary] $Columns, [double[]] $Share)
        $labels = @($Columns.Keys)
        $total = ($Share | Measure-Object -Sum).Sum
        $t = & $pdf.NewTable @($Share | ForEach-Object { $pdf.PageWidth * $_ / $total })
        $numeric = @(for ($i = 0; $i -lt $labels.Count; $i++) { $sample = @($Rows | ForEach-Object { $_.($Columns[$labels[$i]]) } | Where-Object { $null -ne $_ -and "$_" -ne '' } | Select-Object -First 1); if ($sample.Count -and $sample[0] -is [ValueType] -and $sample[0] -isnot [bool]) { $i } })
        & $pdf.AddHeaderRow $t $labels $numeric
        foreach ($item in @($Rows) | Select-Object -First $RowLimit) {
            $row = & $pdf.AddBodyRow $t
            for ($i = 0; $i -lt $labels.Count; $i++) {
                $value = $item.($Columns[$labels[$i]])
                $text = if ($null -eq $value) { '' } elseif ($value -is [double]) { '{0:N1}' -f $value } else { [string]$value }
                if ($text.Length -gt 220) { $text = $text.Substring(0, 217) + '...' }
                $p = $row.Cells[$i].AddParagraph($text)
                $p.Format.Font.Size = 7
                if ($i -in $numeric) { $p.Format.Alignment = $right }
                if ($tone.Contains($text)) { $p.Format.Font.Color = $tone[$text]; $p.Format.Font.Bold = $true }
            }
        }
        if (@($Rows).Count -gt $RowLimit) { $more = $section.AddParagraph("The first $RowLimit of $(@($Rows).Count) rows - the HTML report and CSV files have them all."); $more.Format.Font.Size = 7; $more.Format.Font.Color = $colors.Muted }
    }
    $ordered = { param([string[]] $Pairs) $o = [ordered]@{}; for ($i = 0; $i -lt $Pairs.Count; $i += 2) { $o[$Pairs[$i]] = $Pairs[$i + 1] }; $o }

    # --- 1. Summary ------------------------------------------------------------------------------------------
    & $pdf.AddTitle "AKS cluster assessment · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    foreach ($line in @($Assessment['Notices'])) { $facts['Note'] = $(if ($facts.Contains('Note')) { "$($facts['Note']) $line" } else { $line }) }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) { $row = & $pdf.AddBodyRow $factTable; $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted; $row.Cells[1].AddParagraph($facts[$key]) | Out-Null }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = '{0:N0}' -f $stats.Clusters; Label = 'clusters' }
        @{ Value = '{0:N0}' -f $stats.Nodes; Label = 'nodes' }
        @{ Value = $(if ($null -ne $stats.WafScore) { "$($stats.WafScore)%" } else { '-' }); Label = 'WAF checks passed' }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Color = $(if ($stats.High) { $pdf.Tone.Bad.Solid }) }
        @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium findings'; Color = $(if ($stats.Medium) { $pdf.Tone.Warn.Solid }) }
        @{ Value = '{0:N0}' -f $stats.OutOfSupport; Label = 'out of support'; Color = $(if ($stats.OutOfSupport) { $pdf.Tone.Bad.Solid }) }
        @{ Value = $(if ($policy) { '{0:N0}' -f $policy.Stats.Violations } else { '-' }); Label = 'policy violations' }
    )
    $tiles = & $pdf.NewTable @(1..$tileData.Count | ForEach-Object { $pdf.PageWidth / $tileData.Count })
    $tiles.TopPadding = & $pt 8; $tiles.BottomPadding = & $pt 8
    $tileRow = $tiles.AddRow()
    for ($i = 0; $i -lt $tileData.Count; $i++) {
        $cell = $tileRow.Cells[$i]; $cell.Shading.Color = $colors.Panel; $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 }); $cell.Borders.Left.Color = $colors.White
        $value = $cell.AddParagraph([string]$tileData[$i].Value); $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center; $value.Format.Font.Size = 16; $value.Format.Font.Name = 'Segoe UI Semibold'
        if ($tileData[$i].Contains('Color') -and $tileData[$i].Color) { $value.Format.Font.Color = $tileData[$i].Color }
        $caption = $cell.AddParagraph($tileData[$i].Label); $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center; $caption.Format.Font.Size = 8; $caption.Format.Font.Color = $colors.Muted
    }
    $section.AddParagraph('Clusters', 'Heading2') | Out-Null
    & $table $Assessment.Clusters (& $ordered 'Cluster', 'Name', 'Version', 'Version', 'Support', 'Support', 'Tier', 'Tier', 'Nodes', 'Nodes', 'Network', 'Network', 'API server', 'ApiServer', 'WAF %', 'WafScore', 'High', 'High', 'Medium', 'Medium', 'Policy', 'PolicyViolations') @(3, 1.4, 1.8, 1.1, 0.9, 2, 2, 1, 0.8, 0.8, 1)
    $section.AddParagraph('Well-Architected pillars', 'Heading2') | Out-Null
    & $table $Assessment.Pillars (& $ordered 'Pillar', 'Pillar', 'Score %', 'Score', 'Checks', 'Checks', 'Passed', 'Passed', 'Failed', 'Failed', 'PSRule failed', 'PSRuleFailed', 'Findings', 'Findings') @(3, 1, 1, 1, 1, 1, 1)

    # --- 2. Findings ---------------------------------------------------------------------------------------------
    if (@($Assessment.Findings).Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Findings', 'Heading1') | Out-Null
        & $table $Assessment.Findings (& $ordered 'Severity', 'Severity', 'Pillar', 'Pillar', 'Source', 'Source', 'Cluster', 'Cluster', 'Finding', 'Check', 'What was found', 'Detail', 'What to do', 'Recommendation') @(1, 1.4, 1.2, 1.6, 2.6, 4, 3.4)
    }

    # --- 3. Azure Policy ---------------------------------------------------------------------------------------------
    if ($policy -and ($policy.Stats.Violations -or @($policy.ClusterStates).Count)) {
        $section.AddPageBreak()
        $section.AddParagraph('Azure Policy for Kubernetes', 'Heading1') | Out-Null
        if (@($policy.ByNamespace).Count) { $section.AddParagraph('By namespace', 'Heading2') | Out-Null; & $table $policy.ByNamespace (& $ordered 'Namespace', 'Namespace', 'Violations', 'Violations', 'Workloads', 'Workloads', 'Policies', 'Policies', 'Under Deny', 'Deny', 'Clusters', 'Clusters', 'Policies violated', 'PolicyNames') @(2, 1, 1, 1, 1, 2, 5) }
        if (@($policy.ByPolicy).Count) { $section.AddParagraph('By policy', 'Heading2') | Out-Null; & $table $policy.ByPolicy (& $ordered 'Policy', 'Policy', 'Effect', 'Effect', 'Violations', 'Violations', 'Clusters', 'Clusters', 'Namespaces', 'Namespaces', 'Workloads', 'Workloads', 'Assignment', 'Assignment') @(5, 1.4, 1, 1, 1, 1, 2.5) }
        if (@($policy.ByWorkload).Count) { $section.AddParagraph('By workload', 'Heading2') | Out-Null; & $table $policy.ByWorkload (& $ordered 'Cluster', 'Cluster', 'Namespace', 'Namespace', 'Kind', 'WorkloadKind', 'Workload', 'Workload', 'Violations', 'Violations', 'Policies', 'Policies', 'Policies violated', 'PolicyNames') @(1.6, 1.6, 1.2, 2, 1, 1, 5) }
        $nonCompliant = @($policy.ClusterStates | Where-Object State -EQ 'NonCompliant')
        if ($nonCompliant.Count) { $section.AddParagraph('Non-compliant policies on the clusters', 'Heading2') | Out-Null; & $table $nonCompliant (& $ordered 'Cluster', 'Cluster', 'Policy', 'Policy', 'Scope', 'Scope', 'Effect', 'Effect', 'Assignment', 'Assignment') @(2, 5, 1, 1.4, 2.5) }
    }

    # --- 4. Each cluster -------------------------------------------------------------------------------------------
    foreach ($cluster in $Assessment.Clusters) {
        $id = $cluster.ResourceId
        $section.AddPageBreak()
        $section.AddParagraph("$($cluster.Name) (Kubernetes $($cluster.Version), $($cluster.Support))", 'Heading1') | Out-Null
        $muted = $section.AddParagraph($id); $muted.Format.Font.Size = 7; $muted.Format.Font.Color = $colors.Muted
        $section.AddParagraph('Settings', 'Heading2') | Out-Null
        & $table @($Assessment.Settings | Where-Object ClusterId -EQ $id) (& $ordered 'Area', 'Area', 'Setting', 'Setting', 'Value', 'Value') @(2, 3, 6)
        $section.AddParagraph('Node pools', 'Heading2') | Out-Null
        & $table @($Assessment.NodePools | Where-Object ClusterId -EQ $id) (& $ordered 'Pool', 'Pool', 'Mode', 'Mode', 'Size', 'VmSize', 'OS', 'OsSku', 'Nodes', 'Nodes', 'Autoscale', 'Autoscale', 'Max', 'Max', 'Zones', 'Zones', 'Version', 'Version', 'Image age', 'NodeImageAge', 'OS disk', 'OsDiskType', 'Subnet', 'Subnet') @(1.4, 1, 2, 1.2, 0.8, 1, 0.7, 1, 1, 1, 1.1, 2.4)
        $section.AddParagraph('Versions and upgrades', 'Heading2') | Out-Null
        & $table @($Assessment.Upgrades | Where-Object ClusterId -EQ $id) (& $ordered 'Component', 'Component', 'Version', 'Current', 'Support', 'Support', 'Available', 'Available', 'Channel', 'Channel', 'Node image', 'NodeImage', 'Newest image', 'LatestNodeImage') @(2, 1.2, 1.6, 2, 1.4, 3, 3)
        $failed = @($Assessment.Checks | Where-Object { $_.ClusterId -eq $id -and $_.Status -eq 'Fail' })
        if ($failed.Count) { $section.AddParagraph('Failed Well-Architected checks', 'Heading2') | Out-Null; & $table $failed (& $ordered 'Pillar', 'Pillar', 'Check', 'Check', 'Severity', 'Severity', 'What was found', 'Detail', 'What to do', 'Recommendation') @(1.6, 2.6, 1, 4, 4) }
        $rules = @($Assessment.PSRule | Where-Object { $_.ResourceName -eq $cluster.Name -and $_.Outcome -ne 'Pass' })
        if ($rules.Count) { $section.AddParagraph('PSRule for Azure: failed rules', 'Heading2') | Out-Null; & $table $rules (& $ordered 'Rule', 'RuleName', 'Pillar', 'Pillar', 'Severity', 'Severity', 'Title', 'Title', 'Recommendation', 'Recommendation') @(2.6, 1.6, 1.2, 3.4, 4) }
    }
    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
