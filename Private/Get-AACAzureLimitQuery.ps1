function Get-AACAzureLimitQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Test-AACAzureLimit: what
        counts toward each Azure limit, counted in the query - so only the
        totals come back, however large the tenant.
    .DESCRIPTION
        Returns an ordered hashtable for Invoke-AACGraphBatch. Role
        assignments, custom roles, policy definitions, sets, assignments
        and exemptions, and management groups are counted tenant-wide (a
        management group's count includes what sits above the selected
        subscriptions); resource groups and tags per subscription in scope.

          rbacBySubscription  role assignments at or below each subscription
          rbacByGroup         role assignments at each management group
          customRoles         custom role definitions in the tenant
          policyAssignments   policy and initiative assignments, per scope
          policyDefinitions   custom policy definitions, per scope
          policySets          custom initiative definitions, per scope
          policyExemptions    exemptions, per scope
          managementGroups    every management group and its depth
          resourceGroups      resource groups per subscription
          subscriptionTags    tags on each subscription
          groupTags           the resource group with the most tags, per subscription
          resourceTags        the resource with the most tags, per subscription
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    # The scope a definition, set or exemption lives at: its ID up to /providers/Microsoft.Authorization/.
    $atScope = "extend scope = tolower(substring(id, 0, indexof(tolower(id), '/providers/microsoft.authorization/')))"
    [ordered]@{
        rbacBySubscription = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend scope = tolower(tostring(properties.scope)) | where scope startswith '/subscriptions/' | extend subscriptionId = tostring(split(scope, '/')[2]) | summarize used = count() by subscriptionId" }
        rbacByGroup        = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend scope = tolower(tostring(properties.scope)) | where scope startswith '/providers/microsoft.management/managementgroups/' | summarize used = count() by scope" }
        customRoles        = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' and tostring(properties.type) =~ 'CustomRole' | summarize used = count()" }
        policyAssignments  = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | extend scope = tolower(tostring(properties.scope)) | summarize used = count() by scope" }
        policyDefinitions  = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policydefinitions' and tostring(properties.policyType) =~ 'Custom' | $atScope | summarize used = count() by scope" }
        policySets         = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policysetdefinitions' and tostring(properties.policyType) =~ 'Custom' | $atScope | summarize used = count() by scope" }
        policyExemptions   = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyexemptions' | $atScope | summarize used = count() by scope" }
        managementGroups   = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project name = tolower(name), displayName = tostring(properties.displayName), depth = array_length(properties.details.managementGroupAncestorsChain)" }
        resourceGroups     = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' | summarize used = count() by subscriptionId"
        subscriptionTags   = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, used = array_length(bag_keys(tags))"
        groupTags          = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' | extend used = array_length(bag_keys(tags)) | where used > 0 | summarize arg_max(used, name) by subscriptionId"
        resourceTags       = "resources | extend used = array_length(bag_keys(tags)) | where used > 0 | summarize arg_max(used, name, type) by subscriptionId"
    }
}
