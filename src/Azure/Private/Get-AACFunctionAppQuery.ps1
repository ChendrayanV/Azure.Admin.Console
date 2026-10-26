function Get-AACFunctionAppQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries Invoke-AACFunctionAppAssessment
        reads: the function apps, their App Service plans and deployment
        slots, the private endpoints to them, Advisor recommendations,
        Defender for Cloud assessments and the subscriptions' names.
    .DESCRIPTION
        Function apps are Microsoft.Web/sites whose kind contains
        'functionapp' (Windows, Linux, containers - not Logic Apps
        Standard, whose kind adds 'workflowapp'). -ResourceGroupName
        narrows the apps; plans and slots are read in the same resource
        groups' subscriptions and matched by ID afterwards.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName = @()
    )

    $groups = if (@($ResourceGroupName | Where-Object { $_ }).Count) { " | where resourceGroup in~ ($((@($ResourceGroupName | Where-Object { $_ } | ForEach-Object { ConvertTo-AACKqlLiteral -Text $_ })) -join ', '))" } else { '' }
    [ordered]@{
        apps             = "resources | where type =~ 'microsoft.web/sites' and kind contains 'functionapp' and kind !contains 'workflowapp'$groups | project id, name, kind, location, resourceGroup, subscriptionId, tags, identity, properties"
        plans            = "resources | where type =~ 'microsoft.web/serverfarms' | project id, name, kind, location, resourceGroup, subscriptionId, tags, sku, properties"
        slots            = "resources | where type =~ 'microsoft.web/sites/slots' | project id, name, kind, location, resourceGroup, subscriptionId, properties"
        privateEndpoints = "resources | where type =~ 'microsoft.network/privateendpoints' | mv-expand connection = array_concat(coalesce(properties.privateLinkServiceConnections, dynamic([])), coalesce(properties.manualPrivateLinkServiceConnections, dynamic([]))) | where tostring(connection.properties.privateLinkServiceId) contains '/microsoft.web/sites/' | project id, name, target = tolower(tostring(connection.properties.privateLinkServiceId)), status = tostring(connection.properties.privateLinkServiceConnectionState.status), subnet = tostring(properties.subnet.id)"
        advisor          = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | where tostring(properties.resourceMetadata.resourceId) contains '/microsoft.web/' | project resourceId = tolower(tostring(properties.resourceMetadata.resourceId)), category = tostring(properties.category), impact = tostring(properties.impact), problem = tostring(properties.shortDescription.problem), solution = tostring(properties.shortDescription.solution)"
        defender         = "securityresources | where type =~ 'microsoft.security/assessments' | where tostring(properties.status.code) =~ 'Unhealthy' | where tostring(properties.resourceDetails.Id) contains '/microsoft.web/sites/' | project resourceId = tolower(tostring(properties.resourceDetails.Id)), name = tostring(properties.displayName), severity = tostring(properties.metadata.severity), remediation = tostring(properties.metadata.remediationDescription)"
        subscriptions    = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"
    }
}
