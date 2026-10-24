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

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    [ordered]@{
        accounts   = "resources | where type =~ 'microsoft.storage/storageaccounts'$in | project id = tolower(id), name, location, resourceGroup, subscriptionId = tolower(subscriptionId), kind, sku = tostring(sku.name), accessTier = tostring(properties.accessTier), properties, tags"
        pricing    = Get-AACCommonQuery -Kind DefenderPlan -Plan 'StorageAccounts'
        alerts     = Get-AACCommonQuery -Kind DefenderAlert -ResourceType 'microsoft.storage/storageaccounts' -Filter $in
        workspaces = Get-AACCommonQuery -Kind WorkspaceName
    }
}
