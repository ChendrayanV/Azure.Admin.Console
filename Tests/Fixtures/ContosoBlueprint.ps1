<#
    Made-up Contoso data for New-AACServiceBlueprint: the policies in force as
    Get-AACAssignedPolicy -ExpandPolicySet returns them, Azure Policy's answer
    to checkPolicyRestrictions for a planned body, and Azure's list of services
    (GET /providers/Microsoft.Support/services): upper-case types, classic ones,
    a service with none, and a type two services share.
#>

function Get-AACContosoBlueprint {
    $subscription = '11111111-1111-1111-1111-111111111111'
    $scope = "/subscriptions/$subscription"
    $group = '/providers/Microsoft.Management/managementGroups/mg-contoso'
    $row = {
        param([string] $Name, [string] $Policy, [string] $Effect, [string] $Types, [string] $Parameter = '', [string] $Value = '', [string] $At = $group, [bool] $Inherited = $true, [string] $Enforcement = 'Default', [string] $NotScopes = '')
        [pscustomobject]@{
            AssignmentId = "$At/providers/Microsoft.Authorization/policyAssignments/$Name"; AssignmentName = $Name; AssignmentDisplayName = $Name; AssignmentScope = $At; ScopeName = ($At -split '/')[-1]; Inherited = $Inherited
            EnforcementMode = $Enforcement; NotScopes = $NotScopes; ReferenceId = ''; PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/$Policy"; PolicyDisplayName = $Policy; PolicySetDisplayName = ''
            Effect = $Effect; ResourceType = $Types; ParameterName = $Parameter; EffectiveValue = $Value; Category = 'General'
        }
    }
    $service = {
        param([string] $Name, [string[]] $Types = @())
        @{ name = "guid-$($Name -replace '\W', '')"; type = 'Microsoft.Support/services'; id = "/providers/Microsoft.Support/services/guid-$($Name -replace '\W', '')"; properties = @{ displayName = $Name; resourceTypes = $Types } }
    }
    @{
        Services     = @(
            & $service 'Billing'
            & $service 'Virtual Network' 'MICROSOFT.NETWORK/VIRTUALNETWORKS', 'MICROSOFT.CLASSICNETWORK/VIRTUALNETWORKS'
            & $service 'Virtual Machine running Linux' 'MICROSOFT.COMPUTE/VIRTUALMACHINES', 'MICROSOFT.CLASSICCOMPUTE/VIRTUALMACHINES'
            & $service 'Virtual Machine running Windows' 'MICROSOFT.COMPUTE/VIRTUALMACHINES', 'MICROSOFT.CLASSICCOMPUTE/VIRTUALMACHINES'
            & $service 'Blob Storage' 'MICROSOFT.STORAGE/STORAGEACCOUNTS'
            & $service 'Function App' 'MICROSOFT.WEB/SITES'
            & $service 'Web App (Linux)' 'MICROSOFT.WEB/SITES'
            & $service 'Contoso Widgets' 'MICROSOFT.CONTOSO/WIDGETS'
        )
        Subscription = $subscription
        Scope        = $scope
        Group        = $group
        Rows         = @(
            & $row 'locations' 'Allowed locations' 'deny' 'All' 'listOfAllowedLocations' 'westeurope, northeurope'
            & $row 'types' 'Not allowed resource types' 'deny' 'All' 'listOfResourceTypesNotAllowed' 'Microsoft.EventGrid/topics'
            & $row 'storage-public' 'Storage accounts should disable public network access' 'deny' 'Microsoft.Storage/storageAccounts'
            & $row 'hub-audit' 'Event Hub namespaces should use private link' 'audit' 'Microsoft.EventHub/namespaces' -Enforcement 'DoNotEnforce'
            & $row 'old-rule' 'Retired storage rule' 'disabled' 'Microsoft.Storage/storageAccounts'
            & $row 'excluded' 'Excluded here' 'deny' 'All' -NotScopes $scope
            # At a resource group: below the subscription, so it doesn't reach a new one.
            & $row 'below' 'Below the scope' 'deny' 'All' -At "$scope/resourceGroups/rg-other" -Inherited $false
        )
    }
}
