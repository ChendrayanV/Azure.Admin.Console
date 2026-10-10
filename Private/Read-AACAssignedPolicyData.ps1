function Read-AACAssignedPolicyData {
    <#
    .SYNOPSIS
        Reads what ConvertTo-AACAssignedPolicy needs from Azure Resource
        Graph: every policy assignment, where every subscription and
        management group sits, and the definitions and initiatives assigned
        (their members included). Shared by Get-AACAssignedPolicy and
        Invoke-AACAssessment's policy inventory.
    .DESCRIPTION
        Tenant-wide, so a subscription's assignments inherited from its
        management groups are there to filter. Definitions are read by ID,
        100 to a query, then the initiatives' members; a definition Resource
        Graph doesn't return is read from Azure Resource Manager.

        Progress goes to the Invoke-AACProgress display (assigned-read,
        assigned-definitions). Returns @{ Assignments; Definitions;
        SubscriptionNames; GroupNames; SubscriptionChain; GroupChain } -
        ConvertTo-AACAssignedPolicy's -Assignment, -Definition,
        -SubscriptionName, -ManagementGroupName, -SubscriptionChain and
        -GroupChain.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # --- The assignments and where every scope sits (tenant-wide) --------------------------------
    $queries = [ordered]@{
        assignments      = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id, name, displayName = tostring(properties.displayName), scope = tostring(properties.scope), definitionId = tostring(properties.policyDefinitionId), parameters = properties.parameters, enforcement = tostring(properties.enforcementMode), notScopes = properties.notScopes, overrides = properties.overrides, description = tostring(properties.description)" }
        subscriptions    = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name, chain = properties.managementGroupAncestorsChain" }
        managementGroups = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project id, name, displayName = tostring(properties.displayName), chain = properties.details.managementGroupAncestorsChain" }
    }
    $labels = @{ assignments = 'policy assignments'; subscriptions = 'subscriptions'; managementGroups = 'management groups' }
    Update-AACProgress -Id 'assigned-read' -Total $queries.Count -Description 'Reading the policy assignments from Azure Resource Graph'
    $batch = Invoke-AACGraphBatch -Query $queries -AllowFailure 'managementGroups' -OnProgress {
        param($Name, $Done, $Total)
        Update-AACProgress -Id 'assigned-read' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total queries)"
    }
    # Resource Graph lists a scope's management groups nearest first.
    $rootFirst = {
        param($Chain)
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($item in @($Chain)) { if ($item -is [System.Collections.IDictionary]) { $names.Insert(0, ([string]$item['name']).ToLowerInvariant()) } }
        , $names.ToArray()
    }
    $subscriptionNames = @{}
    $subscriptionChain = @{}
    foreach ($row in @($batch.Rows['subscriptions'])) {
        $id = ([string]$row['subscriptionId']).ToLowerInvariant()
        $subscriptionNames[$id] = [string]$row['name']
        $subscriptionChain[$id] = & $rootFirst $row['chain']
    }
    $groupNames = @{}
    $groupChain = @{}
    foreach ($row in @($batch.Rows['managementGroups'])) {
        $name = ([string]$row['name']).ToLowerInvariant()
        $groupNames[$name] = $(if ($row['displayName']) { [string]$row['displayName'] } else { [string]$row['name'] })
        $groupChain[$name] = [string[]](& $rootFirst $row['chain']) + $name
    }
    $assignments = @($batch.Rows['assignments'])
    Update-AACProgress -Id 'assigned-read' -Complete -Description ('Read {0:N0} policy assignment(s) in {1:N0} subscription(s) and {2:N0} management group(s)' -f $assignments.Count, $subscriptionNames.Count, $groupNames.Count)

    # --- The definitions they assign, and the initiatives' members --------------------------------
    $definitions = @{}
    $add = {
        param($Row, [string] $Kind)
        $definitions[([string]$Row['id']).ToLowerInvariant()] = @{
            Id = [string]$Row['id']; Name = [string]$Row['name']; Kind = $Kind
            DisplayName = $(if ($Row['displayName']) { [string]$Row['displayName'] } else { [string]$Row['name'] })
            PolicyType = [string]$Row['policyType']; Category = [string]$Row['category']; Description = [string]$Row['description']
            Parameters = $Row['parameters']; Rule = $Row['rule']; Members = @($Row['members'])
        }
    }
    $kindOf = { param([string] $Id) if ($Id -match '(?i)/policySetDefinitions/') { 'PolicySet' } else { 'Policy' } }
    $wanted = @($assignments | ForEach-Object { ([string]$_['definitionId']).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    Update-AACProgress -Id 'assigned-definitions' -Indeterminate -Description 'Reading the policy definitions and initiatives'
    $round = 0
    while ($wanted.Count -and $round -lt 2) {
        $round++
        $chunks = [ordered]@{}
        for ($i = 0; $i -lt $wanted.Count; $i += 100) {
            $ids = @($wanted[$i..([Math]::Min($i + 99, $wanted.Count - 1))] | ForEach-Object { "'$_'" }) -join ', '
            $chunks["definitions$round-$i"] = @{ Tenant = $true; Query = "policyresources | where type in~ ('microsoft.authorization/policydefinitions', 'microsoft.authorization/policysetdefinitions') | where tolower(id) in ($ids) | project id, name, type, displayName = tostring(properties.displayName), description = tostring(properties.description), policyType = tostring(properties.policyType), category = tostring(properties.metadata.category), parameters = properties.parameters, rule = properties.policyRule, members = properties.policyDefinitions" }
        }
        $read = Invoke-AACGraphBatch -Query $chunks
        foreach ($rows in $read.Rows.Values) { foreach ($row in @($rows)) { & $add $row (& $kindOf ([string]$row['id'])) } }
        # Then the members of the initiatives just read.
        $wanted = @($definitions.Values | Where-Object { $_.Kind -eq 'PolicySet' } | ForEach-Object { @($_.Members) } | Where-Object { $_ -is [System.Collections.IDictionary] } |
                ForEach-Object { ([string]$_['policyDefinitionId']).ToLowerInvariant() } | Where-Object { $_ -and -not $definitions.ContainsKey($_) } | Select-Object -Unique)
    }
    # Whatever Resource Graph didn't return: from Resource Manager.
    $notFound = @(@($assignments | ForEach-Object { ([string]$_['definitionId']).ToLowerInvariant() }) + @($definitions.Values | Where-Object { $_.Kind -eq 'PolicySet' } | ForEach-Object { @($_.Members) } | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { ([string]$_['policyDefinitionId']).ToLowerInvariant() }) |
            Where-Object { $_ -and -not $definitions.ContainsKey($_) } | Select-Object -Unique)
    if ($notFound.Count) {
        $uris = @{}
        foreach ($id in $notFound) { $uris[$id] = "$($id)?api-version=2023-04-01" }
        $arm = Invoke-AACArmParallel -Uri @($uris.Values)
        foreach ($id in $notFound) {
            $result = $arm[$uris[$id]]
            if (-not $result -or $result.Error -or $result.Body -isnot [System.Collections.IDictionary]) { continue }
            $p = $result.Body['properties']
            if ($p -isnot [System.Collections.IDictionary]) { $p = @{} }
            & $add @{ id = $result.Body['id']; name = $result.Body['name']; displayName = $p['displayName']; description = $p['description']; policyType = $p['policyType']; category = $(if ($p['metadata'] -is [System.Collections.IDictionary]) { $p['metadata']['category'] }); parameters = $p['parameters']; rule = $p['policyRule']; members = $p['policyDefinitions'] } (& $kindOf $id)
        }
    }
    $setCount = @($definitions.Values | Where-Object Kind -EQ 'PolicySet').Count
    Update-AACProgress -Id 'assigned-definitions' -Complete -Description ('Read {0:N0} policy definition(s) and {1:N0} initiative(s)' -f ($definitions.Count - $setCount), $setCount)

    @{
        Assignments       = $assignments
        Definitions       = $definitions
        SubscriptionNames = $subscriptionNames
        GroupNames        = $groupNames
        SubscriptionChain = $subscriptionChain
        GroupChain        = $groupChain
    }
}
