function Get-AACWafQuery {
    <#
    .SYNOPSIS
        The one Resource Graph batch Invoke-AACWafAssessment reads: every
        resource its checks test, what is backed up, Advisor's
        recommendations and Defender for Cloud's plans, secure scores and
        high-severity assessments - all run at once, all checks evaluated
        locally against the result.
    .DESCRIPTION
          resources    the resource types the catalogue tests, with sku,
                       zones, identity and properties
          groups       the resource groups, with their tags
          inventory    every resource, counted by type, subscription and
                       resource group (Advisor's denominator, and the alert
                       rules and action groups a subscription has)
          extensions   VM extensions (the Azure Monitor agent)
          autoscale    enabled autoscale settings' targets
          slots        web apps' deployment slots
          backup       protected items' source resource IDs
          advisor      Advisor recommendations in -AdvisorCategory
          pricing      Defender plans per subscription
          secureScore  the secure score per subscription
          assessments  Defender's high-severity assessments, healthy or not
        -ResourceGroupName narrows the resource-level queries.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string[]] $ResourceType,

        [string[]] $ResourceGroupName,

        [string[]] $AdvisorCategory = @(),

        [switch] $NoDefender
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $list = { param([string[]] $Items) (@($Items | ForEach-Object { & $quote $_ })) -join ', ' }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($(& $list $groups))" } else { '' }

    $queries = [ordered]@{
        resources = "resources | where type in~ ($(& $list ($ResourceType | Where-Object { $_ -notin 'microsoft.resources/subscriptions', 'microsoft.resources/subscriptions/resourcegroups' })))$in | project id = tolower(id), name, type = tolower(type), kind, location, resourceGroup, subscriptionId = tolower(subscriptionId), sku, zones, identity, tags, properties"
        inventory = "resources$in | summarize n = count() by type = tolower(type), subscriptionId = tolower(subscriptionId), resourceGroup"
        groups     = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'$($in -replace 'resourceGroup', 'name') | project id = tolower(id), name, type = 'microsoft.resources/subscriptions/resourcegroups', resourceGroup = name, subscriptionId = tolower(subscriptionId), location, tags"
        extensions = "resources | where type =~ 'microsoft.compute/virtualmachines/extensions'$in | project vm = tolower(tostring(split(id, '/extensions/')[0])), extension = tostring(properties.type)"
        autoscale  = "resources | where type =~ 'microsoft.insights/autoscalesettings' and properties.enabled == true | project target = tolower(tostring(properties.targetResourceUri))"
        slots      = "resources | where type =~ 'microsoft.web/sites/slots'$in | project site = tolower(tostring(split(id, '/slots/')[0]))"
        backup    = "recoveryservicesresources | where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' | project id = tolower(tostring(properties.sourceResourceId)) | where isnotempty(id)"
    }
    if ($AdvisorCategory.Count) {
        $queries['advisor'] = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | where tostring(properties.category) in~ ($(& $list $AdvisorCategory))$in | project resourceId = tolower(tostring(properties.resourceMetadata.resourceId)), category = tostring(properties.category), impact = tostring(properties.impact), problem = tostring(properties.shortDescription.problem), solution = tostring(properties.shortDescription.solution), impactedType = tolower(tostring(properties.impactedField)), typeId = tostring(properties.recommendationTypeId), subscriptionId = tolower(subscriptionId), resourceGroup"
    }
    if (-not $NoDefender) {
        $queries['pricing'] = "securityresources | where type =~ 'microsoft.security/pricings' | project subscriptionId = tolower(subscriptionId), name, tier = tostring(properties.pricingTier)"
        $queries['secureScore'] = "securityresources | where type =~ 'microsoft.security/securescores' and name =~ 'ascScore' | project subscriptionId = tolower(subscriptionId), current = todouble(properties.score.current), max = todouble(properties.score.max)"
        $queries['assessments'] = "securityresources | where type =~ 'microsoft.security/assessments' and tostring(properties.metadata.severity) =~ 'High' and tostring(properties.status.code) in~ ('Healthy', 'Unhealthy')$in | project resourceId = tolower(tostring(properties.resourceDetails.Id)), name = tostring(properties.displayName), status = tostring(properties.status.code), remediation = tostring(properties.metadata.remediationDescription), subscriptionId = tolower(subscriptionId), resourceGroup"
    }
    $queries
}
