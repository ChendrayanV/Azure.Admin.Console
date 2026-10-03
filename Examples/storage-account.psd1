# Deploy-AACStorageAccount configuration - the Azure Verified Module's parameter
# names (avm/res/storage/storage-account). Anything left out takes AVM's
# default: StorageV2, Standard_GRS, Hot, TLS 1.2, HTTPS only, no public blob
# access, infrastructure encryption, network rules denying by default.
#
#   Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-contoso-data -ConfigurationPath .\Examples\storage-account.psd1 -WhatIf
#
@{
    name                      = 'stcontosodata'
    skuName                   = 'Standard_ZRS'
    allowSharedKeyAccess      = $false
    tags                      = @{ env = 'prod'; owner = 'data-platform' }

    networkAcls               = @{
        defaultAction       = 'Deny'
        bypass              = 'AzureServices'
        ipRules             = @('203.0.113.10')
        virtualNetworkRules = @('/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-contoso-net/providers/Microsoft.Network/virtualNetworks/vnet-contoso/subnets/snet-data')
    }

    blobServices              = @{
        deleteRetentionPolicyEnabled          = $true
        deleteRetentionPolicyDays             = 14
        containerDeleteRetentionPolicyEnabled = $true
        containerDeleteRetentionPolicyDays    = 14
        isVersioningEnabled                   = $true
        containers                            = @(
            @{ name = 'raw'; publicAccess = 'None'; metadata = @{ source = 'ingest' } }
            @{
                name            = 'curated'
                roleAssignments = @(@{ roleDefinitionIdOrName = 'Storage Blob Data Reader'; principalId = '00000000-0000-0000-0000-000000000000'; principalType = 'Group' })
            }
        )
        diagnosticSettings                    = @(@{ workspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-contoso-monitor/providers/Microsoft.OperationalInsights/workspaces/law-contoso' })
    }
    fileServices              = @{ shares = @(@{ name = 'exports'; shareQuota = 100 }) }
    queueServices             = @{ queues = @('ingest-jobs') }
    tableServices             = @{ tables = @('runs') }

    managementPolicyRules     = @(
        @{
            name = 'cool-after-30-days'; enabled = $true; type = 'Lifecycle'
            definition = @{
                actions = @{ baseBlob = @{ tierToCool = @{ daysAfterModificationGreaterThan = 30 }; delete = @{ daysAfterModificationGreaterThan = 365 } } }
                filters = @{ blobTypes = @('blockBlob'); prefixMatch = @('raw/') }
            }
        }
    )

    # Account-level diagnostic settings carry metrics only; logs are on the services.
    diagnosticSettings        = @(@{ workspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-contoso-monitor/providers/Microsoft.OperationalInsights/workspaces/law-contoso' })
    roleAssignments           = @(@{ roleDefinitionIdOrName = 'Storage Blob Data Contributor'; principalId = '00000000-0000-0000-0000-000000000000'; principalType = 'ServicePrincipal' })
    lock                      = @{ kind = 'CanNotDelete' }

    # Not AVM's: files to upload (only when new or changed).
    blobs                     = @(@{ container = 'raw'; path = '.\README.md'; name = 'docs/README.md'; contentType = 'text/markdown' })
}
