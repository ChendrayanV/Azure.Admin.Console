function Test-AACSentinelRuleQuery {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Replays Microsoft Sentinel analytics rule queries - or a query you are
        writing - over their last run windows, to see how many results each
        run returns, whether it would alert and how often, and whether the
        columns the rule maps exist, before enabling or changing a rule.
    .DESCRIPTION
        For each scheduled or NRT rule, runs its KQL in the workspace over the
        last -Runs windows as Sentinel would schedule them: each window ends
        one query frequency before the next and looks back the query period.
        Read-only: the rule isn't changed and no alert is raised.

        Each rule (AAC.SentinelRuleQueryTest): Name, Status (Error, Warning,
        Alerting or Quiet), Kind, Enabled, Frequency, Period, Trigger,
        Grouping, Runs, RunsAlerting, LatestResults, AverageResults,
        MaxResults, EstimatedAlerts (over the runs tested), Findings,
        MissingColumns, Columns, Error, Note, RuleId, Sample (up to 5 rows of
        the latest window), RunDetail (each window: start, end, results,
        whether it would alert) and Query.

        Findings: the query fails; columns the rule maps for entities, custom
        details or alert overrides aren't in its results; a look-back over 14
        days; a frequency longer than the look-back; alerting in every run
        tested; reaching 150 alerts in a run; over 10,000 characters;
        searching every table.

        A query that calls ago() or now() counts from when it runs, so only
        its latest window is tested. NRT rules are tested in 1-hour windows.
        Each window is a query against the workspace and its cost: test a few
        rules at a time.

        Rules come from -Name, from the pipeline (Get-AACSentinelAnalyticsRule
        output), or, with neither, every enabled scheduled and NRT rule.
        -Query tests a query that isn't a rule yet.

        Needs Microsoft Sentinel Reader and Log Analytics Reader on the
        workspace.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Name
        The rules to test, by display name or rule ID; wildcards work.
    .PARAMETER RuleId
        The rules to test, by rule ID. Takes RuleId from the pipeline, so
        Get-AACSentinelAnalyticsRule's output can be piped in.
    .PARAMETER Query
        A KQL query to test instead of a rule.
    .PARAMETER Frequency
        With -Query: how often it would run, as an ISO 8601 duration (PT1H by
        default).
    .PARAMETER Period
        With -Query: how far back each run would look (PT1H by default).
    .PARAMETER TriggerOperator
        With -Query: GreaterThan (the default), LessThan, Equal or NotEqual.
    .PARAMETER TriggerThreshold
        With -Query: the result count the operator compares with (0 by
        default).
    .PARAMETER Runs
        How many of the latest run windows to replay: 1 to 48, 6 by default.
    .PARAMETER CsvPath
        Write the results to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the results.
    .PARAMETER NoDisplay
        Return the results without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Name 'Rare admin sign-in'
        One rule's last 6 runs replayed: results, alerts and findings.
    .EXAMPLE
        Get-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -State Disabled -Kind Scheduled -NoDisplay | Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Runs 24
        What the disabled scheduled rules would have done over their last 24 runs.
    .EXAMPLE
        Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Query 'SigninLogs | where ResultType == "50126"' -Frequency PT5M -Period PT1H -TriggerThreshold 10 -Runs 12
        A query you are writing, as a rule that runs every 5 minutes.
    .EXAMPLE
        (Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Name 'Brute force*' -NoDisplay).RunDetail
        Each replayed window of a rule: when, how many results, alert or not.
    .OUTPUTS
        AAC.SentinelRuleQueryTest (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Rule')]
    [OutputType('AAC.SentinelRuleQueryTest')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [Parameter(ParameterSetName = 'Rule')]
        [SupportsWildcards()]
        [string[]] $Name,

        [Parameter(ParameterSetName = 'Rule', ValueFromPipelineByPropertyName)]
        [string[]] $RuleId,

        [Parameter(Mandatory, ParameterSetName = 'Query')]
        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [Parameter(ParameterSetName = 'Query')]
        [ValidatePattern('^P')]
        [string] $Frequency = 'PT1H',

        [Parameter(ParameterSetName = 'Query')]
        [ValidatePattern('^P')]
        [string] $Period = 'PT1H',

        [Parameter(ParameterSetName = 'Query')]
        [ValidateSet('GreaterThan', 'LessThan', 'Equal', 'NotEqual')]
        [string] $TriggerOperator = 'GreaterThan',

        [Parameter(ParameterSetName = 'Query')]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $TriggerThreshold = 0,

        [ValidateRange(1, 48)]
        [int] $Runs = 6,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel rule query test',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $wantedIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($id in @($RuleId | Where-Object { $_ })) { $wantedIds.Add((($id.TrimEnd('/') -split '/')[-1]).ToLowerInvariant()) }
    }

    end {
        # A failure anywhere below ends as a Spectre.Console error panel and this
        # command's own terminating error, not a line inside the module. A stopped
        # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
        # rethrow would stop the caller's whole script, not only this command.
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
        # Each window is a query: past this, the test is a load test of the workspace.
        $maxQueries = 400
        $adHoc = $PSCmdlet.ParameterSetName -eq 'Query'
        $arm = [ordered]@{}
        if (-not $adHoc) { $arm['alertRules'] = 'providers/Microsoft.SecurityInsights/alertRules?api-version=2025-09-01' }
        # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
        $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Arm = $arm }

        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Test Microsoft Sentinel rule queries' -Color 'deepskyblue3_1' }
        $read = Invoke-AACProgress -ScriptBlock {
            $null = Get-AACAccessToken
            Update-AACProgress -Id 'read' -Indeterminate -Description "Reading $($request.Target)"
            $workspace = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm $request.Arm
            Update-AACProgress -Id 'read' -Complete -Description "Workspace $($workspace.Name)"
            $workspace
        }

        # --- Which rules ------------------------------------------------------------------------------------------
        $rules = if ($adHoc) {
            , @(@{ name = 'ad-hoc'; kind = 'Scheduled'; properties = @{ displayName = 'Ad hoc query'; enabled = $true; query = $Query; queryFrequency = $Frequency; queryPeriod = $Period; triggerOperator = $TriggerOperator; triggerThreshold = $TriggerThreshold } })
        }
        else {
            if ($read.Arm['alertRules'].Error) {
                $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the analytics rules of $($read.Name): $($read.Arm['alertRules'].Error)")
                $problem.Data['AACHint'] = 'Your account needs Microsoft Sentinel Reader on the workspace. -Query tests a query without reading the rules.'
                throw $problem
            }
            $testable = @($read.Arm['alertRules'].Items | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_['kind'] -in 'Scheduled', 'NRT' })
            $label = { param($Rule) @([string]$Rule['name'], $(if ($Rule['properties'] -is [System.Collections.IDictionary]) { [string]$Rule['properties']['displayName'] })) }
            $chosen = if ($wantedIds.Count -or $Name) {
                @($testable | Where-Object {
                        $r = $_
                        ($wantedIds -contains ([string]$r['name']).ToLowerInvariant()) -or @($Name | Where-Object { $p = $_; @(& $label $r | Where-Object { $_ -and $_ -like $p }).Count }).Count
                    })
            }
            else { @($testable | Where-Object { $_['properties'] -is [System.Collections.IDictionary] -and $_['properties']['enabled'] }) }
            if (-not @($chosen).Count) {
                throw [System.ArgumentException]::new("Azure Admin Console found no scheduled or NRT rule to test on $($read.Name)$(if ($Name -or $wantedIds.Count) { ' that matches' }). Get-AACSentinelAnalyticsRule -Kind Scheduled, NRT lists them; other kinds have no query of their own.")
            }
            , @($chosen)
        }
        $plan = Get-AACSentinelRuleTestQuery -Rule $rules -Runs $Runs
        if ($plan.Queries.Count -gt $maxQueries) {
            throw [System.ArgumentException]::new("Azure Admin Console would run $($plan.Queries.Count) queries to test $(@($plan.Specs).Count) rules over $Runs window(s), more than the $maxQueries it allows at once. Narrow it with -Name, or lower -Runs.")
        }

        # --- Run the windows --------------------------------------------------------------------------------------
        $kqlRequest = @{ WorkspaceId = $read.WorkspaceId; Queries = $plan.Queries; Count = $plan.Queries.Count; Rules = @($plan.Specs).Count }
        $kql = Invoke-AACProgress -ScriptBlock {
            Update-AACProgress -Id 'kql' -Total $kqlRequest.Count -Description "Replaying $($kqlRequest.Rules) rule(s): $($kqlRequest.Count) queries"
            $result = Invoke-AACLogQueryBatch -WorkspaceId $kqlRequest.WorkspaceId -Query $kqlRequest.Queries -OnProgress {
                param($QueryName, $Done, $Total)
                Update-AACProgress -Id 'kql' -Increment 1 -Description "Replaying the rules ($Done of $Total queries)"
            }
            Update-AACProgress -Id 'kql' -Complete -Description "Replayed $($kqlRequest.Rules) rule(s)"
            $result
        }
        $tests = @(ConvertTo-AACSentinelRuleQueryTest -Spec @($plan.Specs) -Kql $kql)

        # --- The report -------------------------------------------------------------------------------------------
        $statusTones = @{ Error = 'bad'; Warning = 'warn'; Alerting = 'violet'; Quiet = 'good' }
        $failing = @($tests | Where-Object Status -EQ 'Error').Count
        $warned = @($tests | Where-Object Status -EQ 'Warning').Count
        $alertingNow = @($tests | Where-Object { @($_.RunDetail | Select-AACFirst 1 | Where-Object WouldAlert).Count }).Count
        $estimated = [int](@($tests | ForEach-Object { $_.EstimatedAlerts } | Measure-Object -Sum).Sum)
        $runRows = @($tests | ForEach-Object { $_.RunDetail })
        $headline = "$($tests.Count) rule(s) replayed over up to $Runs window(s): $failing failing, $warned with findings, $alertingNow would alert now; about $estimated alert(s) in the windows tested"
        $report = @{
            Subtitle = 'Microsoft Sentinel rule queries replayed over their last run windows'
            Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Windows = "up to $Runs per rule" }
            Status   = $(if ($failing) { 'Failed' } elseif ($warned) { 'Warning' } else { 'Success' })
            Headline = $headline
            Tiles    = @(
                @{ Value = '{0:N0}' -f $tests.Count; Label = 'rules tested'; Tone = 'info'; Table = 'tests' }
                @{ Value = '{0:N0}' -f $failing; Label = 'queries failing'; Tone = $(if ($failing) { 'bad' } else { 'good' }); Table = 'tests'; Filters = @{ Status = 'Error' } }
                @{ Value = '{0:N0}' -f $warned; Label = 'with findings'; Tone = $(if ($warned) { 'warn' } else { 'good' }); Table = 'tests'; Filters = @{ Status = 'Warning' } }
                @{ Value = '{0:N0}' -f $alertingNow; Label = 'would alert now'; Tone = 'violet' }
                @{ Value = '{0:N0}' -f $estimated; Label = 'estimated alerts'; Tone = 'neutral' }
            )
            Charts   = @(
                @{ Title = 'Estimated alerts in the windows tested'; Items = @($tests | Where-Object EstimatedAlerts -GT 0 | Sort-Object EstimatedAlerts -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.EstimatedAlerts; Filter = $_.Name } }); Table = 'tests'; Column = 'Name'; Tone = 'violet'; Console = $true }
            )
            Tables   = @(
                @{ Id = 'tests'; Title = 'Rules tested'; Section = 'Rules'; Rows = $tests; Noun = 'rules'; File = 'sentinel-rule-query-test'; GroupBy = @('Status', 'Kind'); ConsoleLimit = 30
                    Hover = @('Findings', 'Note', 'Error'); HoverTitle = 'Name'
                    Columns = @(
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Name'; Label = 'Rule'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Trigger'; Label = 'Trigger'; Type = 'mono'; Console = $true }
                        @{ Key = 'Runs'; Label = 'Runs'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'RunsAlerting'; Label = 'Alerting'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'LatestResults'; Label = 'Latest results'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'MaxResults'; Label = 'Max results'; Type = 'number' }
                        @{ Key = 'EstimatedAlerts'; Label = 'Alerts'; Type = 'number'; Console = $true }
                        @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Frequency'; Label = 'Every'; Type = 'mono' }
                        @{ Key = 'Period'; Label = 'Looks back'; Type = 'mono' }
                        @{ Key = 'Grouping'; Label = 'Grouping'; Facet = $true }
                        @{ Key = 'MissingColumns'; Label = 'Missing columns'; Type = 'mono' }
                        @{ Key = 'Note'; Label = 'Note'; Type = 'wide'; Hidden = $true }
                        @{ Key = 'Query'; Label = 'KQL'; Type = 'wide'; Hidden = $true }
                    ) }
                @{ Id = 'runs'; Title = 'Replayed windows'; Section = 'Windows'; Rows = $runRows; Noun = 'windows'; File = 'sentinel-rule-query-windows'; GroupBy = @('Rule'); NoConsole = $true
                    Columns = @(
                        @{ Key = 'Rule'; Label = 'Rule'; Type = 'wide'; Facet = $true; Pdf = $true }
                        @{ Key = 'WindowStart'; Label = 'From'; Type = 'datetime'; Pdf = $true }
                        @{ Key = 'WindowEnd'; Label = 'To'; Type = 'datetime'; Pdf = $true }
                        @{ Key = 'Results'; Label = 'Results'; Type = 'number'; Pdf = $true }
                        @{ Key = 'WouldAlert'; Label = 'Would alert'; Facet = $true; Pdf = $true }
                        @{ Key = 'Alerts'; Label = 'Alerts'; Type = 'number' }
                        @{ Key = 'Error'; Label = 'Error'; Type = 'wide' }
                    ) }
            )
            Hint     = '-Runs replays more windows; .RunDetail has each window and .Sample the latest results; -Query tests a query before it is a rule.'
        }
        $csvRows = @($tests | Select-Object -Property * -ExcludeProperty Sample, RunDetail)
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $csvRows -Noun 'rule' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $tests -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
