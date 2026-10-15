<#
    Made-up Contoso estate for WafAssessment.Tests.ps1: the rows of
    Get-AACWafQuery's one Resource Graph batch, by query name.

      Contoso Prod (1111...)  rg-app: vm-prod-01 (zones, backed up, encrypted
                              at host), st-prod (ZRS, locked down, plus an
                              Advisor HighAvailability recommendation), two
                              more storage accounts Advisor doesn't name,
                              kv-prod, nsg-prod (SSH from 10.0.0.0/8 only)
      Contoso Dev  (2222...)  rg-dev: vm-dev-01 (no zone, no backup), st-dev
                              (LRS, TLS 1.0, public blobs), lb-dev (Basic,
                              no probe), nsg-dev (RDP from anywhere)
    Defender: Prod has Servers and Storage plans and a 80% secure score; Dev
    none and 40%. One high-severity assessment: healthy on vm-prod-01,
    unhealthy on vm-dev-01.

    For cost, operations and performance: vm-prod-01 is tagged CostCenter,
    has the Azure Monitor agent, platform patching and a Premium OS disk;
    vm-dev-01 is untagged, stopped (still billed), on Standard HDD, with an
    Advisor cost recommendation; disk-old (Dev) is unattached; snap-2024
    (Prod) is old; rg-app has owner, environment and cost tags, rg-dev none;
    Prod has an alert rule and an action group, Dev neither.

    Duplicates: Advisor's 'Use Availability zones' on vm-dev-01 is RE-01, and
    Defender's 'Storage account public access should be disallowed' on stdev
    is SE-07 - both already tested by the catalogue on those resources.
