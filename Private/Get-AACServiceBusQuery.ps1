function Get-AACServiceBusQuery {
    <#
    .SYNOPSIS
        The Resource Graph batch Invoke-AACServiceBusAssessment reads: the
        Service Bus namespaces and the Log Analytics workspaces (for their
        names).
    .DESCRIPTION
          namespaces  every namespace in scope, with its SKU (tier and
                      messaging units) and properties - TLS, local (SAS)
                      authentication, public network access, zone
                      redundancy, private endpoints, encryption, geo-
                      replication
          workspaces  every workspace (tenant-wide: a namespace's logs often
                      go to another subscription's)
        -ResourceGroupName narrows the namespaces.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName
    )

    $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    [ordered]@{
        namespaces = "resources | where type =~ 'microsoft.servicebus/namespaces'$in | project id = tolower(id), name, location, resourceGroup, subscriptionId = tolower(subscriptionId), tier = tostring(sku.tier), capacity = toint(sku.capacity), properties, identity, tags"
        workspaces = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name" }
    }
}
