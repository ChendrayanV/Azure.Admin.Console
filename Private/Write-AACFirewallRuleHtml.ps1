function Write-AACFirewallRuleHtml {
    <#
    .SYNOPSIS
        Writes Get-AACFirewallRule's -HtmlPath report: tiles for rules,
        Allow, Deny, DNAT, policies and Allow rules open to any address;
        charts by action, policy, rule collection and rule type; and every
        rule in one interactive table, grouped by rule collection.
    .DESCRIPTION
        Sources and destinations are shown as one column each (addresses,
        IP Groups, FQDNs, FQDN tags, web categories, URLs); the separate
        properties are in the CSV download. The Exposure column flags Allow
        rules open to any source or any destination ('*', 0.0.0.0/0),
        and the CSV download says which.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Rule,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Azure Firewall rules',

        [System.Collections.IDictionary] $Detail
    )

    $join = { param([string[]] $Values) (@($Values) | Where-Object { $_ }) -join '; ' }
    $isAny = { param([string] $Value) @(($Value -split ',\s*') | Where-Object { $_ -eq '*' -or $_ -eq '0.0.0.0/0' -or $_ -eq 'Any' }).Count -gt 0 }

    $rows = @(foreach ($item in $Rule) {
            $anySource = [string]$item.Action -eq 'Allow' -and (& $isAny $item.SourceAddresses)
            $anyDestination = [string]$item.Action -eq 'Allow' -and (& $isAny $item.DestinationAddresses)
            [ordered]@{
                FirewallPolicy       = $item.FirewallPolicy
                FirewallPolicyId     = $item.FirewallPolicyId
                RuleCollectionGroup  = $item.RuleCollectionGroup
                RuleCollection       = "$($item.RuleCollection) ($($item.RuleCollectionPriority))"
                Priority             = $item.RuleCollectionPriority
                Action               = $item.Action
                RuleName             = $item.RuleName
                RuleType             = ([string]$item.RuleType) -replace 'Rule$', ''
                Sources              = & $join @($item.SourceAddresses, $(if ($item.SourceIpGroups) { "IP Groups: $($item.SourceIpGroupAddresses)" }))
                Destinations         = & $join @($item.DestinationAddresses, $(if ($item.DestinationIpGroups) { "IP Groups: $($item.DestinationIpGroupAddresses)" }), $item.DestinationFqdns, $item.TargetFqdns, $item.TargetUrls, $(if ($item.FqdnTags) { "FQDN tags: $($item.FqdnTags)" }), $(if ($item.WebCategories) { "Web categories: $($item.WebCategories)" }))
                Protocols            = $item.Protocols
                DestinationPorts     = $item.DestinationPorts
                Translated           = & $join @($item.TranslatedAddress, $item.TranslatedFqdn, $(if ($item.TranslatedPort) { "port $($item.TranslatedPort)" }))
                Exposure             = if ($anySource -or $anyDestination) { 'Open to any' } else { '' }
                ExposureDetail       = if ($anySource -and $anyDestination) { 'any source to any destination' } elseif ($anySource) { 'any source' } elseif ($anyDestination) { 'any destination' } else { '' }
                Description          = $item.Description
                SubscriptionName     = $item.SubscriptionName
                ResourceGroup        = $item.ResourceGroup
                Location             = $item.Location
                BasePolicy           = $item.BasePolicy
                Firewalls            = $item.Firewalls
                TerminateTls         = $item.TerminateTls
            }
        })

    $count = { param([scriptblock] $Where) @($rows | Where-Object $Where).Count }
    $open = & $count { $_.Exposure }
    $tiles = @(
        @{ Value = '{0:N0}' -f $rows.Count; Label = 'rules'; Tone = 'info'; Table = 'rules' }
        @{ Value = '{0:N0}' -f (& $count { $_.Action -eq 'Allow' }); Label = 'allow'; Tone = 'good'; Table = 'rules'; Filters = @{ Action = 'Allow' } }
        @{ Value = '{0:N0}' -f (& $count { $_.Action -eq 'Deny' }); Label = 'deny'; Tone = 'bad'; Table = 'rules'; Filters = @{ Action = 'Deny' } }
        @{ Value = '{0:N0}' -f (& $count { $_.Action -eq 'DNAT' }); Label = 'DNAT'; Tone = 'warn'; Table = 'rules'; Filters = @{ Action = 'DNAT' } }
        @{ Value = '{0:N0}' -f @($rows | ForEach-Object { $_.FirewallPolicyId } | Select-Object -Unique).Count; Label = 'policies'; Tone = 'violet' }
        $(if ($open) { @{ Value = '{0:N0}' -f $open; Label = 'allow rules open to any address'; Tone = 'bad'; Table = 'rules'; Filters = @{ Exposure = 'Open to any' } } })
    ) | Where-Object { $_ }

    $top = {
        param([string] $Property, [int] $First = 10)
        @($rows | Group-Object -Property { $_[$Property] } | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object {
                @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count }
            })
    }
    $byAction = @(foreach ($action in 'Allow', 'Deny', 'DNAT') {
            $n = & $count { $_.Action -eq $action }
            if ($n) { @{ Label = $action; Value = $n; Tone = @{ Allow = 'good'; Deny = 'bad'; DNAT = 'warn' }[$action] } }
        })
    $charts = @(
        @{ Title = 'By action'; Items = $byAction; Table = 'rules'; Column = 'Action' }
        @{ Title = 'By policy'; Items = @(& $top 'FirewallPolicy'); Table = 'rules'; Column = 'FirewallPolicy'; Tone = 'violet' }
        @{ Title = 'Largest rule collections'; Items = @(& $top 'RuleCollection'); Table = 'rules'; Column = 'RuleCollection' }
        @{ Title = 'By rule type'; Items = @(& $top 'RuleType'); Table = 'rules'; Column = 'RuleType'; Tone = 'neutral' }
    )

    $table = @{
        Id      = 'rules'
        Title   = 'Rules'
        Note    = 'In priority order. Allow rules open to any source or destination are flagged under Exposure.'
        Noun    = 'rules'
        File    = 'FirewallRules'
        Rows    = $rows
        Group   = 'RuleCollection'
        GroupBy = @('RuleCollection', 'RuleCollectionGroup', 'FirewallPolicy', 'Action', 'RuleType')
        Columns = @(
            @{ Key = 'Action'; Label = 'Action'; Type = 'badge'; Facet = $true; Tones = @{ Allow = 'good'; Deny = 'bad'; DNAT = 'warn' } }
            @{ Key = 'RuleName'; Label = 'Rule'; Nowrap = $true }
            @{ Key = 'RuleType'; Label = 'Type'; Facet = $true }
            @{ Key = 'Sources'; Label = 'Sources'; Type = 'mono' }
            @{ Key = 'Destinations'; Label = 'Destinations'; Type = 'mono' }
            @{ Key = 'Protocols'; Label = 'Protocols'; Nowrap = $true }
            @{ Key = 'DestinationPorts'; Label = 'Ports'; Type = 'mono' }
            @{ Key = 'Translated'; Label = 'Translated to'; Type = 'mono' }
            @{ Key = 'Exposure'; Label = 'Exposure'; Type = 'badge'; Facet = $true; Tones = @{ 'Open to any' = 'bad' } }
            @{ Key = 'ExposureDetail'; Label = 'Open to'; Hidden = $true }
            @{ Key = 'RuleCollection'; Label = 'Rule collection'; Facet = $true; Nowrap = $true }
            @{ Key = 'RuleCollectionGroup'; Label = 'Collection group'; Facet = $true }
            @{ Key = 'FirewallPolicy'; Label = 'Policy'; Type = 'resource'; IdKey = 'FirewallPolicyId'; Facet = $true }
            @{ Key = 'Description'; Label = 'Description'; Type = 'wide' }
            @{ Key = 'Priority'; Label = 'Collection priority'; Type = 'number'; Hidden = $true }
            @{ Key = 'SubscriptionName'; Label = 'Subscription'; Hidden = $true }
            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Hidden = $true }
            @{ Key = 'Location'; Label = 'Location'; Hidden = $true }
            @{ Key = 'BasePolicy'; Label = 'Base policy'; Hidden = $true }
            @{ Key = 'Firewalls'; Label = 'Firewalls'; Hidden = $true }
            @{ Key = 'TerminateTls'; Label = 'Terminate TLS'; Hidden = $true }
        )
    }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle "$('{0:N0}' -f $rows.Count) rules in $('{0:N0}' -f @($rows | ForEach-Object { $_.FirewallPolicyId } | Select-Object -Unique).Count) policies" -Fact $Detail -Tile $tiles -Chart $charts -Table @($table)
}
