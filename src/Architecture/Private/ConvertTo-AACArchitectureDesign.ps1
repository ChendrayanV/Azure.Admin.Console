function ConvertTo-AACArchitectureDesign {
    <#
    .SYNOPSIS
        Builds a design model from a brief and the chosen patterns: the
        components, where they sit (edge, hub, spoke, data, operations,
        pipeline), their settings and how they connect.
    .DESCRIPTION
        No Azure calls. The components come from the answers:
          compute     by workload kind (BUS-01): App Service, Functions,
                      Container Apps jobs, Data Factory, Azure OpenAI with AI
                      Search, Logic Apps with API Management
          data        by DATA-01: Azure SQL, Cosmos DB, Storage
          edge        Front Door Premium for several geographies or two
                      regions, otherwise Application Gateway WAF_v2, when
                      exposed to the internet (SEC-03)
          network     hub and spoke with private DNS when there is a landing
                      zone or the data is confidential; Azure Firewall for
                      outbound traffic or regulated data
          patterns    the chosen patterns' components: a cache, a queue
                      (with a worker), events, storage, API Management
          always      Key Vault, Log Analytics (Application Insights for
                      full observability), a budget when there is one
          pipeline    repository, PSRule for Azure gate, deploy (OPS-01)
        Settings follow the answers: zone redundancy from a 99.95% SLA, a
        private endpoint and no public access for confidential data, the
        identity from SEC-04, TLS 1.2, purge protection, the WAF on. With a
        second region (-Region a, b) and a need for one (RTO under an hour
        or 99.99%), the regional tier is repeated there with replication.
        -Override changes any component (by Id): @{ kv = @{ Settings =
        @{ PurgeProtection = $false } }; web = @{ Sku = 'P0v3' } }.
        Returns the design hashtable (Resolve-AACArchitectureInput's shape).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Brief,

        [string[]] $Pattern = @(),

        [string[]] $Region = @('westeurope'),

        [hashtable] $LandingZone,

        [System.Collections.IDictionary] $Tag = @{},

        [System.Collections.IDictionary] $Override = @{},

        [string] $Commitment = ''
    )

    $a = $Brief.Answers
    $num = { param($Value) $n = 0.0; if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$n)) { $n } else { 0 } }
    $sensitive = $a['SEC-01'] -in 'Confidential', 'Regulated'
    $zoneRedundant = (& $num $a['REL-03']) -ge 99.95
    $critical = $a['BUS-02'] -in 'Mission-critical', 'Business-critical'
    $needsSecond = (& $num $a['REL-01']) -lt 60 -or $a['REL-03'] -eq '99.99' -or $Pattern -contains 'geodes' -or $Pattern -contains 'deployment-stamp'
    $regions = @($Region | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    $multi = $needsSecond -and $regions.Count -ge 2
    $exposed = $a['SEC-03'] -ne 'None (internal only)'
    $network = $sensitive -or [bool]$a['OPS-03'] -or $a['SEC-03'] -eq 'Inbound and outbound'
    $notices = [System.Collections.Generic.List[string]]::new()

    $nodes = [System.Collections.Generic.List[hashtable]]::new()
    $connections = [System.Collections.Generic.List[hashtable]]::new()
    $paas = @('database', 'cosmos', 'storage', 'keyvault', 'cache', 'queue', 'events', 'search', 'openai', 'datafactory')
    $zonal = @('app', 'functions', 'container', 'database', 'cosmos', 'storage', 'cache', 'queue', 'gateway', 'firewall')
    $add = {
        param([string] $Id, [string] $Kind, [string] $Name, [string] $Service, [string] $Zone, [string] $Sku, [string] $Why, [hashtable] $Settings = @{}, [string] $Where = $regions[0])
        $isPaas = $Kind -in $paas
        $nodes.Add(@{
                Id = $Id; Kind = $Kind; Name = $Name; Service = $Service; Zone = $Zone; Region = $Where; Sku = $Sku
                ZoneRedundant = ($Kind -in $zonal -and $zoneRedundant) -or $Zone -eq 'Edge'
                PrivateEndpoint = $isPaas -and $sensitive; PublicAccess = $isPaas -and -not $sensitive
                Identity = $(if ($Kind -in 'app', 'functions', 'container', 'datafactory') { [string]$a['SEC-04'] } else { '' })
                Settings = $Settings; Pattern = $Why
            })
    }
    $link = { param([string] $From, [string] $To, [string] $Label, [string] $Kind = 'data') $connections.Add(@{ From = $From; To = $To; Label = $Label; Kind = $Kind }) }
    $has = { param([string] $Id) @($nodes | Where-Object { $_.Id -eq $Id }).Count -gt 0 }

    # --- Edge ------------------------------------------------------------------------------------------------------
    if ($exposed) {
        if ($a['PERF-04'] -eq 'Several regions' -or $multi) { & $add 'edge' 'gateway' 'Front Door Premium' 'Microsoft.Cdn/profiles' 'Edge' 'Premium_AzureFrontDoor' 'Global entry point with the web application firewall' @{ Waf = $true; WafMode = 'Prevention' } '' }
        else { & $add 'edge' 'gateway' 'Application Gateway' 'Microsoft.Network/applicationGateways' 'Spoke' 'WAF_v2' 'Regional entry point with the web application firewall' @{ Waf = $true; WafMode = 'Prevention' } }
    }
    # --- Compute, by workload kind ------------------------------------------------------------------------------------
    $tier = if ($a['BUS-02'] -eq 'Mission-critical') { 'P2v3' } elseif ($critical) { 'P1v3' } else { 'P0v3' }
    switch ($a['BUS-01']) {
        'Event-driven' { & $add 'compute' 'functions' 'Function App' 'Microsoft.Web/sites (functionapp)' 'Spoke' 'Flex Consumption' 'Event-driven compute' @{ MinTls = '1.2'; HttpsOnly = $true } }
        'Batch' { & $add 'compute' 'container' 'Container Apps job' 'Microsoft.App/jobs' 'Spoke' 'Consumption' 'Scheduled and event-triggered batch work' @{ MinTls = '1.2' } }
        'Data and analytics' {
            & $add 'compute' 'datafactory' 'Data Factory' 'Microsoft.DataFactory/factories' 'Spoke' '' 'Orchestrates ingestion and transformation' @{}
            & $add 'lake' 'storage' 'Data Lake Storage' 'Microsoft.Storage/storageAccounts (HNS)' 'Data' $(if ($zoneRedundant) { 'Standard_ZRS' } else { 'Standard_LRS' }) 'The data lake' @{ MinTls = '1.2' }
            & $link 'compute' 'lake' 'reads and writes'
        }
        'AI (retrieval-augmented generation)' {
            & $add 'compute' 'app' 'App Service' 'Microsoft.Web/sites' 'Spoke' $tier 'Hosts the chat application and the orchestration' @{ MinTls = '1.2'; HttpsOnly = $true }
            & $add 'openai' 'openai' 'Azure OpenAI' 'Microsoft.CognitiveServices/accounts (OpenAI)' 'Data' 'S0' 'Generates the answers' @{}
            & $add 'search' 'search' 'AI Search' 'Microsoft.Search/searchServices' 'Data' $(if ($critical) { 'S1 (3 replicas)' } else { 'Basic' }) 'Retrieves the grounding data' @{}
            & $link 'compute' 'openai' 'prompts'
            & $link 'compute' 'search' 'retrieval'
        }
        'Integration' {
            & $add 'compute' 'app' 'Logic Apps Standard' 'Microsoft.Web/sites (workflowapp)' 'Spoke' 'WS1' 'Runs the integration workflows' @{ MinTls = '1.2'; HttpsOnly = $true }
            & $add 'apim' 'apim' 'API Management' 'Microsoft.ApiManagement/service' 'Spoke' $(if ($critical) { 'Premium' } else { 'StandardV2' }) 'Publishes and protects the APIs' @{}
            & $link 'apim' 'compute' 'HTTPS'
        }
        default { & $add 'compute' 'app' 'App Service' 'Microsoft.Web/sites' 'Spoke' $tier 'Hosts the web application or API' @{ MinTls = '1.2'; HttpsOnly = $true } }
    }
    if (& $has 'edge') { & $link 'edge' $(if (& $has 'apim') { 'apim' } else { 'compute' }) 'HTTPS' }
    # --- Data -------------------------------------------------------------------------------------------------------
    switch ($a['DATA-01']) {
        'Relational' { & $add 'data' 'database' 'Azure SQL Database' 'Microsoft.Sql/servers/databases' 'Data' $(if ($a['BUS-02'] -eq 'Mission-critical') { 'Business Critical' } else { 'General Purpose' }) 'The relational data store' @{ MinTls = '1.2' } }
        'Document' { & $add 'data' 'cosmos' 'Cosmos DB' 'Microsoft.DocumentDB/databaseAccounts' 'Data' 'Autoscale' 'The document data store' @{} }
        'Files and blobs' { if (-not (& $has 'lake')) { & $add 'data' 'storage' 'Storage account' 'Microsoft.Storage/storageAccounts' 'Data' $(if ($zoneRedundant) { 'Standard_ZRS' } else { 'Standard_LRS' }) 'Files and blobs' @{ MinTls = '1.2' } } }
    }
    if (& $has 'data') { & $link 'compute' 'data' $(if ($sensitive) { 'private endpoint' } else { 'TLS' }) $(if ($sensitive) { 'private' } else { 'data' }) }
    # --- What the chosen patterns add -----------------------------------------------------------------------------------
    if ($Pattern -contains 'cache-aside') { & $add 'cache' 'cache' 'Azure Cache for Redis' 'Microsoft.Cache/redis' 'Data' $(if ($zoneRedundant) { 'Premium P1 (zones)' } else { 'Standard C1' }) 'Cache-Aside' @{ MinTls = '1.2' }; & $link 'compute' 'cache' 'cache-aside' }
    if (@($Pattern | Where-Object { $_ -in 'queue-based-load-leveling', 'competing-consumers' }).Count) {
        & $add 'queue' 'queue' 'Service Bus' 'Microsoft.ServiceBus/namespaces' 'Integration' $(if ($zoneRedundant -or $sensitive) { 'Premium' } else { 'Standard' }) 'Queue-Based Load Leveling' @{}
        & $link 'compute' 'queue' 'enqueue'
        if ($a['BUS-01'] -ne 'Event-driven') { & $add 'worker' 'functions' 'Worker (Functions)' 'Microsoft.Web/sites (functionapp)' 'Spoke' 'Flex Consumption' 'Competing Consumers' @{ MinTls = '1.2'; HttpsOnly = $true }; & $link 'queue' 'worker' 'dequeue' }
        if ((& $has 'worker') -and (& $has 'data')) { & $link 'worker' 'data' 'writes' $(if ($sensitive) { 'private' } else { 'data' }) }
    }
    if ($Pattern -contains 'publisher-subscriber') { & $add 'events' 'events' 'Event Grid' 'Microsoft.EventGrid/namespaces' 'Integration' 'Standard' 'Publisher-Subscriber' @{}; & $link 'compute' 'events' 'publish' }
    if (@($Pattern | Where-Object { $_ -in 'claim-check', 'valet-key' }).Count -and -not @($nodes | Where-Object Kind -EQ 'storage').Count) { & $add 'blob' 'storage' 'Storage account' 'Microsoft.Storage/storageAccounts' 'Data' $(if ($zoneRedundant) { 'Standard_ZRS' } else { 'Standard_LRS' }) 'Claim Check / Valet Key' @{ MinTls = '1.2' }; & $link 'compute' 'blob' 'payloads' }
    if ($Pattern -contains 'throttling' -and -not (& $has 'apim')) { & $add 'apim' 'apim' 'API Management' 'Microsoft.ApiManagement/service' 'Spoke' 'StandardV2' 'Throttling' @{}; & $link 'apim' 'compute' 'rate-limited HTTPS' }
    # --- Always: secrets, monitoring, budget ----------------------------------------------------------------------------
    & $add 'kv' 'keyvault' 'Key Vault' 'Microsoft.KeyVault/vaults' 'Data' 'Standard' 'Secrets, keys and certificates' @{ PurgeProtection = $true; SoftDelete = $true; Rbac = $true }
    & $link 'compute' 'kv' 'keys and secrets' $(if ($sensitive) { 'private' } else { 'data' })
    & $add 'law' 'monitor' 'Log Analytics workspace' 'Microsoft.OperationalInsights/workspaces' 'Operations' 'PerGB2018' 'Logs and metrics of every component' @{} ''
    if ($a['OPS-02'] -eq 'Full') { & $add 'appi' 'monitor' 'Application Insights' 'Microsoft.Insights/components' 'Operations' '' 'Distributed tracing' @{} ''; & $link 'compute' 'appi' 'telemetry' 'control' }
    if ((& $num $a['COST-01']) -gt 0) { & $add 'budget' 'budget' "Budget ($($a['COST-01']) a month)" 'Microsoft.Consumption/budgets' 'Operations' '' 'Actual and forecast alerts to the owner' @{} '' }
    # --- Network: hub and spoke ----------------------------------------------------------------------------------------
    if ($network) {
        & $add 'hub' 'network' 'Hub virtual network' 'Microsoft.Network/virtualNetworks' 'Hub' '' $(if ($a['OPS-03']) { "From the landing zone $($a['OPS-03'])" } else { 'Shared connectivity' }) @{}
        & $add 'spoke' 'network' 'Spoke virtual network' 'Microsoft.Network/virtualNetworks' 'Spoke' '' 'The workload''s network, peered to the hub' @{}
        & $link 'hub' 'spoke' 'peering' 'control'
        if ($sensitive) { & $add 'dns' 'dns' 'Private DNS zones' 'Microsoft.Network/privateDnsZones' 'Hub' '' 'Resolve the private endpoints' @{} }
        if ($a['SEC-03'] -eq 'Inbound and outbound' -or $a['SEC-01'] -eq 'Regulated') { & $add 'firewall' 'firewall' 'Azure Firewall' 'Microsoft.Network/azureFirewalls' 'Hub' 'Premium' 'Inspects outbound traffic' @{}; & $link 'spoke' 'firewall' 'egress (route table)' 'control' }
    }
    # --- Pipeline ------------------------------------------------------------------------------------------------------
    if ($a['OPS-01'] -eq 'Manual') { & $add 'deploy' 'pipeline' 'Manual deployment' '' 'Pipeline' '' 'Deployed by hand' @{} '' }
    else {
        & $add 'repo' 'pipeline' $(if ($a['OPS-01'] -eq 'GitHub Actions') { 'GitHub repository (Bicep)' } else { 'Azure Repos (Bicep)' }) '' 'Pipeline' '' 'Infrastructure as code' @{} ''
        & $add 'gate' 'gate' 'PSRule for Azure gate' '' 'Pipeline' '' 'Validates the templates before deployment' @{} ''
        & $add 'deploy' 'pipeline' $(if ($a['OPS-01'] -eq 'GitHub Actions') { 'GitHub Actions: what-if, deploy' } else { 'Azure Pipelines: what-if, deploy' }) '' 'Pipeline' '' 'Deploys with workload identity federation' @{} ''
        & $link 'repo' 'gate' 'pull request' 'pipeline'
        & $link 'gate' 'deploy' 'passed' 'pipeline'
    }
    & $link 'deploy' 'compute' 'deploys' 'pipeline'

    # --- Overrides, then the second region ------------------------------------------------------------------------------
    foreach ($id in $Override.Keys) {
        $node = @($nodes | Where-Object { $_.Id -eq $id }) | Select-Object -First 1
        if (-not $node) { throw "Azure Admin Console can't override '$id': the design has no such component. Its components are $(@($nodes | ForEach-Object Id) -join ', ')." }
        foreach ($key in $Override[$id].Keys) {
            if ($key -eq 'Settings') { foreach ($s in $Override[$id]['Settings'].Keys) { $node.Settings[$s] = $Override[$id]['Settings'][$s] } }
            else { $node[$key] = $Override[$id][$key] }
        }
    }
    if ($needsSecond -and $regions.Count -lt 2) { $notices.Add("The answers call for a second region (RTO $($a['REL-01']) min, SLA $($a['REL-03'])%) - give two with -Region (for example -Region $($regions[0]), its pair).") }
    if ($multi) {
        $second = $regions[1]
        foreach ($node in @($nodes | Where-Object { $_.Zone -in 'Spoke', 'Data', 'Integration', 'Hub' -and $_.Kind -ne 'dns' })) {
            $copy = @{}; foreach ($k in $node.Keys) { $copy[$k] = $node[$k] }
            $copy.Settings = @{}; foreach ($k in $node.Settings.Keys) { $copy.Settings[$k] = $node.Settings[$k] }
            $copy.Id = "$($node.Id)-2"; $copy.Region = $second; $copy.Pattern = "Second region ($($node.Pattern))"
            $nodes.Add($copy)
        }
        foreach ($c in @($connections | Where-Object { $_.Kind -ne 'pipeline' })) {
            if ((& $has "$($c.From)-2") -and (& $has "$($c.To)-2")) { & $link "$($c.From)-2" "$($c.To)-2" $c.Label $c.Kind }
        }
        if (& $has 'edge') { & $link 'edge' $(if (& $has 'apim-2') { 'apim-2' } else { 'compute-2' }) 'HTTPS (failover)' }
        foreach ($id in 'data', 'lake', 'blob') { if (& $has $id) { & $link $id "$id-2" 'geo-replication' 'control' } }
        if (& $has 'hub-2') { & $link 'hub' 'hub-2' 'global peering' 'control' }
    }
    # Every component sends its logs to the workspace.
    foreach ($node in @($nodes | Where-Object { $_.Zone -in 'Edge', 'Spoke', 'Data', 'Integration', 'Hub' -and $_.Kind -notin 'network', 'dns' })) { & $link $node.Id 'law' 'diagnostics' 'control' }

    $policies = @(); $allowed = @(); $groups = @()
    if ($LandingZone) { $policies = @($LandingZone.Policies); $allowed = @($LandingZone.AllowedLocations); $groups = @($LandingZone.ManagementGroups) }
    @{
        Name = $Brief.Name; CatalogVersion = $Brief.CatalogVersion; Created = [datetime]::UtcNow.ToString('o'); Answers = $a; Open = @($Brief.Open); Assumed = @($Brief.Assumed)
        Patterns = @($Pattern); Regions = $(if ($multi) { @($regions[0..1]) } else { @($regions[0]) }); LandingZone = [string]$a['OPS-03']; ManagementGroups = $groups
        Policies = $policies; AllowedLocations = $allowed; Tags = $Tag; Commitment = $Commitment
        Nodes = $nodes.ToArray(); Connections = $connections.ToArray(); Notices = $notices.ToArray()
    }
}