#>
function Get-AACContosoWaf {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $row = {
        param($Sub, $Group, $Type, $Name, $Properties, $Sku = $null, $Zones = $null, $Identity = $null, $Tags = $null)
        @{ id = "/subscriptions/$Sub/resourcegroups/$Group/providers/$Type/$Name".ToLowerInvariant(); name = $Name; type = $Type; kind = ''; location = 'uksouth'; resourceGroup = $Group; subscriptionId = $Sub; sku = $Sku; zones = $Zones; identity = $Identity; tags = $Tags; properties = $Properties }
    }
    $vmProd = & $row $prod 'rg-app' 'microsoft.compute/virtualmachines' 'vm-prod-01' @{
        storageProfile = @{ osDisk = @{ osType = 'Linux'; managedDisk = @{ id = 'x'; storageAccountType = 'Premium_LRS' } } }; securityProfile = @{ encryptionAtHost = $true }
        hardwareProfile = @{ vmSize = 'Standard_D4s_v5' }; diagnosticsProfile = @{ bootDiagnostics = @{ enabled = $true } }; osProfile = @{ linuxConfiguration = @{ patchSettings = @{ patchMode = 'AutomaticByPlatform' } } }
        extended = @{ instanceView = @{ powerState = @{ code = 'PowerState/running' } } }
    } $null @('1') $null @{ CostCenter = 'CC-1' }
    $vmDev = & $row $dev 'rg-dev' 'microsoft.compute/virtualmachines' 'vm-dev-01' @{
        storageProfile = @{ osDisk = @{ osType = 'Linux'; managedDisk = @{ id = 'y'; storageAccountType = 'Standard_LRS' } } }; hardwareProfile = @{ vmSize = 'Standard_D2_v2' }
        extended = @{ instanceView = @{ powerState = @{ code = 'PowerState/stopped' } } }
    }
    $stProd = & $row $prod 'rg-app' 'microsoft.storage/storageaccounts' 'stprod' @{ supportsHttpsTrafficOnly = $true; minimumTlsVersion = 'TLS1_2'; allowBlobPublicAccess = $false; allowSharedKeyAccess = $false; publicNetworkAccess = 'Disabled' } @{ name = 'Standard_ZRS' }
    $stDev = & $row $dev 'rg-dev' 'microsoft.storage/storageaccounts' 'stdev' @{ minimumTlsVersion = 'TLS1_0'; allowBlobPublicAccess = $true; networkAcls = @{ defaultAction = 'Allow' } } @{ name = 'Standard_LRS' }
    $rule = { param($Source, $Port) @{ name = "allow-$Port"; properties = @{ direction = 'Inbound'; access = 'Allow'; sourceAddressPrefix = $Source; destinationPortRange = $Port } } }
    @{
        resources   = @(
            $vmProd, $vmDev, $stProd, $stDev
            & $row $prod 'rg-app' 'microsoft.keyvault/vaults' 'kv-prod' @{ enableSoftDelete = $true; enablePurgeProtection = $true; enableRbacAuthorization = $true; publicNetworkAccess = 'Disabled' }
            & $row $dev 'rg-dev' 'microsoft.network/loadbalancers' 'lb-dev' @{ loadBalancingRules = @(@{ name = 'http' }); probes = @() } @{ name = 'Basic' }
            & $row $prod 'rg-app' 'microsoft.network/networksecuritygroups' 'nsg-prod' @{ securityRules = @(& $rule '10.0.0.0/8' '22') }
            & $row $dev 'rg-dev' 'microsoft.network/networksecuritygroups' 'nsg-dev' @{ securityRules = @(& $rule '*' '3389') }
            & $row $dev 'rg-dev' 'microsoft.compute/disks' 'disk-old' @{ diskState = 'Unattached' }
            & $row $prod 'rg-app' 'microsoft.compute/snapshots' 'snap-2024' @{ timeCreated = '2024-01-01T00:00:00Z' }
        )
        groups      = @(
            @{ id = "/subscriptions/$prod/resourcegroups/rg-app"; name = 'rg-app'; type = 'microsoft.resources/subscriptions/resourcegroups'; resourceGroup = 'rg-app'; subscriptionId = $prod; location = 'uksouth'; tags = @{ Owner = 'app-team'; Environment = 'prod'; CostCenter = 'CC-1' } }
            @{ id = "/subscriptions/$dev/resourcegroups/rg-dev"; name = 'rg-dev'; type = 'microsoft.resources/subscriptions/resourcegroups'; resourceGroup = 'rg-dev'; subscriptionId = $dev; location = 'uksouth'; tags = $null }
        )
        extensions  = @(@{ vm = $vmProd.id; extension = 'AzureMonitorLinuxAgent' })
        autoscale   = @()
        slots       = @()
        inventory   = @(
            @{ type = 'microsoft.storage/storageaccounts'; subscriptionId = $prod; resourceGroup = 'rg-app'; n = 3 }
            @{ type = 'microsoft.compute/virtualmachines'; subscriptionId = $prod; resourceGroup = 'rg-app'; n = 1 }
            @{ type = 'microsoft.insights/metricalerts'; subscriptionId = $prod; resourceGroup = 'rg-monitor'; n = 2 }
            @{ type = 'microsoft.insights/actiongroups'; subscriptionId = $prod; resourceGroup = 'rg-monitor'; n = 1 }
        )
        backup      = @(@{ id = $vmProd.id })
        advisor     = @(
            @{ resourceId = $stProd.id; category = 'HighAvailability'; impact = 'High'; problem = 'Enable soft delete for blobs'; solution = 'Turn on blob soft delete.'; impactedType = 'microsoft.storage/storageaccounts'; typeId = 'abc-123'; subscriptionId = $prod; resourceGroup = 'rg-app' }
            @{ resourceId = $vmDev.id; category = 'HighAvailability'; impact = 'Medium'; problem = 'Use Availability zones for better resiliency and availability'; solution = 'Deploy into zones.'; impactedType = 'microsoft.compute/virtualmachines'; typeId = 'az-1'; subscriptionId = $dev; resourceGroup = 'rg-dev' }
            @{ resourceId = $vmDev.id; category = 'Cost'; impact = 'High'; problem = 'Right-size or shut down underutilized virtual machines'; solution = 'Resize the VM.'; impactedType = 'microsoft.compute/virtualmachines'; typeId = 'cost-1'; subscriptionId = $dev; resourceGroup = 'rg-dev' }
        )
        pricing     = @(
            @{ subscriptionId = $prod; name = 'VirtualMachines'; tier = 'Standard' }, @{ subscriptionId = $prod; name = 'StorageAccounts'; tier = 'Standard' }, @{ subscriptionId = $prod; name = 'CloudPosture'; tier = 'Free' }
            @{ subscriptionId = $dev; name = 'VirtualMachines'; tier = 'Free' }, @{ subscriptionId = $dev; name = 'StorageAccounts'; tier = 'Free' }, @{ subscriptionId = $dev; name = 'CloudPosture'; tier = 'Free' }
        )
        secureScore = @(@{ subscriptionId = $prod; current = 8.0; max = 10.0 }, @{ subscriptionId = $dev; current = 4.0; max = 10.0 })
        assessments = @(
            @{ resourceId = $vmProd.id; name = 'Machines should have vulnerability findings resolved'; status = 'Healthy'; remediation = 'Fix the findings.'; subscriptionId = $prod; resourceGroup = 'rg-app' }
            @{ resourceId = $vmDev.id; name = 'Machines should have vulnerability findings resolved'; status = 'Unhealthy'; remediation = 'Fix the findings.'; subscriptionId = $dev; resourceGroup = 'rg-dev' }
            @{ resourceId = $stDev.id; name = 'Storage account public access should be disallowed'; status = 'Unhealthy'; remediation = 'Disallow public access.'; subscriptionId = $dev; resourceGroup = 'rg-dev' }
        )
    }
}

function Get-AACContosoWafScope {
    @{
        Subscriptions = @(@{ subscriptionId = '11111111-1111-1111-1111-111111111111'; name = 'Contoso Prod' }, @{ subscriptionId = '22222222-2222-2222-2222-222222222222'; name = 'Contoso Dev' })
        Ids           = @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
        GraphScope    = @()
        Names         = @{ '11111111-1111-1111-1111-111111111111' = 'Contoso Prod'; '22222222-2222-2222-2222-222222222222' = 'Contoso Dev' }
        Label         = 'all 2 subscription(s)'
    }
}
