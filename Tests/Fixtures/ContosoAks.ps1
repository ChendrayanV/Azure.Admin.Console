<#
    Made-up Contoso AKS clusters for the Invoke-AACAksAssessment tests, in the
    shapes Azure returns them:

      aks-prod-weu  Standard tier, Kubernetes 1.30.5 (supported, 1.31.2 available), three zones,
                    a 3-node system pool and an autoscaling user pool, Entra ID with Azure RBAC,
                    local accounts off, private, Azure CNI Overlay with Cilium, Azure Policy,
                    Defender, workload identity, Container insights, Prometheus, kube-audit-admin
                    to Log Analytics, maintenance windows, stable / NodeImage channels, ephemeral
                    OS disks, recent node images - and pods violating Kubernetes policies:
                      payments  api (a Deployment: 2 pods), nightly (a CronJob), ledger (a StatefulSet)
                      kube-system  coredns (left out unless -IncludeSystemNamespace)
      aks-dev       Free tier, Kubernetes 1.27.9 (out of support), no zones, one 1-node system
                    pool, local accounts on, no Entra ID, public API server open to all, flat
                    Azure CNI in a /27 that can't hold the pool at full scale, no network policy,
                    no Azure Policy, no Defender, node public IPs, HTTP application routing,
                    pod identity, an old node image, no diagnostic settings - and Advisor,
                    Defender and a non-compliant cluster policy

    Returns @{ Clusters (Export-AzRuleData shapes); Rows (Resource Graph query -> rows);
    UpgradeProfiles; PoolUpgrades; Versions; Subnets; DefinitionNames; PSRule; Constraint }.
