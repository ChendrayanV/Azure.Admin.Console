<#
    A made-up Contoso estate for AttackPath.Tests.ps1, as Azure Resource
    Graph returns it (Get-AACAttackPathQuery's queries):

      vm-jump    public IP, NSG on its NIC allows RDP 3389 from the Internet;
                 its system identity is Contributor on sub-prod, and reads
                 kv-app's secrets (access policy)            -> Critical
      vm-web     public IP, subnet NSG: SSH denied (100) before it's allowed
                 (200), HTTPS allowed                         -> Medium (443 only)
      vm-basic   Basic public IP, no NSG                      -> High (every port)
      vm-closed  Standard public IP, no NSG                   -> nothing
      app-api    public, user-assigned id-api: Storage Blob Data Reader
                 on stdata                                    -> High (data)
      app-site   public, no identity                          -> nothing
      aks-dev    public API server, no ranges                 -> Medium
      stpublic   every network, anonymous blob access         -> High
      stdata     networks denied                              -> nothing
      kv-app     every network                                -> Medium
      sql-prod   public network access                        -> Medium
      Defender   one attack path, Critical
    vm-jump and vm-web share vnet-hub; sub-prod has 15 resources.
#>
function Get-AACContosoAttack {
    $sub = '11111111-1111-1111-1111-111111111111'
    $rg = { param([string] $Group) "/subscriptions/$sub/resourcegroups/$Group" }
    $res = { param([string] $Group, [string] $Type, [string] $Name) "$(& $rg $Group)/providers/$Type/$Name" }
    $rule = { param([string] $Name, [int] $Priority, [string] $Access, [string] $Source, [string] $Port) @{ name = $Name; properties = @{ direction = 'Inbound'; access = $Access; priority = $Priority; protocol = 'Tcp'; sourceAddressPrefix = $Source; destinationPortRange = $Port } } }
    $nic = { param([string] $Vm, [string] $Nsg, [string] $Subnet, [string] $Ip) @{ id = (& $res 'rg-app' 'microsoft.network/networkinterfaces' "$Vm-nic"); vm = (& $res 'rg-app' 'microsoft.compute/virtualmachines' $Vm); nsg = $Nsg; ipConfigs = @(@{ id = "$(& $res 'rg-app' 'microsoft.network/networkinterfaces' "$Vm-nic")/ipconfigurations/ipconfig1"; properties = @{ subnet = @{ id = $Subnet } } }) } }
    $ipFor = { param([string] $Vm, [string] $Sku, [string] $Address) @{ id = (& $res 'rg-app' 'microsoft.network/publicipaddresses' "$Vm-ip"); name = "$Vm-ip"; ip = $Address; sku = $Sku; attachedTo = "$(& $res 'rg-app' 'microsoft.network/networkinterfaces' "$Vm-nic")/ipconfigurations/ipconfig1" } }
    $vnetHub = & $res 'rg-net' 'microsoft.network/virtualnetworks' 'vnet-hub'
    $vnetOther = & $res 'rg-net' 'microsoft.network/virtualnetworks' 'vnet-other'
    $nsgJump = & $res 'rg-app' 'microsoft.network/networksecuritygroups' 'nsg-jump'
    $nsgWeb = & $res 'rg-net' 'microsoft.network/networksecuritygroups' 'nsg-web'
    $vm = { param([string] $Name, $Identity) @{ id = (& $res 'rg-app' 'microsoft.compute/virtualmachines' $Name); name = $Name; resourceGroup = 'rg-app'; subscriptionId = $sub; identity = $Identity } }
    $roleId = { param([string] $Guid) "/subscriptions/$sub/providers/microsoft.authorization/roledefinitions/$Guid" }
    $stdata = & $res 'rg-data' 'microsoft.storage/storageaccounts' 'stdata'
    @{
        Subscription = $sub
        Names        = @{ $sub = 'sub-prod' }
        Chain        = @{ $sub = @('mg-prod', 'contoso') }
        Read         = @{
            Errors = @{}
            Rows   = @{
                publicIps       = @((& $ipFor 'vm-jump' 'Standard' '20.0.0.1'), (& $ipFor 'vm-web' 'Standard' '20.0.0.2'), (& $ipFor 'vm-basic' 'Basic' '20.0.0.3'), (& $ipFor 'vm-closed' 'Standard' '20.0.0.4'))
                nics            = @((& $nic 'vm-jump' $nsgJump "$vnetHub/subnets/snet-jump" ''), (& $nic 'vm-web' '' "$vnetHub/subnets/snet-web" ''), (& $nic 'vm-basic' '' "$vnetOther/subnets/snet-a" ''), (& $nic 'vm-closed' '' "$vnetOther/subnets/snet-b" ''))
                nsgs            = @(
                    @{ id = $nsgJump; name = 'nsg-jump'; rules = @((& $rule 'rdp' 100 'Allow' 'Internet' '3389')) }
                    @{ id = $nsgWeb; name = 'nsg-web'; rules = @((& $rule 'no-ssh' 100 'Deny' '*' '22'), (& $rule 'ssh' 200 'Allow' 'Internet' '22'), (& $rule 'https' 300 'Allow' '*' '443')) }
                )
                subnets         = @(
                    @{ id = "$vnetHub/subnets/snet-jump"; nsg = ''; vnet = $vnetHub }
                    @{ id = "$vnetHub/subnets/snet-web"; nsg = $nsgWeb; vnet = $vnetHub }
                    @{ id = "$vnetOther/subnets/snet-a"; nsg = ''; vnet = $vnetOther }
                    @{ id = "$vnetOther/subnets/snet-b"; nsg = ''; vnet = $vnetOther }
                )
                vms             = @((& $vm 'vm-jump' @{ type = 'SystemAssigned'; principalId = 'p-jump' }), (& $vm 'vm-web' $null), (& $vm 'vm-basic' $null), (& $vm 'vm-closed' $null))
                apps            = @(
                    @{ id = (& $res 'rg-app' 'microsoft.web/sites' 'app-api'); name = 'app-api'; kind = 'app'; resourceGroup = 'rg-app'; subscriptionId = $sub; publicAccess = ''; hostname = 'app-api.azurewebsites.net'; identity = @{ type = 'UserAssigned'; userAssignedIdentities = @{ (& $res 'rg-app' 'microsoft.managedidentity/userassignedidentities' 'id-api') = @{ principalId = $null } } } }
                    @{ id = (& $res 'rg-app' 'microsoft.web/sites' 'app-site'); name = 'app-site'; kind = 'app'; resourceGroup = 'rg-app'; subscriptionId = $sub; publicAccess = 'Enabled'; hostname = 'app-site.azurewebsites.net'; identity = $null }
                )
                clusters        = @(@{ id = (& $res 'rg-aks' 'microsoft.containerservice/managedclusters' 'aks-dev'); name = 'aks-dev'; resourceGroup = 'rg-aks'; subscriptionId = $sub; private = $false; ranges = $null; identity = @{ principalId = 'p-aks' }; kubelet = 'p-kubelet' })
                stores          = @(
                    @{ id = (& $res 'rg-data' 'microsoft.storage/storageaccounts' 'stpublic'); name = 'stpublic'; type = 'microsoft.storage/storageaccounts'; resourceGroup = 'rg-data'; subscriptionId = $sub; publicAccess = ''; defaultAction = 'Allow'; blobPublic = 'true'; accessPolicies = $null }
                    @{ id = $stdata; name = 'stdata'; type = 'microsoft.storage/storageaccounts'; resourceGroup = 'rg-data'; subscriptionId = $sub; publicAccess = 'Enabled'; defaultAction = 'Deny'; blobPublic = 'false'; accessPolicies = $null }
                    @{ id = (& $res 'rg-data' 'microsoft.keyvault/vaults' 'kv-app'); name = 'kv-app'; type = 'microsoft.keyvault/vaults'; resourceGroup = 'rg-data'; subscriptionId = $sub; publicAccess = ''; defaultAction = 'Allow'; blobPublic = ''; accessPolicies = @(@{ objectId = 'p-jump'; permissions = @{ secrets = @('get', 'list') } }) }
                    @{ id = (& $res 'rg-data' 'microsoft.sql/servers' 'sql-prod'); name = 'sql-prod'; type = 'microsoft.sql/servers'; resourceGroup = 'rg-data'; subscriptionId = $sub; publicAccess = 'Enabled'; defaultAction = ''; blobPublic = ''; accessPolicies = $null }
                )
                identities      = @(@{ id = (& $res 'rg-app' 'microsoft.managedidentity/userassignedidentities' 'id-api'); name = 'id-api'; principalId = 'p-api' })
                roleAssignments = @(
                    @{ id = 'ra1'; principalId = 'p-jump'; principalType = 'ServicePrincipal'; roleId = (& $roleId 'b24988ac-6180-42a0-ab88-20f7382dd24c'); scope = "/subscriptions/$sub" }
                    @{ id = 'ra2'; principalId = 'p-api'; principalType = 'ServicePrincipal'; roleId = (& $roleId '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'); scope = $stdata }
                    @{ id = 'ra3'; principalId = 'p-kubelet'; principalType = 'ServicePrincipal'; roleId = (& $roleId '7f951dda-4ed3-4680-a7ca-43fe172d538d'); scope = (& $rg 'rg-aks') }
                    @{ id = 'ra4'; principalId = 'u-ada'; principalType = 'User'; roleId = (& $roleId '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'); scope = "/subscriptions/$sub" }
                )
                roleDefinitions = @(
                    @{ id = '/providers/microsoft.authorization/roledefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; roleName = 'Owner'; roleType = 'BuiltInRole'; permissions = @(@{ actions = @('*') }) }
                    @{ id = '/providers/microsoft.authorization/roledefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'; roleName = 'Contributor'; roleType = 'BuiltInRole'; permissions = @(@{ actions = @('*'); notActions = @('Microsoft.Authorization/*/Write') }) }
                    @{ id = '/providers/microsoft.authorization/roledefinitions/2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'; roleName = 'Storage Blob Data Reader'; roleType = 'BuiltInRole'; permissions = @(@{ actions = @('Microsoft.Storage/storageAccounts/blobServices/containers/read'); dataActions = @('Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read') }) }
                    @{ id = '/providers/microsoft.authorization/roledefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d'; roleName = 'AcrPull'; roleType = 'BuiltInRole'; permissions = @(@{ actions = @('Microsoft.ContainerRegistry/registries/pull/read') }) }
                )
                counts          = @(@{ id = "$sub/rg-app"; subscriptionId = $sub; resourceGroup = 'rg-app'; resources = 10 }, @{ id = "$sub/rg-data"; subscriptionId = $sub; resourceGroup = 'rg-data'; resources = 5 })
                defender        = @(@{ id = 'ap1'; subscriptionId = $sub; properties = @{ displayName = 'Internet exposed VM with high privileges'; riskLevel = 'Critical'; description = 'vm-jump is reachable from the Internet and its identity can write to the subscription.'; riskCategories = @('Exposure', 'Privilege escalation'); graphComponent = @{ entities = @(@{ entityName = 'Internet' }, @{ entityName = 'vm-jump'; entityId = (& $res 'rg-app' 'microsoft.compute/virtualmachines' 'vm-jump') }, @{ entityName = 'sub-prod'; entityId = "/subscriptions/$sub" }) } } })
            }
        }
    }
}
