function Read-AACAssignedPolicyRest {
    <#
    .SYNOPSIS
        Reads what ConvertTo-AACAssignedPolicy needs from Azure Resource
        Manager's own REST APIs, with Azure Resource Graph filling in only
        what those couldn't read. For Get-AACAssignedPolicy.
    .DESCRIPTION
        REST first because it is the source itself: Resource Graph is a copy
        that can lag behind it.
          where things sit   POST getEntities (management groups, subscriptions
                             and their parent chains, root first), and GET
                             /subscriptions
          the assignments    a subscription's list without a filter: those at
                             it, inherited from its management groups and on
                             the objects inside it; a management group's with
                             atScope(): those at it and at its ancestors
          the definitions    one GET per definition and initiative assigned,
                             then per policy in those initiatives

        -SubscriptionId and -ManagementGroupId limit the scopes read to those
        that can hold what applies there - the management group's ancestors,
        descendants and the subscriptions under it - so asking about one scope
        takes a few calls, not one per subscription in the tenant.

        Resource Graph (Read-AACAssignedPolicyData) is read only when something
        is missing: a scope or definition that failed for a reason other than
        not existing, or a subscription whose management groups aren't known
        (without them, what it inherits can't be told apart). Its rows only
        add to what REST returned.

        Returns Read-AACAssignedPolicyData's result, plus Source ('REST' or
        'REST and Resource Graph') and Notices.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $SubscriptionId = @(),

        [string[]] $ManagementGroupId = @(),

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12
    )

    $apiVersion = '2023-04-01'
    $notices = [System.Collections.Generic.List[string]]::new()
    $failures = [System.Collections.Generic.List[string]]::new()
    $itemsOf = { param($Answer) @(if ($Answer -and -not $Answer.Error) { $Answer.Items | Where-Object { $_ -is [System.Collections.IDictionary] } }) }

    # --- Where every scope sits ----------------------------------------------------------------------
    Update-AACProgress -Id 'assigned-read' -Indeterminate -Description 'Reading the management groups and subscriptions from Azure Resource Manager'
    $entitiesUri = '/providers/Microsoft.Management/getEntities?api-version=2020-05-01'
    $subscriptionsUri = '/subscriptions?api-version=2022-12-01'
    # getEntities is a POST - with an empty body - like each of its pages.
    $post = { param([string] $Target, [string] $Token) Send-AACHttpRequest -Method Post -Uri $Target -Token $Token -Body '{}' -ContentType 'application/json' }
    $entityAnswer = (Invoke-AACArmParallel -Uri @($entitiesUri) -Send $post)[$entitiesUri]
    $subscriptionAnswer = (Invoke-AACArmParallel -Uri @($subscriptionsUri))[$subscriptionsUri]
    if (-not $entityAnswer -or $entityAnswer.Error) { $failures.Add("the management groups: $(if ($entityAnswer) { $entityAnswer.Error })") }
    if (-not $subscriptionAnswer -or $subscriptionAnswer.Error) { $failures.Add("the subscriptions: $(if ($subscriptionAnswer) { $subscriptionAnswer.Error })") }

    $subscriptionNames = @{}
    $subscriptionChain = @{}
    $groupNames = @{}
    $groupChain = @{}
    $deleted = @{}
    $lowered = { param($Names) [string[]]@(@($Names) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
    foreach ($entity in @(& $itemsOf $entityAnswer)) {
        $name = ([string]$entity['name']).ToLowerInvariant()
        $properties = $entity['properties']
        if ($properties -isnot [System.Collections.IDictionary]) { $properties = @{} }
        $chain = & $lowered $properties['parentNameChain']
        $label = if ($properties['displayName']) { [string]$properties['displayName'] } else { [string]$entity['name'] }
        if ([string]$entity['type'] -match '(?i)managementGroups') {
            $groupNames[$name] = $label
            $groupChain[$name] = [string[]]@($chain) + $name
        }
        elseif ([string]$entity['type'] -match '(?i)subscriptions') {
            $subscriptionNames[$name] = $label
            $subscriptionChain[$name] = $chain
        }
    }
    foreach ($subscription in @(& $itemsOf $subscriptionAnswer)) {
        $id = ([string]$subscription['subscriptionId']).ToLowerInvariant()
        if ($subscription['displayName']) { $subscriptionNames[$id] = [string]$subscription['displayName'] }
        if ([string]$subscription['state'] -eq 'Deleted') { $deleted[$id] = $true }
    }

    # --- Which scopes to read ------------------------------------------------------------------------
    $wantedGroups = @($ManagementGroupId | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $wantedSubscriptions = @($SubscriptionId | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $underWanted = { param([string[]] $Chain) @($Chain | Where-Object { $_ -in $wantedGroups }).Count -gt 0 }
    $readSubscriptions = @(
        if ($wantedSubscriptions.Count -or $wantedGroups.Count) {
            $wantedSubscriptions
            foreach ($id in @($subscriptionChain.Keys)) { if (& $underWanted $subscriptionChain[$id]) { $id } }
        }
        else { @($subscriptionNames.Keys) }
    ) | Where-Object { -not $deleted.Contains($_) } | Select-Object -Unique
    $readGroups = @(
        if ($wantedSubscriptions.Count -or $wantedGroups.Count) {
            # atScope() already brings a group's ancestors; its descendants are asked for one by one.
            $wantedGroups
            foreach ($name in @($groupChain.Keys)) { if (& $underWanted $groupChain[$name]) { $name } }
        }
        else { @($groupNames.Keys) }
    ) | Select-Object -Unique

    # A subscription always sits under the root group: no chain means it isn't known.
    $unplaced = @($readSubscriptions | Where-Object { -not $subscriptionChain.Contains($_) -or -not @($subscriptionChain[$_]).Count })
    if ($unplaced.Count) { $failures.Add("the management groups above $($unplaced.Count) subscription(s)") }

    # --- The assignments -----------------------------------------------------------------------------
    $uris = [ordered]@{}
    foreach ($id in $readSubscriptions) { $uris["/subscriptions/$id/providers/Microsoft.Authorization/policyAssignments?api-version=$apiVersion"] = "subscription $(if ($subscriptionNames.Contains($id)) { $subscriptionNames[$id] } else { $id })" }
    foreach ($name in $readGroups) { $uris["/providers/Microsoft.Management/managementGroups/$name/providers/Microsoft.Authorization/policyAssignments?api-version=$apiVersion&`$filter=atScope()"] = "management group $(if ($groupNames.Contains($name)) { $groupNames[$name] } else { $name })" }
    Update-AACProgress -Id 'assigned-read' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading the policy assignments of $($uris.Count) scope(s)"
    $answers = Invoke-AACArmParallel -Uri @($uris.Keys) -ThrottleLimit $ThrottleLimit -OnProgress { Update-AACProgress -Id 'assigned-read' -Increment 1 }
    $assignmentById = [ordered]@{}
    foreach ($uri in $uris.Keys) {
        $answer = $answers[$uri]
        if (-not $answer -or $answer.Error) { $failures.Add("$($uris[$uri]): $(if ($answer) { $answer.Error })"); continue }
        foreach ($item in @(& $itemsOf $answer)) {
            $key = ([string]$item['id']).ToLowerInvariant()
            if ($assignmentById.Contains($key)) { continue }
            $p = $item['properties']
            if ($p -isnot [System.Collections.IDictionary]) { $p = @{} }
            # The columns Read-AACAssignedPolicyData's query projects.
            $assignmentById[$key] = @{
                id = [string]$item['id']; name = [string]$item['name']; displayName = [string]$p['displayName']; scope = [string]$p['scope']; definitionId = [string]$p['policyDefinitionId']
                parameters = $p['parameters']; enforcement = [string]$p['enforcementMode']; notScopes = $p['notScopes']; overrides = $p['overrides']; description = [string]$p['description']
                resourceSelectors = $p['resourceSelectors']; nonComplianceMessages = $p['nonComplianceMessages']; definitionVersion = [string]$p['definitionVersion']
                identityType = $(if ($item['identity'] -is [System.Collections.IDictionary]) { [string]$item['identity']['type'] } else { '' })
            }
        }
    }
    Update-AACProgress -Id 'assigned-read' -Complete -Description ('Read {0:N0} policy assignment(s) from {1:N0} scope(s)' -f $assignmentById.Count, $uris.Count)

    # --- The definitions they assign, then the initiatives' members -----------------------------------
    $definitions = @{}
    $kindOf = { param([string] $Id) if ($Id -match '(?i)/policySetDefinitions/') { 'PolicySet' } else { 'Policy' } }
    $memberIds = {
        @($definitions.Values | Where-Object { $_.Kind -eq 'PolicySet' } | ForEach-Object { @($_.Members) } | Where-Object { $_ -is [System.Collections.IDictionary] } |
                ForEach-Object { ([string]$_['policyDefinitionId']).ToLowerInvariant() })
    }
    $wanted = @($assignmentById.Values | ForEach-Object { ([string]$_['definitionId']).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    Update-AACProgress -Id 'assigned-definitions' -Indeterminate -Description 'Reading the policy definitions and initiatives'
    # Initiatives don't nest: two rounds reach every policy.
    foreach ($round in 1, 2) {
        if (-not $wanted.Count) { break }
        $definitionUris = @{}
        foreach ($id in $wanted) { $definitionUris[$id] = "$($id)?api-version=$apiVersion" }
        Update-AACProgress -Id 'assigned-definitions' -Total $wanted.Count -Description "Reading $($wanted.Count) policy definition(s) and initiative(s)"
        $read = Invoke-AACArmParallel -Uri @($definitionUris.Values) -ThrottleLimit $ThrottleLimit -OnProgress { Update-AACProgress -Id 'assigned-definitions' -Increment 1 }
        foreach ($id in $wanted) {
            $answer = $read[$definitionUris[$id]]
            if (-not $answer -or $answer.Error -or $answer.Body -isnot [System.Collections.IDictionary]) {
                # A 404 is a definition that is gone: Resource Graph can't bring it back.
                if (-not $answer -or $answer.Status -ne 404) { $failures.Add("definition $($id): $(if ($answer) { $answer.Error })") }
                continue
            }
            $p = $answer.Body['properties']
            if ($p -isnot [System.Collections.IDictionary]) { $p = @{} }
            $metadata = $p['metadata']
            $definitions[$id] = @{
                Id = [string]$answer.Body['id']; Name = [string]$answer.Body['name']; Kind = (& $kindOf $id)
                DisplayName = $(if ($p['displayName']) { [string]$p['displayName'] } else { [string]$answer.Body['name'] })
                PolicyType = [string]$p['policyType']; Category = $(if ($metadata -is [System.Collections.IDictionary]) { [string]$metadata['category'] } else { '' }); Description = [string]$p['description']; Mode = [string]$p['mode']
                Parameters = $p['parameters']; Rule = $p['policyRule']; Members = @($p['policyDefinitions'])
            }
        }
        $wanted = @(& $memberIds | Where-Object { $_ -and -not $definitions.ContainsKey($_) } | Select-Object -Unique)
    }
    $setCount = @($definitions.Values | Where-Object Kind -EQ 'PolicySet').Count
    Update-AACProgress -Id 'assigned-definitions' -Complete -Description ('Read {0:N0} policy definition(s) and {1:N0} initiative(s)' -f ($definitions.Count - $setCount), $setCount)

    # --- Only what REST couldn't read: from Resource Graph --------------------------------------------
    $source = 'REST'
    if ($failures.Count) {
        Write-Verbose -Message "Azure Resource Manager couldn't read: $($failures -join '; ')"
        try {
            $graph = Read-AACAssignedPolicyData
            $source = 'REST and Resource Graph'
            foreach ($row in @($graph.Assignments)) {
                $key = ([string]$row['id']).ToLowerInvariant()
                if (-not $assignmentById.Contains($key)) { $assignmentById[$key] = $row }
            }
            foreach ($key in $graph.Definitions.Keys) { if (-not $definitions.ContainsKey($key)) { $definitions[$key] = $graph.Definitions[$key] } }
            foreach ($key in $graph.SubscriptionNames.Keys) { if (-not $subscriptionNames.ContainsKey($key)) { $subscriptionNames[$key] = $graph.SubscriptionNames[$key] } }
            foreach ($key in $graph.GroupNames.Keys) { if (-not $groupNames.ContainsKey($key)) { $groupNames[$key] = $graph.GroupNames[$key] } }
            foreach ($key in $graph.SubscriptionChain.Keys) { if (-not $subscriptionChain.ContainsKey($key) -or -not @($subscriptionChain[$key]).Count) { $subscriptionChain[$key] = $graph.SubscriptionChain[$key] } }
            foreach ($key in $graph.GroupChain.Keys) { if (-not $groupChain.ContainsKey($key)) { $groupChain[$key] = $graph.GroupChain[$key] } }
            $notices.Add("Azure Resource Manager couldn't read $($failures.Count) item(s), so Azure Resource Graph filled them in - first: $($failures[0])")
        }
        catch {
            if (-not $assignmentById.Count) { throw }
            $notices.Add("$($failures.Count) item(s) couldn't be read from Azure Resource Manager or Azure Resource Graph, so this list may be incomplete - first: $($failures[0])")
        }
    }

    @{
        Assignments       = @($assignmentById.Values)
        Definitions       = $definitions
        SubscriptionNames = $subscriptionNames
        GroupNames        = $groupNames
        SubscriptionChain = $subscriptionChain
        GroupChain        = $groupChain
        Source            = $source
        Notices           = $notices.ToArray()
    }
}
