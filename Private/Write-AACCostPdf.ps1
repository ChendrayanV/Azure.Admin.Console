function Write-AACCostPdf {
    <#
    .SYNOPSIS
        Writes Show-AACCost's results as a landscape A4 PDF report.
    .DESCRIPTION
        Layout:
          1. Summary: title, account, tenant and period, then per billing
             currency: tiles (month to date, last month, period total,
             subscriptions), the subscription-by-month table with a total
             column and row, and this month's top services and resource
             groups with their share.
          2. One page per subscription with cost: its services and its
             resource groups month by month (the top 15 of each, the rest
             summed), with totals.
          3. Subscriptions that couldn't be read, with the reason.

        -Cost is Show-AACCost's AAC.SubscriptionCost objects, -Detail its
        per-month, per-service, per-resource-group rows, -MonthStart the
        first day of each month covered. -Path must be a full path; see
        Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Cost,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Detail,

        [Parameter(Mandatory)]
        [datetime[]] $MonthStart,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [string] $Period
    )

    $invariant = [cultureinfo]::InvariantCulture
    $monthKeys = @($MonthStart | ForEach-Object { $_.ToString('yyyy-MM', $invariant) })
    $thisMonthKey = $monthKeys[-1]
    $sum = { param($Items, [string] $Property) $t = 0.0; foreach ($i in @($Items)) { $v = $i.$Property; if ($null -ne $v) { $t += [double]$v } }; $t }
    $money = { param([double] $Value) '{0:N2}' -f $Value }

    $pdf = New-AACPdfDocument -Title $Title -Subject "Azure cost for $($Cost.Count) subscription(s)" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right

    # A right-aligned amount; zero in grey, optionally bold.
    $addAmount = {
        param($Cell, [double] $Value, [switch] $Bold)
        $paragraph = $Cell.AddParagraph((& $money $Value))
        $paragraph.Format.Alignment = $right
        if ($Value -eq 0) { $paragraph.Format.Font.Color = $colors.Muted }
        if ($Bold) { $paragraph.Format.Font.Name = 'Segoe UI Semibold' }
    }
    # A table of rows (Name + one value per month) with a total column; the
    # widths share the page between the name and the months.
    $addMonthTable = {
        param([object[]] $Rows, [string] $NameHeader, [switch] $TotalRow)
        $nameWidth = 6.0
        $valueWidth = ($pdf.PageWidth - $nameWidth) / ($MonthStart.Count + 1)
        $table = & $pdf.NewTable (@($nameWidth) + @(1..($MonthStart.Count + 1) | ForEach-Object { $valueWidth }))
        $headersList = @($NameHeader) + @($MonthStart | ForEach-Object { "$($_.ToString('MMM yyyy'))$(if ($_.ToString('yyyy-MM', $invariant) -eq $thisMonthKey) { ' *' })" }) + 'Total'
        & $pdf.AddHeaderRow $table $headersList @(1..($MonthStart.Count + 1))
        foreach ($item in $Rows) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph([string]$item.Name) | Out-Null
            for ($i = 0; $i -lt $monthKeys.Count; $i++) { & $addAmount $row.Cells[$i + 1] ([double]$item.($monthKeys[$i])) }
            & $addAmount $row.Cells[$monthKeys.Count + 1] ([double]$item.Total) -Bold
        }
        if ($TotalRow -and $Rows.Count -gt 1) {
            $row = & $pdf.AddBodyRow $table
            $row.Shading.Color = $colors.Panel
            $row.Cells[0].AddParagraph('Total').Format.Font.Name = 'Segoe UI Semibold'
            for ($i = 0; $i -lt $monthKeys.Count; $i++) { & $addAmount $row.Cells[$i + 1] (& $sum $Rows $monthKeys[$i]) -Bold }
            & $addAmount $row.Cells[$monthKeys.Count + 1] (& $sum $Rows 'Total') -Bold
        }
    }
    # Detail rows grouped by one field into Name + a value per month + Total,
    # largest total first; beyond -Top the rest are summed into one row.
    $pivot = {
        param([object[]] $Rows, [string] $Field, [int] $Top, [string] $Empty)
        $pivoted = @($Rows | Group-Object -Property $Field | ForEach-Object {
                $entry = [ordered]@{ Name = $(if ($_.Name) { $_.Name } else { $Empty }) }
                foreach ($key in $monthKeys) { $entry[$key] = & $sum @($_.Group | Where-Object Month -eq $key) 'Cost' }
                $entry['Total'] = & $sum $_.Group 'Cost'
                [pscustomobject]$entry
            } | Where-Object Total -ne 0 | Sort-Object Total -Descending)
        if ($pivoted.Count -gt $Top) {
            $rest = @($pivoted | Select-Object -Skip $Top)
            $entry = [ordered]@{ Name = "$($rest.Count) other(s)" }
            foreach ($key in $monthKeys) { $entry[$key] = & $sum $rest $key }
            $entry['Total'] = & $sum $rest 'Total'
            $pivoted = @($pivoted | Select-Object -First $Top) + [pscustomobject]$entry
        }
        $pivoted
    }
    # This month's top 10 services and resource groups, with their share,
    # side by side in one table (MigraDoc can't nest tables).
    $addShareTables = {
        param([object[]] $Rows)
        $top = {
            param([string] $Field, [string] $Empty)
            @($Rows | Where-Object Month -eq $thisMonthKey | Group-Object -Property $Field | ForEach-Object {
                    [pscustomobject]@{ Name = $(if ($_.Name) { $_.Name } else { $Empty }); Cost = (& $sum $_.Group 'Cost') }
                } | Where-Object Cost -gt 0 | Sort-Object Cost -Descending | Select-Object -First 10)
        }
        $sides = @((& $top 'Service' '(no service)'), (& $top 'ResourceGroup' '(no resource group)'))
        $count = [Math]::Max($sides[0].Count, $sides[1].Count)
        if ($count -eq 0) { return }
        $table = & $pdf.NewTable @(7.4, 2.6, 1.6, 1.0, 7.4, 2.6, 1.6)
        & $pdf.AddHeaderRow $table @('Service', 'Month to date', 'Share', '', 'Resource group', 'Month to date', 'Share') @(1, 2, 5, 6)
        $table.Rows[0].Cells[3].Shading.Color = $colors.White
        for ($i = 0; $i -lt $count; $i++) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[3].Borders.Bottom.Width = 0
            for ($side = 0; $side -lt 2; $side++) {
                $items = $sides[$side]
                if ($i -ge $items.Count) { continue }
                $offset = $side * 4
                $total = & $sum $items 'Cost'
                $row.Cells[$offset].AddParagraph($items[$i].Name) | Out-Null
                & $addAmount $row.Cells[$offset + 1] $items[$i].Cost
                $share = $row.Cells[$offset + 2].AddParagraph(('{0:N0}%' -f (100 * $items[$i].Cost / [Math]::Max($total, 0.000001))))
                $share.Format.Alignment = $right
                $share.Format.Font.Color = $colors.Muted
            }
        }
    }

    # --- 1. Summary ------------------------------------------------------------------------------
    & $pdf.AddTitle "$($Cost.Count) subscription(s) · actual cost$(if ($Period) { " · $Period" }) · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) {
        $facts['Azure account'] = [string]$script:AACSession.Account
        $facts['Tenant'] = [string]$script:AACSession.TenantId
    }
    if ($Period) { $facts['Period'] = "$Period (the last month is to date)" }
    $facts['Amounts'] = 'Actual cost as Azure Cost Management reports it, in each subscription''s billing currency - never converted. It can lag usage by a day or so.'
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }

    $read = @($Cost | Where-Object Status -eq 'OK')
    foreach ($currencyGroup in @($read | Group-Object Currency | Sort-Object Count -Descending)) {
        $currency = $currencyGroup.Name
        $group = @($currencyGroup.Group)
        $ids = @($group | ForEach-Object { $_.SubscriptionId })
        $rows = @($Detail | Where-Object { $_.SubscriptionId -in $ids })

        $section.AddParagraph("Summary ($(if ($currency) { $currency } else { 'no currency' }))", 'Heading2') | Out-Null
        $tileData = @(
            @{ Value = (& $money (& $sum $group 'MonthToDate')); Label = "month to date ($currency)" }
            @{ Value = $(if ($monthKeys.Count -gt 1) { & $money (& $sum $group $monthKeys[-2]) } else { '-' }); Label = "last month ($currency)" }
            @{ Value = (& $money (& $sum $group 'Total')); Label = "last $($monthKeys.Count) month(s) ($currency)" }
            @{ Value = ('{0:N0}' -f $group.Count); Label = 'subscriptions' }
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
            $number.Format.Font.Size = 16
            $number.Format.Font.Name = 'Segoe UI Semibold'
            $caption = $cell.AddParagraph($tileData[$i].Label)
            $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
            $caption.Format.Font.Size = 8
            $caption.Format.Font.Color = $colors.Muted
        }

        $section.AddParagraph("By subscription and month ($currency)", 'Heading3') | Out-Null
        $subscriptionRows = @($group | Sort-Object Total -Descending | ForEach-Object {
                $entry = [ordered]@{ Name = $_.SubscriptionName }
                foreach ($key in $monthKeys) { $entry[$key] = $_.$key }
                $entry['Total'] = $_.Total
                [pscustomobject]$entry
            })
        & $addMonthTable $subscriptionRows 'Subscription' -TotalRow
        $note = $section.AddParagraph('* month to date')
        $note.Format.Font.Size = 7.5
        $note.Format.Font.Color = $colors.Muted

        $section.AddParagraph("Top services and resource groups this month ($currency)", 'Heading3') | Out-Null
        & $addShareTables $rows
    }
    if ($read.Count -eq 0) {
        $none = $section.AddParagraph('No costs could be read for these subscriptions.')
        $none.Format.Font.Color = $colors.Muted
    }

    # --- 2. A page per subscription ------------------------------------------------------------------
    foreach ($item in @($read | Where-Object Total -ne 0 | Sort-Object Total -Descending)) {
        $rows = @($Detail | Where-Object SubscriptionId -eq $item.SubscriptionId)
        $section.AddPageBreak()
        $section.AddParagraph($item.SubscriptionName, 'Heading1') | Out-Null
        $about = $section.AddParagraph("$($item.SubscriptionId) · $($item.Currency) · month to date $(& $money $item.MonthToDate) · last $($monthKeys.Count) month(s) $(& $money $item.Total)")
        $about.Format.Font.Color = $colors.Muted
        $about.Format.SpaceAfter = & $pt 4

        $section.AddParagraph('By service', 'Heading3') | Out-Null
        & $addMonthTable (& $pivot $rows 'Service' 15 '(no service)') 'Service' -TotalRow
        $section.AddParagraph('By resource group', 'Heading3') | Out-Null
        & $addMonthTable (& $pivot $rows 'ResourceGroup' 15 '(no resource group)') 'Resource group' -TotalRow
    }

    # --- 3. What couldn't be read ---------------------------------------------------------------------
    $failed = @($Cost | Where-Object Status -ne 'OK')
    if ($failed) {
        $section.AddParagraph('Subscriptions that could not be read', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(7.0, ($pdf.PageWidth - 7.0))
        & $pdf.AddHeaderRow $table @('Subscription', 'Reason')
        foreach ($item in $failed) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.SubscriptionName) | Out-Null
            $row.Cells[1].AddParagraph([string]$item.Status).Format.Font.Color = $colors.Muted
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
