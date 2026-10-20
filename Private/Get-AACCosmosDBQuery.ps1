function Get-AACCosmosDBQuery {
    <#
    .SYNOPSIS
        The Resource Graph batch Invoke-AACCosmosDBAssessment reads: the
        Azure Cosmos DB accounts, the Defender for Azure Cosmos DB plan and
        its alerts, and the Log Analytics workspaces (for their names).
    .DESCRIPTION
          accounts    every Cosmos DB account in scope, with its kind and
                      properties - regions, failover, consistency, backup,
                      capabilities (API, serverless), network access, local
                      authentication, TLS, encryption
          pricing     Defender plans named CosmosDbs, per subscription
          alerts      Defender alerts on a Cosmos DB account, last 30 days
          workspaces  every workspace (tenant-wide: an account's logs often
                      go to another subscription's)
        -ResourceGroupName narrows the accounts and alerts.
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
        accounts   = "resources | where type =~ 'microsoft.documentdb/databaseaccounts'$in | project id = tolower(id), name, location, resourceGroup, subscriptionId = tolower(subscriptionId), kind, properties, identity, tags"
        pricing    = "securityresources | where type =~ 'microsoft.security/pricings' and name =~ 'CosmosDbs' | project subscriptionId = tolower(subscriptionId), tier = tostring(properties.pricingTier)"
        alerts     = "securityresources | where type =~ 'microsoft.security/locations/alerts' and tostring(properties.resourceIdentifiers) contains 'microsoft.documentdb/databaseaccounts'$in | where todatetime(properties.timeGeneratedUtc) > ago(30d) | mv-expand rid = properties.resourceIdentifiers | where tostring(rid.azureResourceId) contains 'microsoft.documentdb/databaseaccounts' | project resourceId = tolower(tostring(rid.azureResourceId)), name = tostring(properties.alertDisplayName), severity = tostring(properties.severity), status = tostring(properties.status)"
        workspaces = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name" }
    }
}
