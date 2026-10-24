function Write-AACSecurityPosturePdf {
    <#
    .SYNOPSIS
        Writes Get-AACSecurityPosture's result as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: title, scope, tiles, notices.
        2. Subscriptions: secure score, recommendations by severity, alerts,
           plans on and off, failed compliance controls.
        3. Recommendations: each recommendation, most severe first, with its
           control and every resource it is on (up to -MaxRows rows).
        4. Active alerts.
        5. Regulatory compliance: the standards, then each failed control
           with the checks failing it.
        6. Azure Policy: each assignment's compliance, and the policies with
           the most non-compliant resources.
        7. Defender plans that are off.
        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Posture,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [int] $MaxRows = 5000
    )

    $stats = $Posture.Stats
    $sections = @($Posture.Sections)
    $pdf = New-AACPdfDocument -Title $Title -Subject "Security posture: $($stats.Findings) findings" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $blue = [MigraDoc.DocumentObjectModel.Color]::Parse('#0369A1')
    $severityColor = @{ High = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Low = $blue }
    $scoreColor = { param($Score) if ($null -eq $Score) { $colors.Muted } elseif ($Score -ge 70) { $pdf.Tone.Good.Solid } elseif ($Score -ge 40) { $pdf.Tone.Warn.Solid } else { $pdf.Tone.Bad.Solid } }
    $number = { param($Cell, $Value, $Color) $p = $Cell.AddParagraph(('{0:N0}' -f [double]$Value)); $p.Format.Alignment = $right; if ([double]$Value -eq 0) { $p.Format.Font.Color = $colors.Muted } elseif ($Color) { $p.Format.Font.Color = $Color; $p.Format.Font.Name = 'Segoe UI Semibold' } }
    $severity = { param($Cell, [string] $Value) $p = $Cell.AddParagraph($Value); $p.Format.Font.Name = 'Segoe UI Semibold'; if ($severityColor.Contains($Value)) { $p.Format.Font.Color = $severityColor[$Value] } }
    $note = { param([string] $Text) $p = $section.AddParagraph($Text); $p.Format.Font.Size = 8; $p.Format.Font.Color = $colors.Muted; $p.Format.SpaceAfter = & $pt 4 }

    # --- 1. Summary -----------------------------------------------------------------------------
    & $pdf.AddTitle "Security posture · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
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
        @{ Value = $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { '-' }); Label = 'secure score'; Color = (& $scoreColor $stats.SecureScore) }
        if ($sections -contains 'Recommendations') { @{ Value = '{0:N0}' -f $stats.High; Label = 'high recommendations'; Color = $(if ($stats.High) { $pdf.Tone.Bad.Solid } else { $pdf.Tone.Good.Solid }) } }
        if ($sections -contains 'Recommendations') { @{ Value = '{0:N0}' -f $stats.Recommendations; Label = 'recommendations' } }
        if ($sections -contains 'Alerts') { @{ Value = '{0:N0}' -f $stats.Alerts; Label = 'active alerts'; Color = $(if ($stats.Alerts) { $pdf.Tone.Bad.Solid } else { $pdf.Tone.Good.Solid }) } }
        if ($sections -contains 'Plans') { @{ Value = "$($stats.PlansOn) / $($stats.PlansOn + $stats.PlansOff)"; Label = 'Defender plans on'; Color = $(if ($stats.PlansOff) { $pdf.Tone.Warn.Solid }) } }
        if ($sections -contains 'Compliance') { @{ Value = '{0:N0}' -f $stats.FailedControls; Label = 'failed compliance controls'; Color = $(if ($stats.FailedControls) { $pdf.Tone.Bad.Solid }) } }
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
    foreach ($text in @($Posture.Notice | Where-Object { $_ })) { & $note $text }

    # --- 2. Subscriptions ------------------------------------------------------------------------
    $section.AddParagraph('Subscriptions', 'Heading2') | Out-Null
    $table = & $pdf.NewTable @(7.0, 2.4, 3.0, 1.7, 1.9, 1.7, 1.9, 2.0, 2.0, 2.8)
    & $pdf.AddHeaderRow $table @('Subscription', 'Secure score', 'Points', 'High', 'Medium', 'Low', 'Alerts', 'Plans on', 'Plans off', 'Failed controls') @(1, 2, 3, 4, 5, 6, 7, 8, 9)
    foreach ($item in $Posture.Subscriptions) {
        $row = & $pdf.AddBodyRow $table
        $row.Cells[0].AddParagraph($item.SubscriptionName) | Out-Null
        $score = $row.Cells[1].AddParagraph($(if ($null -ne $item.SecureScore) { "$($item.SecureScore)%" } else { 'no score' }))
        $score.Format.Alignment = $right; $score.Format.Font.Name = 'Segoe UI Semibold'; $score.Format.Font.Color = & $scoreColor $item.SecureScore
        $points = $row.Cells[2].AddParagraph($item.Points); $points.Format.Alignment = $right; $points.Format.Font.Color = $colors.Muted
        & $number $row.Cells[3] $item.High $pdf.Tone.Bad.Solid
        & $number $row.Cells[4] $item.Medium $pdf.Tone.Warn.Solid
        & $number $row.Cells[5] $item.Low $blue
        & $number $row.Cells[6] $item.Alerts $pdf.Tone.Bad.Solid
        & $number $row.Cells[7] $item.PlansOn
        & $number $row.Cells[8] $item.PlansOff $pdf.Tone.Warn.Solid
        & $number $row.Cells[9] $item.FailedControls $pdf.Tone.Bad.Solid
    }

    # --- 3. Recommendations -------------------------------------------------------------------------
    $recommendations = @($Posture.Recommendations | Select-Object -First $MaxRows)
    if ($sections -contains 'Recommendations' -and $recommendations.Count) {
        $section.AddPageBreak()
        $section.AddParagraph("Recommendations$(if ($recommendations.Count -lt $Posture.Recommendations.Count) { " (the first $($recommendations.Count) of $($Posture.Recommendations.Count); the CSV and HTML report have them all)" })", 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(1.9, 8.4, 5.2, 4.8, 3.2, 3.2)
        & $pdf.AddHeaderRow $table @('Severity', 'Recommendation', 'Control', 'Resource', 'Resource group', 'Subscription')
        foreach ($item in $recommendations) {
            $row = & $pdf.AddBodyRow $table
            & $severity $row.Cells[0] $item.Severity
            $row.Cells[1].AddParagraph($item.Recommendation) | Out-Null
            $row.Cells[2].AddParagraph($item.Control).Format.Font.Color = $colors.Muted
            $row.Cells[3].AddParagraph($item.Resource) | Out-Null
            $row.Cells[4].AddParagraph($item.ResourceGroup) | Out-Null
            $row.Cells[5].AddParagraph($item.SubscriptionName) | Out-Null
        }
    }

    # --- 4. Alerts --------------------------------------------------------------------------------------
    if ($sections -contains 'Alerts' -and $Posture.Alerts.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Active security alerts', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(1.9, 9.0, 5.0, 4.6, 1.6, 4.6)
        & $pdf.AddHeaderRow $table @('Severity', 'Alert', 'Resource', 'Subscription', 'Age', 'Intent') @(4)
        foreach ($alert in $Posture.Alerts) {
            $row = & $pdf.AddBodyRow $table
            & $severity $row.Cells[0] $alert.Severity
            $row.Cells[1].AddParagraph($alert.Alert).Format.Font.Name = 'Segoe UI Semibold'
            if ($alert.Description) { $d = $row.Cells[1].AddParagraph($alert.Description); $d.Format.Font.Size = 7; $d.Format.Font.Color = $colors.Muted }
            $row.Cells[2].AddParagraph($alert.Resource) | Out-Null
            $row.Cells[3].AddParagraph($alert.SubscriptionName) | Out-Null
            $age = $row.Cells[4].AddParagraph($(if ($null -ne $alert.AgeDays) { "$($alert.AgeDays)d" } else { '' })); $age.Format.Alignment = $right
            $row.Cells[5].AddParagraph($alert.Intent).Format.Font.Color = $colors.Muted
        }
    }

    # --- 5. Regulatory compliance ------------------------------------------------------------------------------
    if ($sections -contains 'Compliance' -and $Posture.Standards.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Regulatory compliance', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(9.0, 6.0, 2.6, 2.2, 2.2, 2.2, 2.4)
        & $pdf.AddHeaderRow $table @('Standard', 'Subscription', 'Passed (%)', 'Passed', 'Failed', 'Skipped', 'Unsupported') @(2, 3, 4, 5, 6)
        foreach ($standard in $Posture.Standards) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($standard.Standard) | Out-Null
            $row.Cells[1].AddParagraph($standard.SubscriptionName) | Out-Null
            $rate = $row.Cells[2].AddParagraph($(if ($null -ne $standard.PassRate) { "$($standard.PassRate)%" } else { '' })); $rate.Format.Alignment = $right; $rate.Format.Font.Name = 'Segoe UI Semibold'; $rate.Format.Font.Color = & $scoreColor $standard.PassRate
            & $number $row.Cells[3] $standard.PassedControls
            & $number $row.Cells[4] $standard.FailedControls $pdf.Tone.Bad.Solid
            & $number $row.Cells[5] $standard.SkippedControls
            & $number $row.Cells[6] $standard.UnsupportedControls
        }
        foreach ($group in @($Posture.ComplianceControls | Where-Object State -EQ 'Failed' | Group-Object -Property Standard)) {
            $section.AddParagraph("$($group.Name): failed controls", 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(2.4, 9.6, 4.6, 1.6, 8.4)
            & $pdf.AddHeaderRow $table @('Control', 'Description', 'Subscription', 'Failed', 'Failing checks') @(3)
            foreach ($control in $group.Group) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($control.Control).Format.Font.Name = 'Segoe UI Semibold'
                $row.Cells[1].AddParagraph($control.Description) | Out-Null
                $row.Cells[2].AddParagraph($control.SubscriptionName) | Out-Null
                & $number $row.Cells[3] $control.FailedAssessments $pdf.Tone.Bad.Solid
                $checks = $row.Cells[4].AddParagraph($control.FailingChecks); $checks.Format.Font.Size = 7; $checks.Format.Font.Color = $colors.Muted
            }
        }
    }

    # --- 6. Azure Policy --------------------------------------------------------------------------------------------
    if ($sections -contains 'Policy' -and $Posture.PolicyAssignments.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Azure Policy', 'Heading2') | Out-Null
        & $note "Compliance as the Azure portal counts it - (compliant + exempt + unknown + protected resources) / every resource evaluated; $(if ($null -ne $stats.PolicyCompliance) { "$($stats.PolicyCompliance)% overall" } else { 'no evaluated resources' })."
        $table = & $pdf.NewTable @(10.0, 6.0, 2.8, 2.6, 2.4, 2.2)
        & $pdf.AddHeaderRow $table @('Assignment', 'Assigned at', 'Compliance', 'Non-compliant', 'Compliant', 'Exempt') @(2, 3, 4, 5)
        foreach ($assignment in $Posture.PolicyAssignments) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($assignment.Assignment) | Out-Null
            $row.Cells[1].AddParagraph($assignment.Scope) | Out-Null
            $rate = $row.Cells[2].AddParagraph($(if ($null -ne $assignment.ComplianceRate) { "$($assignment.ComplianceRate)%" } else { '-' })); $rate.Format.Alignment = $right; $rate.Format.Font.Name = 'Segoe UI Semibold'; $rate.Format.Font.Color = & $scoreColor $assignment.ComplianceRate
            & $number $row.Cells[3] $assignment.NonCompliant $pdf.Tone.Bad.Solid
            & $number $row.Cells[4] $assignment.Compliant
            & $number $row.Cells[5] $assignment.Exempt
        }
        $policies = @($Posture.Findings | Where-Object Section -EQ 'Policy' | Group-Object -Property Title | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
        if ($policies.Count) {
            $section.AddParagraph('Non-compliant resources by policy', 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(12.0, 8.0, 3.0, 3.0)
            & $pdf.AddHeaderRow $table @('Policy', 'Assignment', 'Resources', 'Effect') @(2)
            foreach ($policy in $policies) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($policy.Name) | Out-Null
                $row.Cells[1].AddParagraph([string]$policy.Group[0].Category).Format.Font.Color = $colors.Muted
                & $number $row.Cells[2] $policy.Count $pdf.Tone.Bad.Solid
                $row.Cells[3].AddParagraph(([string]$policy.Group[0].Detail -replace '^Effect: ', '')) | Out-Null
            }
        }
    }

    # --- 7. Defender plans that are off ----------------------------------------------------------------------------
    $off = @($Posture.Plans | Where-Object { -not $_.Enabled })
    if ($sections -contains 'Plans' -and $Posture.Plans.Count) {
        $section.AddParagraph('Defender plans that are off', 'Heading2') | Out-Null
        if ($off.Count) {
            $table = & $pdf.NewTable @(8.0, 18.0)
            & $pdf.AddHeaderRow $table @('Subscription', 'Plans off')
            foreach ($group in @($off | Group-Object -Property SubscriptionName)) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($group.Name) | Out-Null
                $row.Cells[1].AddParagraph((@($group.Group | ForEach-Object { $_.Plan }) -join ', ')).Format.Font.Color = $pdf.Tone.Warn.Solid
            }
        }
        else { & $note 'Every Defender plan is on.' }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
