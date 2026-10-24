function Write-AACPolicyStatePdf {
    <#
    .SYNOPSIS
        Writes Get-AACPolicyState's result as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: title, scope, tiles, notices.
        2. Compliance by subscription and by resource group.
        3. Assignments: scope, enforcement, compliance.
        4. Non-compliant resources by policy - each policy, then its
           resources - up to -MaxRows; the CSV and HTML report have every
           state.
        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Compliance,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [int] $MaxRows = 5000
    )

    $stats = $Compliance.Stats
    $pdf = New-AACPdfDocument -Title $Title -Subject "Azure Policy: $($stats.States) states" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $rateColor = { param($Rate) if ($null -eq $Rate) { $colors.Muted } elseif ($Rate -ge 90) { $pdf.Tone.Good.Solid } elseif ($Rate -ge 70) { $pdf.Tone.Warn.Solid } else { $pdf.Tone.Bad.Solid } }
    $number = { param($Cell, $Value, $Color) $p = $Cell.AddParagraph(('{0:N0}' -f [double]$Value)); $p.Format.Alignment = $right; if ([double]$Value -eq 0) { $p.Format.Font.Color = $colors.Muted } elseif ($Color) { $p.Format.Font.Color = $Color; $p.Format.Font.Name = 'Segoe UI Semibold' } }
    $rate = { param($Cell, $Value) $p = $Cell.AddParagraph($(if ($null -ne $Value) { "$Value%" } else { '-' })); $p.Format.Alignment = $right; $p.Format.Font.Name = 'Segoe UI Semibold'; $p.Format.Font.Color = & $rateColor $Value }

    # --- 1. Summary -----------------------------------------------------------------------------
    & $pdf.AddTitle "Azure Policy compliance · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = $(if ($null -ne $stats.ComplianceRate) { "$($stats.ComplianceRate)%" } else { '-' }); Label = ('resource compliance ({0:N0} of {1:N0})' -f $stats.CompliantCounted, $stats.Resources); Color = (& $rateColor $stats.ComplianceRate) }
        @{ Value = '{0:N0}' -f $stats.NonCompliant; Label = 'non-compliant resources'; Color = $(if ($stats.NonCompliant) { $pdf.Tone.Bad.Solid }) }
        @{ Value = '{0:N0}' -f $stats.Compliant; Label = 'compliant resources' }
        @{ Value = '{0:N0}' -f $stats.Exempt; Label = 'exempt' }
        @{ Value = '{0:N0}' -f $stats.Assignments; Label = 'assignments' }
        @{ Value = '{0:N0} / {1:N0}' -f $stats.NonCompliantInitiatives, $stats.Initiatives; Label = 'non-compliant initiatives' }
        @{ Value = '{0:N0} / {1:N0}' -f $stats.NonCompliantPolicies, $stats.Policies; Label = 'non-compliant policies' }
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
        $value = $cell.AddParagraph([string]$tileData[$i].Value)
        if ($tileData[$i].Contains('Color') -and $tileData[$i].Color) { $value.Format.Font.Color = $tileData[$i].Color }
        $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $value.Format.Font.Size = 18
        $value.Format.Font.Name = 'Segoe UI Semibold'
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }
    foreach ($text in @(@($Compliance.Notice | Where-Object { $_ }) + 'Compliance: (compliant + exempt + unknown + protected resources) / every resource evaluated, as the Azure portal counts it.')) {
        $p = $section.AddParagraph($text); $p.Format.Font.Size = 8; $p.Format.Font.Color = $colors.Muted; $p.Format.SpaceBefore = & $pt 4
    }

    # --- 2. By scope ------------------------------------------------------------------------------
    foreach ($level in 'Subscription', 'ResourceGroup') {
        $rows = @($Compliance.Scopes | Where-Object Level -EQ $level)
        if (-not $rows.Count) { continue }
        $section.AddParagraph($(if ($level -eq 'Subscription') { 'Compliance by subscription' } else { 'Compliance by resource group' }), 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(8.0, 6.0, 2.8, 2.8, 2.4, 2.0, 2.4)
        & $pdf.AddHeaderRow $table @($(if ($level -eq 'Subscription') { 'Subscription' } else { 'Resource group' }), $(if ($level -eq 'Subscription') { '' } else { 'Subscription' }), 'Compliance', 'Non-compliant', 'Compliant', 'Exempt', 'Resources') @(2, 3, 4, 5, 6)
        foreach ($item in $rows) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Name).Format.Font.Name = 'Segoe UI Semibold'
            if ($level -eq 'ResourceGroup') { $row.Cells[1].AddParagraph($item.SubscriptionName) | Out-Null }
            & $rate $row.Cells[2] $item.ComplianceRate
            & $number $row.Cells[3] $item.NonCompliant $pdf.Tone.Bad.Solid
            & $number $row.Cells[4] $item.Compliant
            & $number $row.Cells[5] $item.Exempt
            & $number $row.Cells[6] $item.Resources
        }
    }

    # --- 3. Assignments ------------------------------------------------------------------------------
    if ($Compliance.Assignments.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Assignments', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(8.0, 7.4, 2.6, 2.6, 2.6, 2.4)
        & $pdf.AddHeaderRow $table @('Assignment', 'Assigned at', 'Compliance', 'Non-compliant', 'Compliant', 'Policies failing') @(2, 3, 4, 5)
        foreach ($item in $Compliance.Assignments) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Assignment).Format.Font.Name = 'Segoe UI Semibold'
            if ($item.Enforcement -eq 'DoNotEnforce') { $n = $row.Cells[0].AddParagraph('not enforced'); $n.Format.Font.Size = 7; $n.Format.Font.Color = $colors.Amber }
            $row.Cells[1].AddParagraph($item.Scope).Format.Font.Color = $colors.Muted
            & $rate $row.Cells[2] $item.ComplianceRate
            & $number $row.Cells[3] $item.NonCompliant $pdf.Tone.Bad.Solid
            & $number $row.Cells[4] $item.Compliant
            & $number $row.Cells[5] $item.NonCompliantPolicies $pdf.Tone.Warn.Solid
        }
    }

    # --- 4. Non-compliant resources by policy ---------------------------------------------------------------
    $bad = @($Compliance.States | Where-Object ComplianceState -EQ 'NonCompliant' | Group-Object -Property Policy | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
    if ($bad.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Non-compliant resources by policy', 'Heading2') | Out-Null
        $shown = 0
        foreach ($policy in $bad) {
            if ($shown -ge $MaxRows) { break }
            $first = $policy.Group[0]
            $section.AddParagraph("$($policy.Name) ($($policy.Count))", 'Heading3') | Out-Null
            $context = @($(if ($first.PolicySet) { "Initiative: $($first.PolicySet)" }), "Assignment: $($first.Assignment)", $(if ($first.Effect) { "Effect: $($first.Effect)" })) | Where-Object { $_ }
            $p = $section.AddParagraph($context -join ' · '); $p.Format.Font.Size = 8; $p.Format.Font.Color = $colors.Muted; $p.Format.SpaceAfter = & $pt 3
            $table = & $pdf.NewTable @(7.0, 6.0, 5.0, 5.2, 2.8)
            & $pdf.AddHeaderRow $table @('Resource', 'Type', 'Resource group', 'Subscription', 'Evaluated')
            foreach ($item in @($policy.Group | Select-Object -First ($MaxRows - $shown))) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($item.Resource) | Out-Null
                $row.Cells[1].AddParagraph($item.ResourceType).Format.Font.Size = 7
                $row.Cells[2].AddParagraph($item.ResourceGroup) | Out-Null
                $row.Cells[3].AddParagraph($item.SubscriptionName) | Out-Null
                $row.Cells[4].AddParagraph($(if ($item.EvaluatedAt) { $item.EvaluatedAt.ToLocalTime().ToString('d MMM yyyy') } else { '' })).Format.Font.Color = $colors.Muted
                $shown++
            }
        }
        if ($shown -lt @($Compliance.States | Where-Object ComplianceState -EQ 'NonCompliant').Count) {
            $p = $section.AddParagraph("The first $shown non-compliant states are listed; the CSV and HTML report have them all."); $p.Format.Font.Color = $colors.Muted
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
