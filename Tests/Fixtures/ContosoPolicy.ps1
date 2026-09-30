<#
    Made-up Azure Policy states for the Contoso tenant, as
    Get-AACPolicyStateQuery's query returns them from Azure Resource Graph
    (hashtables), for PolicyState.Tests.ps1:

      sub-corp-apps (rg-app, rg-data)
        Allowed locations (assigned at mg-landingzones, in the initiative
        'Contoso baseline'): vm-web-01 compliant, stordersdata non-compliant
        Require a CostCenter tag (assigned at the subscription, not
        enforced): vm-web-01 non-compliant, kv-app compliant, stordersdata
        exempt
      sub-connectivity (rg-hub)
        Allowed locations: vnet-hub compliant
        Deploy Key Vault diagnostics (assigned at the tenant root): nothing
#>
function Get-AACContosoPolicy {
    $connectivity = '11111111-1111-1111-1111-111111111111'
    $corp = '22222222-2222-2222-2222-222222222222'
    $id = { param($Sub, $Group, $Type, $Name) "/subscriptions/$Sub/resourcegroups/$Group/providers/$Type/$Name".ToLowerInvariant() }
    $locations = '/providers/microsoft.management/managementgroups/mg-landingzones/providers/microsoft.authorization/policyassignments/allowed-locations'
    $tags = "/subscriptions/$corp/providers/microsoft.authorization/policyassignments/require-costcenter"
    $state = {
        param($Sub, $Group, $Type, $Name, $State, $Assignment, $Policy, $Set = '', $Effect = 'deny')
        @{
            subscriptionId = $Sub; resourceId = (& $id $Sub $Group $Type $Name); resourceType = $Type.ToLowerInvariant(); resourceGroup = $Group; location = 'uksouth'; state = $State
            assignmentId = $Assignment; assignment = ($Assignment -split '/')[-1]; assignmentScope = ($Assignment -replace '/providers/microsoft.authorization/policyassignments/.*$', '')
            definitionName = ($Policy -replace '\W', '').ToLowerInvariant(); definitionId = "/providers/microsoft.authorization/policydefinitions/$(($Policy -replace '\W', '').ToLowerInvariant())"
            policy = $Policy; setName = $(if ($Set) { 'contoso-baseline' } else { '' }); setId = $(if ($Set) { '/providers/microsoft.management/managementgroups/mg-corp/providers/microsoft.authorization/policysetdefinitions/contoso-baseline' } else { '' }); policySet = $Set; referenceId = ''; effect = $Effect; evaluated = '2026-09-28T06:00:00Z'
        }
    }
    @{
        States           = @(
            & $state $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-01' 'Compliant' $locations 'Allowed locations' 'Contoso baseline'
            & $state $corp 'rg-data' 'Microsoft.Storage/storageAccounts' 'stordersdata' 'NonCompliant' $locations 'Allowed locations' 'Contoso baseline'
            & $state $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-01' 'NonCompliant' $tags 'Require a tag on resources' '' 'audit'
            & $state $corp 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-app' 'Compliant' $tags 'Require a tag on resources' '' 'audit'
            & $state $corp 'rg-data' 'Microsoft.Storage/storageAccounts' 'stordersdata' 'Exempt' $tags 'Require a tag on resources' '' 'audit'
            & $state $connectivity 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub' 'Compliant' $locations 'Allowed locations' 'Contoso baseline'
        )
        Assignments      = @(
            @{ assignmentId = $locations; name = 'allowed-locations'; displayName = 'Contoso: allowed locations'; scope = '/providers/Microsoft.Management/managementGroups/mg-landingzones'; enforcement = 'Default' }
            @{ assignmentId = $tags; name = 'require-costcenter'; displayName = 'Contoso: require CostCenter'; scope = "/subscriptions/$corp"; enforcement = 'DoNotEnforce' }
        )
        Subscriptions    = @(@{ subscriptionId = $connectivity; name = 'sub-connectivity' }, @{ subscriptionId = $corp; name = 'sub-corp-apps' })
        ManagementGroups = @(@{ name = 'mg-landingzones'; displayName = 'Landing Zones' })
    }
}
