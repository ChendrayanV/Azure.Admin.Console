<#
    A made-up Contoso tenant's Azure Policy for the Invoke-AACPolicyAssessment
    tests, as Resource Graph returns it (Get-AACPolicyAssessmentQuery):

      contoso-root (Tenant Root Group)
        mg-platform        sub-connectivity   100% compliant
        mg-landingzones
          mg-corp          sub-app1           70% (under 80: a finding)
                           sub-app2           95%

      a-mcsb        root             Microsoft cloud security benchmark (a built-in
                                     initiative: storage HTTPS, and a deprecated Key Vault
                                     policy); excludes a subscription that doesn't exist
      a-locations   mg-landingzones  Allowed locations, assigned directly, Deny, no message
      a-platform    mg-platform      Allowed locations, with a message
      a-tags        mg-corp          Contoso Tagging (a custom initiative: one unused
                                     group), DoNotEnforce, 50% compliant
      a-diag        sub-app1         Deploy diagnostic settings (DeployIfNotExists, needs
                                     Log Analytics Contributor) with no identity, 0%
      a-diag-mg     mg-landingzones  the same, with an identity that holds the role - and
                                     assigned twice on sub-app1's scope path with a-diag

      Exemptions (on 2026-10-05): expired, expiring in 15 days, no expiry (a waiver),
      and one for an assignment that is gone.
      Unassigned: Contoso Security (custom initiative: no category, a group named
      differently for the same control) and Old test policy (no category).

    Returns @{ Rows (query -> rows); Definitions (id -> row); Now; ids }.
