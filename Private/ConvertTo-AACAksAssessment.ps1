function ConvertTo-AACAksAssessment {
    <#
    .SYNOPSIS
        Assesses AKS clusters through every lens - current settings, the
        Well-Architected Framework, PSRule for Azure, Azure Policy, versions
        and upgrades, capacity, Advisor and Defender for Cloud - the model
        behind Invoke-AACAksAssessment.
    .DESCRIPTION
        No Azure calls. Inputs:
          -Cluster           the clusters as Export-AzRuleData shapes them
                             (Get-AACRuleData): properties, sku, identity, and
                             their child settings in 'resources' (diagnostic
                             settings, maintenance configurations, subnets)
          -UpgradeProfile    cluster ID -> its upgradeProfiles/default
          -PoolUpgrade       '<cluster ID>/<pool>' -> the pool's upgrade profile
                             (the latest node image)
          -KubernetesVersion location -> the versions AKS offers there
          -Subnet            subnet ID -> the subnet (nodes' and pods')
          -Advisor, -Defender  Resource Graph rows (Get-AACAksQuery)
          -PSRule            PSRule for Azure's results for the clusters
          -Policy            ConvertTo-AACAksPolicyCompliance's result
          -Constraint        cluster ID -> Get-AACAksConstraint's result

        Returns a hashtable:
          Clusters     AAC.AksCluster: the summary of each - version and its
                       support, tier, nodes, network, API access, identity,
                       upgrades, monitoring, policy, WAF score per pillar,
                       findings by severity
          NodePools    AAC.AksNodePool: size, mode, OS, nodes, autoscale,
                       zones, max pods, versions, node image and its age,
                       disk, spot, subnet and its free IPs, taints
          Settings     AAC.AksSetting: every setting that matters, by area
                       (General, Upgrades, Identity and access, Networking,
                       Security, Monitoring, Add-ons, Autoscaler)
          Upgrades     AAC.AksUpgrade: the control plane and each pool -
                       current, available, latest, support
          Checks       AAC.AksCheck: each Well-Architected check, Pass or
                       Fail, by pillar
          Findings     AAC.AksFinding: what failed - from the WAF checks,
                       PSRule, Advisor, Defender, Azure Policy and Gatekeeper
                       - most severe first
          Diagnostics, Maintenance, Constraints, PSRule, Policy, Pillars, Stats
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Cluster,

        [hashtable] $UpgradeProfile = @{},
        [hashtable] $PoolUpgrade = @{},
        [hashtable] $KubernetesVersion = @{},
        [hashtable] $Subnet = @{},
        [AllowEmptyCollection()] [object[]] $Advisor = @(),
        [AllowEmptyCollection()] [object[]] $Defender = @(),
        [AllowEmptyCollection()] [object[]] $PSRule = @(),
        [hashtable] $Policy,
        [hashtable] $Constraint = @{},
        [hashtable] $SubscriptionName = @{},
        [datetime] $Now = (Get-Date)
    )

    # --- Helpers -----------------------------------------------------------------------------------------------------
    $at = {
        param($Item, [string] $Path)
        foreach ($part in ($Path -split '\.')) {
            if ($Item -is [System.Collections.IDictionary]) { $Item = if ($Item.Contains($part)) { $Item[$part] } else { $null } }
            elseif ($null -ne $Item -and $Item -isnot [string] -and $Item -isnot [ValueType] -and $Item -isnot [System.Collections.IEnumerable]) { $Item = Get-AACPropertyValue -InputObject $Item -Name $part }
            else { return $null }
        }
        $Item
    }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) if ($Id) { ([string]$Id).TrimEnd('/') -replace '^.*/', '' } else { '' } }
    $isTrue = { param($Value) $null -ne $Value -and ([string]$Value -eq 'True' -or [string]$Value -eq 'true') }
    $yesNo = { param($Value) if (& $isTrue $Value) { 'Yes' } else { 'No' } }
    $object = { param([string] $TypeName, [System.Collections.IDictionary] $Property) $item = [pscustomobject]$Property; $item.PSObject.TypeNames.Insert(0, $TypeName); $item }
    $sumOf = { param($Values) $t = [long]0; foreach ($v in $Values) { if ($null -ne $v -and "$v" -ne '') { $t += [long]$v } }; $t }
    $docs = 'https://learn.microsoft.com/azure'
    $pillars = @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')
    $rank = @{ Critical = 0; High = 1; Medium = 2; Low = 3; Info = 4 }

    $clusters = [System.Collections.Generic.List[object]]::new()
    $pools = [System.Collections.Generic.List[object]]::new()
    $settings = [System.Collections.Generic.List[object]]::new()
    $upgrades = [System.Collections.Generic.List[object]]::new()
    $checks = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $maintenance = [System.Collections.Generic.List[object]]::new()
    $constraints = [System.Collections.Generic.List[object]]::new()
    # The subnets: those given, and those in the clusters' child settings (PSRule reads them).
    $subnets = @{}
    foreach ($k in $Subnet.Keys) { $subnets[(& $lower $k)] = $Subnet[$k] }
    foreach ($c in $Cluster) {
        foreach ($child in @(& $list (& $at $c 'resources'))) {
            if ([string](& $at $child 'type') -like '*virtualNetworks/subnets' -and (& $at $child 'id')) { $subnets[(& $lower (& $at $child 'id'))] = $child }
        }
    }

    foreach ($c in $Cluster) {
        $id = [string](& $at $c 'id')
        $key = & $lower $id
        $name = [string](& $at $c 'name')
        $p = & $at $c 'properties'
        $location = & $lower (& $at $c 'location')
        $subscriptionId = if ($id -match '^/subscriptions/([^/]+)') { $Matches[1].ToLowerInvariant() } else { '' }
        $subscription = if ($SubscriptionName.Contains($subscriptionId)) { $SubscriptionName[$subscriptionId] } else { $subscriptionId }
        $group = [string]$(if (& $at $c 'resourceGroupName') { & $at $c 'resourceGroupName' } else { & $at $c 'resourceGroup' })
        $children = @(& $list (& $at $c 'resources'))
        $tier = [string](& $at $c 'sku.tier')
        $supportPlan = [string](& $at $p 'supportPlan')
        $version = [string]$(if (& $at $p 'currentKubernetesVersion') { & $at $p 'currentKubernetesVersion' } else { & $at $p 'kubernetesVersion' })
        $minor = if ($version -match '^(\d+\.\d+)') { $Matches[1] } else { $version }
        $agentPools = @(& $list (& $at $p 'agentPoolProfiles'))
        $network = & $at $p 'networkProfile'
        $plugin = [string](& $at $network 'networkPlugin')
        $pluginMode = [string](& $at $network 'networkPluginMode')
        $dataplane = [string](& $at $network 'networkDataplane')
        $networkPolicy = [string](& $at $network 'networkPolicy')
        $api = & $at $p 'apiServerAccessProfile'
        $private = & $isTrue (& $at $api 'enablePrivateCluster')
        $authorized = @(& $list (& $at $api 'authorizedIPRanges'))
        $aad = & $at $p 'aadProfile'
        $security = & $at $p 'securityProfile'
        $addons = & $at $p 'addonProfiles'
        $addon = {
            param([string[]] $Names)
            foreach ($n in $Names) { if ($addons -is [System.Collections.IDictionary]) { foreach ($k in $addons.Keys) { if ($k -ieq $n) { return $addons[$k] } } } }
            $null
        }
        $addonOn = { param([string[]] $Names) & $isTrue (& $at (& $addon $Names) 'enabled') }
        $autoUpgrade = [string](& $at $p 'autoUpgradeProfile.upgradeChannel')
        $nodeOsUpgrade = [string](& $at $p 'autoUpgradeProfile.nodeOSUpgradeChannel')
        $diagnosticRows = @($children | Where-Object { [string](& $at $_ 'type') -like '*diagnosticSettings' })
        $maintenanceRows = @($children | Where-Object { [string](& $at $_ 'type') -like '*maintenanceConfigurations' })
        $versions = @(if ($KubernetesVersion.Contains($location)) { $KubernetesVersion[$location] })
        $clusterUpgrade = if ($UpgradeProfile.Contains($key)) { $UpgradeProfile[$key] } else { $null }

        # --- Version and its support ------------------------------------------------------------------------------
        $entry = @($versions | Where-Object { [string](& $at $_ 'version') -eq $minor }) | Select-Object -First 1
        $plans = @(& $list (& $at $entry 'capabilities.supportPlan'))
        $ga = @($versions | Where-Object { -not (& $isTrue (& $at $_ 'isPreview')) -and @(& $list (& $at $_ 'capabilities.supportPlan')) -contains 'KubernetesOfficial' } | ForEach-Object { [string](& $at $_ 'version') })
        $toVersion = { param([string] $Text) try { [version]($Text -replace '[^\d.].*$', '') } catch { $null } }
        $gaSorted = @($ga | Sort-Object { & $toVersion $_ })
        $latestMinor = if ($gaSorted.Count) { $gaSorted[-1] } else { '' }
        $support = if (-not $versions.Count) { 'Unknown' }
        elseif (-not $entry) { 'Out of support' }
        elseif (& $isTrue (& $at $entry 'isPreview')) { 'Preview' }
        elseif ($plans -notcontains 'KubernetesOfficial' -and $plans -contains 'AKSLongTermSupport') { $(if ($supportPlan -eq 'AKSLongTermSupport') { 'Long-term support' } else { 'Out of support (LTS only)' }) }
        else { 'Supported' }
        $behind = if ($latestMinor -and $gaSorted -contains $minor) { $gaSorted.Count - 1 - [array]::IndexOf($gaSorted, $minor) } else { $null }
        $patches = @(if ($entry -and (& $at $entry 'patchVersions') -is [System.Collections.IDictionary]) { (& $at $entry 'patchVersions').Keys })
        $latestPatch = @($patches | Sort-Object { & $toVersion $_ }) | Select-Object -Last 1
        $available = @(@(& $list (& $at $clusterUpgrade 'properties.controlPlaneProfile.upgrades')) | Where-Object { -not (& $isTrue (& $at $_ 'isPreview')) } | ForEach-Object { [string](& $at $_ 'kubernetesVersion') } | Sort-Object { & $toVersion $_ })
        $upgrades.Add((& $object 'AAC.AksUpgrade' ([ordered]@{
                        Cluster = $name; Component = 'Control plane'; Current = $version; Support = $support; Available = $available -join ', '
                        Latest = $(if ($available.Count) { $available[-1] } else { '' }); LatestPatch = [string]$latestPatch; LatestMinor = $latestMinor
                        Behind = $behind; Channel = $(if ($autoUpgrade) { $autoUpgrade } else { 'none' }); NodeImage = ''; NodeImageAge = $null; LatestNodeImage = ''; ClusterId = $id
                    })))

        # --- Checks (the Well-Architected lens) -------------------------------------------------------------------------
        $clusterChecks = [System.Collections.Generic.List[object]]::new()
        $check = {
            param([string] $Pillar, [string] $Check, [string] $Severity, [bool] $Passed, [string] $Detail, [string] $Action, [string] $Link, [string] $Item = '')
            $row = & $object 'AAC.AksCheck' ([ordered]@{ Cluster = $name; Pillar = $Pillar; Check = $Check; Item = $Item; Status = $(if ($Passed) { 'Pass' } else { 'Fail' }); Severity = $Severity; Detail = $Detail; Recommendation = $Action; Link = $Link; ClusterId = $id })
            $clusterChecks.Add($row)
            $checks.Add($row)
        }
        $systemPools = @($agentPools | Where-Object { [string](& $at $_ 'mode') -eq 'System' })
        $userPools = @($agentPools | Where-Object { [string](& $at $_ 'mode') -ne 'System' })
        $zoned = @($agentPools | Where-Object { @(& $list (& $at $_ 'availabilityZones')).Count -gt 1 })

        # Reliability
        & $check 'Reliability' 'Uptime SLA (Standard or Premium tier)' 'Medium' ($tier -in 'Standard', 'Premium') "The cluster is on the $(if ($tier) { $tier } else { 'Free' }) tier$(if ($tier -notin 'Standard', 'Premium') { ': the control plane has no financially backed SLA and fewer API server resources' })." 'Use the Standard tier (Premium for long-term support) for production clusters.' "$docs/aks/free-standard-pricing-tiers"
        & $check 'Reliability' 'Node pools across availability zones' 'Medium' ($zoned.Count -eq $agentPools.Count -and $agentPools.Count -gt 0) "$($agentPools.Count - $zoned.Count) of $($agentPools.Count) node pool(s) are not spread across zones: $(@($agentPools | Where-Object { @(& $list (& $at $_ 'availabilityZones')).Count -le 1 } | ForEach-Object { & $at $_ 'name' }) -join ', ')." 'Create node pools across availability zones (zones can only be set when a pool is created) in regions that have them.' "$docs/aks/availability-zones"
        $systemNodes = & $sumOf @($systemPools | ForEach-Object { $(if (& $isTrue (& $at $_ 'enableAutoScaling')) { & $at $_ 'minCount' } else { & $at $_ 'count' }) })
        & $check 'Reliability' 'System node pool with at least 2 nodes' 'Medium' ($systemNodes -ge 2) "The system pool(s) can run $systemNodes node(s)$(if ($systemNodes -lt 2) { ': one node failing or being upgraded takes CoreDNS and the other system pods down with it' })." 'Run at least 2 (better 3) nodes in the system pool, with autoscale minimum 2 or more.' "$docs/aks/use-system-pools"
        & $check 'Reliability' 'User workloads off the system pool' 'Low' ($userPools.Count -gt 0 -or $agentPools.Count -eq 0) $(if ($userPools.Count) { "$($userPools.Count) user pool(s) for workloads." } else { 'There is only a system pool: application pods share nodes with CoreDNS, metrics-server and the other system pods.' }) 'Add a user node pool for applications, and taint the system pool CriticalAddonsOnly=true:NoSchedule.' "$docs/aks/use-system-pools"
        $spotSystem = @($systemPools | Where-Object { [string](& $at $_ 'scaleSetPriority') -eq 'Spot' })
        & $check 'Reliability' 'No Spot nodes in the system pool' 'High' (-not $spotSystem.Count) 'Spot nodes can be evicted at any time.' 'Run the system pool on regular (not Spot) nodes.' "$docs/aks/spot-node-pool"
        & $check 'Reliability' 'Kubernetes version supported' 'High' ($support -in 'Supported', 'Long-term support', 'Unknown') "Kubernetes $version is $($support.ToLowerInvariant())$(if ($latestMinor) { "; AKS's newest generally available version here is $latestMinor" })." "Upgrade the cluster to a supported version$(if ($available.Count) { " (available: $($available -join ', '))" }) - one minor version at a time." "$docs/aks/supported-kubernetes-versions"
        if ($null -ne $behind) { & $check 'Reliability' 'Within one minor version of the newest' 'Medium' ($behind -le 1) "Kubernetes $minor is $behind minor version(s) behind $latestMinor." 'Plan the upgrade before this version leaves support (AKS supports three minor versions, plus LTS).' "$docs/aks/supported-kubernetes-versions" }
        & $check 'Reliability' 'Planned maintenance window' 'Low' ($maintenanceRows.Count -gt 0) $(if ($maintenanceRows.Count) { "$($maintenanceRows.Count) maintenance configuration(s): $(@($maintenanceRows | ForEach-Object { & $at $_ 'name' }) -join ', ')." } else { 'No maintenance window: automatic upgrades and node OS updates can happen at any time.' }) 'Set aksManagedAutoUpgradeSchedule and aksManagedNodeOSUpgradeSchedule windows outside business hours.' "$docs/aks/planned-maintenance"
        $noSurge = @($agentPools | Where-Object { -not (& $at $_ 'upgradeSettings.maxSurge') })
        & $check 'Reliability' 'Node surge set for upgrades' 'Low' (-not $noSurge.Count) $(if ($noSurge.Count) { "No max surge set on $(@($noSurge | ForEach-Object { & $at $_ 'name' }) -join ', '): upgrades add one node at a time." } else { 'Every pool sets its upgrade surge.' }) 'Set maxSurge (33% is a good start for production) so upgrades are faster without draining too much at once.' "$docs/aks/upgrade-aks-cluster#customize-node-surge-upgrade"

        # Security
        $localAccounts = -not (& $isTrue (& $at $p 'disableLocalAccounts'))
        & $check 'Security' 'Local accounts disabled' 'High' (-not $localAccounts) $(if ($localAccounts) { 'Local accounts are on: anyone with listClusterAdminCredential gets a non-auditable cluster-admin certificate.' } else { 'Local accounts are off.' }) 'Disable local accounts (Entra ID integration needed) so every access is an Entra identity.' "$docs/aks/manage-local-accounts-managed-azure-ad"
        & $check 'Security' 'Entra ID integration' 'High' ($null -ne $aad) $(if ($aad) { "Entra ID integrated$(if (& $at $aad 'managed') { ' (managed)' })." } else { 'No Entra ID integration: access is by client certificates only.' }) 'Enable AKS-managed Entra ID integration.' "$docs/aks/enable-authentication-microsoft-entra-id"
        & $check 'Security' 'Azure RBAC for Kubernetes authorization' 'Medium' (& $isTrue (& $at $aad 'enableAzureRBAC')) $(if (& $isTrue (& $at $aad 'enableAzureRBAC')) { 'Azure RBAC authorizes Kubernetes access.' } else { 'Kubernetes RBAC only: access is managed in each cluster, not in Azure.' }) 'Enable Azure RBAC for Kubernetes authorization to manage access with Azure role assignments.' "$docs/aks/manage-azure-rbac"
        $apiOpen = -not $private -and -not $authorized.Count -and -not (& $isTrue (& $at $api 'enableVnetIntegration'))
        & $check 'Security' 'API server not open to the internet' 'High' (-not $apiOpen) $(if ($private) { 'Private cluster: the API server has a private endpoint.' } elseif ($authorized.Count) { "Public API server limited to $($authorized.Count) authorized IP range(s)." } else { 'The API server is public and reachable from any IP address.' }) 'Make the cluster private, or restrict the public API server to authorized IP ranges.' "$docs/aks/api-server-authorized-ip-ranges"
        & $check 'Security' 'Network policy' 'Medium' ($networkPolicy -and $networkPolicy -ne 'none') $(if ($networkPolicy -and $networkPolicy -ne 'none') { "Network policy engine: $networkPolicy." } else { 'No network policy engine: every pod can reach every other pod.' }) 'Enable a network policy engine (Azure, Calico or Cilium) and apply default-deny policies per namespace.' "$docs/aks/use-network-policies"
        & $check 'Security' 'Azure Policy add-on' 'Medium' (& $addonOn 'azurepolicy') $(if (& $addonOn 'azurepolicy') { 'Azure Policy for Kubernetes is on.' } else { 'The Azure Policy add-on is off: no Kubernetes policy is evaluated or enforced in the cluster.' }) 'Enable the Azure Policy add-on and assign the Kubernetes pod security baseline initiative.' "$docs/aks/use-azure-policy"
        & $check 'Security' 'Defender for Containers sensor' 'Medium' (& $isTrue (& $at $security 'defender.securityMonitoring.enabled')) $(if (& $isTrue (& $at $security 'defender.securityMonitoring.enabled')) { 'The Defender sensor is on.' } else { 'No Defender for Containers sensor: no runtime threat detection.' }) 'Enable Defender for Containers on the subscription with the sensor on the cluster.' "$docs/defender-for-cloud/defender-for-containers-introduction"
        & $check 'Security' 'Workload identity' 'Low' (& $isTrue (& $at $security 'workloadIdentity.enabled')) $(if (& $isTrue (& $at $security 'workloadIdentity.enabled')) { 'Workload identity is on.' } else { 'Workload identity is off: pods reach Azure with secrets or the node''s identity.' }) 'Enable the OIDC issuer and workload identity, and federate pods'' service accounts with managed identities.' "$docs/aks/workload-identity-overview"
        $podIdentity = & $isTrue (& $at $p 'podIdentityProfile.enabled')
        & $check 'Security' 'No pod-managed identity (deprecated)' 'Medium' (-not $podIdentity) $(if ($podIdentity) { 'Pod-managed identity (aad-pod-identity) is on: it is deprecated.' } else { 'Pod-managed identity is off.' }) 'Move to workload identity.' "$docs/aks/use-azure-ad-pod-identity"
        & $check 'Security' 'Image cleaner' 'Low' (& $isTrue (& $at $security 'imageCleaner.enabled')) $(if (& $isTrue (& $at $security 'imageCleaner.enabled')) { 'Image cleaner removes unused, vulnerable images.' } else { 'Image cleaner is off: stale vulnerable images stay on the nodes.' }) 'Enable image cleaner.' "$docs/aks/image-cleaner"
        & $check 'Security' 'etcd encrypted with your key (KMS)' 'Low' (& $isTrue (& $at $security 'azureKeyVaultKms.enabled')) $(if (& $isTrue (& $at $security 'azureKeyVaultKms.enabled')) { 'KMS etcd encryption is on.' } else { 'Kubernetes secrets are encrypted with platform keys only.' }) 'Enable KMS etcd encryption with a key in Key Vault, where your standards require customer-managed keys.' "$docs/aks/use-kms-etcd-encryption"
        $publicNodes = @($agentPools | Where-Object { & $isTrue (& $at $_ 'enableNodePublicIP') })
        & $check 'Security' 'No public IPs on nodes' 'High' (-not $publicNodes.Count) $(if ($publicNodes.Count) { "Nodes have public IPs in $(@($publicNodes | ForEach-Object { & $at $_ 'name' }) -join ', ')." } else { 'No node has a public IP.' }) 'Recreate those pools without node public IPs; reach nodes through the cluster or Bastion.' "$docs/aks/use-node-public-ips"
        $noHostEncryption = @($agentPools | Where-Object { -not (& $isTrue (& $at $_ 'enableEncryptionAtHost')) })
        & $check 'Security' 'Encryption at host' 'Low' (-not $noHostEncryption.Count) $(if ($noHostEncryption.Count) { "No encryption at host on $(@($noHostEncryption | ForEach-Object { & $at $_ 'name' }) -join ', '): temp disks and caches aren't encrypted." } else { 'Every pool encrypts at host.' }) 'Use encryption at host for new pools.' "$docs/aks/enable-host-encryption"
        $servicePrincipal = -not (& $at $c 'identity') -and [string](& $at $p 'servicePrincipalProfile.clientId') -and [string](& $at $p 'servicePrincipalProfile.clientId') -ne 'msi'
        & $check 'Security' 'Managed identity (not a service principal)' 'Medium' (-not $servicePrincipal) $(if ($servicePrincipal) { 'The cluster uses a service principal: its secret expires and has to be rotated.' } else { "The cluster uses a managed identity ($([string](& $at $c 'identity.type')))." }) 'Update the cluster to use a managed identity.' "$docs/aks/use-managed-identity"
        $secretsProvider = & $addon 'azureKeyvaultSecretsProvider'
        if (& $isTrue (& $at $secretsProvider 'enabled')) { & $check 'Security' 'Key Vault secrets rotation' 'Low' ((& $at $secretsProvider 'config.enableSecretRotation') -eq 'true') 'The Key Vault secrets provider is on.' 'Turn on secret rotation so pods get rotated secrets.' "$docs/aks/csi-secrets-store-driver" }
        & $check 'Security' 'Node resource group locked down' 'Low' ([string](& $at $p 'nodeResourceGroupProfile.restrictionLevel') -eq 'ReadOnly') "Node resource group restriction: $(if (& $at $p 'nodeResourceGroupProfile.restrictionLevel') { & $at $p 'nodeResourceGroupProfile.restrictionLevel' } else { 'Unrestricted' })." 'Make the node resource group read-only so its resources are changed only through AKS.' "$docs/aks/node-resource-group-lockdown"

        # Operational Excellence
        & $check 'Operational Excellence' 'Automatic cluster upgrades' 'Medium' ($autoUpgrade -and $autoUpgrade -ne 'none') "Upgrade channel: $(if ($autoUpgrade) { $autoUpgrade } else { 'none' })." 'Set an upgrade channel (patch or stable) with a maintenance window.' "$docs/aks/auto-upgrade-cluster"
        & $check 'Operational Excellence' 'Automatic node OS updates' 'Medium' ($nodeOsUpgrade -in 'NodeImage', 'SecurityPatch') "Node OS upgrade channel: $(if ($nodeOsUpgrade) { $nodeOsUpgrade } else { 'not set' })." 'Set the node OS upgrade channel to NodeImage (or SecurityPatch) with a maintenance window.' "$docs/aks/auto-upgrade-node-os-image"
        & $check 'Operational Excellence' 'Container insights' 'Medium' (& $addonOn 'omsagent', 'omsAgent') $(if (& $addonOn 'omsagent', 'omsAgent') { "Container insights sends logs to $(& $leaf (& $at (& $addon 'omsagent', 'omsAgent') 'config.logAnalyticsWorkspaceResourceID'))." } else { 'Container insights is off: no container logs or inventory in Log Analytics.' }) 'Enable Container insights (with the cost-optimized data collection settings).' "$docs/azure-monitor/containers/container-insights-overview"
        & $check 'Operational Excellence' 'Managed Prometheus metrics' 'Low' (& $isTrue (& $at $p 'azureMonitorProfile.metrics.enabled')) $(if (& $isTrue (& $at $p 'azureMonitorProfile.metrics.enabled')) { 'Azure Monitor managed Prometheus collects the metrics.' } else { 'No managed Prometheus: no cluster and workload metrics or recommended alerts.' }) 'Enable managed Prometheus, Grafana dashboards and the recommended alert rules.' "$docs/azure-monitor/essentials/prometheus-metrics-overview"
        $categories = @(foreach ($d in $diagnosticRows) { foreach ($log in @(& $list (& $at $d 'properties.logs'))) { if (& $isTrue (& $at $log 'enabled')) { [string]$(if (& $at $log 'category') { & $at $log 'category' } else { & $at $log 'categoryGroup' }) } } }) | Select-Object -Unique
        $audit = @($categories | Where-Object { $_ -in 'kube-audit', 'kube-audit-admin', 'audit', 'allLogs' })
        & $check 'Operational Excellence' 'Control plane logs (kube-audit)' 'Medium' ($audit.Count -gt 0) $(if (-not $diagnosticRows.Count) { 'No diagnostic setting: the API server, audit and autoscaler logs are kept nowhere.' } elseif ($audit.Count) { "Diagnostic settings send $($categories -join ', ')." } else { "Diagnostic settings send $(if ($categories) { $categories -join ', ' } else { 'nothing' }), but no audit logs." }) 'Send kube-audit-admin (or kube-audit), kube-apiserver, cluster-autoscaler and guard to a Log Analytics workspace (resource-specific tables).' "$docs/aks/monitor-aks"
        $versionDrift = @($agentPools | Where-Object { [string](& $at $_ 'currentOrchestratorVersion') -and [string](& $at $_ 'currentOrchestratorVersion') -ne $version })
        & $check 'Operational Excellence' 'Node pools on the control plane''s version' 'Low' (-not $versionDrift.Count) $(if ($versionDrift.Count) { "$(@($versionDrift | ForEach-Object { "$(& $at $_ 'name') ($(& $at $_ 'currentOrchestratorVersion'))" }) -join ', ') run another version than the control plane ($version)." } else { 'Every pool runs the control plane''s version.' }) 'Upgrade the node pools to the control plane''s version.' "$docs/aks/upgrade-aks-cluster"
        $httpRouting = & $addonOn 'httpApplicationRouting', 'httpapplicationrouting'
        & $check 'Operational Excellence' 'No HTTP application routing add-on (retired)' 'Medium' (-not $httpRouting) $(if ($httpRouting) { 'The HTTP application routing add-on is on: it is retired and not for production.' } else { 'HTTP application routing is off.' }) 'Move to the application routing add-on (managed NGINX) or Application Gateway for Containers.' "$docs/aks/app-routing"

        # Cost Optimization
        $fixed = @($userPools | Where-Object { -not (& $isTrue (& $at $_ 'enableAutoScaling')) -and [int](& $at $_ 'count') -gt 0 })
        & $check 'Cost Optimization' 'Cluster autoscaler on user pools' 'Low' (-not $fixed.Count) $(if ($fixed.Count) { "Fixed-size user pool(s): $(@($fixed | ForEach-Object { "$(& $at $_ 'name') ($(& $at $_ 'count') nodes)" }) -join ', ')." } else { 'Every user pool scales with demand.' }) 'Enable the cluster autoscaler so pools shrink when idle (or use node auto-provisioning).' "$docs/aks/cluster-autoscaler"
        & $check 'Cost Optimization' 'Cost analysis add-on' 'Low' (& $isTrue (& $at $p 'metricsProfile.costAnalysis.enabled')) $(if (& $isTrue (& $at $p 'metricsProfile.costAnalysis.enabled')) { 'Cost analysis shows cost per namespace and workload.' } else { 'Cost analysis is off: costs can''t be read per namespace or workload.' }) 'Enable the cost analysis add-on (Standard or Premium tier).' "$docs/aks/cost-analysis"

        # Performance Efficiency
        $managedDisks = @($agentPools | Where-Object { [string](& $at $_ 'osDiskType') -ne 'Ephemeral' })
        & $check 'Performance Efficiency' 'Ephemeral OS disks' 'Low' (-not $managedDisks.Count) $(if ($managedDisks.Count) { "Managed OS disks on $(@($managedDisks | ForEach-Object { & $at $_ 'name' }) -join ', '): slower node starts and reimages, and disk cost." } else { 'Every pool uses ephemeral OS disks.' }) 'Use ephemeral OS disks where the VM size has a large enough cache or temp disk.' "$docs/aks/concepts-storage#ephemeral-os-disk"
        & $check 'Performance Efficiency' 'Supported network plugin (not kubenet)' 'Medium' ($plugin -ne 'kubenet') "Network plugin: $plugin$(if ($pluginMode) { " ($pluginMode)" })$(if ($plugin -eq 'kubenet') { ' - kubenet retires on 31 March 2028' })." 'Move to Azure CNI Overlay (and Cilium dataplane).' "$docs/aks/upgrade-azure-cni"
        & $check 'Performance Efficiency' 'Standard load balancer' 'High' ([string](& $at $network 'loadBalancerSku') -ne 'basic') "Load balancer SKU: $(& $at $network 'loadBalancerSku')." 'Basic load balancers are retired: migrate to Standard.' "$docs/aks/load-balancer-standard"

        # --- Node pools, their subnet capacity ---------------------------------------------------------------------------
        $poolUpgradeAvailable = 0
        $needBySubnet = @{}
        $flatCni = $plugin -eq 'azure' -and $pluginMode -ne 'overlay'
        foreach ($pool in $agentPools) {
            $poolName = [string](& $at $pool 'name')
            $autoscale = & $isTrue (& $at $pool 'enableAutoScaling')
            $nodes = [int](& $at $pool 'count')
            $max = if ($autoscale) { [int](& $at $pool 'maxCount') } else { $nodes }
            $maxPods = [int](& $at $pool 'maxPods')
            $image = [string](& $at $pool 'nodeImageVersion')
            $imageDate = if ($image -match '(\d{4})(\d{2})\.(\d{2})') { try { [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) } catch { $null } } else { $null }
            $imageAge = if ($imageDate) { [int]($Now - $imageDate).TotalDays } else { $null }
            $poolProfile = $PoolUpgrade["$key/$($poolName.ToLowerInvariant())"]
            $latestImage = [string](& $at $poolProfile 'properties.latestNodeImageVersion')
            if ($latestImage -and $image -and $latestImage -ne $image) { $poolUpgradeAvailable++ }
            $surge = [string](& $at $pool 'upgradeSettings.maxSurge')
            $surgeNodes = if ($surge -match '^(\d+)%$') { [Math]::Ceiling($max * [int]$Matches[1] / 100) } elseif ($surge -match '^\d+$') { [int]$surge } else { 1 }
            $nodeSubnet = & $lower (& $at $pool 'vnetSubnetID')
            $podSubnet = & $lower (& $at $pool 'podSubnetID')
            # IPs at full scale: a node each, and - with flat Azure CNI - a pod each in the node subnet.
            if ($nodeSubnet) { $needBySubnet[$nodeSubnet] = [long]$(if ($needBySubnet.Contains($nodeSubnet)) { $needBySubnet[$nodeSubnet] } else { 0 }) + ($max + $surgeNodes) * $(if ($flatCni -and -not $podSubnet) { $maxPods + 1 } else { 1 }) }
            if ($podSubnet) { $needBySubnet[$podSubnet] = [long]$(if ($needBySubnet.Contains($podSubnet)) { $needBySubnet[$podSubnet] } else { 0 }) + ($max + $surgeNodes) * $maxPods }
            $pools.Add((& $object 'AAC.AksNodePool' ([ordered]@{
                            Cluster = $name; Pool = $poolName; Mode = [string](& $at $pool 'mode'); VmSize = [string](& $at $pool 'vmSize'); OsType = [string](& $at $pool 'osType'); OsSku = [string](& $at $pool 'osSKU')
                            Nodes = $nodes; Autoscale = $(if ($autoscale) { 'Yes' } else { 'No' }); Min = $(if ($autoscale) { [int](& $at $pool 'minCount') } else { $null }); Max = $(if ($autoscale) { $max } else { $null })
                            Zones = (@(& $list (& $at $pool 'availabilityZones')) -join ', '); MaxPods = $maxPods; Version = [string](& $at $pool 'currentOrchestratorVersion')
                            NodeImage = $image; NodeImageAge = $imageAge; LatestNodeImage = $latestImage; OsDiskType = [string](& $at $pool 'osDiskType'); OsDiskGB = & $at $pool 'osDiskSizeGB'
                            Priority = $(if (& $at $pool 'scaleSetPriority') { [string](& $at $pool 'scaleSetPriority') } else { 'Regular' }); MaxSurge = $surge
                            Subnet = $(if ($nodeSubnet -match '/virtualnetworks/([^/]+)/subnets/([^/]+)') { "$($Matches[1])/$($Matches[2])" } else { '' }); PodSubnet = $(if ($podSubnet) { & $leaf $podSubnet } else { '' })
                            PublicIp = & $yesNo (& $at $pool 'enableNodePublicIP'); EncryptionAtHost = & $yesNo (& $at $pool 'enableEncryptionAtHost'); Fips = & $yesNo (& $at $pool 'enableFIPS')
                            Taints = (@(& $list (& $at $pool 'nodeTaints')) -join ', '); PowerState = [string](& $at $pool 'powerState.code'); State = [string](& $at $pool 'provisioningState')
                            ClusterId = $id
                        })))
            $upgrades.Add((& $object 'AAC.AksUpgrade' ([ordered]@{
                            Cluster = $name; Component = "Node pool $poolName"; Current = [string](& $at $pool 'currentOrchestratorVersion'); Support = ''; Available = ''; Latest = ''; LatestPatch = ''; LatestMinor = ''
                            Behind = $null; Channel = $(if ($nodeOsUpgrade) { $nodeOsUpgrade } else { 'not set' }); NodeImage = $image; NodeImageAge = $imageAge; LatestNodeImage = $latestImage; ClusterId = $id
                        })))
        }
        $oldImages = @($pools | Where-Object { $_.ClusterId -eq $id -and $null -ne $_.NodeImageAge -and $_.NodeImageAge -gt 60 })
        & $check 'Security' 'Node images patched (60 days or newer)' 'Medium' (-not $oldImages.Count) $(if ($oldImages.Count) { "Node images older than 60 days: $(@($oldImages | ForEach-Object { "$($_.Pool) ($($_.NodeImageAge) days)" }) -join ', ')." } else { 'Every pool''s node image is recent.' }) 'Upgrade the node images (or set the node OS upgrade channel to NodeImage).' "$docs/aks/node-image-upgrade"
        $short = @(foreach ($subnetId in $needBySubnet.Keys) {
                $subnetRow = $subnets[$subnetId]
                $prefixes = @(@(& $at $subnetRow 'properties.addressPrefix') + @(& $list (& $at $subnetRow 'properties.addressPrefixes')) | Where-Object { $_ } | Select-Object -Unique)
                $usable = 0
                foreach ($prefix in $prefixes) { $range = ConvertTo-AACCidrRange ([string]$prefix); if ($range.Version -eq 4 -and $range.Valid) { $usable += [Math]::Max(0, $range.Size - 5) } }
                if ($usable -and $needBySubnet[$subnetId] -gt $usable) { "$(if ($subnetId -match '/virtualnetworks/([^/]+)/subnets/([^/]+)') { "$($Matches[1])/$($Matches[2])" }) ($($prefixes -join ', '): $usable usable, $($needBySubnet[$subnetId]) needed at full scale)" }
            })
        if ($needBySubnet.Count) { & $check 'Performance Efficiency' 'Subnets fit the pools at full scale' 'High' (-not $short.Count) $(if ($short.Count) { "Not enough IPs to scale out (max nodes and surge$(if ($flatCni) { ', a pod IP each with Azure CNI' })): $($short -join '; ')." } else { 'The subnets have room for every pool at its maximum, with upgrade surge.' }) $(if ($flatCni) { 'Move to Azure CNI Overlay (pods don''t use subnet IPs), use a pod subnet, or a larger subnet.' } else { 'Use a larger subnet, or lower the pools'' maximum.' }) "$docs/aks/azure-cni-overlay" }

        # --- Settings (the current-settings lens) -----------------------------------------------------------------------
        $setting = { param([string] $Area, [string] $Label, $Value) $settings.Add((& $object 'AAC.AksSetting' ([ordered]@{ Cluster = $name; Area = $Area; Setting = $Label; Value = $(if ($null -eq $Value -or "$Value" -eq '') { '-' } else { [string]$Value }); ClusterId = $id }))) }
        & $setting 'General' 'Kubernetes version' "$version ($support)"
        & $setting 'General' 'Pricing tier' $(if ($tier) { $tier } else { 'Free' })
        & $setting 'General' 'Support plan' $supportPlan
        & $setting 'General' 'Power state' (& $at $p 'powerState.code')
        & $setting 'General' 'Provisioning state' (& $at $p 'provisioningState')
        & $setting 'General' 'Location' $location
        & $setting 'General' 'Node resource group' (& $at $p 'nodeResourceGroup')
        & $setting 'General' 'API server FQDN' $(if (& $at $p 'fqdn') { & $at $p 'fqdn' } else { & $at $p 'privateFQDN' })
        & $setting 'General' 'Node pools / nodes' "$($agentPools.Count) / $(& $sumOf @($agentPools | ForEach-Object { & $at $_ 'count' }))"
        & $setting 'Upgrades' 'Upgrade channel' $(if ($autoUpgrade) { $autoUpgrade } else { 'none' })
        & $setting 'Upgrades' 'Node OS upgrade channel' $nodeOsUpgrade
        & $setting 'Upgrades' 'Available upgrades' ($available -join ', ')
        & $setting 'Upgrades' 'Maintenance windows' (@($maintenanceRows | ForEach-Object { & $at $_ 'name' }) -join ', ')
        & $setting 'Identity and access' 'Cluster identity' $(if (& $at $c 'identity.type') { & $at $c 'identity.type' } else { 'Service principal' })
        & $setting 'Identity and access' 'Kubelet identity' (& $leaf (& $at $p 'identityProfile.kubeletidentity.resourceId'))
        & $setting 'Identity and access' 'Entra ID' $(if ($aad) { "Yes$(if (& $at $aad 'managed') { ' (managed)' })" } else { 'No' })
        & $setting 'Identity and access' 'Azure RBAC' (& $yesNo (& $at $aad 'enableAzureRBAC'))
        & $setting 'Identity and access' 'Admin groups' (@(& $list (& $at $aad 'adminGroupObjectIDs')).Count)
        & $setting 'Identity and access' 'Local accounts' $(if ($localAccounts) { 'Enabled' } else { 'Disabled' })
        & $setting 'Identity and access' 'OIDC issuer' (& $yesNo (& $at $p 'oidcIssuerProfile.enabled'))
        & $setting 'Identity and access' 'Workload identity' (& $yesNo (& $at $security 'workloadIdentity.enabled'))
        & $setting 'Networking' 'Network plugin' "$plugin$(if ($pluginMode) { " ($pluginMode)" })"
        & $setting 'Networking' 'Dataplane' $dataplane
        & $setting 'Networking' 'Network policy' $networkPolicy
        & $setting 'Networking' 'Outbound type' (& $at $network 'outboundType')
        & $setting 'Networking' 'Load balancer SKU' (& $at $network 'loadBalancerSku')
        & $setting 'Networking' 'Pod CIDR' (& $at $network 'podCidr')
        & $setting 'Networking' 'Service CIDR' (& $at $network 'serviceCidr')
        & $setting 'Networking' 'DNS service IP' (& $at $network 'dnsServiceIP')
        & $setting 'Networking' 'Private cluster' (& $yesNo $private)
        & $setting 'Networking' 'Private DNS zone' (& $leaf (& $at $api 'privateDNSZone'))
        & $setting 'Networking' 'Authorized IP ranges' ($authorized -join ', ')
        & $setting 'Networking' 'API server VNet integration' (& $yesNo (& $at $api 'enableVnetIntegration'))
        & $setting 'Networking' 'Run command' $(if (& $isTrue (& $at $api 'disableRunCommand')) { 'Disabled' } else { 'Enabled' })
        & $setting 'Security' 'Defender sensor' (& $yesNo (& $at $security 'defender.securityMonitoring.enabled'))
        & $setting 'Security' 'Azure Policy add-on' (& $yesNo (& $addonOn 'azurepolicy'))
        & $setting 'Security' 'KMS etcd encryption' (& $yesNo (& $at $security 'azureKeyVaultKms.enabled'))
        & $setting 'Security' 'Image cleaner' (& $yesNo (& $at $security 'imageCleaner.enabled'))
        & $setting 'Security' 'Key Vault secrets provider' "$(& $yesNo (& $at $secretsProvider 'enabled'))$(if (& $isTrue (& $at $secretsProvider 'enabled')) { ", rotation $(if ((& $at $secretsProvider 'config.enableSecretRotation') -eq 'true') { 'on' } else { 'off' })" })"
        & $setting 'Security' 'Node resource group restriction' (& $at $p 'nodeResourceGroupProfile.restrictionLevel')
        & $setting 'Security' 'Pod-managed identity (deprecated)' (& $yesNo $podIdentity)
        & $setting 'Monitoring' 'Container insights' (& $yesNo (& $addonOn 'omsagent', 'omsAgent'))
        & $setting 'Monitoring' 'Log Analytics workspace' (& $leaf (& $at (& $addon 'omsagent', 'omsAgent') 'config.logAnalyticsWorkspaceResourceID'))
        & $setting 'Monitoring' 'Managed Prometheus' (& $yesNo (& $at $p 'azureMonitorProfile.metrics.enabled'))
        & $setting 'Monitoring' 'Cost analysis' (& $yesNo (& $at $p 'metricsProfile.costAnalysis.enabled'))
        & $setting 'Monitoring' 'Diagnostic settings' "$($diagnosticRows.Count)$(if ($categories) { ": $($categories -join ', ')" })"
        if ($addons -is [System.Collections.IDictionary]) { foreach ($k in $addons.Keys | Sort-Object) { & $setting 'Add-ons' $k $(if (& $isTrue (& $at $addons[$k] 'enabled')) { 'Enabled' } else { 'Disabled' }) } }
        & $setting 'Add-ons' 'Application routing (managed NGINX)' (& $yesNo (& $at $p 'ingressProfile.webAppRouting.enabled'))
        & $setting 'Add-ons' 'KEDA' (& $yesNo (& $at $p 'workloadAutoScalerProfile.keda.enabled'))
        & $setting 'Add-ons' 'Vertical pod autoscaler' (& $yesNo (& $at $p 'workloadAutoScalerProfile.verticalPodAutoscaler.enabled'))
        & $setting 'Add-ons' 'Service mesh' (& $at $p 'serviceMeshProfile.mode')
        & $setting 'Add-ons' 'CSI drivers' (@(foreach ($driver in 'diskCSIDriver', 'fileCSIDriver', 'blobCSIDriver', 'snapshotController') { if (& $isTrue (& $at $p "storageProfile.$driver.enabled")) { $driver -replace 'CSIDriver|Controller', '' } }) -join ', ')
        $scaler = & $at $p 'autoScalerProfile'
        if ($scaler -is [System.Collections.IDictionary]) { foreach ($k in 'expander', 'scan-interval', 'scale-down-unneeded-time', 'scale-down-utilization-threshold', 'max-graceful-termination-sec', 'balance-similar-node-groups') { if ($scaler.Contains($k)) { & $setting 'Autoscaler' $k $scaler[$k] } } }

        foreach ($d in $diagnosticRows) {
            $diagnostics.Add((& $object 'AAC.AksDiagnostic' ([ordered]@{
                            Cluster = $name; Setting = [string](& $at $d 'name'); Workspace = & $leaf (& $at $d 'properties.workspaceId'); Storage = & $leaf (& $at $d 'properties.storageAccountId')
                            EventHub = [string](& $at $d 'properties.eventHubName'); Destination = [string](& $at $d 'properties.logAnalyticsDestinationType')
                            Logs = (@(foreach ($log in @(& $list (& $at $d 'properties.logs'))) { if (& $isTrue (& $at $log 'enabled')) { [string]$(if (& $at $log 'category') { & $at $log 'category' } else { & $at $log 'categoryGroup' }) } }) -join ', ')
                            ClusterId = $id
                        })))
        }
        foreach ($m in $maintenanceRows) {
            $schedule = & $at $m 'properties.maintenanceWindow'
            $maintenance.Add((& $object 'AAC.AksMaintenance' ([ordered]@{
                            Cluster = $name; Configuration = [string](& $at $m 'name')
                            Schedule = $(if ($schedule) { ConvertTo-Json -InputObject (& $at $schedule 'schedule') -Compress -Depth 5 } else { ConvertTo-Json -InputObject @(& $list (& $at $m 'properties.timeInWeek')) -Compress -Depth 5 })
                            Duration = $(if ($schedule) { "$(& $at $schedule 'durationHours') h" } else { '' }); Start = [string](& $at $schedule 'startTime'); TimeZone = [string](& $at $schedule 'utcOffset')
                            ClusterId = $id
                        })))
        }

        # --- The other lenses' findings for this cluster ----------------------------------------------------------------
        $add = {
            param([string] $Severity, [string] $Pillar, [string] $Source, [string] $Check, [string] $Item, [string] $Detail, [string] $Action, [string] $Link)
            $findings.Add((& $object 'AAC.AksFinding' ([ordered]@{ Severity = $Severity; Pillar = $Pillar; Source = $Source; Check = $Check; Cluster = $name; Item = $Item; Detail = $Detail; Recommendation = $Action; Link = $Link; Subscription = $subscription; ResourceGroup = $group; ClusterId = $id })))
        }
        foreach ($row in $clusterChecks | Where-Object Status -EQ 'Fail') { & $add $row.Severity $row.Pillar 'Well-Architected' $row.Check $row.Item $row.Detail $row.Recommendation $row.Link }
        $psruleHere = @($PSRule | Where-Object { ([string]$_.ResourceId).ToLowerInvariant() -eq $key -or ($_.ResourceName -eq $name -and $_.ResourceGroup -eq $group) })
        foreach ($row in $psruleHere | Where-Object Outcome -NE 'Pass') {
            $severity = switch -Wildcard ([string]$row.Severity) { 'Critical*' { 'High' } 'Important*' { 'Medium' } 'Awareness*' { 'Low' } default { 'Medium' } }
            & $add $severity ([string]$row.Pillar) 'PSRule' ([string]$row.RuleName) '' "$($row.Title)$(if ($row.Reason) { " $($row.Reason)" })" ([string]$row.Recommendation) ([string]$row.Link)
        }
        $pillarOf = @{ HighAvailability = 'Reliability'; Security = 'Security'; Cost = 'Cost Optimization'; OperationalExcellence = 'Operational Excellence'; Performance = 'Performance Efficiency' }
        foreach ($row in @($Advisor | Where-Object { [string](& $at $_ 'resourceId') -eq $key })) {
            $retiring = [string](& $at $row 'subCategory') -eq 'ServiceUpgradeAndRetirement'
            & $add $(if ($retiring -or [string](& $at $row 'impact') -eq 'High') { 'High' } elseif ([string](& $at $row 'impact') -eq 'Medium') { 'Medium' } else { 'Low' }) $(if ($pillarOf.Contains([string](& $at $row 'category'))) { $pillarOf[[string](& $at $row 'category')] } else { [string](& $at $row 'category') }) $(if ($retiring) { 'Retirement' } else { 'Advisor' }) ([string](& $at $row 'problem')) '' "$(& $at $row 'problem')$(if (& $at $row 'retirementDate') { " (by $(& $at $row 'retirementDate'))" })" ([string](& $at $row 'solution')) ([string](& $at $row 'learnMore'))
        }
        foreach ($row in @($Defender | Where-Object { [string](& $at $_ 'resourceId') -eq $key })) {
            & $add $(if ([string](& $at $row 'severity') -in 'High', 'Medium', 'Low') { [string](& $at $row 'severity') } else { 'Medium' }) 'Security' 'Defender' ([string](& $at $row 'recommendation')) '' "$(& $at $row 'recommendation')$(if (& $at $row 'cause') { " ($(& $at $row 'cause'))" })" ([string](& $at $row 'remediation')) ([string](& $at $row 'link'))
        }
        if ($Policy) {
            foreach ($row in @($Policy.ClusterStates | Where-Object { $_.ClusterId -eq $key -and $_.State -eq 'NonCompliant' -and $_.Scope -eq 'Cluster' })) {
                & $add 'Medium' 'Security' 'Azure Policy' $row.Policy $row.Assignment "Non-compliant with '$($row.Policy)' ($($row.Effect))." 'Bring the cluster''s configuration in line with the policy, or exempt it on purpose.' ''
            }
            foreach ($row in @($Policy.ByCluster | Where-Object { $_.ClusterId -eq $key })) {
                & $add $(if ($row.Effect -match 'deny') { 'High' } else { 'Medium' }) 'Security' 'Azure Policy' $row.Policy "$($row.Namespaces) namespace(s)" "$($row.Violations)$(if ($row.Capped) { '+ (Azure Policy''s 500-record cap: the in-cluster count is complete)' }) non-compliant component(s) in $($row.Workloads) workload(s) ($($row.Effect))." 'Fix the workloads before the policy moves from Audit to Deny (the by-namespace and by-workload views say whose they are).' ''
            }
        }
        $gatekeeper = $Constraint[$key]
        if ($gatekeeper) {
            foreach ($row in @($gatekeeper.Totals)) {
                $constraints.Add((& $object 'AAC.AksConstraint' ([ordered]@{ Cluster = $name; Kind = $row.Kind; Constraint = $row.Name; Action = $row.Action; TotalViolations = $row.TotalViolations; Assignment = $row.Assignment; ReferenceId = $row.ReferenceId; ClusterId = $id })))
            }
        }

        # --- The cluster's summary --------------------------------------------------------------------------------
        $mine = @($findings | Where-Object { $_.ClusterId -eq $id })
        $score = [ordered]@{}
        foreach ($pillar in $pillars) {
            $inPillar = @($clusterChecks | Where-Object Pillar -EQ $pillar)
            $score[$pillar] = if ($inPillar.Count) { [Math]::Round(@($inPillar | Where-Object Status -EQ 'Pass').Count / $inPillar.Count * 100) } else { $null }
        }
        $clusters.Add((& $object 'AAC.AksCluster' ([ordered]@{
                        Name = $name; ResourceGroup = $group; Subscription = $subscription; Location = $location
                        Version = $version; Support = $support; Upgrade = $(if ($available.Count) { $available[-1] } else { '' }); Tier = $(if ($tier) { $tier } else { 'Free' })
                        PowerState = [string](& $at $p 'powerState.code'); State = [string](& $at $p 'provisioningState')
                        NodePools = $agentPools.Count; Nodes = & $sumOf @($agentPools | ForEach-Object { & $at $_ 'count' })
                        MaxNodes = & $sumOf @($agentPools | ForEach-Object { if (& $isTrue (& $at $_ 'enableAutoScaling')) { & $at $_ 'maxCount' } else { & $at $_ 'count' } })
                        Network = "$plugin$(if ($pluginMode) { " $pluginMode" })$(if ($dataplane) { " / $dataplane" })"; NetworkPolicy = $(if ($networkPolicy) { $networkPolicy } else { 'none' })
                        Outbound = [string](& $at $network 'outboundType'); ApiServer = $(if ($private) { 'Private' } elseif ($authorized.Count) { "Public ($($authorized.Count) range(s))" } else { 'Public (open)' })
                        EntraId = $(if ($aad) { 'Yes' } else { 'No' }); AzureRbac = & $yesNo (& $at $aad 'enableAzureRBAC'); LocalAccounts = $(if ($localAccounts) { 'Enabled' } else { 'Disabled' })
                        AutoUpgrade = $(if ($autoUpgrade) { $autoUpgrade } else { 'none' }); NodeOsUpgrade = $(if ($nodeOsUpgrade) { $nodeOsUpgrade } else { 'not set' })
                        Monitoring = (@($(if (& $addonOn 'omsagent', 'omsAgent') { 'Container insights' }), $(if (& $isTrue (& $at $p 'azureMonitorProfile.metrics.enabled')) { 'Prometheus' }), $(if ($diagnosticRows.Count) { 'Diagnostics' })) | Where-Object { $_ }) -join ', '
                        PolicyAddon = & $yesNo (& $addonOn 'azurepolicy'); Defender = & $yesNo (& $at $security 'defender.securityMonitoring.enabled')
                        PolicyViolations = $(if ($Policy) { @($Policy.Components | Where-Object { $_.ClusterId -eq $key }).Count } else { $null })
                        PSRuleFailed = @($psruleHere | Where-Object Outcome -NE 'Pass').Count; PSRulePassed = @($psruleHere | Where-Object Outcome -EQ 'Pass').Count
                        Reliability = $score['Reliability']; Security = $score['Security']; CostOptimization = $score['Cost Optimization']; OperationalExcellence = $score['Operational Excellence']; PerformanceEfficiency = $score['Performance Efficiency']
                        WafScore = $(if ($clusterChecks.Count) { [Math]::Round(@($clusterChecks | Where-Object Status -EQ 'Pass').Count / $clusterChecks.Count * 100) } else { $null })
                        High = @($mine | Where-Object Severity -EQ 'High').Count; Medium = @($mine | Where-Object Severity -EQ 'Medium').Count; Low = @($mine | Where-Object Severity -EQ 'Low').Count
                        PoolUpgrades = $poolUpgradeAvailable; ResourceId = $id
                    })))
    }

    # --- Totals ------------------------------------------------------------------------------------------------------
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Cluster, Pillar, Check)
    $pillarRows = @(foreach ($pillar in $pillars) {
            $inPillar = @($checks | Where-Object Pillar -EQ $pillar)
            & $object 'AAC.AksPillar' ([ordered]@{
                    Pillar = $pillar; Checks = $inPillar.Count; Passed = @($inPillar | Where-Object Status -EQ 'Pass').Count; Failed = @($inPillar | Where-Object Status -EQ 'Fail').Count
                    Score = $(if ($inPillar.Count) { [Math]::Round(@($inPillar | Where-Object Status -EQ 'Pass').Count / $inPillar.Count * 100) } else { $null })
                    PSRuleFailed = @($PSRule | Where-Object { $_.Pillar -eq $pillar -and $_.Outcome -ne 'Pass' }).Count
                    Findings = @($sorted | Where-Object Pillar -EQ $pillar).Count
                })
        })
    @{
        Clusters    = @($clusters | Sort-Object -Property @{ Expression = 'High'; Descending = $true }, @{ Expression = 'Medium'; Descending = $true }, Name)
        NodePools   = $pools.ToArray()
        Settings    = $settings.ToArray()
        Upgrades    = $upgrades.ToArray()
        Checks      = $checks.ToArray()
        Findings    = $sorted
        Diagnostics = $diagnostics.ToArray()
        Maintenance = $maintenance.ToArray()
        Constraints = @($constraints | Sort-Object -Property @{ Expression = 'TotalViolations'; Descending = $true })
        PSRule      = @($PSRule)
        Policy      = $Policy
        Pillars     = $pillarRows
        Stats       = [ordered]@{
            Clusters        = $clusters.Count
            NodePools       = $pools.Count
            Nodes           = & $sumOf @($pools | ForEach-Object Nodes)
            OutOfSupport    = @($clusters | Where-Object { $_.Support -like 'Out of support*' }).Count
            Upgradable      = @($clusters | Where-Object Upgrade).Count
            High            = @($sorted | Where-Object Severity -EQ 'High').Count
            Medium          = @($sorted | Where-Object Severity -EQ 'Medium').Count
            Low             = @($sorted | Where-Object Severity -EQ 'Low').Count
            WafScore        = $(if ($checks.Count) { [Math]::Round(@($checks | Where-Object Status -EQ 'Pass').Count / $checks.Count * 100) } else { $null })
            PSRuleFailed    = @($PSRule | Where-Object Outcome -NE 'Pass').Count
            PSRulePassed    = @($PSRule | Where-Object Outcome -EQ 'Pass').Count
            PolicyViolations = $(if ($Policy) { $Policy.Stats.Violations } else { $null })
            GatekeeperViolations = & $sumOf @($constraints | ForEach-Object TotalViolations)
        }
    }
}
