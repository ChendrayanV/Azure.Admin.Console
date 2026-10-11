function ConvertTo-AACPrivateEndpoint {
    <#
    .SYNOPSIS
        Builds Get-AACPrivateEndpoint's model from the Resource Graph rows of
        Get-AACPrivateEndpointQuery and each endpoint's private DNS zone
        groups: every private endpoint connection - its state, target, IPs
        and names, the DNS zone that resolves it and whether its network can
        see that zone - and the findings.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result; -ZoneGroup
        maps an endpoint ID (lower case) to its privateDnsZoneGroups (as ARM
        returns them), or to $null when they couldn't be read. Endpoints of
        subscriptions not in -SubscriptionName are left out.

        Findings (AAC.PrivateEndpointFinding), each with what to do:
          High    a connection Pending, Rejected or Disconnected; the target
                  deleted (an orphaned endpoint); provisioning failed; the
                  zone that resolves it linked to neither the endpoint's
                  network nor one peered with it (clients there resolve the
                  public address)
          Medium  no DNS zone group (records kept by hand, or not at all);
                  the zone group's zone isn't the one the service needs; the
                  target still open to public networks; the same zone name
                  in several places (which answers depends on the network)
          Low     the network uses custom DNS servers: the zone must be
                  linked where those servers resolve (checked by hand)

        Returns @{ Endpoints; Findings; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $ZoneGroup = @{},

        [hashtable] $SubscriptionName = @{}
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $label = { param([string] $Id) $s = ([string]$Id).ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { $SubscriptionName[$s] } else { $Id } }
    $leaf = { param([string] $Id) if ($Id) { ($Id.TrimEnd('/') -split '/')[-1] } else { '' } }
    $typeOf = { param([string] $Id) if ($Id -match '(?i)/providers/([^/]+/[^/]+)/[^/]+$') { $Matches[1].ToLowerInvariant() } elseif ($Id -match '(?i)/providers/([^/]+/[^/]+)/') { $Matches[1].ToLowerInvariant() } else { '' } }

    # The zone each sub-resource (group ID) resolves in - for the target types where it is fixed.
    $zoneFor = {
        param([string] $GroupId, [string] $TargetType)
        $cosmos = @{ sql = 'privatelink.documents.azure.com'; mongodb = 'privatelink.mongo.cosmos.azure.com'; cassandra = 'privatelink.cassandra.cosmos.azure.com'; gremlin = 'privatelink.gremlin.cosmos.azure.com'; table = 'privatelink.table.cosmos.azure.com'; analytical = 'privatelink.analytics.cosmos.azure.com' }
        $g = $GroupId.ToLowerInvariant()
        if ($TargetType -eq 'microsoft.documentdb/databaseaccounts' -and $cosmos.Contains($g)) { return $cosmos[$g] }
        if ($TargetType -eq 'microsoft.cognitiveservices/accounts') { return @('privatelink.cognitiveservices.azure.com', 'privatelink.openai.azure.com', 'privatelink.services.ai.azure.com') }
        $fixed = @{
            blob = 'privatelink.blob.core.windows.net'; blob_secondary = 'privatelink.blob.core.windows.net'; file = 'privatelink.file.core.windows.net'; queue = 'privatelink.queue.core.windows.net'; queue_secondary = 'privatelink.queue.core.windows.net'
            table = 'privatelink.table.core.windows.net'; table_secondary = 'privatelink.table.core.windows.net'; web = 'privatelink.web.core.windows.net'; web_secondary = 'privatelink.web.core.windows.net'; dfs = 'privatelink.dfs.core.windows.net'; dfs_secondary = 'privatelink.dfs.core.windows.net'
            vault = 'privatelink.vaultcore.azure.net'; managedhsm = 'privatelink.managedhsm.azure.net'; sqlserver = 'privatelink.database.windows.net'; postgresqlserver = 'privatelink.postgres.database.azure.com'; mysqlserver = 'privatelink.mysql.database.azure.com'; mariadbserver = 'privatelink.mariadb.database.azure.com'
            registry = 'privatelink.azurecr.io'; sites = 'privatelink.azurewebsites.net'; namespace = 'privatelink.servicebus.windows.net'; configurationstores = 'privatelink.azconfig.io'; searchservice = 'privatelink.search.windows.net'; rediscache = 'privatelink.redis.cache.windows.net'
            amlworkspace = 'privatelink.api.azureml.ms'; datafactory = 'privatelink.datafactory.azure.net'; portal = 'privatelink.adf.azure.com'; topic = 'privatelink.eventgrid.azure.net'; domain = 'privatelink.eventgrid.azure.net'; signalr = 'privatelink.service.signalr.net'; webpubsub = 'privatelink.webpubsub.azure.com'
            webhook = 'privatelink.azure-automation.net'; dscandhybridworker = 'privatelink.azure-automation.net'; azuremonitor = 'privatelink.monitor.azure.com'; vault_secondary = 'privatelink.vaultcore.azure.net'; batchaccount = 'privatelink.batch.azure.com'; iothub = 'privatelink.azure-devices.net'
        }
        if ($fixed.Contains($g)) { $fixed[$g] }
    }

    # --- The network around the endpoints ----------------------------------------------------------------------
    $vnets = @{}
    foreach ($row in (& $rowsOf 'vnets')) {
        $vnets[(& $text $row 'id')] = @{
            Name    = & $text $row 'name'
            Dns     = @(& $list (& $get $row 'dnsServers'))
            Peered  = @(@(& $list (& $get $row 'peerings')) | ForEach-Object { (& $text $_ 'properties.remoteVirtualNetwork.id').ToLowerInvariant() } | Where-Object { $_ })
        }
    }
    $zonesByName = @{}; $zonesById = @{}
    foreach ($row in (& $rowsOf 'zones')) {
        $zonesById[(& $text $row 'id')] = $row
        $name = & $text $row 'name'
        if (-not $zonesByName.Contains($name)) { $zonesByName[$name] = [System.Collections.Generic.List[object]]::new() }
        $zonesByName[$name].Add($row)
    }
    $linksOf = @{}
    foreach ($row in (& $rowsOf 'links')) {
        $zone = & $text $row 'zone'
        if (-not $linksOf.Contains($zone)) { $linksOf[$zone] = [System.Collections.Generic.List[string]]::new() }
        $linksOf[$zone].Add((& $text $row 'vnet'))
    }
    $targets = @{}
    foreach ($row in (& $rowsOf 'targets')) { $targets[(& $text $row 'id')] = $row }
    $targetsRead = $Read.Rows -and $Read.Rows.Contains('targets') -and -not ($Read.Errors -and $Read.Errors.Contains('targets'))
    $zonesRead = $Read.Rows -and $Read.Rows.Contains('links') -and -not ($Read.Errors -and $Read.Errors.Contains('links'))

    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(@{ endpoints = 'private endpoints'; zones = 'private DNS zones'; links = 'private DNS zone links'; vnets = 'virtual networks'; targets = 'private endpoint targets' }[$key]) couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }
    $findings = [System.Collections.Generic.List[object]]::new()
    $docs = 'https://learn.microsoft.com/azure/private-link'
    $finding = {
        param([string] $Severity, [string] $Category, [string] $Finding, $Row, [string] $Detail, [string] $Impact, [string] $Remediation, [string] $Link, [string] $Effort = 'Low')
        $findings.Add((New-AACFinding -TypeName 'AAC.PrivateEndpointFinding' -Severity $Severity -Category $Category -Finding $Finding -ResourceId (& $text $Row 'id') -Resource (& $text $Row 'name') -ResourceGroup (& $text $Row 'resourceGroup') `
                    -Subscription (& $label (& $text $Row 'subscriptionId')) -Detail $Detail -Impact $Impact -Remediation $Remediation -Effort $Effort -Link $Link))
    }

    # --- Endpoints ------------------------------------------------------------------------------------------------
    $endpoints = [System.Collections.Generic.List[object]]::new()
    $groupsUnread = 0
    foreach ($row in (& $rowsOf 'endpoints')) {
        $subscription = (& $text $row 'subscriptionId').ToLowerInvariant()
        if (-not $SubscriptionName.Contains($subscription)) { continue }
        $id = & $text $row 'id'
        $name = & $text $row 'name'
        $subnet = & $text $row 'subnet'
        $vnetId = if ($subnet -match '^(.+/virtualnetworks/[^/]+)/subnets/') { $Matches[1] } else { '' }
        $vnet = if ($vnets.Contains($vnetId)) { $vnets[$vnetId] } else { @{ Name = (& $leaf $vnetId); Dns = @(); Peered = @() } }
        $customDns = @($vnet.Dns).Count -gt 0
        $ips = @(@(& $list (& $get $row 'dns')) | ForEach-Object { @(& $list (& $get $_ 'ipAddresses')) } | Select-Object -Unique)
        $fqdns = @(@(& $list (& $get $row 'dns')) | ForEach-Object { & $text $_ 'fqdn' } | Where-Object { $_ } | Select-Object -Unique)
        $groupsKnown = $ZoneGroup.Contains($id) -and $null -ne $ZoneGroup[$id]
        if ($ZoneGroup.Contains($id) -and $null -eq $ZoneGroup[$id]) { $groupsUnread++ }
        $zoneIds = @(if ($groupsKnown) { @(& $list $ZoneGroup[$id]) | ForEach-Object { @(& $list (& $get $_ 'properties.privateDnsZoneConfigs')) } | ForEach-Object { (& $text $_ 'properties.privateDnsZoneId').ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique })
        $zoneNames = @($zoneIds | ForEach-Object { & $leaf $_ })
        if ((& $text $row 'state') -eq 'Failed') {
            & $finding 'High' 'Provisioning' 'Private endpoint provisioning failed' $row "$name is in the Failed state." 'It may not route traffic, and later changes to it can fail.' 'Look at the deployment''s error; delete and recreate the endpoint.' "$docs/troubleshoot-private-endpoint-connectivity" 'Medium'
        }
        $connections = @(@(& $list (& $get $row 'connections')) | ForEach-Object { @{ Item = $_; Manual = $false } }) + @(@(& $list (& $get $row 'manual')) | ForEach-Object { @{ Item = $_; Manual = $true } })
        foreach ($c in $connections) {
            $target = (& $text $c.Item 'properties.privateLinkServiceId').ToLowerInvariant()
            $targetType = & $typeOf $target
            $groupIds = @(& $list (& $get $c.Item 'properties.groupIds'))
            $groupId = [string](@($groupIds) | Select-Object -First 1)
            $status = & $text $c.Item 'properties.privateLinkServiceConnectionState.status'
            $description = & $text $c.Item 'properties.privateLinkServiceConnectionState.description'
            $targetRow = if ($targets.Contains($target)) { $targets[$target] } else { $null }
            $targetSubscription = if ($target -match '^/subscriptions/([^/]+)') { $Matches[1] } else { '' }
            $missing = $targetsRead -and -not $targetRow -and $SubscriptionName.Contains($targetSubscription) -and $targetType -ne 'microsoft.network/privatelinkservices'
            $public = if ($targetRow) { (& $text $targetRow 'publicAccess') } else { '' }
            $openToPublic = $targetRow -and $public -ne 'Disabled' -and (& $text $targetRow 'defaultAction') -ne 'Deny'
            $expected = @(if ($groupId) { & $zoneFor $groupId $targetType })
            $issues = [System.Collections.Generic.List[string]]::new()
            $levels = [System.Collections.Generic.List[string]]::new()

            if ($status -in 'Pending', 'Rejected', 'Disconnected') {
                $why = @{ Pending = 'waits for the target''s owner to approve it'; Rejected = 'was rejected by the target''s owner'; Disconnected = 'was removed on the target''s side (or the target was deleted)' }[$status]
                & $finding 'High' 'Connection' "Private endpoint connection $status" $row "$name -> $(& $leaf $target) ($groupId) $why$(if ($description) { ": $description" })." 'No traffic flows through it: clients fail, or fall back to the public endpoint.' $(if ($status -eq 'Pending') { 'Approve it on the target (Networking > Private endpoint connections), or ask its owner to.' } else { 'Delete the endpoint and create a new connection - or, if it is no longer needed, just delete it.' }) "$docs/manage-private-endpoint"
                $issues.Add("connection $status"); $levels.Add('High')
            }
            if ($missing) {
                & $finding 'High' 'Orphaned' 'Private endpoint to a deleted resource' $row "$name points to $(& $leaf $target), which no longer exists." 'It holds an IP address and DNS records for a service that is gone.' 'Delete the endpoint (and its DNS records, if they were kept by hand).' "$docs/manage-private-endpoint"
                $issues.Add('target deleted'); $levels.Add('High')
            }
            $linked = 'Not checked'
            if ($zoneIds.Count) {
                $seenBy = @($zoneIds | ForEach-Object { if ($linksOf.Contains($_)) { $linksOf[$_] } })
                if (@($seenBy | Where-Object { $_ -eq $vnetId }).Count) { $linked = 'Yes' }
                elseif (@($seenBy | Where-Object { $vnet.Peered -contains $_ }).Count) { $linked = 'Peered network' }
                elseif ($customDns) { $linked = 'Custom DNS' }
                elseif ($zonesRead) { $linked = 'No' }
                if ($linked -eq 'No') {
                    & $finding 'High' 'DNS' 'Private DNS zone not linked to the endpoint''s network' $row "$name's zone $($zoneNames -join ', ') is linked to neither $($vnet.Name) nor a network peered with it." "Clients in $($vnet.Name) resolve the service's public address: traffic leaves the private network, or fails if public access is off." "Link the zone to $($vnet.Name) (or to the hub whose DNS it uses)." "$docs/private-endpoint-dns"
                    $issues.Add('zone not linked'); $levels.Add('High')
                }
                if ($expected.Count -and -not @($zoneNames | Where-Object { $expected -contains $_ }).Count) {
                    & $finding 'Medium' 'DNS' 'Private DNS zone group uses the wrong zone' $row "$name ($groupId) is registered in $($zoneNames -join ', '); the service resolves in $($expected -join ' or ')." 'The record is in a zone clients never query: they resolve the public address.' "Replace the zone group with one for $($expected[0])." "$docs/private-endpoint-dns"
                    $issues.Add('wrong zone'); $levels.Add('Medium')
                }
            }
            elseif ($groupsKnown) {
                $linked = 'No zone group'
                if ($customDns) {
                    & $finding 'Low' 'DNS' 'Private endpoint relies on custom DNS' $row "$name has no private DNS zone group; $($vnet.Name) uses DNS servers $(@($vnet.Dns) -join ', ')." 'Its name resolves privately only if those servers have (or forward to) a record for it.' "Check $($fqdns -join ', ') resolves to $($ips -join ', ') from $($vnet.Name); prefer a zone group, linked where the DNS servers resolve." "$docs/private-endpoint-dns-integration"
                    $issues.Add('custom DNS'); $levels.Add('Low')
                }
                else {
                    & $finding 'Medium' 'DNS' 'Private endpoint without a DNS zone group' $row "$name has no private DNS zone group, and $($vnet.Name) uses Azure DNS." 'Unless a record was added by hand, its name resolves to the public address; a hand-made record goes stale when the IP changes.' "Add a private DNS zone group for $(if ($expected.Count) { $expected[0] } else { 'the service''s privatelink zone' })." "$docs/private-endpoint-dns"
                    $issues.Add('no zone group'); $levels.Add('Medium')
                }
            }
            if ($openToPublic -and $status -eq 'Approved') {
                & $finding 'Medium' 'Exposure' 'Target still open to public networks' $row "$(& $leaf $target) has a private endpoint but public network access is $(if ($public) { $public } else { 'not restricted' })." 'The private endpoint adds a private path; it doesn''t close the public one.' 'Disable public network access on the target (or restrict it to selected networks) once its clients use the private endpoint.' "$docs/private-endpoint-overview" 'Medium'
                $issues.Add('target public'); $levels.Add('Medium')
            }
            $item = [pscustomobject][ordered]@{
                Status             = $(switch ($(if ($levels -contains 'High') { 'High' } elseif ($levels -contains 'Medium') { 'Medium' } elseif ($levels -contains 'Low') { 'Low' } else { 'Info' })) { 'High' { 'Failed' } 'Medium' { 'Warning' } 'Low' { 'Review' } default { 'Healthy' } })
                Endpoint           = $name
                Target             = & $leaf $target
                TargetType         = $targetType
                GroupId            = ($groupIds -join ', ')
                ConnectionState    = $status
                Approval           = $(if ($c.Manual) { 'Manual' } else { 'Automatic' })
                IpAddresses        = ($ips -join ', ')
                Fqdns              = ($fqdns -join ', ')
                DnsZones           = ($zoneNames -join ', ')
                ExpectedZone       = ($expected -join ' or ')
                ZoneLinked         = $linked
                VirtualNetwork     = $vnet.Name
                Subnet             = & $leaf $subnet
                CustomDns          = $(if ($customDns) { @($vnet.Dns) -join ', ' } else { '' })
                TargetPublicAccess = $(if ($targetRow) { if ($public) { $public } else { 'Not set' } } elseif ($missing) { 'Deleted' } else { '' })
                Issues             = ($issues -join ', ')
                ResourceGroup      = & $text $row 'resourceGroup'
                Subscription       = & $label $subscription
                Location           = & $text $row 'location'
                ProvisioningState  = & $text $row 'state'
                TargetId           = $target
                ResourceId         = $id
            }
            $item.PSObject.TypeNames.Insert(0, 'AAC.PrivateEndpoint')
            $endpoints.Add($item)
        }
    }
    if ($groupsUnread) { $notices.Add("The DNS zone groups of $groupsUnread private endpoint(s) couldn't be read: their DNS isn't checked.") }

    # --- The same zone in several places -----------------------------------------------------------------------------
    foreach ($name in @($zonesByName.Keys | Sort-Object)) {
        $copies = @($zonesByName[$name] | Where-Object { $SubscriptionName.Contains((& $text $_ 'subscriptionId').ToLowerInvariant()) })
        if ($copies.Count -lt 2 -or $name -notlike 'privatelink.*') { continue }
        & $finding 'Medium' 'DNS' 'Private DNS zone defined more than once' $copies[0] "$name exists $($copies.Count) times: $(@($copies | ForEach-Object { "$(& $text $_ 'resourceGroup') ($(& $label (& $text $_ 'subscriptionId')))" }) -join '; ')." 'Which records a client sees depends on which copy its network is linked to: endpoints registered in one copy are invisible from networks linked to another.' 'Keep one zone per privatelink name (usually in the hub or a central DNS subscription), link it everywhere, and move the records into it.' "$docs/private-endpoint-dns" 'Medium'
    }

    $rank = (Get-AACSeverityRank).Rank
    $statusOrder = @{ Failed = 0; Warning = 1; Review = 2; Healthy = 3 }
    $sortedEndpoints = @($endpoints | Sort-Object -Property @{ Expression = { $statusOrder[$_.Status] } }, Endpoint)
    $sortedFindings = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Category, Resource)
    @{
        Endpoints = $sortedEndpoints
        Findings  = $sortedFindings
        Notices   = @($notices)
        Stats     = @{
            Endpoints   = @($sortedEndpoints | Select-Object -ExpandProperty ResourceId -Unique).Count
            Connections = $sortedEndpoints.Count
            Healthy     = @($sortedEndpoints | Where-Object Status -EQ 'Healthy').Count
            Failed      = @($sortedEndpoints | Where-Object Status -EQ 'Failed').Count
            Pending     = @($sortedEndpoints | Where-Object ConnectionState -EQ 'Pending').Count
            Orphaned    = @($sortedEndpoints | Where-Object TargetPublicAccess -EQ 'Deleted').Count
            DnsIssues   = @($sortedFindings | Where-Object Category -EQ 'DNS').Count
            Public      = @($sortedEndpoints | Where-Object { $_.Issues -match 'target public' }).Count
            High        = @($sortedFindings | Where-Object Severity -EQ 'High').Count
        }
    }
}
