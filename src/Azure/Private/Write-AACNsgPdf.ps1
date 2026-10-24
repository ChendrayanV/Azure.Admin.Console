function Write-AACNsgPdf {
    <#
    .SYNOPSIS
        Writes the network security group assessment (ConvertTo-AACNsgAssessment)
        as a landscape A4 PDF report.
    .DESCRIPTION
        1. Summary: title, scope, tiles, and a table of the NSGs - applied
           to, rules, flow logs, diagnostics, findings by severity.
        2. Findings, most severe first: severity (High red, Medium amber, Low
           blue, Info grey), check, NSG, rule, what was found, what to do.
        3. One page per NSG: its metadata, associations and telemetry, then
           its inbound and outbound rules in evaluation order - Allow green,
           Deny red, default rules grey, risky rules flagged.

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

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Assessment.Stats
    $groups = @($Assessment.Groups)
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($stats.Groups) network security groups" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $blue = [MigraDoc.DocumentObjectModel.Color]::Parse('#0369A1')
    $severityColor = @{ High = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Low = $blue; Info = $colors.Muted }
    $small = { param($Paragraph) $Paragraph.Format.Font.Size = 7.5; $Paragraph }
    $colored = {
        param($Cell, [string] $Text, $Color, [switch] $Bold)
        $p = $Cell.AddParagraph($Text)
        if ($Color) { $p.Format.Font.Color = $Color }
        if ($Bold) { $p.Format.Font.Name = 'Segoe UI Semibold' }
        $p
    }
    $findingCounts = {
        param($Cell, $Item)
        $p = $Cell.AddParagraph()
        $p.Format.Alignment = $right
        foreach ($level in 'High', 'Medium', 'Low', 'Info') {
            $n = [int]$Item.$level
            if (-not $n) { continue }
            $t = $p.AddFormattedText("$($level.Substring(0, 1))$n ")
            $t.Color = $severityColor[$level]
            $t.Bold = $true
        }
    }

    # --- 1. Summary ---------------------------------------------------------------------------------
    & $pdf.AddTitle "Network security group assessment · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    $facts['How rules are read'] = 'Per direction, custom rules by priority (lowest number first), then the default rules; the first rule that matches decides. Traffic to a NIC passes its subnet''s NSG and its own NSG: both must allow it.'
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = $stats.Groups; Label = 'NSGs' }
        @{ Value = $stats.Rules; Label = 'custom rules' }
        @{ Value = $stats.High; Label = 'high findings'; Color = $(if ($stats.High) { $pdf.Tone.Bad.Solid }) }
        @{ Value = $stats.Medium; Label = 'medium findings'; Color = $(if ($stats.Medium) { $pdf.Tone.Warn.Solid }) }
        @{ Value = $stats.Unassociated; Label = 'unassociated'; Color = $(if ($stats.Unassociated) { $pdf.Tone.Warn.Solid }) }
        @{ Value = $stats.WithoutFlowLogs; Label = 'without flow logs'; Color = $(if ($stats.WithoutFlowLogs) { $pdf.Tone.Warn.Solid }) }
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
        $value = $cell.AddParagraph(('{0:N0}' -f $tileData[$i].Value))
        $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $value.Format.Font.Size = 18
        $value.Format.Font.Name = 'Segoe UI Semibold'
        if ($tileData[$i].Contains('Color') -and $tileData[$i].Color) { $value.Format.Font.Color = $tileData[$i].Color }
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }

    $section.AddParagraph('Network security groups', 'Heading2') | Out-Null
    $table = & $pdf.NewTable @(5.0, 7.4, 1.4, 1.4, 4.2, 2.4, 4.3)
    & $pdf.AddHeaderRow $table @('NSG', 'Applied to', 'In', 'Out', 'Flow logs', 'Diagnostics', 'Findings') @(2, 3, 6)
    foreach ($nsg in $groups) {
        $row = & $pdf.AddBodyRow $table
        $name = $row.Cells[0].AddParagraph($nsg.Name)
        $name.Format.Font.Name = 'Segoe UI Semibold'
        & $small ($row.Cells[0].AddParagraph("$($nsg.ResourceGroup) · $($nsg.SubscriptionName)")) | ForEach-Object { $_.Format.Font.Color = $colors.Muted }
        if ($nsg.Associated) { & $small ($row.Cells[1].AddParagraph(($nsg.AppliedTo -replace '; ', "`n"))) | Out-Null } else { & $colored $row.Cells[1] 'nothing' $pdf.Tone.Warn.Solid | Out-Null }
        & $small ($row.Cells[2].AddParagraph("$($nsg.InboundRules)")) | ForEach-Object { $_.Format.Alignment = $right }
        & $small ($row.Cells[3].AddParagraph("$($nsg.OutboundRules)")) | ForEach-Object { $_.Format.Alignment = $right }
        & $colored $row.Cells[4] $nsg.FlowLogs $(if ($nsg.FlowLogs -like 'Enabled*') { $pdf.Tone.Good.Solid } elseif ($nsg.Associated) { $pdf.Tone.Warn.Solid } else { $colors.Muted }) | Out-Null
        if ($nsg.FlowLogRetention) { & $small ($row.Cells[4].AddParagraph("$($nsg.FlowLogRetention)$(if ($nsg.TrafficAnalytics) { ' · Traffic Analytics' })")) | ForEach-Object { $_.Format.Font.Color = $colors.Muted } }
        & $colored $row.Cells[5] $nsg.Diagnostics $(if ($nsg.Diagnostics -eq 'Enabled') { $pdf.Tone.Good.Solid } elseif ($nsg.Diagnostics -eq 'Disabled') { $pdf.Tone.Warn.Solid } else { $colors.Muted }) | Out-Null
        & $findingCounts $row.Cells[6] $nsg
    }

    # --- 2. Findings --------------------------------------------------------------------------------------
    $findings = @($Assessment.Findings | Sort-Object -Property @{ Expression = { @{ High = 0; Medium = 1; Low = 2; Info = 3 }[$_.Severity] } }, Nsg, Check)
    if ($findings.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Findings', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(1.8, 3.4, 3.4, 3.4, 7.4, 6.7)
        & $pdf.AddHeaderRow $table @('Severity', 'Check', 'NSG', 'Rule', 'What was found', 'What to do')
        foreach ($finding in $findings) {
            $row = & $pdf.AddBodyRow $table
            & $colored $row.Cells[0] $finding.Severity $severityColor[$finding.Severity] -Bold | Out-Null
            $row.Cells[1].AddParagraph($finding.Check) | Out-Null
            $row.Cells[2].AddParagraph($finding.Nsg) | Out-Null
            & $small ($row.Cells[3].AddParagraph($finding.Rule)) | Out-Null
            & $small ($row.Cells[4].AddParagraph($finding.Detail)) | Out-Null
            & $small ($row.Cells[5].AddParagraph($finding.Recommendation)) | ForEach-Object { $_.Format.Font.Color = $colors.Muted }
        }
    }

    # --- 3. Each NSG ----------------------------------------------------------------------------------------
    foreach ($nsg in $groups) {
        $section.AddPageBreak()
        $section.AddParagraph($nsg.Name, 'Heading1') | Out-Null
        & $small ($section.AddParagraph($nsg.Id)) | ForEach-Object { $_.Format.Font.Color = $colors.Muted }
        $meta = & $pdf.NewTable @(4.0, 8.9, 4.0, 9.2)
        $pairs = @(
            , @('Subscription', $nsg.SubscriptionName, 'Resource group', $nsg.ResourceGroup)
            , @('Location', $nsg.Location, 'Tags', $nsg.Tags)
            , @('Subnets', $((@($nsg.Subnets | ForEach-Object { "$($_.VirtualNetwork)/$($_.Name) ($($_.Prefix))" })) -join "`n"), 'Network interfaces', $((@($nsg.NetworkInterfaces | ForEach-Object { "$($_.Name)$(if ($_.VirtualMachine) { " · $($_.VirtualMachine)" })$(if ($_.PrivateIp) { " · $($_.PrivateIp)" })" })) -join "`n"))
            , @('Flow logs', "$($nsg.FlowLogs)$(foreach ($log in $nsg.FlowLogDetail) { "`n$($log.Name): $($log.Kind), $(if ($log.Enabled) { 'enabled' } else { 'disabled' })$(if ($log.Storage) { ", storage $($log.Storage)" }), $(if ($log.RetentionEnabled -and $log.RetentionDays) { "$($log.RetentionDays) days" } else { 'no retention limit' })$(if ($log.Analytics) { ', Traffic Analytics' })" })", 'Diagnostics', "$($nsg.Diagnostics)$(if ($nsg.LogDestinations) { "`n$($nsg.LogDestinations)" })$(foreach ($setting in $nsg.DiagnosticSettings) { "`n$($setting.Name): $($setting.Categories)" })")
        )
        foreach ($pair in $pairs) {
            $row = & $pdf.AddBodyRow $meta
            $row.Cells[0].AddParagraph($pair[0]).Format.Font.Color = $colors.Muted
            & $small ($row.Cells[1].AddParagraph($(if ($pair[1]) { $pair[1] } else { '-' }))) | Out-Null
            $row.Cells[2].AddParagraph($pair[2]).Format.Font.Color = $colors.Muted
            & $small ($row.Cells[3].AddParagraph($(if ($pair[3]) { $pair[3] } else { '-' }))) | Out-Null
        }
        foreach ($direction in 'Inbound', 'Outbound') {
            $section.AddParagraph("$direction rules", 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(1.5, 4.8, 1.6, 1.6, 4.6, 2.4, 4.6, 4.9)
            & $pdf.AddHeaderRow $table @('Priority', 'Name', 'Access', 'Protocol', 'Source', 'Ports', 'Destination', 'Finding') @(0)
            foreach ($rule in @($nsg.Rules | Where-Object Direction -EQ $direction)) {
                $row = & $pdf.AddBodyRow $table
                $muted = $rule.IsDefault
                $priority = & $small ($row.Cells[0].AddParagraph("$($rule.Priority)"))
                $priority.Format.Alignment = $right
                $ruleName = & $small ($row.Cells[1].AddParagraph($rule.Name))
                & $colored $row.Cells[2] $rule.Access $(if ($rule.Access -eq 'Allow') { $pdf.Tone.Good.Solid } else { $pdf.Tone.Bad.Solid }) -Bold | Out-Null
                $cells = @(
                    (& $small ($row.Cells[3].AddParagraph($rule.Protocol)))
                    (& $small ($row.Cells[4].AddParagraph($rule.Source)))
                    (& $small ($row.Cells[5].AddParagraph($rule.DestinationPorts)))
                    (& $small ($row.Cells[6].AddParagraph($rule.Destination)))
                )
                if ($muted) { foreach ($p in @($priority, $ruleName) + $cells) { $p.Format.Font.Color = $colors.Muted } }
                if ($rule.Risk) {
                    $finding = & $small ($row.Cells[7].AddParagraph("$($rule.Risk): $($rule.Finding)"))
                    $finding.Format.Font.Color = $severityColor[$rule.Risk]
                }
            }
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
