<#
    Made-up Contoso Application Insights components for
    ApplicationInsightAssessment.Tests.ps1, as Resource Graph, Resource
    Manager, Azure Monitor, Log Analytics and the Activity Log return them.

      appi-orders  (Contoso Prod, rg-app)  workspace-based (law-prod, same
                   region), local auth off with a Monitoring Metrics
                   Publisher, IP masking on, in a private link scope with
                   public access off, daily cap 10 GB, sampling (25% kept),
                   a standard test from 5 locations, a metric alert and
                   Failure Anomalies with action groups, owner tag, resource
                   group lock: nothing to fix.
      appi-legacy  (Contoso Dev, rg-dev)  classic; local auth on, IP masking
                   off, an API key that can write, a URL ping test from 1
                   location, no alert, Owner granted to a user on the
                   component, cap 100 GB, no lock, no tags.
      appi-web     (Contoso Prod, rg-app)  workspace-based (law-prod); local
                   auth off but no publisher; a diagnostic setting sending
                   AppRequests to law-prod again; 15 GB in 7 days with no
                   sampling (one 6 GB day, cap 5 GB), traces 60% of it and
                   mostly Verbose, 30% of requests health probes; no test; a
                   metric alert with no action group. Activity Log: a purge
                   and a change by alice@contoso.com, an API key created by
                   an app, a failed change.
      appi-idle    (Contoso Prod, rg-app)  workspace-based (law-eu, West
                   Europe, workspace-only permissions); no telemetry since
                   2025; a publisher at the resource group; no alert.
