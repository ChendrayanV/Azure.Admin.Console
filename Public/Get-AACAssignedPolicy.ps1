function Get-AACAssignedPolicy {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Every Azure Policy assignment with its parameters - the default,
        assigned and effective value of each - and the resource types the
        policy applies to, with a Spectre.Console view, objects, and CSV and
        interactive HTML reports.
    .DESCRIPTION
        An inventory of what is assigned, not of compliance (for that, see
        Get-AACPolicyState). Reads the assignments, the policy definitions
        and initiatives they assign and the initiatives' member policies
        with Azure Resource Graph - a handful of queries however many
        assignments there are, with the Connect-AAC sign-in; Reader is
        enough, no Az modules. A definition Resource Graph doesn't return is
        read from Azure Resource Manager.

        Without parameters: every assignment the account can see. With
        -SubscriptionId or -ManagementGroupId: the assignments that apply
        there - at that scope or below it (its resource groups, subscriptions,
        child management groups) and those inherited from the management
        groups above it (Inherited = True), as the Azure portal lists them.
        -AssignmentName keeps the assignments whose name or display name
        matches (wildcards).

        One row per assignment and parameter (AAC.AssignedPolicy):
          AssignmentName, AssignmentDisplayName, ScopeType (Management
          group, Subscription, Resource group, Resource), ScopeName,
          Inherited, EnforcementMode, DefinitionType (Policy or PolicySet),
          DefinitionName, DefinitionDisplayName, PolicyType (BuiltIn,
          Custom, Static), Category, ResourceType, ParameterName,
          ParameterDisplayName, ParameterType, DefaultValue, AssignedValue,
          EffectiveValue, ValueSource (Assigned, Default, Not set),
          AllowedValues, NotScopes, AssignmentScope, AssignmentId and
          DefinitionId
        A list is written as its items joined with ', ', an object as
        compact JSON. A policy without parameters is one row with no
        parameter, so every assignment is listed.

        ResourceType is what the policy's rule targets: the types in its
        "field": "type" conditions, with [parameters()] resolved to the
        effective values (so "Not allowed resource types" lists the types
        it denies), else the types of the property aliases it reads, else
        'All except ...' for a rule that only leaves types out ("Allowed
        resource types": every type except those allowed), or 'All'.
        For an initiative, a row shows the types of the member policies that
        use its parameter - 'All' when one of them applies to every type.

        What you get depends on where the command runs:
          at the prompt    tiles, the assignments by scope with their
                           enforcement and resource types, the resource
                           types assigned most, and each assignment's
                           parameters as a tree - assigned values in green,
                           defaults in grey - a page at a time
          piped onward     the rows, with no view
          -PassThru        the view and the rows
          -NoDisplay       the rows only
        -CsvPath writes the rows. -HtmlPath writes an interactive report:
        tiles, charts, a table of the assignments and one of every
        parameter, searchable, filterable and downloadable as CSV. With
        either, the console shows only the progress and the files written.
    .PARAMETER ManagementGroupId
        Only the assignments that apply to these management groups (their
        ID, the name in the portal's URL).
    .PARAMETER SubscriptionId
        Only the assignments that apply to these subscriptions.
    .PARAMETER AssignmentName
        Only the assignments whose name or display name matches; wildcards
        work, e.g. '*ISO*'.
    .PARAMETER CsvPath
        Write every row to this CSV file. Alias: OutputPath.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The HTML report's title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACAssignedPolicy
        Every policy assignment you can see, with its parameters and resource types.
    .EXAMPLE
        Get-AACAssignedPolicy -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath .\assignedPolicyInventory.csv
        What applies to one subscription - its own assignments and those inherited from management groups - to CSV.
    .EXAMPLE
        Get-AACAssignedPolicy -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\AssignedPolicy.html
        Everything assigned at, above or below a management group, as an interactive HTML report.
    .EXAMPLE
        Get-AACAssignedPolicy -NoDisplay | Where-Object { $_.ValueSource -eq 'Assigned' -and $_.AssignedValue -ne $_.DefaultValue }
        The parameters set to something other than their default.
    .EXAMPLE
        Get-AACAssignedPolicy -NoDisplay | Where-Object ResourceType -Like '*Microsoft.Storage/storageAccounts*' | Select-Object AssignmentDisplayName, DefinitionDisplayName -Unique
        The assignments with a policy for storage accounts.
    .OUTPUTS
        AAC.AssignedPolicy (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.AssignedPolicy')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $AssignmentName,

        [Alias('OutputPath')]
        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $Title = 'Assigned Azure Policy',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $htmlFullPath = & $resolve $HtmlPath

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Assigned Azure Policy' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken

        # --- The assignments and where every scope sits (tenant-wide) --------------------------------
        # Tenant-wide, so a subscription's assignments inherited from its
        # management groups are there to filter (ConvertTo-AACAssignedPolicy).
        $queries = [ordered]@{
            assignments      = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id, name, displayName = tostring(properties.displayName), scope = tostring(properties.scope), definitionId = tostring(properties.policyDefinitionId), parameters = properties.parameters, enforcement = tostring(properties.enforcementMode), notScopes = properties.notScopes, description = tostring(properties.description)" }
            subscriptions    = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name, chain = properties.managementGroupAncestorsChain" }
            managementGroups = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project id, name, displayName = tostring(properties.displayName), chain = properties.details.managementGroupAncestorsChain" }
        }
        $labels = @{ assignments = 'policy assignments'; subscriptions = 'subscriptions'; managementGroups = 'management groups' }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading the policy assignments from Azure Resource Graph'
        $batch = Invoke-AACGraphBatch -Query $queries -AllowFailure 'managementGroups' -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total queries)"
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
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} policy assignment(s) in {1:N0} subscription(s) and {2:N0} management group(s)' -f $assignments.Count, $subscriptionNames.Count, $groupNames.Count)

        # --- The definitions they assign, and the initiatives' members --------------------------------
        $definitions = @{}
        $add = {
            param($Row, [string] $Kind)
            $definitions[([string]$Row['id']).ToLowerInvariant()] = @{
                Id = [string]$Row['id']; Name = [string]$Row['name']; Kind = $Kind
                DisplayName = $(if ($Row['displayName']) { [string]$Row['displayName'] } else { [string]$Row['name'] })
                PolicyType = [string]$Row['policyType']; Category = [string]$Row['category']
                Parameters = $Row['parameters']; Rule = $Row['rule']; Members = @($Row['members'])
            }
        }
        $kindOf = { param([string] $Id) if ($Id -match '(?i)/policySetDefinitions/') { 'PolicySet' } else { 'Policy' } }
        $wanted = @($assignments | ForEach-Object { ([string]$_['definitionId']).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
        Update-AACProgress -Id 'definitions' -Indeterminate -Description 'Reading the policy definitions and initiatives'
        $round = 0
        while ($wanted.Count -and $round -lt 2) {
            $round++
            $chunks = [ordered]@{}
            for ($i = 0; $i -lt $wanted.Count; $i += 100) {
                $ids = @($wanted[$i..([Math]::Min($i + 99, $wanted.Count - 1))] | ForEach-Object { "'$_'" }) -join ', '
                $chunks["definitions$round-$i"] = @{ Tenant = $true; Query = "policyresources | where type in~ ('microsoft.authorization/policydefinitions', 'microsoft.authorization/policysetdefinitions') | where tolower(id) in ($ids) | project id, name, type, displayName = tostring(properties.displayName), policyType = tostring(properties.policyType), category = tostring(properties.metadata.category), parameters = properties.parameters, rule = properties.policyRule, members = properties.policyDefinitions" }
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
                & $add @{ id = $result.Body['id']; name = $result.Body['name']; displayName = $p['displayName']; policyType = $p['policyType']; category = $(if ($p['metadata'] -is [System.Collections.IDictionary]) { $p['metadata']['category'] }); parameters = $p['parameters']; rule = $p['policyRule']; members = $p['policyDefinitions'] } (& $kindOf $id)
            }
        }
        $setCount = @($definitions.Values | Where-Object Kind -EQ 'PolicySet').Count
        Update-AACProgress -Id 'definitions' -Complete -Description ('Read {0:N0} policy definition(s) and {1:N0} initiative(s)' -f ($definitions.Count - $setCount), $setCount)

        # --- One row per assignment and parameter -----------------------------------------------------
        Update-AACProgress -Id 'flatten' -Indeterminate -Description 'Working out the effective values and resource types'
        $inventory = ConvertTo-AACAssignedPolicy -Assignment $assignments -Definition $definitions -SubscriptionName $subscriptionNames -ManagementGroupName $groupNames `
            -SubscriptionChain $subscriptionChain -GroupChain $groupChain -SubscriptionId @($SubscriptionId | Where-Object { $_ }) -ManagementGroupId @($ManagementGroupId | Where-Object { $_ }) -AssignmentName @($AssignmentName | Where-Object { $_ })
        $stats = $inventory.Stats
        Update-AACProgress -Id 'flatten' -Complete -Description ('{0:N0} assignment(s): {1:N0} initiative(s), {2:N0} policies - {3:N0} parameter(s), {4:N0} assigned, {5:N0} default' -f $stats.Assignments, $stats.Initiatives, $stats.Policies, $stats.Parameters, $stats.Assigned, $stats.Default)

        $notices = [System.Collections.Generic.List[string]]::new()
        if ($stats.Missing) { $notices.Add("$($stats.Missing) definition(s) couldn't be read (deleted, or at a scope you can't see); their assignments are listed without parameters or resource types.") }
        if (-not $stats.Assignments) { $notices.Add('No policy assignments were found in this scope.') }
        $scope = [ordered]@{}
        $scope['Scope'] = @(
            if ($ManagementGroupId) { "management group(s) $(@($ManagementGroupId | ForEach-Object { if ($groupNames.Contains($_.ToLowerInvariant())) { $groupNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ')" }
            if ($SubscriptionId) { "subscription(s) $(@($SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_.ToLowerInvariant())) { $subscriptionNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ')" }
        ) -join '; '
        if (-not $scope['Scope']) { $scope['Scope'] = 'every assignment the account can see' }
        if ($AssignmentName) { $scope['Assignments'] = $AssignmentName -join ', ' }
        $inventory.Notice = $notices.ToArray()

        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($inventory.Rows) -Noun 'assigned parameter' -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACAssignedPolicyHtml -Inventory $inventory -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Inventory = $inventory; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACAssignedPolicyView -Inventory $state.Inventory -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Inventory.Notice)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $state.Inventory.Rows
    }
}
