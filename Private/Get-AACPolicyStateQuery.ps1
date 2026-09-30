function Get-AACPolicyStateQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph query for Azure Policy states - one per
        resource and policy (policyresources) - with the policy's and the
        initiative's display names. Shared by Get-AACPolicyState (every
        state) and Get-AACSecurityPosture (the non-compliant ones).
    .DESCRIPTION
        Each row: subscriptionId, resourceId, resourceType, resourceGroup,
        location, state (Compliant, NonCompliant, Exempt, Unknown, ...),
        assignmentId, assignment (its name), assignmentScope, definitionName,
        definitionId, policy (display name), setName, setId and policySet
        (the initiative, when the policy is in one), referenceId, effect and
        evaluated (when it was last evaluated). It keeps the state's id:
        Resource Graph only pages (returns a $skipToken for) results that
        have an id column, so without it a large tenant's states stop at the
        first page. The display names are joined on the definitions' full
        IDs - a definition's name alone repeats at every scope it's defined.
        -ComplianceState and -ResourceGroupName filter in the query itself.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string[]] $ComplianceState = @(),

        [string[]] $ResourceGroupName = @()
    )

    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $where = @(
        if ($ComplianceState.Count) { "state in~ ($((@($ComplianceState | ForEach-Object { & $quote $_ })) -join ', '))" }
        if ($ResourceGroupName.Count) { "resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" }
    )
    @(
        "policyresources | where type =~ 'microsoft.policyinsights/policystates'"
        "| project id, subscriptionId, resourceId = tolower(tostring(properties.resourceId)), resourceType = tolower(tostring(properties.resourceType)), resourceGroup = tostring(properties.resourceGroup), location = tostring(properties.resourceLocation), state = tostring(properties.complianceState), assignmentId = tolower(tostring(properties.policyAssignmentId)), assignment = tostring(properties.policyAssignmentName), assignmentScope = tostring(properties.policyAssignmentScope), definitionName = tostring(properties.policyDefinitionName), definitionId = tolower(tostring(properties.policyDefinitionId)), setName = tostring(properties.policySetDefinitionName), setId = tolower(tostring(properties.policySetDefinitionId)), referenceId = tostring(properties.policyDefinitionReferenceId), effect = tostring(properties.policyDefinitionAction), evaluated = tostring(properties.timestamp)"
        if ($where.Count) { "| where $($where -join ' and ')" }
        "| join kind=leftouter (policyresources | where type =~ 'microsoft.authorization/policydefinitions' | project definitionId = tolower(id), policy = tostring(properties.displayName)) on definitionId"
        "| join kind=leftouter (policyresources | where type =~ 'microsoft.authorization/policysetdefinitions' | project setId = tolower(id), policySet = tostring(properties.displayName)) on setId"
        '| project-away definitionId1, setId1'
    ) -join ' '
}