#>
function Get-AACContosoAks {
    $sub = '44444444-4444-4444-4444-444444444444'
    $prodId = "/subscriptions/$sub/resourceGroups/rg-aks/providers/Microsoft.ContainerService/managedClusters/aks-prod-weu"
    $devId = "/subscriptions/$sub/resourceGroups/rg-aks-dev/providers/Microsoft.ContainerService/managedClusters/aks-dev"
    $devSubnet = "/subscriptions/$sub/resourceGroups/rg-aks-dev/providers/Microsoft.Network/virtualNetworks/vnet-aks-dev/subnets/snet-nodes"
    $prodSubnet = "/subscriptions/$sub/resourceGroups/rg-aks/providers/Microsoft.Network/virtualNetworks/vnet-aks/subnets/snet-nodes"
    $workspace = "/subscriptions/$sub/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-aks"
    $pool = {
        param([string] $Name, [string] $Mode, [hashtable] $More = @{})
        $p = @{ name = $Name; mode = $Mode; vmSize = 'Standard_D4ds_v5'; osType = 'Linux'; osSKU = 'AzureLinux'; count = 3; maxPods = 110; currentOrchestratorVersion = '1.30.5'; nodeImageVersion = 'AKSAzureLinux-V2gen2-202609.20.0'; osDiskType = 'Ephemeral'; osDiskSizeGB = 128; availabilityZones = @('1', '2', '3'); enableEncryptionAtHost = $true; upgradeSettings = @{ maxSurge = '33%' }; powerState = @{ code = 'Running' }; provisioningState = 'Succeeded'; vnetSubnetID = $prodSubnet }
        foreach ($k in $More.Keys) { $p[$k] = $More[$k] }
        $p
    }
    $prod = @{
        id = $prodId; name = 'aks-prod-weu'; type = 'Microsoft.ContainerService/managedClusters'; location = 'westeurope'; subscriptionId = $sub; resourceGroupName = 'rg-aks'
        sku = @{ name = 'Base'; tier = 'Standard' }; identity = @{ type = 'SystemAssigned' }; tags = @{ env = 'prod' }
        properties = @{
            kubernetesVersion = '1.30'; currentKubernetesVersion = '1.30.5'; provisioningState = 'Succeeded'; powerState = @{ code = 'Running' }; supportPlan = 'KubernetesOfficial'
            nodeResourceGroup = 'MC_rg-aks_aks-prod-weu_westeurope'; privateFQDN = 'aks-prod-weu-abc.privatelink.westeurope.azmk8s.io'; disableLocalAccounts = $true
            aadProfile = @{ managed = $true; enableAzureRBAC = $true; adminGroupObjectIDs = @('g1') }
            apiServerAccessProfile = @{ enablePrivateCluster = $true; privateDNSZone = 'system' }
            networkProfile = @{ networkPlugin = 'azure'; networkPluginMode = 'overlay'; networkDataplane = 'cilium'; networkPolicy = 'cilium'; outboundType = 'userDefinedRouting'; loadBalancerSku = 'standard'; podCidr = '10.244.0.0/16'; serviceCidr = '10.0.0.0/16'; dnsServiceIP = '10.0.0.10' }
            addonProfiles = @{ azurepolicy = @{ enabled = $true }; omsagent = @{ enabled = $true; config = @{ logAnalyticsWorkspaceResourceID = $workspace } }; azureKeyvaultSecretsProvider = @{ enabled = $true; config = @{ enableSecretRotation = 'true' } } }
            securityProfile = @{ defender = @{ securityMonitoring = @{ enabled = $true } }; workloadIdentity = @{ enabled = $true }; imageCleaner = @{ enabled = $true; intervalHours = 168 }; azureKeyVaultKms = @{ enabled = $true } }
            oidcIssuerProfile = @{ enabled = $true }; azureMonitorProfile = @{ metrics = @{ enabled = $true } }; metricsProfile = @{ costAnalysis = @{ enabled = $true } }
            autoUpgradeProfile = @{ upgradeChannel = 'stable'; nodeOSUpgradeChannel = 'NodeImage' }; nodeResourceGroupProfile = @{ restrictionLevel = 'ReadOnly' }
            autoScalerProfile = @{ expander = 'least-waste'; 'scan-interval' = '10s' }
            agentPoolProfiles = @(
                & $pool 'system' 'System' @{ nodeTaints = @('CriticalAddonsOnly=true:NoSchedule') }
                & $pool 'apps' 'User' @{ count = 4; enableAutoScaling = $true; minCount = 2; maxCount = 10 }
            )
        }
        resources = @(
            @{ type = 'Microsoft.Insights/diagnosticSettings'; name = 'to-law'; properties = @{ workspaceId = $workspace; logAnalyticsDestinationType = 'Dedicated'; logs = @(@{ category = 'kube-audit-admin'; enabled = $true }, @{ category = 'kube-apiserver'; enabled = $true }, @{ category = 'guard'; enabled = $false }) } }
            @{ type = 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations'; name = 'aksManagedAutoUpgradeSchedule'; properties = @{ maintenanceWindow = @{ schedule = @{ weekly = @{ dayOfWeek = 'Sunday'; intervalWeeks = 1 } }; durationHours = 4; startTime = '01:00'; utcOffset = '+00:00' } } }
        )
    }
    $dev = @{
        id = $devId; name = 'aks-dev'; type = 'Microsoft.ContainerService/managedClusters'; location = 'westeurope'; subscriptionId = $sub; resourceGroupName = 'rg-aks-dev'
        sku = @{ name = 'Base'; tier = 'Free' }; identity = @{ type = 'SystemAssigned' }; tags = $null
        properties = @{
            kubernetesVersion = '1.27'; currentKubernetesVersion = '1.27.9'; provisioningState = 'Succeeded'; powerState = @{ code = 'Running' }; fqdn = 'aks-dev-xyz.hcp.westeurope.azmk8s.io'
            disableLocalAccounts = $false; podIdentityProfile = @{ enabled = $true }
            networkProfile = @{ networkPlugin = 'azure'; outboundType = 'loadBalancer'; loadBalancerSku = 'standard'; serviceCidr = '10.0.0.0/16'; dnsServiceIP = '10.0.0.10' }
            addonProfiles = @{ httpApplicationRouting = @{ enabled = $true } }
            agentPoolProfiles = @(& $pool 'nodepool1' 'System' @{ count = 1; vmSize = 'Standard_B2s'; osSKU = 'Ubuntu'; currentOrchestratorVersion = '1.27.9'; nodeImageVersion = 'AKSUbuntu-2204gen2containerd-202501.10.0'; osDiskType = 'Managed'; availabilityZones = @(); enableEncryptionAtHost = $false; enableNodePublicIP = $true; upgradeSettings = @{}; enableAutoScaling = $true; minCount = 1; maxCount = 5; maxPods = 30; vnetSubnetID = $devSubnet })
        }
        resources = @(@{ type = 'Microsoft.Network/virtualNetworks/subnets'; id = $devSubnet; name = 'snet-nodes'; properties = @{ addressPrefix = '10.20.0.0/27' } })
    }
    $policy = '/providers/microsoft.authorization/policydefinitions'
    $readOnlyRoot = "$policy/df49d893-a74c-421d-bc95-c663042e5b80"
    $limits = "$policy/e345eecc-fa47-480f-9e88-67dcc122b164"
    $localAuth = "$policy/993c2fcd-2b29-49d2-9eb0-df2c3a730c32"
    $baseline = '/providers/microsoft.authorization/policysetdefinitions/a8640138-9b0a-4a28-b8cb-1666c838647d'
    $denyAssignment = '/providers/microsoft.management/managementgroups/contoso/providers/microsoft.authorization/policyassignments/aks-baseline'
    $auditAssignment = "/subscriptions/$sub/providers/microsoft.authorization/policyassignments/aks-limits"
    $component = { param([string] $Cluster, [string] $Definition, [string] $Assignment, [string] $Type, [string] $ComponentId, [string] $SetId = '') @{ id = [guid]::NewGuid().ToString(); clusterId = $Cluster.ToLowerInvariant(); assignmentId = $Assignment; definitionId = $Definition; setId = $SetId; refId = ''; componentType = $Type; componentId = $ComponentId; evaluated = '2026-10-04T06:00:00Z' } }
    @{
        SubscriptionId = $sub; ProdId = $prodId; DevId = $devId
        Clusters = @($prod, $dev)
        Rows = @{
            clusters = @(foreach ($c in $prod, $dev) { @{ id = $c.id; name = $c.name; resourceGroup = $c.resourceGroupName; subscriptionId = $sub; location = $c.location; sku = $c.sku; identity = $c.identity; tags = $c.tags; properties = $c.properties } })
            subscriptions = @(@{ id = "/subscriptions/$sub"; subscriptionId = $sub; name = 'sub-aks' })
            components = @(
                & $component $prodId $readOnlyRoot $denyAssignment 'pod' 'payments/api-7d9f8b6c5d-x2kfz' $baseline
                & $component $prodId $readOnlyRoot $denyAssignment 'pod' 'payments/api-7d9f8b6c5d-q8mnp' $baseline
                & $component $prodId $limits $auditAssignment 'pod' 'payments/nightly-28812345-bcdfg'
                & $component $prodId $limits $auditAssignment 'pod' 'payments/ledger-0'
                & $component $prodId $limits $auditAssignment 'pod' 'kube-system/coredns-5d78c9869d-bcdfg'
            )
            clusterStates = @(
                @{ id = 's1'; clusterId = $prodId.ToLowerInvariant(); assignmentId = $denyAssignment; definitionId = $readOnlyRoot; setId = $baseline; refId = ''; effect = 'deny'; state = 'NonCompliant'; evaluated = '2026-10-04T06:00:00Z' }
                @{ id = 's2'; clusterId = $prodId.ToLowerInvariant(); assignmentId = $auditAssignment; definitionId = $limits; setId = ''; refId = ''; effect = 'audit'; state = 'NonCompliant'; evaluated = '2026-10-04T06:00:00Z' }
                @{ id = 's3'; clusterId = $devId.ToLowerInvariant(); assignmentId = $auditAssignment; definitionId = $localAuth; setId = ''; refId = ''; effect = 'audit'; state = 'NonCompliant'; evaluated = '2026-10-04T06:00:00Z' }
                @{ id = 's4'; clusterId = $prodId.ToLowerInvariant(); assignmentId = $auditAssignment; definitionId = $localAuth; setId = ''; refId = ''; effect = 'audit'; state = 'Compliant'; evaluated = '2026-10-04T06:00:00Z' }
            )
            assignments = @(
                @{ id = 'a1'; assignmentId = $denyAssignment; name = 'aks-baseline'; displayName = 'AKS pod security baseline'; scope = '/providers/Microsoft.Management/managementGroups/contoso'; enforcementMode = 'Default'; effect = 'deny'; definitionId = $baseline }
                @{ id = 'a2'; assignmentId = $auditAssignment; name = 'aks-limits'; displayName = 'AKS resource limits'; scope = "/subscriptions/$sub"; enforcementMode = 'DoNotEnforce'; effect = 'audit'; definitionId = $limits }
            )
            advisor = @(@{ id = 'ad1'; resourceId = $devId.ToLowerInvariant(); category = 'HighAvailability'; impact = 'High'; problem = 'Enable availability zones for AKS'; solution = 'Use zones'; subCategory = ''; retirementDate = ''; learnMore = 'https://learn.microsoft.com/azure/aks/availability-zones' })
            defender = @(@{ id = 'd1'; resourceId = $devId.ToLowerInvariant(); recommendation = 'Kubernetes clusters should be accessible only over HTTPS'; severity = 'High'; categories = 'Compute'; remediation = 'Use HTTPS ingress.'; cause = ''; link = '' })
        }
        UpgradeProfiles = @{
            $prodId.ToLowerInvariant() = @{ properties = @{ controlPlaneProfile = @{ kubernetesVersion = '1.30.5'; upgrades = @(@{ kubernetesVersion = '1.31.2' }, @{ kubernetesVersion = '1.32.0'; isPreview = $true }) } } }
            $devId.ToLowerInvariant()  = @{ properties = @{ controlPlaneProfile = @{ kubernetesVersion = '1.27.9'; upgrades = @(@{ kubernetesVersion = '1.28.15' }) } } }
        }
        PoolUpgrades = @{
            "$($prodId.ToLowerInvariant())/system" = @{ properties = @{ latestNodeImageVersion = 'AKSAzureLinux-V2gen2-202609.20.0' } }
            "$($devId.ToLowerInvariant())/nodepool1" = @{ properties = @{ latestNodeImageVersion = 'AKSUbuntu-2204gen2containerd-202609.22.0' } }
        }
        Versions = @{ westeurope = @(
                @{ version = '1.29'; capabilities = @{ supportPlan = @('KubernetesOfficial', 'AKSLongTermSupport') }; patchVersions = @{ '1.29.9' = @{}; '1.29.10' = @{} } }
                @{ version = '1.30'; capabilities = @{ supportPlan = @('KubernetesOfficial', 'AKSLongTermSupport') }; patchVersions = @{ '1.30.5' = @{}; '1.30.6' = @{} } }
                @{ version = '1.31'; isDefault = $true; capabilities = @{ supportPlan = @('KubernetesOfficial', 'AKSLongTermSupport') }; patchVersions = @{ '1.31.2' = @{} } }
                @{ version = '1.32'; isPreview = $true; capabilities = @{ supportPlan = @('KubernetesOfficial') }; patchVersions = @{ '1.32.0' = @{} } }
                @{ version = '1.27'; capabilities = @{ supportPlan = @('AKSLongTermSupport') }; patchVersions = @{ '1.27.100' = @{} } }
            )
        }
        Subnets = @{ $prodSubnet.ToLowerInvariant() = @{ id = $prodSubnet; properties = @{ addressPrefix = '10.10.0.0/24' } } }
        DefinitionNames = @{ $readOnlyRoot = 'Kubernetes cluster containers should run with a read only root file system'; $limits = 'Kubernetes cluster containers CPU and memory resource limits should not exceed the specified limits'; $localAuth = 'Azure Kubernetes Service Clusters should have local authentication methods disabled'; $baseline = 'Kubernetes cluster pod security baseline standards for Linux-based workloads' }
        PSRule = @(
            [pscustomobject]@{ PSTypeName = 'AAC.PSRuleResult'; Outcome = 'Pass'; Pillar = 'Reliability'; RuleName = 'Azure.AKS.AvailabilityZone'; Title = 'Use zones'; Severity = 'Important'; ResourceName = 'aks-prod-weu'; ResourceType = 'microsoft.containerservice/managedclusters'; ResourceGroup = 'rg-aks'; Reason = ''; Recommendation = 'Use zones.'; Link = 'https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.AKS.AvailabilityZone/'; ResourceId = $prodId }
            [pscustomobject]@{ PSTypeName = 'AAC.PSRuleResult'; Outcome = 'Fail'; Pillar = 'Security'; RuleName = 'Azure.AKS.LocalAccounts'; Title = 'Disable local accounts'; Severity = 'Critical'; ResourceName = 'aks-dev'; ResourceType = 'microsoft.containerservice/managedclusters'; ResourceGroup = 'rg-aks-dev'; Reason = 'disableLocalAccounts is false.'; Recommendation = 'Disable local accounts.'; Link = 'https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.AKS.LocalAccounts/'; ResourceId = $devId }
            [pscustomobject]@{ PSTypeName = 'AAC.PSRuleResult'; Outcome = 'Fail'; Pillar = 'Operational Excellence'; RuleName = 'Azure.AKS.AuditLogs'; Title = 'Enable audit logs'; Severity = 'Important'; ResourceName = 'aks-dev'; ResourceType = 'microsoft.containerservice/managedclusters'; ResourceGroup = 'rg-aks-dev'; Reason = 'No diagnostic setting.'; Recommendation = 'Send kube-audit logs.'; Link = ''; ResourceId = $devId }
        )
        Constraint = @{ Totals = @([pscustomobject]@{ Kind = 'K8sAzureV1ReadOnlyRootFilesystem'; Name = 'azurepolicy-readonly-1'; Action = 'deny'; TotalViolations = 612; Assignment = 'aks-baseline'; ReferenceId = 'readOnlyRoot' }); Violations = @([pscustomobject]@{ Constraint = 'K8sAzureV1ReadOnlyRootFilesystem'; Namespace = 'payments'; Object = 'Pod/api-7d9f8b6c5d-x2kfz'; Message = 'only read-only root filesystem container is allowed' }); Status = 'OK' }
    }
}