#>
function Get-AACContosoPolicyAssessment {
    $conn = '11111111-1111-1111-1111-111111111111'
    $app1 = '22222222-2222-2222-2222-222222222222'
    $app2 = '33333333-3333-3333-3333-333333333333'
    $mg = { param([string] $Name) "/providers/Microsoft.Management/managementGroups/$Name" }
    $chainOf = @{ 'contoso-root' = @(); 'mg-platform' = @('contoso-root'); 'mg-landingzones' = @('contoso-root'); 'mg-corp' = @('mg-landingzones', 'contoso-root') }
    $groupNames = @{ 'contoso-root' = 'Tenant Root Group'; 'mg-platform' = 'Platform'; 'mg-landingzones' = 'Landing zones'; 'mg-corp' = 'Corp' }
    $chain = { param([string[]] $Names) @($Names | ForEach-Object { @{ name = $_; displayName = $groupNames[$_] } }) }
    $assignmentId = { param([string] $Scope, [string] $Name) "$Scope/providers/Microsoft.Authorization/policyAssignments/$Name" }

    # --- Definitions ---------------------------------------------------------------------------------------------
    $builtIn = { param([string] $Kind, [string] $Name) "/providers/Microsoft.Authorization/$Kind/$Name" }
    $custom = { param([string] $Kind, [string] $Name) "$(& $mg 'contoso-root')/providers/Microsoft.Authorization/$Kind/$Name" }
    $logAnalyticsContributor = '92aaf0da-9dab-42b6-94a3-d43ce8d16293'
    $effectParameter = { param([string] $Default, [string[]] $Allowed) @{ effect = @{ type = 'String'; defaultValue = $Default; allowedValues = $Allowed } } }
    $def = {
        param([string] $Id, [string] $Name, [string] $Type, [hashtable] $More = @{})
        $row = @{ id = $Id; name = ($Id -replace '^.*/', ''); type = $(if ($Id -match 'policySetDefinitions') { 'microsoft.authorization/policysetdefinitions' } else { 'microsoft.authorization/policydefinitions' }); displayName = $Name; description = "$Name."; policyType = $Type; mode = 'Indexed'; version = '1.0.0'; metadata = @{}; parameters = @{}; rule = $null; members = $null; groups = $null }
        foreach ($k in $More.Keys) { $row[$k] = $More[$k] }
        $row
    }
    $https = & $def (& $builtIn 'policyDefinitions' 'storage-https') 'Secure transfer to storage accounts should be enabled' 'BuiltIn' @{ metadata = @{ category = 'Storage'; version = '2.0.0' }; parameters = (& $effectParameter 'Audit' 'Audit', 'Deny', 'Disabled'); rule = @{ if = @{ field = 'type'; equals = 'Microsoft.Storage/storageAccounts' }; then = @{ effect = "[parameters('effect')]" } } }
    $softDelete = & $def (& $builtIn 'policyDefinitions' 'kv-soft-delete') '[Deprecated]: Key vaults should have soft delete enabled' 'BuiltIn' @{ metadata = @{ category = 'Key Vault'; deprecated = $true }; rule = @{ then = @{ effect = 'Audit' } } }
    $locations = & $def (& $builtIn 'policyDefinitions' 'allowed-locations') 'Allowed locations' 'BuiltIn' @{ mode = 'Indexed'; metadata = @{ category = 'General' }; rule = @{ then = @{ effect = 'deny' } } }
    $diagnostics = & $def (& $builtIn 'policyDefinitions' 'deploy-diagnostics') 'Deploy diagnostic settings to Log Analytics' 'BuiltIn' @{ metadata = @{ category = 'Monitoring' }; parameters = (& $effectParameter 'DeployIfNotExists' 'DeployIfNotExists', 'Disabled'); rule = @{ then = @{ effect = "[parameters('effect')]"; details = @{ type = 'Microsoft.Insights/diagnosticSettings'; roleDefinitionIds = @("/providers/Microsoft.Authorization/roleDefinitions/$logAnalyticsContributor") } } } }
    $mcsb = & $def (& $builtIn 'policySetDefinitions' 'mcsb') 'Microsoft cloud security benchmark' 'BuiltIn' @{ metadata = @{ category = 'Security Center' }; members = @(@{ policyDefinitionId = $https.id; policyDefinitionReferenceId = 'storageHttps'; groupNames = @('NS-1') }, @{ policyDefinitionId = $softDelete.id; policyDefinitionReferenceId = 'kvSoftDelete'; groupNames = @('DP-8') }); groups = @(@{ name = 'NS-1' }, @{ name = 'DP-8' }) }
    $costCenter = & $def (& $custom 'policyDefinitions' 'require-cost-center') 'Require a cost center tag' 'Custom' @{ metadata = @{ category = 'Tags'; 'hidden-owner' = 'platform-team' }; parameters = (& $effectParameter 'Deny' 'Audit', 'Deny'); rule = @{ then = @{ effect = "[parameters('effect')]" } } }
    $oldTest = & $def (& $custom 'policyDefinitions' 'old-test') 'Old test policy' 'Custom' @{ rule = @{ then = @{ effect = 'Audit' } } }
    $tagging = & $def (& $custom 'policySetDefinitions' 'contoso-tagging') 'Contoso Tagging' 'Custom' @{ metadata = @{ category = 'Tags' }; members = @(@{ policyDefinitionId = $costCenter.id; policyDefinitionReferenceId = 'costCenter'; groupNames = @('Tagging-1') }); groups = @(@{ name = 'Tagging-1'; additionalMetadataId = '/providers/Microsoft.PolicyInsights/policyMetadata/ACF1001' }, @{ name = 'Tagging-2' }) }
    $security = & $def (& $custom 'policySetDefinitions' 'contoso-security') 'Contoso Security' 'Custom' @{ members = @(@{ policyDefinitionId = $costCenter.id; policyDefinitionReferenceId = 'costCenter'; groupNames = @('Sec-1') }); groups = @(@{ name = 'Sec-1'; additionalMetadataId = '/providers/Microsoft.PolicyInsights/policyMetadata/ACF1001' }) }
    $definitions = @{}
    foreach ($row in $https, $softDelete, $locations, $diagnostics, $mcsb, $costCenter, $oldTest, $tagging, $security) { $definitions[$row.id.ToLowerInvariant()] = $row }

    # --- Assignments ------------------------------------------------------------------------------------------------
    $assign = {
        param([string] $Scope, [string] $Name, [string] $Display, $Definition, [hashtable] $More = @{})
        $row = @{ id = (& $assignmentId $Scope $Name); name = $Name; displayName = $Display; description = ''; scope = $Scope; definitionId = $Definition.id; definitionVersion = '1.*.*'; parameters = @{}; enforcement = 'Default'; notScopes = @(); overrides = $null; resourceSelectors = $null; messages = $null; metadata = @{ assignedBy = 'Platform team' }; identity = $null; location = 'westeurope' }
        foreach ($k in $More.Keys) { $row[$k] = $More[$k] }
        $row
    }
    $assignments = @(
        & $assign (& $mg 'contoso-root') 'a-mcsb' 'Security benchmark' $mcsb @{ notScopes = @('/subscriptions/99999999-9999-9999-9999-999999999999'); messages = @(@{ message = 'See the security wiki.' }) }
        & $assign (& $mg 'mg-landingzones') 'a-locations' 'Allowed locations' $locations @{ parameters = @{ listOfAllowedLocations = @{ value = @('westeurope', 'northeurope') } } }
        & $assign (& $mg 'mg-platform') 'a-platform' 'Allowed locations (platform)' $locations @{ messages = @(@{ message = 'Only West and North Europe.' }) }
        & $assign (& $mg 'mg-corp') 'a-tags' 'Tagging' $tagging @{ enforcement = 'DoNotEnforce'; messages = @(@{ message = 'Tag with a cost center.' }); metadata = @{ assignedBy = 'Platform team'; 'hidden-ticket' = 'CHG-1001' } }
        & $assign "/subscriptions/$app1" 'a-diag' 'Diagnostics (app1)' $diagnostics
        & $assign (& $mg 'mg-landingzones') 'a-diag-mg' 'Diagnostics' $diagnostics @{ identity = @{ type = 'SystemAssigned'; principalId = 'aaaaaaaa-0000-0000-0000-00000000d1a6' } }
    )
    $idOf = @{}
    foreach ($row in $assignments) { $idOf[$row.name] = $row.id.ToLowerInvariant() }

    # --- Exemptions -------------------------------------------------------------------------------------------------
    $exempt = {
        param([string] $Scope, [string] $Sub, [string] $Name, [string] $Assignment, [string] $Expires, [string] $Category = 'Mitigated')
        @{ id = "$Scope/providers/Microsoft.Authorization/policyExemptions/$Name"; name = $Name; displayName = $Name; description = ''; assignmentId = $Assignment; referenceIds = @(); category = $Category; expiresOn = $Expires; metadata = @{}; resourceSelectors = $null; subscriptionId = $Sub; resourceGroup = '' }
    }
    $exemptions = @(
        & $exempt "/subscriptions/$app1" $app1 'ex-expired' (& $assignmentId (& $mg 'contoso-root') 'a-mcsb') '2026-09-01T00:00:00Z'
        & $exempt "/subscriptions/$app2" $app2 'ex-expiring' (& $assignmentId (& $mg 'mg-landingzones') 'a-locations') '2026-10-20T00:00:00Z'
        & $exempt "/subscriptions/$app1/resourceGroups/rg-legacy" $app1 'ex-forever' (& $assignmentId (& $mg 'mg-corp') 'a-tags') '' 'Waiver'
        & $exempt "/subscriptions/$app2" $app2 'ex-orphan' (& $assignmentId (& $mg 'mg-corp') 'a-gone') '2027-06-01T00:00:00Z'
    )

    # --- Compliance (each resource at its worst state) ------------------------------------------------------------------
    $counts = { param([long] $N, [long] $C, [long] $E = 0, [long] $X = 0) @{ nonCompliant = $N; compliant = $C; exempt = $E; conflict = $X } }
    $bySub = { param([string] $Sub, [hashtable] $Counts) $Counts.subscriptionId = $Sub; $Counts.id = $Sub; $Counts }
    $byAssignment = { param([string] $Name, [string] $Sub, [hashtable] $Counts) $Counts.assignmentId = $idOf[$Name]; $Counts.subscriptionId = $Sub; $Counts.id = "$($idOf[$Name])|$Sub"; $Counts }
    $byPolicy = { param([string] $Name, $Definition, [string] $Reference, [string] $Effect, [string] $Sub, [hashtable] $Counts) $Counts.assignmentId = $idOf[$Name]; $Counts.definitionId = $Definition.id.ToLowerInvariant(); $Counts.referenceId = $Reference; $Counts.effect = $Effect; $Counts.subscriptionId = $Sub; $Counts.id = "$($idOf[$Name])|$Reference|$($Definition.id.ToLowerInvariant())|$Sub"; $Counts }

    @{
        Conn          = $conn; App1 = $app1; App2 = $app2
        Now           = [datetime]'2026-10-05T12:00:00Z'
        AssignmentIds = $idOf
        Definitions   = $definitions
        Rows          = @{
            subscriptions            = @(
                @{ id = "/subscriptions/$conn"; subscriptionId = $conn; name = 'sub-connectivity'; state = 'Enabled'; chain = (& $chain @('mg-platform', 'contoso-root')); tags = @{} }
                @{ id = "/subscriptions/$app1"; subscriptionId = $app1; name = 'sub-app1'; state = 'Enabled'; chain = (& $chain @('mg-corp', 'mg-landingzones', 'contoso-root')); tags = @{ 'hidden-costcode' = 'CC-42' } }
                @{ id = "/subscriptions/$app2"; subscriptionId = $app2; name = 'sub-app2'; state = 'Enabled'; chain = (& $chain @('mg-corp', 'mg-landingzones', 'contoso-root')); tags = @{} }
            )
            managementGroups         = @(foreach ($name in 'contoso-root', 'mg-platform', 'mg-landingzones', 'mg-corp') { @{ id = (& $mg $name); name = $name; displayName = $groupNames[$name]; parent = $(if ($chainOf[$name].Count) { $chainOf[$name][0] } else { '' }); chain = (& $chain $chainOf[$name]) } })
            assignments              = $assignments
            exemptions               = $exemptions
            customDefinitions        = @($costCenter, $oldTest)
            customInitiatives        = @($tagging, $security)
            roleDefinitions          = @(@{ id = "/providers/Microsoft.Authorization/roleDefinitions/$logAnalyticsContributor"; name = $logAnalyticsContributor; roleName = 'Log Analytics Contributor' })
            roles0                   = @(@{ id = "$(& $mg 'mg-landingzones')/providers/Microsoft.Authorization/roleAssignments/ra-1"; principalId = 'aaaaaaaa-0000-0000-0000-00000000d1a6'; roleDefinitionId = "/providers/microsoft.authorization/roledefinitions/$logAnalyticsContributor"; scope = (& $mg 'mg-landingzones') })
            complianceBySubscription = @((& $bySub $conn (& $counts 0 40)), (& $bySub $app1 (& $counts 30 60 10)), (& $bySub $app2 (& $counts 5 95)))
            complianceByAssignment   = @(
                & $byAssignment 'a-mcsb' $conn (& $counts 0 40); & $byAssignment 'a-mcsb' $app1 (& $counts 10 80 10); & $byAssignment 'a-mcsb' $app2 (& $counts 2 98)
                & $byAssignment 'a-locations' $app1 (& $counts 5 95); & $byAssignment 'a-locations' $app2 (& $counts 3 97)
                & $byAssignment 'a-platform' $conn (& $counts 0 40)
                & $byAssignment 'a-tags' $app1 (& $counts 20 20)
                & $byAssignment 'a-diag' $app1 (& $counts 10 0)
                & $byAssignment 'a-diag-mg' $app1 (& $counts 10 0); & $byAssignment 'a-diag-mg' $app2 (& $counts 0 50)
            )
            complianceByPolicy       = @(
                & $byPolicy 'a-mcsb' $https 'storageHttps' 'audit' $app1 (& $counts 10 40 10); & $byPolicy 'a-mcsb' $https 'storageHttps' 'audit' $app2 (& $counts 2 48)
                & $byPolicy 'a-mcsb' $softDelete 'kvSoftDelete' 'audit' $conn (& $counts 0 40); & $byPolicy 'a-mcsb' $softDelete 'kvSoftDelete' 'audit' $app1 (& $counts 0 40); & $byPolicy 'a-mcsb' $softDelete 'kvSoftDelete' 'audit' $app2 (& $counts 0 50)
                & $byPolicy 'a-locations' $locations '' 'deny' $app1 (& $counts 5 95); & $byPolicy 'a-locations' $locations '' 'deny' $app2 (& $counts 3 97)
                & $byPolicy 'a-platform' $locations '' 'deny' $conn (& $counts 0 40)
                & $byPolicy 'a-tags' $costCenter 'costCenter' 'deny' $app1 (& $counts 20 20)
                & $byPolicy 'a-diag' $diagnostics '' 'deployifnotexists' $app1 (& $counts 10 0)
                & $byPolicy 'a-diag-mg' $diagnostics '' 'deployifnotexists' $app1 (& $counts 10 0); & $byPolicy 'a-diag-mg' $diagnostics '' 'deployifnotexists' $app2 (& $counts 0 50)
            )
        }
    }
}
