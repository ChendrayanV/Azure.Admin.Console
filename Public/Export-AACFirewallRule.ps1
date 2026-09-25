function Export-AACFirewallRule {
    <#
    .SYNOPSIS
        Exports every Azure Firewall Policy rule - DNAT, network and
        application - as PowerShell objects, a CSV file and/or a PDF report.
    .DESCRIPTION
        Reads the rules of every Azure Firewall Policy the signed-in account
        can see (or only those in -SubscriptionId / -FirewallPolicyName) from
        Azure Resource Graph, over REST with the Connect-AAC sign-in - no Az
        modules needed. One object is returned per rule, sorted as the Azure
        portal lists them: by policy, rule collection group priority, rule
        collection priority, then the rule's position in its collection.
        (Azure Firewall itself applies all DNAT rules first, then network,
        then application rules, each in that priority order, and a base
        policy's rules before the policy's own.)

        IP Groups used as a source or destination are resolved to their names
        and addresses, wherever in the tenant they live (one Resource Graph
        query, no per-group calls). Each rule also carries its policy's base
        (parent) policy and the firewalls the policy is attached to.

        Output:
          (no path)   the rules as AAC.FirewallRule objects, e.g. to filter
                      with Where-Object or pipe to Export-Csv yourself
          -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
                      rule, list values joined with ", ")
          -PdfPath    a landscape A4 PDF: a summary of each policy, then every
                      rule grouped by policy, rule collection group and rule
                      collection, with source, destination, protocols, ports
                      and DNAT translation

        With -CsvPath or -PdfPath the rule objects are only returned when
        -PassThru is also given. Both paths can be used in one run.

        Only Firewall Policy rules are exported. Classic rules configured
        directly on a firewall (without a policy) are not included. Rules a
        policy inherits from its base policy appear under the base policy.

        PDF export needs Windows and PowerShell 7.4 or later (see
        Export-AACPesterReport); objects and CSV work everywhere.
    .PARAMETER SubscriptionId
        Only export policies in these subscriptions. Defaults to every
        subscription the signed-in account can see. IP Groups and base
        policies are resolved in every subscription either way.
    .PARAMETER FirewallPolicyName
        Only export policies whose name matches one of these wildcard
        patterns (case-insensitive), e.g. 'fwpol-hub-*'.
    .PARAMETER CsvPath
        Write the rules to this CSV file. An existing file is overwritten;
        missing folders are created.
    .PARAMETER PdfPath
        Write the rules to this PDF file. An existing file is overwritten;
        missing folders are created.
    .PARAMETER Title
        The PDF's title. Defaults to 'Azure Firewall rules'.
    .PARAMETER PassThru
        With -CsvPath or -PdfPath, also return the rule objects.
    .EXAMPLE
        Connect-AAC
        Export-AACFirewallRule -CsvPath .\out\FirewallRules.csv -PdfPath .\out\FirewallRules.pdf
        Writes every Firewall Policy rule you can see to a CSV file and a PDF report.
    .EXAMPLE
        Export-AACFirewallRule -SubscriptionId '00000000-0000-0000-0000-000000000000' |
            Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' } |
            Format-Table FirewallPolicy, RuleCollection, RuleName, DestinationPorts
        Lists allow rules open to any source in one subscription.
    .EXAMPLE
        Export-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' -PdfPath .\HubFirewall.pdf -Title 'Hub firewall rules'
        A PDF of the hub firewall policies only.
    .EXAMPLE
        Export-AACFirewallRule | Export-Csv -Path .\rules.csv -NoTypeInformation -Delimiter ';'
        Uses Export-Csv directly, for control over its options.
    .OUTPUTS
        AAC.FirewallRule (without -CsvPath/-PdfPath, or with -PassThru)
    #>
    [CmdletBinding()]
    [OutputType('AAC.FirewallRule')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [SupportsWildcards()]
        [string[]] $FirewallPolicyName,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $Title = 'Azure Firewall rules',

        [switch] $PassThru
    )

    # Resolve paths now, relative to the caller's location, so a bad path
    # fails before any Azure call.
    $csvFullPath = if ($CsvPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath) }
    $pdfFullPath = if ($PdfPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PdfPath) }

    $headers = @{ Authorization = "Bearer $(Get-AACAccessToken)" }

    $ruleQuery = @'
