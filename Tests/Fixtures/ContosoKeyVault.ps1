<#
    Made-up Contoso Key Vaults for KeyVaultInsight.Tests.ps1, as Resource
    Graph, Azure Monitor metrics, diagnostic settings, Log Analytics and the
    Key Vault data plane return them.

      kv-prod (Contoso Prod, rg-app)  purge protection, RBAC, private; audit
                                      logs to law-prod (AZKVAuditLogs);
                                      1,000 transactions: 900 OK, 50 x 401,
                                      20 x 403, 30 x 429; saturation up to 80%;
                                      secrets: db-password expiring in 10
                                      days, web-tls (managed, left out); keys:
                                      cmk, no expiry; certificates: web-tls,
                                      expired; app-2 denied 25 times in the logs
      kv-dev  (Contoso Dev, rg-dev)   no purge protection, access policies,
                                      public, no audit logs, idle; its data
                                      plane denies the account
    Defender for Key Vault: on in Prod, off in Dev.
#>
function Get-AACContosoKeyVault {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $vault = { param($Sub, $Group, $Name, $Properties) @{ id = "/subscriptions/$Sub/resourcegroups/$Group/providers/microsoft.keyvault/vaults/$Name"; name = $Name; location = 'uksouth'; resourceGroup = $Group; subscriptionId = $Sub; sku = 'standard'; tags = $null; properties = $Properties } }
    $kvProd = & $vault $prod 'rg-app' 'kv-prod' @{ vaultUri = 'https://kv-prod.vault.azure.net/'; enableSoftDelete = $true; enablePurgeProtection = $true; enableRbacAuthorization = $true; publicNetworkAccess = 'Disabled'; privateEndpointConnections = @(@{ properties = @{ privateLinkServiceConnectionState = @{ status = 'Approved' } } }) }
    $kvDev = & $vault $dev 'rg-dev' 'kv-dev' @{ vaultUri = 'https://kv-dev.vault.azure.net/'; enableSoftDelete = $true; networkAcls = @{ defaultAction = 'Allow' } }
    $workspace = "/subscriptions/$prod/resourcegroups/rg-monitor/providers/microsoft.operationalinsights/workspaces/law-prod"
    $point = { param($Average, $Total, $Maximum) @{ timeStamp = '2026-10-15T10:00:00Z'; average = $Average; total = $Total; maximum = $Maximum } }
    $metric = { param($Name, [object[]] $Series) @{ name = @{ value = $Name }; timeseries = $Series } }
    $plain = { param([object[]] $Data) @{ metadatavalues = @(); data = $Data } }
    $split = { param($Dimension, $Value, [object[]] $Data) @{ metadatavalues = @(@{ name = @{ value = $Dimension }; value = $Value }); data = $Data } }
    $exp = { param([int] $Days) [DateTimeOffset]::new([datetime]::UtcNow.AddDays($Days)).ToUnixTimeSeconds() }
    @{
        Graph     = @{
            vaults     = @($kvProd, $kvDev)
            pricing    = @(@{ subscriptionId = $prod; tier = 'Standard' }, @{ subscriptionId = $dev; tier = 'Free' })
            alerts     = @()
            workspaces = @(@{ id = $workspace; name = 'law-prod'; customerId = 'cust-1' })
        }
        Metrics   = @{
            "$($kvProd.id)|Core"    = @{ value = @(
                    & $metric 'Availability' @(& $plain @((& $point 99.99 $null $null), (& $point 99.97 $null $null)))
                    & $metric 'ServiceApiHit' @(& $plain @((& $point $null 600 $null), (& $point $null 400 $null)))
                    & $metric 'ServiceApiLatency' @(& $plain @((& $point 20 $null 90), (& $point 30 $null 120)))
                    & $metric 'SaturationShoebox' @(& $plain @((& $point 40 $null 80), (& $point 30 $null 55)))
                ) }
            "$($kvProd.id)|Results" = @{ value = @(& $metric 'ServiceApiResult' @(
                        (& $split 'statuscode' '200' @(& $point $null 900 $null)), (& $split 'statuscode' '401' @(& $point $null 50 $null))
                        (& $split 'statuscode' '403' @(& $point $null 20 $null)), (& $split 'statuscode' '429' @(& $point $null 30 $null))
                    )) }
            "$($kvProd.id)|Types"   = @{ value = @(& $metric 'ServiceApiHit' @((& $split 'activitytype' 'SecretGet' @(& $point $null 800 $null)), (& $split 'activitytype' 'KeyGet' @(& $point $null 200 $null)))) }
            "$($kvDev.id)|Core"     = @{ value = @(& $metric 'Availability' @(& $plain @()); & $metric 'ServiceApiHit' @(& $plain @(& $point $null 0 $null))) }
            "$($kvDev.id)|Results"  = @{ value = @() }
            "$($kvDev.id)|Types"    = @{ value = @() }
        }
        Settings  = @{
            $kvProd.id = @(@{ name = 'to-law'; properties = @{ workspaceId = $workspace; logAnalyticsDestinationType = 'Dedicated'; logs = @(@{ categoryGroup = 'audit'; enabled = $true }) } })
            $kvDev.id  = @()
        }
        Logs      = @(
            @{ VaultId = $kvProd.id; Operation = 'SecretGet'; Caller = 'app-1'; CallerIp = '10.0.0.4'; Count = 500; Failed = 0; AuthDenied = 0; Throttled = 0; P99Ms = 45.2 }
            @{ VaultId = $kvProd.id; Operation = 'SecretGet'; Caller = 'app-2'; CallerIp = '10.0.0.9'; Count = 25; Failed = 25; AuthDenied = 25; Throttled = 0; P99Ms = 12.0 }
        )
        DataPlane = @{
            'https://kv-prod.vault.azure.net/secrets'      = @{ value = @(@{ id = 'https://kv-prod.vault.azure.net/secrets/db-password'; attributes = @{ enabled = $true; exp = (& $exp 10) } }, @{ id = 'https://kv-prod.vault.azure.net/secrets/web-tls'; managed = $true; attributes = @{ enabled = $true; exp = (& $exp -5) } }) }
            'https://kv-prod.vault.azure.net/keys'         = @{ value = @(@{ kid = 'https://kv-prod.vault.azure.net/keys/cmk'; attributes = @{ enabled = $true } }) }
            'https://kv-prod.vault.azure.net/certificates' = @{ value = @(@{ id = 'https://kv-prod.vault.azure.net/certificates/web-tls'; attributes = @{ enabled = $true; exp = (& $exp -5) } }) }
        }
        Scope     = @{
            Subscriptions = @(@{ subscriptionId = $prod; name = 'Contoso Prod' }, @{ subscriptionId = $dev; name = 'Contoso Dev' })
            Ids = @($prod, $dev); GraphScope = @(); Label = 'all 2 subscription(s)'
            Names = @{ $prod = 'Contoso Prod'; $dev = 'Contoso Dev' }
        }
    }
}
