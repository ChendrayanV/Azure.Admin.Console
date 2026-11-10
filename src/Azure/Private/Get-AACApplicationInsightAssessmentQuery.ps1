function Get-AACApplicationInsightAssessmentQuery {
    <#
    .SYNOPSIS
        The Resource Graph batch Invoke-AACApplicationInsightAssessment reads:
        the Application Insights components, the workspaces they write to,
        their availability tests, the alert rules on them and the locks
        above them.
    .DESCRIPTION
          components  every component in scope, with its properties -
                      ingestion mode and workspace, local authentication, IP
                      masking, public network access, private link scopes,
                      sampling, retention, creation date
          workspaces  every Log Analytics workspace (tenant-wide: a
                      component often writes to another subscription's), with
                      its region, query ID, retention, daily cap and access
                      mode
          webtests    availability tests, with the hidden-link tag naming
                      their component, kind (ping, standard, multistep),
                      enabled and how many locations
          alerts      metric alerts, log search alerts and smart detector
                      rules, with what they watch (scopes) and their action
                      groups
          locks       management locks (the converter matches them to the
                      component, its resource group or subscription)
        -ResourceGroupName narrows the components.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName
    )

    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { ConvertTo-AACKqlLiteral -Text $_ })) -join ', '))" } else { '' }
    [ordered]@{
        components = "resources | where type =~ 'microsoft.insights/components'$in | project id = tolower(id), name, location, resourceGroup, subscriptionId = tolower(subscriptionId), kind, properties, tags"
        workspaces = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name, location, customerId = tostring(properties.customerId), sku = tostring(properties.sku.name), retentionInDays = toint(properties.retentionInDays), dailyQuotaGb = todouble(properties.workspaceCapping.dailyQuotaGb), resourcePermissions = tostring(properties.features.enableLogAccessUsingOnlyResourcePermissions)" }
        webtests   = "resources | where type =~ 'microsoft.insights/webtests' | project id = tolower(id), name, resourceGroup, subscriptionId = tolower(subscriptionId), tags, kind = tostring(properties.Kind), enabled = tostring(properties.Enabled), locations = array_length(properties.Locations)"
        alerts     = "resources | where type in~ ('microsoft.insights/metricalerts', 'microsoft.insights/scheduledqueryrules', 'microsoft.alertsmanagement/smartdetectoralertrules') | project id = tolower(id), name, type = tolower(type), enabled = coalesce(tostring(properties.enabled), tostring(properties.state)), scopes = tolower(tostring(coalesce(properties.scopes, properties.scope))), actions = tolower(coalesce(tostring(properties.actions), tostring(properties.actionGroups))), detector = tostring(properties.detector.id)"
        locks      = "resources | where type =~ 'microsoft.authorization/locks' | project id = tolower(id), level = tostring(properties.level)"
    }
}
