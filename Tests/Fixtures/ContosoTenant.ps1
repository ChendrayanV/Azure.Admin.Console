<#
    A made-up Contoso tenant as Azure Resource Graph returns it (hashtables):
    the rows Get-AACInventory's tree is built from in Inventory.Tests.ps1.

      Tenant Root Group
        Platform
          Connectivity          sub-connectivity: rg-hub (6 resources)
        Landing Zones
          Corp                  sub-corp-apps: rg-app (7), rg-data (3), rg-empty (0)
        Sandbox                 (no subscriptions)
      sub-legacy                (in no management group the account can read)
#>
$script:ContosoTenantId = 'aaaaaaaa-0000-0000-0000-00000000c0de'

function Get-AACContosoTenant {
    $tenant = $script:ContosoTenantId
    $mg = { param($Name, $Display, $Parent) @{ id = "/providers/Microsoft.Management/managementGroups/$Name"; name = $Name; displayName = $Display; parentId = $(if ($Parent) { "/providers/Microsoft.Management/managementGroups/$Parent" } else { '' }) } }
    $connectivity = '11111111-1111-1111-1111-111111111111'
    $corp = '22222222-2222-2222-2222-222222222222'
    $legacy = '33333333-3333-3333-3333-333333333333'
    $rg = { param($Sub, $Name, $Location = 'uksouth') @{ id = "/subscriptions/$Sub/resourceGroups/$Name"; name = $Name; subscriptionId = $Sub; location = $Location; state = 'Succeeded'; managedBy = ''; tags = @{ env = 'prod' } } }
    $res = {
        param($Sub, $Group, $Type, $Name, $Sku = '', $Location = 'uksouth')
        @{ id = "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name"; name = $Name; type = $Type; kind = ''; location = $Location; resourceGroup = $Group; subscriptionId = $Sub; sku = $Sku; zones = @(); tags = @{ owner = 'platform' } }
    }
    @{
        TenantId         = $tenant
        ManagementGroups = @(
            & $mg $tenant 'Tenant Root Group' ''
            & $mg 'mg-platform' 'Platform' $tenant
            & $mg 'mg-connectivity' 'Connectivity' 'mg-platform'
            & $mg 'mg-landingzones' 'Landing Zones' $tenant
            & $mg 'mg-corp' 'Corp' 'mg-landingzones'
            & $mg 'mg-sandbox' 'Sandbox' $tenant
        )
        Subscriptions    = @(
            @{ subscriptionId = $connectivity; name = 'sub-connectivity'; state = 'Enabled'; parentGroup = 'mg-connectivity'; tags = @{} }
            @{ subscriptionId = $corp; name = 'sub-corp-apps'; state = 'Enabled'; parentGroup = 'mg-corp'; tags = @{ costCenter = '1234' } }
            @{ subscriptionId = $legacy; name = 'sub-legacy'; state = 'Warned'; parentGroup = ''; tags = @{} }
        )
        ResourceGroups   = @(
            & $rg $connectivity 'rg-hub'
            & $rg $corp 'rg-app'
            & $rg $corp 'rg-data' 'ukwest'
            & $rg $corp 'rg-empty'
            & $rg $legacy 'rg-old' 'westeurope'
        )
        # Microsoft Defender for Cloud (Resource Graph securityresources).
        Security         = @{
            Scores          = @(
                @{ subscriptionId = $connectivity; current = 38.0; max = 50.0 }
                @{ subscriptionId = $corp; current = 18.0; max = 50.0 }
            )
            Controls        = @(
                @{ subscriptionId = $corp; control = 'Secure management ports'; current = 0.0; max = 8.0; healthy = 0; unhealthy = 2 }
                @{ subscriptionId = $corp; control = 'Enable encryption at rest'; current = 2.0; max = 4.0; healthy = 3; unhealthy = 2 }
                @{ subscriptionId = $corp; control = 'Restrict unauthorized network access'; current = 3.5; max = 4.0; healthy = 6; unhealthy = 1 }
                @{ subscriptionId = $connectivity; control = 'Secure management ports'; current = 8.0; max = 8.0; healthy = 1; unhealthy = 0 }
                @{ subscriptionId = $connectivity; control = 'Enable DDoS protection'; current = 0.0; max = 2.0; healthy = 0; unhealthy = 1 }
            )
            Summary         = @(
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01"; healthy = 6; unhealthy = 4; high = 2; medium = 1; low = 1 }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-02"; healthy = 8; unhealthy = 2; high = 0; medium = 2; low = 0 }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv-app"; healthy = 4; unhealthy = 0; high = 0; medium = 0; low = 0 }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stordersdata"; healthy = 3; unhealthy = 1; high = 0; medium = 0; low = 1 }
                @{ resourceId = "/subscriptions/$connectivity/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"; healthy = 1; unhealthy = 1; high = 0; medium = 1; low = 0 }
            )
            Recommendations = @(
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01"; subscriptionId = $corp; name = 'Management ports of virtual machines should be protected with just-in-time network access control'; severity = 'High'; impact = 'High'; effort = 'Low'; categories = 'Networking'; cause = '' }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01"; subscriptionId = $corp; name = 'Machines should have vulnerability findings resolved'; severity = 'High'; impact = 'High'; effort = 'Moderate'; categories = 'Compute'; cause = '' }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01"; subscriptionId = $corp; name = 'Virtual machines should encrypt temp disks, caches, and data flows'; severity = 'Medium'; impact = 'Moderate'; effort = 'Low'; categories = 'Data'; cause = '' }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01"; subscriptionId = $corp; name = 'Guest Configuration extension should be installed on machines'; severity = 'Low'; impact = 'Low'; effort = 'Low'; categories = 'Compute'; cause = '' }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-02"; subscriptionId = $corp; name = 'Virtual machines should encrypt temp disks, caches, and data flows'; severity = 'Medium'; impact = 'Moderate'; effort = 'Low'; categories = 'Data'; cause = '' }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-02"; subscriptionId = $corp; name = 'System updates should be installed on your machines'; severity = 'Medium'; impact = 'Moderate'; effort = 'Low'; categories = 'Compute'; cause = '' }
                @{ resourceId = "/subscriptions/$corp/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stordersdata"; subscriptionId = $corp; name = 'Storage accounts should restrict network access using virtual network rules'; severity = 'Low'; impact = 'Low'; effort = 'Moderate'; categories = 'Networking'; cause = '' }
                @{ resourceId = "/subscriptions/$connectivity/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"; subscriptionId = $connectivity; name = 'Azure DDoS Protection Standard should be enabled'; severity = 'Medium'; impact = 'Moderate'; effort = 'Moderate'; categories = 'Networking'; cause = '' }
            )
        }
        Resources        = @(
            & $res $connectivity 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub'
            & $res $connectivity 'rg-hub' 'Microsoft.Network/azureFirewalls' 'afw-hub' 'AZFW_VNet'
            & $res $connectivity 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-afw' 'Standard'
            & $res $connectivity 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-bas' 'Standard'
            & $res $connectivity 'rg-hub' 'Microsoft.Network/bastionHosts' 'bas-hub' 'Standard'
            & $res $connectivity 'rg-hub' 'Microsoft.Network/virtualNetworkGateways' 'vgw-hub'
            & $res $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-01'
            & $res $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-02'
            & $res $corp 'rg-app' 'Microsoft.Compute/disks' 'vm-web-01_OsDisk' 'Premium_LRS'
            & $res $corp 'rg-app' 'Microsoft.Compute/disks' 'vm-web-02_OsDisk' 'Premium_LRS'
            & $res $corp 'rg-app' 'Microsoft.Network/networkInterfaces' 'nic-web-01'
            & $res $corp 'rg-app' 'Microsoft.Network/networkInterfaces' 'nic-web-02'
            & $res $corp 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-app' 'standard'
            & $res $corp 'rg-data' 'Microsoft.Sql/servers' 'sql-orders' '' 'ukwest'
            & $res $corp 'rg-data' 'Microsoft.Sql/servers/databases' 'sql-orders/sqldb-orders' 'GP_Gen5_2' 'ukwest'
            & $res $corp 'rg-data' 'Microsoft.Storage/storageAccounts' 'stordersdata' 'Standard_ZRS' 'ukwest'
            & $res $legacy 'rg-old' 'Microsoft.Web/serverFarms' 'asp-old' 'B1' 'westeurope'
        )
    }
}

