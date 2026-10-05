function Get-AACRuleData {
    <#
    .SYNOPSIS
        Reads the Azure estate in the shape PSRule for Azure expects - the
        same data Export-AzRuleData produces, without the Az modules.
    .DESCRIPTION
        PSRule for Azure (https://azure.github.io/PSRule.Rules.Azure/) checks
        live resources from Export-AzRuleData's output: each resource with
        its full properties, plus a 'resources' array of the child settings
        its rules look at (a storage account's blob services and containers,
        a SQL server's auditing and firewall rules, a Key Vault's diagnostic
        settings, ...). Export-AzRuleData needs the Az modules; this reads
        the same things with the Connect-AAC sign-in:

          1. Resources, resource groups and subscriptions from Azure Resource
             Graph (a few calls however many resources there are).
          2. The child settings, from Azure Resource Manager, for the types
             Export-AzRuleData expands - the same children and API versions
             as its ResourceExpandVisitor (PSRule.Rules.Azure v1.47). That
             is one to a dozen calls per resource of those types; resources
             of other types need none. Security alerts aren't read, as
             Export-AzRuleData doesn't by default. Shared keys on network
             connections are masked, as Export-AzRuleData does.

             The reads run in parallel (Invoke-AACArmParallel, 12 at a time),
             a level at a time across every resource: each resource's
             expansion runs first to find what it needs, those reads go out
             together, and it runs again with their results - until nothing
             new is needed (an API Management service needs three rounds:
             its APIs, then each API's operations and policies, then each
             operation's policy). A last run puts the results together, in
             the same order as reading them one by one would.

        Reader on the subscriptions is enough. A child that can't be read
        (usually 403 - Reader can't list some settings) is left out and
        reported in Warnings, so the caller can say which results may be
        affected; the resource itself is still returned.

        -NoExpand reads only step 1: names, types, tags and properties, for
        rules that need no child settings (the module's AAC.* rules). With
        -ResourceType, Resource Graph returns only those types.

        Returns @{ Resources = <hashtables>; Warnings = <strings> }.
        Progress goes to the Invoke-AACProgress display when one is running
        (Ids 'psrule-read' and 'psrule-expand').
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Defaults to every subscription the signed-in account can see.
        [string[]] $SubscriptionId = @(),

        # Only these resource types (wildcards work). Resource groups and
        # subscriptions are included only when no type is given, or when
        # their own type matches.
        [string[]] $ResourceType = @(),

        # Don't read the child settings (step 2).
        [switch] $NoExpand,
        # Only these resources (by ID, any case): the others aren't
        # expanded either (Invoke-AACAksAssessment's chosen clusters).
        [string[]] $ResourceId = @()
    )

    $warnings = [System.Collections.Generic.List[string]]::new()
    $onlyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $ResourceId) { if ($id) { [void]$onlyIds.Add($id) } }

    # --- Resource Graph ---------------------------------------------------------
    $graph = {
        param([string] $Query)
        $body = @{ query = $Query; options = @{ resultFormat = 'objectArray' } }
        if ($SubscriptionId.Count -gt 0) {
            $body.subscriptions = @($SubscriptionId)
        }
        do {
            $response = Invoke-AACArmRequest -Method Post -Uri '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body ($body | ConvertTo-Json -Depth 10)
            $response['data']
            $skipToken = $response['$skipToken']
            $body.options['$skipToken'] = $skipToken
        } while ($skipToken)
    }
    $wanted = {
        param([string] $Type)
        $ResourceType.Count -eq 0 -or @($ResourceType | Where-Object { $Type -like $_ }).Count -gt 0
    }

    # -ResourceType in the query itself, so only those types come back: each
    # name or wildcard as a case-insensitive regular expression.
    $typeFilter = if ($ResourceType.Count) {
        $alternatives = @($ResourceType | ForEach-Object { ([regex]::Escape($_) -replace '\\\*', '.*' -replace '\\\?', '.') -replace '"', '' })
        "| where type matches regex @`"(?i)^($($alternatives -join '|'))$`"`n"
    }
    else { '' }

    Update-AACProgress -Id 'psrule-read' -Total 3 -Description 'Reading resources from Azure Resource Graph'
    $resources = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @(& $graph @"
Resources
$typeFilter| project id, name, type, kind, location, resourceGroup, subscriptionId, tenantId, tags, sku, plan, zones, identity, managedBy, extendedLocation, properties
| order by type asc, name asc
"@)) {
        if (-not (& $wanted $row['type'])) {
            continue
        }
        if ($onlyIds.Count -and -not $onlyIds.Contains([string]$row['id'])) {
            continue
        }
        # Export-AzRuleData's field names: resourceGroupName, not resourceGroup.
        $row['resourceGroupName'] = $row['resourceGroup']
        $row.Remove('resourceGroup')
        foreach ($key in @($row.Keys)) {
            if ($null -eq $row[$key]) { $row.Remove($key) }
        }
        $resources.Add($row)
    }

    Update-AACProgress -Id 'psrule-read' -Increment 1 -Description 'Reading resource groups and subscriptions'
    if (& $wanted 'Microsoft.Resources/resourceGroups') {
        foreach ($row in @(& $graph @'
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions/resourcegroups'
| project id, name, location, subscriptionId, tenantId, tags, managedBy, properties
| order by name asc
'@)) {
            $row['type'] = 'Microsoft.Resources/resourceGroups'
            foreach ($key in @($row.Keys)) {
                if ($null -eq $row[$key]) { $row.Remove($key) }
            }
            $resources.Add($row)
        }
    }
    Update-AACProgress -Id 'psrule-read' -Increment 1
    $subscriptionNames = @{}
    foreach ($row in @(& $graph @'
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions'
| project subscriptionId, name, tenantId, properties
| order by name asc
'@)) {
        $subscriptionNames[[string]$row['subscriptionId']] = [string]$row['name']
        if (& $wanted 'Microsoft.Subscription') {
            $resources.Add(@{
                    type           = 'Microsoft.Subscription'
                    id             = "/subscriptions/$($row['subscriptionId'])"
                    subscriptionId = $row['subscriptionId']
                    name           = $row['name']
                    displayName    = $row['name']
                    tenantId       = $row['tenantId']
                    properties     = $row['properties']
                })
        }
    }
    Update-AACProgress -Id 'psrule-read' -Complete -Description ('Read {0:N0} resources, resource groups and subscriptions' -f $resources.Count)

    # --- Child settings -----------------------------------------------------------
    # Every item of an ARM list (following nextLink); a singleton setting
    # returned as one object counts as a list of one. 404 means "none", as
    # does 400 for settings a SKU doesn't have (Export-AzRuleData leaves
    # those out too). Anything else is noted in Warnings.
    $describe = {
        param([string] $Id)
        $parts = $Id.Trim('/').Split('/')
        if ($parts.Count -ge 2) { "$($parts[-2])/$($parts[-1])" } else { $Id }
    }
    # Reads come from $cache; one not read yet is noted in $needed (and
    # returns nothing) - Invoke-AACArmParallel then reads them all at once.
    # Warnings are only noted on the last run, so each is noted once.
    $cache = @{}
    $needed = [System.Collections.Generic.HashSet[string]]::new()
    $final = $false
    $list = {
        param([string] $Id, [string] $Child, [string] $ApiVersion)
        $uri = if ($Child.StartsWith('/')) { "$Id$($Child)?api-version=$ApiVersion" } else { "$Id/$($Child)?api-version=$ApiVersion" }
        if (-not $cache.Contains($uri)) { [void]$needed.Add($uri); return }
        $result = $cache[$uri]
        if ($result.Error) {
            if ($final -and $result.Status -notin 400, 404) {
                $warnings.Add("$(& $describe $Id): could not read $($Child.TrimStart('/')) ($(if ($result.Status) { "HTTP $($result.Status)" } else { 'no response' })): $($result.Error)")
            }
            return
        }
        if ($null -ne $result.Items) {
            foreach ($item in $result.Items) { if ($item -is [System.Collections.IDictionary]) { $item } }
        }
        elseif ($result.Body -is [System.Collections.IDictionary] -and $result.Body.Contains('id')) {
            $result.Body
        }
    }
    $getOne = {
        param([string] $Id, [string] $ApiVersion)
        $uri = "$($Id)?api-version=$ApiVersion"
        if (-not $cache.Contains($uri)) { [void]$needed.Add($uri); return }
        $result = $cache[$uri]
        if ($result.Error) {
            if ($final -and $result.Status -ne 404) {
                $warnings.Add("$(& $describe $Id): could not read it ($(if ($result.Status) { "HTTP $($result.Status)" } else { 'no response' })): $($result.Error)")
            }
            return
        }
        $result.Body
    }
    $add = {
        param([System.Collections.IDictionary] $Parent, [object[]] $Children)
        # Finding what is needed changes nothing; the last run adds.
        if (-not $final) { return }
        $items = @($Children | Where-Object { $_ -is [System.Collections.IDictionary] })
        if ($items.Count -eq 0) {
            return
        }
        if (-not $Parent.Contains('resources')) {
            $Parent['resources'] = [System.Collections.Generic.List[object]]::new()
        }
        foreach ($item in $items) { $Parent['resources'].Add($item) }
    }
    $prop = {
        param($Object, [string] $Path)
        $value = $Object
        foreach ($part in $Path.Split('.')) {
            if ($value -isnot [System.Collections.IDictionary]) { return $null }
            $key = $value.Keys | Where-Object { $_ -eq $part } | Select-Object -First 1
            $value = if ($null -ne $key) { $value[$key] } else { $null }
        }
        $value
    }
    $diagnostics = { param($Resource) & $add $Resource @(& $list $Resource['id'] '/providers/microsoft.insights/diagnosticSettings' '2021-05-01-preview') }

    # Type -> how to expand it. Mirrors ResourceExpandVisitor.
    $expand = @{
        'microsoft.resources/resourcegroups'                  = {
            param($r)
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Authorization/roleAssignments' '2022-04-01')
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Authorization/locks' '2016-09-01')
        }
        'microsoft.subscription'                              = {
            param($r)
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Authorization/roleAssignments' '2022-04-01')
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Authorization/classicAdministrators' '2015-07-01')
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Security/autoProvisioningSettings' '2017-08-01-preview')
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Security/securityContacts' '2017-08-01-preview')
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Security/pricings' '2018-06-01')
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Authorization/policyAssignments' '2019-06-01')
        }
        'microsoft.apimanagement/service'                     = {
            param($r)
            $id = $r['id']
            $apis = @(& $list $id 'apis' '2024-05-01')
            & $add $r $apis
            foreach ($api in $apis) {
                & $add $r @(& $list $api['id'] 'policies' '2024-05-01')
                if ([string](& $prop $api 'properties.type') -eq 'graphql') {
                    foreach ($resolver in @(& $list $api['id'] 'resolvers' '2022-08-01')) {
                        & $add $r @(& $list $resolver['id'] 'policies' '2022-08-01')
                    }
                }
                else {
                    foreach ($operation in @(& $list $api['id'] 'operations' '2022-08-01')) {
                        & $add $r @(& $list $operation['id'] 'policies' '2022-08-01')
                    }
                }
            }
            & $add $r @(& $list $id 'backends' '2024-05-01')
            $products = @(& $list $id 'products' '2024-05-01')
            & $add $r $products
            foreach ($product in $products) {
                & $add $r @(& $list $product['id'] 'policies' '2024-05-01')
            }
            & $add $r @(& $list $id 'policies' '2024-05-01')
            foreach ($child in 'identityProviders', 'diagnostics', 'loggers', 'certificates', 'namedValues', 'authorizationServers', 'portalsettings') {
                & $add $r @(& $list $id $child '2022-08-01')
            }
            & $add $r @(& $list $id '/providers/Microsoft.Security/apiCollections' '2022-11-20-preview')
        }
        'microsoft.automation/automationaccounts'             = {
            param($r)
            & $add $r @(& $list $r['id'] 'variables' '2022-08-08')
            & $add $r @(& $list $r['id'] 'webhooks' '2015-10-31')
        }
        'microsoft.cdn/profiles/endpoints'                    = {
            param($r)
            & $add $r @(& $list $r['id'] 'customDomains' '2023-05-01')
            & $add $r @(& $list $r['id'] 'originGroups' '2023-05-01')
            & $diagnostics $r
        }
        'microsoft.cdn/profiles'                              = {
            param($r)
            foreach ($child in 'customDomains', 'originGroups', 'ruleSets', 'secrets', 'securityPolicies') {
                & $add $r @(& $list $r['id'] $child '2023-05-01')
            }
        }
        'microsoft.cdn/profiles/afdendpoints'                 = {
            param($r)
            & $add $r @(& $list $r['id'] 'routes' '2023-05-01')
        }
        'microsoft.containerregistry/registries'              = {
            param($r)
            & $add $r @(& $list $r['id'] 'replications' '2023-01-01-preview')
            & $add $r @(& $list $r['id'] 'webhooks' '2023-01-01-preview')
            & $add $r @(& $list $r['id'] 'tasks' '2019-04-01')
            foreach ($usage in @(& $list $r['id'] 'listUsages' '2023-01-01-preview')) {
                $usage['type'] = 'Microsoft.ContainerRegistry/registries/listUsages'
                & $add $r @($usage)
            }
        }
        'microsoft.containerservice/managedclusters'          = {
            param($r)
            if ([string](& $prop $r 'properties.networkProfile.networkPlugin') -eq 'azure') {
                foreach ($pool in @(& $prop $r 'properties.agentPoolProfiles')) {
                    $subnetId = & $prop $pool 'vnetSubnetID'
                    if ($subnetId) { & $add $r @(& $getOne $subnetId '2022-07-01') }
                }
            }
            & $add $r @(& $list $r['id'] 'maintenanceConfigurations' '2024-03-02-preview')
            & $diagnostics $r
        }
        'microsoft.sql/servers'                               = {
            param($r)
            foreach ($child in 'firewallRules', 'administrators', 'securityAlertPolicies', 'vulnerabilityAssessments', 'auditingSettings') {
                & $add $r @(& $list $r['id'] $child '2021-11-01')
            }
            & $add $r @(& $list $r['id'] 'sqlVulnerabilityAssessments' '2024-05-01-preview')
        }
        'microsoft.sql/servers/databases'                     = {
            param($r)
            $lower = ([string]$r['id']).ToLowerInvariant()
            & $add $r @(& $list $lower 'dataMaskingPolicies' '2014-04-01')
            & $add $r @(& $list $r['id'] 'transparentDataEncryption' '2021-11-01')
            & $add $r @(& $list $lower 'connectionPolicies' '2014-04-01')
            & $add $r @(& $list $lower 'geoBackupPolicies' '2014-04-01')
        }
        'microsoft.dbforpostgresql/servers'                   = {
            param($r)
            foreach ($child in 'administrators', 'firewallRules', 'securityAlertPolicies', 'configurations') {
                & $add $r @(& $list $r['id'] $child '2017-12-01')
            }
        }
        'microsoft.dbforpostgresql/flexibleservers'           = {
            param($r)
            foreach ($child in 'administrators', 'firewallRules', 'configurations') {
                & $add $r @(& $list $r['id'] $child '2023-03-01-preview')
            }
        }
        'microsoft.dbformysql/servers'                        = {
            param($r)
            foreach ($child in 'administrators', 'firewallRules', 'securityAlertPolicies', 'configurations') {
                & $add $r @(& $list $r['id'] $child '2017-12-01')
            }
        }
        'microsoft.dbformysql/flexibleservers'                = {
            param($r)
            foreach ($child in 'administrators', 'firewallRules', 'configurations') {
                & $add $r @(& $list $r['id'] $child '2023-06-30')
            }
        }
        'microsoft.storage/storageaccounts'                   = {
            param($r)
            $kind = [string]$r['kind']
            if ($kind -and $kind -ne 'FileStorage') {
                $blobServices = @(& $list $r['id'] 'blobServices' '2023-01-01')
                & $add $r $blobServices
                foreach ($service in $blobServices) {
                    & $add $r @(& $list $service['id'] 'containers' '2023-01-01')
                }
            }
            elseif ($kind -and $kind -notin 'BlobStorage', 'BlockBlobStorage') {
                $fileServices = @(& $list $r['id'] 'fileServices' '2023-01-01')
                & $add $r $fileServices
                foreach ($service in $fileServices) {
                    & $add $r @(& $list $service['id'] 'shares' '2023-01-01')
                }
            }
            & $add $r @(& $list $r['id'] '/providers/Microsoft.Security/DefenderForStorageSettings' '2022-12-01-preview')
        }
        'microsoft.web/sites'                                 = { param($r) & $add $r @(& $list $r['id'] 'config' '2022-09-01') }
        'microsoft.web/sites/slots'                           = { param($r) & $add $r @(& $list $r['id'] 'config' '2022-09-01') }
        'microsoft.recoveryservices/vaults'                   = {
            param($r)
            & $add $r @(& $list $r['id'] 'replicationRecoveryPlans' '2022-09-10')
            & $add $r @(& $list $r['id'] 'replicationAlertSettings' '2022-09-10')
            & $add $r @(& $list $r['id'] 'backupstorageconfig/vaultstorageconfig' '2022-09-01-preview')
        }
        'microsoft.compute/virtualmachines'                   = {
            param($r)
            foreach ($nic in @(& $prop $r 'properties.networkProfile.networkInterfaces')) {
                $nicId = & $prop $nic 'id'
                if ($nicId) { & $add $r @(& $getOne $nicId '2022-07-01') }
            }
            $view = & $getOne "$($r['id'])/instanceView" '2021-11-01'
            $power = @(& $prop $view 'statuses') | Where-Object { [string](& $prop $_ 'code') -like 'PowerState/*' } | Select-Object -First 1
            if ($power) { $r['PowerState'] = [string](& $prop $power 'code') }
        }
        'microsoft.keyvault/vaults'                           = { param($r) & $diagnostics $r }
        'microsoft.network/frontdoors'                        = { param($r) & $diagnostics $r }
        'microsoft.kusto/clusters'                            = { param($r) & $add $r @(& $list $r['id'] 'databases' '2021-08-27') }
        'microsoft.eventhub/namespaces'                       = { param($r) & $add $r @(& $list $r['id'] 'eventhubs' '2021-11-01') }
        'microsoft.servicebus/namespaces'                     = {
            param($r)
            & $add $r @(& $list $r['id'] 'queues' '2021-06-01-preview')
            & $add $r @(& $list $r['id'] 'topics' '2021-06-01-preview')
        }
        'microsoft.eventgrid/topics'                          = { param($r) & $add $r @(& $list $r['id'] 'eventSubscriptions' '2023-12-15-preview') }
        'microsoft.eventgrid/domains'                         = {
            param($r)
            $topics = @(& $list $r['id'] 'topics' '2023-12-15-preview')
            foreach ($topic in $topics) { & $add $topic @(& $list $topic['id'] 'eventSubscriptions' '2023-12-15-preview') }
            & $add $r $topics
            & $add $r @(& $list $r['id'] 'eventSubscriptions' '2023-12-15-preview')
        }
        'microsoft.eventgrid/namespaces'                      = {
            param($r)
            $topics = @(& $list $r['id'] 'topics' '2023-12-15-preview')
            foreach ($topic in $topics) { & $add $topic @(& $list $topic['id'] 'eventSubscriptions' '2023-12-15-preview') }
            & $add $r $topics
        }
        'microsoft.devcenter/projects'                        = {
            param($r)
            $pools = @(& $list $r['id'] 'pools' '2023-04-01')
            foreach ($pool in $pools) { & $add $pool @(& $list $pool['id'] 'schedules' '2023-04-01') }
            & $add $r $pools
        }
        'microsoft.network/firewallpolicies'                  = {
            param($r)
            & $add $r @(& $list $r['id'] 'ruleCollectionGroups' '2023-09-01')
            if ([string](& $prop $r 'properties.sku.tier') -eq 'Premium') {
                & $add $r @(& $list $r['id'] 'signatureOverrides' '2023-09-01')
            }
        }
        'microsoft.network/virtualhubs'                       = { param($r) & $add $r @(& $list $r['id'] 'routingIntent' '2023-04-01') }
        'microsoft.network/dnszones'                          = { param($r) & $add $r @(& $list $r['id'] 'dnssecConfigs' '2023-07-01-preview') }
    }

    # Never pass a VPN connection's shared key on to anything.
    foreach ($resource in $resources) {
        if ([string]$resource['type'] -eq 'microsoft.network/connections' -and (& $prop $resource 'properties.sharedKey')) {
            $resource['properties']['sharedKey'] = '*** MASKED ***'
        }
    }

    $toExpand = @(if (-not $NoExpand) { $resources | Where-Object { $expand.ContainsKey(([string]$_['type']).ToLowerInvariant()) } })
    if ($toExpand.Count -gt 0) {
        Update-AACProgress -Id 'psrule-expand' -Indeterminate -Description ('Reading the settings of {0:N0} resources' -f $toExpand.Count)
        $calls = 0
        # Find what is needed, read it all in parallel, and again with the
        # results - a level of children at a time - until nothing is new.
        for ($round = 1; $round -le 8; $round++) {
            $needed.Clear()
            foreach ($resource in $toExpand) { & $expand[([string]$resource['type']).ToLowerInvariant()] $resource }
            if ($needed.Count -eq 0) { break }
            $batch = @($needed)
            $before = $calls
            # The callback runs inside Invoke-AACArmParallel, called from
            # here, so it sees $before, $round and $toExpand.
            $read = Invoke-AACArmParallel -Uri $batch -OnProgress {
                param($Done, $Total)
                Update-AACProgress -Id 'psrule-expand' -Total ($before + $Total) -Increment 1 -Description ('Reading the settings of {0:N0} resources: {1:N0} calls (level {2})' -f $toExpand.Count, ($before + $Done), $round)
            }
            foreach ($key in $read.Keys) { $cache[$key] = $read[$key] }
            $calls += $batch.Count
        }
        # The last run: every read is in the cache; put the children in place.
        $final = $true
        foreach ($resource in $toExpand) { & $expand[([string]$resource['type']).ToLowerInvariant()] $resource }
        Update-AACProgress -Id 'psrule-expand' -Complete -Description ('Read the settings of {0:N0} resources in {1:N0} calls{2}' -f $toExpand.Count, $calls, $(if ($warnings.Count) { " ($($warnings.Count) could not be read)" }))
    }

    @{
        Resources         = $resources.ToArray()
        SubscriptionNames = $subscriptionNames
        Warnings          = $warnings.ToArray()
    }
}
