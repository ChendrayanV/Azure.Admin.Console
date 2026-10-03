<#
    A made-up estate for the Get-AACDiagnosticSetting tests, in the shapes
    Azure returns: Resource Graph rows, each type's diagnosticSettingsCategories
    and each resource's diagnosticSettings. Every status and misconfiguration
    occurs at least once:

      kv-app          Key Vault, westeurope: allLogs to law-central (uksouth)  Exported; workspace in another region
      kv-old          Key Vault: only AuditEvent to law-central                Partial
      app-api         App Service: no setting                                   No setting
      app-empty       App Service: a setting to law-central, nothing enabled    Not to workspace; nothing enabled
      agw-edge        Application gateway: storage only, 30-day retention       Not to workspace; deprecated retention
      app-locked      App Service: settings can't be read (403)                 Unknown
      disk-data       Managed disk: no diagnostic settings at all (400)         No logs
      stcontoso       Storage account: metrics only on the account              No logs
        (blob)        a workspace that was deleted                              Not to workspace; workspace doesn't exist
        (file)        allLogs to law-central from two settings                  Exported; sent twice
        (queue, table) no setting                                               No setting
      sub-prod        activity log: Administrative and Security only            Partial
      sub-dev         activity log: no setting                                  Activity log not exported

    Returns @{ Graph; Categories (type -> response); Settings (resource ID -> response); ... }.
