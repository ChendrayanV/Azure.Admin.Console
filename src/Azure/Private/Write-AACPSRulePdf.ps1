function Write-AACPSRulePdf {
    <#
    .SYNOPSIS
        Writes Invoke-AACPSRule's results as a landscape A4 PDF report.
    .DESCRIPTION
        1. Summary: what was checked (account, tenant, scope, rules,
           settings), a PASSED/FAILED verdict, tiles and results by
           Well-Architected pillar.
        2. Failed rules: one row per rule, most failures first, with its
           severity, pillar and how many resources failed.
        3. Details: per pillar and rule, the rule's recommendation and
           documentation link, then every resource that failed and why.

        Passed results are counted, not listed. Drawn with the vendored
        PDFsharp + MigraDoc (Windows, PowerShell 7.4 or later).
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'PSRule for Azure',

        [System.Collections.IDictionary] $Detail,

        [int] $Rules,

        [int] $Objects
    )

    $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $passed = @($Result | Where-Object Outcome -EQ 'Pass').Count
    $problems = @($Result | Where-Object Outcome -NE 'Pass')
    $failedCount = @($problems | Where-Object Outcome -EQ 'Fail').Count
    $errorCount = @($problems | Where-Object Outcome -EQ 'Error').Count
    $decided = $passed + $failedCount
    $pillars = @('Security', 'Reliability', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency', 'Other')

    $pdf = New-AACPdfDocument -Title $Title -Subject "PSRule for Azure: $($Result.Count) results, $($problems.Count) failed" -Landscape
    $section = $pdf.Section
    $pageWidth = $pdf.PageWidth
    $pt = $pdf.Pt
    $newTable = $pdf.NewTable
    $addHeaderRow = $pdf.AddHeaderRow
    $addBodyRow = $pdf.AddBodyRow
    $muted = $pdf.Colors.Muted
    $accent = $pdf.Colors.Accent
    $panel = $pdf.Colors.Panel
    $white = $pdf.Colors.White
    $tone = $pdf.Tone
    $severityTone = @{ Critical = $tone.Bad; Error = $tone.Bad; Important = $tone.Warn; Warning = $tone.Warn; Awareness = $tone.Neutral }

    # --- 1. Summary ------------------------------------------------------------------------------
    & $pdf.AddTitle "$('{0:N0}' -f $Objects) objects · $('{0:N0}' -f $Rules) rules · $('{0:N0}' -f $Result.Count) results · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    $session = $script:AACSession
    if ($session) {
        $facts['Azure account'] = [string]$session.Account
        $facts['Tenant'] = [string]$session.TenantId
    }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    $factTable = & $newTable @(4.5, ($pageWidth - 4.5))
    foreach ($key in $facts.Keys) {
        $row = & $addBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }

    $verdict = if ($problems.Count -gt 0) { @{ Text = "FAILED  ·  $('{0:N0}' -f $failedCount) failed$(if ($errorCount) { ", $errorCount could not be evaluated" }) of $('{0:N0}' -f $Result.Count) results"; Fill = $tone.Bad.Solid } }
    elseif ($Result.Count -eq 0) { @{ Text = 'NO RULE APPLIED'; Fill = $tone.Warn.Solid } }
    else { @{ Text = "PASSED  ·  all $('{0:N0}' -f $passed) results passed"; Fill = $tone.Good.Solid } }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $banner = & $newTable @($pageWidth)
    $banner.TopPadding = & $pt 9
    $banner.BottomPadding = & $pt 9
    $bannerRow = $banner.AddRow()
    $bannerRow.Shading.Color = $verdict.Fill
    $bannerText = $bannerRow.Cells[0].AddParagraph($verdict.Text)
    $bannerText.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
    $bannerText.Format.Font.Size = 14
    $bannerText.Format.Font.Name = 'Segoe UI Semibold'
    $bannerText.Format.Font.Color = $white

    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileWidth = $pageWidth / 6
    $tiles = & $newTable @($tileWidth, $tileWidth, $tileWidth, $tileWidth, $tileWidth, $tileWidth)
    $tiles.TopPadding = & $pt 8
    $tiles.BottomPadding = & $pt 8
    $tileRow = $tiles.AddRow()
    $tileData = @(
        @{ Value = '{0:N0}' -f $Objects; Label = 'objects checked'; Color = $accent }
        @{ Value = '{0:N0}' -f $Rules; Label = 'rules'; Color = $accent }
        @{ Value = '{0:N0}' -f $passed; Label = 'passed'; Color = $tone.Good.Text }
        @{ Value = '{0:N0}' -f $failedCount; Label = 'failed'; Color = $(if ($failedCount) { $tone.Bad.Text } else { $muted }) }
        @{ Value = '{0:N0}' -f $errorCount; Label = 'could not evaluate'; Color = $(if ($errorCount) { $tone.Warn.Text } else { $muted }) }
        @{ Value = $(if ($decided) { '{0:N1}%' -f (100 * $passed / $decided) } else { '-' }); Label = 'pass rate'; Color = $accent }
    )
    for ($i = 0; $i -lt $tileData.Count; $i++) {
        $cell = $tileRow.Cells[$i]
        $cell.Shading.Color = $panel
        $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
        $cell.Borders.Left.Color = $white
        $number = $cell.AddParagraph($tileData[$i].Value)
        $number.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $number.Format.Font.Size = 18
        $number.Format.Font.Name = 'Segoe UI Semibold'
        $number.Format.Font.Color = $tileData[$i].Color
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $muted
    }

    $section.AddParagraph('Results by Well-Architected pillar', 'Heading2') | Out-Null
    $byPillar = & $newTable @(8.1, 3.6, 3.6, 3.6, 3.6, 3.6)
    & $addHeaderRow $byPillar @('Pillar', 'Rules failed', 'Failed', 'Could not evaluate', 'Passed', 'Pass rate') @(1, 2, 3, 4, 5)
    foreach ($pillar in $pillars) {
        $items = @($Result | Where-Object Pillar -EQ $pillar)
        if ($items.Count -eq 0) { continue }
        $p = @($items | Where-Object Outcome -EQ 'Pass').Count
        $f = @($items | Where-Object Outcome -EQ 'Fail').Count
        $e = @($items | Where-Object Outcome -EQ 'Error').Count
        $row = & $addBodyRow $byPillar
        $row.Cells[0].AddParagraph($pillar) | Out-Null
        $values = @(
            @($items | Where-Object Outcome -NE 'Pass' | ForEach-Object RuleName | Select-Object -Unique).Count
            $f, $e, $p
        )
        for ($i = 0; $i -lt $values.Count; $i++) {
            $para = $row.Cells[$i + 1].AddParagraph('{0:N0}' -f $values[$i])
            $para.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
            if ($i -eq 1 -and $values[$i]) { $para.Format.Font.Color = $tone.Bad.Text; $para.Format.Font.Bold = $true }
            elseif ($values[$i] -eq 0) { $para.Format.Font.Color = $muted }
        }
        $rate = $row.Cells[5].AddParagraph($(if ($p + $f) { '{0:N0}%' -f (100 * $p / ($p + $f)) } else { '-' }))
        $rate.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    }

    if ($problems.Count -eq 0) {
        Save-AACPdfDocument -Pdf $pdf -Path $fullPath
        return
    }

    # --- 2. Failed rules -----------------------------------------------------------------------------
    $groups = @($problems | Group-Object -Property RuleName | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
    $heading = $section.AddParagraph('Failed rules', 'Heading1')
    $heading.Format.SpaceBefore = & $pt 18
    $intro = $section.AddParagraph('One row per rule, most failures first. The details follow, pillar by pillar.')
    $intro.Format.Font.Color = $muted
    $intro.Format.SpaceAfter = & $pt 6
    $ruleTable = & $newTable @(2.6, 7.6, 10.5, 3.6, 1.8)
    & $addHeaderRow $ruleTable @('Severity', 'Rule', 'Title', 'Pillar', 'Failed') @(4)
    foreach ($group in $groups) {
        $first = $group.Group[0]
        $row = & $addBodyRow $ruleTable
        $look = if ($severityTone.ContainsKey([string]$first.Severity)) { $severityTone[[string]$first.Severity] } else { $tone.Neutral }
        $row.Cells[0].Shading.Color = $look.Fill
        $badge = $row.Cells[0].AddParagraph(([string]$first.Severity).ToUpperInvariant())
        $badge.Format.Font.Size = 7.5
        $badge.Format.Font.Bold = $true
        $badge.Format.Font.Color = $look.Text
        $row.Cells[1].AddParagraph([string]$first.RuleName).Format.Font.Name = 'Segoe UI Semibold'
        $row.Cells[2].AddParagraph([string]$first.Title) | Out-Null
        $row.Cells[3].AddParagraph([string]$first.Pillar) | Out-Null
        $count = $row.Cells[4].AddParagraph('{0:N0}' -f $group.Count)
        $count.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
        $count.Format.Font.Color = $tone.Bad.Text
        $count.Format.Font.Bold = $true
    }

    # --- 3. Details ------------------------------------------------------------------------------------
    foreach ($pillar in $pillars) {
        $inPillar = @($groups | Where-Object { $_.Group[0].Pillar -eq $pillar })
        if ($inPillar.Count -eq 0) { continue }
        $pillarHeading = $section.AddParagraph($pillar, 'Heading1')
        $pillarHeading.Format.SpaceBefore = & $pt 18
        foreach ($group in $inPillar) {
            $first = $group.Group[0]
            $ruleHeading = $section.AddParagraph('', 'Heading3')
            $ruleHeading.AddText([string]$first.RuleName) | Out-Null
            $sub = $ruleHeading.AddFormattedText("   $($first.Severity) · $($group.Count) failed · $($first.Source)")
            $sub.Size = 8.5
            $sub.Color = $muted
            if ($first.Title) { $section.AddParagraph([string]$first.Title) | Out-Null }
            if ($first.Recommendation) {
                $recommendation = $section.AddParagraph()
                $recommendation.Format.Font.Size = 8.5
                $label = $recommendation.AddFormattedText('Recommendation: ')
                $label.Bold = $true
                $recommendation.AddText([string]$first.Recommendation) | Out-Null
            }
            if ($first.Link) {
                $linkParagraph = $section.AddParagraph()
                $linkParagraph.Format.Font.Size = 8
                $hyperlink = $linkParagraph.AddHyperlink([string]$first.Link, [MigraDoc.DocumentObjectModel.HyperlinkType]::Web)
                $linkText = $hyperlink.AddFormattedText([string]$first.Link)
                $linkText.Color = $accent
            }
            $section.AddParagraph().Format.SpaceAfter = & $pt 2
            $table = & $newTable @(5.4, 5.2, 5.0, 10.5)
            & $addHeaderRow $table @('Resource', 'Type', 'Resource group · subscription', 'Why') @()
            foreach ($item in $group.Group) {
                $row = & $addBodyRow $table
                $name = $row.Cells[0].AddParagraph([string]$item.ResourceName)
                $name.Format.Font.Name = 'Segoe UI Semibold'
                $row.Cells[1].AddParagraph(([string]$item.ResourceType)) | Out-Null
                $row.Cells[2].AddParagraph((@($item.ResourceGroup, $item.SubscriptionName) | Where-Object { $_ }) -join ' · ') | Out-Null
                $why = $row.Cells[3].AddParagraph([string]$item.Reason)
                $why.Format.Font.Size = 8
                if ($item.Outcome -eq 'Error') { $why.Format.Font.Color = $tone.Warn.Text }
            }
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $fullPath
}