<#
    Cost Management rows for the Contoso tenant (grouped by ResourceId and
    SubscriptionId, monthly), this month and last:
      sub-connectivity (USD)  afw-hub 800 / 900
      sub-corp-apps (USD)     vm-web-01 100 / 150, vm-web-02 50 / 0,
                              a database of sql-orders 30 / 0 (billed to its
                              server), a deleted VM in rg-app 20, a deleted
                              resource in rg-other 7, a charge with no
                              resource 5
      sub-legacy (EUR)        asp-old 10 / 0
#>
function Get-AACContosoCost {
    $thisMonth = [datetime]::new((Get-Date).Year, (Get-Date).Month, 1)
    $lastMonth = $thisMonth.AddMonths(-1)
    $connectivity = '11111111-1111-1111-1111-111111111111'
    $corp = '22222222-2222-2222-2222-222222222222'
    $legacy = '33333333-3333-3333-3333-333333333333'
    $row = {
        param($Sub, [string] $Path, [datetime] $Month, [double] $Cost, [string] $Currency = 'USD')
        [pscustomobject]@{ Cost = $Cost; BillingMonth = $Month; ResourceId = $(if ($Path) { "/subscriptions/$Sub/resourcegroups/$Path".ToLowerInvariant() } else { '' }); SubscriptionId = $Sub; Currency = $Currency }
    }
    @{
        ThisMonth = $thisMonth.ToString('yyyy-MM', [cultureinfo]::InvariantCulture)
        LastMonth = $lastMonth.ToString('yyyy-MM', [cultureinfo]::InvariantCulture)
        Rows      = @(
            & $row $connectivity 'rg-hub/providers/Microsoft.Network/azureFirewalls/afw-hub' $thisMonth 800
            & $row $connectivity 'rg-hub/providers/Microsoft.Network/azureFirewalls/afw-hub' $lastMonth 900
            & $row $corp 'rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01' $thisMonth 100
            & $row $corp 'rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01' $lastMonth 150
            & $row $corp 'rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-02' $thisMonth 50
            & $row $corp 'rg-data/providers/Microsoft.Sql/servers/sql-orders/databases/sqldb-billing' $thisMonth 30
            & $row $corp 'rg-app/providers/Microsoft.Compute/virtualMachines/vm-gone' $thisMonth 20
            & $row $corp 'rg-other/providers/Microsoft.Storage/storageAccounts/stgone' $thisMonth 7
            & $row $corp '' $thisMonth 5
            & $row $legacy 'rg-old/providers/Microsoft.Web/serverFarms/asp-old' $thisMonth 10 'EUR'
        )
        Status    = @{ $connectivity = 'OK'; $corp = 'OK'; $legacy = 'OK' }
    }
}