#>
$prod = '11111111-1111-1111-1111-111111111111'
$dev = '22222222-2222-2222-2222-222222222222'
$id = { param([string] $Sub, [string] $Group, [string] $Provider, [string] $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/$Provider/$Name" }
$lawCentral = (& $id $prod 'rg-monitor' 'Microsoft.OperationalInsights/workspaces' 'law-central')
$lawDeleted = (& $id $prod 'rg-monitor' 'Microsoft.OperationalInsights/workspaces' 'law-deleted')
$resource = { param([string] $Sub, [string] $Group, [string] $Provider, [string] $Name, [string] $Location = 'uksouth', [string] $Kind = '')
    @{ id = (& $id $Sub $Group $Provider $Name); name = $Name; type = $Provider.ToLowerInvariant(); resourceKind = $Kind; location = $Location; resourceGroup = $Group; subscriptionId = $Sub }
}
$resources = @(
    (& $resource $prod 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-app' 'westeurope')
    (& $resource $prod 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-old')
    (& $resource $prod 'rg-app' 'Microsoft.Web/sites' 'app-api' -Kind 'app')
    (& $resource $prod 'rg-app' 'Microsoft.Web/sites' 'app-empty' -Kind 'app')
    (& $resource $dev 'rg-dev' 'Microsoft.Web/sites' 'app-locked' -Kind 'app')
    (& $resource $prod 'rg-net' 'Microsoft.Network/applicationGateways' 'agw-edge')
    (& $resource $prod 'rg-app' 'Microsoft.Compute/disks' 'disk-data')
    (& $resource $prod 'rg-data' 'Microsoft.Storage/storageAccounts' 'stcontoso' -Kind 'storagev2')
    @{ id = $lawCentral; name = 'law-central'; type = 'microsoft.operationalinsights/workspaces'; resourceKind = ''; location = 'uksouth'; resourceGroup = 'rg-monitor'; subscriptionId = $prod }
)
$log = { param([string] $Name, [string[]] $Groups = @('allLogs')) @{ name = $Name; properties = @{ categoryType = 'Logs'; categoryGroups = $Groups } } }
$metric = { param([string] $Name = 'AllMetrics') @{ name = $Name; properties = @{ categoryType = 'Metrics'; categoryGroups = @() } } }
$ok = { param([object[]] $Items) @{ Status = 200; Body = @{ value = $Items }; Items = $Items; Error = '' } }
$categories = @{
    'microsoft.keyvault/vaults'                          = & $ok @((& $log 'AuditEvent' @('audit', 'allLogs')), (& $log 'AzurePolicyEvaluationDetails'), (& $metric))
    'microsoft.web/sites'                                = & $ok @((& $log 'AppServiceHTTPLogs'), (& $log 'AppServiceConsoleLogs'), (& $log 'AppServiceAuditLogs' @('audit', 'allLogs')), (& $metric))
    'microsoft.network/applicationgateways'              = & $ok @((& $log 'ApplicationGatewayAccessLog'), (& $log 'ApplicationGatewayFirewallLog'), (& $metric))
    'microsoft.compute/disks'                            = @{ Status = 400; Body = $null; Items = $null; Error = 'The resource type microsoft.compute/disks does not support diagnostic settings.' }
    'microsoft.storage/storageaccounts'                  = & $ok @((& $metric 'Transaction'), (& $metric 'Capacity'))
    'microsoft.storage/storageaccounts/blobservices'     = & $ok @((& $log 'StorageRead' @('audit', 'allLogs')), (& $log 'StorageWrite' @('audit', 'allLogs')), (& $log 'StorageDelete' @('audit', 'allLogs')), (& $metric 'Transaction'))
    'microsoft.storage/storageaccounts/fileservices'     = & $ok @((& $log 'StorageRead'), (& $log 'StorageWrite'), (& $log 'StorageDelete'), (& $metric 'Transaction'))
    'microsoft.storage/storageaccounts/queueservices'    = & $ok @((& $log 'StorageRead'), (& $log 'StorageWrite'), (& $log 'StorageDelete'))
    'microsoft.storage/storageaccounts/tableservices'    = & $ok @((& $log 'StorageRead'), (& $log 'StorageWrite'), (& $log 'StorageDelete'))
    'microsoft.operationalinsights/workspaces'           = & $ok @((& $log 'Audit' @('audit', 'allLogs')), (& $log 'SummaryLogs'))
    'microsoft.resources/subscriptions'                  = & $ok @('Administrative', 'Security', 'ServiceHealth', 'Alert', 'Recommendation', 'Policy', 'Autoscale', 'ResourceHealth' | ForEach-Object { @{ name = $_; properties = @{ categoryType = 'Logs'; categoryGroups = @() } } })
}
$setting = {
    param([string] $Name, [hashtable] $Destination, [object[]] $Logs = @(), [object[]] $Metrics = @())
    $properties = @{ logs = $Logs; metrics = $Metrics }
    foreach ($key in $Destination.Keys) { $properties[$key] = $Destination[$key] }
    @{ id = "x/providers/microsoft.insights/diagnosticSettings/$Name"; name = $Name; properties = $properties }
}
$group = { param([string] $Group) @{ categoryGroup = $Group; enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } } }
$category = { param([string] $Name, [bool] $Enabled = $true, [int] $Days = 0) @{ category = $Name; enabled = $Enabled; retentionPolicy = @{ enabled = [bool]$Days; days = $Days } } }
$toLaw = @{ workspaceId = $lawCentral; logAnalyticsDestinationType = 'Dedicated' }
$storageAccount = "/subscriptions/$prod/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/starchive"
$st = (& $id $prod 'rg-data' 'Microsoft.Storage/storageAccounts' 'stcontoso')
$settings = @{
    (& $id $prod 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-app')             = & $ok @((& $setting 'to-law' $toLaw @((& $group 'allLogs')) @((& $category 'AllMetrics'))))
    (& $id $prod 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-old')             = & $ok @((& $setting 'audit-only' @{ workspaceId = $lawCentral } @((& $category 'AuditEvent'), (& $category 'AzurePolicyEvaluationDetails' $false))))
    (& $id $prod 'rg-app' 'Microsoft.Web/sites' 'app-api')                  = & $ok @()
    (& $id $prod 'rg-app' 'Microsoft.Web/sites' 'app-empty')                = & $ok @((& $setting 'empty' $toLaw @((& $category 'AppServiceHTTPLogs' $false))))
    (& $id $dev 'rg-dev' 'Microsoft.Web/sites' 'app-locked')                = @{ Status = 403; Body = $null; Items = $null; Error = 'The client does not have authorization to perform action microsoft.insights/diagnosticSettings/read.' }
    (& $id $prod 'rg-net' 'Microsoft.Network/applicationGateways' 'agw-edge') = & $ok @((& $setting 'to-storage' @{ storageAccountId = $storageAccount } @((& $category 'ApplicationGatewayAccessLog' $true 30), (& $category 'ApplicationGatewayFirewallLog' $true 30))))
    "$st/blobServices/default"                                              = & $ok @((& $setting 'to-old-law' @{ workspaceId = $lawDeleted } @((& $group 'allLogs'))))
    "$st/fileServices/default"                                              = & $ok @((& $setting 'to-law' $toLaw @((& $group 'allLogs'))), (& $setting 'to-law-again' $toLaw @((& $group 'allLogs'))))
    "$st/queueServices/default"                                             = & $ok @()
    "$st/tableServices/default"                                             = & $ok @()
    $lawCentral                                                             = & $ok @((& $setting 'self' $toLaw @((& $group 'allLogs'))))
    "/subscriptions/$prod"                                                  = & $ok @((& $setting 'activity-to-law' @{ workspaceId = $lawCentral } @((& $category 'Administrative'), (& $category 'Security'), (& $category 'Policy' $false))))
    "/subscriptions/$dev"                                                   = & $ok @()
}

@{
    Prod       = $prod
    Dev        = $dev
    LawCentral = $lawCentral
    Graph      = @{
        resources     = $resources
        subscriptions = @(@{ subscriptionId = $prod; name = 'sub-prod' }, @{ subscriptionId = $dev; name = 'sub-dev' })
        workspaces    = @(@{ id = $lawCentral.ToLowerInvariant(); name = 'law-central'; location = 'uksouth' })
    }
    Categories = $categories
    Settings   = $settings
}
