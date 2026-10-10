function Show-AACAdvisorSummary {
    <#
    .SYNOPSIS
        Renders the Spectre.Console summary Get-AACAdvisorRecommendation shows
        at the prompt: a title rule, the scope, and a row of tiles.
    .DESCRIPTION
        Layout:
          ── Azure Admin Console :: Azure Advisor ─────────────────────
          account · tenant · scope · filters · when
          ╭────────╮╭──────╮╭────────╮╭──────╮╭──────────╮╭────────────╮
          │  412   ││  37  ││  118   ││ 257  ││   298    ││ USD 6,738  │
          │ recs   ││ high ││ medium ││ low  ││resources ││ est./month │
          ╰────────╯╰──────╯╰────────╯╰──────╯╰──────────╯╰────────────╯

        Each tile's border and number take the tone of what it counts (high
        red, medium orange, savings green); a zero is drawn grey. Tiles wrap
        onto more lines in a narrow terminal. With no recommendations a
        single green panel says so instead of the tiles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Recommendation,

        [System.Collections.IDictionary] $Scope,

        # The command has already written the title, above its progress display.
        [switch] $NoTitle
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    # Unicode symbols, or ASCII in a console that isn't UTF-8.
    $glyph = Get-AACGlyph
    $count = $Recommendation.Count

    if (-not $NoTitle) {
        Write-AACRule -Title 'Azure Admin Console :: Azure Advisor' -Color 'deepskyblue3_1'
    }

    # The scope line: who, where, which filters, when.
    $facts = [System.Collections.Generic.List[string]]::new()
    $session = $script:AACSession
    if ($session) {
        $facts.Add("[white]$(& $escape $session.Account)[/]")
        $facts.Add("tenant $(& $escape $session.TenantId)")
    }
    # Get-AACAdvisorRecommendation's scope is worded for the PDF; here it is
    # shortened to fit one line.
    if ($Scope) {
        foreach ($key in $Scope.Keys) {
            $value = [string]$Scope[$key]
            switch ($key) {
                'Subscriptions' {
                    $ids = @($value -split ',\s*' | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' })
                    $facts.Add($(if ($ids) { "$($ids.Count) subscription$(if ($ids.Count -ne 1) { 's' })" } else { 'all subscriptions' }))
                }
                'Postponed / dismissed' {
                    if ($value -ne 'not included') { $facts.Add('incl. postponed / dismissed') }
                }
                default { $facts.Add("$(& $escape $key.ToLowerInvariant()): $(& $escape $value)") }
            }
        }
    }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    if ($count -eq 0) {
        Show-AACCallout Success -Message '[bold green]No Azure Advisor recommendations[/] [grey58]for this scope - nothing to act on.[/]'
    }
    else {
        $resources = @($Recommendation | ForEach-Object { if ($_.ResourceId) { $_.ResourceId.ToLowerInvariant() } else { $_.ResourceName } } | Select-Object -Unique).Count

        # Savings per currency, largest first; the tile shows the largest and
        # names any others underneath.
        $savings = @($Recommendation | Where-Object { $null -ne $_.MonthlySavings } |
                Group-Object -Property SavingsCurrency |
                ForEach-Object { [pscustomobject]@{ Currency = $(if ($_.Name) { $_.Name } else { '?' }); Total = ($_.Group | Measure-Object -Property MonthlySavings -Sum).Sum } } |
                Sort-Object -Property Total -Descending)
        $savingsValue = if ($savings) { '{0} {1:N0}' -f $savings[0].Currency, $savings[0].Total } else { '-' }
        $savingsCaption = if ($savings.Count -gt 1) {
            "est. / month (+ $(($savings | Select-Object -Skip 1 | ForEach-Object { '{0} {1:N0}' -f $_.Currency, $_.Total }) -join ' + '))"
        }
        elseif ($savings) { 'est. savings / month' }
        else { 'no savings estimates' }

        $impactCount = { param([string] $Level) @($Recommendation | Where-Object Impact -eq $Level).Count }
        $tiles = @(
            @{ Value = ('{0:N0}' -f $count); Caption = 'recommendations'; Color = 'deepskyblue3_1' }
            @{ Value = ('{0:N0}' -f (& $impactCount 'High')); Caption = 'high impact'; Color = 'red1' }
            @{ Value = ('{0:N0}' -f (& $impactCount 'Medium')); Caption = 'medium impact'; Color = 'orange1' }
            @{ Value = ('{0:N0}' -f (& $impactCount 'Low')); Caption = 'low impact'; Color = 'grey70' }
            @{ Value = ('{0:N0}' -f $resources); Caption = 'resources affected'; Color = 'mediumpurple2' }
            @{ Value = $savingsValue; Caption = $savingsCaption; Color = 'green3' }
        )

        Show-AACTileRow -Tile $tiles
    }

}
