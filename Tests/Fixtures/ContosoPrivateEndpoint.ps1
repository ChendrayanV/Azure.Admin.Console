<#
    Made-up private endpoints for PrivateEndpoint.Tests.ps1, as Azure
    Resource Graph (Get-AACPrivateEndpointQuery) and the zone group calls
    return them:

      vnet-hub      Azure DNS                 vnet-spoke  Azure DNS, peered with the hub
      vnet-custom   DNS server 10.0.0.4
      zones         blob (rg-dns, linked to the hub), vault and file (linked
                    to the spoke), and a second blob zone in rg-app linked
                    to nothing
      targets       stdata (public access Disabled), kv-app (Enabled, Allow),
                    sql-srv (Disabled); stgone was deleted

      pe-blob       stdata/blob, zone linked to the peered hub   -> Healthy
      pe-kv         kv-app/vault, zone linked; target public     -> Warning
      pe-sql        sql-srv, Pending, no zone group              -> Failed
      pe-gone       stgone/blob, Disconnected, target deleted    -> Failed
      pe-wrong      stdata/blob registered in the file zone      -> Warning
      pe-custom     stdata/blob in vnet-custom, no zone group    -> Review
      pe-unlinked   stdata/blob in the unlinked blob zone        -> Failed
      pe-unread     its zone groups couldn't be read             -> Healthy (not checked)
      pe-other      a subscription not in scope                  -> left out
