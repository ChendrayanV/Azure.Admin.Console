function Show-AACDefenderAssessmentView {
    <#
    .SYNOPSIS
        Renders Invoke-AACDefenderAssessment's result as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (secure score, recommendations, attack paths, active
        alerts, vulnerabilities, plans, failed compliance controls); secure
        score by subscription; the subscriptions; the top recommendations by
        unhealthy resources; the attack paths; the active alerts; the plans
        that are off; and the Critical, High and Medium findings with what
        to do. Wrap the call in Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Scope,

        [int] $Top = 15
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Assessment.Stats
    $color = @{ Critical = 'red1'; High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1'; Informational = 'grey62' }
    $sev = { param([string] $Severity) if ($Severity) { "[$(if ($color.Contains($Severity)) { $color[$Severity] } else { 'grey62' })]$(& $escape $Severity)[/]" } else { '[grey50]-[/]' } }
    $scoreText = { param($Value) if ($null -eq $Value) { '[grey50]-[/]' } else { "[$(if ($Value -ge 70) { 'green3' } elseif ($Value -ge 40) { 'orange1' } else { 'red1' })]$Value%[/]" } }
    $newTable = {
        param([string] $TitleText, [string[]] $Headers, [string[]] $Right = @())
        $t = [Spectre.Console.Table]::new(); $t.Border = [Spectre.Console.TableBorder]::Rounded; $t.BorderStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1'); $t.Expand = $true
        if ($TitleText) { $t.Title = [Spectre.Console.TableTitle]::new($TitleText) }
        foreach ($header in $Headers) { $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]"); if ($header -in $Right) { $column.Alignment = [Spectre.Console.Justify]::Right }; $t.AddColumn($column) | Out-Null }
        $t
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }
    $title = { param([string] $Text, [string] $Note) "[bold]$($glyph.Bullet) $Text[/]$(if ($Note) { " [grey58]$($glyph.Dot) $Note[/]" })" }
    $write = { param($Table) [Spectre.Console.AnsiConsole]::Write($Table); [Spectre.Console.AnsiConsole]::WriteLine() }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    foreach ($line in @($Assessment.Notices)) { Write-AACMarkup "[orange1]$(& $escape $line)[/]" }
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { '-' }); Caption = 'secure score'; Color = $(if ($null -eq $stats.SecureScore) { 'grey50' } elseif ($stats.SecureScore -ge 70) { 'green3' } elseif ($stats.SecureScore -ge 40) { 'orange1' } else { 'red1' }) }
        @{ Value = '{0:N0}' -f $stats.Recommendations; Caption = "recommendations ($($stats.HighRecommendations) High)"; Color = $(if ($stats.HighRecommendations) { 'red1' } else { 'orange1' }) }
        @{ Value = '{0:N0}' -f $stats.AttackPaths; Caption = "attack paths ($($stats.CriticalAttackPaths) Critical/High)"; Color = $(if ($stats.CriticalAttackPaths) { 'red1' } elseif ($stats.AttackPaths) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.ActiveAlerts; Caption = "active alerts ($($stats.HighAlerts) High)"; Color = $(if ($stats.HighAlerts) { 'red1' } elseif ($stats.ActiveAlerts) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Vulnerabilities; Caption = "vulnerabilities ($($stats.HighVulnerabilities) High+)"; Color = $(if ($stats.HighVulnerabilities) { 'red1' } elseif ($stats.Vulnerabilities) { 'orange1' } else { 'green3' }) }
        @{ Value = "$($stats.PlansOn)/$($stats.PlansOn + $stats.PlansOff)"; Caption = 'Defender plans on'; Color = $(if ($stats.PlansOff) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.FailedControls; Caption = 'failed compliance controls'; Color = $(if ($stats.FailedControls) { 'orange1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    $subs = @($Assessment.Subscriptions)
    if ($subs.Count) {
        $table = & $newTable (& $title 'Subscriptions' 'lowest secure score first') @('Subscription', 'Score', 'Plans on', 'Unhealthy', 'High', 'Attack paths', 'Alerts', 'Findings') @('Plans on', 'Unhealthy', 'High', 'Attack paths', 'Alerts', 'Findings')
        foreach ($s in $subs | Select-Object -First $Top) { & $addRow $table @("[bold]$(& $escape $s.Subscription)[/]", (& $scoreText $s.SecureScore), "$($s.PlansOn)/$($s.Plans)", "$($s.UnhealthyResources)", $(if ($s.HighRecommendations) { "[red1]$($s.HighRecommendations)[/]" } else { '0' }), "$($s.AttackPaths)", "$($s.ActiveAlerts)", "$($s.Findings)") }
        & $write $table
    }

    $recs = @($Assessment.Recommendations | Where-Object UnhealthyResources)
    if ($recs.Count) {
        $table = & $newTable (& $title 'Recommendations' "highest risk first$(if ($recs.Count -gt $Top) { ", $Top of $($recs.Count)" })") @('Recommendation', 'Severity', 'Risk', 'Unhealthy', 'Healthy', 'Control') @('Unhealthy', 'Healthy')
        foreach ($r in $recs | Select-Object -First $Top) { & $addRow $table @("[white]$(& $escape $r.Recommendation)[/]", (& $sev $r.Severity), (& $sev $r.RiskLevel), "[orange1]$($r.UnhealthyResources)[/]", "$($r.HealthyResources)", "[grey70]$(& $escape $r.Control)[/]") }
        & $write $table
    }

    $paths = @($Assessment.AttackPaths)
    if ($paths.Count) {
        $table = & $newTable (& $title 'Attack paths' "$($paths.Count) in all") @('Attack path', 'Risk', 'Path')
        foreach ($p in $paths | Select-Object -First $Top) { & $addRow $table @("[white]$(& $escape $p.AttackPath)[/]", (& $sev $p.RiskLevel), "[grey85]$(& $escape ($p.Path -replace ' → ', " $($glyph.Arrow) "))[/]") }
        & $write $table
    }

    $active = @($Assessment.Alerts | Where-Object Active -EQ 'Yes')
    if ($active.Count) {
        $table = & $newTable (& $title 'Active alerts' "$($active.Count) active, most severe first") @('Alert', 'Severity', 'Resource', 'Tactics', 'Age') @('Age')
        foreach ($al in $active | Select-Object -First $Top) { & $addRow $table @("[white]$(& $escape $al.Alert)[/]", (& $sev $al.Severity), (& $escape $al.Resource), "[grey70]$(& $escape $al.Tactics)[/]", "$($al.AgeDays)d") }
        & $write $table
    }

    $off = @($Assessment.Plans | Where-Object State -EQ 'Off')
    if ($off.Count) {
        $table = & $newTable (& $title 'Defender plans off' 'with the resources each would protect') @('Subscription', 'Plan', 'Resources') @('Resources')
        foreach ($p in $off | Sort-Object Resources -Descending | Select-Object -First $Top) { & $addRow $table @((& $escape $p.SubscriptionName), "[white]$(& $escape $p.Plan)[/]", $(if ($p.Resources) { "[orange1]$($p.Resources)[/]" } else { '[grey50]0[/]' })) }
        & $write $table
    }

    $serious = @($Assessment.Findings | Where-Object { $_.Severity -in 'Critical', 'High', 'Medium' })
    if ($serious.Count) {
        Write-AACMarkup (& $title 'Findings' "Critical, High and Medium: $($serious.Count) ($($stats.Low) low)")
        foreach ($f in $serious | Select-Object -First 30) {
            Write-AACMarkup "  [$($color[$f.Severity])]$($f.Severity.ToUpperInvariant().PadRight(8))[/] [white]$(& $escape $f.Finding)[/] [grey62]$(& $escape $f.Item)[/] [grey42]$(& $escape $f.Area)$(if ($f.SubscriptionName) { " $($glyph.Dot) $(& $escape $f.SubscriptionName)" })[/]"
            Write-AACMarkup "           [grey85]$(& $escape $f.Detail)[/]"
            if ($f.Recommendation) { Write-AACMarkup "           [grey50]$($glyph.Arrow) $(& $escape $f.Recommendation)[/]" }
        }
        if ($serious.Count -gt 30) { Write-AACMarkup "  [grey50]... and $($serious.Count - 30) more: -HtmlPath has them all.[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    Write-AACMarkup '[grey42]-HtmlPath writes the tabbed report (every recommendation, resource, alert, vulnerability, compliance control and setting, with row details); -CsvPath a CSV per table; -PassThru (or a pipe) returns the object.[/]'
}
