function Write-AACAdvisorRecommendationPdf {
    <#
    .SYNOPSIS
        Writes AAC.AdvisorRecommendation objects (from
        Get-AACAdvisorRecommendation) as a landscape A4 PDF report.
    .DESCRIPTION
        Layout:
          1. Summary: title, where the recommendations came from, tiles with
             the totals (recommendations, high / medium / low impact,
             resources affected, estimated monthly savings), a category by
             impact table and one row per subscription.
          2. Recommendations by type: every distinct recommendation once,
             with its category, impact, how many resources and subscriptions
             it affects and its estimated savings - the consolidated view.
          3. One part per category (each starting on a new page): each
             recommendation as a heading with its impact (High in red, Medium
             in amber, Low in grey) and solution, then a table of the
             resources it affects, with savings or retirement date.

        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Recommendation,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $categories = @('Cost', 'Security', 'Reliability', 'OperationalExcellence', 'Performance')
    $categoryLabel = @{ Cost = 'Cost'; Security = 'Security'; Reliability = 'Reliability'; OperationalExcellence = 'Operational excellence'; Performance = 'Performance' }
    $impacts = @('High', 'Medium', 'Low')

    $pdf = New-AACPdfDocument -Title $Title -Subject "$($Recommendation.Count) Azure Advisor recommendations" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $impactTone = @{ High = $pdf.Tone.Bad; Medium = $pdf.Tone.Warn; Low = $pdf.Tone.Neutral }
    $toneOf = { param([string] $Impact) $t = $impactTone[$Impact]; if ($t) { $t } else { $pdf.Tone.Neutral } }

    # "USD 1,234.50" per currency present, e.g. "USD 1,234.50 + EUR 20.00".
    # Returns '' when none of the items has a savings estimate.
    $savings = {
        param($Items, [string] $Property = 'MonthlySavings')
        (@($Items | Where-Object { $null -ne $_.$Property }) |
            Group-Object -Property SavingsCurrency |
            Sort-Object -Property Name |
            ForEach-Object { ('{0} {1:N2}' -f $(if ($_.Name) { $_.Name } else { '?' }), ($_.Group | Measure-Object -Property $Property -Sum).Sum).Trim() }) -join ' + '
    }
    $distinctResources = { param($Items) @($Items | ForEach-Object { if ($_.ResourceId) { $_.ResourceId.ToLowerInvariant() } else { $_.ResourceName } } | Select-Object -Unique).Count }
    $subscriptionLabel = { param($Item) if ($Item.SubscriptionName) { $Item.SubscriptionName } else { $Item.SubscriptionId } }
    $addNumber = {
        param($Cell, $Value)
        $number = $Cell.AddParagraph(('{0:N0}' -f $Value))
        $number.Format.Alignment = $right
        if ($Value -eq 0) { $number.Format.Font.Color = $colors.Muted }
    }
    # A paragraph with the text, or a grey '-' when there is none.
    $addText = {
        param($Cell, [string] $Text)
        $paragraph = $Cell.AddParagraph($(if ($Text) { $Text } else { '-' }))
        if (-not $Text) { $paragraph.Format.Font.Color = $colors.Muted }
        $paragraph
    }
    $addImpactBadge = {
        param($Paragraph, [string] $Impact)
        $badge = $Paragraph.AddFormattedText(" $($Impact.ToUpperInvariant()) ")
        $badge.Size = 7.5
        $badge.Bold = $true
        $badge.Color = (& $toneOf $Impact).Text
        $badge.Font.Name = 'Segoe UI'
    }

    # --- 1. Summary ---------------------------------------------------------------
    $subscriptionCount = @($Recommendation | Select-Object -ExpandProperty SubscriptionId -Unique).Count
    $resourceCount = & $distinctResources $Recommendation
    & $pdf.AddTitle "$('{0:N0}' -f $Recommendation.Count) recommendations for $('{0:N0}' -f $resourceCount) resources in $subscriptionCount subscription$(if ($subscriptionCount -ne 1) { 's' }) · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"

    $facts = [ordered]@{}
    $session = $script:AACSession
    if ($session) {
        $facts['Azure account'] = [string]$session.Account
        $facts['Tenant'] = [string]$session.TenantId
    }
    if ($Detail) {
        foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] }
    }
    $monthly = & $savings $Recommendation 'MonthlySavings'
    $annual = & $savings $Recommendation 'AnnualSavings'
    if ($monthly -or $annual) {
        $facts['Estimated savings'] = "$(if ($monthly) { "$monthly per month" })$(if ($monthly -and $annual) { ' · ' })$(if ($annual) { "$annual per year" }). Advisor's own estimates; recommendations can overlap (e.g. a reservation and a right-size for the same VM), so totals are an upper bound."
    }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }

    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $firstCurrency = @($Recommendation | Where-Object { $null -ne $_.MonthlySavings } | Group-Object SavingsCurrency | Sort-Object Count -Descending | Select-Object -First 1)
    $tileData = @(
        @{ Value = ('{0:N0}' -f $Recommendation.Count); Label = 'recommendations' }
        @{ Value = ('{0:N0}' -f @($Recommendation | Where-Object Impact -eq 'High').Count); Label = 'high impact'; Tone = $pdf.Tone.Bad }
        @{ Value = ('{0:N0}' -f @($Recommendation | Where-Object Impact -eq 'Medium').Count); Label = 'medium impact'; Tone = $pdf.Tone.Warn }
        @{ Value = ('{0:N0}' -f @($Recommendation | Where-Object Impact -eq 'Low').Count); Label = 'low impact' }
        @{ Value = ('{0:N0}' -f $resourceCount); Label = 'resources affected' }
        @{
            Value = if ($firstCurrency) { '{0:N0}' -f ($firstCurrency[0].Group | Measure-Object -Property MonthlySavings -Sum).Sum } else { '-' }
            Label = if ($firstCurrency) { "$($firstCurrency[0].Name) / month est. savings".Trim() } else { 'no savings estimates' }
            Tone  = $pdf.Tone.Good
        }
    )
    $tileWidth = $pdf.PageWidth / $tileData.Count
    $tiles = & $pdf.NewTable @(1..$tileData.Count | ForEach-Object { $tileWidth })
    $tiles.TopPadding = & $pt 8
    $tiles.BottomPadding = & $pt 8
    $tileRow = $tiles.AddRow()
    for ($i = 0; $i -lt $tileData.Count; $i++) {
        $cell = $tileRow.Cells[$i]
        $cell.Shading.Color = $colors.Panel
        $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
        $cell.Borders.Left.Color = $colors.White
        $number = $cell.AddParagraph($tileData[$i].Value)
        $number.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $number.Format.Font.Size = 18
        $number.Format.Font.Name = 'Segoe UI Semibold'
        if ($tileData[$i]['Tone'] -and $tileData[$i].Value -notin '0', '-') { $number.Format.Font.Color = $tileData[$i]['Tone'].Text }
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }

    if ($Recommendation.Count -eq 0) {
        $none = $section.AddParagraph('No Azure Advisor recommendations were found.')
        $none.Format.Font.Color = $colors.Muted
        $none.Format.SpaceBefore = & $pt 12
        return Save-AACPdfDocument -Pdf $pdf -Path $Path
    }

    $section.AddParagraph('By category', 'Heading2') | Out-Null
    $categoryTable = & $pdf.NewTable @(6.1, 2.4, 2.4, 2.4, 2.4, 3.2, 7.2)
    & $pdf.AddHeaderRow $categoryTable @('Category', 'High', 'Medium', 'Low', 'Total', 'Resources', 'Estimated savings / month') @(1, 2, 3, 4, 5, 6)
    foreach ($categoryName in $categories) {
        $items = @($Recommendation | Where-Object Category -eq $categoryName)
        $row = & $pdf.AddBodyRow $categoryTable
        $row.Cells[0].AddParagraph($categoryLabel[$categoryName]).Format.Font.Name = 'Segoe UI Semibold'
        foreach ($i in 0..2) { & $addNumber $row.Cells[$i + 1] @($items | Where-Object Impact -eq $impacts[$i]).Count }
        & $addNumber $row.Cells[4] $items.Count
        & $addNumber $row.Cells[5] (& $distinctResources $items)
        $saving = & $savings $items
        (& $addText $row.Cells[6] $saving).Format.Alignment = $right
    }

    $section.AddParagraph('By subscription', 'Heading2') | Out-Null
    $subscriptionTable = & $pdf.NewTable @(6.4, 2.0, 2.0, 2.1, 2.5, 2.4, 1.6, 1.7, 5.4)
    & $pdf.AddHeaderRow $subscriptionTable @('Subscription', 'Cost', 'Security', 'Reliability', 'Op. excellence', 'Performance', 'High', 'Total', 'Est. savings / month') @(1, 2, 3, 4, 5, 6, 7, 8)
    foreach ($subscription in @($Recommendation | Group-Object -Property SubscriptionId | Sort-Object { & $subscriptionLabel $_.Group[0] })) {
        $row = & $pdf.AddBodyRow $subscriptionTable
        $name = $row.Cells[0].AddParagraph((& $subscriptionLabel $subscription.Group[0]))
        $name.Format.Font.Name = 'Segoe UI Semibold'
        for ($i = 0; $i -lt $categories.Count; $i++) {
            & $addNumber $row.Cells[$i + 1] @($subscription.Group | Where-Object Category -eq $categories[$i]).Count
        }
        & $addNumber $row.Cells[6] @($subscription.Group | Where-Object Impact -eq 'High').Count
        & $addNumber $row.Cells[7] $subscription.Count
        $saving = & $savings $subscription.Group
        (& $addText $row.Cells[8] $saving).Format.Alignment = $right
    }

    # One group per distinct recommendation (same type, impact and wording),
    # in category then impact order - the objects arrive sorted that way.
    $typeKey = { "$($_.Category)|$($_.Impact)|$(if ($_.RecommendationTypeId) { $_.RecommendationTypeId } else { $_.Problem })|$($_.Problem)" }
    $types = @($Recommendation | Group-Object -Property $typeKey | Sort-Object -Property @(
            @{ Expression = { $categories.IndexOf($_.Group[0].Category) } }
            @{ Expression = { $impacts.IndexOf($_.Group[0].Impact) } }
            @{ Expression = { $_.Count }; Descending = $true }
            @{ Expression = { $_.Group[0].Problem } }
        ))

    # --- 2. Recommendations by type -----------------------------------------------------
    $section.AddPageBreak()
    $section.AddParagraph('Recommendations by type', 'Heading1') | Out-Null
    $intro = $section.AddParagraph("$($types.Count) distinct recommendation$(if ($types.Count -ne 1) { 's' }), each listed once with the number of resources it applies to. Resource-level detail follows, category by category.")
    $intro.Format.Font.Color = $colors.Muted
    $intro.Format.SpaceAfter = & $pt 6
    $typeTable = & $pdf.NewTable @(11.4, 4.1, 1.9, 2.0, 2.2, 4.5)
    & $pdf.AddHeaderRow $typeTable @('Recommendation', 'Category', 'Impact', 'Resources', 'Subscriptions', 'Est. savings / month') @(3, 4, 5)
    foreach ($type in $types) {
        $first = $type.Group[0]
        $row = & $pdf.AddBodyRow $typeTable
        $row.Cells[0].Borders.Left.Width = 2.5
        $row.Cells[0].Borders.Left.Color = (& $toneOf $first.Impact).Solid
        $row.Cells[0].AddParagraph($(if ($first.Problem) { $first.Problem } else { '(no description)' })) | Out-Null
        $row.Cells[1].AddParagraph($categoryLabel[$first.Category] ?? $first.Category) | Out-Null
        & $addImpactBadge $row.Cells[2].AddParagraph() $first.Impact
        & $addNumber $row.Cells[3] (& $distinctResources $type.Group)
        & $addNumber $row.Cells[4] @($type.Group | Select-Object -ExpandProperty SubscriptionId -Unique).Count
        $saving = & $savings $type.Group
        (& $addText $row.Cells[5] $saving).Format.Alignment = $right
    }

    # --- 3. Every affected resource, category by category ------------------------------
    foreach ($categoryName in $categories) {
        $categoryTypes = @($types | Where-Object { $_.Group[0].Category -eq $categoryName })
        if ($categoryTypes.Count -eq 0) { continue }
        $items = @($categoryTypes | ForEach-Object { $_.Group })

        $section.AddPageBreak()
        $section.AddParagraph($categoryLabel[$categoryName], 'Heading1') | Out-Null
        $about = $section.AddParagraph(@(
                "$($items.Count) recommendation(s) for $(& $distinctResources $items) resource(s)"
                "$(@($items | Where-Object Impact -eq 'High').Count) high · $(@($items | Where-Object Impact -eq 'Medium').Count) medium · $(@($items | Where-Object Impact -eq 'Low').Count) low impact"
                $(if (($saving = & $savings $items)) { "est. $saving per month" })
            ) -join '  ·  ')
        $about.Format.Font.Color = $colors.Muted
        $about.Format.SpaceAfter = & $pt 4

        foreach ($type in $categoryTypes) {
            $first = $type.Group[0]
            $heading = $section.AddParagraph('', 'Heading3')
            $heading.AddText($(if ($first.Problem) { $first.Problem } else { '(no description)' })) | Out-Null
            $heading.AddText('   ') | Out-Null
            & $addImpactBadge $heading $first.Impact
            if ($first.Solution -and $first.Solution -ne $first.Problem) {
                $solution = $section.AddParagraph($first.Solution)
                $solution.Format.Font.Color = $colors.Muted
                $solution.Format.SpaceAfter = & $pt 3
                $solution.Format.KeepWithNext = $true
            }

            $table = & $pdf.NewTable @(6.4, 5.4, 7.0, 4.6, 2.7)
            & $pdf.AddHeaderRow $table @('Resource', 'Type', 'Subscription · resource group', 'Savings / retirement', 'Updated')
            foreach ($item in $type.Group) {
                $row = & $pdf.AddBodyRow $table
                # A coloured bar on the left edge carries the impact.
                $row.Cells[0].Borders.Left.Width = 2.5
                $row.Cells[0].Borders.Left.Color = (& $toneOf $item.Impact).Solid
                $name = & $addText $row.Cells[0] $item.ResourceName
                $name.Format.Font.Name = 'Segoe UI Semibold'
                if ($item.Status -ne 'Active') {
                    $status = $row.Cells[0].AddParagraph("$($item.Status)$(if ($item.SuppressionExpires) { " until $($item.SuppressionExpires.ToString('d MMM yyyy'))" })")
                    $status.Format.Font.Size = 7
                    $status.Format.Font.Color = $colors.Amber
                }
                (& $addText $row.Cells[1] $item.ResourceType).Format.Font.Size = 8
                $row.Cells[2].AddParagraph("$(& $subscriptionLabel $item)$(if ($item.ResourceGroup) { " · $($item.ResourceGroup)" })") | Out-Null

                $notes = [System.Collections.Generic.List[string]]::new()
                if ($null -ne $item.MonthlySavings) { $notes.Add(('{0} {1:N2} / month' -f $item.SavingsCurrency, $item.MonthlySavings).Trim()) }
                elseif ($null -ne $item.AnnualSavings) { $notes.Add(('{0} {1:N2} / year' -f $item.SavingsCurrency, $item.AnnualSavings).Trim()) }
                if ($item.RetirementDate) { $notes.Add("Retires $($item.RetirementDate.ToString('d MMM yyyy'))") }
                if ($item.RetiringFeature) { $notes.Add($item.RetiringFeature) }
                & $addText $row.Cells[3] ($notes -join ' · ') | Out-Null
                & $addText $row.Cells[4] $(if ($item.LastUpdated) { $item.LastUpdated.ToString('d MMM yyyy') }) | Out-Null
            }
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
