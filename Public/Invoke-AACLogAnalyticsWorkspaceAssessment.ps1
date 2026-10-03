function Invoke-AACLogAnalyticsWorkspaceAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses a Log Analytics workspace: billable and free tables and
        their size, every workspace setting, recommendations, data collection
        rules and the Workspace Insights views (Overview, Usage, Health,
        Agents, Query Audit, Data Collection Rules, Change Log) - with a
        Spectre.Console view, an object, and CSV and interactive HTML
        reports.
    .DESCRIPTION
        Reads one workspace - read-only, nothing is changed - from:
          Azure Resource Manager   the workspace's settings, its tables
                                   (plan, retention), data exports, linked
                                   services and storage, diagnostic
                                   settings, saved searches, and the
                                   activity log (Change Log)
          Azure Resource Graph     the data collection rules sending to it
                                   and their associations, its solutions,
                                   its Azure Advisor recommendations
          the workspace itself     KQL: Usage (size per table, per day, per
                                   solution; per resource and computer for
                                   the last 24 hours), _LogOperation
                                   (Health), Heartbeat (Agents, latency),
                                   LAQueryLogs (Query Audit) - up to 5
                                   queries at a time

        -WorkspaceId is the workspace ID (its customerId GUID, as the portal
        shows it), the full resource ID, or the workspace's name.

        What comes back:
          Tables            billable and not billable: billable and free GB
                            over -Days, share of billable data, daily
                            average, last record, plan (Analytics, Basic,
                            Auxiliary), interactive and total retention,
                            Azure or custom. Tables with no data are left
                            out unless custom, on another plan or retention,
                            or -IncludeEmptyTable.
          Settings          every workspace setting: general, pricing tier
                            and daily cap, retention, access (local
                            authentication, network access, private link),
                            data collection (workspace transformation DCR,
                            solutions), data exports, linked services and
                            storage, diagnostic settings - and anything else
                            the workspace has, under Other
          Recommendations   Azure Advisor's for the workspace, and the
                            assessment's own: legacy tier, commitment tiers,
                            daily cap hit or near, spikes, retention, tables
                            for the Basic plan, ContainerLog and
                            AzureDiagnostics, unused custom tables, retired
                            MMA agents, silent agents, operation errors,
                            unassociated DCRs, shared keys, network access,
                            access control mode, query auditing, diagnostic
                            settings - by severity, with what to do
          Insights          the Workspace Insights tabs, as row sets:
                            Overview, Usage, Health, Agents, QueryAudit,
                            DataCollectionRules, ChangeLog
        -Section limits the reading to some of: Overview, Tables, Settings,
        Recommendations, Usage, Health, Agents, QueryAudit,
        DataCollectionRules, ChangeLog.

        Needs Reader on the workspace (Log Analytics Reader to query it) and
        on its resource group for the activity log. A query that can't run
        (no LAQueryLogs because query auditing is off, no Heartbeat because
        no agent reports there) is reported, and the rest carries on.

        What you get depends on where the command runs:
          at the prompt    tiles, then each section - a page at a time
          piped onward     the assessment object, with no view
          -PassThru        the view and the object
          -NoDisplay       the object only
        -CsvPath writes the tables (one row each). -HtmlPath writes an
        interactive report with every section, searchable and downloadable
        as CSV.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER Days
        How far back the usage, health, agents, query audit and change log
        look: 1 to 90 days, 30 by default.
    .PARAMETER Section
        Only these sections: Overview, Tables, Settings, Recommendations,
        Usage, Health, Agents, QueryAudit, DataCollectionRules, ChangeLog.
        All of them by default.
    .PARAMETER IncludeEmptyTable
        Also list the tables with no data in the period (a workspace has
        hundreds).
    .PARAMETER CsvPath
        Write the tables to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The HTML report's title.
    .PARAMETER PassThru
        Show the view and also return the assessment.
    .PARAMETER NoDisplay
        Return the assessment without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 00000000-0000-0000-0000-000000000000
        The whole assessment of one workspace, by its workspace ID.
    .EXAMPLE
        Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -Days 7 -HtmlPath .\out\Workspace.html -CsvPath .\out\Tables.csv
        The last 7 days, as an HTML report and the tables as CSV.
    .EXAMPLE
        (Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -Section Tables -NoDisplay).Tables | Where-Object Billing -EQ 'Billable' | Sort-Object BillableGB -Descending | Select-Object -First 10
        The ten largest billable tables.
    .EXAMPLE
        (Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -NoDisplay).Recommendations | Where-Object Severity -EQ 'High'
        The high-severity recommendations.
    .OUTPUTS
        AAC.LogAnalyticsWorkspaceAssessment (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.LogAnalyticsWorkspaceAssessment')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [ValidateSet('Overview', 'Tables', 'Settings', 'Recommendations', 'Usage', 'Health', 'Agents', 'QueryAudit', 'DataCollectionRules', 'ChangeLog')]
        [string[]] $Section,

        [switch] $IncludeEmptyTable,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $Title = 'Log Analytics workspace assessment',

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
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        Target            = $WorkspaceId.Trim()
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ })
        Days              = $Days
        Section           = @(if ($Section) { $Section } else { 'Overview', 'Tables', 'Settings', 'Recommendations', 'Usage', 'Health', 'Agents', 'QueryAudit', 'DataCollectionRules', 'ChangeLog' })
        IncludeEmptyTable = [bool]$IncludeEmptyTable
        Title             = $Title
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Log Analytics workspace assessment' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $want = { param([string[]] $Name) @($Name | Where-Object { $request.Section -contains $_ }).Count -gt 0 }

        # --- Which workspace ------------------------------------------------------------------------------------
        Update-AACProgress -Id 'find' -Description "Finding workspace $($request.Target)" -Indeterminate
        $target = $request.Target
        $resourceId = if ($target -match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.OperationalInsights/workspaces/[^/]+$') {
            $target
        }
        elseif ($target -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
            $found = Invoke-AACGraphBatch -SubscriptionId $request.SubscriptionId -Query @{ workspace = "resources | where type =~ 'microsoft.operationalinsights/workspaces' and tostring(properties.customerId) =~ '$($target.ToLowerInvariant())' | project id" }
            $ids = @($found.Rows['workspace'] | ForEach-Object { [string]$_['id'] })
            if (-not $ids.Count) {
                $problem = [System.InvalidOperationException]::new("No Log Analytics workspace with workspace ID $target was found$(if ($request.SubscriptionId) { " in subscription $($request.SubscriptionId -join ', ')" } else { ' in the subscriptions the account can see' }).")
                $problem.Data['AACHint'] = 'The workspace ID is on the workspace''s Overview page in the portal. You can also pass its resource ID or name.'
                throw $problem
            }
            $ids[0]
        }
        else {
            (Resolve-AACLogResource -Kind Workspace -Name $target -SubscriptionId $request.SubscriptionId).Id
        }
        $resourceId = $resourceId.TrimEnd('/')
        $segments = $resourceId -split '/'
        $subscription = $segments[2]
        $group = $segments[4]
        Update-AACProgress -Id 'find' -Complete -Description "Workspace $($segments[-1]) ($group)"

        # --- Azure Resource Manager -------------------------------------------------------------------------------
        $now = [datetime]::UtcNow
        $uris = [ordered]@{ workspace = "$resourceId`?api-version=2023-09-01" }
        if (& $want 'Tables', 'Overview', 'Recommendations', 'Usage') { $uris['tables'] = "$resourceId/tables?api-version=2022-10-01" }
        if (& $want 'Settings', 'Recommendations') {
            $uris['dataExports'] = "$resourceId/dataExports?api-version=2020-08-01"
            $uris['linkedServices'] = "$resourceId/linkedServices?api-version=2020-08-01"
            $uris['linkedStorageAccounts'] = "$resourceId/linkedStorageAccounts?api-version=2020-08-01"
            $uris['diagnosticSettings'] = "$resourceId/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
            $uris['savedSearches'] = "$resourceId/savedSearches?api-version=2020-08-01"
        }
        if (& $want 'ChangeLog', 'Overview') {
            $filter = "eventTimestamp ge '$($now.AddDays(-$request.Days).ToString('yyyy-MM-ddTHH:mm:ssZ'))' and eventTimestamp le '$($now.ToString('yyyy-MM-ddTHH:mm:ssZ'))' and resourceGroupName eq '$group'"
            $uris['activityLog'] = "/subscriptions/$subscription/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$([uri]::EscapeDataString($filter))&`$select=eventTimestamp,operationName,status,subStatus,caller,resourceId,level"
        }
        Update-AACProgress -Id 'arm' -Total $uris.Count -Description 'Reading the workspace''s settings from Azure Resource Manager'
        $read = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'arm' -Increment 1 -Description "Reading the workspace's settings ($Done of $Total)" }
        $arm = @{}
        foreach ($name in $uris.Keys) { $arm[$name] = $read[$uris[$name]] }
        if ($arm.workspace.Error -or $arm.workspace.Body -isnot [System.Collections.IDictionary]) {
            $problem = [System.InvalidOperationException]::new("The workspace $resourceId couldn't be read: $($arm.workspace.Error)")
            if ($arm.workspace.Status -in 401, 403) { $problem.Data['AACHint'] = 'Your account needs Reader (or Log Analytics Reader) on the workspace.' }
            throw $problem
        }
        $workspace = $arm.workspace.Body
        $customerId = [string]$workspace['properties']['customerId']
        $arm.Remove('workspace')
        Update-AACProgress -Id 'arm' -Complete -Description "Read the workspace's settings: $($uris.Count) request(s)$(if (@($arm.Values | Where-Object Error).Count) { ", $(@($arm.Values | Where-Object Error).Count) failed" })"

        # --- Azure Resource Graph ----------------------------------------------------------------------------------
        $graphQueries = Get-AACWorkspaceAssessmentQuery -Kind Graph -Section $request.Section -WorkspaceResourceId $resourceId
        Update-AACProgress -Id 'graph' -Total $graphQueries.Count -Description 'Reading data collection rules, solutions and Advisor from Azure Resource Graph'
        $graph = Invoke-AACGraphBatch -Query $graphQueries -AllowFailure @($graphQueries.Keys) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'graph' -Increment 1 }
        $ruleIds = @($graph.Rows['rules'] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_['id'] })
        if ($ruleIds.Count) {
            $linked = Invoke-AACGraphBatch -Query (Get-AACWorkspaceAssessmentQuery -Kind Association -RuleId $ruleIds) -AllowFailure 'associations'
            $graph.Rows['associations'] = $linked.Rows['associations']
            if ($linked.Errors.Contains('associations')) { $graph.Errors['associations'] = $linked.Errors['associations'] }
        }
        elseif ($graph.Rows.Contains('rules')) { $graph.Rows['associations'] = @() }
        Update-AACProgress -Id 'graph' -Complete -Description "$($ruleIds.Count) data collection rule(s), $(@($graph.Rows['solutions'] | Where-Object { $null -ne $_ }).Count) solution(s), $(@($graph.Rows['advisor'] | Where-Object { $null -ne $_ }).Count) Advisor recommendation(s)"

        # --- KQL in the workspace ----------------------------------------------------------------------------------
        $kqlQueries = Get-AACWorkspaceAssessmentQuery -Kind Kql -Section $request.Section -Days $request.Days
        $kql = @{ Rows = @{}; Errors = @{} }
        if ($kqlQueries.Count) {
            Update-AACProgress -Id 'kql' -Total $kqlQueries.Count -Description "Querying the workspace ($($kqlQueries.Count) queries)"
            $kql = Invoke-AACLogQueryBatch -WorkspaceId $customerId -Query $kqlQueries -Timespan "P$($request.Days)D" -OnProgress {
                param($Name, $Done, $Total)
                Update-AACProgress -Id 'kql' -Increment 1 -Description "Querying the workspace ($Done of $Total queries)"
            }
            Update-AACProgress -Id 'kql' -Complete -Description "Queried the workspace: $($kqlQueries.Count) queries$(if ($kql.Errors.Count) { ", $($kql.Errors.Count) couldn't run" })"
        }

        $assessment = ConvertTo-AACWorkspaceAssessment -Workspace $workspace -Arm $arm -Kql $kql -Graph $graph -Days $request.Days -IncludeEmptyTable:$request.IncludeEmptyTable -Now $now
        $assessment['Section'] = $request.Section
        $result = [pscustomobject][ordered]@{
            PSTypeName          = 'AAC.LogAnalyticsWorkspaceAssessment'
            Name                = $assessment.Workspace.Name
            WorkspaceId         = $assessment.Workspace.WorkspaceId
            ResourceGroup       = $assessment.Workspace.ResourceGroup
            PricingTier         = $assessment.Workspace.PricingTier
            RetentionDays       = $assessment.Workspace.RetentionDays
            Days                = $request.Days
            BillableGB          = $assessment.Stats.BillableGB
            AverageDailyGB      = $assessment.Stats.AverageDailyGB
            Recommendations     = $assessment.Recommendations
            Tables              = $assessment.Tables
            Settings            = $assessment.Settings
            Agents              = $assessment.Agents
            DataCollectionRules = $assessment.DataCollectionRules
            ChangeLog           = $assessment.ChangeLog
            Insights            = $assessment.Insights
            Workspace           = $assessment.Workspace
            Errors              = $assessment.Errors
        }
        $detail = [ordered]@{ Workspace = "$($assessment.Workspace.Name) ($($assessment.Workspace.WorkspaceId))"; 'Resource group' = $assessment.Workspace.ResourceGroup; Period = "last $($request.Days) day(s)" }
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($assessment.Tables) -Noun 'table' -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACWorkspaceAssessmentHtml -Assessment $assessment -Path $htmlFullPath -Title $request.Title -Detail $detail
        }
        @{ Assessment = $assessment; Result = $result }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACWorkspaceAssessmentView -Assessment $state.Assessment
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Assessment.Notices)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $state.Result
    }
}
