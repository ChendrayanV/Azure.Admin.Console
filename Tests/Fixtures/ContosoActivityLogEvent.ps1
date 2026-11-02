<#
    Made-up Contoso Activity Log events for ActivityLogEvent.Tests.ps1, in
    the shape the portal's JSON tab and the REST API give them (and one as a
    Log Analytics AzureActivity row):

      arc-upgrade    an app (certificate) upgrades the extensions of an
                     Azure Arc machine: Started, then Failed - 404, HCRP404,
                     the extension isn't published in the region
      tag-write      ada (password and MFA) writes the tags of a storage
                     account: Succeeded
      Workspace      a row of the same failure as AzureActivity returns it
#>
function Get-AACContosoActivityLogEvent {
    $tenant = '00000000-aaaa-4bbb-8ccc-000000000001'
    $sub = '11111111-1111-1111-1111-111111111111'
    $machine = "/subscriptions/$sub/resourceGroups/rg-arc/providers/Microsoft.HybridCompute/machines/arc-web-01.contoso.example"
    $store = "/subscriptions/$sub/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stdata"
    $app = 'aaaaaaaa-1111-4222-8333-000000000abc'
    $sp = 'bbbbbbbb-1111-4222-8333-000000000def'
    $correlation = 'cccccccc-1111-4222-8333-000000000123'
    $appClaims = [ordered]@{
        aud = 'https://management.core.windows.net/'; iss = "https://sts.windows.net/$tenant/"; iat = '1793442186'; nbf = '1793442186'; exp = '1793528886'
        aio = 'opaque-aio-value'; appid = $app; appidacr = '2'; idtyp = 'app'
        'http://schemas.microsoft.com/identity/claims/objectidentifier' = $sp; 'http://schemas.microsoft.com/identity/claims/tenantid' = $tenant
        rh = 'opaque-rh-value'; uti = 'opaque-uti'; ver = '1.0'; wids = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'; xms_ftd = 'opaque-ftd'; xms_tcdt = '1440513369'
    }
    $statusMessage = '{"error":{"code":"HCRP404","target":"' + $sub + '/rg-arc/arc-web-01.contoso.example","message":"The VM extension with publisher ''microsoft.azure.monitor'' and type ''azuremonitorlinuxagent'' could not be found in location ''uksouth''."}}'
    $arc = {
        param([string] $Phase, [string] $Status, [string] $When, [string] $DataId)
        [ordered]@{
            authorization = @{ action = 'Microsoft.HybridCompute/machines/upgradeExtensions/action'; scope = $machine }
            caller = $sp; channels = 'Operation'; claims = $appClaims; correlationId = $correlation; description = ''; eventDataId = $DataId
            eventName = @{ value = $Phase; localizedValue = $(if ($Phase -eq 'EndRequest') { 'End request' } else { 'Begin request' }) }
            category = @{ value = 'Administrative'; localizedValue = 'Administrative' }; eventTimestamp = $When
            id = "$machine/events/$DataId/ticks/639290392872176382"; level = $(if ($Status -eq 'Failed') { 'Error' } else { 'Informational' }); operationId = 'dddddddd-1111-4222-8333-000000000456'
            operationName = @{ value = 'Microsoft.HybridCompute/machines/upgradeExtensions/action'; localizedValue = 'Upgrade Extensions on Azure Arc machines' }
            resourceGroupName = 'rg-arc'; resourceProviderName = @{ value = 'Microsoft.HybridCompute'; localizedValue = 'Microsoft.HybridCompute' }
            resourceType = @{ value = 'Microsoft.HybridCompute/machines'; localizedValue = 'Microsoft.HybridCompute/machines' }; resourceId = $machine
            status = @{ value = $Status; localizedValue = $Status }
            subStatus = $(if ($Status -eq 'Failed') { @{ value = 'NotFound'; localizedValue = 'Not Found (HTTP Status Code: 404)' } } else { @{ value = ''; localizedValue = '' } })
            submissionTimestamp = '2026-10-31T10:29:55Z'; subscriptionId = $sub; tenantId = $tenant
            properties = $(if ($Status -eq 'Failed') { @{ statusCode = 'NotFound'; serviceRequestId = $null; statusMessage = $statusMessage; eventCategory = 'Administrative'; entity = $machine; message = 'Microsoft.HybridCompute/machines/upgradeExtensions/action'; hierarchy = "$tenant/$sub" } } else { @{ eventCategory = 'Administrative'; hierarchy = "$tenant/$sub" } })
            relatedEvents = @()
        }
    }
    @{
        Tenant      = $tenant
        Subscription = $sub
        Machine     = $machine
        Store       = $store
        Correlation = $correlation
        Failed      = (& $arc 'EndRequest' 'Failed' '2026-10-31T10:28:07.2176382Z' 'eeeeeeee-0000-0000-0000-000000000002')
        Started     = (& $arc 'BeginRequest' 'Started' '2026-10-31T10:28:01.0000000Z' 'eeeeeeee-0000-0000-0000-000000000001')
        UserWrite   = [ordered]@{
            caller = 'ada@contoso.example'; channels = 'Operation'; correlationId = 'ffffffff-1111-4222-8333-000000000789'; eventDataId = 'eeeeeeee-0000-0000-0000-000000000003'
            claims = [ordered]@{ iss = "https://sts.windows.net/$tenant/"; iat = '1793440000'; exp = '1793443600'; name = 'Ada Lovelace'; 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn' = 'ada@contoso.example'; 'http://schemas.microsoft.com/claims/authnmethodsreferences' = 'pwd,mfa'; wids = '62e90394-69f5-4237-9190-012177145e10 b79fbf4d-3ef9-4689-8143-76b194e85509' }
            eventName = @{ value = 'EndRequest'; localizedValue = 'End request' }; category = @{ value = 'Administrative' }; eventTimestamp = '2026-10-31T09:00:00Z'; level = 'Informational'
            operationName = @{ value = 'Microsoft.Resources/tags/write'; localizedValue = 'Update resource tags' }; operationId = 'op-tags'; resourceId = "$store/providers/Microsoft.Resources/tags/default"
            status = @{ value = 'Succeeded'; localizedValue = 'Succeeded' }; subscriptionId = $sub; tenantId = $tenant; httpRequest = @{ clientIpAddress = '203.0.113.9'; method = 'PUT' }
            properties = @{ statusCode = 'OK'; hierarchy = "$tenant/$sub" }
        }
        Workspace   = [ordered]@{
            TimeGenerated = '2026-10-31T10:28:07.2176382Z'; OperationNameValue = 'MICROSOFT.HYBRIDCOMPUTE/MACHINES/UPGRADEEXTENSIONS/ACTION'; OperationName = 'Upgrade Extensions on Azure Arc machines'
            ActivityStatusValue = 'Failure'; ActivitySubstatusValue = 'NotFound'; Level = 'Error'; CategoryValue = 'Administrative'; Caller = $sp; CallerIpAddress = ''
            Claims_d = $appClaims; Authorization_d = @{ action = 'Microsoft.HybridCompute/machines/upgradeExtensions/action'; scope = $machine }
            Properties_d = @{ statusCode = 'NotFound'; statusMessage = $statusMessage; hierarchy = "$tenant/$sub" }; _ResourceId = $machine.ToLowerInvariant(); SubscriptionId = $sub; TenantId = $tenant
            CorrelationId = $correlation; OperationId = 'dddddddd-1111-4222-8333-000000000456'; EventDataId = 'eeeeeeee-0000-0000-0000-000000000002'; EventSubmissionTimestamp = '2026-10-31T10:29:55Z'; Hierarchy = "$tenant/$sub"
        }
    }
}
