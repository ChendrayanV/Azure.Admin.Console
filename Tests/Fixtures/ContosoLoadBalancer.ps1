<#
    Made-up balancers for LoadBalancerHealth.Tests.ps1, as Azure Resource
    Graph (Get-AACLoadBalancerQuery) and Azure Monitor return them:

      lb-web     Standard; pool web: vm-web1 (probe 100%), vm-web2 (0%);
                 data path 100%                          -> Degraded
      lb-api     Standard; pool api: vm-api (0%); data path 80%; its rule
                 has no probe                            -> Unhealthy
      lb-old     Basic; pool with vm-old (no metrics)    -> Unknown
      agw-v2     Standard_v2, autoscale min 1; pool app (2 addresses: 1
                 healthy, 1 unhealthy host), pool empty  -> Degraded
      tm-global  endpoints ep-eu Online, ep-us Degraded, ep-asia Disabled
                                                         -> Degraded
      lb-other   a subscription not in scope             -> left out
#>
function Get-AACContosoLoadBalancer {
    $sub = '11111111-1111-1111-1111-111111111111'
    $other = '99999999-9999-9999-9999-999999999999'
    $res = { param([string] $Type, [string] $Name, [string] $Sub = $sub) "/subscriptions/$Sub/resourcegroups/rg-net/providers/$Type/$Name" }
    $lbId = { param([string] $Name, [string] $Sub = $sub) & $res 'microsoft.network/loadbalancers' $Name $Sub }
    $config = { param([string] $Vm) "$(& $res 'microsoft.network/networkinterfaces' "$Vm-nic")/ipconfigurations/ipconfig1" }
    $lb = {
        param([string] $Name, [string] $Sku, [string[]] $Vms, [bool] $Probe = $true, [string] $Sub = $sub)
        $id = & $lbId $Name $Sub
        @{
            id = $id; name = $Name; resourceGroup = 'rg-net'; subscriptionId = $Sub; location = 'westeurope'; sku = $Sku; frontends = 1
            pools = @(@{ id = "$id/backendaddresspools/pool"; name = 'pool'; properties = @{ backendIPConfigurations = @($Vms | ForEach-Object { @{ id = (& $config $_) } }) } })
            probes = @(@{ id = "$id/probes/http"; name = 'http'; properties = @{ protocol = 'Http'; port = 80; requestPath = '/health' } })
            rules = @(@{ name = 'rule'; properties = @{ backendAddressPool = @{ id = "$id/backendaddresspools/pool" }; probe = $(if ($Probe) { @{ id = "$id/probes/http" } } else { $null }) } })
        }
    }
    $series = { param([string] $Dimension, [string] $Value, [double] $Average) @{ metadatavalues = @(if ($Dimension) { @{ name = @{ value = $Dimension }; value = $Value } }); data = @(@{ timeStamp = '2026-10-11T08:00:00Z'; average = 50 }, @{ timeStamp = '2026-10-11T08:01:00Z'; average = $null }, @{ timeStamp = '2026-10-11T08:02:00Z'; average = $Average }) } }
    $metric = { param([string] $Name, [object[]] $Series) @{ value = @(@{ name = @{ value = $Name }; timeseries = $Series }) } }
    $agw = & $res 'microsoft.network/applicationgateways' 'agw-v2'

    @{
        Subscription = $sub
        Names        = @{ $sub = 'sub-prod' }
        Read         = @{
            Errors = @{}
            Rows   = @{
                loadBalancers  = @(
                    (& $lb 'lb-web' 'Standard' @('vm-web1', 'vm-web2'))
                    (& $lb 'lb-api' 'Standard' @('vm-api') $false)
                    (& $lb 'lb-old' 'Basic' @('vm-old'))
                    (& $lb 'lb-other' 'Standard' @('vm-x') $true $other)
                )
                appGateways    = @(@{
                        id = $agw; name = 'agw-v2'; resourceGroup = 'rg-net'; subscriptionId = $sub; location = 'westeurope'; sku = 'Standard_v2'; tier = 'Standard_v2'; capacity = 0; minCapacity = 1; maxCapacity = 3; state = 'Running'; zones = @()
                        pools = @(@{ name = 'app'; properties = @{ backendAddresses = @(@{ fqdn = 'app1.contoso.com' }, @{ fqdn = 'app2.contoso.com' }) } }, @{ name = 'empty'; properties = @{ backendAddresses = @() } }); settings = @(); probes = @(); rules = 2
                    })
                trafficManager = @(@{
                        id = (& $res 'microsoft.network/trafficmanagerprofiles' 'tm-global'); name = 'tm-global'; resourceGroup = 'rg-net'; subscriptionId = $sub; location = 'global'; status = 'Enabled'; routing = 'Priority'; monitor = 'Degraded'; monitorProtocol = 'HTTPS'; monitorPort = 443; monitorPath = '/health'
                        endpoints = @(
                            @{ name = 'ep-eu'; properties = @{ target = 'eu.contoso.com'; endpointStatus = 'Enabled'; endpointMonitorStatus = 'Online' } }
                            @{ name = 'ep-us'; properties = @{ target = 'us.contoso.com'; endpointStatus = 'Enabled'; endpointMonitorStatus = 'Degraded' } }
                            @{ name = 'ep-asia'; properties = @{ target = 'asia.contoso.com'; endpointStatus = 'Disabled'; endpointMonitorStatus = 'Disabled' } }
                        )
                    })
                backendNics    = @(
                    @{ id = (& $config 'vm-web1'); ip = '10.0.0.4'; vm = (& $res 'microsoft.compute/virtualmachines' 'vm-web1'); nic = 'vm-web1-nic' }
                    @{ id = (& $config 'vm-web2'); ip = '10.0.0.5'; vm = (& $res 'microsoft.compute/virtualmachines' 'vm-web2'); nic = 'vm-web2-nic' }
                    @{ id = (& $config 'vm-api'); ip = '10.0.1.4'; vm = (& $res 'microsoft.compute/virtualmachines' 'vm-api'); nic = 'vm-api-nic' }
                    @{ id = (& $config 'vm-old'); ip = '10.0.2.4'; vm = ''; nic = 'vm-old-nic' }
                )
            }
        }
        Metric       = @{
            (& $lbId 'lb-web') = @{ Error = ''; Hosts = $null; Dip = (& $metric 'DipAvailability' @((& $series 'BackendIPAddress' '10.0.0.4' 100), (& $series 'BackendIPAddress' '10.0.0.5' 0))); Vip = (& $metric 'VipAvailability' @((& $series '' '' 100))) }
            (& $lbId 'lb-api') = @{ Error = ''; Hosts = $null; Dip = (& $metric 'DipAvailability' @((& $series 'BackendIPAddress' '10.0.1.4' 0))); Vip = (& $metric 'VipAvailability' @((& $series '' '' 80))) }
            $agw               = @{ Error = ''; Dip = $null; Vip = $null; Hosts = @{ value = @(
                        @{ name = @{ value = 'HealthyHostCount' }; timeseries = @((& $series 'BackendSettingsPool' 'app~settings1' 1)) }
                        @{ name = @{ value = 'UnhealthyHostCount' }; timeseries = @((& $series 'BackendSettingsPool' 'app~settings1' 1)) }
                    ) }
            }
        }
    }
}
