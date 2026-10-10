function Show-AACPolicyAssessmentView {
    <#
    .SYNOPSIS
        Renders Invoke-AACPolicyAssessment's result as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (overall compliance, assignments, non-compliant
        resources, exemptions to look at, findings by severity); compliance
        by subscription and by category as bar charts; the assignments,
        least compliant first; the exemptions expired or expiring; and the
        High and Medium findings with what to do. Wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Scope,

        [int] $Top = 25
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Assessment.Stats
    $color = @{ High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1'; Info = 'grey62' }
    $rateColor = @{ Good = 'green3'; Warning = 'orange1'; Poor = 'red1'; 'No data' = 'grey50' }
    $percent = { param($Value, [string] $Rating) if ($null -eq $Value) { '[grey50]-[/]' } else { "[$($rateColor[$Rating])]$Value%[/]" } }
    $newTable = {
        param([string] $TitleText, [string[]] $Headers, [string[]] $Right = @())
        $t = [Spectre.Console.Table]::new(); $t.Border = [Spectre.Console.TableBorder]::Rounded; $t.BorderStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1'); $t.Expand = $true
        if ($TitleText) { $t.Title = [Spectre.Console.TableTitle]::new($TitleText) }
        foreach ($header in $Headers) { $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]"); if ($header -in $Right) { $column.Alignment = [Spectre.Console.Justify]::Right }; $t.AddColumn($column) | Out-Null }
        $t
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    foreach ($line in @($Assessment['Notices'])) { Write-AACStatusLine Warning $line }
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = $(if ($null -ne $stats.CompliancePercent) { "$($stats.CompliancePercent)%" } else { '-' }); Caption = 'resources compliant'; Color = $rateColor[$stats.Rating] }
        @{ Value = '{0:N0}' -f $stats.Assignments; Caption = "assignments, $($stats.NotEnforced) not enforced"; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.NonCompliant; Caption = "non-compliant of $('{0:N0}' -f $stats.Resources)"; Color = $(if ($stats.NonCompliant) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.ExpiringExemptions; Caption = "exemptions expired or expiring ($($stats.Exemptions) in all)"; Color = $(if ($stats.ExpiringExemptions) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.High; Caption = 'high findings'; Color = $(if ($stats.High) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Medium; Caption = 'medium findings'; Color = $(if ($stats.Medium) { 'orange1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    $bars = @($Assessment.Subscriptions | Where-Object { $null -ne $_.CompliancePercent } | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Subscription; Value = $_.CompliancePercent } })
    if ($bars.Count) { Show-AACBarChart -Item $bars -Title 'Compliance by subscription (%), least compliant first'; [Spectre.Console.AnsiConsole]::WriteLine() }
    $bars = @($Assessment.Categories | Where-Object { $null -ne $_.CompliancePercent } | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Category; Value = $_.CompliancePercent } })
    if ($bars.Count) { Show-AACBarChart -Item $bars -Title 'Compliance by category (%)'; [Spectre.Console.AnsiConsole]::WriteLine() }

    $rows = @($Assessment.Assignments)
    if ($rows.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Assignments[/] [grey58]$($glyph.Dot) least compliant first$(if ($rows.Count -gt $Top) { ", $Top of $($rows.Count)" })[/]" @('Assignment', 'Scope', 'Assigns', 'Enforcement', 'Compliance', 'Non-compliant', 'Exemptions') @('Non-compliant', 'Exemptions')
        foreach ($row in $rows | Select-Object -First $Top) {
            & $addRow $table @(
                "[bold]$(& $escape $row.Assignment)[/]"
                "$(& $escape $row.Scope)`n[grey50]$(& $escape $row.ScopeType)[/]"
                "$(& $escape $row.Definition)`n[grey50]$(& $escape $row.Kind)$(if ($row.Kind -eq 'Initiative') { ", $($row.Policies) $(if ($row.Policies -eq 1) { 'policy' } else { 'policies' })" }) $($glyph.Dot) $(& $escape $row.PolicyType)[/]"
                $(if ($row.Enforcement -eq 'DoNotEnforce') { '[orange1]DoNotEnforce[/]' } else { '[grey70]Default[/]' })
                (& $percent $row.CompliancePercent $row.Rating)
                $(if ($row.NonCompliant) { "[orange1]$('{0:N0}' -f $row.NonCompliant)[/]" } else { '0' })
                "$($row.Exemptions)"
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    $attention = @($Assessment.Exemptions | Where-Object { $_.Status -in 'Expired', 'Expiring' })
    if ($attention.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Exemptions to look at[/] [grey58]$($glyph.Dot) expired or expiring soon[/]" @('Exemption', 'Assignment', 'Scope', 'Category', 'Expires', 'Status')
        foreach ($row in $attention | Select-Object -First $Top) {
            & $addRow $table @("[white]$(& $escape $row.Exemption)[/]", (& $escape $row.Assignment), (& $escape $row.Scope), (& $escape $row.Category), "$(& $escape $row.ExpiresOn)`n[grey50]$(if ($row.DaysLeft -lt 0) { "$(-$row.DaysLeft) days ago" } else { "in $($row.DaysLeft) days" })[/]", $(if ($row.Status -eq 'Expired') { '[red1]Expired[/]' } else { '[orange1]Expiring[/]' }))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    $serious = @($Assessment.Findings | Where-Object { $_.Severity -in 'High', 'Medium' })
    if ($serious.Count) {
        Write-AACMarkup "[bold]$($glyph.Bullet) Findings[/] [grey58]$($glyph.Dot) High and Medium, $($serious.Count) in all ($($stats.Low) low, $($stats.Info) info)[/]"
        foreach ($f in $serious | Select-Object -First 40) {
            Write-AACMarkup "  [$($color[$f.Severity])]$($f.Severity.ToUpperInvariant().PadRight(6))[/] [white]$(& $escape $f.Item)[/] [grey62]$(& $escape $f.Finding)[/] [grey42]$(& $escape $f.Area)$(if ($f.Scope) { " $($glyph.Dot) $(& $escape $f.Scope)" })[/]"
            Write-AACMarkup "         [grey85]$(& $escape $f.Detail)[/]"
            if ($f.Recommendation) { Write-AACMarkup "         [grey50]$($glyph.Arrow) $(& $escape $f.Recommendation)[/]" }
        }
        if ($serious.Count -gt 40) { Write-AACMarkup "  [grey50]... and $($serious.Count - 40) more: -HtmlPath has them all.[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    elseif (@($Assessment.Findings).Count) {
        Write-AACMarkup "[green3]$($glyph.Tick)[/] [grey70]No High or Medium findings; $($stats.Low) low and $($stats.Info) info - -HtmlPath has them.[/]"
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    Write-AACMarkup '[grey42]-HtmlPath has the management group tree, compliance by policy and every definition; -PassThru (or a pipe) returns the objects; -CsvPath writes a CSV per table.[/]'
}
