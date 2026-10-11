<#
    Made-up identities for OrphanedIdentity.Tests.ps1, as Azure Resource
    Graph, the federated credential calls, Get-AACDirectoryObject and
    Microsoft Graph return them:

      p-deleted     Owner on sub-prod, gone from Entra ID         -> High
      p-deleted2    Reader on rg-app, gone                        -> Medium
      uai-used      attached to vm1                               -> nothing
      uai-loose     attached to nothing, no federated credential;
                    Reader on sub-prod                            -> Medium
      uai-fed       attached to nothing, one federated credential -> nothing
      uai-unread    attached to nothing, credentials not read     -> Low
      mi-gone       managed identity of a deleted web app; Reader -> Medium
      app-stale     last sign-in 200 days ago; Owner on mg-root   -> High
      app-active    signed in 5 days ago                          -> nothing
      app-disabled  disabled service principal with a role        -> Medium
      app-expired   every credential expired, no owners           -> Medium
      app-noowner   no owners                                     -> Low
      sp-foreign    another tenant's app                          -> nothing
      an assignment in a subscription out of scope                -> ignored
#>
function Get-AACContosoIdentity {
    $sub = '11111111-1111-1111-1111-111111111111'
    $other = '99999999-9999-9999-9999-999999999999'
    $now = [datetime]::UtcNow
    $ago = { param([int] $Days) $now.AddDays(-$Days).ToString('o', [cultureinfo]::InvariantCulture) }
    $owner = '/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    $reader = '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
    $uai = { param([string] $Name) "/subscriptions/$sub/resourcegroups/rg-id/providers/microsoft.managedidentity/userassignedidentities/$Name" }
    $assignment = { param([string] $Principal, [string] $Role, [string] $Scope, [string] $Type = 'ServicePrincipal') @{ id = "ra-$Principal-$($Scope.GetHashCode())"; principalId = $Principal; principalType = $Type; roleId = $Role; scope = $Scope.ToLowerInvariant(); createdOn = '' } }
    $vm1 = "/subscriptions/$sub/resourcegroups/rg-app/providers/microsoft.compute/virtualmachines/vm1"
    $credential = { param([int] $EndsInDays) @{ keyId = [guid]::NewGuid().ToString(); endDateTime = $now.AddDays($EndsInDays).ToString('o', [cultureinfo]::InvariantCulture) } }
    $app = { param([string] $Name, [int] $Owners, [object[]] $Secrets) @{ id = "obj-$Name"; appId = $Name; displayName = $Name; createdDateTime = (& $ago 400); passwordCredentials = $Secrets; keyCredentials = @(); owners = @(1..$Owners | Where-Object { $Owners } | ForEach-Object { @{ id = "owner$_" } }) } }
    $sp = { param([string] $Name, [string] $Tenant = 't-1', [bool] $Enabled = $true) @{ id = "p-sp-$Name"; appId = $Name; displayName = $Name; accountEnabled = $Enabled; appOwnerOrganizationId = $Tenant; createdDateTime = (& $ago 400) } }

    @{
        Subscription = $sub
        TenantId     = 't-1'
        Names        = @{ $sub = 'sub-prod' }
        Read         = @{
            Errors = @{}
            Rows   = @{
                userIdentities   = @('uai-used', 'uai-loose', 'uai-fed', 'uai-unread' | ForEach-Object { @{ id = (& $uai $_); name = $_; resourceGroup = 'rg-id'; subscriptionId = $sub; location = 'westeurope'; principalId = "p-$_"; clientId = "c-$_" } })
                attached         = @(@{ id = $vm1; identities = @{ (& $uai 'uai-used').ToUpperInvariant() = @{ principalId = 'p-uai-used' } }; kubelet = '' })
                systemIdentities = @(@{ id = $vm1; principalId = 'p-vm1' })
                roleAssignments  = @(
                    (& $assignment 'p-deleted' $owner "/subscriptions/$sub" 'User')
                    (& $assignment 'p-deleted2' $reader "/subscriptions/$sub/resourceGroups/rg-app")
                    (& $assignment 'p-uai-loose' $reader "/subscriptions/$sub")
                    (& $assignment 'p-sp-app-stale' $owner '/providers/Microsoft.Management/managementGroups/mg-root')
                    (& $assignment 'p-sp-app-disabled' $reader "/subscriptions/$sub")
                    (& $assignment 'p-mi-gone' $reader "/subscriptions/$sub")
                    (& $assignment 'p-gone-elsewhere' $owner "/subscriptions/$other")
                )
                roleDefinitions  = @(@{ id = $owner.ToLowerInvariant(); roleName = 'Owner' }, @{ id = $reader.ToLowerInvariant(); roleName = 'Reader' })
            }
        }
        Federated    = @{ (& $uai 'uai-loose') = 0; (& $uai 'uai-fed') = 1 }
        Directory    = @{ Error = ''; Objects = @{ 'p-uai-loose' = @{}; 'p-sp-app-stale' = @{}; 'p-sp-app-disabled' = @{}; 'p-mi-gone' = @{} } }
        Entra        = @{
            Errors = @{}
            Data   = @{
                managedIdentities = @(
                    @{ id = 'p-vm1'; appId = 'mi-vm1'; displayName = 'vm1'; alternativeNames = @('isExplicit=False', $vm1) }
                    @{ id = 'p-mi-gone'; appId = 'mi-gone'; displayName = 'app-deleted'; alternativeNames = @('isExplicit=False', "/subscriptions/$sub/resourceGroups/rg-app/providers/Microsoft.Web/sites/app-deleted") }
                    @{ id = 'p-uai-loose'; appId = 'c-uai-loose'; displayName = 'uai-loose'; alternativeNames = @('isExplicit=True', (& $uai 'uai-loose')) }
                )
                servicePrincipals = @((& $sp 'app-stale'), (& $sp 'app-active'), (& $sp 'app-disabled' 't-1' $false), (& $sp 'sp-foreign' 't-other'))
                applications      = @(
                    (& $app 'app-stale' 1 @((& $credential 100)))
                    (& $app 'app-active' 1 @((& $credential 100)))
                    (& $app 'app-disabled' 1 @((& $credential 100)))
                    (& $app 'app-expired' 0 @((& $credential -30), (& $credential -10)))
                    (& $app 'app-noowner' 0 @((& $credential 100)))
                )
                signIns           = @(
                    @{ appId = 'app-stale'; lastSignInActivity = @{ lastSignInDateTime = (& $ago 200) } }
                    @{ appId = 'app-active'; lastSignInActivity = @{ lastSignInDateTime = (& $ago 5) } }
                    @{ appId = 'app-disabled'; lastSignInActivity = @{ lastSignInDateTime = (& $ago 10) } }
                )
            }
        }
    }
}
