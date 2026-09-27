<#
    Governance check of a live Azure estate: every resource the signed-in
    account can see is tested against location, tagging, security,
    networking and operations rules. It only reads - nothing in Azure is
    changed.

    Data comes from Azure Resource Graph (resources, their settings and Azure
    Backup protected items) plus one Azure Monitor call per resource for the
    diagnostic-settings rule. Reader on the subscriptions is enough; the
    backup rule also needs Reader on the Recovery Services vaults, or every
    VM reports as unprotected.

    Needs a Connect-AAC sign-in in the same PowerShell session. Without one
    it reports a single Skipped test. Run it on its own with:

        Connect-AAC
        Invoke-AACPester -Path .\Azure.Admin.Console\Checks\AzureEstate.Tests.ps1 -Data @{
            SubscriptionId = '00000000-0000-0000-0000-000000000000'
        }

    Only some resource types, listing only the failures:

        Invoke-AACPester -Path .\Azure.Admin.Console\Checks\AzureEstate.Tests.ps1 -FailedOnly -Data @{
            ResourceType = 'microsoft.network/applicationgateways', 'microsoft.servicebus/*'
        }

    Each area is a Describe block tagged with its name, so -Tag picks areas:
        Governance  - approved region; required tags; Service Bus geo-replicas
                      in approved regions; Application Gateway, API
                      Management, Application Insights and Key Vault naming
                      (plus your own Application Insights name format, when
                      set); Key Vault key and secret names; storage
                      account names (plus your own name format, when set)
        Security    - storage HTTPS, minimum TLS 1.2, no anonymous blob
                      access, firewall, no shared key access, private
                      containers, Defender malware and sensitive data
                      scanning (and Defender per account, when asked for); Key Vault purge protection, RBAC, firewall,
                      audit logs, no all/purge access policies and keys
                      that rotate automatically; SQL public network
                      access; App Service HTTPS only; managed disks encrypted
                      with a customer-managed key; Service Bus local auth
                      disabled, minimum TLS 1.2 and audit logs (Premium);
                      Application Gateway WAF SKU and WAF enabled (Internet
                      facing), TLS 1.2 SSL policy, HTTP redirected to HTTPS,
                      classic WAF in prevention mode with OWASP 3.x and all
                      rules on; WAF policies enabled, in prevention mode,
                      without exclusions, with the default and bot rule sets;
                      API Management managed identity, no SSL 3.0 / TLS 1.0 /
                      TLS 1.1, no weak ciphers, APIs over HTTPS only, HTTPS
                      backends, named values in Key Vault, products need a
                      subscription and approval, no sample products, no
                      wildcard CORS, policies include <base />, APIs
                      protected by Defender for APIs; Application Insights
                      local authentication disabled; Logic Apps with an HTTP
                      request trigger limited to allowed caller IPs
        Networking  - no RDP/SSH from the Internet; public IPs attached;
                      VNets use custom (hub) DNS servers
        Operations  - VMs protected by Azure Backup (skipped for exempt
                      environments); diagnostic logs sent to Log Analytics;
                      Service Bus geo-replicated and in use; Application
                      Gateway 2+ instances, Medium or larger, v2 SKU, WAF
                      policy instead of classic WAF, availability zones; API
                      Management certificates not expiring within 30 days,
                      availability zones, multi-region with gateways
                      enabled, minimum API version 2021-08-01, APIs and
                      products described; Application Insights is
                      workspace-based; Managed Grafana on version 11 or
                      later and zone redundant; Key Vault soft delete;
                      storage geo/zone replication, blob, container and file
                      share soft delete

    The Service Bus, Application Gateway, API Management and Application
    Insights, Managed Grafana, Key Vault, Logic Apps and Storage rules follow
    PSRule for Azure's Azure.ServiceBus.*, Azure.AppGw.*, Azure.AppGwWAF.*,
    Azure.APIM.*, Azure.AppInsights.*, Azure.Grafana.*, Azure.KeyVault.*,
    Azure.LogicApp.* and Azure.Storage.* rules (https://azure.github.io/PSRule.Rules.Azure/),
    each named in its reason. The Service Bus in-use rule makes up to two
    Service Bus calls per namespace, and its audit-log rule one Azure
    Monitor call per Premium namespace. The zone rules read the
    Microsoft.Network, Microsoft.ApiManagement and Microsoft.Compute
    providers once per subscription to learn which regions have zones.

    API Management APIs, products, backends, named values, policies and
    Defender for APIs collections aren't in Resource Graph, so they are read
    from Azure Resource Manager: about six calls per API Management
    service, plus one per API and one per product for their policies. Each
    is read once however many rules use it. Operation-level policies aren't
    read (that would be one call per operation), and neither is the
    deprecated Azure.APIM.ProductTerms rule.

    Key Vault keys and secrets are listed through Azure Resource Manager
    (names and settings only - never the secret values or key material, and
    Reader is enough): two calls per vault. The audit-log rule shares the
    vault's diagnostic settings with the Log Analytics rule.

    Storage accounts' blob services, containers, file services (FileStorage
    accounts only) and Defender for Storage settings are read the same way:
    up to three calls per account.

    Run only the API Management checks with:

        Invoke-AACPester -Path .\Azure.Admin.Console\Checks\AzureEstate.Tests.ps1 -Data @{
            ResourceType = 'microsoft.apimanagement/service'
        }
#>

