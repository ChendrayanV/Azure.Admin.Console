function Invoke-AACSentinelAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses Microsoft Sentinel on a Log Analytics workspace: analytics
        rules and MITRE ATT&CK coverage, rule templates, data connectors,
        tables and ingestion, health failures, incidents, automation rules and
        recommendations - with a Spectre.Console view, an object, and CSV and
        interactive HTML and PDF reports.
    .DESCRIPTION
        Reads one workspace - read-only, nothing is changed - from:
          Azure Resource Manager   whether Sentinel is enabled, its analytics
                                   rules and templates, data connectors,
                                   incidents and automation rules, and the
                                   workspace's tables (plan, retention)
          the workspace itself     KQL: Usage (size and last record per table),
                                   _SentinelHealth (failures per resource) and
                                   SecurityIncident (when incidents closed)

        -WorkspaceId is the workspace ID (its customerId GUID, as the portal
        shows it), the full resource ID, or the workspace's name.

        What comes back:
          AnalyticsRules    every rule: kind, severity, enabled, tactics,
                            frequency, query, its health failures and
                            incidents. Failing rules first.
          TacticCoverage    how many enabled rules declare each MITRE ATT&CK
                            Enterprise tactic
          RuleTemplates     every template the API lists (built-in and from
                            installed solutions): the data it needs, whether
                            that data is arriving and whether a rule uses it.
                            Candidates - data arriving, no rule yet - first.
          Incidents         every incident created in the last -Days: severity,
                            status, owner, classification, hours to close.
                            These hold people's names and email addresses, and
                            so do the reports.
          AutomationRules   every automation rule, in the order they run:
                            state, triggers, actions, expiry
          DataConnectors    every connector the API lists: kind, state, data
                            types. A source can send data without being listed
                            here, so Tables is what shows what really arrives.
          Tables            billable and free GB over -Days, share of billable
                            data, daily average, plan, retention, last record.
                            Tables with no data are left out unless custom, or
                            with -IncludeEmptyTable.
          HealthFailures    what _SentinelHealth reports as failed: resource,
                            operation, count, last failure and reason
          Recommendations   Sentinel not enabled, enabled rules failing, tables
                            that stopped receiving data, health monitoring off,
                            connector or automation failures, billable tables
                            no enabled rule reads, templates to enable, MITRE
                            ATT&CK gaps, incidents with no owner or slow to
                            close, noisy rules, expired or disabled automation,
                            rules with a newer template - by severity, with
                            what to do
        -Section limits the reading to some of: AnalyticsRules, RuleTemplates,
        DataConnectors, Tables, Health, Incidents, AutomationRules,
        Recommendations.

        Needs Microsoft Sentinel Reader and Log Analytics Reader on the
        workspace. What can't be read is reported, and the rest carries on.

        What you get depends on where the command runs:
          at the prompt    tiles, then each section - a page at a time
          piped onward     the assessment object, with no view
          -PassThru        the view and the object
          -NoDisplay       the object only
        -CsvPath writes the analytics rules (one row each). -HtmlPath writes a
        tabbed interactive report - a Summary (headline, tiles, charts), then
        a tab per section - every table searchable, filterable and
        downloadable as CSV. -PdfPath writes the same as a PDF, each section a
        bookmarked heading.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER Days
        How far back ingestion, health and incidents look: 1 to 90 days, 30 by
        default.
    .PARAMETER Section
        Only these sections: AnalyticsRules, RuleTemplates, DataConnectors,
        Tables, Health, Incidents, AutomationRules, Recommendations. All of
        them by default.
    .PARAMETER IncludeEmptyTable
        Also list the tables with no data in the period (a workspace has
        hundreds).
    .PARAMETER CsvPath
        Write the analytics rules to this CSV file.
    .PARAMETER HtmlPath
        Write a tabbed interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the assessment.
    .PARAMETER NoDisplay
        Return the assessment without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACSentinelAssessment -WorkspaceId 00000000-0000-0000-0000-000000000000
        The whole assessment of one workspace, by its workspace ID.
    .EXAMPLE
        Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -Days 7 -Section Tables, Health
        Ingestion and health failures over the last 7 days.
    .EXAMPLE
        Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -HtmlPath .\out\Sentinel.html -PdfPath .\out\Sentinel.pdf -CsvPath .\out\AnalyticsRules.csv
        A tabbed HTML report and a PDF, and the analytics rules as CSV.
    .EXAMPLE
        (Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -Section RuleTemplates -NoDisplay).RuleTemplates | Where-Object Candidate
        The templates worth enabling: their data is arriving and no rule uses them.
    .EXAMPLE
        (Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -Section AnalyticsRules -NoDisplay).AnalyticsRules | Where-Object Enabled -EQ $false
        The analytics rules that are turned off.
    .EXAMPLE
        (Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -NoDisplay).Recommendations | Where-Object Severity -EQ 'High'
        The high-severity recommendations.
    .OUTPUTS
        AAC.SentinelAssessment (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelAssessment')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [ValidateSet('AnalyticsRules', 'RuleTemplates', 'DataConnectors', 'Tables', 'Health', 'Incidents', 'AutomationRules', 'Recommendations')]
        [string[]] $Section,

        [switch] $IncludeEmptyTable,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel assessment',

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
    $showView = $interactive -and -not ($CsvPath -or $HtmlPath -or $PdfPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $htmlFullPath = & $resolve $HtmlPath
    $pdfFullPath = & $resolve $PdfPath
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        Target            = $WorkspaceId.Trim()
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ })
        Days              = $Days
        Section           = @(if ($Section) { $Section } else { 'AnalyticsRules', 'RuleTemplates', 'DataConnectors', 'Tables', 'Health', 'Incidents', 'AutomationRules', 'Recommendations' })
        IncludeEmptyTable = [bool]$IncludeEmptyTable
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel assessment' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $want = { param([string[]] $Name) @($Name | Where-Object { $request.Section -contains $_ }).Count -gt 0 }

        # --- Which workspace ------------------------------------------------------------------------------------
        Update-AACProgress -Id 'find' -Description "Finding workspace $($request.Target)" -Indeterminate
        $resourceId = Resolve-AACWorkspaceResourceId -Target $request.Target -SubscriptionId $request.SubscriptionId
        $insights = "$resourceId/providers/Microsoft.SecurityInsights"
        $workspaceUri = "$resourceId`?api-version=2023-09-01"
        $onboardingUri = "$insights/onboardingStates?api-version=2025-09-01"
        $first = Invoke-AACArmParallel -Uri @($workspaceUri, $onboardingUri)
        $found = $first[$workspaceUri]
        if ($found.Error -or $found.Body -isnot [System.Collections.IDictionary]) {
            $problem = [System.InvalidOperationException]::new("The workspace $resourceId couldn't be read: $($found.Error)")
            if ($found.Status -in 401, 403) { $problem.Data['AACHint'] = 'Your account needs Reader (or Microsoft Sentinel Reader) on the workspace.' }
            throw $problem
        }
        $workspace = $found.Body
        $customerId = [string]$workspace['properties']['customerId']
        # Sentinel is on when the workspace has an onboarding state. If that
        # couldn't be read (no permission), carry on: the other reads can still work.
        $onboarding = $first[$onboardingUri]
        $notOnboarded = $onboarding.Status -eq 404 -or (-not $onboarding.Error -and -not @($onboarding.Items | Where-Object { $_ }).Count)
        Update-AACProgress -Id 'find' -Complete -Description "Workspace $($workspace['name']): Microsoft Sentinel $(if ($notOnboarded) { 'isn''t enabled' } else { 'found' })"

        $arm = @{ onboarding = $onboarding }
        $kql = @{ Rows = @{}; Errors = @{} }
        if (-not $notOnboarded) {
            # --- Azure Resource Manager -------------------------------------------------------------------------
            $uris = [ordered]@{}
            # A template's candidacy depends on which rules use it, so templates read the rules too.
            if (& $want 'AnalyticsRules', 'RuleTemplates', 'Recommendations') { $uris['alertRules'] = "$insights/alertRules?api-version=2025-09-01" }
            if (& $want 'AnalyticsRules', 'RuleTemplates', 'Recommendations') { $uris['alertRuleTemplates'] = "$insights/alertRuleTemplates?api-version=2025-09-01" }
            if (& $want 'DataConnectors') { $uris['dataConnectors'] = "$insights/dataConnectors?api-version=2025-09-01" }
            if (& $want 'Tables', 'RuleTemplates', 'Recommendations') { $uris['tables'] = "$resourceId/tables?api-version=2022-10-01" }
            if (& $want 'Incidents', 'Recommendations') {
                # Bounded by date, because every page is read: a busy workspace has
                # far too many incidents to fetch them all.
                $since = [datetime]::UtcNow.AddDays(-$request.Days).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
                $uris['incidents'] = "$insights/incidents?api-version=2025-09-01&`$top=1000&`$filter=$([uri]::EscapeDataString("properties/createdTimeUtc ge $since"))"
            }
            if (& $want 'AutomationRules', 'Recommendations') { $uris['automationRules'] = "$insights/automationRules?api-version=2025-09-01" }
            if ($uris.Count) {
                Update-AACProgress -Id 'arm' -Total $uris.Count -Description 'Reading Microsoft Sentinel from Azure Resource Manager'
                $read = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'arm' -Increment 1 -Description "Reading Microsoft Sentinel ($Done of $Total)" }
                foreach ($name in $uris.Keys) { $arm[$name] = $read[$uris[$name]] }
                Update-AACProgress -Id 'arm' -Complete -Description "Read from Azure Resource Manager: $($uris.Count) request(s)"
            }

            # --- KQL in the workspace ---------------------------------------------------------------------------
            $kqlQueries = Get-AACSentinelAssessmentQuery -Section $request.Section -Days $request.Days
            if ($kqlQueries.Count) {
                Update-AACProgress -Id 'kql' -Total $kqlQueries.Count -Description "Querying the workspace ($($kqlQueries.Count) queries)"
                $kql = Invoke-AACLogQueryBatch -WorkspaceId $customerId -Query $kqlQueries -Timespan "P$($request.Days)D" -OnProgress {
                    param($Name, $Done, $Total)
                    Update-AACProgress -Id 'kql' -Increment 1 -Description "Querying the workspace ($Done of $Total queries)"
                }
                Update-AACProgress -Id 'kql' -Complete -Description "Queried the workspace: $($kqlQueries.Count) queries"
            }
        }

        $assessment = ConvertTo-AACSentinelAssessment -Workspace $workspace -Arm $arm -Kql $kql -NotOnboarded:$notOnboarded -Days $request.Days -IncludeEmptyTable:$request.IncludeEmptyTable
        $assessment['Section'] = $request.Section
        $result = [pscustomobject][ordered]@{
            PSTypeName      = 'AAC.SentinelAssessment'
            Name            = $assessment.Workspace.Name
            WorkspaceId     = $assessment.Workspace.WorkspaceId
            ResourceGroup   = $assessment.Workspace.ResourceGroup
            SentinelEnabled = $assessment.Workspace.SentinelEnabled
            Days            = $request.Days
            BillableGB      = $assessment.Stats.BillableGB
            HealthState     = $assessment.HealthState
            Recommendations = $assessment.Recommendations
            AnalyticsRules  = $assessment.AnalyticsRules
            TacticCoverage  = $assessment.TacticCoverage
            RuleTemplates   = $assessment.RuleTemplates
            Incidents       = $assessment.Incidents
            AutomationRules = $assessment.AutomationRules
            DataConnectors  = $assessment.DataConnectors
            Tables          = $assessment.Tables
            HealthFailures  = $assessment.HealthFailures
            Workspace       = $assessment.Workspace
            Errors          = $assessment.Errors
        }
        $detail = [ordered]@{ Workspace = "$($assessment.Workspace.Name) ($($assessment.Workspace.WorkspaceId))"; 'Resource group' = $assessment.Workspace.ResourceGroup; Period = "last $($request.Days) day(s)" }
        @{ Assessment = $assessment; Result = $result; Detail = $detail }
    }

    # The reports: CSV of the analytics rules, and the tabbed HTML report and PDF from one report model.
    if ($csvFullPath -or $htmlFullPath -or $pdfFullPath) {
        $report = ConvertTo-AACSentinelReport -Assessment $state.Assessment -Detail $state.Detail
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject @($state.Assessment.AnalyticsRules) -Noun 'analytics rule' -CsvPath $csvFullPath -HtmlPath $htmlFullPath -PdfPath $pdfFullPath
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACSentinelAssessmentView -Assessment $state.Assessment
        }
    }
    if ($returnObjects) {
        $state.Result
    }
}