#>
function Get-AACContosoPrivateEndpoint {
    $sub = '11111111-1111-1111-1111-111111111111'
    $other = '99999999-9999-9999-9999-999999999999'
    $res = { param([string] $Group, [string] $Type, [string] $Name, [string] $Sub = $sub) "/subscriptions/$Sub/resourcegroups/$Group/providers/$Type/$Name" }
    $vnet = { param([string] $Name) & $res 'rg-net' 'microsoft.network/virtualnetworks' $Name }
    $zone = { param([string] $Group, [string] $Name) & $res $Group 'microsoft.network/privatednszones' $Name }
    $st = & $res 'rg-data' 'microsoft.storage/storageaccounts' 'stdata'
    $kv = & $res 'rg-data' 'microsoft.keyvault/vaults' 'kv-app'
    $sql = & $res 'rg-data' 'microsoft.sql/servers' 'sql-srv'
    $gone = & $res 'rg-data' 'microsoft.storage/storageaccounts' 'stgone'
    $blobHub = & $zone 'rg-dns' 'privatelink.blob.core.windows.net'
    $blobApp = & $zone 'rg-app' 'privatelink.blob.core.windows.net'
    $vaultZone = & $zone 'rg-dns' 'privatelink.vaultcore.azure.net'
    $fileZone = & $zone 'rg-dns' 'privatelink.file.core.windows.net'
    $endpoint = {
        param([string] $Name, [string] $Target, [string] $Group, [string] $Status = 'Approved', [string] $Network = 'vnet-spoke', [string] $Sub = $sub, [string] $Ip = '10.1.0.4')
        @{
            id = (& $res 'rg-app' 'microsoft.network/privateendpoints' $Name $Sub); name = $Name; resourceGroup = 'rg-app'; subscriptionId = $Sub; location = 'westeurope'
            subnet = "$(& $vnet $Network)/subnets/snet-pe"; state = 'Succeeded'
            connections = @(@{ name = "$Name-conn"; properties = @{ privateLinkServiceId = $Target; groupIds = @($Group); privateLinkServiceConnectionState = @{ status = $Status; description = $(if ($Status -eq 'Pending') { 'Please approve' } else { '' }) } } })
            manual = @(); dns = @(@{ fqdn = "$(($Target -split '/')[-1]).$Group.core.windows.net"; ipAddresses = @($Ip) }); nics = @(); ipConfigs = @()
        }
    }
    $zoneGroup = { param([string[]] $ZoneId) @(@{ name = 'default'; properties = @{ privateDnsZoneConfigs = @($ZoneId | ForEach-Object { @{ name = 'cfg'; properties = @{ privateDnsZoneId = $_ } } }) } }) }
    $id = { param([string] $Name) (& $res 'rg-app' 'microsoft.network/privateendpoints' $Name) }

    @{
        Subscription = $sub
        Names        = @{ $sub = 'sub-prod' }
        Read         = @{
            Errors = @{}
            Rows   = @{
                endpoints = @(
                    (& $endpoint 'pe-blob' $st 'blob')
                    (& $endpoint 'pe-kv' $kv 'vault')
                    (& $endpoint 'pe-sql' $sql 'sqlServer' 'Pending')
                    (& $endpoint 'pe-gone' $gone 'blob' 'Disconnected')
                    (& $endpoint 'pe-wrong' $st 'blob')
                    (& $endpoint 'pe-custom' $st 'blob' 'Approved' 'vnet-custom')
                    (& $endpoint 'pe-unlinked' $st 'blob')
                    (& $endpoint 'pe-unread' $st 'blob')
                    (& $endpoint 'pe-other' $st 'blob' 'Approved' 'vnet-spoke' $other)
                )
                zones     = @(
                    @{ id = $blobHub; name = 'privatelink.blob.core.windows.net'; resourceGroup = 'rg-dns'; subscriptionId = $sub; records = 3; links = 1 }
                    @{ id = $blobApp; name = 'privatelink.blob.core.windows.net'; resourceGroup = 'rg-app'; subscriptionId = $sub; records = 1; links = 0 }
                    @{ id = $vaultZone; name = 'privatelink.vaultcore.azure.net'; resourceGroup = 'rg-dns'; subscriptionId = $sub; records = 1; links = 1 }
                    @{ id = $fileZone; name = 'privatelink.file.core.windows.net'; resourceGroup = 'rg-dns'; subscriptionId = $sub; records = 1; links = 1 }
                )
                links     = @(
                    @{ id = "$blobHub/virtualnetworklinks/hub"; zone = $blobHub; vnet = (& $vnet 'vnet-hub'); registration = $false; linkState = 'Completed' }
                    @{ id = "$vaultZone/virtualnetworklinks/spoke"; zone = $vaultZone; vnet = (& $vnet 'vnet-spoke'); registration = $false; linkState = 'Completed' }
                    @{ id = "$fileZone/virtualnetworklinks/spoke"; zone = $fileZone; vnet = (& $vnet 'vnet-spoke'); registration = $false; linkState = 'Completed' }
                )
                vnets     = @(
                    @{ id = (& $vnet 'vnet-hub'); name = 'vnet-hub'; subscriptionId = $sub; dnsServers = @(); peerings = @(@{ properties = @{ remoteVirtualNetwork = @{ id = (& $vnet 'vnet-spoke') } } }) }
                    @{ id = (& $vnet 'vnet-spoke'); name = 'vnet-spoke'; subscriptionId = $sub; dnsServers = $null; peerings = @(@{ properties = @{ remoteVirtualNetwork = @{ id = (& $vnet 'vnet-hub').ToUpperInvariant() } } }) }
                    @{ id = (& $vnet 'vnet-custom'); name = 'vnet-custom'; subscriptionId = $sub; dnsServers = @('10.0.0.4'); peerings = @() }
                )
                targets   = @(
                    @{ id = $st; name = 'stdata'; type = 'microsoft.storage/storageaccounts'; subscriptionId = $sub; publicAccess = 'Disabled'; defaultAction = 'Deny' }
                    @{ id = $kv; name = 'kv-app'; type = 'microsoft.keyvault/vaults'; subscriptionId = $sub; publicAccess = 'Enabled'; defaultAction = 'Allow' }
                    @{ id = $sql; name = 'sql-srv'; type = 'microsoft.sql/servers'; subscriptionId = $sub; publicAccess = 'Disabled'; defaultAction = '' }
                )
            }
        }
        ZoneGroup    = @{
            (& $id 'pe-blob')     = (& $zoneGroup $blobHub)
            (& $id 'pe-kv')       = (& $zoneGroup $vaultZone)
            (& $id 'pe-sql')      = @()
            (& $id 'pe-gone')     = (& $zoneGroup $blobHub)
            (& $id 'pe-wrong')    = (& $zoneGroup $fileZone)
            (& $id 'pe-custom')   = @()
            (& $id 'pe-unlinked') = (& $zoneGroup $blobApp)
            (& $id 'pe-unread')   = $null
        }
    }
}