networkresources
| where type =~ 'microsoft.network/firewallpolicies/rulecollectiongroups'
| extend firewallPolicyId = tolower(substring(id, 0, indexof(tolower(id), '/rulecollectiongroups/')))
| mv-expand ruleCollection = properties.ruleCollections
| mv-expand with_itemindex = ruleIndex rule = ruleCollection.rules
| project subscriptionId, resourceGroup, location, firewallPolicyId,
    ruleCollectionGroupId = id,
    ruleCollectionGroup = name,
    ruleCollectionGroupPriority = toint(properties.priority),
    ruleCollection = tostring(ruleCollection.name),
    ruleCollectionPriority = toint(ruleCollection.priority),
    ruleCollectionType = tostring(ruleCollection.ruleCollectionType),
    action = tostring(ruleCollection.action.type),
    ruleIndex, rule
'@
    $policyQuery = @'
resources
| where type =~ 'microsoft.network/firewallpolicies'
| project id = tolower(id), name, basePolicyId = tolower(tostring(properties.basePolicy.id)), firewalls = properties.firewalls, tier = tostring(properties.sku.tier)
'@
    $ipGroupQuery = @'
resources
| where type =~ 'microsoft.network/ipgroups'
| project id = tolower(id), name, addresses = properties.ipAddresses
'@
    $subscriptionQuery = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"

    $data = Invoke-AACStatus -Title 'Reading firewall policies from Azure Resource Graph' -Spinner 'Dots' -ScriptBlock {
        @{
            Rules         = @(Invoke-AACResourceGraphQuery -SubscriptionId $SubscriptionId -Headers $headers -Query $ruleQuery)
            # Base policies, IP Groups and subscription names can live in any
            # subscription, so these three are read tenant-wide.
            Policies      = @(Invoke-AACResourceGraphQuery -Headers $headers -Query $policyQuery)
            IpGroups      = @(Invoke-AACResourceGraphQuery -Headers $headers -Query $ipGroupQuery)
            Subscriptions = @(Invoke-AACResourceGraphQuery -Headers $headers -Query $subscriptionQuery)
        }
    }

    $lastSegment = { param([string] $Id) if ($Id) { $Id.TrimEnd('/').Split('/')[-1] } }
    $join = { param($Values) (@($Values) | Where-Object { $null -ne $_ -and "$_" -ne '' }) -join ', ' }

    $policies = @{}
    foreach ($policy in $data.Policies) {
        $policies[$policy.id] = $policy
    }
    $ipGroups = @{}
    foreach ($ipGroup in $data.IpGroups) {
        $ipGroups[$ipGroup.id] = $ipGroup
    }
    $subscriptionNames = @{}
    foreach ($subscription in $data.Subscriptions) {
        $subscriptionNames[$subscription.subscriptionId] = $subscription.name
    }

    # IP Group IDs -> "name" list and "name: address, address" list. An IP
    # Group the account can't read is shown by the name in its ID.
    $describeIpGroups = {
        param($Ids)
        $names = [System.Collections.Generic.List[string]]::new()
        $addresses = [System.Collections.Generic.List[string]]::new()
        foreach ($id in @($Ids | Where-Object { $_ })) {
            $ipGroup = $ipGroups[([string]$id).ToLowerInvariant()]
            if ($ipGroup) {
                $names.Add($ipGroup.name)
                $addresses.Add("$($ipGroup.name): $(& $join $ipGroup.addresses)")
            }
            else {
                $name = & $lastSegment $id
                $names.Add($name)
                $addresses.Add("${name}: (not readable)")
            }
        }
        @{ Names = $names -join ', '; Addresses = $addresses -join ' | ' }
    }

    $rows = @($data.Rules)
    if ($FirewallPolicyName) {
        $rows = @($rows | Where-Object {
                $policyName = & $lastSegment $_.firewallPolicyId
                @($FirewallPolicyName | Where-Object { $policyName -like $_ }).Count -gt 0
            })
    }

    $rules = foreach ($row in @($rows | Sort-Object -Property firewallPolicyId, ruleCollectionGroupPriority, ruleCollectionGroup, ruleCollectionPriority, ruleCollection, ruleIndex)) {
        $rule = $row.rule
        $get = { param([string] $Name) Get-AACPropertyValue -InputObject $rule -Name $Name }
        $policy = $policies[$row.firewallPolicyId]
        $ruleType = [string](& $get 'ruleType')
        $source = & $describeIpGroups (& $get 'sourceIpGroups')
        $destination = & $describeIpGroups (& $get 'destinationIpGroups')

        # Application rules list protocol:port pairs; network and DNAT rules
        # list IP protocols (TCP, UDP, ICMP, Any).
        $protocols = if ($ruleType -eq 'ApplicationRule') {
            & $join @(& $get 'protocols' | ForEach-Object { "$(Get-AACPropertyValue -InputObject $_ -Name 'protocolType'):$(Get-AACPropertyValue -InputObject $_ -Name 'port')" })
        }
        else {
            & $join (& $get 'ipProtocols')
        }

        [pscustomobject]@{
            PSTypeName                  = 'AAC.FirewallRule'
            SubscriptionName            = $subscriptionNames[$row.subscriptionId]
            SubscriptionId              = $row.subscriptionId
            ResourceGroup               = $row.resourceGroup
            Location                    = $row.location
            FirewallPolicy              = if ($policy) { $policy.name } else { & $lastSegment $row.firewallPolicyId }
            BasePolicy                  = if ($policy) { & $lastSegment $policy.basePolicyId } else { '' }
            Firewalls                   = if ($policy) { & $join @($policy.firewalls | ForEach-Object { & $lastSegment (Get-AACPropertyValue -InputObject $_ -Name 'id') }) } else { '' }
            RuleCollectionGroup         = $row.ruleCollectionGroup
            RuleCollectionGroupPriority = $row.ruleCollectionGroupPriority
            RuleCollection              = $row.ruleCollection
            RuleCollectionPriority      = $row.ruleCollectionPriority
            RuleCollectionType          = switch ($row.ruleCollectionType) {
                'FirewallPolicyNatRuleCollection' { 'DNAT' }
                'FirewallPolicyFilterRuleCollection' { 'Filter' }
                default { $row.ruleCollectionType }
            }
            Action                      = $row.action
            RuleName                    = [string](& $get 'name')
            RuleType                    = $ruleType
            Description                 = [string](& $get 'description')
            SourceAddresses             = & $join (& $get 'sourceAddresses')
            SourceIpGroups              = $source.Names
            SourceIpGroupAddresses      = $source.Addresses
            DestinationAddresses        = & $join (& $get 'destinationAddresses')
            DestinationIpGroups         = $destination.Names
            DestinationIpGroupAddresses = $destination.Addresses
            DestinationFqdns            = & $join (& $get 'destinationFqdns')
            TargetFqdns                 = & $join (& $get 'targetFqdns')
            TargetUrls                  = & $join (& $get 'targetUrls')
            FqdnTags                    = & $join (& $get 'fqdnTags')
            WebCategories               = & $join (& $get 'webCategories')
            Protocols                   = $protocols
            DestinationPorts            = & $join (& $get 'destinationPorts')
            TranslatedAddress           = [string](& $get 'translatedAddress')
            TranslatedFqdn              = [string](& $get 'translatedFqdn')
            TranslatedPort              = [string](& $get 'translatedPort')
            TerminateTls                = if ($ruleType -eq 'ApplicationRule') { [bool](& $get 'terminateTLS') } else { $null }
            FirewallPolicyId            = $row.firewallPolicyId
            RuleCollectionGroupId       = $row.ruleCollectionGroupId
        }
    }
    $rules = @($rules)

    if ($rules.Count -eq 0) {
        Write-Warning 'No Firewall Policy rules were found for the signed-in account and the given filters.'
    }

    if ($csvFullPath) {
        $folder = Split-Path -Path $csvFullPath -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        $rules | Export-Csv -LiteralPath $csvFullPath -NoTypeInformation -Encoding utf8 -Force
        Write-AACMarkup "[grey58]$($rules.Count) rule(s) written to $([Spectre.Console.Markup]::Escape($csvFullPath))[/]"
    }

    if ($pdfFullPath) {
        $detail = [ordered]@{
            Subscriptions = if ($SubscriptionId) { $SubscriptionId -join ', ' } else { 'every subscription the account can see' }
        }
        if ($FirewallPolicyName) { $detail['Policy filter'] = $FirewallPolicyName -join ', ' }
        # Copied first: inside Invoke-AACStatus's script block, $Title would
        # be Invoke-AACStatus's own -Title (the spinner text).
        $reportTitle = $Title
        $pdf = Invoke-AACStatus -Title 'Writing the PDF report' -Spinner 'Dots' -ScriptBlock {
            Write-AACFirewallRulePdf -Rule $rules -Path $pdfFullPath -Title $reportTitle -Detail $detail
        }
        Write-AACMarkup "[grey58]PDF report written to $([Spectre.Console.Markup]::Escape($pdf.FullName))[/]"
    }

    if ($PassThru -or (-not $csvFullPath -and -not $pdfFullPath)) {
        $rules
    }
}
