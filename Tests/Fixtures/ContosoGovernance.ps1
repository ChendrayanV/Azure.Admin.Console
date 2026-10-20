<#
    Made-up governance data for GovernanceSetting.Tests.ps1,
    TagUsage.Tests.ps1 and ResourceLock.Tests.ps1, as Resource Manager and
    Resource Graph return it. Two subscriptions: sub-prod (Enterprise
    Agreement) and sub-dev (Visual Studio).

    Settings: anyone may create management groups; new subscriptions land
    in the root; sub-prod has a security contact with alerts on but not to
    owners; sub-dev has none and a classic co-administrator, a registered
    preview feature, and Microsoft.Kusto registered only in sub-prod.

    Tags: 'Environment' and 'environment' (casing clash), 'cost-center' and
    'CostCenter' (near-duplicate), env values 'Prod'/'prod' (value casing),
    'owner' required but on 2 of 10 resources, 'tmp' used once.

    Locks: CanNotDelete on sub-prod's rg-core, ReadOnly on sub-dev, and a
    resource lock on kv-app; critical resources kv-app (direct), st-core
    (through rg-core), st-dev (through sub-dev's ReadOnly lock) and sql-legacy
    (unlocked, in sub-prod's rg-old).
#>
function Get-AACContosoGovernance {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $tags = { param([string] $Name, [int] $Uses, [string[]] $Values) @{ name = $Name; uses = $Uses; valueCount = $Values.Count; values = $Values } }
    $lock = { param([string] $Scope, [string] $Name, [string] $Level, [string] $Notes = '') @{ id = "$Scope/providers/Microsoft.Authorization/locks/$Name"; name = $Name; properties = @{ level = $Level; notes = $Notes } } }
    @{
        TenantId      = 't-1'
        Prod          = $prod
        Dev           = $dev
        Subscriptions = @(
            @{ subscriptionId = $prod; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-root' }) }
            @{ subscriptionId = $dev; name = 'sub-dev'; state = 'Enabled'; chain = @(@{ name = 'mg-root' }) }
        )
        Names         = @{ $prod = 'sub-prod'; $dev = 'sub-dev' }
        Details       = @(@{ subscriptionId = $prod; quotaId = 'EnterpriseAgreement_2014-09-01'; spendingLimit = 'Off' }, @{ subscriptionId = $dev; quotaId = 'MSDN_2014-09-01'; spendingLimit = 'On' })
        Hierarchy     = @{ properties = @{ requireAuthorizationForGroupCreation = $false; defaultManagementGroup = '/providers/Microsoft.Management/managementGroups/t-1' } }
        PerSubscription = @{
            $prod = @{ Errors = @{}
                Contacts  = @(@{ name = 'default'; properties = @{ emails = 'secops@contoso.example'; alertNotifications = @{ state = 'On'; minimalSeverity = 'High' }; notificationsByRole = @{ state = 'On'; roles = @('AccountAdmin') } } })
                Classic   = @(@{ properties = @{ emailAddress = 'billing@contoso.example'; role = 'ServiceAdministrator' } })
                Features  = @(@{ name = 'Microsoft.Compute/EncryptionAtHost'; properties = @{ state = 'NotRegistered' } })
                Providers = @(@{ namespace = 'Microsoft.Compute'; registrationState = 'Registered' }, @{ namespace = 'Microsoft.Kusto'; registrationState = 'Registered' })
            }
            $dev  = @{ Errors = @{}
                Contacts  = @()
                Classic   = @(@{ properties = @{ emailAddress = 'old-admin@contoso.example'; role = 'CoAdministrator' } })
                Features  = @(@{ name = 'Microsoft.Network/AllowPreviewThing'; properties = @{ state = 'Registered' } })
                Providers = @(@{ namespace = 'Microsoft.Compute'; registrationState = 'Registered' }, @{ namespace = 'Microsoft.Kusto'; registrationState = 'NotRegistered' })
            }
        }
        GroupDiag     = [ordered]@{
            'mg-root'     = @{ Items = @(@{ name = 'to-law'; properties = @{ workspaceId = '/subscriptions/x/resourcegroups/rg/providers/microsoft.operationalinsights/workspaces/law-platform'; logs = @(@{ category = 'Administrative'; enabled = $true }, @{ category = 'Policy'; enabled = $true }) } }) }
            'mg-platform' = @{ Items = @() }
        }
        TagRead       = @{
            Errors = @{}
            Rows   = @{
                resourceTags     = @(
                    (& $tags 'Environment' 6 @('Prod', 'prod', 'Dev'))
                    (& $tags 'environment' 2 @('test'))
                    (& $tags 'cost-center' 4 @('1001', '1002'))
                    (& $tags 'CostCenter' 3 @('1001'))
                    (& $tags 'owner' 2 @('alice', 'bob'))
                    (& $tags 'tmp' 1 @('x'))
                )
                groupTags        = @((& $tags 'Environment' 3 @('Prod')), (& $tags 'owner' 3 @('alice')))
                subscriptionTags = @((& $tags 'Environment' 2 @('Prod', 'Dev')))
                totals           = @(@{ kind = 'resources'; total = 10; tagged = 8 }, @{ kind = 'resourceGroups'; total = 4; tagged = 3 }, @{ kind = 'subscriptions'; total = 2; tagged = 2 })
            }
        }
        Locks         = @(
            (& $lock "/subscriptions/$prod/resourceGroups/rg-core" 'core-nodelete' 'CanNotDelete' 'Platform core')
            (& $lock "/subscriptions/$dev" 'dev-freeze' 'ReadOnly')
            (& $lock "/subscriptions/$prod/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv-app" 'kv-nodelete' 'CanNotDelete')
        )
        Groups        = @(
            @{ id = "/subscriptions/$prod/resourcegroups/rg-core"; name = 'rg-core'; subscriptionId = $prod }
            @{ id = "/subscriptions/$prod/resourcegroups/rg-app"; name = 'rg-app'; subscriptionId = $prod }
            @{ id = "/subscriptions/$prod/resourcegroups/rg-old"; name = 'rg-old'; subscriptionId = $prod }
            @{ id = "/subscriptions/$dev/resourcegroups/rg-dev"; name = 'rg-dev'; subscriptionId = $dev }
        )
        Critical      = @(
            @{ id = "/subscriptions/$prod/resourcegroups/rg-app/providers/microsoft.keyvault/vaults/kv-app"; name = 'kv-app'; type = 'microsoft.keyvault/vaults'; resourceGroup = 'rg-app'; subscriptionId = $prod }
            @{ id = "/subscriptions/$prod/resourcegroups/rg-core/providers/microsoft.storage/storageaccounts/stcore"; name = 'stcore'; type = 'microsoft.storage/storageaccounts'; resourceGroup = 'rg-core'; subscriptionId = $prod }
            @{ id = "/subscriptions/$dev/resourcegroups/rg-dev/providers/microsoft.storage/storageaccounts/stdev"; name = 'stdev'; type = 'microsoft.storage/storageaccounts'; resourceGroup = 'rg-dev'; subscriptionId = $dev }
            @{ id = "/subscriptions/$prod/resourcegroups/rg-old/providers/microsoft.sql/servers/sql-legacy"; name = 'sql-legacy'; type = 'microsoft.sql/servers'; resourceGroup = 'rg-old'; subscriptionId = $prod }
        )
    }
}
