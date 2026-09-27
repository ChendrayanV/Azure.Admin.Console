function Show-AACPSRuleView {
    <#
    .SYNOPSIS
        Renders Invoke-AACPSRule's results as a Spectre.Console view.
    .DESCRIPTION
        The account and scope, tiles (objects checked, rules, passed, failed,
        could not evaluate, pass rate), failures by Well-Architected pillar,
        then one table per pillar with each failing rule - most severe
        first, then most failures - its severity, name and title, how many
        resources failed, which (the first few) and why.

          ── Security · 14 rules failed on 32 resources ──────────────────────
          │ Severity  │ Rule                          │ Failed │ Resources        │
          │ Critical  │ Azure.Storage.MinTLS          │      3 │ stdev01, stlogs  │
          │           │ Use secure protocols for ...  │        │ Min TLS is 1.0   │

        Output goes straight to the Spectre console; wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [System.Collections.IDictionary] $Scope,

        [int] $Rules,

        [int] $Objects,

        [string[]] $Warning = @()
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $pillars = [ordered]@{
        'Security'               = 'indianred1'
        'Reliability'            = 'deepskyblue1'
        'Cost Optimization'      = 'green3'
        'Operational Excellence' = 'mediumpurple2'
        'Performance Efficiency' = 'gold1'
        'Other'                  = 'grey70'
    }
    $severityStyle = @{
        Critical  = '[bold white on red3] CRITICAL [/]'
        Important = '[bold black on orange1] IMPORTANT [/]'
        Awareness = '[black on grey70] AWARENESS [/]'
        Error     = '[bold white on red3] ERROR [/]'
        Warning   = '[bold black on orange1] WARNING [/]'
    }

    # The facts line.
    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) {
        $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]")
        $facts.Add("tenant $(& $escape $script:AACSession.TenantId)")
    }
    if ($Scope) {
        foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") }
    }
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    $passed = @($Result | Where-Object Outcome -EQ 'Pass').Count
    $failed = @($Result | Where-Object Outcome -EQ 'Fail')
    $errors = @($Result | Where-Object Outcome -EQ 'Error')
    $decided = $passed + $failed.Count
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $Objects; Caption = 'objects checked'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $Rules; Caption = 'rules'; Color = 'mediumpurple2' }
        @{ Value = '{0:N0}' -f $passed; Caption = 'passed'; Color = 'green3' }
        @{ Value = '{0:N0}' -f $failed.Count; Caption = 'failed'; Color = $(if ($failed.Count) { 'red3' } else { 'grey50' }) }
        @{ Value = '{0:N0}' -f $errors.Count; Caption = 'could not evaluate'; Color = $(if ($errors.Count) { 'orange1' } else { 'grey50' }) }
        @{ Value = $(if ($decided) { '{0:N1}%' -f (100 * $passed / $decided) } else { '-' }); Caption = 'pass rate'; Color = 'gold1' }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    foreach ($line in $Warning | Select-Object -First 5) {
        Write-AACMarkup "[orange1]![/] [grey58]$(& $escape $line)[/]"
    }
    if (@($Warning).Count -gt 5) { Write-AACMarkup "[grey58]  ... and $(@($Warning).Count - 5) more settings that could not be read[/]" }

    $problems = @($failed + $errors)
    if ($problems.Count -eq 0) {
        Show-AACPanel -Content $(if ($Result.Count) { '[bold green3]Every rule passed.[/]' } else { '[bold]No rule applied[/] [grey58]to the resources in scope.[/]' }) -BorderColor $(if ($Result.Count) { 'green3' } else { 'grey50' }) -AllowMarkup
        return
    }

    # Failures by pillar.
    $bars = @(foreach ($pillar in $pillars.Keys) {
            $n = @($problems | Where-Object Pillar -EQ $pillar).Count
            if ($n) { @{ Label = $pillar; Value = $n; Color = $pillars[$pillar] } }
        })
    Show-AACBarChart -Item $bars -Title 'Failed results by Well-Architected pillar'
    [Spectre.Console.AnsiConsole]::WriteLine()

    foreach ($pillar in $pillars.Keys) {
        $inPillar = @($problems | Where-Object Pillar -EQ $pillar)
        if ($inPillar.Count -eq 0) { continue }
        $color = $pillars[$pillar]
        # Most severe first, then the rules that fail most.
        $rank = @{ Critical = 0; Error = 0; Important = 1; Warning = 1; Awareness = 2 }
        $byRule = @($inPillar | Group-Object -Property RuleName | Sort-Object -Property @(
                @{ Expression = { $r = $rank[[string]$_.Group[0].Severity]; if ($null -eq $r) { 3 } else { $r } } }
                @{ Expression = 'Count'; Descending = $true }
                'Name'
            ))
        $resourceCount = @($inPillar | ForEach-Object { if ($_.ResourceId) { $_.ResourceId.ToLowerInvariant() } else { $_.ResourceName } } | Select-Object -Unique).Count

        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($color)
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new("[bold $color]$($glyph.Bullet) $(& $escape $pillar)[/] [grey58]$($glyph.Dot)[/] $($byRule.Count) rule$(if ($byRule.Count -ne 1) { 's' }) failed on $resourceCount resource$(if ($resourceCount -ne 1) { 's' })")
        foreach ($header in @(@('Severity', 12, $true), @('Rule', 0, $false), @('Failed', 7, $true), @('Resources and reasons', 0, $false))) {
            $column = [Spectre.Console.TableColumn]::new("[grey62]$($header[0])[/]")
            if ($header[1]) { $column.Width = $header[1] }
            $column.NoWrap = $header[2]
            if ($header[0] -eq 'Failed') { $column.Alignment = [Spectre.Console.Justify]::Right }
            $table.AddColumn($column) | Out-Null
        }
        foreach ($group in $byRule) {
            $first = $group.Group[0]
            $severity = if ($severityStyle.ContainsKey([string]$first.Severity)) { $severityStyle[[string]$first.Severity] } else { "[grey70]$(& $escape $first.Severity)[/]" }
            $ruleText = "[bold]$(& $escape $first.RuleName)[/]"
            if ($first.Title) { $ruleText += "`n[grey58]$(& $escape $first.Title)[/]" }
            if ($first.Source -ne 'PSRule for Azure') { $ruleText += "`n[italic mediumpurple2]$(& $escape $first.Source)[/]" }
            $shown = @($group.Group | Select-Object -First 3)
            $lines = @(foreach ($item in $shown) {
                    $mark = if ($item.Outcome -eq 'Error') { "[orange1]$($glyph.Bullet)[/] " } else { '' }
                    "$mark[white]$(& $escape $item.ResourceName)[/] [grey50]$(& $escape $item.ResourceGroup)[/]"
                    if ($item.Reason) { "  [grey58]$(& $escape ($item.Reason.Substring(0, [Math]::Min(110, $item.Reason.Length))))[/]" }
                })
            if ($group.Count -gt $shown.Count) { $lines += "[grey50]and $($group.Count - $shown.Count) more[/]" }
            $cells = @(
                [Spectre.Console.Markup]::new($severity)
                [Spectre.Console.Markup]::new($ruleText)
                [Spectre.Console.Markup]::new("[bold $color]$($group.Count)[/]")
                [Spectre.Console.Markup]::new(($lines -join "`n"))
            )
            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]$cells) | Out-Null
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
}
