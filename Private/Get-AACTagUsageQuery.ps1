function Get-AACTagUsageQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACTagUsage: each tag
        name's use on resources, resource groups and subscriptions -
        counted in the query - with its distinct values, and how many of
        each are tagged at all.
    .DESCRIPTION
        Returns an ordered hashtable for Invoke-AACGraphBatch:
          resourceTags, groupTags, subscriptionTags
                    name, uses, valueCount, values (up to 50 distinct)
          totals    how many resources, resource groups and subscriptions,
                    and how many have at least one tag
        Azure's own hidden tags (hidden-*, link:*) are left out.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $expand = "mv-expand bagexpansion = array tags | extend name = tostring(tags[0]), value = tostring(tags[1]) | where isnotempty(name) and name !startswith 'hidden-' and name !startswith 'link:' | summarize uses = count(), valueCount = dcount(value), values = make_set(value, 50) by name"
    $groups = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'"
    $subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions'"
    [ordered]@{
        resourceTags     = "resources | where array_length(bag_keys(tags)) > 0 | $expand"
        groupTags        = "$groups | where array_length(bag_keys(tags)) > 0 | $expand"
        subscriptionTags = "$subscriptions | where array_length(bag_keys(tags)) > 0 | $expand"
        totals           = "resources | summarize total = count(), tagged = countif(array_length(bag_keys(tags)) > 0) | extend kind = 'resources' | union ($groups | summarize total = count(), tagged = countif(array_length(bag_keys(tags)) > 0) | extend kind = 'resourceGroups') | union ($subscriptions | summarize total = count(), tagged = countif(array_length(bag_keys(tags)) > 0) | extend kind = 'subscriptions')"
    }
}
