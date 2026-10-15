function Get-AACKeyVaultQuery {
    <#
    .SYNOPSIS
        The Resource Graph batch Get-AACKeyVaultInsight reads: the vaults,
        the Defender for Key Vault plan and alerts, and the Log Analytics
        workspaces (for their query IDs).
    .DESCRIPTION
          vaults      every Key Vault in scope, with SKU and properties
          pricing     Defender plans named KeyVaults, per subscription
          alerts      Defender alerts on a Key Vault, last 30 days
          workspaces  every workspace the account can see (tenant-wide: a
                      vault's logs often go to another subscription's)
        -ResourceGroupName narrows the vaults and alerts.
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
        vaults     = "resources | where type =~ 'microsoft.keyvault/vaults'$in | project id = tolower(id), name, location, resourceGroup, subscriptionId = tolower(subscriptionId), sku = tostring(properties.sku.name), properties, tags"
        pricing    = "securityresources | where type =~ 'microsoft.security/pricings' and name =~ 'KeyVaults' | project subscriptionId = tolower(subscriptionId), tier = tostring(properties.pricingTier)"
        alerts     = "securityresources | where type =~ 'microsoft.security/locations/alerts' and tostring(properties.resourceIdentifiers) contains 'microsoft.keyvault/vaults'$in | where todatetime(properties.timeGeneratedUtc) > ago(30d) | mv-expand rid = properties.resourceIdentifiers | where tostring(rid.azureResourceId) contains 'microsoft.keyvault/vaults' | project resourceId = tolower(tostring(rid.azureResourceId)), name = tostring(properties.alertDisplayName), severity = tostring(properties.severity), status = tostring(properties.status)"
        workspaces = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name, customerId = tostring(properties.customerId)" }
    }
}
