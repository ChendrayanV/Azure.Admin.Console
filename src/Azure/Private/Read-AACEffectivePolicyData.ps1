function Read-AACEffectivePolicyData {
    <#
    .SYNOPSIS
        Reads what ConvertTo-AACEffectivePolicy needs to work out the policy
        that applies to some resources: the resources, every assignment and
        definition (Read-AACAssignedPolicyData), every exemption, the
        resources' compliance states and - for the non-compliant ones - why.
    .DESCRIPTION
        The resources: -ResourceId (resources, resource groups or
        subscriptions), or those in -SubscriptionId narrowed by
        -ResourceGroupName and -ResourceType - at most -MaxResource of them
        (Truncated says when more matched). With -SkipResource none are
        read: a planned resource brings its own.

        Assignments and exemptions are read tenant-wide, so those inherited
        from management groups are there. States come from Resource Graph
        (policyresources, policystates). Why a resource is non-compliant -
        the field, the expected and the actual value - comes from Policy
        Insights' queryResults with $expand=PolicyEvaluationDetails, one
        call per non-compliant resource, for at most -ReasonLimit resources
        (ReasonsSkipped counts the rest); -SkipReason reads none.

        Progress goes to the Invoke-AACProgress display (effective-read,
        effective-state, effective-reason, and Read-AACAssignedPolicyData's).
        Returns @{ Policy (Read-AACAssignedPolicyData's result); Resources
        (@{ Id; Name; Type; Location; Kind; Tags; ResourceGroup;
        SubscriptionId }); Missing (IDs not found); Truncated; Exemptions;
        States; Reasons ('resourceId|assignmentId|referenceId', lower case
        -> @{ Reason; Expressions }); ReasonsSkipped; Errors }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $ResourceId = @(),

        [string] $SubscriptionId,

        [string[]] $ResourceGroupName = @(),

        [string[]] $ResourceType = @(),

        [switch] $SkipResource,

        [switch] $SkipState,

        [switch] $SkipReason,

        [ValidateRange(1, 5000)]
        [int] $MaxResource = 500,

        [ValidateRange(0, 200)]
        [int] $ReasonLimit = 25,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $inList = { param([string[]] $Value) (@($Value | ForEach-Object { & $quote $_.ToLowerInvariant() })) -join ', ' }
    $columns = 'id, name, type, location, kind, tags, resourceGroup, subscriptionId'
    $errors = [System.Collections.Generic.List[string]]::new()
    $policy = Read-AACAssignedPolicyData

    # --- The resources, and every exemption ------------------------------------------------------------------------
    $queries = [ordered]@{
        exemptions = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyexemptions' | project id, name, displayName = tostring(properties.displayName), description = tostring(properties.description), assignmentId = tolower(tostring(properties.policyAssignmentId)), referenceIds = properties.policyDefinitionReferenceIds, category = tostring(properties.exemptionCategory), expiresOn = tostring(properties.expiresOn), resourceSelectors = properties.resourceSelectors" }
    }
    $ids = @($ResourceId | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('/') } | Select-Object -Unique)
    if (-not $SkipResource) {
        if ($ids.Count) {
            for ($i = 0; $i -lt $ids.Count; $i += 200) {
                $chunk = & $inList $ids[$i..([Math]::Min($i + 199, $ids.Count - 1))]
                $queries["resources-$i"] = @{ Tenant = $true; Query = "resources | where tolower(id) in ($chunk) | project $columns" }
                $queries["containers-$i"] = @{ Tenant = $true; Query = "resourcecontainers | where tolower(id) in ($chunk) | project $columns" }
            }
        }
        elseif ($SubscriptionId) {
            $filter = @(
                "subscriptionId =~ $(& $quote $SubscriptionId)"
                if ($ResourceGroupName.Count) { "resourceGroup in~ ($(& $inList $ResourceGroupName))" }
                if ($ResourceType.Count) { "type in~ ($(& $inList $ResourceType))" }
            ) -join ' and '
            $queries['resources'] = @{ Tenant = $true; Query = "resources | where $filter | project $columns | order by id asc | take $($MaxResource + 1)" }
        }
    }
    Update-AACProgress -Id 'effective-read' -Indeterminate -Description 'Reading the resources and the policy exemptions'
    $batch = Invoke-AACGraphBatch -Query $queries -AllowFailure 'exemptions'
    if ($batch.Errors.Contains('exemptions')) { $errors.Add("The policy exemptions couldn't be read: $($batch.Errors['exemptions'])") }
    $resources = [System.Collections.Generic.List[hashtable]]::new()
    $seen = @{}
    foreach ($name in @($batch.Rows.Keys | Where-Object { $_ -ne 'exemptions' } | Sort-Object)) {
        foreach ($row in @($batch.Rows[$name])) {
            if ($row -isnot [System.Collections.IDictionary]) { continue }
            $key = ([string]$row['id']).ToLowerInvariant()
            if ($seen.Contains($key)) { continue }
            $seen[$key] = $true
            $resources.Add(@{
                    Id = [string]$row['id']; Name = [string]$row['name']; Type = [string]$row['type']; Location = [string]$row['location']; Kind = [string]$row['kind']
                    Tags = $(if ($row['tags'] -is [System.Collections.IDictionary]) { $row['tags'] } else { @{} }); ResourceGroup = [string]$row['resourceGroup']; SubscriptionId = [string]$row['subscriptionId']
                })
        }
    }
    $truncated = $false
    if (-not $ids.Count -and $resources.Count -gt $MaxResource) { $truncated = $true; $resources.RemoveRange($MaxResource, $resources.Count - $MaxResource) }
    $missing = @($ids | Where-Object { -not $seen.Contains($_.ToLowerInvariant()) })
    $exemptions = @($batch.Rows['exemptions'])
    Update-AACProgress -Id 'effective-read' -Complete -Description ('Read {0:N0} resource(s) and {1:N0} policy exemption(s)' -f $resources.Count, $exemptions.Count)

    # --- Their compliance states -----------------------------------------------------------------------------------
    $states = @()
    if (-not $SkipState -and $resources.Count) {
        Update-AACProgress -Id 'effective-state' -Indeterminate -Description 'Reading the compliance states'
        $keys = @($resources | ForEach-Object { $_.Id })
        $stateQueries = [ordered]@{}
        for ($i = 0; $i -lt $keys.Count; $i += 200) {
            $stateQueries["states-$i"] = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | extend resourceId = tolower(tostring(properties.resourceId)) | where resourceId in ($(& $inList $keys[$i..([Math]::Min($i + 199, $keys.Count - 1))])) | project id, resourceId, assignmentId = tolower(tostring(properties.policyAssignmentId)), referenceId = tolower(tostring(properties.policyDefinitionReferenceId)), definitionId = tolower(tostring(properties.policyDefinitionId)), state = tostring(properties.complianceState), effect = tostring(properties.policyDefinitionAction), evaluated = tostring(properties.timestamp)" }
        }
        $read = Invoke-AACGraphBatch -Query $stateQueries -AllowFailure @($stateQueries.Keys)
        $states = @(foreach ($rows in $read.Rows.Values) { @($rows) })
        if ($read.Errors.Count) { $errors.Add("Some compliance states couldn't be read: $(@($read.Errors.Values)[0])") }
        Update-AACProgress -Id 'effective-state' -Complete -Description ('Read {0:N0} compliance state(s)' -f $states.Count)
    }

    # --- Why the non-compliant ones are --------------------------------------------------------------------------------
    $reasons = @{}
    $skipped = 0
    $failing = @($states | Where-Object { [string]$_['state'] -eq 'NonCompliant' } | ForEach-Object { [string]$_['resourceId'] } | Select-Object -Unique)
    if (-not $SkipReason -and $failing.Count -and $ReasonLimit) {
        $asked = @($failing | Select-Object -First $ReasonLimit)
        $skipped = $failing.Count - $asked.Count
        Update-AACProgress -Id 'effective-reason' -Total $asked.Count -Description "Reading why $($asked.Count) resource(s) are non-compliant"
        $filter = [System.Uri]::EscapeDataString("ComplianceState eq 'NonCompliant'")
        $uris = @{}
        foreach ($id in $asked) { $uris[$id] = "$id/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=2019-10-01&`$expand=PolicyEvaluationDetails&`$filter=$filter" }
        # queryResults is a POST - with an empty body - like each of its pages.
        $post = { param([string] $Target, [string] $Token) Send-AACHttpRequest -Method Post -Uri $Target -Token $Token -Body '{}' -ContentType 'application/json' }
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -Send $post -ThrottleLimit $ThrottleLimit -OnProgress { Update-AACProgress -Id 'effective-reason' -Increment 1 }
        $text = { param($Value) if ($null -eq $Value) { 'null' } elseif ($Value -is [string]) { "'$Value'" } else { ConvertTo-Json -InputObject $Value -Compress -Depth 10 } }
        $failedCalls = 0
        foreach ($id in $asked) {
            $answer = $answers[$uris[$id]]
            if (-not $answer -or $answer['Error']) { $failedCalls++; continue }
            foreach ($item in @($answer['Items'] | Where-Object { $_ -is [System.Collections.IDictionary] })) {
                $details = $item['policyEvaluationDetails']
                if ($details -isnot [System.Collections.IDictionary]) { continue }
                $expressions = @($details['evaluatedExpressions'] | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_['result'] -eq 'True' -and [string]$_['path'] -ne 'type' } | ForEach-Object {
                        "$($_['path']) $($_['operator']) $(& $text $_['targetValue']) (is $(& $text $_['expressionValue']))"
                    })
                $key = '{0}|{1}|{2}' -f $id.ToLowerInvariant(), ([string]$item['policyAssignmentId']).ToLowerInvariant(), ([string]$item['policyDefinitionReferenceId']).ToLowerInvariant()
                $reasons[$key] = @{ Reason = [string]$details['reason']; Expressions = $expressions }
            }
        }
        if ($failedCalls) { $errors.Add("Why $failedCalls resource(s) are non-compliant couldn't be read (Policy Insights: needs Reader on the resource).") }
        Update-AACProgress -Id 'effective-reason' -Complete -Description "Read why $($asked.Count - $failedCalls) resource(s) are non-compliant"
    }

    @{
        Policy         = $policy
        Resources      = $resources.ToArray()
        Missing        = $missing
        Truncated      = $truncated
        Exemptions     = $exemptions
        States         = $states
        Reasons        = $reasons
        ReasonsSkipped = $skipped
        Errors         = $errors.ToArray()
    }
}
