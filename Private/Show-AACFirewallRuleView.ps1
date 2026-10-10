function Show-AACFirewallRuleView {
    <#
    .SYNOPSIS
        Renders AAC.FirewallRule objects (from Get-AACFirewallRule) as the
        Spectre.Console view shown at the prompt.
    .DESCRIPTION
        Layout, following the policy hierarchy:

          ── Azure Admin Console :: Azure Firewall ──────────────────────
          account · tenant · scope · filters · when
          [ rules ] [ allow ] [ deny ] [ DNAT ] [ policies ] [ collections ]

          Firewall policies: one row per policy - base policy, attached
          firewalls, where it lives and its rule counts.

          ── fwpol-hub ── base: fwpol-base · firewalls: afw-hub ─────────
          ╭ rcg-platform · 100 › Allow-Web · 200 · Filter   ALLOW ─────╮   <- green
          │ # │ Rule       │ Source │ Destination │ Protocols │ Extra   │
          ╰───────────────────────────────────────────────────────────────╯
          ╭ rcg-platform · 100 › Block-Legacy · 300 · Filter  DENY ────╮   <- red

        Each rule collection is one table, in priority order. Its border and
        badge carry the action: Allow in green, Deny in red, DNAT in orange.
        IP Groups are shown by name with their addresses under them in grey,
        and an Allow rule open to any source or destination ('*') has the
        '*' called out in yellow. The last column holds the DNAT
        translation, or the TLS inspection setting of application rules.

        Output goes straight to the Spectre console, so wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Rule,

        [System.Collections.IDictionary] $Scope,

        # The command has already written the title, above its progress display.
        [switch] $NoTitle
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    # Unicode symbols, or ASCII in a console that isn't UTF-8.
    $glyph = Get-AACGlyph
    $actionStyle = @{
        Allow = @{ Color = 'green3'; Badge = '[bold white on green4] ALLOW [/]' }
        Deny  = @{ Color = 'red1'; Badge = '[bold white on red3] DENY [/]' }
        DNAT  = @{ Color = 'orange1'; Badge = '[bold black on orange1] DNAT [/]' }
    }
    $styleOf = { param([string] $Action) $s = $actionStyle[$Action]; if ($s) { $s } else { @{ Color = 'grey70'; Badge = "[black on grey70] $(& $escape $Action.ToUpperInvariant()) [/]" } } }
    $unique = { param([string] $Property) @($Rule | ForEach-Object { "$($_.FirewallPolicyId)|$($_.$Property)" } | Select-Object -Unique).Count }

    # --- Header -------------------------------------------------------------------------
    if (-not $NoTitle) {
        Write-AACRule -Title 'Azure Admin Console :: Azure Firewall' -Color 'deepskyblue3_1'
    }
    $facts = [System.Collections.Generic.List[string]]::new()
    $session = $script:AACSession
    if ($session) {
        $facts.Add("[white]$(& $escape $session.Account)[/]")
        $facts.Add("tenant $(& $escape $session.TenantId)")
    }
    if ($Scope) {
        foreach ($key in $Scope.Keys) {
            $value = [string]$Scope[$key]
            if ($key -eq 'Subscriptions') {
                $ids = @($value -split ',\s*' | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' })
                $facts.Add($(if ($ids) { "$($ids.Count) subscription$(if ($ids.Count -ne 1) { 's' })" } else { 'all subscriptions' }))
            }
            else {
                $facts.Add("$(& $escape $key.ToLowerInvariant()): $(& $escape $value)")
            }
        }
    }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    if ($Rule.Count -eq 0) {
        Show-AACCallout Info -Message '[bold]No Firewall Policy rules[/] [grey58]were found for this account and these filters.[/]'
        return
    }

    $policies = @($Rule | Group-Object -Property FirewallPolicyId | Sort-Object { $_.Group[0].FirewallPolicy })
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $Rule.Count; Caption = 'rules'; Color = 'deepskyblue3_1' }
        @{ Value = '{0:N0}' -f @($Rule | Where-Object Action -eq 'Allow').Count; Caption = 'allow'; Color = 'green3' }
        @{ Value = '{0:N0}' -f @($Rule | Where-Object Action -eq 'Deny').Count; Caption = 'deny'; Color = 'red1' }
        @{ Value = '{0:N0}' -f @($Rule | Where-Object RuleType -eq 'NatRule').Count; Caption = 'DNAT'; Color = 'orange1' }
        @{ Value = '{0:N0}' -f $policies.Count; Caption = 'policies'; Color = 'mediumpurple2' }
        @{ Value = '{0:N0}' -f (& $unique 'RuleCollection'); Caption = 'rule collections'; Color = 'grey70' }
    )

    # --- Policies ----------------------------------------------------------------------------
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
    $table.Expand = $true
    $table.Title = [Spectre.Console.TableTitle]::new('[bold]Firewall policies[/]')
    foreach ($header in 'Policy', 'Base policy', 'Firewalls', 'Subscription / resource group', 'DNAT', 'Network', 'App', 'Allow', 'Deny') {
        $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
        if ($header -in 'DNAT', 'Network', 'App', 'Allow', 'Deny') {
            $column.Alignment = [Spectre.Console.Justify]::Right
            $column.NoWrap = $true
        }
        $table.AddColumn($column) | Out-Null
    }
    $count = {
        param($Items, [string] $Color)
        $n = @($Items).Count
        if ($n -eq 0) { '[grey42]0[/]' } else { "[$Color]$('{0:N0}' -f $n)[/]" }
    }
    foreach ($policy in $policies) {
        $first = $policy.Group[0]
        $where = "$(if ($first.SubscriptionName) { $first.SubscriptionName } else { $first.SubscriptionId }) $($glyph.Dot) $($first.ResourceGroup)"
        [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@(
                [Spectre.Console.Markup]::new("[bold]$(& $escape $first.FirewallPolicy)[/]")
                [Spectre.Console.Markup]::new($(if ($first.BasePolicy) { & $escape $first.BasePolicy } else { '[grey42]-[/]' }))
                [Spectre.Console.Markup]::new($(if ($first.Firewalls) { & $escape $first.Firewalls } else { '[grey42]not attached[/]' }))
                [Spectre.Console.Markup]::new("[grey70]$(& $escape $where)[/]")
                [Spectre.Console.Markup]::new((& $count @($policy.Group | Where-Object RuleType -eq 'NatRule') 'orange1'))
                [Spectre.Console.Markup]::new((& $count @($policy.Group | Where-Object RuleType -eq 'NetworkRule') 'white'))
                [Spectre.Console.Markup]::new((& $count @($policy.Group | Where-Object RuleType -eq 'ApplicationRule') 'white'))
                [Spectre.Console.Markup]::new((& $count @($policy.Group | Where-Object Action -eq 'Allow') 'green3'))
                [Spectre.Console.Markup]::new((& $count @($policy.Group | Where-Object Action -eq 'Deny') 'red1'))
            )) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::WriteLine()
    [Spectre.Console.AnsiConsole]::Write($table)

    # --- Rules, policy by policy ---------------------------------------------------------------
    # A list of values, one per line; '*' on an Allow rule is called out.
    $lines = {
        param([string] $Values, [string] $Label, [bool] $FlagAny)
        foreach ($value in @($Values -split ',\s*' | Where-Object { $_ })) {
            $text = if ($FlagAny -and $value -eq '*') { '[bold yellow]* (any)[/]' } else { & $escape $value }
            if ($Label) { "[grey50]$Label[/] $text" } else { $text }
        }
    }
    # IP Groups, from "name: a, b | name2: c": the name, then its addresses in grey.
    $ipGroups = {
        param([string] $Described)
        foreach ($entry in @($Described -split ' \| ' | Where-Object { $_ })) {
            $name, $addresses = $entry -split ': ', 2
            "[deepskyblue1]$(& $escape $name)[/] [grey50](IP group)[/]"
            if ($addresses) { "[grey50]$(& $escape $addresses)[/]" }
        }
    }
    $cell = { param($Lines) [Spectre.Console.Markup]::new($(if (@($Lines).Count) { @($Lines) -join "`n" } else { '[grey42]-[/]' })) }

    foreach ($policy in $policies) {
        $first = $policy.Group[0]
        $about = @(
            if ($first.BasePolicy) { "base: $($first.BasePolicy)" }
            "firewalls: $(if ($first.Firewalls) { $first.Firewalls } else { 'not attached' })"
        ) -join " $($glyph.Dot) "
        [Spectre.Console.AnsiConsole]::WriteLine()
        Write-AACRule -Title "[bold]$(& $escape $first.FirewallPolicy)[/] [grey58]$(& $escape $about)[/]" -Color 'mediumpurple2'

        $collections = @($policy.Group | Group-Object -Property RuleCollectionGroup, RuleCollection | Sort-Object { $_.Group[0].RuleCollectionGroupPriority }, { $_.Group[0].RuleCollectionPriority }, Name)
        foreach ($collection in $collections) {
            $info = $collection.Group[0]
            $style = & $styleOf ([string]$info.Action)
            $isAllow = $info.Action -eq 'Allow'

            $table = [Spectre.Console.Table]::new()
            $table.Border = [Spectre.Console.TableBorder]::Rounded
            $table.BorderStyle = [Spectre.Console.Style]::Parse($style.Color)
            $table.Title = [Spectre.Console.TableTitle]::new(
                "[grey58]$(& $escape $info.RuleCollectionGroup) $($glyph.Dot) $($info.RuleCollectionGroupPriority) $($glyph.Chevron)[/] [bold]$(& $escape $info.RuleCollection)[/] [grey58]$($glyph.Dot) $($info.RuleCollectionPriority) $($glyph.Dot) $(& $escape $info.RuleCollectionType) $($glyph.Dot) $($collection.Count) rule$(if ($collection.Count -ne 1) { 's' })[/]  $($style.Badge)")
            # A line between rules, and the same column widths in every table
            # so they line up down the page: shares of the terminal width,
            # less the borders and padding (16 characters for 5 columns).
            $table.ShowRowSeparators = $true
            $table.Expand = $false
            $available = [Math]::Max(80, [Spectre.Console.AnsiConsole]::Profile.Width) - 16
            foreach ($column in @(@('Rule', 0.20), @('Source', 0.23), @('Destination', 0.25), @('Protocols / ports', 0.15), @('Translation / TLS', 0.17))) {
                $tableColumn = [Spectre.Console.TableColumn]::new("[grey62]$($column[0])[/]")
                $tableColumn.Width = [int][Math]::Floor($available * $column[1])
                $table.AddColumn($tableColumn) | Out-Null
            }

            foreach ($item in $collection.Group) {
                $kind = ([string]$item.RuleType -replace 'Rule$', '' -replace '^Nat$', 'DNAT').ToLowerInvariant()
                $ruleLines = @(
                    "[bold]$(& $escape $item.RuleName)[/]"
                    "[grey50]$kind rule[/]"
                    if ($item.Description) { "[grey50 italic]$(& $escape $item.Description)[/]" }
                )
                $source = @(
                    & $lines $item.SourceAddresses '' $isAllow
                    & $ipGroups $item.SourceIpGroupAddresses
                )
                $destination = @(
                    & $lines $item.DestinationAddresses '' $isAllow
                    & $ipGroups $item.DestinationIpGroupAddresses
                    & $lines $item.DestinationFqdns 'fqdn' $isAllow
                    & $lines $item.TargetFqdns 'fqdn' $isAllow
                    & $lines $item.TargetUrls 'url' $false
                    & $lines $item.FqdnTags 'tag' $false
                    & $lines $item.WebCategories 'category' $false
                )
                $protocols = @(
                    & $lines $item.Protocols '' $false
                    if ($item.DestinationPorts) { "[grey50]ports[/] $(& $escape $item.DestinationPorts)" }
                )
                $extra = @(
                    if ($item.RuleType -eq 'NatRule') {
                        $target = if ($item.TranslatedFqdn) { $item.TranslatedFqdn } else { $item.TranslatedAddress }
                        "[orange1]$($glyph.Arrow) $(& $escape $target)$(if ($item.TranslatedPort) { ":$(& $escape $item.TranslatedPort)" })[/]"
                    }
                    elseif ($item.RuleType -eq 'ApplicationRule') {
                        if ($item.TerminateTls) { '[green3]TLS inspection on[/]' } else { '[grey50]TLS inspection off[/]' }
                    }
                )
                [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@(
                        (& $cell $ruleLines), (& $cell $source), (& $cell $destination), (& $cell $protocols), (& $cell $extra)
                    )) | Out-Null
            }
            [Spectre.Console.AnsiConsole]::WriteLine()
            [Spectre.Console.AnsiConsole]::Write($table)
        }
    }
}