param(
    # Defaults to every subscription the signed-in account can see.
    [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
    [string[]] $SubscriptionId = @(),

    # Only check resources of these types, e.g.
    # 'microsoft.network/applicationgateways'. Case-insensitive; wildcards
    # work ('microsoft.network/*'). Defaults to every type.
    [string[]] $ResourceType = @(),

    # Compared case-insensitively with spaces removed ('UK South' = 'uksouth').
    # "global" is where Azure keeps resources that can't be placed in a region
    # (DNS zones, Front Door, action groups, ...).
    [string[]] $AllowedLocation = @('uksouth', 'ukwest', 'global'),

    # Tag names every resource must have (names compared case-insensitively).
    [string[]] $RequiredTag = @('Owner', 'CostCenter', 'Environment'),

    # The DNS servers every VNet must use, e.g. the hub's resolvers. Leave
    # empty to accept any custom DNS and fail only Azure-provided DNS.
    [string[]] $DnsServer = @(),

    # Resource ID of the Log Analytics workspace diagnostic logs must go to.
    # Leave empty to accept any workspace.
    [string] $LogAnalyticsWorkspaceId = '',

    # A regular expression every Application Insights name must match, e.g.
    # '^appi-' (case-sensitive). Leave empty to skip that check, as PSRule
    # does when AZURE_APP_INSIGHTS_NAME_FORMAT isn't set.
    [string] $AppInsightsNameFormat = '',

    # A regular expression every storage account name must match, e.g.
    # '^st' (case-sensitive). Leave empty to skip that check, as PSRule does
    # when AZURE_STORAGE_ACCOUNT_NAME_FORMAT isn't set.
    [string] $StorageAccountNameFormat = '',

    # True to require Microsoft Defender for Storage to be enabled on each
    # account itself, as PSRule's AZURE_STORAGE_DEFENDER_PER_ACCOUNT does -
    # leave False when Defender is enabled for whole subscriptions.
    [bool] $StorageDefenderPerAccount = $false,

    # VMs whose Environment tag is one of these don't need a backup.
    [string[]] $BackupExemptEnvironment = @('dev'),

    # Resource types the diagnostic-logs rule applies to. One Azure Monitor
    # call is made per resource of these types.
    [string[]] $DiagnosticResourceType = @(
        'microsoft.keyvault/vaults'
        'microsoft.web/sites'
        'microsoft.sql/servers/databases'
        'microsoft.network/networksecuritygroups'
    )
)

BeforeDiscovery {
    # Import only if not already loaded - a -Force reimport would replace the
    # module Invoke-AACPester is running from and clear the Connect-AAC sign-in.
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $module = Get-Module -Name 'Azure.Admin.Console'

    # Exactly one of these ends up non-empty, and decides which tests exist.
    $areas = @()
    $notConnectedCase = @()
    $noResourcesCase = @()
    $readErrorCase = @()

    # --- Helpers (discovery only - nothing here writes to the console, as
    # Invoke-AACPester's spinner is live while this runs) -----------------------

    # Reads a dotted path like 'properties.encryption.type' from the parsed
    # JSON (hashtables) or any other object, returning $null for any missing
    # step instead of throwing. Hashtable keys are matched exactly first, then
    # ignoring case. A missing value outputs nothing, so @(Get-Value ...) is
    # an empty list rather than a list holding one $null.
    function Get-Value {
        param($InputObject, [string] $Path)
        $value = $InputObject
        foreach ($part in $Path.Split('.')) {
            if ($null -eq $value) {
                return
            }
            if ($value -is [System.Collections.IDictionary]) {
                $key = if ($value.Contains($part)) { $part } else { $value.Keys | Where-Object { $_ -eq $part } | Select-Object -First 1 }
                $value = if ($null -ne $key) { $value[$key] } else { $null }
            }
            else {
                $property = $value.PSObject.Properties[$part]
                $value = if ($property) { $property.Value } else { $null }
            }
        }
        if ($null -ne $value) {
            $value
        }
    }

    # Tag names are case-insensitive in Azure, and -eq is too. A resource can
    # still carry both 'Owner' and 'owner'; the first non-empty one wins.
    function Get-TagValue {
        param($Tags, [string] $Name)
        if ($Tags -isnot [System.Collections.IDictionary]) {
            return $null
        }
        foreach ($tag in $Tags.GetEnumerator()) {
            if ($tag.Key -eq $Name -and -not [string]::IsNullOrWhiteSpace([string]$tag.Value)) {
                return [string]$tag.Value
            }
        }
        $null
    }

    # Moves on a line of Invoke-AACPester's progress display (see
    # Update-AACProgress); does nothing under plain Invoke-Pester.
    function Write-CheckProgress {
        param([string] $Id, [string] $Description, [double] $Total, [double] $Increment, [switch] $Complete)
        & $module { param($Parameters) Update-AACProgress @Parameters } $PSBoundParameters
    }

    # A fresh header per call, so a long run keeps working after the token's
    # hour is up (Get-AACAccessToken refreshes it).
    function Get-AuthHeader {
        @{ Authorization = "Bearer $(& $module { Get-AACAccessToken })" }
    }

    # Calls Azure Resource Manager and returns the JSON as hashtables.
    # Invoke-RestMethod can't be used: it silently returns the raw text when
    # the JSON has keys differing only by case - which tags often do
    # ('Owner' and 'owner' on one resource) - and ConvertFrom-Json -AsHashtable
    # accepts them. Retries throttled (429) and transient 5xx responses,
    # honouring Retry-After.
    function Invoke-Arm {
        param([string] $Method = 'Get', [string] $Uri, [string] $Body)
        for ($attempt = 1; ; $attempt++) {
            try {
                # No web-request progress bar or verbose line per call: they
                # would draw over Invoke-AACPester's progress display.
                $ProgressPreference = 'SilentlyContinue'
                $request = @{ Method = $Method; Uri = $Uri; Headers = (Get-AuthHeader); ErrorAction = 'Stop'; Verbose = $false }
                if ($Body) {
                    $request.Body = $Body
                    $request.ContentType = 'application/json'
                }
                $content = (Invoke-WebRequest @request).Content
                if ($content -is [byte[]]) {
                    $content = [System.Text.Encoding]::UTF8.GetString($content)
                }
                if ([string]::IsNullOrWhiteSpace($content)) {
                    return $null
                }
                return ConvertFrom-Json -InputObject $content -AsHashtable -Depth 100
            }
            catch {
                # Network failures (DNS, TLS, ...) have no Response at all.
                $status = [int](Get-Value $_.Exception 'Response.StatusCode')
                if ($attempt -ge 4 -or ($status -ne 429 -and $status -lt 500)) {
                    $details = Get-Value $_ 'ErrorDetails.Message'
                    throw "$(if ($details) { $details } else { $_.Exception.Message })"
                }
                $retryAfter = Get-Value $_.Exception 'Response.Headers.RetryAfter.Delta'
                Start-Sleep -Seconds $(if ($retryAfter) { [math]::Min(60, $retryAfter.TotalSeconds) } else { 5 * $attempt })
            }
        }
    }

    # Runs a Resource Graph query over the chosen subscriptions (all visible
    # ones when none are given), following $skipToken paging.
    function Invoke-Graph {
        param([string] $Query)
        $body = @{ query = $Query; options = @{ resultFormat = 'objectArray' } }
        if ($SubscriptionId.Count -gt 0) {
            $body.subscriptions = @($SubscriptionId)
        }
        do {
            $response = Invoke-Arm -Method 'Post' -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body ($body | ConvertTo-Json -Depth 10)
            Get-Value $response 'data'
            $skipToken = Get-Value $response '$skipToken'
            $body.options['$skipToken'] = $skipToken
        } while ($skipToken)
    }

    # True when an NSG port range ('*', '22', '20-25') covers any of $Port.
    function Test-PortRange {
        param([string[]] $Range, [int[]] $Port)
        foreach ($item in $Range) {
            if ($item -eq '*') {
                return $true
            }
            $low, $high = $item.Split('-')
            if (-not $high) {
                $high = $low
            }
            if (@($Port | Where-Object { $_ -ge [int]$low -and $_ -le [int]$high }).Count -gt 0) {
                return $true
            }
        }
        $false
    }

    # A resource's diagnostic settings, read once however many rules use them.
    # Throws when they can't be read.
    $diagnosticSettings = @{}
    function Get-DiagnosticSetting {
        param([string] $ResourceId)
        if (-not $diagnosticSettings.ContainsKey($ResourceId)) {
            $response = Invoke-Arm -Uri "https://management.azure.com$ResourceId/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
            $diagnosticSettings[$ResourceId] = @(Get-Value $response 'value')
        }
        $diagnosticSettings[$ResourceId]
    }

    # True when a Service Bus namespace has at least one queue or topic.
    # Basic namespaces have no topics, so only their queues are asked for.
    function Test-ServiceBusInUse {
        param($Namespace)
        $children = if ((Get-Value $Namespace 'sku.name') -eq 'Basic') { 'queues' } else { 'queues', 'topics' }
        foreach ($child in $children) {
            $response = Invoke-Arm -Uri "https://management.azure.com$($Namespace.id)/$($child)?api-version=2021-11-01&`$top=1"
            if (@(Get-Value $response 'value').Count -gt 0) {
                return $true
            }
        }
        $false
    }

    # True when a version string like '3.2' is at least $Minimum (and below
    # $Below, when given). A version that can't be parsed never qualifies.
    function Test-Version {
        param([string] $Version, [string] $Minimum, [string] $Below)
        $parsed = $null
        if (-not [version]::TryParse($Version, [ref]$parsed)) {
            return $false
        }
        $parsed -ge [version]$Minimum -and (-not $Below -or $parsed -lt [version]$Below)
    }

    # Application Gateway facts several rules depend on.
    function Test-AppGwPublic {
        param($Gateway)
        @(Get-Value $Gateway 'props.frontendIPConfigurations' | Where-Object { Get-Value $_ 'properties.publicIPAddress.id' }).Count -gt 0
    }
    # A WAF-tier gateway configured with the classic (in-gateway) WAF settings
    # rather than a WAF policy.
    function Test-AppGwClassicWaf {
        param($Gateway)
        (Get-Value $Gateway 'props.sku.tier') -in 'WAF', 'WAF_v2' -and
        (Get-Value $Gateway 'props.webApplicationFirewallConfiguration.enabled') -eq $true
    }

    # The availability zones a resource type offers in a region, as its
    # resource provider reports them - read once per subscription and
    # provider. Nothing is returned for a region without zones.
    $providerZones = @{}
    function Get-ProviderZone {
        param([string] $Subscription, [string] $Namespace, [string] $ResourceType, [string] $Location)
        $key = "$Subscription|$Namespace/$ResourceType".ToLowerInvariant()
        if (-not $providerZones.ContainsKey($key)) {
            $zonesByRegion = @{}
            $provider = Invoke-Arm -Uri "https://management.azure.com/subscriptions/$Subscription/providers/$($Namespace)?api-version=2021-04-01"
            $type = Get-Value $provider 'resourceTypes' | Where-Object { (Get-Value $_ 'resourceType') -eq $ResourceType } | Select-Object -First 1
            foreach ($mapping in @(Get-Value $type 'zoneMappings')) {
                $zonesByRegion[((Get-Value $mapping 'location') -replace '\s', '').ToLowerInvariant()] = @(Get-Value $mapping 'zones' | Sort-Object)
            }
            $providerZones[$key] = $zonesByRegion
        }
        $zones = $providerZones[$key][($Location -replace '\s', '').ToLowerInvariant()]
        if ($zones) {
            $zones
        }
    }

    # --- API Management ---------------------------------------------------------
    # Every item of an ARM list, following nextLink paging.
    function Get-ArmList {
        param([string] $Uri)
        while ($Uri) {
            $response = Invoke-Arm -Uri $Uri
            Get-Value $response 'value'
            $Uri = Get-Value $response 'nextLink'
        }
    }

    # A child collection of a resource (an API Management service's 'apis',
    # a Key Vault's 'keys', ...), read once however many rules use it. A
    # failed read is remembered and thrown again each time.
    $childCache = @{}
    function Get-ResourceChild {
        param($Resource, [string] $Child, [Parameter(Mandatory)] [string] $ApiVersion)
        $key = "$($Resource.id)|$Child"
        if (-not $childCache.ContainsKey($key)) {
            try {
                $childCache[$key] = @{ Items = @(Get-ArmList "https://management.azure.com$($Resource.id)/$($Child)?api-version=$ApiVersion") }
            }
            catch {
                $childCache[$key] = @{ Error = "could not read $($Child): $($_.Exception.Message)" }
            }
        }
        $entry = $childCache[$key]
        if ($entry.ContainsKey('Error')) {
            throw $entry.Error
        }
        $entry.Items
    }

    # API Management children ('apis', 'products', 'backends', ...).
    function Get-ApimChild {
        param($Service, [string] $Child, [string] $ApiVersion = '2022-08-01')
        Get-ResourceChild $Service $Child -ApiVersion $ApiVersion
    }

    # The service's APIs - current revisions only, as the portal lists them.
    function Get-ApimApi {
        param($Service)
        Get-ApimChild $Service 'apis' | Where-Object { (Get-Value $_ 'properties.isCurrent') -ne $false }
    }

    # Every policy document of a service: the global one, and one per API and
    # per product that has its own. Each is @{ Where; Global; Xml } with Xml
    # $null (and ParseError set) when the document isn't valid XML.
    function Get-ApimPolicy {
        param($Service)
        $key = "$($Service.id)|policy-documents"
        if (-not $childCache.ContainsKey($key)) {
            try {
                $sources = @(
                    @{ Where = 'service (global)'; Global = $true; Path = 'policies' }
                    foreach ($api in @(Get-ApimApi $Service)) {
                        @{ Where = "API '$($api.name)'"; Global = $false; Path = "apis/$([uri]::EscapeDataString($api.name))/policies" }
                    }
                    foreach ($product in @(Get-ApimChild $Service 'products')) {
                        @{ Where = "product '$($product.name)'"; Global = $false; Path = "products/$([uri]::EscapeDataString($product.name))/policies" }
                    }
                )
                $documents = @(foreach ($source in $sources) {
                        foreach ($policy in @(Get-ArmList "https://management.azure.com$($Service.id)/$($source.Path)?api-version=2022-08-01")) {
                            $value = [string](Get-Value $policy 'properties.value')
                            if (-not $value) {
                                continue
                            }
                            $document = @{ Where = $source.Where; Global = $source.Global; Xml = $null; ParseError = $null }
                            try {
                                $document.Xml = [xml]$value
                            }
                            catch {
                                $document.ParseError = $_.Exception.Message
                            }
                            $document
                        }
                    })
                $childCache[$key] = @{ Items = $documents }
            }
            catch {
                $childCache[$key] = @{ Error = "could not read policies: $($_.Exception.Message)" }
            }
        }
        $entry = $childCache[$key]
        if ($entry.ContainsKey('Error')) {
            throw $entry.Error
        }
        $entry.Items
    }

    # Runs a rule's child-resource logic (API Management, Key Vault),
    # turning a failed read into the
    # rule's Error result instead of failing the whole run.
    function Invoke-ChildRule {
        param([scriptblock] $Rule)
        try {
            & $Rule
        }
        catch {
            @{ Mode = 'Error'; Actual = $_.Exception.Message }
        }
    }

    # True when a customProperties flag is 'True'. Unset means the default,
    # which for these protocols and ciphers is off on new services.
    function Test-ApimFlagOn {
        param($Service, [string] $Name)
        $properties = Get-Value $Service 'props.customProperties'
        $value = if ($properties -is [System.Collections.IDictionary] -and $properties.Contains($Name)) { $properties[$Name] }
        $null -ne $value -and [string]$value -eq 'true'
    }

    # The availability zone problems of one API Management location (the
    # primary or an additional one), or nothing when it is fine.
    function Get-ApimZoneProblem {
        param([string] $Subscription, [string] $Location, $Zones, $Capacity)
        $offered = @(Get-ProviderZone -Subscription $Subscription -Namespace 'Microsoft.ApiManagement' -ResourceType 'service' -Location $Location)
        if ($offered.Count -eq 0) {
            return
        }
        $zones = @($Zones | Where-Object { $_ })
        if ($zones.Count -lt 2 -or [int]$Capacity -lt $zones.Count) {
            "$Location - zones $(if ($zones) { $zones -join ', ' } else { 'none' }), $Capacity unit(s); the region offers $($offered -join ', ')"
        }
    }

    # A vault's keys and secrets (metadata only), through Azure Resource
    # Manager rather than the vault's data plane.
    function Get-KeyVaultChild {
        param($Vault, [string] $Child)
        Get-ResourceChild $Vault $Child -ApiVersion '2023-07-01'
    }

    # Key and secret names: 1-127 letters, numbers or -.
    function Get-InvalidKeyVaultName {
        param($Items)
        @($Items | ForEach-Object { $_.name.Split('/')[-1] } | Where-Object { $_ -cnotmatch '^[A-Za-z0-9-]{1,127}$' })
    }

    # --- Storage ------------------------------------------------------------------
    # What PSRule's storage rules key on: the account kind, Azure-managed
    # accounts (Cloud Shell, Functions, Monitor), hierarchical namespace and
    # large file shares.
    function Test-StorageKind {
        param($Account, [string] $Kind)
        (Get-Value $Account 'kind') -eq $Kind
    }
    function Test-StorageUsage {
        param($Account, [string] $Tag, [string] $Value)
        (Get-TagValue $Account.tags $Tag) -eq $Value
    }
    function Test-CloudShellStorage {
        param($Account)
        Test-StorageUsage $Account 'ms-resource-usage' 'azure-cloud-shell'
    }
    function Test-HnsStorage {
        param($Account)
        (Get-Value $Account 'props.isHnsEnabled') -eq $true
    }

    # Blob services, containers and file services, through Azure Resource Manager.
    function Get-StorageChild {
        param($Account, [string] $Child)
        Get-ResourceChild $Account $Child -ApiVersion '2023-01-01'
    }

    # The account's Microsoft Defender for Storage settings, or nothing when
    # the account has none of its own. Read once per account.
    $storageDefender = @{}
    function Get-StorageDefenderSetting {
        param($Account)
        if (-not $storageDefender.ContainsKey($Account.id)) {
            try {
                $storageDefender[$Account.id] = @{ Setting = (Invoke-Arm -Uri "https://management.azure.com$($Account.id)/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2022-12-01-preview") }
            }
            catch {
                $storageDefender[$Account.id] = if ($_.Exception.Message -match 'NotFound|404|could not be found|does not exist') {
                    @{ Setting = $null }
                }
                else {
                    @{ Error = "could not read Defender for Storage settings: $($_.Exception.Message)" }
                }
            }
        }
        $entry = $storageDefender[$Account.id]
        if ($entry.ContainsKey('Error')) {
            throw $entry.Error
        }
        $entry.Setting
    }

    # Defender for Storage scans only accounts reachable from public networks.
    function Test-StoragePublicNetwork {
        param($Account)
        $access = Get-Value $Account 'props.publicNetworkAccess'
        -not $access -or $access -eq 'Enabled'
    }

    if (-not $global:AACSession) {
        $notConnectedCase = @(@{})
    }
    else {
        try {
            # --- Read the estate ----------------------------------------------
            # Full properties only for the types a rule inspects - the rest
            # would only make the response bigger.
            $inspected = @(
                'microsoft.storage/storageaccounts', 'microsoft.keyvault/vaults', 'microsoft.sql/servers', 'microsoft.web/sites'
                'microsoft.compute/disks', 'microsoft.network/networksecuritygroups', 'microsoft.network/publicipaddresses'
                'microsoft.network/virtualnetworks', 'microsoft.servicebus/namespaces', 'microsoft.network/applicationgateways'
                'microsoft.network/applicationgatewaywebapplicationfirewallpolicies', 'microsoft.apimanagement/service'
                'microsoft.insights/components', 'microsoft.dashboard/grafana', 'microsoft.logic/workflows'
            )
            $typeList = ($inspected | ForEach-Object { "'$_'" }) -join ', '
            Write-CheckProgress -Id 'estate-read' -Total 3 -Description 'Reading resources from Azure Resource Graph'
            $resources = @(Invoke-Graph -Query @"
Resources
| extend props = iff(type in~ ($typeList), properties, dynamic(null))
| project id, name, type = tolower(type), kind, location, resourceGroup, subscriptionId, tags, sku, zones, identity, props
| order by type asc, name asc
"@)
            if ($ResourceType.Count -gt 0) {
                $resources = @($resources | Where-Object {
                        $type = $_.type
                        @($ResourceType | Where-Object { $type -like $_ }).Count -gt 0
                    })
            }

            Write-CheckProgress -Id 'estate-read' -Increment 1 -Description 'Reading subscription names'
            $subscriptionNames = @{}
            foreach ($row in @(Invoke-Graph -Query "ResourceContainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name")) {
                $subscriptionNames[$row.subscriptionId] = $row.name
            }

            # VM resource ID (lower case) -> protection state of its Azure Backup item.
            Write-CheckProgress -Id 'estate-read' -Increment 1 -Description 'Reading Azure Backup protection'
            $backupState = @{}
            foreach ($row in @(Invoke-Graph -Query @"
RecoveryServicesResources
| where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
| where properties.backupManagementType =~ 'AzureIaasVM'
| project vmId = tolower(tostring(coalesce(properties.dataSourceInfo.resourceID, properties.sourceResourceId))),
          state = tostring(coalesce(properties.currentProtectionState, properties.protectionState))
"@)) {
                if ($row.vmId) {
                    $backupState[$row.vmId] = if ($row.state) { $row.state } else { 'Protected' }
                }
            }
            $subscriptionCount = @($resources | ForEach-Object { $_.subscriptionId } | Select-Object -Unique).Count
            Write-CheckProgress -Id 'estate-read' -Complete -Description ('Read {0:N0} resources in {1:N0} subscription(s)' -f $resources.Count, $subscriptionCount)

            # --- The rules --------------------------------------------------------
            # Each rule applies to some resource types (or all of them) and
            # returns, per resource, the setting found (Actual) and how the test
            # checks it (Mode):
            #   Equal    - Actual must equal Expected
            #   NotEqual - Actual must not equal Expected
            #   In       - Actual must be one of Expected (a list)
            #   Empty    - Actual lists what's wrong, and must be empty
            #   Contain  - Actual is a list that must contain Expected
            #   NotEmpty - Actual must not be empty
            #   Error    - the setting couldn't be read; Actual is the reason
            # Returning Skip = $true (with SkipReason) reports the test as Skipped.
            $allowed = @($AllowedLocation | ForEach-Object { ($_ -replace '\s', '').ToLowerInvariant() })
            $internet = '*', 'internet', 'any', '0.0.0.0/0', '::/0'
            $appGwType = 'microsoft.network/applicationgateways'
            $wafPolicyType = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'
            $apimType = 'microsoft.apimanagement/service'
            $storageType = 'microsoft.storage/storageaccounts'
            $appInsightsType = 'microsoft.insights/components'
            $grafanaType = 'microsoft.dashboard/grafana'
            $apimProtocols = [ordered]@{
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30'         = 'SSL 3.0 (clients)'
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10'         = 'TLS 1.0 (clients)'
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11'         = 'TLS 1.1 (clients)'
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30' = 'SSL 3.0 (backends)'
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10' = 'TLS 1.0 (backends)'
                'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11' = 'TLS 1.1 (backends)'
            }
            # TripleDes168 is off unless set; the others are on unless set to False.
            $apimCipherPrefix = 'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.'
            $apimWeakCiphers = @(
                'TLS_RSA_WITH_AES_128_CBC_SHA', 'TLS_RSA_WITH_AES_256_CBC_SHA', 'TLS_RSA_WITH_AES_128_CBC_SHA256'
                'TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA', 'TLS_RSA_WITH_AES_256_CBC_SHA256', 'TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA'
                'TLS_RSA_WITH_AES_128_GCM_SHA256'
            )

            $rules = @(
                @{ Area = 'Governance'; Check = 'Deployed in an approved region'; Types = '*'
                    Because  = "resources must stay in $($allowed -join ' / ')"
                    Evaluate = { param($r) @{ Mode = 'In'; Actual = ([string]$r.location -replace '\s', '').ToLowerInvariant(); Expected = $allowed } } 
                }
                @{ Area = 'Governance'; Check = "Has the $($RequiredTag -join ', ') tags"; Types = '*'
                    Because  = 'every resource needs these tags for ownership and cost reporting'
                    Evaluate = { param($r)
                        $missing = @($RequiredTag | Where-Object { [string]::IsNullOrWhiteSpace((Get-TagValue $r.tags $_)) })
                        @{ Mode = 'Empty'; Actual = ($missing -join ', ') } } 
                }
                @{ Area = 'Governance'; Check = 'Service Bus geo-replicas are in approved regions'; Types = 'microsoft.servicebus/namespaces'
                    Because  = "replicas must stay in $($allowed -join ' / ') (PSRule Azure.ServiceBus.ReplicaLocation)"
                    Evaluate = { param($r)
                        # Only namespaces that are geo-replicated get this test.
                        $replicas = @(Get-Value $r 'props.geoDataReplication.locations' | ForEach-Object { Get-Value $_ 'locationName' })
                        if ($replicas.Count -eq 0) {
                            return $null
                        }
                        $outside = @($replicas | Where-Object { ($_ -replace '\s', '').ToLowerInvariant() -notin $allowed })
                        @{ Mode = 'Empty'; Actual = ($outside -join ', ') } }
                }
                @{ Area = 'Governance'; Check = 'Application Gateway name meets the naming rules'; Types = $appGwType
                    Because  = '1-80 letters, numbers, _ . or -, starting with a letter or number and ending with a letter, number or _ (PSRule Azure.AppGw.Name)'
                    Evaluate = { param($r)
                        $valid = $r.name -cmatch '^[A-Za-z0-9]([\w.-]{0,78}[\w])?$'
                        @{ Mode = 'Empty'; Actual = $(if (-not $valid) { "'$($r.name)' is not a valid name" }) } }
                }
                @{ Area = 'Governance'; Check = 'API Management name meets the naming rules'; Types = $apimType
                    Because  = '1-50 letters, numbers or -, starting with a letter and ending with a letter or number (PSRule Azure.APIM.Name)'
                    Evaluate = { param($r)
                        $valid = $r.name.Length -le 50 -and $r.name -cmatch '^[a-zA-Z]([A-Za-z0-9-]*[a-zA-Z0-9]){0,49}$'
                        @{ Mode = 'Empty'; Actual = $(if (-not $valid) { "'$($r.name)' is not a valid name" }) } }
                }
                @{ Area = 'Governance'; Check = 'Application Insights name meets the naming rules'; Types = $appInsightsType
                    Because  = '1-255 letters, numbers, . - _ ( or ), not ending with a period (PSRule Azure.AppInsights.Name)'
                    Evaluate = { param($r)
                        $valid = $r.name.Length -le 255 -and $r.name -match '^[a-z0-9.\-_()]{0,254}[a-z0-9\-_()]$'
                        @{ Mode = 'Empty'; Actual = $(if (-not $valid) { "'$($r.name)' is not a valid name" }) } }
                }
                @{ Area = 'Governance'; Check = "Application Insights name matches $AppInsightsNameFormat"; Types = $appInsightsType
                    Because  = 'names must follow the organisation''s naming standard (PSRule Azure.AppInsights.Naming)'
                    Evaluate = { param($r)
                        # Only when a name format is given.
                        if (-not $AppInsightsNameFormat) {
                            return $null
                        }
                        @{ Mode = 'Empty'; Actual = $(if ($r.name -cnotmatch $AppInsightsNameFormat) { "'$($r.name)' does not match" }) } }
                }
                @{ Area = 'Governance'; Check = 'Storage account name meets the naming rules'; Types = $storageType
                    Because  = '3-24 lowercase letters or numbers (PSRule Azure.Storage.Name)'
                    Evaluate = { param($r)
                        $valid = $r.name -cmatch '^[a-z0-9]{3,24}$'
                        @{ Mode = 'Empty'; Actual = $(if (-not $valid) { "'$($r.name)' is not a valid name" }) } }
                }
                @{ Area = 'Governance'; Check = "Storage account name matches $StorageAccountNameFormat"; Types = $storageType
                    Because  = 'names must follow the organisation''s naming standard (PSRule Azure.Storage.Naming)'
                    Evaluate = { param($r)
                        # Only when a name format is given; Cloud Shell names its own accounts.
                        if (-not $StorageAccountNameFormat -or (Test-CloudShellStorage $r)) {
                            return $null
                        }
                        @{ Mode = 'Empty'; Actual = $(if ($r.name -cnotmatch $StorageAccountNameFormat) { "'$($r.name)' does not match" }) } }
                }
                @{ Area = 'Governance'; Check = 'Key Vault name meets the naming rules'; Types = 'microsoft.keyvault/vaults'
                    Because  = '3-24 letters, numbers or -, starting with a letter and ending with a letter or number (PSRule Azure.KeyVault.Name)'
                    Evaluate = { param($r)
                        $valid = $r.name.Length -ge 3 -and $r.name.Length -le 24 -and $r.name -match '^[A-Za-z](-|[A-Za-z0-9])*[A-Za-z0-9]$'
                        @{ Mode = 'Empty'; Actual = $(if (-not $valid) { "'$($r.name)' is not a valid name" }) } }
                }
                @{ Area = 'Governance'; Check = 'Key Vault secret names meet the naming rules'; Types = 'microsoft.keyvault/vaults'
                    Because  = '1-127 letters, numbers or - (PSRule Azure.KeyVault.SecretName)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $invalid = Get-InvalidKeyVaultName (Get-KeyVaultChild $r 'secrets')
                            @{ Mode = 'Empty'; Actual = $(if ($invalid) { "invalid: $($invalid -join ', ')" }) }
                        } }
                }
                @{ Area = 'Governance'; Check = 'Key Vault key names meet the naming rules'; Types = 'microsoft.keyvault/vaults'
                    Because  = '1-127 letters, numbers or - (PSRule Azure.KeyVault.KeyName)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $invalid = Get-InvalidKeyVaultName (Get-KeyVaultChild $r 'keys')
                            @{ Mode = 'Empty'; Actual = $(if ($invalid) { "invalid: $($invalid -join ', ')" }) }
                        } }
                }

                @{ Area = 'Security'; Check = 'Storage requires secure transfer (HTTPS)'; Types = 'microsoft.storage/storageaccounts'
                    Because  = 'supportsHttpsTrafficOnly must be enabled (PSRule Azure.Storage.SecureTransfer)'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.supportsHttpsTrafficOnly') -eq $true; Expected = $true } } 
                }
                @{ Area = 'Security'; Check = 'Storage minimum TLS version is 1.2'; Types = 'microsoft.storage/storageaccounts'
                    Because  = 'TLS 1.0 and 1.1 are retired (PSRule Azure.Storage.MinTLS)'
                    Evaluate = { param($r)
                        $tls = Get-Value $r 'props.minimumTlsVersion'
                        @{ Mode = 'In'; Actual = $(if ($tls) { $tls } else { 'TLS1_0 (not set)' }); Expected = @('TLS1_2', 'TLS1_3') } } 
                }
                @{ Area = 'Security'; Check = 'Storage blocks anonymous blob access'; Types = 'microsoft.storage/storageaccounts'
                    Because  = 'allowBlobPublicAccess must be disabled (older accounts allow it when it is not set) (PSRule Azure.Storage.BlobPublicAccess)'
                    Evaluate = { param($r)
                        # FileStorage accounts have no blob service.
                        if (Test-StorageKind $r 'FileStorage') {
                            return $null
                        }
                        $public = Get-Value $r 'props.allowBlobPublicAccess'
                        @{ Mode = 'Equal'; Actual = $(if ($null -eq $public) { 'not set' } else { $public }); Expected = $false } } 
                }
                @{ Area = 'Security'; Check = 'Storage firewall denies by default'; Types = $storageType
                    Because  = 'only allowed networks and private endpoints may reach the account (PSRule Azure.Storage.Firewall)'
                    Evaluate = { param($r)
                        if (Test-CloudShellStorage $r) {
                            return $null
                        }
                        $action = Get-Value $r 'props.networkAcls.defaultAction'
                        @{ Mode = 'Equal'; Actual = $(if ($action) { $action } else { 'Allow (not set)' }); Expected = 'Deny' } }
                }
                @{ Area = 'Security'; Check = 'Storage shared key access is disabled'; Types = $storageType
                    Because  = 'clients must authenticate with Entra ID, not the account keys (PSRule Azure.Storage.LocalAuth)'
                    Evaluate = { param($r)
                        $shared = Get-Value $r 'props.allowSharedKeyAccess'
                        @{ Mode = 'Equal'; Actual = $(if ($null -eq $shared) { 'not set (allowed)' } else { $shared }); Expected = $false } }
                }
                @{ Area = 'Security'; Check = 'Storage containers are private'; Types = $storageType
                    Because  = 'no container may allow anonymous access - public access must be None (PSRule Azure.Storage.BlobAccessType)'
                    Evaluate = { param($r)
                        if (Test-StorageKind $r 'FileStorage') {
                            return $null
                        }
                        Invoke-ChildRule {
                            $public = @(Get-StorageChild $r 'blobServices/default/containers' | ForEach-Object {
                                    $access = Get-Value $_ 'properties.publicAccess'
                                    if ($access -and $access -ne 'None') { "$($_.name) ($access)" }
                                })
                            @{ Mode = 'Empty'; Actual = $(if ($public) { "public containers: $($public -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'Storage has Defender malware scanning on upload'; Types = $storageType
                    Because  = 'uploads must be scanned for malware - it must not be turned off for the account (PSRule Azure.Storage.Defender.MalwareScan)'
                    Evaluate = { param($r)
                        if (-not (Test-StoragePublicNetwork $r)) {
                            return $null
                        }
                        Invoke-ChildRule {
                            $setting = Get-StorageDefenderSetting $r
                            $off = $setting -and (Get-Value $setting 'properties.malwareScanning.onUpload.isEnabled') -eq $false
                            @{ Mode = 'Empty'; Actual = $(if ($off) { 'malware scanning on upload is turned off for the account' }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'Storage has Defender sensitive data discovery'; Types = $storageType
                    Because  = 'sensitive data threat detection must not be turned off for the account (PSRule Azure.Storage.Defender.DataScan, preview)'
                    Evaluate = { param($r)
                        if (-not (Test-StoragePublicNetwork $r)) {
                            return $null
                        }
                        Invoke-ChildRule {
                            $setting = Get-StorageDefenderSetting $r
                            $off = $setting -and (Get-Value $setting 'properties.sensitiveDataDiscovery.isEnabled') -eq $false
                            @{ Mode = 'Empty'; Actual = $(if ($off) { 'sensitive data discovery is turned off for the account' }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'Storage has Defender for Storage enabled on the account'; Types = $storageType
                    Because  = 'Defender for Storage must be enabled on each account (PSRule Azure.Storage.DefenderCloud)'
                    Evaluate = { param($r)
                        # Only when asked for: Defender is usually enabled per subscription.
                        if (-not $StorageDefenderPerAccount) {
                            return $null
                        }
                        Invoke-ChildRule {
                            $setting = Get-StorageDefenderSetting $r
                            $enabled = $setting -and (Get-Value $setting 'properties.isEnabled') -eq $true
                            @{ Mode = 'Empty'; Actual = $(if (-not $enabled) { 'Defender for Storage is not enabled on the account' }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'Key Vault has purge protection'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'deleted secrets, keys and certificates must be recoverable (PSRule Azure.KeyVault.PurgeProtect)'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.enablePurgeProtection') -eq $true; Expected = $true } } 
                }
                @{ Area = 'Security'; Check = 'Key Vault uses Azure RBAC'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'access must be granted with Azure role assignments, not vault access policies (PSRule Azure.KeyVault.RBAC)'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.enableRbacAuthorization') -eq $true; Expected = $true } }
                }
                @{ Area = 'Security'; Check = 'Key Vault firewall denies by default'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'only allowed networks and private endpoints may reach the vault (PSRule Azure.KeyVault.Firewall)'
                    Evaluate = { param($r)
                        $action = Get-Value $r 'props.networkAcls.defaultAction'
                        @{ Mode = 'Equal'; Actual = $(if ($action) { $action } else { 'Allow (not set)' }); Expected = 'Deny' } }
                }
                @{ Area = 'Security'; Check = 'Key Vault access policies do not grant all or purge'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'access policies must be least privilege - no All or Purge permission (PSRule Azure.KeyVault.AccessPolicy)'
                    Evaluate = { param($r)
                        $broad = @(foreach ($policy in @(Get-Value $r 'props.accessPolicies')) {
                                $granted = @(foreach ($kind in 'keys', 'secrets', 'certificates', 'storage') {
                                        $permissions = @(Get-Value $policy "permissions.$kind" | Where-Object { $_ -in 'All', 'Purge' })
                                        if ($permissions) { "$kind $($permissions -join '/')" }
                                    })
                                if ($granted) { "$(Get-Value $policy 'objectId'): $($granted -join ', ')" }
                            })
                        @{ Mode = 'Empty'; Actual = ($broad -join '; ') } }
                }
                @{ Area = 'Security'; Check = 'Key Vault sends audit logs'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'a diagnostic setting must enable AuditEvent or the audit/allLogs category group (PSRule Azure.KeyVault.Logs)'
                    Evaluate = { param($r)
                        try {
                            $settings = @(Get-DiagnosticSetting $r.id)
                        }
                        catch {
                            return @{ Mode = 'Error'; Actual = "could not read diagnostic settings: $($_.Exception.Message)" }
                        }
                        $auditing = @(foreach ($setting in $settings) {
                                $logs = @(Get-Value $setting 'properties.logs' | Where-Object {
                                        (Get-Value $_ 'enabled') -eq $true -and
                                        ((Get-Value $_ 'category') -eq 'AuditEvent' -or (Get-Value $_ 'categoryGroup') -in 'audit', 'allLogs')
                                    })
                                if ($logs.Count -gt 0) {
                                    Get-Value $setting 'name'
                                }
                            })
                        @{ Mode = 'NotEmpty'; Actual = $auditing } }
                }
                @{ Area = 'Security'; Check = 'Key Vault keys rotate automatically'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'every key needs a rotation policy with a rotate action (PSRule Azure.KeyVault.AutoRotationPolicy)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $manual = @(Get-KeyVaultChild $r 'keys' | Where-Object {
                                    @(Get-Value $_ 'properties.rotationPolicy.lifetimeActions' | Where-Object { (Get-Value $_ 'action.type') -eq 'rotate' }).Count -eq 0
                                } | ForEach-Object { $_.name.Split('/')[-1] })
                            @{ Mode = 'Empty'; Actual = $(if ($manual) { "no auto-rotation: $($manual -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'SQL server public network access is disabled'; Types = 'microsoft.sql/servers'
                    Because  = 'databases are reached through private endpoints only'
                    Evaluate = { param($r)
                        $access = Get-Value $r 'props.publicNetworkAccess'
                        @{ Mode = 'Equal'; Actual = $(if ($access) { $access } else { 'Enabled' }); Expected = 'Disabled' } } 
                }
                @{ Area = 'Security'; Check = 'App Service is HTTPS only'; Types = 'microsoft.web/sites'
                    Because  = 'plain HTTP must be redirected to HTTPS'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.httpsOnly') -eq $true; Expected = $true } } 
                }
                @{ Area = 'Security'; Check = 'Managed disk is encrypted with a customer-managed key'; Types = 'microsoft.compute/disks'
                    Because  = 'disks must use customer-managed keys'
                    Evaluate = { param($r)
                        $encryption = Get-Value $r 'props.encryption.type'
                        @{ Mode = 'In'; Actual = $(if ($encryption) { $encryption } else { 'not set' }); Expected = @('EncryptionAtRestWithCustomerKey', 'EncryptionAtRestWithPlatformAndCustomerKeys') } } 
                }
                @{ Area = 'Security'; Check = 'Service Bus local (SAS key) authentication is disabled'; Types = 'microsoft.servicebus/namespaces'
                    Because  = 'publishers and consumers must authenticate with Entra ID identities, not shared access keys (PSRule Azure.ServiceBus.DisableLocalAuth)'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.disableLocalAuth') -eq $true; Expected = $true } } 
                }
                @{ Area = 'Security'; Check = 'Service Bus minimum TLS version is 1.2'; Types = 'microsoft.servicebus/namespaces'
                    Because  = 'clients must send and receive data with TLS 1.2 or later (PSRule Azure.ServiceBus.MinTLS)'
                    Evaluate = { param($r)
                        $tls = Get-Value $r 'props.minimumTlsVersion'
                        @{ Mode = 'In'; Actual = $(if ($tls) { $tls } else { 'not set' }); Expected = @('1.2', '1.3') } } 
                }
                @{ Area = 'Security'; Check = 'Service Bus Premium namespace sends audit logs'; Types = 'microsoft.servicebus/namespaces'
                    Because  = 'a diagnostic setting must enable RuntimeAuditLogs or the audit/allLogs category group (PSRule Azure.ServiceBus.AuditLogs)'
                    Evaluate = { param($r)
                        # Runtime audit logs exist only on the Premium tier.
                        if ((Get-Value $r 'sku.name') -ne 'Premium') {
                            return $null
                        }
                        try {
                            $settings = @(Get-DiagnosticSetting $r.id)
                        }
                        catch {
                            return @{ Mode = 'Error'; Actual = "could not read diagnostic settings: $($_.Exception.Message)" }
                        }
                        $auditing = @(foreach ($setting in $settings) {
                                $logs = @(Get-Value $setting 'properties.logs' | Where-Object {
                                        (Get-Value $_ 'enabled') -eq $true -and
                                        ((Get-Value $_ 'category') -eq 'RuntimeAuditLogs' -or (Get-Value $_ 'categoryGroup') -in 'audit', 'allLogs')
                                    })
                                if ($logs.Count -gt 0) {
                                    Get-Value $setting 'name'
                                }
                            })
                        @{ Mode = 'NotEmpty'; Actual = $auditing } }
                }
                @{ Area = 'Security'; Check = 'Internet-facing Application Gateway uses a WAF SKU'; Types = $appGwType
                    Because  = 'endpoints reachable from the Internet must be protected by a web application firewall (PSRule Azure.AppGw.UseWAF)'
                    Evaluate = { param($r)
                        if (-not (Test-AppGwPublic $r)) {
                            return $null
                        }
                        $tier = Get-Value $r 'props.sku.tier'
                        @{ Mode = 'In'; Actual = $(if ($tier) { $tier } else { 'not set' }); Expected = @('WAF', 'WAF_v2') } }
                }
                @{ Area = 'Security'; Check = 'Internet-facing Application Gateway has its WAF enabled'; Types = $appGwType
                    Because  = 'a WAF policy must be attached or the classic WAF enabled to protect backend resources (PSRule Azure.AppGw.WAFEnabled)'
                    Evaluate = { param($r)
                        if (-not (Test-AppGwPublic $r)) {
                            return $null
                        }
                        $enabled = (Get-Value $r 'props.webApplicationFirewallConfiguration.enabled') -eq $true -or (Get-Value $r 'props.firewallPolicy.id')
                        @{ Mode = 'Empty'; Actual = $(if (-not $enabled) { 'no WAF policy attached and the classic WAF is not enabled' }) } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway only accepts TLS 1.2 or later'; Types = $appGwType
                    Because  = 'the SSL policy must be AppGwSslPolicy20170401S, AppGwSslPolicy20220101(S) or a custom policy with a minimum of TLS 1.2 (PSRule Azure.AppGw.SSLPolicy)'
                    Evaluate = { param($r)
                        $policyName = Get-Value $r 'props.sslPolicy.policyName'
                        $minimum = Get-Value $r 'props.sslPolicy.minProtocolVersion'
                        $ok = $policyName -in 'AppGwSslPolicy20170401S', 'AppGwSslPolicy20220101', 'AppGwSslPolicy20220101S' -or $minimum -in 'TLSv1_2', 'TLSv1_3'
                        $found = if ($policyName) { "policy $policyName" } elseif ($minimum) { "minimum $minimum" } else { 'no SSL policy set' }
                        @{ Mode = 'Empty'; Actual = $(if (-not $ok) { $found }) } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway HTTP listeners redirect to HTTPS'; Types = $appGwType
                    Because  = 'frontend endpoints must only be exposed over HTTPS (PSRule Azure.AppGw.UseHTTPS)'
                    Evaluate = { param($r)
                        $httpListeners = @(Get-Value $r 'props.httpListeners' | Where-Object { (Get-Value $_ 'properties.protocol') -eq 'http' } | ForEach-Object { Get-Value $_ 'name' })
                        $unredirected = @(foreach ($routing in @(Get-Value $r 'props.requestRoutingRules')) {
                                $listenerId = [string](Get-Value $routing 'properties.httpListener.id')
                                if ($listenerId -and $listenerId.Split('/')[-1] -in $httpListeners -and -not (Get-Value $routing 'properties.redirectConfiguration.id')) {
                                    Get-Value $routing 'name'
                                }
                            })
                        @{ Mode = 'Empty'; Actual = $(if ($unredirected) { "HTTP served without a redirect by rule(s) $($unredirected -join ', ')" }) } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway classic WAF is in prevention mode'; Types = $appGwType
                    Because  = 'detection mode only logs attacks; prevention mode blocks them (PSRule Azure.AppGw.Prevention)'
                    Evaluate = { param($r)
                        if (-not (Test-AppGwClassicWaf $r)) {
                            return $null
                        }
                        $mode = Get-Value $r 'props.webApplicationFirewallConfiguration.firewallMode'
                        @{ Mode = 'Equal'; Actual = $(if ($mode) { $mode } else { 'not set' }); Expected = 'Prevention' } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway classic WAF uses OWASP 3.x rules'; Types = $appGwType
                    Because  = 'the WAF must use the OWASP 3.x core rule set (PSRule Azure.AppGw.OWASP)'
                    Evaluate = { param($r)
                        if (-not (Test-AppGwClassicWaf $r)) {
                            return $null
                        }
                        $type = Get-Value $r 'props.webApplicationFirewallConfiguration.ruleSetType'
                        $version = Get-Value $r 'props.webApplicationFirewallConfiguration.ruleSetVersion'
                        $ok = $type -eq 'OWASP' -and (Test-Version $version -Minimum '3.0' -Below '4.0')
                        @{ Mode = 'Empty'; Actual = $(if (-not $ok) { "uses $(if ($type) { "$type $version" } else { 'no rule set' })" }) } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway classic WAF has all rules enabled'; Types = $appGwType
                    Because  = 'disabled rule groups leave attacks undetected (PSRule Azure.AppGw.WAFRules)'
                    Evaluate = { param($r)
                        if (-not (Test-AppGwClassicWaf $r)) {
                            return $null
                        }
                        $disabled = @(Get-Value $r 'props.webApplicationFirewallConfiguration.disabledRuleGroups' | ForEach-Object { Get-Value $_ 'ruleGroupName' })
                        @{ Mode = 'Empty'; Actual = $(if ($disabled) { "disabled rule group(s) $($disabled -join ', ')" }) } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway WAF policy is enabled'; Types = $wafPolicyType
                    Because  = 'a disabled WAF policy protects nothing (PSRule Azure.AppGwWAF.Enabled)'
                    Evaluate = { param($r)
                        $state = Get-Value $r 'props.policySettings.state'
                        @{ Mode = 'Equal'; Actual = $(if ($state) { $state } else { 'not set' }); Expected = 'Enabled' } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway WAF policy is in prevention mode'; Types = $wafPolicyType
                    Because  = 'detection mode only logs attacks; prevention mode blocks them (PSRule Azure.AppGwWAF.PreventionMode)'
                    Evaluate = { param($r)
                        $mode = Get-Value $r 'props.policySettings.mode'
                        @{ Mode = 'Equal'; Actual = $(if ($mode) { $mode } else { 'not set' }); Expected = 'Prevention' } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway WAF policy has no exclusions'; Types = $wafPolicyType
                    Because  = 'every exclusion is traffic the managed rules no longer inspect (PSRule Azure.AppGwWAF.Exclusions)'
                    Evaluate = { param($r)
                        $exclusions = @(Get-Value $r 'props.managedRules.exclusions').Count
                        @{ Mode = 'Empty'; Actual = $(if ($exclusions) { "$exclusions exclusion(s)" }) } }
                }
                @{ Area = 'Security'; Check = 'Application Gateway WAF policy uses the default and bot manager rule sets'; Types = $wafPolicyType
                    Because  = 'the policy needs Microsoft_DefaultRuleSet 2.1+ and Microsoft_BotManagerRuleSet 1.0+ (PSRule Azure.AppGwWAF.RuleGroups)'
                    Evaluate = { param($r)
                        $ruleSets = @(Get-Value $r 'props.managedRules.managedRuleSets')
                        $missing = @(
                            if (-not ($ruleSets | Where-Object { (Get-Value $_ 'ruleSetType') -eq 'Microsoft_DefaultRuleSet' -and (Test-Version (Get-Value $_ 'ruleSetVersion') -Minimum '2.1') })) { 'Microsoft_DefaultRuleSet 2.1+' }
                            if (-not ($ruleSets | Where-Object { (Get-Value $_ 'ruleSetType') -eq 'Microsoft_BotManagerRuleSet' -and (Test-Version (Get-Value $_ 'ruleSetVersion') -Minimum '1.0') })) { 'Microsoft_BotManagerRuleSet 1.0+' }
                        )
                        $found = @($ruleSets | ForEach-Object { "$(Get-Value $_ 'ruleSetType') $(Get-Value $_ 'ruleSetVersion')" })
                        @{ Mode = 'Empty'; Actual = $(if ($missing) { "missing $($missing -join ' and ') (has $(if ($found) { $found -join ', ' } else { 'none' }))" }) } }
                }

                @{ Area = 'Security'; Check = 'API Management uses a managed identity'; Types = $apimType
                    Because  = 'the gateway must reach Key Vault and backends with an Entra ID identity, not stored credentials (PSRule Azure.APIM.ManagedIdentity)'
                    Evaluate = { param($r)
                        $identity = Get-Value $r 'identity.type'
                        @{ Mode = 'In'; Actual = $(if ($identity) { $identity } else { 'None' }); Expected = @('SystemAssigned', 'UserAssigned', 'SystemAssigned,UserAssigned', 'SystemAssigned, UserAssigned') } }
                }
                @{ Area = 'Security'; Check = 'API Management has SSL 3.0, TLS 1.0 and TLS 1.1 disabled'; Types = $apimType
                    Because  = 'clients and backends must use TLS 1.2 or later (PSRule Azure.APIM.Protocols)'
                    Evaluate = { param($r)
                        $enabled = @($apimProtocols.Keys | Where-Object { Test-ApimFlagOn $r $_ } | ForEach-Object { $apimProtocols[$_] })
                        @{ Mode = 'Empty'; Actual = $(if ($enabled) { "enabled: $($enabled -join ', ')" }) } }
                }
                @{ Area = 'Security'; Check = 'API Management has weak ciphers disabled'; Types = $apimType
                    Because  = 'Triple DES and the CBC / non-ECDHE RSA suites must be turned off (PSRule Azure.APIM.Ciphers)'
                    Evaluate = { param($r)
                        $properties = Get-Value $r 'props.customProperties'
                        $enabled = @(
                            if (Test-ApimFlagOn $r "$($apimCipherPrefix)TripleDes168") { 'TripleDes168' }
                            foreach ($cipher in $apimWeakCiphers) {
                                $value = if ($properties -is [System.Collections.IDictionary] -and $properties.Contains("$apimCipherPrefix$cipher")) { $properties["$apimCipherPrefix$cipher"] }
                                if ([string]$value -ne 'false') { $cipher }
                            }
                        )
                        @{ Mode = 'Empty'; Actual = $(if ($enabled) { "still enabled: $($enabled -join ', ')" }) } }
                }
                @{ Area = 'Security'; Check = 'API Management APIs accept HTTPS only'; Types = $apimType
                    Because  = 'no API may be published over plain HTTP (PSRule Azure.APIM.HTTPEndpoint)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $http = @(Get-ApimApi $r | Where-Object { 'http' -in @(Get-Value $_ 'properties.protocols') } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($http) { "HTTP allowed on: $($http -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management backends use HTTPS'; Types = $apimType
                    Because  = 'traffic from the gateway to backends must be encrypted (PSRule Azure.APIM.HTTPBackend)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $plain = @(
                                Get-ApimChild $r 'backends' | Where-Object { ([string](Get-Value $_ 'properties.url')).StartsWith('http://', 'OrdinalIgnoreCase') } | ForEach-Object { "backend $($_.name)" }
                                Get-ApimApi $r | Where-Object { ([string](Get-Value $_ 'properties.serviceUrl')).StartsWith('http://', 'OrdinalIgnoreCase') } | ForEach-Object { "API $($_.name)" }
                            )
                            @{ Mode = 'Empty'; Actual = $(if ($plain) { "http:// URL on: $($plain -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management named values are stored in Key Vault'; Types = $apimType
                    Because  = 'secrets must be referenced from Key Vault, not kept in API Management (PSRule Azure.APIM.EncryptValues)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $local = @(Get-ApimChild $r 'namedValues' | Where-Object { -not (Get-Value $_ 'properties.keyVault.secretIdentifier') } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($local) { "not in Key Vault: $($local -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management products require a subscription'; Types = $apimType
                    Because  = 'APIs must not be callable anonymously (PSRule Azure.APIM.ProductSubscription)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $open = @(Get-ApimChild $r 'products' | Where-Object { (Get-Value $_ 'properties.subscriptionRequired') -ne $true } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($open) { "no subscription needed: $($open -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management products require approval'; Types = $apimType
                    Because  = 'an administrator must approve each new subscription (PSRule Azure.APIM.ProductApproval)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $open = @(Get-ApimChild $r 'products' | Where-Object { (Get-Value $_ 'properties.approvalRequired') -ne $true } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($open) { "no approval needed: $($open -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management has no sample products'; Types = $apimType
                    Because  = 'the Starter and Unlimited sample products must be removed (PSRule Azure.APIM.SampleProducts)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $samples = @(Get-ApimChild $r 'products' | Where-Object { $_.name -in 'starter', 'unlimited' } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($samples) { "sample products: $($samples -join ', ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management CORS policies have no wildcards'; Types = $apimType
                    Because  = 'CORS must name the allowed origins, methods and headers instead of * (PSRule Azure.APIM.CORSPolicy)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $documents = @(Get-ApimPolicy $r)
                            $cors = @(foreach ($document in @($documents | Where-Object Xml)) {
                                    foreach ($node in @($document.Xml.SelectNodes('//cors'))) { @{ Where = $document.Where; Node = $node } }
                                })
                            # Only services with a CORS policy get this test.
                            if ($cors.Count -eq 0) {
                                return $null
                            }
                            $wildcards = @(foreach ($entry in $cors) {
                                    $open = @($entry.Node.SelectNodes('.//origin | .//method | .//header') | Where-Object { $_.InnerText.Trim() -eq '*' } | ForEach-Object { $_.Name } | Select-Object -Unique)
                                    if ($open) { "$($entry.Where) ($($open -join ', '))" }
                                })
                            @{ Mode = 'Empty'; Actual = $(if ($wildcards) { "* allowed in: $($wildcards -join '; ')" }) }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management API and product policies include <base />'; Types = $apimType
                    Because  = 'every section of a scoped policy must run the parent policy first, or global controls are skipped (PSRule Azure.APIM.PolicyBase)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $scoped = @(Get-ApimPolicy $r | Where-Object { -not $_.Global })
                            # Only services with API or product policies get this test.
                            if ($scoped.Count -eq 0) {
                                return $null
                            }
                            $problems = @(foreach ($document in $scoped) {
                                    if (-not $document.Xml) {
                                        "$($document.Where): not valid XML"
                                        continue
                                    }
                                    foreach ($section in 'inbound', 'backend', 'outbound', 'on-error') {
                                        $node = $document.Xml.SelectSingleNode("/policies/$section")
                                        if (-not $node) { "$($document.Where): no $section section" }
                                        elseif (-not $node.SelectSingleNode('base')) { "$($document.Where): $section has no <base />" }
                                    }
                                })
                            @{ Mode = 'Empty'; Actual = ($problems -join '; ') }
                        } }
                }
                @{ Area = 'Security'; Check = 'API Management APIs are protected by Defender for APIs'; Types = $apimType
                    Because  = 'every REST API must be onboarded to Microsoft Defender for APIs (PSRule Azure.APIM.DefenderCloud)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $rest = @(Get-ApimApi $r | Where-Object { (Get-Value $_ 'properties.apiType') -in $null, '', 'http' })
                            # Only services with REST APIs get this test.
                            if ($rest.Count -eq 0) {
                                return $null
                            }
                            $onboarded = @(Get-ApimChild $r 'providers/Microsoft.Security/apiCollections' -ApiVersion '2023-11-15' | ForEach-Object { $_.name })
                            $missing = @($rest | Where-Object { $_.name -notin $onboarded } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($missing) { "not onboarded: $($missing -join ', ')" }) }
                        } }
                }

                @{ Area = 'Security'; Check = 'Application Insights local authentication is disabled'; Types = $appInsightsType
                    Because  = 'telemetry must be sent with Entra ID authentication, not the instrumentation key alone (PSRule Azure.AppInsights.LocalAuth)'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.disableLocalAuth') -eq $true; Expected = $true } }
                }

                @{ Area = 'Security'; Check = 'Logic App HTTP triggers are limited to allowed caller IPs'; Types = 'microsoft.logic/workflows'
                    Because  = 'a request trigger reachable from any address can be called by anyone holding its URL - list the allowed caller IP ranges (PSRule Azure.LogicApp.LimitHTTPTrigger)'
                    Evaluate = { param($r)
                        # Only workflows with an HTTP request trigger get this test.
                        $triggers = Get-Value $r 'props.definition.triggers'
                        $http = @(if ($triggers -is [System.Collections.IDictionary]) {
                                $triggers.GetEnumerator() | Where-Object { (Get-Value $_.Value 'type') -eq 'Request' -and (Get-Value $_.Value 'kind') -eq 'Http' } | ForEach-Object { $_.Key }
                            })
                        if ($http.Count -eq 0) {
                            return $null
                        }
                        $allowed = @(Get-Value $r 'props.accessControl.triggers.allowedCallerIpAddresses')
                        @{ Mode = 'Empty'; Actual = $(if ($allowed.Count -eq 0) { "trigger $($http -join ', ') accepts calls from any IP address" }) } }
                }

                @{ Area = 'Networking'; Check = 'NSG does not allow RDP/SSH from the Internet'; Types = 'microsoft.network/networksecuritygroups'
                    Because  = 'management ports must only be reachable through Bastion'
                    Evaluate = { param($r)
                        $open = foreach ($rule in @(Get-Value $r 'props.securityRules')) {
                            $p = $rule.properties
                            $sources = @((Get-Value $p 'sourceAddressPrefix'), @(Get-Value $p 'sourceAddressPrefixes')) | ForEach-Object { $_ } | Where-Object { $_ }
                            $ports = @((Get-Value $p 'destinationPortRange'), @(Get-Value $p 'destinationPortRanges')) | ForEach-Object { $_ } | Where-Object { $_ }
                            if ($p.direction -eq 'Inbound' -and $p.access -eq 'Allow' -and
                                @($sources | Where-Object { $_.ToLowerInvariant() -in $internet }).Count -gt 0 -and
                                (Test-PortRange -Range $ports -Port 22, 3389)) {
                                "$($rule.name) ($($ports -join ',') from $($sources -join ','))"
                            }
                        }
                        @{ Mode = 'Empty'; Actual = (@($open) -join '; ') } } 
                }
                @{ Area = 'Networking'; Check = 'Public IP is attached to a resource'; Types = 'microsoft.network/publicipaddresses'
                    Because  = 'unattached public IPs cost money and should be removed'
                    Evaluate = { param($r)
                        $attached = (Get-Value $r 'props.ipConfiguration') -or (Get-Value $r 'props.natGateway')
                        @{ Mode = 'Equal'; Actual = $(if ($attached) { 'Attached' } else { 'Not attached' }); Expected = 'Attached' } } 
                }
                @{ Area = 'Networking'; Check = $(if ($DnsServer) { "VNet uses the DNS servers $($DnsServer -join ', ')" } else { 'VNet uses custom (hub) DNS servers' })
                    Types    = 'microsoft.network/virtualnetworks'
                    Because  = 'private endpoint names only resolve through the hub DNS'
                    Evaluate = { param($r)
                        $servers = @(Get-Value $r 'props.dhcpOptions.dnsServers' | Where-Object { $_ })
                        $actual = if ($servers) { ($servers | Sort-Object) -join ', ' } else { 'Azure-provided' }
                        if ($DnsServer) {
                            @{ Mode = 'Equal'; Actual = $actual; Expected = (($DnsServer | Sort-Object) -join ', ') }
                        }
                        else {
                            @{ Mode = 'NotEqual'; Actual = $actual; Expected = 'Azure-provided' }
                        } } 
                }

                @{ Area = 'Operations'; Check = 'VM is protected by Azure Backup'; Types = 'microsoft.compute/virtualmachines'
                    Because  = 'VMs need daily backups'
                    Evaluate = { param($r)
                        $environment = Get-TagValue $r.tags 'Environment'
                        if ($environment -and $environment -in $BackupExemptEnvironment) {
                            return @{ Skip = $true; SkipReason = "$environment environment - backup not required" }
                        }
                        $state = $backupState[$r.id.ToLowerInvariant()]
                        @{ Mode = 'In'; Actual = $(if ($state) { $state } else { 'Not protected' }); Expected = @('ProtectionConfigured', 'Protected') } } 
                }
                @{ Area = 'Operations'; Check = 'Diagnostic logs go to Log Analytics'; Types = @($DiagnosticResourceType | ForEach-Object { $_.ToLowerInvariant() })
                    Because  = $(if ($LogAnalyticsWorkspaceId) { "security monitoring needs every resource's logs in $($LogAnalyticsWorkspaceId.Split('/')[-1])" } else { "security monitoring needs every resource's logs" })
                    Evaluate = { param($r)
                        # Every SQL server has a master database; it isn't monitored like the rest.
                        if ($r.type -eq 'microsoft.sql/servers/databases' -and $r.name -eq 'master') {
                            return $null
                        }
                        try {
                            $settings = @(Get-DiagnosticSetting $r.id)
                        }
                        catch {
                            return @{ Mode = 'Error'; Actual = "could not read diagnostic settings: $($_.Exception.Message)" }
                        }
                        $workspaces = @($settings | ForEach-Object { Get-Value $_ 'properties.workspaceId' } | ForEach-Object { $_.ToLowerInvariant() })
                        if ($LogAnalyticsWorkspaceId) {
                            @{ Mode = 'Contain'; Actual = $workspaces; Expected = $LogAnalyticsWorkspaceId.ToLowerInvariant() }
                        }
                        else {
                            @{ Mode = 'NotEmpty'; Actual = $workspaces }
                        } } 
                }
                @{ Area = 'Operations'; Check = 'Service Bus namespace is geo-replicated'; Types = 'microsoft.servicebus/namespaces'
                    Because  = 'namespaces must survive a regional outage - geo-replication needs the Premium tier and at least 2 locations (PSRule Azure.ServiceBus.GeoReplica)'
                    Evaluate = { param($r)
                        $sku = Get-Value $r 'sku.name'
                        $locations = @(Get-Value $r 'props.geoDataReplication.locations').Count
                        $problem = if ($sku -ne 'Premium') { "$sku tier - geo-replication needs Premium" }
                        elseif ($locations -lt 2) { "$locations geo-replication location(s)" }
                        @{ Mode = 'Empty'; Actual = [string]$problem } } 
                }
                @{ Area = 'Operations'; Check = 'Service Bus namespace is in use'; Types = 'microsoft.servicebus/namespaces'
                    Because  = 'namespaces without queues or topics cost money and should be removed (PSRule Azure.ServiceBus.Usage)'
                    Evaluate = { param($r)
                        try {
                            $inUse = Test-ServiceBusInUse $r
                        }
                        catch {
                            return @{ Mode = 'Error'; Actual = "could not list queues and topics: $($_.Exception.Message)" }
                        }
                        @{ Mode = 'Equal'; Actual = $(if ($inUse) { 'Has queues or topics' } else { 'No queues or topics' }); Expected = 'Has queues or topics' } }
                }
                @{ Area = 'Operations'; Check = 'Application Gateway runs at least two instances'; Types = $appGwType
                    Because  = 'a single instance is a single point of failure - use a capacity of 2+ or autoscaling (PSRule Azure.AppGw.MinInstance)'
                    Evaluate = { param($r)
                        $capacity = Get-Value $r 'props.sku.capacity'
                        $autoscaleMin = Get-Value $r 'props.autoscaleConfiguration.minCapacity'
                        $ok = ($null -ne $capacity -and [int]$capacity -ge 2) -or ($null -ne $autoscaleMin -and [int]$autoscaleMin -ge 0)
                        @{ Mode = 'Empty'; Actual = $(if (-not $ok) { "capacity $(if ($null -ne $capacity) { $capacity } else { 'not set' }), no autoscaling" }) } }
                }
                @{ Area = 'Operations'; Check = 'Application Gateway SKU is Medium or larger'; Types = $appGwType
                    Because  = 'Small instances are for development and testing only (PSRule Azure.AppGw.MinSku)'
                    Evaluate = { param($r)
                        $sku = Get-Value $r 'props.sku.name'
                        @{ Mode = 'In'; Actual = $(if ($sku) { $sku } else { 'not set' }); Expected = @('WAF_Medium', 'Standard_Medium', 'WAF_Large', 'Standard_Large', 'WAF_v2', 'Standard_v2') } }
                }
                @{ Area = 'Operations'; Check = 'Application Gateway uses a v2 SKU'; Types = $appGwType
                    Because  = 'v1 gateways are retired - migrate to Standard_v2 or WAF_v2 (PSRule Azure.AppGw.MigrateV2)'
                    Evaluate = { param($r)
                        $sku = Get-Value $r 'props.sku.name'
                        $tier = Get-Value $r 'props.sku.tier'
                        $ok = $sku -in 'Standard_v2', 'WAF_v2' -or $tier -in 'Standard_v2', 'WAF_v2'
                        @{ Mode = 'Empty'; Actual = $(if (-not $ok) { "$sku ($tier tier) is a v1 SKU" }) } }
                }
                @{ Area = 'Operations'; Check = 'Application Gateway WAF_v2 uses a WAF policy'; Types = $appGwType
                    Because  = 'the classic WAF configuration is retired - migrate it to a WAF policy (PSRule Azure.AppGw.MigrateWAFPolicy)'
                    Evaluate = { param($r)
                        if ((Get-Value $r 'props.sku.tier') -ne 'WAF_v2') {
                            return $null
                        }
                        $classic = $null -ne (Get-Value $r 'props.webApplicationFirewallConfiguration')
                        @{ Mode = 'Empty'; Actual = $(if ($classic) { 'still uses the classic WAF configuration' }) } }
                }
                @{ Area = 'Operations'; Check = 'Application Gateway v2 uses availability zones'; Types = $appGwType
                    Because  = 'in regions with availability zones, a gateway must span at least two to survive a zone outage (PSRule Azure.AppGw.AvailabilityZone)'
                    Evaluate = { param($r)
                        if ((Get-Value $r 'props.sku.tier') -notin 'Standard_v2', 'WAF_v2') {
                            return $null
                        }
                        try {
                            $offered = @(Get-ProviderZone -Subscription $r.subscriptionId -Namespace 'Microsoft.Network' -ResourceType 'applicationGateways' -Location $r.location)
                        }
                        catch {
                            return @{ Mode = 'Error'; Actual = "could not read the regions' availability zones: $($_.Exception.Message)" }
                        }
                        # A region without zones passes - there is nothing to spread across.
                        $zones = @(Get-Value $r 'zones')
                        $problem = if ($offered.Count -gt 0 -and $zones.Count -lt 2) {
                            "zones $(if ($zones) { $zones -join ', ' } else { 'none' }) - $($r.location) offers $($offered -join ', ')"
                        }
                        @{ Mode = 'Empty'; Actual = [string]$problem } }
                }
                @{ Area = 'Operations'; Check = 'Application Insights is workspace-based'; Types = $appInsightsType
                    Because  = 'classic Application Insights is retired - telemetry must go to a Log Analytics workspace (PSRule Azure.AppInsights.Workspace)'
                    Evaluate = { param($r)
                        $workspace = Get-Value $r 'props.WorkspaceResourceId'
                        @{ Mode = 'NotEmpty'; Actual = $(if ($workspace) { $workspace.Split('/')[-1] }) } }
                }
                @{ Area = 'Operations'; Check = 'Storage is geo or zone replicated'; Types = $storageType
                    Because  = 'data must survive a zone or regional outage - use ZRS, GRS, RA-GRS, GZRS or RA-GZRS (PSRule Azure.Storage.UseReplication)'
                    Evaluate = { param($r)
                        # Standard accounts only, not ones Azure services manage, nor large file shares.
                        $sku = [string](Get-Value $r 'sku.name')
                        if ($sku -notlike 'Standard_*' -or (Test-CloudShellStorage $r) -or
                            (Test-StorageUsage $r 'resource-usage' 'azure-functions') -or (Test-StorageUsage $r 'resource-usage' 'azure-monitor') -or
                            (Get-Value $r 'props.largeFileSharesState') -eq 'Enabled') {
                            return $null
                        }
                        @{ Mode = 'In'; Actual = $sku; Expected = @('Standard_GRS', 'Standard_RAGRS', 'Standard_GZRS', 'Standard_RAGZRS', 'Standard_ZRS', 'Premium_ZRS') } }
                }
                @{ Area = 'Operations'; Check = 'Storage blob soft delete is enabled'; Types = $storageType
                    Because  = 'deleted blobs must be recoverable (PSRule Azure.Storage.SoftDelete)'
                    Evaluate = { param($r)
                        if ((Test-CloudShellStorage $r) -or (Test-HnsStorage $r) -or (Test-StorageKind $r 'FileStorage')) {
                            return $null
                        }
                        Invoke-ChildRule {
                            $services = @(Get-StorageChild $r 'blobServices')
                            $problem = if ($services.Count -eq 0) { 'no blob service found' }
                            elseif (@($services | Where-Object { (Get-Value $_ 'properties.deleteRetentionPolicy.enabled') -ne $true }).Count -gt 0) { 'blob soft delete is off' }
                            @{ Mode = 'Empty'; Actual = [string]$problem }
                        } }
                }
                @{ Area = 'Operations'; Check = 'Storage container soft delete is enabled'; Types = $storageType
                    Because  = 'deleted containers must be recoverable for at least a day (PSRule Azure.Storage.ContainerSoftDelete)'
                    Evaluate = { param($r)
                        if ((Test-CloudShellStorage $r) -or (Test-HnsStorage $r) -or (Test-StorageKind $r 'FileStorage')) {
                            return $null
                        }
                        Invoke-ChildRule {
                            $services = @(Get-StorageChild $r 'blobServices')
                            $problem = if ($services.Count -eq 0) { 'no blob service found' }
                            elseif (@($services | Where-Object {
                                        (Get-Value $_ 'properties.containerDeleteRetentionPolicy.enabled') -ne $true -or
                                        [int](Get-Value $_ 'properties.containerDeleteRetentionPolicy.days') -lt 1
                                    }).Count -gt 0) { 'container soft delete is off' }
                            @{ Mode = 'Empty'; Actual = [string]$problem }
                        } }
                }
                @{ Area = 'Operations'; Check = 'Storage file share soft delete keeps 7+ days'; Types = $storageType
                    Because  = 'deleted file shares must be recoverable for at least 7 days (PSRule Azure.Storage.FileShareSoftDelete)'
                    Evaluate = { param($r)
                        # FileStorage accounts only.
                        if (-not (Test-StorageKind $r 'FileStorage') -or (Test-CloudShellStorage $r) -or (Test-HnsStorage $r)) {
                            return $null
                        }
                        Invoke-ChildRule {
                            $services = @(Get-StorageChild $r 'fileServices')
                            $problem = if ($services.Count -eq 0) { 'no file service found' }
                            else {
                                $short = @($services | Where-Object {
                                        (Get-Value $_ 'properties.shareDeleteRetentionPolicy.enabled') -ne $true -or
                                        [int](Get-Value $_ 'properties.shareDeleteRetentionPolicy.days') -lt 7
                                    })
                                if ($short) {
                                    $days = Get-Value $short[0] 'properties.shareDeleteRetentionPolicy.days'
                                    if ((Get-Value $short[0] 'properties.shareDeleteRetentionPolicy.enabled') -ne $true) { 'file share soft delete is off' } else { "file share soft delete keeps $days day(s)" }
                                }
                            }
                            @{ Mode = 'Empty'; Actual = [string]$problem }
                        } }
                }
                @{ Area = 'Operations'; Check = 'Key Vault has soft delete enabled'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'deleted vaults and their contents must be recoverable (PSRule Azure.KeyVault.SoftDelete)'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.enableSoftDelete') -eq $true; Expected = $true } }
                }
                @{ Area = 'Operations'; Check = 'Managed Grafana runs version 11 or later'; Types = $grafanaType
                    Because  = 'Grafana 10 is out of support - upgrade the workspace to Grafana 11 or later (PSRule Azure.Grafana.Version)'
                    Evaluate = { param($r)
                        $version = [string](Get-Value $r 'props.grafanaMajorVersion')
                        $major = 0
                        $problem = if (-not $version) { 'grafanaMajorVersion is not set' }
                        elseif (-not [int]::TryParse($version, [ref]$major) -or $major -lt 11) { "Grafana $version" }
                        @{ Mode = 'Empty'; Actual = [string]$problem } }
                }
                @{ Area = 'Operations'; Check = 'Managed Grafana is zone redundant'; Types = $grafanaType
                    Because  = 'in regions with availability zones, the workspace must survive a zone outage (PSRule Azure.Grafana.AvailabilityZone)'
                    Evaluate = { param($r)
                        # PSRule decides whether a region has zones from the
                        # virtual machine scale set zone mappings.
                        try {
                            $offered = @(Get-ProviderZone -Subscription $r.subscriptionId -Namespace 'Microsoft.Compute' -ResourceType 'virtualMachineScaleSets' -Location $r.location)
                        }
                        catch {
                            return @{ Mode = 'Error'; Actual = "could not read the regions' availability zones: $($_.Exception.Message)" }
                        }
                        # A region without zones passes - there is nothing to spread across.
                        $redundancy = Get-Value $r 'props.zoneRedundancy'
                        $problem = if ($offered.Count -gt 0 -and $redundancy -ne 'Enabled') {
                            "zone redundancy $(if ($redundancy) { $redundancy } else { 'not set' }) - $($r.location) offers zones $($offered -join ', ')"
                        }
                        @{ Mode = 'Empty'; Actual = [string]$problem } }
                }
                @{ Area = 'Operations'; Check = 'API Management certificates are not about to expire'; Types = $apimType
                    Because  = 'custom domain certificates must have at least 30 days left (PSRule Azure.APIM.CertificateExpiry)'
                    Evaluate = { param($r)
                        $certificates = @(Get-Value $r 'props.hostnameConfigurations' | Where-Object { Get-Value $_ 'certificate.expiry' })
                        # Only services with custom domain certificates get this test.
                        if ($certificates.Count -eq 0) {
                            return $null
                        }
                        $expiring = @(foreach ($configuration in $certificates) {
                                $expiry = [datetime](Get-Value $configuration 'certificate.expiry')
                                $days = [int][Math]::Floor(($expiry - (Get-Date)).TotalDays)
                                if ($days -lt 30) { "$(Get-Value $configuration 'hostName') expires $($expiry.ToString('yyyy-MM-dd')) ($days days)" }
                            })
                        @{ Mode = 'Empty'; Actual = ($expiring -join '; ') } }
                }
                @{ Area = 'Operations'; Check = 'API Management uses availability zones'; Types = $apimType
                    Because  = 'in regions with zones, each location needs 2+ zones and at least one unit per zone - zones need the Premium tier (PSRule Azure.APIM.AvailabilityZone)'
                    Evaluate = { param($r)
                        $sku = Get-Value $r 'sku.name'
                        if ($sku -ne 'Premium') {
                            return @{ Mode = 'Empty'; Actual = "$sku tier - availability zones need Premium" }
                        }
                        try {
                            $problems = @(
                                Get-ApimZoneProblem -Subscription $r.subscriptionId -Location $r.location -Zones $r.zones -Capacity (Get-Value $r 'sku.capacity')
                                foreach ($location in @(Get-Value $r 'props.additionalLocations')) {
                                    Get-ApimZoneProblem -Subscription $r.subscriptionId -Location (Get-Value $location 'location') -Zones (Get-Value $location 'zones') -Capacity (Get-Value $location 'sku.capacity')
                                }
                            )
                        }
                        catch {
                            return @{ Mode = 'Error'; Actual = "could not read the regions' availability zones: $($_.Exception.Message)" }
                        }
                        @{ Mode = 'Empty'; Actual = ($problems -join '; ') } }
                }
                @{ Area = 'Operations'; Check = 'API Management is deployed to more than one region'; Types = $apimType
                    Because  = 'a second region keeps the gateway up through a regional outage - it needs the Premium tier (PSRule Azure.APIM.MultiRegion)'
                    Evaluate = { param($r)
                        $sku = Get-Value $r 'sku.name'
                        $additional = @(Get-Value $r 'props.additionalLocations').Count
                        $problem = if ($sku -ne 'Premium') { "$sku tier - multi-region needs Premium" }
                        elseif ($additional -lt 1) { 'no additional locations' }
                        @{ Mode = 'Empty'; Actual = [string]$problem } }
                }
                @{ Area = 'Operations'; Check = 'API Management gateways are enabled in every region'; Types = $apimType
                    Because  = 'a disabled regional gateway serves no traffic in a failover (PSRule Azure.APIM.MultiRegionGateway)'
                    Evaluate = { param($r)
                        $locations = @(Get-Value $r 'props.additionalLocations')
                        # Only multi-region Premium services get this test.
                        if ((Get-Value $r 'sku.name') -ne 'Premium' -or $locations.Count -eq 0) {
                            return $null
                        }
                        $disabled = @($locations | Where-Object { (Get-Value $_ 'disableGateway') -eq $true } | ForEach-Object { Get-Value $_ 'location' })
                        @{ Mode = 'Empty'; Actual = $(if ($disabled) { "gateway disabled in: $($disabled -join ', ')" }) } }
                }
                @{ Area = 'Operations'; Check = 'API Management blocks management API versions before 2021-08-01'; Types = $apimType
                    Because  = 'older control-plane API versions are retired - set apiVersionConstraint.minApiVersion to 2021-08-01 or later (PSRule Azure.APIM.MinAPIVersion)'
                    Evaluate = { param($r)
                        $minimum = [string](Get-Value $r 'props.apiVersionConstraint.minApiVersion')
                        $problem = if (-not $minimum) { 'minApiVersion is not set' }
                        else {
                            $parsed = [datetime]::MinValue
                            if (-not [datetime]::TryParse(($minimum -replace '-preview', ''), [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed) -or $parsed -lt [datetime]'2021-08-01') {
                                "minApiVersion is $minimum"
                            }
                        }
                        @{ Mode = 'Empty'; Actual = [string]$problem } }
                }
                @{ Area = 'Operations'; Check = 'API Management APIs have a display name and description'; Types = $apimType
                    Because  = 'consumers find and understand APIs by these (PSRule Azure.APIM.APIDescriptors)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $undescribed = @(Get-ApimApi $r | Where-Object { -not (Get-Value $_ 'properties.displayName') -or -not (Get-Value $_ 'properties.description') } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($undescribed) { "missing a display name or description: $($undescribed -join ', ')" }) }
                        } }
                }
                @{ Area = 'Operations'; Check = 'API Management products have a display name and description'; Types = $apimType
                    Because  = 'consumers choose products by these (PSRule Azure.APIM.ProductDescriptors)'
                    Evaluate = { param($r)
                        Invoke-ChildRule {
                            $undescribed = @(Get-ApimChild $r 'products' | Where-Object { -not (Get-Value $_ 'properties.displayName') -or -not (Get-Value $_ 'properties.description') } | ForEach-Object { $_.name })
                            @{ Mode = 'Empty'; Actual = $(if ($undescribed) { "missing a display name or description: $($undescribed -join ', ')" }) }
                        } }
                }
            )

            # --- One test case per rule and resource -------------------------------
            if ($resources.Count -eq 0) {
                $noResourcesCase = @(@{})
            }
            else {
                # One progress step per rule and resource it applies to - the
                # REST calls some rules make are where the time goes. Steps are
                # reported in batches, so thousands of resources stay cheap.
                $applies = { param($Rule, $Resource) $Rule.Types -eq '*' -or $Resource.type -in $Rule.Types }
                $totalSteps = 0
                $activeRules = 0
                foreach ($rule in $rules) {
                    $count = @($resources | Where-Object { & $applies $rule $_ }).Count
                    $totalSteps += $count
                    if ($count -gt 0) { $activeRules++ }
                }
                Write-CheckProgress -Id 'estate-rules' -Total $totalSteps -Description ('Evaluating {0:N0} rules on {1:N0} resources' -f $activeRules, $resources.Count)
                $pendingSteps = 0
                $caseCount = 0

                $areas = @(foreach ($area in @($rules | ForEach-Object { $_.Area } | Select-Object -Unique)) {
                        $checks = @(foreach ($rule in @($rules | Where-Object { $_.Area -eq $area })) {
                                $ruleResources = @($resources | Where-Object { & $applies $rule $_ })
                                # Only rules with something to check show their name.
                                if ($ruleResources.Count -gt 0) {
                                    Write-CheckProgress -Id 'estate-rules' -Increment $pendingSteps -Description "$($rule.Area): $($rule.Check)"
                                    $pendingSteps = 0
                                }
                                $cases = @(foreach ($resource in $ruleResources) {
                                        $pendingSteps++
                                        if ($pendingSteps -ge 25) {
                                            Write-CheckProgress -Id 'estate-rules' -Increment $pendingSteps
                                            $pendingSteps = 0
                                        }
                                        $result = & $rule.Evaluate $resource
                                        if (-not $result) {
                                            continue
                                        }
                                        $subscription = $subscriptionNames[$resource.subscriptionId]
                                        @{
                                            Name         = $resource.name
                                            ResourceId   = $resource.id
                                            Type         = $resource.type
                                            RG           = $resource.resourceGroup
                                            Subscription = if ($subscription) { $subscription } else { $resource.subscriptionId }
                                            Mode         = $result['Mode']
                                            Actual       = $result['Actual']
                                            Expected     = $result['Expected']
                                            Because      = $rule.Because
                                            Skip         = [bool]$result['Skip']
                                            SkipReason   = $result['SkipReason']
                                        }
                                    })
                                $caseCount += $cases.Count
                                if ($cases.Count -gt 0) {
                                    @{ Check = $rule.Check; Cases = $cases }
                                }
                            })
                        if ($checks.Count -gt 0) {
                            @{ Area = $area; Checks = $checks }
                        }
                    })
                Write-CheckProgress -Id 'estate-rules' -Complete -Description ('Evaluated {0:N0} rules: {1:N0} checks' -f $activeRules, $caseCount)
            }
        }
        catch {
            $readErrorCase = @(@{ Message = $_.Exception.Message })
        }
    }
}

# One Describe per area, each tagged with its name so Invoke-AACPester -Tag
# can run just some of them.
foreach ($areaCase in $areas) {
    Describe '<Area>' -Tag $areaCase.Area -ForEach @($areaCase) {
        Context '<Check>' -ForEach $Checks {
            It '<Name> (<Type>, <RG>)' -ForEach $Cases {
                if ($Skip) {
                    Set-ItResult -Skipped -Because $SkipReason
                    return
                }

                $reason = "$Because (subscription $Subscription)"
                switch ($Mode) {
                    'Equal' { $Actual | Should -Be $Expected -Because $reason }
                    'NotEqual' { $Actual | Should -Not -Be $Expected -Because $reason }
                    'In' { $Actual | Should -BeIn $Expected -Because $reason }
                    'Empty' { $Actual | Should -BeNullOrEmpty -Because $reason }
                    'Contain' { $Actual | Should -Contain $Expected -Because $reason }
                    'NotEmpty' { $Actual | Should -Not -BeNullOrEmpty -Because $reason }
                    'Error' { throw $Actual }
                    default { throw "Unknown check mode '$Mode'" }
                }
            }
        }
    }
}

Describe 'Azure estate' -Tag 'Governance', 'Security', 'Networking', 'Operations' {
    It 'Estate meets the governance rules (needs Connect-AAC)' -ForEach $notConnectedCase {
        Set-ItResult -Skipped -Because 'there is no active Azure sign-in in this session - run Connect-AAC first'
    }

    It 'Estate meets the governance rules' -ForEach $noResourcesCase {
        Set-ItResult -Skipped -Because 'the signed-in account can see no resources in the chosen subscriptions (of the chosen types, if ResourceType is set)'
    }

    It 'Estate could be read from Azure' -ForEach $readErrorCase {
        throw "Could not read the estate: $Message"
    }
}
