<#
    A made-up Contoso Application Gateway for ApplicationGateway.Tests.ps1,
    as Resource Graph, Azure Monitor and the backend health check return it.

      appgw-prod  WAF_v2, zones 1-3, autoscale 2-10, TLS AppGwSslPolicy20150501,
                  WAF policy waf-prod (Detection, OWASP 3.1), in vnet-hub/snet-appgw
        fe-public (pip-appgw 20.0.0.1), ports 80, 443, 8080
        https-shop  Https 443 shop.contoso.com, cert-shop (uploaded, expired)
                    -> rule-shop (100, path-based, pm-shop)
                         /api/*    -> be-api (Https 443, probe-api, draining) -> pool-api: vm-api-1 (NIC), app-api (App Service)
                         (default) -> be-web (Http 80, no probe)            -> pool-web: 10.1.2.10, 10.1.2.11
        http-shop   Http 80   -> rule-redirect (110) -> rd-https -> https-shop
        http-legacy Http 8080 -> rule-legacy (120)   -> be-web -> pool-web   (plain HTTP, not redirected)
        https-old   no rule; pool-empty, probe-unused: nothing uses them
    Health: metrics - pool-api 2 healthy; pool-web 1 healthy, 1 unhealthy.
    Live - 10.1.2.11 unhealthy (timeout), the rest healthy.
#>
function Get-AACContosoApplicationGateway {
    $sub = '11111111-1111-1111-1111-111111111111'
    $rg = "/subscriptions/$sub/resourceGroups/rg-edge/providers/Microsoft.Network"
    $gw = "$rg/applicationGateways/appgw-prod"
    $sid = { param([string] $Kind, [string] $Name) @{ id = "$gw/$Kind/$Name" } }
    $item = { param([string] $Kind, [string] $Name, [hashtable] $Properties) @{ id = "$gw/$Kind/$Name"; name = $Name; properties = $Properties } }
    # An expired self-signed certificate, as publicCertData carries it (PKCS#7).
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=shop.contoso.com', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $request.CreateSelfSigned([datetimeoffset]::UtcNow.AddDays(-400), [datetimeoffset]::UtcNow.AddDays(-5))
    $collection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new($cert)
    $certData = [Convert]::ToBase64String($collection.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs7))
    $vnet = '/subscriptions/' + $sub + '/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub'
    $nic = "/subscriptions/$sub/resourceGroups/rg-api/providers/Microsoft.Network/networkInterfaces/nic-api-1"
    $waf = "$rg/ApplicationGatewayWebApplicationFirewallPolicies/waf-prod"
    $gateway = @{
        id = $gw.ToLowerInvariant(); name = 'appgw-prod'; location = 'uksouth'; resourceGroup = 'rg-edge'; subscriptionId = $sub; zones = @('1', '2', '3'); tags = $null
        properties = @{
            sku = @{ name = 'WAF_v2'; tier = 'WAF_v2' }; autoscaleConfiguration = @{ minCapacity = 2; maxCapacity = 10 }; operationalState = 'Running'; enableHttp2 = $true
            sslPolicy = @{ policyType = 'Predefined'; policyName = 'AppGwSslPolicy20150501' }; firewallPolicy = @{ id = $waf }
            gatewayIPConfigurations = @(@{ name = 'gwip'; properties = @{ subnet = @{ id = "$vnet/subnets/snet-appgw" } } })
            frontendIPConfigurations = @(& $item 'frontendIPConfigurations' 'fe-public' @{ publicIPAddress = @{ id = "$rg/publicIPAddresses/pip-appgw" } })
            frontendPorts = @((& $item 'frontendPorts' 'p80' @{ port = 80 }), (& $item 'frontendPorts' 'p443' @{ port = 443 }), (& $item 'frontendPorts' 'p8080' @{ port = 8080 }))
            sslCertificates = @(& $item 'sslCertificates' 'cert-shop' @{ publicCertData = $certData })
            httpListeners = @(
                & $item 'httpListeners' 'https-shop' @{ protocol = 'Https'; hostNames = @('shop.contoso.com'); frontendIPConfiguration = (& $sid 'frontendIPConfigurations' 'fe-public'); frontendPort = (& $sid 'frontendPorts' 'p443'); sslCertificate = (& $sid 'sslCertificates' 'cert-shop') }
                & $item 'httpListeners' 'http-shop' @{ protocol = 'Http'; hostNames = @('shop.contoso.com'); frontendIPConfiguration = (& $sid 'frontendIPConfigurations' 'fe-public'); frontendPort = (& $sid 'frontendPorts' 'p80') }
                & $item 'httpListeners' 'http-legacy' @{ protocol = 'Http'; frontendIPConfiguration = (& $sid 'frontendIPConfigurations' 'fe-public'); frontendPort = (& $sid 'frontendPorts' 'p8080') }
                & $item 'httpListeners' 'https-old' @{ protocol = 'Https'; hostNames = @('old.contoso.com'); frontendIPConfiguration = (& $sid 'frontendIPConfigurations' 'fe-public'); frontendPort = (& $sid 'frontendPorts' 'p443'); sslCertificate = (& $sid 'sslCertificates' 'cert-shop') }
            )
            backendHttpSettingsCollection = @(
                & $item 'backendHttpSettingsCollection' 'be-api' @{ protocol = 'Https'; port = 443; requestTimeout = 30; pickHostNameFromBackendAddress = $true; cookieBasedAffinity = 'Disabled'; probe = (& $sid 'probes' 'probe-api'); connectionDraining = @{ enabled = $true; drainTimeoutInSec = 60 } }
                & $item 'backendHttpSettingsCollection' 'be-web' @{ protocol = 'Http'; port = 80; requestTimeout = 20; cookieBasedAffinity = 'Enabled' }
            )
            probes = @(
                & $item 'probes' 'probe-api' @{ protocol = 'Https'; path = '/health'; interval = 30; timeout = 30; unhealthyThreshold = 3; pickHostNameFromBackendHttpSettings = $true; match = @{ statusCodes = @('200-399') } }
                & $item 'probes' 'probe-unused' @{ protocol = 'Http'; host = 'x.contoso.com'; path = '/'; interval = 30; timeout = 30; unhealthyThreshold = 3 }
            )
            backendAddressPools = @(
                & $item 'backendAddressPools' 'pool-api' @{ backendAddresses = @(@{ fqdn = 'app-api.azurewebsites.net' }); backendIPConfigurations = @(@{ id = "$nic/ipConfigurations/ipconfig1" }) }
                & $item 'backendAddressPools' 'pool-web' @{ backendAddresses = @(@{ ipAddress = '10.1.2.10' }, @{ ipAddress = '10.1.2.11' }) }
                & $item 'backendAddressPools' 'pool-empty' @{ backendAddresses = @() }
            )
            redirectConfigurations = @(& $item 'redirectConfigurations' 'rd-https' @{ redirectType = 'Permanent'; targetListener = (& $sid 'httpListeners' 'https-shop'); includePath = $true; includeQueryString = $true })
            urlPathMaps = @(& $item 'urlPathMaps' 'pm-shop' @{
                    defaultBackendAddressPool = (& $sid 'backendAddressPools' 'pool-web'); defaultBackendHttpSettings = (& $sid 'backendHttpSettingsCollection' 'be-web')
                    pathRules = @(& $item 'urlPathMaps/pm-shop/pathRules' 'api' @{ paths = @('/api/*'); backendAddressPool = (& $sid 'backendAddressPools' 'pool-api'); backendHttpSettings = (& $sid 'backendHttpSettingsCollection' 'be-api') })
                })
            requestRoutingRules = @(
                & $item 'requestRoutingRules' 'rule-legacy' @{ ruleType = 'Basic'; priority = 120; httpListener = (& $sid 'httpListeners' 'http-legacy'); backendAddressPool = (& $sid 'backendAddressPools' 'pool-web'); backendHttpSettings = (& $sid 'backendHttpSettingsCollection' 'be-web') }
                & $item 'requestRoutingRules' 'rule-shop' @{ ruleType = 'PathBasedRouting'; priority = 100; httpListener = (& $sid 'httpListeners' 'https-shop'); urlPathMap = (& $sid 'urlPathMaps' 'pm-shop') }
                & $item 'requestRoutingRules' 'rule-redirect' @{ ruleType = 'Basic'; priority = 110; httpListener = (& $sid 'httpListeners' 'http-shop'); redirectConfiguration = (& $sid 'redirectConfigurations' 'rd-https') }
            )
        }
    }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    @{
        Gateways = @($gateway)
        Subscriptions = @(@{ subscriptionId = $sub; name = 'Contoso Prod' })
        Related  = @(
            @{ id = & $lower "$rg/publicIPAddresses/pip-appgw"; name = 'pip-appgw'; type = 'microsoft.network/publicipaddresses'; resourceGroup = 'rg-edge'; subscriptionId = $sub; properties = @{ ipAddress = '20.0.0.1' } }
            @{ id = & $lower $waf; name = 'waf-prod'; type = 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies'; resourceGroup = 'rg-edge'; subscriptionId = $sub; properties = @{ policySettings = @{ mode = 'Detection'; state = 'Enabled' }; managedRules = @{ managedRuleSets = @(@{ ruleSetType = 'OWASP'; ruleSetVersion = '3.1' }) }; customRules = @() } }
            @{ id = & $lower $vnet; name = 'vnet-hub'; type = 'microsoft.network/virtualnetworks'; resourceGroup = 'rg-hub'; subscriptionId = $sub; properties = @{ addressSpace = @{ addressPrefixes = @('10.0.0.0/16') }; subnets = @(@{ id = "$vnet/subnets/snet-appgw"; name = 'snet-appgw'; properties = @{ addressPrefix = '10.0.5.0/24'; networkSecurityGroup = @{ id = "$rg/networkSecurityGroups/nsg-appgw" } } }) } }
            @{ id = & $lower $nic; name = 'nic-api-1'; type = 'microsoft.network/networkinterfaces'; resourceGroup = 'rg-api'; subscriptionId = $sub; properties = @{ virtualMachine = @{ id = "/subscriptions/$sub/resourceGroups/rg-api/providers/Microsoft.Compute/virtualMachines/vm-api-1" }; ipConfigurations = @(@{ id = "$nic/ipConfigurations/ipconfig1"; properties = @{ privateIPAddress = '10.1.1.4' } }) } }
        )
        Sites    = @(@{ id = "/subscriptions/$sub/resourcegroups/rg-api/providers/microsoft.web/sites/app-api"; name = 'app-api'; type = 'microsoft.web/sites'; resourceGroup = 'rg-api'; subscriptionId = $sub; host = 'app-api.azurewebsites.net'; kind = 'app' })
        Metrics  = @{ value = @(
                @{ name = @{ value = 'HealthyHostCount' }; timeseries = @(
                        @{ metadatavalues = @(@{ name = @{ value = 'backendsettingspool' }; value = 'pool-api~be-api' }); data = @(@{ average = 2 }) }
                        @{ metadatavalues = @(@{ name = @{ value = 'backendsettingspool' }; value = 'pool-web~be-web' }); data = @(@{ average = 1 }) }) }
                @{ name = @{ value = 'UnhealthyHostCount' }; timeseries = @(
                        @{ metadatavalues = @(@{ name = @{ value = 'backendsettingspool' }; value = 'pool-api~be-api' }); data = @(@{ average = 0 }) }
                        @{ metadatavalues = @(@{ name = @{ value = 'backendsettingspool' }; value = 'pool-web~be-web' }); data = @(@{ average = 1 }) }) }
            ) }
        Live     = @{ backendAddressPools = @(
                @{ backendAddressPool = @{ id = "$gw/backendAddressPools/pool-api" }; backendHttpSettingsCollection = @(@{ backendHttpSettings = @{ id = "$gw/backendHttpSettingsCollection/be-api" }; servers = @(@{ address = '10.1.1.4'; health = 'Healthy' }, @{ address = 'app-api.azurewebsites.net'; health = 'Healthy' }) }) }
                @{ backendAddressPool = @{ id = "$gw/backendAddressPools/pool-web" }; backendHttpSettingsCollection = @(@{ backendHttpSettings = @{ id = "$gw/backendHttpSettingsCollection/be-web" }; servers = @(@{ address = '10.1.2.10'; health = 'Healthy' }, @{ address = '10.1.2.11'; health = 'Unhealthy'; healthProbeLog = 'Time taken by the backend to respond to application gateway''s health probe is more than the timeout threshold.' }) }) }
            ) }
    }
}
