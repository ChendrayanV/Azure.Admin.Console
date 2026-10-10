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

        -ExpandPolicySet opens up the initiatives: one row per policy in
        force and its parameter (AAC.AssignedPolicyMember) - each member
        policy of an assigned initiative, and each policy assigned on its
        own - with the value the parameter ends up with:
          AssignmentName, AssignmentDisplayName, ScopeType, ScopeName,
          Inherited, EnforcementMode, DefinitionType, PolicySetName,
          PolicySetDisplayName, ReferenceId, PolicyName, PolicyDisplayName,
          PolicyType, Category, Effect, EffectSource, Groups, ResourceType,
          ParameterName, ParameterDisplayName, ParameterType, DefaultValue
          (the policy's), InitiativeValue (what the initiative passes it),
          InitiativeParameter, EffectiveValue, ValueSource, AllowedValues,
          NotScopes, AssignmentScope, AssignmentId, PolicySetId and PolicyId
        ValueSource: Assigned (the assignment sets the initiative parameter
        the policy's parameter takes), Initiative default, Initiative (a
        value fixed in the initiative), Policy default, Expression (another
        template expression, left as written) or Not set. Effect is the
        policy's effect resolved the same way, or the assignment's effect
        override (EffectSource Override). The HTML report always has this
        table.

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
    .PARAMETER ExpandPolicySet
        One row per policy in force and its parameter - every member policy
        of an assigned initiative with its effect and the effective value
        of each of its parameters - instead of one per assignment and
        parameter. The view lists each initiative's member policies, and
        -CsvPath writes these rows.
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
    .EXAMPLE
        Get-AACAssignedPolicy -AssignmentName '*PostgreSQL*' -ExpandPolicySet -NoDisplay | Format-Table PolicyDisplayName, Effect, ParameterName, EffectiveValue, ValueSource
        The policies inside an initiative assignment, with the effect and the value of every parameter.
    .EXAMPLE
        Get-AACAssignedPolicy -ExpandPolicySet -CsvPath .\policySetMembers.csv
        Every policy in force - initiatives opened up - with its parameters, to CSV.
    .OUTPUTS
        AAC.AssignedPolicy (piped onward, or with -PassThru or -NoDisplay)
        AAC.AssignedPolicyMember (with -ExpandPolicySet)
    #>
    [CmdletBinding()]
    [OutputType('AAC.AssignedPolicy', 'AAC.AssignedPolicyMember')]
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

        [switch] $ExpandPolicySet,

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

        # The assignments, where every scope sits and the definitions assigned (tenant-wide).
        $policyData = Read-AACAssignedPolicyData
        $assignments = $policyData.Assignments; $definitions = $policyData.Definitions
        $subscriptionNames = $policyData.SubscriptionNames; $groupNames = $policyData.GroupNames
        $subscriptionChain = $policyData.SubscriptionChain; $groupChain = $policyData.GroupChain


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

        $csvRows = if ($ExpandPolicySet) { @($inventory.Members) } else { @($inventory.Rows) }
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $csvRows -Noun $(if ($ExpandPolicySet) { 'policy parameter' } else { 'assigned parameter' }) -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACAssignedPolicyHtml -Inventory $inventory -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Inventory = $inventory; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACAssignedPolicyView -Inventory $state.Inventory -Scope $state.Scope -ExpandPolicySet:$ExpandPolicySet
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Inventory.Notice)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        if ($ExpandPolicySet) { $state.Inventory.Members } else { $state.Inventory.Rows }
    }
}
