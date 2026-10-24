function Get-AACFirewallRule {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Gets every Azure Firewall Policy rule - DNAT, network and application:
        a colour-coded Spectre.Console view at the prompt, PowerShell objects
        down a pipeline, and optional CSV, PDF and interactive HTML exports.
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

        What you get depends on where the command runs:
          at the prompt    a Spectre.Console view: the account and scope,
                           tiles with the number of rules, allow, deny and
                           DNAT rules, policies and collections, a table of
                           the policies, then one table per rule collection
                           in priority order - Allow collections bordered in
                           green, Deny in red, DNAT in orange - shown a
                           screen at a time
          piped onward     the AAC.FirewallRule objects, with no view
          -PassThru        the view and the objects
          -NoDisplay       the objects only (scripts, scheduled tasks)

        PowerShell can't tell "$r = Get-AACFirewallRule" from a plain call,
        so to keep the objects in a variable add -PassThru or -NoDisplay.

        In the view, IP Groups are shown by name with their addresses under
        them, and an Allow rule open to any source or destination has its
        '*' called out in yellow. When the view is longer than the terminal
        it is paged: press any key for the next page, or A for the rest.

        Exports:
          -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
                      rule, list values joined with ", ")
          -PdfPath    a landscape A4 PDF: a summary of each policy, then every
                      rule grouped by policy, rule collection group and rule
                      collection, with Allow in green, Deny in red and DNAT
                      in amber
          -HtmlPath   a self-contained, interactive HTML report: clickable
                      tiles and charts (by action, policy, rule collection,
                      rule type) that filter a table of every rule, grouped
                      by rule collection, with search, filters, sorting,
                      Allow rules open to any address flagged, Azure portal
                      links and a CSV download of what is shown

        When any of -CsvPath, -PdfPath or -HtmlPath is given, the console
        shows only the progress and the files written - the report is in
        the files. Add -PassThru to get the objects as well.

        Search: -SourceAddress, -DestinationAddress, -Port, -Protocol,
        -Fqdn, -Action and -RuleName narrow the rules to those that match -
        every filter given must match, and any one of a filter's values.
        Addresses and ports match by containment, so the search answers
        "which rules let this source reach that destination on this port?":
        10.1.2.3 matches a rule for 10.1.0.0/16, for an IP Group holding it,
        or for '*'; a CIDR or 'a-b' range matches rules that overlap it; port
        443 matches '443', '400-500' and '*'. Service tags (e.g. AzureCloud)
        aren't expanded, so they only match a search for them by -RuleName.

        Only Firewall Policy rules are read. Classic rules configured
        directly on a firewall (without a policy) are not included. Rules a
        policy inherits from its base policy appear under the base policy.

        PDF export needs Windows and PowerShell 7.4 or later; objects and
        CSV work everywhere.
    .PARAMETER SubscriptionId
        Only get policies in these subscriptions. Defaults to every
        subscription the signed-in account can see. IP Groups and base
        policies are resolved in every subscription either way.
    .PARAMETER FirewallPolicyName
        Only get policies whose name matches one of these wildcard patterns
        (case-insensitive), e.g. 'fwpol-hub-*'.
    .PARAMETER SourceAddress
        Only rules whose source covers or overlaps one of these addresses:
        IPs, CIDR prefixes or 'a-b' ranges, IPv4 or IPv6. The rule's IP
        Groups count, and a '*' source matches any address.
    .PARAMETER DestinationAddress
        Only rules whose destination covers or overlaps one of these
        addresses, as for -SourceAddress.
    .PARAMETER Port
        Only rules whose destination ports include one of these ports or
        overlap one of these ranges ('443', '8000-8080'). For application
        rules, the port of each protocol ('Https:443') counts.
    .PARAMETER Protocol
        Only rules for one of these protocols: TCP, UDP, ICMP (network and
        DNAT rules - a rule for 'Any' matches all), or Http, Https, Mssql
        (application rules).
    .PARAMETER Fqdn
        Only rules for one of these host names - '*.contoso.com' in a rule
        covers 'www.contoso.com' - or whose FQDNs match one of these
        wildcard patterns.
    .PARAMETER Action
        Only rules in collections with one of these actions: Allow, Deny,
        DNAT.
    .PARAMETER RuleName
        Only rules whose name matches one of these wildcard patterns.
    .PARAMETER CsvPath
        Also write the rules to this CSV file. An existing file is
        overwritten; missing folders are created.
    .PARAMETER PdfPath
        Also write the rules to this PDF file. An existing file is
        overwritten; missing folders are created.
    .PARAMETER HtmlPath
        Also write an interactive HTML report to this file. An existing file
        is overwritten; missing folders are created.
    .PARAMETER Title
        The PDF and HTML report's title. Defaults to 'Azure Firewall rules'.
    .PARAMETER PassThru
        Show the view and also return the rule objects.
    .PARAMETER NoDisplay
        Return the rule objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a screen at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACFirewallRule
        Shows every Firewall Policy rule you can see, policy by policy.
    .EXAMPLE
        Get-AACFirewallRule -CsvPath .\out\FirewallRules.csv -PdfPath .\out\FirewallRules.pdf
        Writes every rule to a CSV file and a PDF report; the console shows the progress and the files.
    .EXAMPLE
        Get-AACFirewallRule -SubscriptionId '00000000-0000-0000-0000-000000000000' |
            Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' } |
            Format-Table FirewallPolicy, RuleCollection, RuleName, DestinationPorts
        Lists allow rules open to any source in one subscription.
    .EXAMPLE
        Get-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' -PdfPath .\HubFirewall.pdf -Title 'Hub firewall rules'
        The hub firewall policies only, as a PDF.
    .EXAMPLE
        Get-AACFirewallRule -HtmlPath .\out\FirewallRules.html
        Every rule in an interactive HTML report to search, filter and share.
    .EXAMPLE
        Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP
        Which rules let 10.1.2.3 reach 10.0.0.4 on UDP 53 - allow and deny - in priority order.
    .EXAMPLE
        Get-AACFirewallRule -Action Allow -SourceAddress 0.0.0.0/0 -Port 3389, 22
        Allow rules for RDP or SSH from any address.
    .EXAMPLE
        Get-AACFirewallRule -Fqdn www.contoso.com -Protocol Https -CsvPath .\contoso.csv
        Application rules that cover www.contoso.com over HTTPS, also saved as a CSV file.
    .EXAMPLE
        $rules = Get-AACFirewallRule -NoDisplay
        Keeps the rule objects in a variable, without showing the view.
    .EXAMPLE
        Get-AACFirewallRule | Export-Csv -Path .\rules.csv -NoTypeInformation -Delimiter ';'
        Uses Export-Csv directly, for control over its options.
    .OUTPUTS
        AAC.FirewallRule (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.FirewallRule')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [SupportsWildcards()]
        [string[]] $FirewallPolicyName,

        [string[]] $SourceAddress,

        [string[]] $DestinationAddress,

        [string[]] $Port,

        [string[]] $Protocol,

        [SupportsWildcards()]
        [string[]] $Fqdn,

        [ValidateSet('Allow', 'Deny', 'DNAT')]
        [string[]] $Action,

        [SupportsWildcards()]
        [string[]] $RuleName,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Azure Firewall rules',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    # Piped onward (| Where-Object, | Export-Csv ...) the objects are the
    # point, so no view is drawn over them.
    # An export means the report is in the files: the console shows only
    # the title, the progress and the files written.
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $exporting = [bool]($CsvPath -or $PdfPath -or $HtmlPath)
    $showView = $interactive -and -not $exporting
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward

    # Resolve paths now, relative to the caller's location, so a bad path
    # fails before any Azure call.
    $csvFullPath = if ($CsvPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath) }
    $pdfFullPath = if ($PdfPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PdfPath) }
    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) }

    # Signed in? (Get-AACAccessToken says what to do when not.)
    $null = Get-AACAccessToken

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

    # The title first, then a line per step - as every command shows them.
    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Azure Firewall' -Color 'deepskyblue3_1'
    }
    $data = Invoke-AACProgress -ScriptBlock {
        # The four queries at once (Invoke-AACGraphBatch). Base policies, IP
        # Groups and subscription names can live in any subscription, so
        # those three are read tenant-wide.
        Update-AACProgress -Id 'read' -Total 4 -Description 'Reading firewall policy rules, policies, IP Groups and subscription names'
        $batch = Invoke-AACGraphBatch -AsObject -SubscriptionId $SubscriptionId -Query ([ordered]@{
                rules         = $ruleQuery
                policies      = @{ Tenant = $true; Query = $policyQuery }
                ipGroups      = @{ Tenant = $true; Query = $ipGroupQuery }
                subscriptions = @{ Tenant = $true; Query = $subscriptionQuery }
            }) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total queries)" }
        $ruleRows = @($batch.Rows['rules'])
        $policyRows = @($batch.Rows['policies'])
        $ipGroupRows = @($batch.Rows['ipGroups'])
        $subscriptionRows = @($batch.Rows['subscriptions'])
        $policyCount = @($ruleRows | ForEach-Object { $_.firewallPolicyId } | Select-Object -Unique).Count
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} firewall rule(s) in {1:N0} policy(ies), {2:N0} IP Group(s)' -f $ruleRows.Count, $policyCount, $ipGroupRows.Count)
        @{ Rules = $ruleRows; Policies = $policyRows; IpGroups = $ipGroupRows; Subscriptions = $subscriptionRows }
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

    # The search filters: all given must match, any value of each.
    $matchParameters = @{}
    foreach ($name in 'SourceAddress', 'DestinationAddress', 'Port', 'Protocol', 'Fqdn') {
        if ($PSBoundParameters.ContainsKey($name)) { $matchParameters[$name] = $PSBoundParameters[$name] }
    }
    if ($Action) {
        $rules = @($rules | Where-Object { $_.Action -in $Action })
    }
    if ($RuleName) {
        $rules = @($rules | Where-Object { $name = $_.RuleName; @($RuleName | Where-Object { $name -like $_ }).Count -gt 0 })
    }
    if ($matchParameters.Count -gt 0) {
        $rules = @($rules | Where-Object { Test-AACFirewallRuleMatch -Rule $_ @matchParameters })
    }

    # Where the rules came from and what was searched for, for the view and the PDF.
    $scope = [ordered]@{
        Subscriptions = if ($SubscriptionId) { $SubscriptionId -join ', ' } else { 'every subscription the account can see' }
    }
    if ($FirewallPolicyName) { $scope['Policy filter'] = $FirewallPolicyName -join ', ' }
    foreach ($filter in @(
            @('Source', $SourceAddress), @('Destination', $DestinationAddress), @('Port', $Port), @('Protocol', $Protocol),
            @('FQDN', $Fqdn), @('Action', $Action), @('Rule name', $RuleName))) {
        if ($filter[1]) { $scope[$filter[0]] = @($filter[1]) -join ', ' }
    }

    if ($rules.Count -eq 0 -and -not $showView) {
        Write-Warning 'No Firewall Policy rules were found for the signed-in account and the given filters.'
    }

    $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $rules -Noun 'rule' -PdfPath $pdfFullPath -WritePdf {
        Write-AACFirewallRulePdf -Rule $rules -Path $pdfFullPath -Title $Title -Detail $scope
    } -HtmlPath $htmlFullPath -WriteHtml {
        Write-AACFirewallRuleHtml -Rule $rules -Path $htmlFullPath -Title $Title -Detail $scope
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACFirewallRuleView -Rule $rules -Scope $scope -NoTitle
            [Spectre.Console.AnsiConsole]::WriteLine()
            if ($rules.Count -gt 0) {
                Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath, -PdfPath or -HtmlPath for a report.[/]'
            }
        }
    }

    if ($returnObjects) {
        $rules
    }
}
