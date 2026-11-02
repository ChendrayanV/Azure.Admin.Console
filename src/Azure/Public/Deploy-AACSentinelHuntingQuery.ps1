function Deploy-AACSentinelHuntingQuery {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Adds hunting queries to a Microsoft Sentinel workspace, from the packs,
        from YAML files you name or from Find-AACSentinelHuntingQuery, and keeps
        them up to date.
    .DESCRIPTION
        Plans, shows the plan, asks, applies. Each query is a saved search in
        the Hunting Queries category, which is how Sentinel stores them, with
        the query's ID from its source file: running this again updates it
        rather than adding another.

        What happens to each query:
          Create   not on the workspace, and ready
          Update   deployed by this module, unedited, and the catalog has moved on
          Skip     already current; not ready (a table with no data, a missing
                   watchlist - -IncludeNotReady deploys it anyway); edited in the
                   workspace or not deployed by this module (-OverwriteChanged
                   replaces it); or this name is already there under another ID,
                   say from Content hub (always skipped: a second copy would
                   only confuse)

        Entity mappings in the source files aren't deployed: a saved search has
        nowhere to put them, and Microsoft's own solutions leave them out too.

        These queries are community content, and only read data: read one before
        relying on it. -WhatIf shows the plan and writes nothing. -Force skips
        the question, for pipelines; it doesn't overwrite an edited query.

        -YamlSource deploys files you name instead of a pack: links to GitHub, or
        files on this computer. They go through the same plan and rules, so a
        file whose tables have no data is skipped unless -IncludeNotReady says
        otherwise. A link to a branch reads whatever is on it now, not the
        pinned commit: link to a commit to deploy exactly what you read.

        Needs Microsoft Sentinel Contributor or Log Analytics Contributor on the
        workspace.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER InputObject
        Queries from Find-AACSentinelHuntingQuery, instead of -Pack.
    .PARAMETER Pack
        SignIn, M365, EntraAudit, Intune.
    .PARAMETER YamlSource
        Hunting query YAML files, instead of a pack: github.com/.../blob/... or
        raw.githubusercontent.com links, or local paths. A stub in
        Azure/Azure-Sentinel is followed to where the query moved. If one can't
        be read, nothing is deployed.
    .PARAMETER Name
        Only queries with these names (wildcards work).
    .PARAMETER Tactic
        Only queries for these MITRE ATT&CK tactics, such as InitialAccess.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Days
        How far back a table must have data to count: 1 to 90 days, 30 by
        default.
    .PARAMETER Ref
        The commit, branch or tag of Azure/Azure-Sentinel to read. A commit
        pinned in the module by default.
    .PARAMETER Path
        The top folder of a local clone of Azure/Azure-Sentinel, instead of
        GitHub.
    .PARAMETER IncludeNotReady
        Also create queries whose tables have no data or whose watchlists are
        missing.
    .PARAMETER OverwriteChanged
        Replace queries that were edited in the workspace, or that this module
        didn't deploy.
    .PARAMETER Force
        Apply without asking (for pipelines).
    .PARAMETER PassThru
        Show the plan and also return the deployment.
    .PARAMETER NoDisplay
        Return the deployment without showing the plan.
    .EXAMPLE
        Connect-AAC
        Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel' -Pack SignIn, M365, Intune -WhatIf
        The plan: what would be created, updated and skipped, and why. Nothing is written.
    .EXAMPLE
        Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel' -Pack Intune -IncludeNotReady
        Add the Intune queries, even before Intune's logs reach the workspace.
    .EXAMPLE
        Find-AACSentinelHuntingQuery -Pack SignIn -Tactic InitialAccess | Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel'
        Add the sign-in queries for one tactic.
    .EXAMPLE
        Deploy-AACSentinelHuntingQuery -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName 'rg-sentinel' -WorkspaceName 'law-sentinel' -YamlSource 'https://github.com/Azure/Azure-Sentinel/blob/master/Hunting%20Queries/OfficeActivity/AnomolousUserAccessingOtherUsersMailbox.yaml'
        Add one query from a link. This file has moved, so the query is read from where it says it went.
    .EXAMPLE
        Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-sentinel' -YamlSource .\queries\OurOwnQuery.yaml, .\queries\AnotherOne.yaml -WhatIf
        The plan for your own query files.
    .OUTPUTS
        AAC.SentinelHuntingDeployment (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Pack')]
    [OutputType('AAC.SentinelHuntingDeployment')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [object[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Pack')]
        [ValidateSet('SignIn', 'M365', 'EntraAudit', 'Intune')]
        [string[]] $Pack,

        [Parameter(Mandatory, ParameterSetName = 'YamlSource')]
        [ValidateNotNullOrEmpty()]
        [string[]] $YamlSource,

        [SupportsWildcards()]
        [string[]] $Name,

        [string[]] $Tactic,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [Parameter(ParameterSetName = 'Pack')]
        [ValidatePattern('^[\w./-]+$')]
        [string] $Ref,

        [Parameter(ParameterSetName = 'Pack')]
        [string] $Path,

        [switch] $IncludeNotReady,

        [switch] $OverwriteChanged,

        [switch] $Force,

        [switch] $PassThru,

        [switch] $NoDisplay
    )

    begin {
        $piped = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in @($InputObject | Where-Object { $null -ne $_ })) { $piped.Add($item) }
    }

    end {
        # A failure anywhere below ends as a Spectre.Console error panel and this
        # command's own terminating error, not a line inside the module. A stopped
        # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
        # rethrow would stop the caller's whole script, not only this command.
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
        # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
        $catalogArguments = @{}
        if ($Pack) { $catalogArguments.Pack = $Pack }
        if ($Ref) { $catalogArguments.Ref = $Ref }
        if ($Path) { $catalogArguments.Path = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) }
        $yamlSources = @($YamlSource | Where-Object { $_ } | ForEach-Object { if ($_ -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $_ } else { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_) } })
        $request = @{
            Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Days = $Days; Piped = $piped.ToArray(); YamlSource = $yamlSources
            Name = @($Name | Where-Object { $_ }); Tactic = @($Tactic | Where-Object { $_ }); IncludeNotReady = [bool]$IncludeNotReady; OverwriteChanged = [bool]$OverwriteChanged; UseCatalog = $PSCmdlet.ParameterSetName -eq 'Pack'
        }

        if ($interactive) {
            Write-AACRule -Title 'Azure Admin Console :: Deploy Sentinel hunting queries' -Color 'springgreen3'
        }

        # --- The plan -----------------------------------------------------------------------------------------------
        $state = Invoke-AACProgress -ScriptBlock {
            # The plan only reads - -WhatIf is for the apply below.
            $WhatIfPreference = $false
            $null = Get-AACAccessToken
            Update-AACProgress -Id 'catalog' -Description 'Reading the hunting queries' -Indeterminate
            $catalog = if ($request.YamlSource.Count) { Get-AACHuntingQueryFromYaml -Source $request.YamlSource }
            elseif ($request.UseCatalog) { Get-AACHuntingQueryCatalog @catalogArguments }
            else { @{ Queries = $request.Piped; Failures = [ordered]@{} } }
            $queries = @($catalog.Queries | Where-Object {
                    $row = $_
                    (-not $request.Name.Count -or @($request.Name | Where-Object { $row.Name -like $_ }).Count) -and
                    (-not $request.Tactic.Count -or @($request.Tactic | Where-Object { ([string]$row.Tactics -split ',\s*') -contains $_ }).Count)
                })
            Update-AACProgress -Id 'catalog' -Complete -Description "$($queries.Count) hunting query(ies) to consider"

            Update-AACProgress -Id 'workspace' -Description "Checking workspace $($request.Target)" -Indeterminate
            $workspace = Read-AACHuntingWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Days $request.Days
            if (-not $workspace.SentinelEnabled) {
                $problem = [System.InvalidOperationException]::new("Microsoft Sentinel is not enabled on workspace $($workspace.Name), so nothing was deployed.")
                $problem.Data['AACHint'] = 'Enable Microsoft Sentinel on the workspace first, or point this command at the workspace that has it.'
                throw $problem
            }
            # Without knowing what is there, a write could replace someone's work.
            if ($workspace.Errors.Contains('Saved searches')) {
                $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the saved searches of $($workspace.Name), so nothing was deployed: $($workspace.Errors['Saved searches'])")
                $problem.Data['AACHint'] = 'Check your role on the workspace, then run the command again.'
                throw $problem
            }
            $savedById = @{}
            foreach ($saved in @($workspace.SavedSearches)) { $savedById[([string]$saved['name']).ToLowerInvariant()] = $saved }

            $plan = @(foreach ($query in @(ConvertTo-AACHuntingQueryState -Query $queries -Workspace $workspace)) {
                    $action = 'Skip'
                    $reason = ''
                    switch ($query.Deployment) {
                        'New' {
                            if ($query.Ready -or $request.IncludeNotReady) { $action = 'Create'; $reason = $(if ($query.Ready) { 'Not on the workspace' } else { "Not on the workspace; deployed although: $($query.Readiness) $($query.Missing)".TrimEnd() }) }
                            else { $reason = "$($query.Readiness)$(if ($query.Missing) { ": $($query.Missing)" }). -IncludeNotReady deploys it anyway." }
                        }
                        'Update available' { $action = 'Update'; $reason = 'The catalog has a newer query' }
                        'Current' { $reason = 'Already current' }
                        'Other copy' { $reason = 'This name is already on the workspace under another ID' }
                        'Changed' {
                            if ($request.OverwriteChanged) { $action = 'Update'; $reason = 'Replacing the workspace''s version (-OverwriteChanged)' }
                            else { $reason = 'Edited in the workspace, or not deployed by this module. -OverwriteChanged replaces it.' }
                        }
                    }
                    $saved = $savedById[([string]$query.Id).ToLowerInvariant()]
                    $tags = @(
                        @{ name = 'description'; value = [string]$query.Description }
                        @{ name = 'tactics'; value = (([string]$query.Tactics -split ',\s*') -join ',') }
                        @{ name = 'techniques'; value = (([string]$query.Techniques -split ',\s*') -join ',') }
                        # So that a later run can tell this module's queries, and whether they were edited.
                        @{ name = 'aacSource'; value = $(if ($query.RepoPath) { "$($query.Source)/$($query.RepoPath)" } else { [string]$query.Source }) }
                        @{ name = 'aacVersion'; value = [string]$query.Version }
                        @{ name = 'aacQueryHash'; value = (Get-AACHuntingQueryHash -Query ([string]$query.Query)) }
                    )
                    $body = [ordered]@{ properties = [ordered]@{ category = 'Hunting Queries'; displayName = [string]$query.Name; query = [string]$query.Query; version = 2; tags = $tags } }
                    # Azure refuses to replace a saved search without its etag, or '*'.
                    if ($saved) { $body['etag'] = $(if ($saved['etag']) { [string]$saved['etag'] } else { '*' }) }
                    [pscustomobject][ordered]@{
                        PSTypeName = 'AAC.SentinelHuntingPlanItem'
                        Name       = [string]$query.Name
                        Action     = $action
                        Reason     = $reason
                        Status     = $(if ($action -eq 'Skip') { 'Skipped' } else { 'Planned' })
                        Detail     = ''
                        Pack       = [string]$query.Pack
                        Readiness  = [string]$query.Readiness
                        Deployment = [string]$query.Deployment
                        Id         = [string]$query.Id
                        Uri        = "$($workspace.ResourceId)/savedSearches/$($query.Id)?api-version=2025-07-01"
                        Body       = $body
                    }
                })
            $writes = @($plan | Where-Object Action -NE 'Skip').Count
            Update-AACProgress -Id 'workspace' -Complete -Description "Plan: $(@($plan | Where-Object Action -EQ 'Create').Count) to create, $(@($plan | Where-Object Action -EQ 'Update').Count) to update, $(@($plan | Where-Object Action -EQ 'Skip').Count) to skip"
            @{ Workspace = $workspace; Plan = $plan; Writes = $writes; Catalog = $catalog; Status = '' }
        }

        $actionTones = @{ Create = 'info'; Update = 'warn'; Skip = 'neutral' }
        $statusTones = @{ Planned = 'info'; Applied = 'good'; Failed = 'bad'; Skipped = 'neutral'; Declined = 'neutral' }
        $showPlan = {
            param([string] $Headline, [string] $Status)
            $WhatIfPreference = $false
            $plan = @($state.Plan)
            Invoke-AACReportOutput -ShowView -NoPaging -Title 'Sentinel hunting queries' -Object @() -Report @{
                Facts    = [ordered]@{ Workspace = "$($state.Workspace.Name) ($($state.Workspace.ResourceGroup))" }
                Status   = $Status
                Headline = $Headline
                Tiles    = @(
                    @{ Value = '{0:N0}' -f @($plan | Where-Object Action -EQ 'Create').Count; Label = 'to create'; Tone = 'info' }
                    @{ Value = '{0:N0}' -f @($plan | Where-Object Action -EQ 'Update').Count; Label = 'to update'; Tone = 'warn' }
                    @{ Value = '{0:N0}' -f @($plan | Where-Object Action -EQ 'Skip').Count; Label = 'skipped'; Tone = 'neutral' }
                )
                Notices  = @(
                    foreach ($key in @($state.Workspace.Errors.Keys)) { @{ Status = 'Warning'; Text = "$key couldn't be read: $($state.Workspace.Errors[$key])" } }
                    foreach ($key in @($state.Catalog.Failures.Keys)) { @{ Status = 'Warning'; Text = "$key couldn't be read: $($state.Catalog.Failures[$key])" } }
                )
                Tables   = @(
                    @{ Id = 'plan'; Title = 'Hunting queries'; Rows = @($plan | Sort-Object -Property @{ Expression = { @{ Create = 0; Update = 1; Skip = 2 }[$_.Action] } }, Name); Noun = 'queries'; ConsoleLimit = 200
                        Empty = 'No hunting query matches.'; EmptyStatus = 'Info'
                        Columns = @(
                            @{ Key = 'Action'; Label = 'Action'; Type = 'badge'; Tones = $actionTones; Console = $true }
                            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Console = $true }
                            @{ Key = 'Name'; Label = 'Query'; Console = $true }
                            @{ Key = 'Pack'; Label = 'Pack'; Console = $true }
                            @{ Key = 'Reason'; Label = 'Why'; Console = $true }
                            @{ Key = 'Detail'; Label = 'Detail'; Console = @($plan | Where-Object Detail).Count -gt 0 }
                        ) }
                )
            }
        }

        # --- Decide -------------------------------------------------------------------------------------------------
        $target = "workspace $($state.Workspace.Name)"
        $what = "Create $(@($state.Plan | Where-Object Action -EQ 'Create').Count) and update $(@($state.Plan | Where-Object Action -EQ 'Update').Count) hunting query(ies)"
        if ($interactive) { & $showPlan "$what on $($state.Workspace.Name)" 'Warning' }
        if (-not $state.Writes) {
            $state.Status = 'NoChanges'
        }
        elseif ($WhatIfPreference) {
            $null = $PSCmdlet.ShouldProcess($target, $what)
            $state.Status = 'Planned'
        }
        elseif ($Force -or $PSCmdlet.ShouldProcess($target, $what)) {
            # --- Apply: one query failing doesn't stop the rest -------------------------------------------------------
            $state = Invoke-AACProgress -ScriptBlock {
                $toWrite = @($state.Plan | Where-Object Action -NE 'Skip')
                Update-AACProgress -Id 'apply' -Total $toWrite.Count -Description 'Writing the hunting queries'
                foreach ($item in $toWrite) {
                    try {
                        $null = Invoke-AACArmWrite -Method Put -Uri $item.Uri -Body $item.Body
                        $item.Status = 'Applied'
                    }
                    catch {
                        $item.Status = 'Failed'
                        $item.Detail = [string]$_.Exception.Message
                    }
                    Update-AACProgress -Id 'apply' -Increment 1
                }
                $state.Status = if (@($toWrite | Where-Object Status -EQ 'Failed').Count) { 'Failed' } else { 'Applied' }
                Update-AACProgress -Id 'apply' -Complete -Description "Wrote $(@($toWrite | Where-Object Status -EQ 'Applied').Count) of $($toWrite.Count) hunting query(ies)"
                $state
            }
            if ($interactive) { & $showPlan "$(@($state.Plan | Where-Object Status -EQ 'Applied').Count) hunting query(ies) written to $($state.Workspace.Name)" $(if ($state.Status -eq 'Failed') { 'Failed' } else { 'Success' }) }
            if ($state.Status -eq 'Failed') {
                $failures = @($state.Plan | Where-Object Status -EQ 'Failed')
                $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't write $($failures.Count) hunting query(ies), first '$($failures[0].Name)': $($failures[0].Detail)")
                $problem.Data['AACHint'] = "$(@($state.Plan | Where-Object Status -EQ 'Applied').Count) written before or after it stay. You need Microsoft Sentinel Contributor or Log Analytics Contributor on the workspace. Fix the cause and run again: it carries on from there."
                throw $problem
            }
        }
        else {
            $state.Status = 'Declined'
            foreach ($item in @($state.Plan | Where-Object Status -EQ 'Planned')) { $item.Status = 'Declined' }
        }

        if ($returnObjects) {
            [pscustomobject][ordered]@{
                PSTypeName  = 'AAC.SentinelHuntingDeployment'
                Workspace   = $state.Workspace.Name
                Status      = $state.Status
                Created     = @($state.Plan | Where-Object { $_.Action -eq 'Create' -and $_.Status -eq 'Applied' }).Count
                Updated     = @($state.Plan | Where-Object { $_.Action -eq 'Update' -and $_.Status -eq 'Applied' }).Count
                Skipped     = @($state.Plan | Where-Object Action -EQ 'Skip').Count
                Queries     = @($state.Plan)
            }
        }
    }
}
