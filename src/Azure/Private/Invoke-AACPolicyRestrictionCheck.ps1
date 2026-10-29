function Invoke-AACPolicyRestrictionCheck {
    <#
    .SYNOPSIS
        Asks Azure Policy what it would do to a resource before it exists:
        checkPolicyRestrictions with the resource's body - which policies it
        would fail (deny, audit), which fields policy sets or removes, and
        which values a field is allowed. Shared by Deploy-AACStorageAccount,
        Show-AACEffectivePolicy (a planned resource) and
        Test-AACPolicyDeployment.
    .DESCRIPTION
        POST {scope}/providers/Microsoft.PolicyInsights/
        checkPolicyRestrictions (2024-10-01) with includeAuditEffect, so
        audits come back as well as denies. -Scope is the subscription or
        resource group the resource goes in (a private endpoint's parent,
        for one that sits under another resource); -ParentId makes it a
        child (resourceDetails.scope), as a blob service is of its account.
        -PendingField asks for the values policy allows for those fields
        (location, type, name, tags.x...) - the "allowed locations" answer.

        Only effects Azure can judge from the request body come back:
        Deny, Audit, Modify, Append. DeployIfNotExists and AuditIfNotExists
        look at other resources after the deployment, so Azure never returns
        them here - the caller lists those from the assignments.

        Returns @{ Error; Evaluations; Restrictions }:
          Evaluations   one per policy the body fails: Outcome (Blocks,
                        Audits, Changes), Effect, AssignmentId, Assignment
                        (-AssignmentName's display name, else its name),
                        DefinitionId, SetId, ReferenceId, Reason and
                        Expressions ("path operator target (is actual)"),
                        Detail (both as one line)
          Restrictions  one per field restriction: Field, Result (Required,
                        Removed, Deny, Audit), Values, DefaultValue, Effect,
                        AssignmentId, Assignment, DefinitionId, ReferenceId,
                        Reason
        A call that fails returns its reason in Error and nothing else.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ResourceContent,

        [string] $ApiVersion,

        [string] $ParentId,

        [string[]] $PendingField = @(),

        # Assignment ID (lower case) -> display name.
        [System.Collections.IDictionary] $AssignmentName = @{}
    )

    $details = [ordered]@{ resourceContent = $ResourceContent }
    if ($ApiVersion) { $details['apiVersion'] = $ApiVersion }
    if ($ParentId) { $details['scope'] = $ParentId }
    $request = [ordered]@{ resourceDetails = $details; includeAuditEffect = $true }
    if ($PendingField.Count) { $request['pendingFields'] = @($PendingField | ForEach-Object { @{ field = $_ } }) }
    try {
        $result = Invoke-AACArmRequest -Method Post -Uri "$($Scope.TrimEnd('/'))/providers/Microsoft.PolicyInsights/checkPolicyRestrictions?api-version=2024-10-01" -Body (ConvertTo-Json -InputObject $request -Depth 50 -Compress)
    }
    catch {
        return @{ Error = [string]$_.Exception.Message; Evaluations = @(); Restrictions = @() }
    }
    if ($result -isnot [System.Collections.IDictionary]) { $result = @{} }

    $info = {
        param($Policy)
        if ($Policy -isnot [System.Collections.IDictionary]) { $Policy = @{} }
        $id = ([string]$Policy['policyAssignmentId']).ToLowerInvariant()
        @{
            AssignmentId = $id; Assignment = $(if ($AssignmentName.Contains($id)) { [string]$AssignmentName[$id] } else { ($id -split '/')[-1] })
            DefinitionId = [string]$Policy['policyDefinitionId']; SetId = [string]$Policy['policySetDefinitionId']; ReferenceId = [string]$Policy['policyDefinitionReferenceId']
        }
    }
    $text = { param($Value) if ($null -eq $Value) { 'null' } elseif ($Value -is [string]) { "'$Value'" } else { ConvertTo-Json -InputObject $Value -Compress -Depth 10 } }

    $evaluations = [System.Collections.Generic.List[hashtable]]::new()
    $content = $result['contentEvaluationResult']
    foreach ($evaluation in @(if ($content -is [System.Collections.IDictionary]) { $content['policyEvaluations'] })) {
        if ($evaluation -isnot [System.Collections.IDictionary] -or [string]$evaluation['evaluationResult'] -ne 'NonCompliant') { continue }
        $effect = if ($evaluation['effectDetails'] -is [System.Collections.IDictionary]) { [string]$evaluation['effectDetails']['policyEffect'] } else { '' }
        $why = $evaluation['evaluationDetails']
        if ($why -isnot [System.Collections.IDictionary]) { $why = @{} }
        # The expressions that came out true are the ones that made it fail;
        # the type check is true for every resource the policy looks at.
        $expressions = @($why['evaluatedExpressions'] | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_['result'] -eq 'True' -and [string]$_['path'] -ne 'type' } | ForEach-Object {
                "$($_['path']) $($_['operator']) $(& $text $_['targetValue'])$(if ($_.Contains('expressionValue')) { " (is $(& $text $_['expressionValue']))" })"
            })
        $row = & $info $evaluation['policyInfo']
        $row.Effect = $effect
        $row.Outcome = if ($effect -match '^(?i)deny') { 'Blocks' } elseif ($effect -match '(?i)audit') { 'Audits' } else { 'Changes' }
        $row.Reason = [string]$why['reason']
        $row.Expressions = $expressions
        $row.Detail = (@($row.Reason, $(if ($expressions.Count) { $expressions -join '; ' })) | Where-Object { $_ }) -join ' - '
        $evaluations.Add($row)
    }

    $restrictions = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($field in @($result['fieldRestrictions'])) {
        if ($field -isnot [System.Collections.IDictionary]) { continue }
        foreach ($restriction in @($field['restrictions'] | Where-Object { $_ -is [System.Collections.IDictionary] })) {
            $row = & $info $restriction['policy']
            $row.Field = [string]$field['field']
            $row.Result = [string]$restriction['result']
            $row.Values = @($restriction['values'] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
            $row.DefaultValue = $restriction['defaultValue']
            $row.Effect = [string]$restriction['policyEffect']
            $row.Reason = [string]$restriction['reason']
            $restrictions.Add($row)
        }
    }
    @{ Error = ''; Evaluations = $evaluations.ToArray(); Restrictions = $restrictions.ToArray() }
}
