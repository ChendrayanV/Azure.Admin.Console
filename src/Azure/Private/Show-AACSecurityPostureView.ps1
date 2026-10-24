function Show-AACSecurityPostureView {
    <#
    .SYNOPSIS
        Renders Get-AACSecurityPosture's result as a Spectre.Console view.
    .DESCRIPTION
        The scope, tiles (secure score, High and Medium recommendations,
        active alerts, plans off, failed compliance controls), then - for the
        sections read:
          Subscriptions     secure score in colour, recommendations by
                            severity, alerts, plans on and off
          Recommendations   one table row per recommendation, most severe
                            first: its control and category, and every
                            resource it is on (up to -MaxResource)
          Alerts            severity, alert, resource, age, intent
          Compliance        each standard's pass rate as a bar, then its
                            failed controls with the checks failing them
          Policy            Azure Policy assignments, least compliant first,
                            and the policies with the most non-compliant
                            resources
          Plans             the Defender plans that are off
        Scores: Good (70%+) green, Fair (40-69%) amber, Poor red; severities
        High red, Medium amber, Low blue. Wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Posture,

        [System.Collections.IDictionary] $Scope,

        [int] $MaxResource = 50
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Posture.Stats
    $sections = @($Posture.Sections)
    $ratingColor = @{ Good = 'green3'; Fair = 'orange1'; Poor = 'red1' }
    $badge = {
        param([string] $Severity)
        switch ($Severity) {
            'High' { '[bold white on red3] HIGH [/]' }
            'Medium' { '[bold black on orange1] MEDIUM [/]' }
            'Low' { '[black on deepskyblue1] LOW [/]' }
            default { "[grey70]$(& $escape $Severity)[/]" }
        }
    }
    $newTable = {
        param([string] $Title, [string] $Color, [object[]] $Columns)
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($Color)
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new($Title)
        foreach ($column in $Columns) {
            $spectre = [Spectre.Console.TableColumn]::new("[grey62]$($column[0])[/]")
            if ($column[1]) { $spectre.Width = $column[1] }
            if ($column[2]) { $spectre.Alignment = [Spectre.Console.Justify]::Right; $spectre.NoWrap = $true }
            $table.AddColumn($spectre) | Out-Null
        }
        $table
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }
    $count = { param([int] $Value, [string] $Color) if ($Value -eq 0) { '[grey42]0[/]' } else { "[$Color]$('{0:N0}' -f $Value)[/]" } }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    $tiles = @(
        @{ Value = $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { '-' }); Caption = $(if ($stats.Rating) { "secure score ($($stats.Rating.ToLowerInvariant()))" } else { 'secure score' }); Color = $(if ($stats.Rating) { $ratingColor[$stats.Rating] } else { 'grey50' }) }
        if ($sections -contains 'Recommendations') {
            @{ Value = '{0:N0}' -f $stats.High; Caption = 'high recommendations'; Color = $(if ($stats.High) { 'red1' } else { 'green3' }) }
            @{ Value = '{0:N0}' -f $stats.Medium; Caption = 'medium recommendations'; Color = $(if ($stats.Medium) { 'orange1' } else { 'green3' }) }
        }
        if ($sections -contains 'Alerts') { @{ Value = '{0:N0}' -f $stats.Alerts; Caption = 'active alerts'; Color = $(if ($stats.HighAlerts) { 'red1' } elseif ($stats.Alerts) { 'orange1' } else { 'green3' }) } }
        if ($sections -contains 'Plans') { @{ Value = "$($stats.PlansOn) / $($stats.PlansOn + $stats.PlansOff)"; Caption = 'Defender plans on'; Color = $(if ($stats.PlansOff) { 'orange1' } else { 'green3' }) } }
        if ($sections -contains 'Compliance') { @{ Value = '{0:N0}' -f $stats.FailedControls; Caption = 'failed compliance controls'; Color = $(if ($stats.FailedControls) { 'red1' } else { 'green3' }) } }
        if ($sections -contains 'Policy') { @{ Value = $(if ($null -ne $stats.PolicyCompliance) { "$($stats.PolicyCompliance)%" } else { '-' }); Caption = 'Azure Policy compliance'; Color = $(if ($null -eq $stats.PolicyCompliance) { 'grey50' } elseif ($stats.PolicyCompliance -ge 90) { 'green3' } elseif ($stats.PolicyCompliance -ge 70) { 'orange1' } else { 'red1' }) } }
    )
    Show-AACTileRow -Tile $tiles
    [Spectre.Console.AnsiConsole]::WriteLine()
    foreach ($notice in @($Posture.Notice | Where-Object { $_ })) { Write-AACMarkup "[deepskyblue1]i[/] [grey70]$(& $escape $notice)[/]" }
    if (@($Posture.Notice).Count) { [Spectre.Console.AnsiConsole]::WriteLine() }

    # --- Subscriptions ---------------------------------------------------------------------------------
    if ($Posture.Subscriptions.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Subscriptions[/]" 'grey42' @(@('Subscription', 0, $false), @('Secure score', 0, $true), @('Points', 0, $true), @('High', 0, $true), @('Medium', 0, $true), @('Low', 0, $true), @('Alerts', 0, $true), @('Plans on / off', 0, $true), @('Failed controls', 0, $true))
        foreach ($item in $Posture.Subscriptions) {
            & $addRow $table @(
                "[bold]$(& $escape $item.SubscriptionName)[/]"
                $(if ($null -ne $item.SecureScore) { "[bold $($ratingColor[$item.Rating])]$($item.SecureScore)%[/]" } else { '[grey50]no score[/]' })
                "[grey58]$(& $escape $item.Points)[/]"
                (& $count $item.High 'red1'); (& $count $item.Medium 'orange1'); (& $count $item.Low 'deepskyblue1')
                (& $count $item.Alerts 'red1')
                "[green3]$($item.PlansOn)[/] / $(if ($item.PlansOff) { "[orange1]$($item.PlansOff)[/]" } else { '[grey42]0[/]' })"
                (& $count $item.FailedControls 'red1')
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Secure score controls with the most to gain -------------------------------------------------------
    $gain = @($Posture.Controls | Where-Object { $_.PotentialIncrease -gt 0 } | Sort-Object -Property @{ Expression = 'PotentialIncrease'; Descending = $true }, Control)
    if ($gain.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Secure score controls with the most to gain[/]" 'grey42' @(@('Control', 0, $false), @('Subscription', 0, $false), @('Score', 0, $true), @('Unhealthy resources', 0, $true), @('Potential increase', 0, $true))
        foreach ($control in $gain) {
            $rating = if ($null -eq $control.Score) { '' } elseif ($control.Score -ge 70) { 'Good' } elseif ($control.Score -ge 40) { 'Fair' } else { 'Poor' }
            & $addRow $table @(
                "[white]$(& $escape $control.Control)[/]"
                "[grey70]$(& $escape $control.SubscriptionName)[/]"
                $(if ($rating) { "[$($ratingColor[$rating])]$($control.Score)%[/]" } else { '' })
                (& $count $control.UnhealthyResources 'grey85')
                "[bold $(if ($control.PotentialIncrease -ge 5) { 'red1' } elseif ($control.PotentialIncrease -ge 2) { 'orange1' } else { 'deepskyblue1' })]+$($control.PotentialIncrease)%[/]"
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Recommendations, grouped ---------------------------------------------------------------------------
    if ($sections -contains 'Recommendations') {
        $groups = @($Posture.Recommendations | Group-Object -Property Recommendation | Sort-Object -Property @(
                @{ Expression = { @{ High = 0; Medium = 1; Low = 2 }[[string]$_.Group[0].Severity] } }
                @{ Expression = 'Count'; Descending = $true }
                'Name'))
        if ($groups.Count) {
            $table = & $newTable "[bold]$($glyph.Bullet) Recommendations[/] [grey58]$($glyph.Dot) $($groups.Count) on $($stats.Resources) resource(s), most severe first[/]" 'indianred1' @(@('Severity', 10, $false), @('Recommendation', 0, $false), @('Resources', 9, $true), @('Where', 0, $false))
            foreach ($group in $groups) {
                $first = $group.Group[0]
                $what = "[bold]$(& $escape $first.Recommendation)[/]"
                $context = @($first.Control, $first.Category) | Where-Object { $_ }
                if ($context) { $what += "`n[grey58]$(& $escape ($context -join " $($glyph.Dot) "))[/]" }
                $shown = @($group.Group | Select-Object -First $MaxResource)
                $where = @($shown | ForEach-Object { "[white]$(& $escape $_.Resource)[/] [grey50]$(& $escape (@($_.ResourceGroup, $_.SubscriptionName) | Where-Object { $_ }) -join ' / ')[/]" })
                if ($group.Count -gt $shown.Count) { $where += "[grey50]... and $($group.Count - $shown.Count) more: -PassThru, -CsvPath or -HtmlPath lists them all[/]" }
                & $addRow $table @((& $badge $first.Severity), $what, "[bold]$($group.Count)[/]", ($where -join "`n"))
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        else {
            Show-AACCallout Success -Message '[bold green3]No unhealthy recommendations[/] [grey58]in this scope.[/]'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    # --- Alerts ----------------------------------------------------------------------------------------------
    if ($sections -contains 'Alerts') {
        if ($Posture.Alerts.Count) {
            $table = & $newTable "[bold]$($glyph.Bullet) Active security alerts[/] [grey58]$($glyph.Dot) $($Posture.Alerts.Count)[/]" 'red3' @(@('Severity', 10, $false), @('Alert', 0, $false), @('Resource', 0, $false), @('Age', 7, $true), @('Intent', 0, $false))
            foreach ($alert in $Posture.Alerts) {
                & $addRow $table @(
                    (& $badge $alert.Severity)
                    "[bold]$(& $escape $alert.Alert)[/]$(if ($alert.Description) { "`n[grey58]$(& $escape $alert.Description)[/]" })"
                    "[white]$(& $escape $alert.Resource)[/]`n[grey50]$(& $escape (@($alert.ResourceGroup, $alert.SubscriptionName) | Where-Object { $_ }) -join ' / ')[/]"
                    $(if ($null -ne $alert.AgeDays) { "$($alert.AgeDays)d" } else { '' })
                    "[grey70]$(& $escape $alert.Intent)[/]"
                )
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        else {
            Write-AACMarkup "[green3]$($glyph.Bullet)[/] [grey70]No active security alerts.[/]"
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    # --- Regulatory compliance ----------------------------------------------------------------------------------
    if ($sections -contains 'Compliance' -and $Posture.Standards.Count) {
        $bars = @($Posture.Standards | Where-Object { $null -ne $_.PassRate } | ForEach-Object {
                @{ Label = "$($_.Standard) ($($_.SubscriptionName))"; Value = $_.PassRate; Color = $(if ($_.PassRate -ge 70) { 'green3' } elseif ($_.PassRate -ge 40) { 'orange1' } else { 'red1' }) }
            })
        if ($bars.Count) {
            Show-AACBarChart -Item $bars -Title 'Regulatory compliance: controls passed (%)'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        $failed = @($Posture.ComplianceControls | Where-Object State -EQ 'Failed')
        foreach ($standard in @($failed | Group-Object -Property Standard)) {
            $table = & $newTable "[bold]$($glyph.Bullet) $(& $escape $standard.Name)[/] [grey58]$($glyph.Dot) $($standard.Count) failed control(s)[/]" 'orange1' @(@('Control', 12, $false), @('Description', 0, $false), @('Subscription', 0, $false), @('Failed', 7, $true), @('Failing checks', 0, $false))
            foreach ($control in $standard.Group) {
                & $addRow $table @("[bold]$(& $escape $control.Control)[/]", "[white]$(& $escape $control.Description)[/]", "[grey70]$(& $escape $control.SubscriptionName)[/]", "[red1]$($control.FailedAssessments)[/]", "[grey58]$(& $escape $control.FailingChecks)[/]")
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    # --- Azure Policy ------------------------------------------------------------------------------------------------
    if ($sections -contains 'Policy' -and $Posture.PolicyAssignments.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Azure Policy assignments[/] [grey58]$($glyph.Dot) least compliant first[/]" 'mediumpurple2' @(@('Assignment', 0, $false), @('Assigned at', 0, $false), @('Compliance', 0, $true), @('Non-compliant', 0, $true), @('Compliant', 0, $true), @('Exempt', 0, $true))
        foreach ($assignment in $Posture.PolicyAssignments) {
            $rate = $assignment.ComplianceRate
            & $addRow $table @(
                "[bold]$(& $escape $assignment.Assignment)[/]$(if ($assignment.Enforcement -eq 'DoNotEnforce') { ' [grey50](not enforced)[/]' })"
                "[grey70]$(& $escape $assignment.Scope)[/]"
                $(if ($null -eq $rate) { '[grey50]-[/]' } else { "[bold $(if ($rate -ge 90) { 'green3' } elseif ($rate -ge 70) { 'orange1' } else { 'red1' })]$rate%[/]" })
                (& $count $assignment.NonCompliant 'red1'); (& $count $assignment.Compliant 'green3'); (& $count $assignment.Exempt 'grey70')
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
        $policies = @($Posture.Findings | Where-Object Section -EQ 'Policy' | Group-Object -Property Title | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
        if ($policies.Count) {
            $table = & $newTable "[bold]$($glyph.Bullet) Non-compliant resources by policy[/]" 'mediumpurple2' @(@('Policy', 0, $false), @('Resources', 9, $true), @('Where', 0, $false))
            foreach ($policy in $policies) {
                $shown = @($policy.Group | Select-Object -First $MaxResource)
                $where = @($shown | ForEach-Object { "[white]$(& $escape $_.Resource)[/] [grey50]$(& $escape (@($_.ResourceGroup, $_.SubscriptionName) | Where-Object { $_ }) -join ' / ')[/]" })
                if ($policy.Count -gt $shown.Count) { $where += "[grey50]... and $($policy.Count - $shown.Count) more: -PassThru, -CsvPath or -HtmlPath lists them all[/]" }
                & $addRow $table @("[bold]$(& $escape $policy.Name)[/]`n[grey58]$(& $escape $policy.Group[0].Category)[/]", "[bold]$($policy.Count)[/]", ($where -join "`n"))
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    # --- Defender plans that are off --------------------------------------------------------------------------------
    if ($sections -contains 'Plans') {
        $off = @($Posture.Plans | Where-Object { -not $_.Enabled })
        if ($off.Count) {
            Write-AACMarkup "[bold orange1]$($glyph.Bullet) Defender plans that are off[/] [grey58]$($glyph.Dot) no threat protection or alerts for these workloads[/]"
            foreach ($group in @($off | Group-Object -Property SubscriptionName)) {
                Write-AACMarkup "  [white]$(& $escape $group.Name)[/]  [grey70]$(& $escape (@($group.Group | ForEach-Object { $_.Plan }) -join ', '))[/]"
            }
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the findings; -CsvPath, -PdfPath or -HtmlPath for a report with every finding and its portal link.[/]'
}
