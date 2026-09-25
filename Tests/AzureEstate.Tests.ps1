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
        Invoke-AACPester -Path .\Azure.Admin.Console\Tests\AzureEstate.Tests.ps1 -Data @{
            SubscriptionId = '00000000-0000-0000-0000-000000000000'
        }

    Only some resource types, listing only the failures:

        Invoke-AACPester -Path .\Azure.Admin.Console\Tests\AzureEstate.Tests.ps1 -FailedOnly -Data @{
            ResourceType = 'microsoft.network/applicationgateways', 'microsoft.servicebus/*'
        }

    Each area is a Describe block tagged with its name, so -Tag picks areas:
        Governance  - approved region; required tags; Service Bus geo-replicas
                      in approved regions; Application Gateway naming
        Security    - storage HTTPS, minimum TLS 1.2, no anonymous blob
                      access; Key Vault purge protection; SQL public network
                      access; App Service HTTPS only; managed disks encrypted
                      with a customer-managed key; Service Bus local auth
                      disabled, minimum TLS 1.2 and audit logs (Premium);
                      Application Gateway WAF SKU and WAF enabled (Internet
                      facing), TLS 1.2 SSL policy, HTTP redirected to HTTPS,
                      classic WAF in prevention mode with OWASP 3.x and all
                      rules on; WAF policies enabled, in prevention mode,
                      without exclusions, with the default and bot rule sets
        Networking  - no RDP/SSH from the Internet; public IPs attached;
                      VNets use custom (hub) DNS servers
        Operations  - VMs protected by Azure Backup (skipped for exempt
                      environments); diagnostic logs sent to Log Analytics;
                      Service Bus geo-replicated and in use; Application
                      Gateway 2+ instances, Medium or larger, v2 SKU, WAF
                      policy instead of classic WAF, availability zones

    The Service Bus and Application Gateway rules follow PSRule for Azure's
    Azure.ServiceBus.*, Azure.AppGw.* and Azure.AppGwWAF.* rules
    (https://azure.github.io/PSRule.Rules.Azure/), each named in its reason.
    The Service Bus in-use rule makes up to two Service Bus calls per
    namespace, and its audit-log rule one Azure Monitor call per Premium
    namespace. The Application Gateway zone rule reads the Microsoft.Network
    provider once per subscription to learn which regions have zones.
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
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Azure.Admin.Console.psd1') -ErrorAction Stop
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
                $request = @{ Method = $Method; Uri = $Uri; Headers = (Get-AuthHeader); ErrorAction = 'Stop' }
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

    # The availability zones Application Gateway offers in a region, as the
    # Microsoft.Network provider reports them - read once per subscription.
    # Nothing is returned for a region without zones.
    $appGwZones = @{}
    function Get-AppGwZone {
        param([string] $Subscription, [string] $Location)
        if (-not $appGwZones.ContainsKey($Subscription)) {
            $zonesByRegion = @{}
            $provider = Invoke-Arm -Uri "https://management.azure.com/subscriptions/$Subscription/providers/Microsoft.Network?api-version=2021-04-01"
            $gatewayType = Get-Value $provider 'resourceTypes' | Where-Object { (Get-Value $_ 'resourceType') -eq 'applicationGateways' } | Select-Object -First 1
            foreach ($mapping in @(Get-Value $gatewayType 'zoneMappings')) {
                $zonesByRegion[((Get-Value $mapping 'location') -replace '\s', '').ToLowerInvariant()] = @(Get-Value $mapping 'zones' | Sort-Object)
            }
            $appGwZones[$Subscription] = $zonesByRegion
        }
        $zones = $appGwZones[$Subscription][($Location -replace '\s', '').ToLowerInvariant()]
        if ($zones) {
            $zones
        }
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
                'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'
            )
            $typeList = ($inspected | ForEach-Object { "'$_'" }) -join ', '
            $resources = @(Invoke-Graph -Query @"
Resources
| extend props = iff(type in~ ($typeList), properties, dynamic(null))
| project id, name, type = tolower(type), location, resourceGroup, subscriptionId, tags, sku, zones, props
| order by type asc, name asc
"@)
            if ($ResourceType.Count -gt 0) {
                $resources = @($resources | Where-Object {
                        $type = $_.type
                        @($ResourceType | Where-Object { $type -like $_ }).Count -gt 0
                    })
            }

            $subscriptionNames = @{}
            foreach ($row in @(Invoke-Graph -Query "ResourceContainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name")) {
                $subscriptionNames[$row.subscriptionId] = $row.name
            }

            # VM resource ID (lower case) -> protection state of its Azure Backup item.
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

                @{ Area = 'Security'; Check = 'Storage requires secure transfer (HTTPS)'; Types = 'microsoft.storage/storageaccounts'
                    Because  = 'supportsHttpsTrafficOnly must be enabled'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.supportsHttpsTrafficOnly') -eq $true; Expected = $true } } 
                }
                @{ Area = 'Security'; Check = 'Storage minimum TLS version is 1.2'; Types = 'microsoft.storage/storageaccounts'
                    Because  = 'TLS 1.0 and 1.1 are retired'
                    Evaluate = { param($r)
                        $tls = Get-Value $r 'props.minimumTlsVersion'
                        @{ Mode = 'In'; Actual = $(if ($tls) { $tls } else { 'TLS1_0 (not set)' }); Expected = @('TLS1_2', 'TLS1_3') } } 
                }
                @{ Area = 'Security'; Check = 'Storage blocks anonymous blob access'; Types = 'microsoft.storage/storageaccounts'
                    Because  = 'allowBlobPublicAccess must be disabled (older accounts allow it when it is not set)'
                    Evaluate = { param($r)
                        $public = Get-Value $r 'props.allowBlobPublicAccess'
                        @{ Mode = 'Equal'; Actual = $(if ($null -eq $public) { 'not set' } else { $public }); Expected = $false } } 
                }
                @{ Area = 'Security'; Check = 'Key Vault has purge protection'; Types = 'microsoft.keyvault/vaults'
                    Because  = 'deleted secrets, keys and certificates must be recoverable'
                    Evaluate = { param($r) @{ Mode = 'Equal'; Actual = (Get-Value $r 'props.enablePurgeProtection') -eq $true; Expected = $true } } 
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
                            $offered = @(Get-AppGwZone -Subscription $r.subscriptionId -Location $r.location)
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
            )

            # --- One test case per rule and resource -------------------------------
            if ($resources.Count -eq 0) {
                $noResourcesCase = @(@{})
            }
            else {
                $areas = @(foreach ($area in @($rules | ForEach-Object { $_.Area } | Select-Object -Unique)) {
                        $checks = @(foreach ($rule in @($rules | Where-Object { $_.Area -eq $area })) {
                                $cases = @(foreach ($resource in $resources) {
                                        if ($rule.Types -ne '*' -and $resource.type -notin $rule.Types) {
                                            continue
                                        }
                                        $result = & $rule.Evaluate $resource
                                        if (-not $result) {
                                            continue
                                        }
                                        $subscription = $subscriptionNames[$resource.subscriptionId]
                                        @{
                                            Name         = $resource.name
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
                                if ($cases.Count -gt 0) {
                                    @{ Check = $rule.Check; Cases = $cases }
                                }
                            })
                        if ($checks.Count -gt 0) {
                            @{ Area = $area; Checks = $checks }
                        }
                    })
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
