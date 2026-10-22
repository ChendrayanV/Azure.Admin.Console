function Get-AACResourceExportQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph query behind Export-AACResource: every resource,
        joined to its subscription (name, state, management group chain) and its
        resource group (tags, location) from resourcecontainers.
    .DESCRIPTION
        The filters Resource Graph can apply are applied there, so only the rows
        wanted come back: -ResourceType, -ResourceGroupName, -Name and -Location
        when they have no wildcards (with wildcards, the command filters them
        afterwards), -Tag (an exact value, or '*' for any value), -MissingTag,
        and -Filter, a KQL condition of your own appended as '| where <Filter>'.

        Both joins are to resourcecontainers, which Resource Graph allows (up to
        three joins when they are all between resources and resourcecontainers).
        The resource group is matched on a lower-case ID built from the
        resource's subscription and group, because resource group names keep
        whatever case they were created with.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string[]] $ResourceType,

        [string[]] $ResourceGroupName,

        [string[]] $Name,

        [string[]] $Location,

        [hashtable] $Tag,

        [string[]] $MissingTag,

        [string] $Filter
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $exact = { param([string[]] $Value) @($Value | Where-Object { $_ -and $_ -notmatch '[*?]' }) }
    $hasWildcard = { param([string[]] $Value) [bool]@($Value | Where-Object { $_ -match '[*?]' }).Count }
    $in = { param([string] $Column, [string[]] $Value) "| where $Column in~ ($((@($Value | ForEach-Object { & $quote $_ })) -join ', '))" }

    $where = [System.Collections.Generic.List[string]]::new()
    # A list with a wildcard in it is filtered afterwards, all of it - an exact
    # filter here would drop what the wildcard should have kept.
    if ($ResourceType -and -not (& $hasWildcard $ResourceType)) { $where.Add((& $in 'type' (& $exact $ResourceType))) }
    if ($ResourceGroupName -and -not (& $hasWildcard $ResourceGroupName)) { $where.Add((& $in 'resourceGroup' (& $exact $ResourceGroupName))) }
    if ($Name -and -not (& $hasWildcard $Name)) { $where.Add((& $in 'name' (& $exact $Name))) }
    if ($Location) { $where.Add((& $in 'location' @($Location | ForEach-Object { $_ -replace '\s', '' }))) }
    if ($Tag) {
        foreach ($key in $Tag.Keys) {
            $value = [string]$Tag[$key]
            $where.Add($(if ($value -eq '*' -or -not $value) { "| where isnotempty(tags[$(& $quote $key)])" } else { "| where tostring(tags[$(& $quote $key)]) =~ $(& $quote $value)" }))
        }
    }
    foreach ($key in @($MissingTag | Where-Object { $_ })) { $where.Add("| where isempty(tags[$(& $quote $key)])") }
    if ($Filter) { $where.Add("| where $Filter") }

    @(
        'resources'
        $where
        "| extend groupKey = tolower(strcat('/subscriptions/', subscriptionId, '/resourcegroups/', resourceGroup))"
        "| join kind=leftouter (resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, subscriptionName = name, subscriptionState = tostring(properties.state), managementGroupChain = properties.managementGroupAncestorsChain) on subscriptionId"
        "| join kind=leftouter (resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' | project groupKey = tolower(id), groupTags = tags, groupLocation = location) on groupKey"
        '| project id, name, type, kind, location, resourceGroup, subscriptionId, subscriptionName, subscriptionState, managementGroupChain, groupTags, groupLocation, zones, sku, plan, identity, managedBy, tags, extendedLocation, properties'
    ) -join ' '
}
