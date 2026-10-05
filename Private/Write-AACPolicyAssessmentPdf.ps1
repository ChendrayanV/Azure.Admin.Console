function Write-AACPolicyAssessmentPdf {
    <#
    .SYNOPSIS
        Writes Invoke-AACPolicyAssessment's report as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: the scope, tiles, compliance by subscription, management
           group and category.
        2. Findings, most severe first.
        3. Assignments, and compliance by policy (the least compliant).
        4. Exemptions.
        5. Initiatives and definitions.
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
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($stats.Assignments) Azure Policy assignments" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $tone = @{ High = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Poor = $pdf.Tone.Bad.Solid; Warning = $pdf.Tone.Warn.Solid; Good = $pdf.Tone.Good.Solid; Expired = $pdf.Tone.Bad.Solid; Expiring = $pdf.Tone.Warn.Solid; DoNotEnforce = $pdf.Tone.Warn.Solid }
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
    $heading = { param([string] $Text, [string] $Style = 'Heading2') $section.AddParagraph($Text, $Style) | Out-Null }

    # --- 1. Summary ------------------------------------------------------------------------------------------
    & $pdf.AddTitle "Azure Policy assessment · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    foreach ($line in @($Assessment['Notices'])) { $facts['Note'] = $(if ($facts.Contains('Note')) { "$($facts['Note']) $line" } else { $line }) }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) { $row = & $pdf.AddBodyRow $factTable; $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted; $row.Cells[1].AddParagraph($facts[$key]) | Out-Null }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = $(if ($null -ne $stats.CompliancePercent) { "$($stats.CompliancePercent)%" } else { '-' }); Label = 'resources compliant'; Color = $tone[[string]$stats.Rating] }
        @{ Value = '{0:N0}' -f $stats.Assignments; Label = 'assignments' }
        @{ Value = '{0:N0}' -f $stats.NonCompliant; Label = 'non-compliant resources'; Color = $(if ($stats.NonCompliant) { $pdf.Tone.Warn.Solid }) }
        @{ Value = '{0:N0}' -f $stats.NotEnforced; Label = 'not enforced'; Color = $(if ($stats.NotEnforced) { $pdf.Tone.Warn.Solid }) }
        @{ Value = '{0:N0}' -f $stats.ExpiringExemptions; Label = 'exemptions expired or expiring'; Color = $(if ($stats.ExpiringExemptions) { $pdf.Tone.Warn.Solid }) }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Color = $(if ($stats.High) { $pdf.Tone.Bad.Solid }) }
        @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium findings'; Color = $(if ($stats.Medium) { $pdf.Tone.Warn.Solid }) }
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
    $states = 'Compliance %', 'CompliancePercent', 'Rating', 'Rating', 'Non-compliant', 'NonCompliant', 'Compliant', 'Compliant', 'Exempt', 'Exempt'
    if (@($Assessment.Subscriptions).Count) { & $heading 'Compliance by subscription'; & $table $Assessment.Subscriptions (& $ordered (@('Subscription', 'Subscription', 'Management groups', 'ManagementGroups') + $states + @('Assignments', 'Assignments', 'Exemptions', 'Exemptions'))) @(3, 4, 1.2, 1.2, 1.2, 1.2, 1, 1.2, 1.2) }
    if (@($Assessment.ManagementGroups).Count) { & $heading 'Compliance by management group'; & $table $Assessment.ManagementGroups (& $ordered (@('Management group', 'ManagementGroup', 'Parent', 'Parent') + $states + @('Assigned here', 'Assignments', 'Subscriptions', 'Subscriptions'))) @(3, 3, 1.2, 1.2, 1.2, 1.2, 1, 1.2, 1.2) }
    if (@($Assessment.Categories).Count) { & $heading 'Compliance by category'; & $table $Assessment.Categories (& $ordered (@('Category', 'Category', 'Policies', 'Policies', 'Assignments', 'Assignments') + $states)) @(3, 1, 1, 1.2, 1.2, 1.2, 1.2, 1) }

    # --- 2. Findings ---------------------------------------------------------------------------------------------
    if (@($Assessment.Findings).Count) {
        $section.AddPageBreak()
        & $heading 'Findings' 'Heading1'
        & $table $Assessment.Findings (& $ordered 'Severity', 'Severity', 'Area', 'Area', 'Finding', 'Finding', 'Item', 'Item', 'Scope', 'Scope', 'What was found', 'Detail', 'What to do', 'Recommendation') @(1, 1.2, 2.2, 2.4, 1.8, 4, 3.4)
    }

    # --- 3. Assignments and policies ------------------------------------------------------------------------------------
    if (@($Assessment.Assignments).Count) {
        $section.AddPageBreak()
        & $heading 'Assignments' 'Heading1'
        & $table $Assessment.Assignments (& $ordered 'Assignment', 'Assignment', 'Scope', 'Scope', 'Assigns', 'Definition', 'Kind', 'Kind', 'Enforcement', 'Enforcement', 'Compliance %', 'CompliancePercent', 'Rating', 'Rating', 'Non-compliant', 'NonCompliant', 'Exemptions', 'Exemptions', 'Identity', 'Identity') @(3, 2.4, 3.4, 1.1, 1.3, 1.1, 1, 1.1, 1, 1.3)
        $worst = @($Assessment.Policies | Where-Object NonCompliant -GT 0)
        if ($worst.Count) { & $heading 'Policies with non-compliant resources'; & $table $worst (& $ordered 'Policy', 'Policy', 'Assignment', 'Assignment', 'Effect', 'Effect', 'Category', 'Category', 'Compliance %', 'CompliancePercent', 'Non-compliant', 'NonCompliant', 'Resources', 'Resources') @(4.4, 2.6, 1.1, 1.6, 1.1, 1.1, 1) }
    }

    # --- 4. Exemptions -------------------------------------------------------------------------------------------------
    if (@($Assessment.Exemptions).Count) {
        $section.AddPageBreak()
        & $heading 'Exemptions' 'Heading1'
        & $table $Assessment.Exemptions (& $ordered 'Exemption', 'Exemption', 'Status', 'Status', 'Expires', 'ExpiresOn', 'Days left', 'DaysLeft', 'Category', 'Category', 'Assignment', 'Assignment', 'Scope', 'Scope', 'Policies', 'Policies') @(3, 1, 1.1, 0.8, 1, 2.6, 2.6, 2)
    }

    # --- 5. Definitions ------------------------------------------------------------------------------------------------
    if (@($Assessment.Initiatives).Count -or @($Assessment.Definitions).Count) {
        $section.AddPageBreak()
        & $heading 'Initiatives and definitions' 'Heading1'
        if (@($Assessment.Initiatives).Count) { & $heading 'Initiatives'; & $table $Assessment.Initiatives (& $ordered 'Initiative', 'Initiative', 'Type', 'PolicyType', 'Category', 'Category', 'Version', 'Version', 'Policies', 'Policies', 'Assigned', 'Assigned', 'Deprecated', 'Deprecated', 'Defined at', 'DefinedAt') @(4.4, 1, 1.6, 1, 0.9, 0.9, 1, 2.4) }
        if (@($Assessment.Definitions).Count) { & $heading 'Policy definitions'; & $table $Assessment.Definitions (& $ordered 'Definition', 'Definition', 'Type', 'PolicyType', 'Category', 'Category', 'Effect', 'Effect', 'Roles needed', 'RolesNeeded', 'Initiatives', 'Initiatives', 'Assigned', 'Assigned', 'Deprecated', 'Deprecated') @(4.4, 1, 1.6, 1.4, 2, 0.9, 0.9, 1) }
    }
    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
