function Get-AACStorageAccountQuery {
    <#
    .SYNOPSIS
        The Resource Graph batch Invoke-AACStorageAccountAssessment reads: the
        storage accounts, the Defender for Storage plan and its alerts, and
        the Log Analytics workspaces (for their names).
    .DESCRIPTION
          accounts    every storage account in scope, with kind, SKU, access
                      tier and properties
          pricing     Defender plans named StorageAccounts, per subscription
          alerts      Defender alerts on a storage account, last 30 days
          workspaces  every workspace the account can see (tenant-wide: an
                      account's logs often go to another subscription's)
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
        accounts   = "resources | where type =~ 'microsoft.storage/storageaccounts'$in | project id = tolower(id), name, location, resourceGroup, subscriptionId = tolower(subscriptionId), kind, sku = tostring(sku.name), accessTier = tostring(properties.accessTier), properties, tags"
        pricing    = "securityresources | where type =~ 'microsoft.security/pricings' and name =~ 'StorageAccounts' | project subscriptionId = tolower(subscriptionId), tier = tostring(properties.pricingTier)"
        alerts     = "securityresources | where type =~ 'microsoft.security/locations/alerts' and tostring(properties.resourceIdentifiers) contains 'microsoft.storage/storageaccounts'$in | where todatetime(properties.timeGeneratedUtc) > ago(30d) | mv-expand rid = properties.resourceIdentifiers | where tostring(rid.azureResourceId) contains 'microsoft.storage/storageaccounts' | project resourceId = tolower(tostring(rid.azureResourceId)), name = tostring(properties.alertDisplayName), severity = tostring(properties.severity), status = tostring(properties.status)"
        workspaces = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name" }
    }
}