#>
function Get-AACContosoApplicationInsight {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $lawProd = "/subscriptions/$prod/resourcegroups/rg-monitor/providers/microsoft.operationalinsights/workspaces/law-prod"
    $lawEu = "/subscriptions/$prod/resourcegroups/rg-monitor/providers/microsoft.operationalinsights/workspaces/law-eu"
    $component = {
        param($Sub, $Group, $Name, $Properties, $Tags)
        @{ id = "/subscriptions/$Sub/resourcegroups/$Group/providers/microsoft.insights/components/$Name"; name = $Name; location = 'uksouth'; resourceGroup = $Group; subscriptionId = $Sub; kind = 'web'; properties = $Properties; tags = $Tags }
    }
    $orders = & $component $prod 'rg-app' 'appi-orders' @{ Application_Type = 'web'; IngestionMode = 'LogAnalytics'; WorkspaceResourceId = $lawProd; DisableLocalAuth = $true; DisableIpMasking = $false; publicNetworkAccessForIngestion = 'Disabled'; publicNetworkAccessForQuery = 'Disabled'; PrivateLinkScopedResources = @(@{ ResourceId = 'x'; ScopeId = 'y' }); CreationDate = '2024-01-10T00:00:00Z' } @{ owner = 'orders-team' }
    $legacy = & $component $dev 'rg-dev' 'appi-legacy' @{ Application_Type = 'web'; IngestionMode = 'ApplicationInsights'; DisableIpMasking = $true; CreationDate = '2019-05-01T00:00:00Z' } $null
    $web = & $component $prod 'rg-app' 'appi-web' @{ Application_Type = 'web'; IngestionMode = 'LogAnalytics'; WorkspaceResourceId = $lawProd; DisableLocalAuth = $true; CreationDate = '2024-03-01T00:00:00Z' } @{ Owner = 'web-team' }
    $idle = & $component $prod 'rg-app' 'appi-idle' @{ Application_Type = 'web'; IngestionMode = 'LogAnalytics'; WorkspaceResourceId = $lawEu; DisableLocalAuth = $true; CreationDate = '2025-02-01T00:00:00Z' } @{ team = 'platform' }

    $list = { param([object[]] $Items) @{ Status = 200; Body = @{}; Items = @($Items); Error = '' } }
    $cap = { param($Gb) @{ Status = 200; Body = @{ DataVolumeCap = @{ Cap = $Gb; StopSendNotificationWhenHitThreshold = $false } }; Items = $null; Error = '' } }
    $role = { param($Guid, $Principal, $Type, $Scope) @{ properties = @{ roleDefinitionId = "/providers/Microsoft.Authorization/roleDefinitions/$Guid"; principalId = $Principal; principalType = $Type; scope = $Scope } } }
    $publisher = '3913510d-42f4-4e42-8a64-420c390055eb'
    $reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    $owner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    $roles = '/providers/Microsoft.Authorization/roleAssignments'
    $diag = '/providers/Microsoft.Insights/diagnosticSettings'
    $arm = @{
        "$($orders.id)/currentbillingfeatures" = & $cap 10
        "$($orders.id)/ApiKeys"                = & $list @()
        "$($orders.id)$diag"                   = & $list @()
        "$($orders.id)$roles"                  = & $list @((& $role $publisher 'sp-orders' 'ServicePrincipal' $orders.id), (& $role $reader 'grp-ops' 'Group' "/subscriptions/$prod"))
        "$($legacy.id)/currentbillingfeatures" = & $cap 100
        "$($legacy.id)/ApiKeys"                = & $list @(@{ name = 'release-annotations'; CreatedDate = '2020-01-01'; LinkedReadProperties = @("$($legacy.id)/api"); LinkedWriteProperties = @("$($legacy.id)/annotations") })
        "$($legacy.id)$diag"                   = & $list @()
        "$($legacy.id)$roles"                  = & $list @(& $role $owner 'user-bob' 'User' $legacy.id)
        "$($web.id)/currentbillingfeatures"    = & $cap 5
        "$($web.id)/ApiKeys"                   = & $list @()
        "$($web.id)$diag"                      = & $list @(@{ name = 'to-law'; properties = @{ workspaceId = $lawProd; logs = @(@{ category = 'AppRequests'; enabled = $true }) } })
        "$($web.id)$roles"                     = & $list @(& $role $reader 'grp-ops' 'Group' "/subscriptions/$prod")
        "$($idle.id)/ApiKeys"                  = & $list @()
        "$($idle.id)$diag"                     = & $list @()
        "$($idle.id)$roles"                    = & $list @(& $role $publisher 'sp-batch' 'ServicePrincipal' "/subscriptions/$prod/resourcegroups/rg-app")
    }

    $point = { param($Value) @{ timeStamp = '2026-11-05T00:00:00Z'; count = $Value } }
    $telemetry = { param($Requests, $Dependencies, $Exceptions, $Traces) @{ value = @(foreach ($m in @(@('requests/count', $Requests), @('dependencies/count', $Dependencies), @('exceptions/count', $Exceptions), @('traces/count', $Traces))) { @{ name = @{ value = $m[0] }; timeseries = @(@{ metadatavalues = @(); data = @(& $point $m[1]) }) } }) } }

    $day = { param($Id, $Offset, $Gb) [ordered]@{ ResourceId = $Id; Day = (Get-Date '2026-11-01').AddDays($Offset); GB = $Gb } }
    @{
        Graph    = @{
            components = @($orders, $legacy, $web, $idle)
            workspaces = @(
                @{ id = $lawProd; name = 'law-prod'; location = 'uksouth'; customerId = 'cid-prod'; sku = 'PerGB2018'; retentionInDays = 90; dailyQuotaGb = -1; resourcePermissions = 'True' }
                @{ id = $lawEu; name = 'law-eu'; location = 'westeurope'; customerId = 'cid-eu'; sku = 'PerGB2018'; retentionInDays = 30; dailyQuotaGb = -1; resourcePermissions = 'False' }
            )
            webtests   = @(
                @{ id = 'wt-orders'; name = 'orders-home'; tags = @{ "hidden-link:$($orders.id)" = 'Resource' }; kind = 'standard'; enabled = 'True'; locations = 5 }
                @{ id = 'wt-legacy'; name = 'legacy-ping'; tags = @{ "hidden-link:$($legacy.id)" = 'Resource' }; kind = 'ping'; enabled = 'True'; locations = 1 }
            )
            alerts     = @(
                @{ id = 'ma-orders'; name = 'orders-failed'; type = 'microsoft.insights/metricalerts'; enabled = 'True'; scopes = "[`"$($orders.id)`"]"; actions = '[{"actiongroupid":"/subscriptions/x/resourcegroups/rg/providers/microsoft.insights/actiongroups/ops"}]'; detector = '' }
                @{ id = 'sd-orders'; name = 'orders-anomalies'; type = 'microsoft.alertsmanagement/smartdetectoralertrules'; enabled = 'Enabled'; scopes = "[`"$($orders.id)`"]"; actions = '{"groupids":["/subscriptions/x/resourcegroups/rg/providers/microsoft.insights/actiongroups/ops"]}'; detector = 'FailureAnomaliesDetector' }
                @{ id = 'ma-web'; name = 'web-latency'; type = 'microsoft.insights/metricalerts'; enabled = 'True'; scopes = "[`"$($web.id)`"]"; actions = '[]'; detector = '' }
            )
            locks      = @(@{ id = "/subscriptions/$prod/resourcegroups/rg-app/providers/microsoft.authorization/locks/no-delete"; level = 'CanNotDelete' })
        }
        Arm      = $arm
        # "<component>|Telemetry" -> the metrics API's body.
        Metrics  = @{
            "$($orders.id)|Telemetry" = & $telemetry 100000 250000 120 40000
            "$($legacy.id)|Telemetry" = & $telemetry 500 900 3 100
            "$($web.id)|Telemetry"    = & $telemetry 400000 300000 900 900000
            "$($idle.id)|Telemetry"   = & $telemetry 0 0 0 0
        }
        # Log Analytics: workspace query ID -> query name -> rows.
        Logs     = @{
            'cid-prod' = @{
                tables   = @(
                    [ordered]@{ ResourceId = $orders.id; Table = 'AppRequests'; GB = 2.0; Rows = 30000; Items = 120000 }
                    [ordered]@{ ResourceId = $orders.id; Table = 'AppDependencies'; GB = 1.5; Rows = 20000; Items = 80000 }
                    [ordered]@{ ResourceId = $web.id; Table = 'AppTraces'; GB = 9.0; Rows = 900000; Items = 900000 }
                    [ordered]@{ ResourceId = $web.id; Table = 'AppRequests'; GB = 4.0; Rows = 400000; Items = 400000 }
                    [ordered]@{ ResourceId = $web.id; Table = 'AppDependencies'; GB = 2.0; Rows = 300000; Items = 300000 }
                )
                daily    = @(
                    foreach ($i in 0..6) { & $day $orders.id $i 0.5 }
                    foreach ($i in 0..5) { & $day $web.id $i 1.5 }
                    & $day $web.id 6 6.0
                )
                traces   = @(
                    [ordered]@{ ResourceId = $web.id; SeverityLevel = 0; GB = 7.0 }
                    [ordered]@{ ResourceId = $web.id; SeverityLevel = 1; GB = 1.0 }
                    [ordered]@{ ResourceId = $web.id; SeverityLevel = 3; GB = 1.0 }
                )
                requests = @(
                    [ordered]@{ ResourceId = $orders.id; Rows = 30000; Health = 300 }
                    [ordered]@{ ResourceId = $web.id; Rows = 400000; Health = 120000 }
                )
            }
            'cid-eu'   = @{ tables = @(); daily = @(); traces = @(); requests = @() }
        }
        Activity = @(
            @{ ResourceId = $web.id; Operation = 'Microsoft.Insights/components/purge/action'; OperationName = 'Purge'; Status = 'Succeeded'; Upn = 'alice@contoso.com'; AppId = ''; Caller = 'alice@contoso.com'; Count = 1; First = (Get-Date '2026-11-03'); Last = (Get-Date '2026-11-03') }
            @{ ResourceId = $web.id; Operation = 'Microsoft.Insights/components/write'; OperationName = 'Update component'; Status = 'Succeeded'; Upn = 'alice@contoso.com'; AppId = ''; Caller = 'alice@contoso.com'; Count = 2; First = (Get-Date '2026-11-02'); Last = (Get-Date '2026-11-04') }
            @{ ResourceId = "$($web.id)/apikeys/k1"; Operation = 'Microsoft.Insights/components/ApiKeys/write'; OperationName = 'Create API key'; Status = 'Succeeded'; Upn = ''; AppId = 'app-grafana'; Caller = 'app-grafana'; Count = 1; First = (Get-Date '2026-11-05'); Last = (Get-Date '2026-11-05') }
            @{ ResourceId = $web.id; Operation = 'Microsoft.Insights/components/write'; OperationName = 'Update component'; Status = 'Failed'; Upn = ''; AppId = 'app-pipeline'; Caller = 'app-pipeline'; Count = 3; First = (Get-Date '2026-11-01'); Last = (Get-Date '2026-11-06') }
            @{ ResourceId = "$($web.id)-2";Operation = 'Microsoft.Insights/components/write'; OperationName = 'Update component'; Status = 'Succeeded'; Upn = 'carol@contoso.com'; AppId = ''; Caller = 'carol@contoso.com'; Count = 1; First = (Get-Date '2026-11-01'); Last = (Get-Date '2026-11-01') }
        )
        Scope    = @{
            Subscriptions = @(@{ subscriptionId = $prod; name = 'Contoso Prod' }, @{ subscriptionId = $dev; name = 'Contoso Dev' })
            Ids = @($prod, $dev); GraphScope = @(); Label = 'all 2 subscription(s)'
            Names = @{ $prod = 'Contoso Prod'; $dev = 'Contoso Dev' }
        }
    }
}
