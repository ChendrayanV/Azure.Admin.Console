<#
    A made-up Contoso tenant for EffectivePolicy.Tests.ps1 - the rows Azure
    Resource Graph, Resource Manager and Policy Insights return
    (hashtables) - with a policy of every kind the effective view tells
    apart:

      tenant-root > mg-landingzones > sub-corp-apps
        rg-data   stordersdata  (storage, uksouth)
        rg-app    kv-app        (key vault, westeurope)
                  aks-orders    (AKS, uksouth)

      Allowed locations (mg-landingzones, deny uksouth/ukwest)
                         kv-app non-compliant: in westeurope
      Contoso baseline   (tenant-root initiative, no managed identity)
        storageTls       storage TLS, deny - stordersdata exempt (a
                         waiver ending in 10 days)
        kvDiag           key vault diagnostics, deployIfNotExists -
                         kv-app non-compliant
        aksPods          a Kubernetes data-plane audit - aks-orders
        vmOs             VMs only, overridden to Disabled
      Require CostCenter (sub, deny, DoNotEnforce) - an expired
                         exemption on rg-app
      Storage TLS audit  (sub, notScopes rg-data)
      EU vault RBAC      (sub, resource selector: westeurope only)
#>
function Get-AACContosoEffectivePolicy {
    $corp = '22222222-2222-2222-2222-222222222222'
    $mg = '/providers/Microsoft.Management/managementGroups'
    $assignment = { param([string] $Scope, [string] $Name) "$Scope/providers/Microsoft.Authorization/policyAssignments/$Name" }
    $builtin = { param([string] $Name) "/providers/Microsoft.Authorization/policyDefinitions/$Name" }
    $custom = { param([string] $Name) "$mg/tenant-root/providers/Microsoft.Authorization/policyDefinitions/$Name" }
    $set = "$mg/tenant-root/providers/Microsoft.Authorization/policySetDefinitions/contoso-baseline"
    $ids = @{
        Storage    = "/subscriptions/$corp/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stordersdata"
        Vault      = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv-app"
        Aks        = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.ContainerService/managedClusters/aks-orders"
        Locations  = (& $assignment "$mg/mg-landingzones" 'allowed-locations')
        Baseline   = (& $assignment "$mg/tenant-root" 'baseline')
        CostCenter = (& $assignment "/subscriptions/$corp" 'require-costcenter')
        TlsAudit   = (& $assignment "/subscriptions/$corp" 'tls-audit')
        EuOnly     = (& $assignment "/subscriptions/$corp" 'eu-only')
    }
    $now = [datetime]::UtcNow
    $tlsRule = @{ if = @{ allOf = @(@{ field = 'type'; equals = 'Microsoft.Storage/storageAccounts' }, @{ field = 'Microsoft.Storage/storageAccounts/minimumTlsVersion'; notEquals = "[parameters('minimumTlsVersion')]" }) }; then = @{ effect = "[parameters('effect')]" } }
    $tlsParameters = [ordered]@{ minimumTlsVersion = @{ type = 'String'; defaultValue = 'TLS1_2' }; effect = @{ type = 'String'; defaultValue = 'Audit' } }

    @{
        SubscriptionId   = $corp
        Ids              = $ids
        Subscriptions    = @(@{ id = "/subscriptions/$corp"; subscriptionId = $corp; name = 'sub-corp-apps'; chain = @(@{ name = 'mg-landingzones' }, @{ name = 'tenant-root' }) })
        ManagementGroups = @(
            @{ id = "$mg/tenant-root"; name = 'tenant-root'; displayName = 'Tenant Root Group'; chain = @() }
            @{ id = "$mg/mg-landingzones"; name = 'mg-landingzones'; displayName = 'Landing zones'; chain = @(@{ name = 'tenant-root' }) }
        )
        Definitions      = @(
            @{ id = (& $builtin 'allowed-locations'); name = 'allowed-locations'; displayName = 'Allowed locations'; policyType = 'BuiltIn'; category = 'General'; mode = 'Indexed'
                parameters = @{ listOfAllowedLocations = @{ type = 'Array' } }
                rule = @{ if = @{ allOf = @(@{ field = 'location'; notIn = "[parameters('listOfAllowedLocations')]" }, @{ field = 'location'; notEquals = 'global' }, @{ field = 'type'; notEquals = 'Microsoft.AzureActiveDirectory/b2cDirectories' }) }; then = @{ effect = 'deny' } }; members = $null }
            @{ id = (& $custom 'storage-tls'); name = 'storage-tls'; displayName = 'Storage accounts use TLS 1.2'; policyType = 'Custom'; category = 'Storage'; mode = 'Indexed'; parameters = $tlsParameters; rule = $tlsRule; members = $null }
            @{ id = (& $builtin 'kv-diagnostics'); name = 'kv-diagnostics'; displayName = 'Deploy Key Vault diagnostics'; policyType = 'BuiltIn'; category = 'Key Vault'; mode = 'Indexed'; parameters = @{}
                rule = @{ if = @{ field = 'type'; equals = 'Microsoft.KeyVault/vaults' }; then = @{ effect = 'deployIfNotExists'; details = @{ type = 'Microsoft.Insights/diagnosticSettings' } } }; members = $null }
            @{ id = (& $builtin 'aks-privileged'); name = 'aks-privileged'; displayName = 'Kubernetes: no privileged containers'; policyType = 'BuiltIn'; category = 'Kubernetes'; mode = 'Microsoft.Kubernetes.Data'; parameters = @{}
                rule = @{ if = @{ field = 'type'; in = @('Microsoft.ContainerService/managedClusters') }; then = @{ effect = 'audit' } }; members = $null }
            @{ id = (& $builtin 'vm-os'); name = 'vm-os'; displayName = 'VM OS check'; policyType = 'BuiltIn'; category = 'Compute'; mode = 'Indexed'; parameters = @{}
                rule = @{ if = @{ field = 'Microsoft.Compute/virtualMachines/storageProfile.osDisk.osType'; equals = 'Linux' }; then = @{ effect = 'audit' } }; members = $null }
            @{ id = (& $builtin 'require-tag'); name = 'require-tag'; displayName = 'Require a tag on resources'; policyType = 'BuiltIn'; category = 'Tags'; mode = 'Indexed'
                parameters = @{ tagName = @{ type = 'String' } }
                rule = @{ if = @{ field = "[concat('tags[', parameters('tagName'), ']')]"; exists = 'false' }; then = @{ effect = 'deny' } }; members = $null }
            @{ id = (& $custom 'kv-rbac'); name = 'kv-rbac'; displayName = 'Key vaults use RBAC'; policyType = 'Custom'; category = 'Key Vault'; mode = 'Indexed'; parameters = @{}
                rule = @{ if = @{ allOf = @(@{ field = 'type'; equals = 'Microsoft.KeyVault/vaults' }, @{ field = 'Microsoft.KeyVault/vaults/enableRbacAuthorization'; notEquals = $true }) }; then = @{ effect = 'audit' } }; members = $null }
            @{ id = $set; name = 'contoso-baseline'; displayName = 'Contoso baseline'; policyType = 'Custom'; category = 'Security'; mode = ''; rule = $null
                parameters = @{ tlsEffect = @{ type = 'String'; defaultValue = 'Deny' } }
                members = @(
                    @{ policyDefinitionId = (& $custom 'storage-tls'); policyDefinitionReferenceId = 'storageTls'; parameters = @{ minimumTlsVersion = @{ value = 'TLS1_2' }; effect = @{ value = "[parameters('tlsEffect')]" } }; groupNames = @('Azure_Security_Benchmark_v3.0_DP-3') }
                    @{ policyDefinitionId = (& $builtin 'kv-diagnostics'); policyDefinitionReferenceId = 'kvDiag'; parameters = @{}; groupNames = @('Azure_Security_Benchmark_v3.0_LT-3') }
                    @{ policyDefinitionId = (& $builtin 'aks-privileged'); policyDefinitionReferenceId = 'aksPods'; parameters = @{} }
                    @{ policyDefinitionId = (& $builtin 'vm-os'); policyDefinitionReferenceId = 'vmOs'; parameters = @{} }
                ) }
        )
        Assignments      = @(
            @{ id = $ids.Locations; name = 'allowed-locations'; displayName = 'Allowed locations - UK'; scope = "$mg/mg-landingzones"; definitionId = (& $builtin 'allowed-locations'); enforcement = 'Default'
                parameters = @{ listOfAllowedLocations = @{ value = @('uksouth', 'ukwest') } }; notScopes = @(); overrides = $null; resourceSelectors = $null; identityType = ''
                nonComplianceMessages = @(@{ message = 'Deploy to UK South or UK West only.' }); definitionVersion = '1.*.*' }
            @{ id = $ids.Baseline; name = 'baseline'; displayName = 'Contoso baseline'; scope = "$mg/tenant-root"; definitionId = $set; enforcement = 'Default'; parameters = @{}; notScopes = @(); resourceSelectors = $null; identityType = ''
                overrides = @(@{ kind = 'policyEffect'; value = 'Disabled'; selectors = @(@{ kind = 'policyDefinitionReferenceId'; in = @('vmOs') }) })
                nonComplianceMessages = @(@{ message = 'Storage must use TLS 1.2.'; policyDefinitionReferenceId = 'storageTls' }); definitionVersion = '' }
            @{ id = $ids.CostCenter; name = 'require-costcenter'; displayName = 'Require CostCenter'; scope = "/subscriptions/$corp"; definitionId = (& $builtin 'require-tag'); enforcement = 'DoNotEnforce'
                parameters = @{ tagName = @{ value = 'CostCenter' } }; notScopes = @(); overrides = $null; resourceSelectors = $null; identityType = ''; nonComplianceMessages = $null; definitionVersion = '' }
            @{ id = $ids.TlsAudit; name = 'tls-audit'; displayName = 'Storage TLS audit'; scope = "/subscriptions/$corp"; definitionId = (& $custom 'storage-tls'); enforcement = 'Default'
                parameters = @{ effect = @{ value = 'Audit' } }; notScopes = @("/subscriptions/$corp/resourceGroups/rg-data"); overrides = $null; resourceSelectors = $null; identityType = ''; nonComplianceMessages = $null; definitionVersion = '' }
            @{ id = $ids.EuOnly; name = 'eu-only'; displayName = 'EU vault RBAC'; scope = "/subscriptions/$corp"; definitionId = (& $custom 'kv-rbac'); enforcement = 'Default'; parameters = @{}; notScopes = @(); overrides = $null; identityType = ''
                resourceSelectors = @(@{ name = 'EU only'; selectors = @(@{ kind = 'resourceLocation'; in = @('westeurope', 'northeurope') }) }); nonComplianceMessages = $null; definitionVersion = '' }
        )
        Exemptions       = @(
            @{ id = "$($ids.Storage)/providers/Microsoft.Authorization/policyExemptions/tls-waiver"; name = 'tls-waiver'; displayName = 'Legacy client needs TLS 1.0'; description = 'Retail POS until the upgrade.'
                assignmentId = $ids.Baseline.ToLowerInvariant(); referenceIds = @('storageTls'); category = 'Waiver'; expiresOn = $now.AddDays(10).ToString('o'); resourceSelectors = $null }
            @{ id = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Authorization/policyExemptions/cc-mitigated"; name = 'cc-mitigated'; displayName = 'Tagged by the pipeline'; description = ''
                assignmentId = $ids.CostCenter.ToLowerInvariant(); referenceIds = @(); category = 'Mitigated'; expiresOn = $now.AddDays(-5).ToString('o'); resourceSelectors = $null }
        )
        Resources        = @(
            @{ id = $ids.Storage; name = 'stordersdata'; type = 'Microsoft.Storage/storageAccounts'; location = 'uksouth'; kind = 'StorageV2'; tags = @{}; resourceGroup = 'rg-data'; subscriptionId = $corp }
            @{ id = $ids.Vault; name = 'kv-app'; type = 'Microsoft.KeyVault/vaults'; location = 'westeurope'; kind = ''; tags = @{ CostCenter = 'cc-1' }; resourceGroup = 'rg-app'; subscriptionId = $corp }
            @{ id = $ids.Aks; name = 'aks-orders'; type = 'Microsoft.ContainerService/managedClusters'; location = 'uksouth'; kind = ''; tags = @{}; resourceGroup = 'rg-app'; subscriptionId = $corp }
        )
        States           = @(
            @{ resourceId = $ids.Storage.ToLowerInvariant(); assignmentId = $ids.Locations.ToLowerInvariant(); referenceId = ''; state = 'Compliant'; evaluated = '2026-10-28T06:00:00Z' }
            @{ resourceId = $ids.Storage.ToLowerInvariant(); assignmentId = $ids.Baseline.ToLowerInvariant(); referenceId = 'storagetls'; state = 'Exempt'; evaluated = '2026-10-28T06:00:00Z' }
            @{ resourceId = $ids.Vault.ToLowerInvariant(); assignmentId = $ids.Locations.ToLowerInvariant(); referenceId = ''; state = 'NonCompliant'; evaluated = '2026-10-28T06:00:00Z' }
            @{ resourceId = $ids.Vault.ToLowerInvariant(); assignmentId = $ids.Baseline.ToLowerInvariant(); referenceId = 'kvdiag'; state = 'NonCompliant'; evaluated = '2026-10-28T06:00:00Z' }
            @{ resourceId = $ids.Aks.ToLowerInvariant(); assignmentId = $ids.Baseline.ToLowerInvariant(); referenceId = 'akspods'; state = 'Compliant'; evaluated = '2026-10-28T06:00:00Z' }
        )
        # Policy Insights' queryResults for kv-app, with the evaluation details.
        Reasons          = @{
            $ids.Vault.ToLowerInvariant() = @(
                @{ policyAssignmentId = $ids.Locations; policyDefinitionReferenceId = ''; policyEvaluationDetails = @{ evaluatedExpressions = @(
                            @{ result = 'True'; expressionKind = 'Field'; expression = 'location'; path = 'location'; expressionValue = 'westeurope'; targetValue = @('uksouth', 'ukwest'); operator = 'NotIn' }
                            @{ result = 'True'; expressionKind = 'Field'; expression = 'type'; path = 'type'; expressionValue = 'Microsoft.KeyVault/vaults'; targetValue = 'Microsoft.AzureActiveDirectory/b2cDirectories'; operator = 'NotEquals' }
                        ) } }
            )
        }
    }
}
