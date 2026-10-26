<#
    Made-up Contoso function apps for Invoke-AACFunctionAppAssessment: Resource
    Graph rows (apps, plans, slots, private endpoints, Advisor, Defender),
    Azure Resource Manager answers (configuration, functions, deployment
    center, publishing credentials, backups, authentication, Service
    Connector, diagnostics, health, locks, Activity Log), app settings, and
    Azure Monitor metrics.

      func-orders-prod  Windows, Elastic Premium (EP1, not zone redundant);
                        .NET 6 in-process; HTTPS, TLS 1.2 - but FTP and SCM
                        basic auth allowed, public, CORS *, an anonymous HTTP
                        function; secrets in plain settings and a storage key;
                        8% 5xx, 1.5 s responses; restarted 4 times, settings
                        read; a staging slot; GitHub Actions; Production tag
      func-reports-dev  Linux Consumption (Y1); Python 3.8 (out of support);
                        HTTPS off, TLS 1.0; idle; no Application Insights;
                        functions can't be listed; access restricted
      func-ingest-flex  Flex Consumption (FC1, zone redundant); Python 3.12;
                        public access off, a private endpoint; identity-based
                        storage; a Service Connector connection
#>

function Get-AACContosoFunctionApp {
    $sub = 'aaaaaaaa-0000-0000-0000-0000000000f1'
    $rg = "/subscriptions/$sub/resourceGroups/rg-functions"
    $site = { param([string] $Name) "$rg/providers/Microsoft.Web/sites/$Name" }
    $farm = { param([string] $Name) "$rg/providers/Microsoft.Web/serverfarms/$Name" }
    $one = { param($Body) @{ Status = 200; Body = $Body; Items = $null; Error = '' } }
    $list = { param([object[]] $Items) @{ Status = 200; Body = @{}; Items = [System.Collections.Generic.List[object]]@($Items); Error = '' } }
    $fail = { param([int] $Status, [string] $Message) @{ Status = $Status; Body = $null; Items = $null; Error = $Message } }
    $ago = { param([double] $Hours) [datetime]::UtcNow.AddHours(-$Hours).ToString('o') }
    $orders = & $site 'func-orders-prod'; $reports = & $site 'func-reports-dev'; $ingest = & $site 'func-ingest-flex'

    $apps = @(
        @{ id = $orders; name = 'func-orders-prod'; kind = 'functionapp'; location = 'westeurope'; resourceGroup = 'rg-functions'; subscriptionId = $sub
            tags = @{ Environment = 'Production'; Owner = 'alice@contoso.com'; CostCenter = 'CC-100' }; identity = @{ type = 'SystemAssigned' }
            properties = @{ serverFarmId = (& $farm 'plan-ep-prod'); state = 'Running'; httpsOnly = $true; publicNetworkAccess = 'Enabled'; defaultHostName = 'func-orders-prod.azurewebsites.net'; possibleOutboundIpAddresses = '20.1.1.1,20.1.1.2,20.1.1.3'; lastModifiedTimeUtc = (& $ago 30) } }
        @{ id = $reports; name = 'func-reports-dev'; kind = 'functionapp,linux'; location = 'westeurope'; resourceGroup = 'rg-functions'; subscriptionId = $sub
            tags = @{ Environment = 'Dev' }; identity = $null
            properties = @{ serverFarmId = (& $farm 'plan-y1'); state = 'Running'; httpsOnly = $false; defaultHostName = 'func-reports-dev.azurewebsites.net' } }
        @{ id = $ingest; name = 'func-ingest-flex'; kind = 'functionapp,linux'; location = 'westeurope'; resourceGroup = 'rg-functions'; subscriptionId = $sub
            tags = @{ Environment = 'Production'; Owner = 'ops@contoso.com' }; identity = @{ type = 'SystemAssigned, UserAssigned' }
            properties = @{ serverFarmId = (& $farm 'plan-fc1'); state = 'Running'; httpsOnly = $true; publicNetworkAccess = 'Disabled'; defaultHostName = 'func-ingest-flex.azurewebsites.net'
                virtualNetworkSubnetId = "/subscriptions/$sub/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-app/subnets/snet-func"
                functionAppConfig = @{ runtime = @{ name = 'python'; version = '3.12' }; scaleAndConcurrency = @{ maximumInstanceCount = 100; instanceMemoryMB = 2048 } } } }
    )
    $plans = @(
        @{ id = (& $farm 'plan-ep-prod'); name = 'plan-ep-prod'; kind = 'elastic'; location = 'westeurope'; resourceGroup = 'rg-functions'; subscriptionId = $sub; sku = @{ name = 'EP1'; tier = 'ElasticPremium'; capacity = 1 }; properties = @{ zoneRedundant = $false; maximumElasticWorkerCount = 20; numberOfSites = 1; reserved = $false } }
        @{ id = (& $farm 'plan-y1'); name = 'plan-y1'; kind = 'functionapp'; location = 'westeurope'; resourceGroup = 'rg-functions'; subscriptionId = $sub; sku = @{ name = 'Y1'; tier = 'Dynamic' }; properties = @{ numberOfSites = 1; reserved = $true } }
        @{ id = (& $farm 'plan-fc1'); name = 'plan-fc1'; kind = 'functionapp'; location = 'westeurope'; resourceGroup = 'rg-functions'; subscriptionId = $sub; sku = @{ name = 'FC1'; tier = 'FlexConsumption' }; properties = @{ zoneRedundant = $true; numberOfSites = 1; reserved = $true } }
        @{ id = (& $farm 'plan-unrelated'); name = 'plan-unrelated'; kind = 'app'; location = 'westeurope'; resourceGroup = 'rg-web'; subscriptionId = $sub; sku = @{ name = 'P1v3'; tier = 'PremiumV3' }; properties = @{ numberOfSites = 3 } }
    )

    # Resource Manager answers, by app and part.
    $web = {
        param([hashtable] $Overrides)
        $p = @{ minTlsVersion = '1.2'; ftpsState = 'Disabled'; http20Enabled = $true; alwaysOn = $false; use32BitWorkerProcess = $false; remoteDebuggingEnabled = $false; scmType = 'None'; ipSecurityRestrictions = @(@{ ipAddress = 'Any'; action = 'Allow'; priority = 2147483647; name = 'Allow all' }); cors = @{ allowedOrigins = @() } }
        foreach ($k in $Overrides.Keys) { $p[$k] = $Overrides[$k] }
        & $one @{ properties = $p }
    }
    $fn = {
        param([string] $App, [string] $Name, [hashtable] $Trigger, [object[]] $More = @())
        @{ id = "$(& $site $App)/functions/$Name"; name = "$App/$Name"; properties = @{ config = @{ bindings = @(@($Trigger) + @($More)) }; isDisabled = $false; language = 'dotnet-isolated' } }
    }
    $event = {
        param([string] $Op, [string] $Status, [string] $Caller, [double] $HoursAgo, [string] $Correlation)
        @{ operationName = @{ value = $Op; localizedValue = ($Op -split '/')[-2..-1] -join ' ' }; status = @{ value = $Status }; caller = $Caller; eventTimestamp = (& $ago $HoursAgo); correlationId = $Correlation; category = @{ value = 'Administrative' } }
    }
    $answers = @{
        'func-orders-prod|Web'           = (& $web @{ ftpsState = 'AllAllowed'; netFrameworkVersion = 'v6.0'; healthCheckPath = '/api/health'; minimumElasticInstanceCount = 1; cors = @{ allowedOrigins = @('*') }; scmType = 'GitHubAction' })
        'func-orders-prod|Functions'     = (& $list @(
                (& $fn 'func-orders-prod' 'GetOrder' @{ type = 'httpTrigger'; direction = 'in'; authLevel = 'anonymous' } @(@{ type = 'http'; direction = 'out' }))
                (& $fn 'func-orders-prod' 'Cleanup' @{ type = 'timerTrigger'; direction = 'in'; schedule = '0 0 2 * * *' })
                (& $fn 'func-orders-prod' 'ProcessOrder' @{ type = 'serviceBusTrigger'; direction = 'in'; connection = 'ServiceBusConnection' } @(@{ type = 'cosmosDB'; direction = 'out'; connection = 'CosmosConnection' }))
            ))
        'func-orders-prod|SourceControl' = (& $one @{ properties = @{ repoUrl = 'https://github.com/contoso/orders'; branch = 'main'; isGitHubAction = $true } })
        'func-orders-prod|Deployments'   = (& $list @(@{ properties = @{ status = 4; author = 'alice'; deployer = 'GitHub'; message = "Deploy 1.4.2`nmore"; end_time = (& $ago 50); active = $true } }, @{ properties = @{ status = 3; author = 'alice'; deployer = 'GitHub'; message = 'Deploy 1.4.1'; end_time = (& $ago 75); active = $false } }))
        'func-orders-prod|ScmBasic'      = (& $one @{ properties = @{ allow = $true } })
        'func-orders-prod|FtpBasic'      = (& $one @{ properties = @{ allow = $false } })
        'func-orders-prod|Backups'       = (& $list @())
        'func-orders-prod|Auth'          = (& $one @{ properties = @{ platform = @{ enabled = $false } } })
        'func-orders-prod|Linkers'       = (& $list @())
        'func-orders-prod|Diagnostics'   = (& $list @())
        'func-orders-prod|Health'        = (& $one @{ properties = @{ availabilityState = 'Available' } })
        'func-orders-prod|Locks'         = (& $list @())
        'func-orders-prod|Activity'      = (& $list @(
                (& $event 'Microsoft.Web/sites/restart/action' 'Succeeded' 'alice@contoso.com' 10 'c1')
                (& $event 'Microsoft.Web/sites/restart/action' 'Succeeded' 'alice@contoso.com' 20 'c2')
                (& $event 'Microsoft.Web/sites/restart/action' 'Succeeded' 'bob@contoso.com' 30 'c3')
                (& $event 'Microsoft.Web/sites/restart/action' 'Succeeded' 'bob@contoso.com' 40 'c4')
                (& $event 'Microsoft.Web/sites/config/write' 'Started' 'alice@contoso.com' 45 'c5')
                (& $event 'Microsoft.Web/sites/config/write' 'Succeeded' 'alice@contoso.com' 44.9 'c5')
                (& $event 'Microsoft.Web/sites/config/appsettings/list/action' 'Succeeded' 'bob@contoso.com' 46 'c6')
                (& $event 'Microsoft.Web/sites/slots/slotsswap/action' 'Failed' 'pipeline-sp' 60 'c7')
                (& $event 'Microsoft.Web/sites/read' 'Succeeded' 'reader@contoso.com' 61 'c8')
            ))
        'func-reports-dev|Web'           = (& $web @{ minTlsVersion = '1.0'; linuxFxVersion = 'Python|3.8'; ipSecurityRestrictions = @(@{ ipAddress = '203.0.113.0/24'; action = 'Allow'; priority = 100; name = 'Office' }, @{ ipAddress = 'Any'; action = 'Deny'; priority = 2147483647; name = 'Deny all' }) })
        'func-reports-dev|Functions'     = (& $fail 400 'The function host is not running.')
        'func-reports-dev|Health'        = (& $one @{ properties = @{ availabilityState = 'Degraded' } })
        'func-reports-dev|Activity'      = (& $list @())
        'func-ingest-flex|Web'           = (& $web @{ linuxFxVersion = '' })
        'func-ingest-flex|Functions'     = (& $list @((& $fn 'func-ingest-flex' 'Ingest' @{ type = 'eventHubTrigger'; direction = 'in'; connection = 'EventHub' })))
        'func-ingest-flex|Linkers'       = (& $list @(@{ id = "$ingest/providers/Microsoft.ServiceLinker/linkers/storage"; name = 'storage'; properties = @{ targetService = @{ type = 'AzureResource'; id = "/subscriptions/$sub/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stingest" }; authInfo = @{ authType = 'systemAssignedIdentity' } } }))
        'func-ingest-flex|Diagnostics'   = (& $list @(@{ name = 'to-law'; properties = @{ workspaceId = 'law' } }))
        'func-ingest-flex|Health'        = (& $one @{ properties = @{ availabilityState = 'Available' } })
        'func-ingest-flex|Locks'         = (& $list @(@{ name = 'nodelete'; properties = @{ level = 'CanNotDelete' } }))
        'func-ingest-flex|Deployments'   = (& $list @(@{ properties = @{ status = 4; author = 'ops'; deployer = 'OneDeploy'; message = 'Deploy'; end_time = (& $ago 5); active = $true } }))
        'func-ingest-flex|Activity'      = (& $list @((& $event 'Microsoft.Web/sites/write' 'Succeeded' 'ops@contoso.com' 5 'd1')))
    }
    # App settings (POST list): values only the module sees - the report must never show them.
    $settings = @{
        'func-orders-prod' = @{ FUNCTIONS_EXTENSION_VERSION = '~4'; FUNCTIONS_WORKER_RUNTIME = 'dotnet'; AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=stfuncshared;AccountKey=SuperSecretKey==;EndpointSuffix=core.windows.net'
            SqlPassword = 'P@ssw0rd-visible'; ApiKey = '@Microsoft.KeyVault(SecretUri=https://kv-orders.vault.azure.net/secrets/ApiKey/)'; APPLICATIONINSIGHTS_CONNECTION_STRING = 'InstrumentationKey=00000000-0000-0000-0000-000000000000'
            ServiceBusConnection = 'Endpoint=sb://sb-orders.servicebus.windows.net/;SharedAccessKeyName=root;SharedAccessKey=AnotherSecret='; Region = 'westeurope' }
        'func-reports-dev' = @{ FUNCTIONS_EXTENSION_VERSION = '~4'; FUNCTIONS_WORKER_RUNTIME = 'python'; AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=stfuncshared;AccountKey=SuperSecretKey==;EndpointSuffix=core.windows.net' }
        'func-ingest-flex' = @{ AzureWebJobsStorage__accountName = 'stingest'; APPLICATIONINSIGHTS_CONNECTION_STRING = 'InstrumentationKey=11111111-1111-1111-1111-111111111111'; EventHub__fullyQualifiedNamespace = 'eh-ingest.servicebus.windows.net' }
    }
    # Azure Monitor: totals, averages and maxima per app and call.
    $series = { param([string] $Name, [hashtable] $Point) @{ Name = $Name; Dims = @{}; Points = @($Point) } }
    $metrics = @{
        $orders                     = @{
            Http    = @{ Error = ''; Series = @((& $series 'Requests' @{ total = 10000 }), (& $series 'Http5xx' @{ total = 800 }), (& $series 'Http4xx' @{ total = 120 })) }
            Exec    = @{ Error = ''; Series = @((& $series 'FunctionExecutionCount' @{ total = 50000 }), (& $series 'FunctionExecutionUnits' @{ total = 2048000000 })) }
            Latency = @{ Error = ''; Series = @((& $series 'HttpResponseTime' @{ average = 1.5 })) }
            Memory  = @{ Error = ''; Series = @((& $series 'MemoryWorkingSet' @{ average = 300MB; maximum = 600MB })) }
        }
        $reports                    = @{
            Http    = @{ Error = ''; Series = @((& $series 'Requests' @{ total = 0 }), (& $series 'Http5xx' @{ total = 0 }), (& $series 'Http4xx' @{ total = 0 })) }
            Exec    = @{ Error = ''; Series = @((& $series 'FunctionExecutionCount' @{ total = 0 }), (& $series 'FunctionExecutionUnits' @{ total = 0 })) }
            Latency = @{ Error = 'No data'; Series = @() }
            Memory  = @{ Error = ''; Series = @((& $series 'MemoryWorkingSet' @{ average = 100MB; maximum = 1400MB })) }
        }
        $ingest                     = @{
            Http    = @{ Error = ''; Series = @((& $series 'Requests' @{ total = 0 }), (& $series 'Http5xx' @{ total = 0 }), (& $series 'Http4xx' @{ total = 0 })) }
            Exec    = @{ Error = ''; Series = @((& $series 'FunctionExecutionCount' @{ total = 1200 }), (& $series 'FunctionExecutionUnits' @{ total = 102400000 })) }
            Latency = @{ Error = 'No data'; Series = @() }
            Memory  = @{ Error = ''; Series = @((& $series 'MemoryWorkingSet' @{ average = 200MB; maximum = 400MB })) }
        }
        (& $farm 'plan-ep-prod')    = @{ Plan = @{ Error = ''; Series = @((& $series 'CpuPercentage' @{ average = 8; maximum = 15 }), (& $series 'MemoryPercentage' @{ average = 30; maximum = 45 })) } }
    }

    @{
        Rows     = @{
            apps             = $apps
            plans            = $plans
            slots            = @(@{ id = "$orders/slots/staging"; name = 'func-orders-prod/staging'; kind = 'functionapp'; location = 'westeurope'; resourceGroup = 'rg-functions'; subscriptionId = $sub; properties = @{ state = 'Running'; defaultHostName = 'func-orders-prod-staging.azurewebsites.net'; httpsOnly = $true; lastModifiedTimeUtc = (& $ago 50) } })
            privateEndpoints = @(@{ id = "/subscriptions/$sub/resourceGroups/rg-net/providers/Microsoft.Network/privateEndpoints/pe-ingest"; name = 'pe-ingest'; target = $ingest.ToLowerInvariant(); status = 'Approved'; subnet = 'snet-pe' })
            advisor          = @(@{ resourceId = $orders.ToLowerInvariant(); category = 'HighAvailability'; impact = 'High'; problem = 'Enable zone redundancy for the plan'; solution = 'Use a zone-redundant Elastic Premium plan' })
            defender         = @(@{ resourceId = $reports.ToLowerInvariant(); name = 'Function App should only be accessible over HTTPS'; severity = 'Medium'; remediation = 'Turn on HTTPS Only' })
            subscriptions    = @(@{ subscriptionId = $sub; name = 'Contoso Apps' })
        }
        Answers  = $answers
        Settings = $settings
        Metrics  = $metrics
        Secrets  = @('SuperSecretKey==', 'P@ssw0rd-visible', 'AnotherSecret=', 'InstrumentationKey=00000000')
    }
}

# The answer to one GET: the app and the part of it asked for, or the Activity Log by its resourceUri.
function Get-AACContosoFunctionAppAnswer {
    param([hashtable] $Data, [string] $Uri)
    $decoded = [System.Uri]::UnescapeDataString($Uri)
    $part = $null
    if ($decoded -match "resourceUri eq '[^']*/sites/([^'/]+)'") { $app = $Matches[1]; $part = 'Activity' }
    elseif ($decoded -match '/sites/([^/?]+)/(.+?)\?') {
        $app = $Matches[1]
        $part = switch -Regex ($Matches[2]) {
            '^config/web$' { 'Web' } '^functions$' { 'Functions' } '^sourcecontrols/web$' { 'SourceControl' } '^deployments$' { 'Deployments' }
            'basicPublishingCredentialsPolicies/scm' { 'ScmBasic' } 'basicPublishingCredentialsPolicies/ftp' { 'FtpBasic' } '^backups$' { 'Backups' } 'authsettingsV2' { 'Auth' }
            'ServiceLinker' { 'Linkers' } 'diagnosticSettings' { 'Diagnostics' } 'availabilityStatuses' { 'Health' } 'locks' { 'Locks' } default { $null }
        }
    }
    if ($part -and $Data.Answers.ContainsKey("$app|$part")) { return $Data.Answers["$app|$part"] }
    @{ Status = 404; Body = $null; Items = $null; Error = 'Not found.' }
}
