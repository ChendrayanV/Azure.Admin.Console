<#
    Made-up Resource Graph totals for AzureLimit.Tests.ps1 - what
    Get-AACAzureLimitQuery's queries return (already counted):

      sub-prod       3,900 role assignments (97.5% -> Critical), 120 resource
                     groups, 12 subscription tags, a resource with 46 tags
                     (92% -> Warning), 30 policy assignments
      sub-dev        900 role assignments (OK), 40 resource groups
      sub-out        out of scope (another management group): 4,000 role
                     assignments - must not show when scoped
      mg-platform    420 role assignments (84% -> Warning), 170 policy
                     assignments (85% -> Warning), 30 custom definitions
      mg-other       not above any subscription in scope
      rg-hot         190 policy assignments on one resource group (95% ->
                     Critical); rg-cool 10 (OK - not listed)
      tenant         4,100 custom roles (82% -> Warning), 6 management
                     groups, the deepest at depth 5 (83% -> Warning)
#>
function Get-AACContosoLimit {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $out = '99999999-9999-9999-9999-999999999999'
    $mg = { param([string] $Name) "/providers/microsoft.management/managementgroups/$Name" }
    $chain = { param([string[]] $Names) @($Names | ForEach-Object { @{ name = $_; displayName = $_ } }) }
    @{
        Prod  = $prod
        Dev   = $dev
        Out   = $out
        Subscriptions = @(
            @{ subscriptionId = $prod; name = 'sub-prod'; state = 'Enabled'; chain = (& $chain 'mg-platform', 'mg-root') }
            @{ subscriptionId = $dev; name = 'sub-dev'; state = 'Enabled'; chain = (& $chain 'mg-platform', 'mg-root') }
            @{ subscriptionId = $out; name = 'sub-out'; state = 'Enabled'; chain = (& $chain 'mg-other', 'mg-root') }
        )
        Read  = @{
            Errors = @{}
            Rows   = @{
                rbacBySubscription = @(@{ subscriptionId = $prod; used = 3900 }, @{ subscriptionId = $dev; used = 900 }, @{ subscriptionId = $out; used = 4000 })
                rbacByGroup        = @(@{ scope = (& $mg 'mg-platform'); used = 420 }, @{ scope = (& $mg 'mg-other'); used = 480 })
                customRoles        = @(@{ used = 4100 })
                policyAssignments  = @(@{ scope = (& $mg 'mg-platform'); used = 170 }, @{ scope = "/subscriptions/$prod"; used = 30 }, @{ scope = "/subscriptions/$prod/resourcegroups/rg-hot"; used = 190 }, @{ scope = "/subscriptions/$prod/resourcegroups/rg-cool"; used = 10 })
                policyDefinitions  = @(@{ scope = (& $mg 'mg-platform'); used = 30 })
                policySets         = @(@{ scope = (& $mg 'mg-platform'); used = 4 })
                policyExemptions   = @()
                managementGroups   = @(
                    @{ name = 'mg-root'; displayName = 'Tenant Root Group'; depth = 0 }
                    @{ name = 'mg-platform'; displayName = 'Platform'; depth = 1 }
                    @{ name = 'mg-other'; displayName = 'Other'; depth = 1 }
                    @{ name = 'mg-a'; displayName = 'Level 3'; depth = 3 }
                    @{ name = 'mg-b'; displayName = 'Level 4'; depth = 4 }
                    @{ name = 'mg-c'; displayName = 'Deep team'; depth = 5 }
                )
                resourceGroups     = @(@{ subscriptionId = $prod; used = 120 }, @{ subscriptionId = $dev; used = 40 })
                subscriptionTags   = @(@{ subscriptionId = $prod; used = 12 }, @{ subscriptionId = $dev; used = 0 })
                groupTags          = @(@{ subscriptionId = $prod; used = 8; name = 'rg-app' })
                resourceTags       = @(@{ subscriptionId = $prod; used = 46; name = 'vm-tagged'; type = 'microsoft.compute/virtualmachines' })
            }
        }
    }
}
