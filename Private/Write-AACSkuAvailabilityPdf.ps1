function Write-AACSkuAvailabilityPdf {
    <#
    .SYNOPSIS
        Writes Get-AACSkuAvailability's result as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: title, scope, tiles, notices, the zones.
        2. vCPU quota and the AKS cluster's node pools.
        3. VM sizes, usable first, up to -MaxRows; the CSV and HTML report
           have them all.
        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Availability,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [int] $MaxRows = 3000
    )

    $stats = $Availability.Stats
    $pdf = New-AACPdfDocument -Title $Title -Subject "VM size availability: $($stats.Sizes) sizes" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $statusColor = @{ Available = $pdf.Tone.Good.Solid; Partial = $pdf.Tone.Warn.Solid; NoQuota = $pdf.Tone.Warn.Solid; ZoneUnavailable = $pdf.Tone.Bad.Solid; NotSupported = $pdf.Tone.Bad.Solid; Restricted = $pdf.Tone.Bad.Solid; NotChecked = $colors.Muted }
    $number = { param($Cell, $Value) $p = $Cell.AddParagraph($(if ($null -eq $Value) { '-' } else { '{0:N0}' -f [double]$Value })); $p.Format.Alignment = $right; if ($null -eq $Value) { $p.Format.Font.Color = $colors.Muted } }
    $status = { param($Cell, [string] $Name) $p = $Cell.AddParagraph($Name); $p.Format.Font.Name = 'Segoe UI Semibold'; $p.Format.Font.Color = $statusColor[$Name] }

    # --- 1. Summary -----------------------------------------------------------------------------
    & $pdf.AddTitle "VM size availability · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    foreach ($group in @($Availability.Zones | Group-Object -Property SubscriptionName, Location)) {
        $facts["Zones: $($group.Group[0].Location), $($group.Group[0].SubscriptionName)"] = (@($group.Group | Sort-Object LogicalZone | ForEach-Object { "$($_.LogicalZone) = $($_.PhysicalZone)" }) -join ', ')
    }
    $factTable = & $pdf.NewTable @(6.0, ($pdf.PageWidth - 6.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = '{0:N0}' -f $stats.Sizes; Label = 'sizes checked' }
        @{ Value = '{0:N0}' -f $stats.Available; Label = 'available'; Color = $(if ($stats.Available) { $pdf.Tone.Good.Solid }) }
        @{ Value = '{0:N0}' -f $stats.Partial; Label = 'in some zones only'; Color = $(if ($stats.Partial) { $pdf.Tone.Warn.Solid }) }
        @{ Value = '{0:N0}' -f $stats.NoQuota; Label = 'short of quota'; Color = $(if ($stats.NoQuota) { $pdf.Tone.Warn.Solid }) }
        @{ Value = '{0:N0}' -f ($stats.ZoneUnavailable + $stats.NotSupported); Label = 'not in the zones / not for AKS'; Color = $(if ($stats.ZoneUnavailable + $stats.NotSupported) { $pdf.Tone.Bad.Solid }) }
        @{ Value = '{0:N0}' -f $stats.Restricted; Label = 'restricted'; Color = $(if ($stats.Restricted) { $pdf.Tone.Bad.Solid }) }
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
    foreach ($text in @(@($Availability.Notice | Where-Object { $_ }) + 'Read-only: Microsoft.Compute SKUs (offered zones and the subscription''s restrictions), vCPU usage and the zone mapping. Capacity at deployment time can''t be checked without deploying.')) {
        $p = $section.AddParagraph($text); $p.Format.Font.Size = 8; $p.Format.Font.Color = $colors.Muted; $p.Format.SpaceBefore = & $pt 4
    }

    # --- 2. Quota and node pools ----------------------------------------------------------------------
    if (@($Availability.Quotas).Count) {
        $section.AddParagraph('vCPU quota', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(9.0, 3.0, 3.0, 3.0, 2.4, 3.6, 3.6)
        & $pdf.AddHeaderRow $table @('Quota', 'Used', 'Limit', 'Free', 'Used %', 'Region', 'Subscription') @(1, 2, 3, 4)
        foreach ($item in $Availability.Quotas) {
            $row = & $pdf.AddBodyRow $table
            $name = $row.Cells[0].AddParagraph($item.Quota); if (-not $item.Family) { $name.Format.Font.Name = 'Segoe UI Semibold' }
            & $number $row.Cells[1] $item.Used
            & $number $row.Cells[2] $item.Limit
            & $number $row.Cells[3] $item.Free
            $p = $row.Cells[4].AddParagraph($(if ($null -ne $item.UsedPercent) { "$($item.UsedPercent)%" } else { '-' })); $p.Format.Alignment = $right
            if ($null -ne $item.UsedPercent -and $item.UsedPercent -ge 90) { $p.Format.Font.Color = $pdf.Tone.Bad.Solid } elseif ($null -ne $item.UsedPercent -and $item.UsedPercent -ge 70) { $p.Format.Font.Color = $pdf.Tone.Warn.Solid }
            $row.Cells[5].AddParagraph($item.Location) | Out-Null
            $row.Cells[6].AddParagraph($item.SubscriptionName) | Out-Null
        }
    }
    if (@($Availability.Pools).Count) {
        $section.AddParagraph('AKS node pools', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(3.6, 4.4, 1.8, 2.0, 3.0, 2.6, 10.2)
        & $pdf.AddHeaderRow $table @('Pool', 'Size', 'Nodes', 'Zones', 'Size status', 'Family free', 'Why') @(2, 5)
        foreach ($item in $Availability.Pools) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Pool).Format.Font.Name = 'Segoe UI Semibold'
            if ($item.Mode) { $n = $row.Cells[0].AddParagraph($item.Mode); $n.Format.Font.Size = 7; $n.Format.Font.Color = $colors.Muted }
            $row.Cells[1].AddParagraph($item.VmSize) | Out-Null
            & $number $row.Cells[2] $item.Nodes
            $row.Cells[3].AddParagraph($(if ($item.Zones) { $item.Zones } else { 'none' })) | Out-Null
            & $status $row.Cells[4] $item.SizeStatus
            & $number $row.Cells[5] $item.FamilyVCpuFree
            $row.Cells[6].AddParagraph($item.Reason).Format.Font.Size = 7
        }
    }

    # --- 3. Sizes -----------------------------------------------------------------------------------
    $skus = @($Availability.Skus)
    if ($skus.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('VM sizes', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(5.0, 3.0, 1.4, 1.8, 1.8, 2.2, 4.2, 8.2)
        & $pdf.AddHeaderRow $table @('Size', 'Status', 'vCPUs', 'Memory GB', 'Zones', 'Family free', 'Features', 'Why') @(2, 3, 5)
        foreach ($item in @($skus | Select-Object -First $MaxRows)) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Sku).Format.Font.Name = 'Segoe UI Semibold'
            if ($stats.Locations -gt 1 -or $stats.Subscriptions -gt 1) { $n = $row.Cells[0].AddParagraph("$($item.Location) · $($item.SubscriptionName)"); $n.Format.Font.Size = 7; $n.Format.Font.Color = $colors.Muted }
            & $status $row.Cells[1] $item.Status
            & $number $row.Cells[2] $item.vCPUs
            $p = $row.Cells[3].AddParagraph(('{0:0.##}' -f $item.MemoryGB)); $p.Format.Alignment = $right
            $row.Cells[4].AddParagraph($(if ($item.Zones) { $item.Zones } else { 'none' })) | Out-Null
            & $number $row.Cells[5] $item.FamilyVCpuFree
            $features = @(if ($item.Architecture -eq 'Arm64') { 'Arm64' }; if ($item.GPUs) { "$($item.GPUs) GPU" }; if ($item.EphemeralOSDisk) { 'ephemeral OS' }; if ($item.AcceleratedNetworking) { 'accel. net' }; if ($item.PremiumStorage) { 'premium' })
            $row.Cells[6].AddParagraph($features -join ', ').Format.Font.Size = 7
            $row.Cells[7].AddParagraph((@($item.Reason, $item.Note, $(if ($item.InUse) { "in use: $($item.InUse)" })) | Where-Object { $_ }) -join '; ').Format.Font.Size = 7
        }
        if ($skus.Count -gt $MaxRows) {
            $p = $section.AddParagraph("The first $MaxRows sizes are listed; the CSV and HTML report have them all."); $p.Format.Font.Color = $colors.Muted
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
