<#
    A made-up Contoso tenant for the Invoke-AACAssessment tests, as Azure
    Resource Graph and Resource Manager return it:

      Tenant Root Group > mg-platform > sub-connectivity (vnet-hub-weu, a public IP, an orphaned NIC)
                        > mg-landingzones > sub-landingzone-app
                              rg-app      vm-web-1 (running), vm-web-2 (deallocated, a Basic public IP
                                          being retired), stcontosoapp (TLS 1.0, shared keys), disk-old
                                          (unattached), kv-contoso-app
                              rg-empty    nothing
      Advisor: a High cost recommendation, a retirement (Basic public IPs) - Defender: a High one
      Policy: an assignment with 3 non-compliant resources - an outage - a reservation saving

    Sheet rows are keyed by the sheet's column labels; ConvertTo-AACAssessmentFixtureRow
    turns them into the columns the query returns (c0, r1, ...).

    Returns @{ Subscriptions; ManagementGroups; Groups; Resources; Types; Sheets (sheet -> rows by
    label); Advisor; Security; SecureScores; Policy; SupportTickets; Arm; Cost; Diagram }.
#>
function Get-AACContosoAssessment {
    $hub = '11111111-1111-1111-1111-111111111111'
    $app = '22222222-2222-2222-2222-222222222222'
    $chain = { param([string[]] $Names) @($Names | ForEach-Object { @{ name = $_; displayName = $(switch ($_) { 'contoso' { 'Tenant Root Group' } 'mg-platform' { 'Platform' } 'mg-landingzones' { 'Landing zones' } }) } }) }
    $id = { param([string] $Sub, [string] $Group, [string] $Type, [string] $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name" }
    $resource = {
        param([string] $Sub, [string] $Group, [string] $Type, [string] $Name, [string] $Location = 'westeurope', [hashtable] $Tags = $null, [string] $Sku = '', [string] $Kind = '')
        @{ id = & $id $Sub $Group $Type $Name; name = $Name; type = $Type.ToLowerInvariant(); kind = $Kind; location = $Location; resourceGroup = $Group; subscriptionId = $Sub; sku = $Sku; state = 'Succeeded'; tags = $Tags }
    }
    $resources = @(
        & $resource $hub 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub-weu' -Tags @{ env = 'prod' }
        & $resource $hub 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-hub' -Sku 'Standard' -Tags @{ env = 'prod' }
        & $resource $hub 'rg-hub' 'Microsoft.Network/networkInterfaces' 'nic-orphan'
        & $resource $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-1' -Tags @{ env = 'prod'; app = 'web' }
        & $resource $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-2' -Tags @{ env = 'prod'; app = 'web' }
        & $resource $app 'rg-app' 'Microsoft.Network/publicIPAddresses' 'pip-web-2' -Sku 'Basic'
        & $resource $app 'rg-app' 'Microsoft.Storage/storageAccounts' 'stcontosoapp' -Sku 'Standard_LRS' -Kind 'StorageV2' -Tags @{ env = 'prod' }
        & $resource $app 'rg-app' 'Microsoft.Compute/disks' 'disk-old' -Sku 'Premium_LRS'
        & $resource $app 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-contoso-app' -Tags @{ env = 'prod' }
        & $resource $app 'rg-app' 'Microsoft.Logic/workflows' 'logic-orders'
    )
    $types = @($resources | Group-Object { "$($_.type)|$($_.subscriptionId)|$($_.location)" } | ForEach-Object { $first = $_.Group[0]; @{ type = $first.type; subscriptionId = $first.subscriptionId; location = $first.location; resources = $_.Count } })
    $row = {
        param([string] $Sub, [string] $Group, [string] $Type, [string] $Name, [hashtable] $Labels)
        @{ id = & $id $Sub $Group $Type $Name; name = $Name; resourceGroup = $Group; subscriptionId = $Sub; location = 'westeurope'; tags = $null; Labels = $Labels }
    }
    $sheets = @{
        'Virtual machines' = @(
            & $row $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-1' @{ 'Size' = 'Standard_D2s_v5'; 'Power state' = 'VM running'; 'OS type' = 'Linux'; 'OS' = 'ubuntu'; 'Private IP' = '10.1.0.4'; 'Virtual network' = 'vnet-spoke-app'; 'Subnet' = 'snet-web'; 'Data disks (GB)' = @(@{ diskSizeGB = 128 }, @{ diskSizeGB = 256 }); 'Boot diagnostics' = 'true'; 'Created' = '2024-03-01T10:15:00Z' }
            & $row $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-2' @{ 'Size' = 'Standard_B2ms'; 'Power state' = 'VM deallocated'; 'OS type' = 'Windows'; 'OS' = 'WindowsServer'; 'Public IP' = '203.0.113.20'; 'Data disks (GB)' = @(); 'Boot diagnostics' = 'false' }
        )
        'Storage accounts' = @(& $row $app 'rg-app' 'Microsoft.Storage/storageAccounts' 'stcontosoapp' @{ 'Kind' = 'StorageV2'; 'SKU' = 'Standard_LRS'; 'Minimum TLS' = 'TLS1_0'; 'Shared key access' = 'true'; 'Public blob access' = 'false'; 'Default action' = 'Allow'; 'Private endpoints' = 0 })
        'Disks' = @(& $row $app 'rg-app' 'Microsoft.Compute/disks' 'disk-old' @{ 'State' = 'Unattached'; 'SKU' = 'Premium_LRS'; 'Size (GB)' = 512 })
        'Network interfaces' = @(& $row $hub 'rg-hub' 'Microsoft.Network/networkInterfaces' 'nic-orphan' @{ 'Private IP' = '10.0.1.9'; 'Orphaned' = 'Yes' })
        'Public IP addresses' = @(
            & $row $hub 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-hub' @{ 'IP address' = '203.0.113.10'; 'SKU' = 'Standard'; 'Orphaned' = 'No'; 'Associated with' = 'afw-hub' }
            & $row $app 'rg-app' 'Microsoft.Network/publicIPAddresses' 'pip-web-2' @{ 'IP address' = '203.0.113.20'; 'SKU' = 'Basic'; 'Orphaned' = 'No' }
        )
        'Virtual networks' = @(& $row $hub 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub-weu' @{ 'Address space' = '10.0.0.0/22'; 'Subnets' = 2; 'Subnet names' = @(@{ name = 'GatewaySubnet' }, @{ name = 'snet-dns' }) })
        'Subnets' = @(
            & $row $hub 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub-weu' @{ 'Subnet' = 'GatewaySubnet'; 'Prefix' = '10.0.0.0/27'; 'IP configurations' = 2 }
            & $row $hub 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub-weu' @{ 'Subnet' = 'snet-dns'; 'Prefix' = '10.0.1.0/28'; 'IP configurations' = 1 }
        )
        'Key vaults' = @(& $row $app 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-contoso-app' @{ 'SKU' = 'standard'; 'RBAC' = 'true'; 'Purge protection' = $null; 'Public network access' = 'Enabled' })
    }
    @{
        HubSubscriptionId = $hub; AppSubscriptionId = $app
        Subscriptions = @(
            @{ id = "/subscriptions/$hub"; subscriptionId = $hub; name = 'sub-connectivity'; state = 'Enabled'; quotaId = 'EnterpriseAgreement_2014-09-01'; chain = & $chain 'mg-platform', 'contoso'; tags = $null }
            @{ id = "/subscriptions/$app"; subscriptionId = $app; name = 'sub-landingzone-app'; state = 'Enabled'; quotaId = 'EnterpriseAgreement_2014-09-01'; chain = & $chain 'mg-landingzones', 'contoso'; tags = $null }
        )
        ManagementGroups = @(
            @{ id = '/providers/Microsoft.Management/managementGroups/contoso'; name = 'contoso'; displayName = 'Tenant Root Group'; parent = '' }
            @{ id = '/providers/Microsoft.Management/managementGroups/mg-platform'; name = 'mg-platform'; displayName = 'Platform'; parent = 'contoso' }
            @{ id = '/providers/Microsoft.Management/managementGroups/mg-landingzones'; name = 'mg-landingzones'; displayName = 'Landing zones'; parent = 'contoso' }
            @{ id = '/providers/Microsoft.Management/managementGroups/mg-sandbox'; name = 'mg-sandbox'; displayName = 'Sandbox'; parent = 'contoso' }
        )
        Groups = @(
            @{ id = "/subscriptions/$hub/resourceGroups/rg-hub"; name = 'rg-hub'; subscriptionId = $hub; location = 'westeurope'; tags = @{ env = 'prod' } }
            @{ id = "/subscriptions/$app/resourceGroups/rg-app"; name = 'rg-app'; subscriptionId = $app; location = 'westeurope'; tags = $null }
            @{ id = "/subscriptions/$app/resourceGroups/rg-empty"; name = 'rg-empty'; subscriptionId = $app; location = 'northeurope'; tags = $null }
        )
        Resources = $resources
        Types = $types
        Sheets = $sheets
        Advisor = @(
            @{ id = 'a1'; subscriptionId = $app; resourceGroup = 'rg-app'; category = 'Cost'; impact = 'High'; problem = 'Right-size or shut down underutilized virtual machines'; solution = 'Resize to Standard_B1ms'; resourceId = (& $id $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-1').ToLowerInvariant(); impactedType = 'Microsoft.Compute/virtualMachines'; impactedValue = 'vm-web-1'; savings = 412.5; savingsCurrency = 'EUR'; subCategory = ''; retirementDate = ''; retirementFeature = ''; lastUpdated = '2026-09-30T08:00:00Z' }
            @{ id = 'a2'; subscriptionId = $app; resourceGroup = 'rg-app'; category = 'HighAvailability'; impact = 'Medium'; problem = 'Upgrade Basic SKU public IP addresses to Standard SKU'; solution = 'Upgrade to a Standard public IP'; resourceId = (& $id $app 'rg-app' 'Microsoft.Network/publicIPAddresses' 'pip-web-2').ToLowerInvariant(); impactedType = 'Microsoft.Network/publicIPAddresses'; impactedValue = 'pip-web-2'; savings = $null; savingsCurrency = ''; subCategory = 'ServiceUpgradeAndRetirement'; retirementDate = '2025-09-30'; retirementFeature = 'Basic SKU public IP addresses'; lastUpdated = '2026-09-30T08:00:00Z' }
            @{ id = 'a3'; subscriptionId = $app; resourceGroup = 'rg-app'; category = 'Security'; impact = 'Low'; problem = 'Storage account public access should be disallowed'; solution = ''; resourceId = (& $id $app 'rg-app' 'Microsoft.Storage/storageAccounts' 'stcontosoapp').ToLowerInvariant(); impactedType = 'Microsoft.Storage/storageAccounts'; impactedValue = 'stcontosoapp'; savings = $null; savingsCurrency = ''; subCategory = ''; retirementDate = ''; retirementFeature = ''; lastUpdated = '' }
        )
        Security = @(@{ id = 's1'; subscriptionId = $app; resourceGroup = 'rg-app'; resourceId = (& $id $app 'rg-app' 'Microsoft.Storage/storageAccounts' 'stcontosoapp').ToLowerInvariant(); recommendation = 'Storage accounts should restrict network access'; severity = 'High'; categories = 'Data'; remediation = 'Set the default action to Deny.'; since = '2026-08-01T00:00:00Z' })
        SecureScores = @(@{ id = 'sc1'; subscriptionId = $app; current = 31.5; max = 45 }, @{ id = 'sc2'; subscriptionId = $hub; current = 40; max = 45 })
        Policy = @(@{ id = 'p1'; assignmentId = '/providers/microsoft.management/managementgroups/contoso/providers/microsoft.authorization/policyassignments/allowed-locations'; assignmentName = 'allowed-locations'; assignment = 'Allowed locations'; assignmentScope = '/providers/Microsoft.Management/managementGroups/contoso'; definitionId = '/providers/microsoft.authorization/policydefinitions/e56962a6'; policy = 'Allowed locations'; setId = ''; policySet = ''; effect = 'deny'; nonCompliant = 3; compliant = 7; exempt = 0; other = 0; subscriptions = 2 })
        # Compliance per resource group, each non-compliant resource, and the assignment behind them.
        PolicyByGroup = @(
            @{ id = "$app|rg-app"; subscriptionId = $app; resourceGroup = 'rg-app'; resources = 6; nonCompliant = 2; compliant = 4; exempt = 0; nonCompliantStates = 3 }
            @{ id = "$hub|rg-hub"; subscriptionId = $hub; resourceGroup = 'rg-hub'; resources = 4; nonCompliant = 0; compliant = 4; exempt = 0; nonCompliantStates = 0 }
        )
        PolicyResources = @(
            @{ id = 'r1'; resourceId = (& $id $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-1').ToLowerInvariant(); subscriptionId = $app; resourceGroup = 'rg-app'; resourceType = 'Microsoft.Compute/virtualMachines'; assignmentId = '/providers/microsoft.management/managementgroups/contoso/providers/microsoft.authorization/policyassignments/allowed-locations'; assignment = 'Allowed locations'; definitionId = '/providers/microsoft.authorization/policydefinitions/e56962a6'; policy = 'Allowed locations'; description = 'Restrict the locations resources can be deployed to.'; effect = 'deny'; reasonCode = ''; groups = ''; setId = ''; policySet = ''; evaluated = '2026-10-04T08:00:00Z' }
        )
        PolicyData = @{
            Assignments       = @(@{ id = '/providers/Microsoft.Management/managementGroups/contoso/providers/Microsoft.Authorization/policyAssignments/allowed-locations'; name = 'allowed-locations'; displayName = 'Allowed locations'; scope = '/providers/Microsoft.Management/managementGroups/contoso'; definitionId = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6'; parameters = @{}; enforcement = 'Default'; notScopes = @(); overrides = $null; description = '' })
            Definitions       = @{ '/providers/microsoft.authorization/policydefinitions/e56962a6' = @{ Id = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6'; Name = 'e56962a6'; Kind = 'Policy'; DisplayName = 'Allowed locations'; PolicyType = 'BuiltIn'; Category = 'General'; Description = 'Restrict the locations resources can be deployed to.'; Parameters = @{}; Rule = @{ if = @{ field = 'location'; notIn = @('westeurope') }; then = @{ effect = 'deny' } }; Members = @() } }
            SubscriptionNames = @{ $hub = 'sub-connectivity'; $app = 'sub-landingzone-app' }
            GroupNames        = @{ contoso = 'Tenant Root Group'; 'mg-platform' = 'Platform'; 'mg-landingzones' = 'Landing zones' }
            SubscriptionChain = @{ $hub = @('contoso', 'mg-platform'); $app = @('contoso', 'mg-landingzones') }
            GroupChain        = @{ contoso = @('contoso'); 'mg-platform' = @('contoso', 'mg-platform'); 'mg-landingzones' = @('contoso', 'mg-landingzones') }
        }
        SupportTickets = @(@{ id = '/subscriptions/x/providers/Microsoft.Support/supportTickets/t1'; subscriptionId = $app; ticketId = '2410040010001234'; ticketTitle = 'VM cannot start'; service = 'Virtual Machine running Windows'; severity = 'Moderate'; status = 'Open'; plan = 'Unified'; created = '2026-10-01T09:00:00Z'; modified = '2026-10-02T09:00:00Z' })
        Arm = @{
            AdvisorScore = @{ $app = @(@{ name = 'Cost'; properties = @{ lastRefreshedScore = @{ date = '2026-10-03'; score = 62; impactedResourceCount = 3; potentialScoreIncrease = 12 } } }) }
            Reservation  = @{ $app = @(@{ location = 'westeurope'; sku = 'Standard_D2s_v5'; properties = @{ resourceType = 'virtualmachines'; normalizedSize = 'Standard_D2s_v5'; recommendedQuantity = 2; term = 'P1Y'; scope = 'Single'; lookBackPeriod = 'Last30Days'; costWithNoReservedInstances = 1200; totalCostWithReservedInstances = 780; netSavings = 420 } }) }
            Outage       = @{
                $app = @(@{ name = 'TRK-1ZZ'; properties = @{ eventType = 'ServiceIssue'; title = 'Virtual Machines - West Europe'; status = 'Resolved'; level = 'Warning'; impactStartTime = '2026-07-12T10:00:00Z'; impactMitigationTime = '2026-07-12T13:00:00Z'; lastUpdateTime = '2026-07-14T09:00:00Z'; summary = '<p>Some VMs <b>restarted</b>.</p>'; impact = @(@{ impactedService = 'Virtual Machines'; impactedRegions = @(@{ impactedRegion = 'West Europe' }) }) } }, @{ name = 'PLAN-1'; properties = @{ eventType = 'PlannedMaintenance'; title = 'Maintenance' } })
                $hub = @(@{ name = 'TRK-1ZZ'; properties = @{ eventType = 'ServiceIssue'; title = 'Virtual Machines - West Europe'; status = 'Resolved'; impactStartTime = '2026-07-12T10:00:00Z' } })
            }
            Quota        = @{ "$app|westeurope" = @(@{ name = @{ value = 'standardDSv5Family'; localizedValue = 'Standard DSv5 Family vCPUs' }; currentValue = 8; limit = 10 }, @{ name = @{ value = 'standardNCFamily'; localizedValue = 'Standard NC Family vCPUs' }; currentValue = 0; limit = 24 }) }
            Sku          = @{ westeurope = @(@{ resourceType = 'virtualMachines'; name = 'Standard_D2s_v5'; capabilities = @(@{ name = 'vCPUs'; value = '2' }, @{ name = 'MemoryGB'; value = '8' }) }, @{ resourceType = 'disks'; name = 'Premium_LRS'; capabilities = @() }) }
        }
        Cost = @{
            ThisMonth = '2026-10'; LastMonth = '2026-09'; Status = @{ $app = 'OK'; $hub = 'OK' }; Notice = @()
            Rows = @(
                @{ ResourceId = (& $id $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-1'); SubscriptionId = $app; BillingMonth = '20261001'; Cost = 41.25; Currency = 'EUR' }
                @{ ResourceId = (& $id $app 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-1'); SubscriptionId = $app; BillingMonth = '20260901'; Cost = 120.5; Currency = 'EUR' }
                @{ ResourceId = (& $id $hub 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-hub'); SubscriptionId = $hub; BillingMonth = '20261001'; Cost = 1.1; Currency = 'EUR' }
            )
        }
        Diagram = @(@{ id = & $id $hub 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub-weu'; name = 'vnet-hub-weu'; type = 'microsoft.network/virtualnetworks'; kind = ''; location = 'westeurope'; resourceGroup = 'rg-hub'; subscriptionId = $hub; sku = $null; tags = $null; properties = @{ addressSpace = @{ addressPrefixes = @('10.0.0.0/22') }; subnets = @(@{ id = "$(& $id $hub 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub-weu')/subnets/GatewaySubnet"; name = 'GatewaySubnet'; properties = @{ addressPrefix = '10.0.0.0/27' } }) } })
    }
}

# The rows a sheet's query returns: each label's value under its query column (c0, r1...).
function ConvertTo-AACAssessmentFixtureRow {
    param([hashtable] $Compiled, [object[]] $Rows)
    foreach ($row in $Rows) {
        $out = @{ id = $row.id; name = $row.name; resourceGroup = $row.resourceGroup; subscriptionId = $row.subscriptionId; location = $row.location; tags = $row.tags }
        foreach ($label in $Compiled.Columns.Keys) {
            $column = $Compiled.Columns[$label].Column
            if ($column) { $out[$column] = $(if ($row.Labels.Contains($label)) { $row.Labels[$label] } else { $null }) }
        }
        $out
    }
}
