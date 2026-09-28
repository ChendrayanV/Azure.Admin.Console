function Invoke-AACApplicationInsightQuery {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Queries Application Insights - the exceptions of the last few hours by
        default, or any KQL query - from a Log Analytics workspace or an
        Application Insights resource, with a Spectre.Console view, flattened
        objects, and CSV and interactive HTML exports.
    .DESCRIPTION
        Finds the Log Analytics workspace (-LogWorkspaceName) or Application
        Insights resource (-ApplicationInsightsName) by name with Azure
        Resource Graph, then runs the query through the Log Analytics or
        Application Insights query API. Their tokens come from the
        Connect-AAC sign-in, with no second sign-in and no Az modules. Needs
        Log Analytics Reader (or Reader) on it.

        Without -Query it reads exceptions: the AppExceptions table of a
        workspace (workspace-based Application Insights) or the exceptions
        table of an Application Insights resource - newest first, from the
        last -Last (default 2 hours), narrowed by -MinimumSeverity,
        -ExceptionType (wildcards), -AppRoleName and -Search. A workspace
        only holds the exceptions of the Application Insights resources that
        send to it; when it has none, a warning names those resources, or -
        if none send there - the ones you can see and where each sends, with
        the -ApplicationInsightsName command to query one directly. Each row is
        flattened to one AAC.ApplicationInsightsException, the same for both
        tables:

          when and how bad    TimeGenerated (UTC), Severity, SeverityLevel
          what                ExceptionType, Message, OuterType, OuterMessage,
                              InnermostType, InnermostMessage
          details             DetailType, DetailMessage, DetailSeverityLevel
                              (the outermost entry of the details array),
                              DetailCount, StackTop (method, file and line)
          where               Method, Assembly, ProblemId, HandledAt,
                              OperationName, OperationId, AppRoleName,
                              AppRoleInstance, AppVersion, SdkVersion
          who                 ClientType, ClientCountryOrRegion, ClientCity
          plus                ItemCount (sampling), CustomProperties
                              ("key=value; ..."), Source, ResourceId

        With -TableName it reads another table the same way - requests,
        dependencies, traces, customEvents, pageViews, availabilityResults,
        ... - newest first from the last -Last, narrowed by -AppRoleName,
        -Search (any column) and -MinimumSeverity (traces), each row an
        object with the table's columns. Either schema's name works for
        either source: 'requests' on a workspace reads AppRequests, and
        'AppTraces' on an Application Insights resource reads traces. A
        workspace's other tables (e.g. ContainerLog) work too.

        With -Query it runs any KQL you give - against the workspace's
        tables (AppExceptions, AppRequests, AppTraces, ...) or the
        resource's (exceptions, requests, traces, ...) - bounded by -Last,
        and returns each row as an object with the query's columns.

        What you get depends on where the command runs:
          at the prompt    a Spectre.Console view: tiles, exceptions over
                           time, by severity, top exception types, top
                           problems and the latest exceptions (for -Query:
                           a table of the rows) - a page at a time
          piped onward     the objects, with no view
          -PassThru        the view and the objects
          -NoDisplay       the objects only
        -CsvPath and -HtmlPath (a self-contained, interactive report) export
        them; with either, the console shows only the progress and the files
        written.
    .PARAMETER LogWorkspaceName
        The Log Analytics workspace that workspace-based Application Insights
        sends its data to.
    .PARAMETER ApplicationInsightsName
        The Application Insights resource (its classic schema: exceptions,
        requests, traces, ...).
    .PARAMETER SubscriptionId
        The subscription the workspace or resource is in. Needed only when
        the name is used in more than one subscription.
    .PARAMETER ResourceGroupName
        The resource group the workspace or resource is in, when the name is
        used more than once.
    .PARAMETER Last
        How far back to look: minutes, hours or days, e.g. '30m', '2h' (the
        default) or '7d'.
    .PARAMETER TableName
        Read this table instead of the exceptions: requests, dependencies,
        traces, customEvents, pageViews, availabilityResults,
        performanceCounters, customMetrics, browserTimings - or their
        workspace names (AppRequests, AppTraces, ...), which work for either
        source. A workspace's other tables work too. Tab completes the
        names.
    .PARAMETER MinimumSeverity
        Only exceptions (or, with -TableName traces, traces) of at least this
        severity: Verbose, Information, Warning, Error or Critical.
    .PARAMETER ExceptionType
        Only these exception types; wildcards work, e.g. '*SqlException' or
        'System.Net.*'.
    .PARAMETER AppRoleName
        Only rows from these apps / cloud roles.
    .PARAMETER Search
        Only exceptions whose type or messages contain this text - or, with
        -TableName, rows with this text in any column.
    .PARAMETER Top
        At most this many rows, newest first. By default every row in the
        period is read (up to the query API's own limit of 500,000 rows) and
        the view pages through them all.
    .PARAMETER Query
        Run this KQL query instead of the exceptions query. -Last still
        bounds it.
    .PARAMETER CsvPath
        Also write the rows to this CSV file.
    .PARAMETER HtmlPath
        Also write an interactive HTML report to this file.
    .PARAMETER Title
        The HTML report's title.
    .PARAMETER PassThru
        Show the view and also return the objects.
    .PARAMETER NoDisplay
        Return the objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACApplicationInsightQuery -SubscriptionId '00000000-0000-0000-0000-000000000000' -LogWorkspaceName 'law-contoso-prod'
        The exceptions of the last 2 hours in that workspace.
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 1d -MinimumSeverity Error -AppRoleName 'orders-api'
        A day of errors and worse from one app.
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -ExceptionType '*SqlException' -Search 'timeout'
        SQL timeouts, from the Application Insights resource.
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 7d -HtmlPath .\out\Exceptions.html
        A week of exceptions as an interactive HTML report.
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -TableName requests -Last 1d -Search '/api/orders'
        A day of requests to the orders API.
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -TableName traces -MinimumSeverity Warning -AppRoleName 'orders-api'
        Warnings and worse that one app traced (the workspace's AppTraces).
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Query 'AppRequests | where Success == false | summarize Failed = count() by Name | top 10 by Failed'
        Any KQL query: the ten most failed requests.
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -NoDisplay | Group-Object ExceptionType | Sort-Object Count -Descending
        The exceptions as objects, grouped by type.
    .OUTPUTS
        AAC.ApplicationInsightsException, or the table's or query's rows
        with -TableName or -Query
        (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Workspace')]
    [OutputType('AAC.ApplicationInsightsException', [pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Workspace')]
        [Alias('WorkspaceName')]
        [ValidateNotNullOrEmpty()]
        [string] $LogWorkspaceName,

        [Parameter(Mandatory, ParameterSetName = 'Component')]
        [Alias('ComponentName')]
        [ValidateNotNullOrEmpty()]
        [string] $ApplicationInsightsName,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidatePattern('^\d{1,4}[mhd]$')]
        [string] $Last = '2h',

        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete)
                'requests', 'dependencies', 'exceptions', 'traces', 'customEvents', 'pageViews', 'availabilityResults', 'performanceCounters', 'customMetrics', 'browserTimings',
                'AppRequests', 'AppDependencies', 'AppExceptions', 'AppTraces', 'AppEvents', 'AppPageViews', 'AppAvailabilityResults', 'AppPerformanceCounters', 'AppMetrics', 'AppBrowserTimings' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            })]
        [string] $TableName,

        [ValidateSet('Verbose', 'Information', 'Warning', 'Error', 'Critical')]
        [string] $MinimumSeverity,

        [SupportsWildcards()]
        [string[]] $ExceptionType,

        [string[]] $AppRoleName,

        [string] $Search,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $Top,

        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $Title,

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module.
    trap { $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $filters = @('TableName', 'MinimumSeverity', 'ExceptionType', 'AppRoleName', 'Search', 'Top') | Where-Object { $PSBoundParameters.ContainsKey($_) }
    if ($Query -and $filters) {
        throw "-$($filters -join ', -') narrow the exceptions query; with -Query, write them into the query itself."
    }

    $kind = if ($PSCmdlet.ParameterSetName -eq 'Workspace') { 'Workspace' } else { 'Component' }
    $name = if ($kind -eq 'Workspace') { $LogWorkspaceName } else { $ApplicationInsightsName }

    # What runs: the exceptions (the default, or -TableName exceptions),
    # another table, or a query of your own.
    $table = Resolve-AACInsightsTable -Kind $kind -TableName $(if ($TableName) { $TableName } else { 'exceptions' })
    $mode = if ($Query) { 'Query' } elseif ($table.IsExceptions) { 'Exceptions' } else { 'Table' }
    if ($mode -eq 'Table') {
        if ($ExceptionType) {
            throw "-ExceptionType is for the exceptions; the $($table.Name) table has no exception type. Use -Search, or -Query."
        }
        if ($MinimumSeverity -and -not $table.HasSeverity) {
            throw "-MinimumSeverity is for exceptions and traces; the $($table.Name) table has no severity level. Use -Query to filter it."
        }
    }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $csvFullPath = if ($CsvPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath) }
    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) }

    # '2h' -> ago(2h) in KQL, PT2H for the API, and a TimeSpan for the view.
    $amount = [int]$Last.Substring(0, $Last.Length - 1)
    $unit = $Last.Substring($Last.Length - 1)
    $range = switch ($unit) { 'm' { [timespan]::FromMinutes($amount) } 'h' { [timespan]::FromHours($amount) } 'd' { [timespan]::FromDays($amount) } }
    $isoRange = switch ($unit) { 'm' { "PT${amount}M" } 'h' { "PT${amount}H" } 'd' { "P${amount}D" } }

    # --- The exceptions query, from the parameters -----------------------------------------------
    # Values go into KQL string literals, escaped; wildcards become an
    # anchored, case-insensitive regular expression.
    $kqlText = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $kqlRegex = {
        param([string[]] $Patterns)
        $alternatives = @($Patterns | ForEach-Object { [regex]::Escape($_) -replace '\\\*', '.*' -replace '\\\?', '.' })
        "@'(?i)^(" + (($alternatives -join '|') -replace "'", "''") + ")$'"
    }
    if ($mode -eq 'Table') {
        # Any table: the time filter, then filters that work on any columns.
        $role = if ($kind -eq 'Workspace') { 'AppRoleName' } else { 'cloud_RoleName' }
        $level = if ($kind -eq 'Workspace') { 'SeverityLevel' } else { 'severityLevel' }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add($table.Name)
        $lines.Add("| where $($table.Time) > ago($Last)")
        if ($MinimumSeverity) {
            $lines.Add("| where toint($level) >= $(@('Verbose', 'Information', 'Warning', 'Error', 'Critical').IndexOf($MinimumSeverity))")
        }
        if ($AppRoleName) { $lines.Add("| where tostring(column_ifexists('$role', '')) in~ ($((@($AppRoleName | ForEach-Object { & $kqlText $_ })) -join ', '))") }
        if ($Search) { $lines.Add("| where tostring(pack_all()) contains $(& $kqlText $Search)") }
        $lines.Add($(if ($Top) { "| top $Top by $($table.Time) desc" } else { "| order by $($table.Time) desc" }))
        $kql = $lines -join "`n"
    }
    elseif ($mode -eq 'Exceptions') {
        $col = if ($kind -eq 'Workspace') {
            @{ Table = 'AppExceptions'; Time = 'TimeGenerated'; Level = 'SeverityLevel'; Role = 'AppRoleName'
                Type = "tostring(column_ifexists('ExceptionType', column_ifexists('OuterType', '')))"
                Text = @("column_ifexists('Message', '')", "column_ifexists('OuterMessage', '')", "column_ifexists('InnermostMessage', '')", "column_ifexists('ExceptionType', '')") }
        }
        else {
            @{ Table = 'exceptions'; Time = 'timestamp'; Level = 'severityLevel'; Role = 'cloud_RoleName'
                Type = 'type'; Text = @('message', 'outerMessage', 'innermostMessage', 'type') }
        }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add($col.Table)
        $lines.Add("| where $($col.Time) > ago($Last)")
        if ($MinimumSeverity) {
            $lines.Add("| where toint($($col.Level)) >= $(@('Verbose', 'Information', 'Warning', 'Error', 'Critical').IndexOf($MinimumSeverity))")
        }
        if ($AppRoleName) { $lines.Add("| where $($col.Role) in~ ($((@($AppRoleName | ForEach-Object { & $kqlText $_ })) -join ', '))") }
        if ($ExceptionType) { $lines.Add("| where $($col.Type) matches regex $(& $kqlRegex $ExceptionType)") }
        if ($Search) { $lines.Add('| where ' + ((@($col.Text | ForEach-Object { "tostring($_) contains $(& $kqlText $Search)" })) -join ' or ')) }
        $lines.Add($(if ($Top) { "| top $Top by $($col.Time) desc" } else { "| order by $($col.Time) desc" }))
        $kql = $lines -join "`n"
    }
    else {
        $kql = $Query
    }

    # --- Find the source, run the query ------------------------------------------------------------
    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Application Insights' -Color 'deepskyblue3_1'
    }
    $run = Invoke-AACProgress -ScriptBlock {
        $noun = if ($kind -eq 'Workspace') { 'Log Analytics workspace' } else { 'Application Insights resource' }
        Update-AACProgress -Id 'find' -Description "Finding the $noun '$name' in Azure Resource Graph" -Indeterminate
        $source = Resolve-AACLogResource -Kind $kind -Name $name -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
        Update-AACProgress -Id 'find' -Complete -Description "Found $($source.Name) in $($source.ResourceGroup) ($($source.Location))"

        $what = switch ($mode) { 'Query' { 'query' } 'Exceptions' { 'exceptions query' } default { "$($table.Name) query" } }
        Update-AACProgress -Id 'query' -Description "Running the $what over the last $Last" -Indeterminate
        try {
            $rows = @(Invoke-AACLogQuery -Kind $kind -Id $source.QueryId -Query $kql -Timespan $isoRange)
        }
        catch {
            # A table the source doesn't have: say so, and which it does have.
            $failure = $_.Exception
            if (-not ($failure.Data.Contains('StatusCode') -and $failure.Data['StatusCode'] -eq 400 -and $failure.Message -match 'resolve table')) { throw }
            $missing = if ($failure.Message -match "named '([^']+)'") { $Matches[1] } else { $table.Name }
            Update-AACProgress -Id 'query' -Description "Looking up the tables $($source.Name) has"
            $problem = [System.Exception]::new("There is no table '$missing' in $($source.Name).", $failure)
            $problem.Data['AACHint'] = Get-AACTableSuggestion -Kind $kind -Id $source.QueryId -TableName $missing -SourceName $source.Name -Last $Last
            $problem.Data['AACStep'] = "Running the $what over the last $Last"
            throw $problem
        }
        # @() around the whole if: an if statement unrolls what it returns,
        # so @() inside it would still leave no rows as no array at all.
        $objects = @(if ($mode -eq 'Exceptions') {
                foreach ($row in $rows) { ConvertTo-AACExceptionRecord -Row $row -Source $source.Name }
            }
            else {
                foreach ($row in $rows) { [pscustomobject]$row }
            })
        $noun = switch ($mode) { 'Query' { 'row' } 'Exceptions' { 'exception' } default { "$($table.Name) row" } }
        Update-AACProgress -Id 'query' -Complete -Description ('Read {0:N0} {1}(s) from {2} over the last {3}' -f $objects.Count, $noun, $source.Name, $Last)

        # Nothing in a workspace's Application Insights table: often because
        # no Application Insights resource sends to it (the portal's
        # 'exceptions' of a resource that sends elsewhere). Say which do, so
        # the empty result is explained.
        $components = $null
        if ($mode -ne 'Query' -and $table.IsKnown -and $kind -eq 'Workspace' -and $objects.Count -eq 0) {
            Update-AACProgress -Id 'why' -Description "Finding the Application Insights resources that send to $($source.Name)" -Indeterminate
            $components = @(Get-AACWorkspaceComponent)
            Update-AACProgress -Id 'why' -Complete -Description "Found $($components.Count) Application Insights resource(s)"
        }
        @{ Source = $source; Objects = $objects; Components = $components }
    }
    $objects = @($run.Objects)
    if ($null -ne $run.Components) {
        $components = @($run.Components)
        $linked = @($components | Where-Object { $_.WorkspaceId -eq $run.Source.Id })
        $others = @($components | Where-Object { $_.WorkspaceId -ne $run.Source.Id })
        $where = { param($Component) if ($Component.WorkspaceId) { "sends to $(($Component.WorkspaceId -split '/')[-1])" } else { 'classic, keeps its own data' } }
        $what = if ($mode -eq 'Exceptions') { 'exceptions' } else { "$($table.Name) rows" }
        $tableArgument = if ($TableName) { " -TableName $TableName" } else { '' }
        $message = if ($linked.Count) {
            "No $what in $($run.Source.Name) over the last ${Last}. The Application Insights resource(s) that send to it - $(($linked.Name) -join ', ') - recorded none in that time, or your account can't read the workspace's $($table.Name) table."
        }
        elseif ($others.Count) {
            $list = ($others | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($(& $where $_))" }) -join ', '
            "No Application Insights resource sends to $($run.Source.Name), so its $($table.Name) table is empty. Application Insights resources you can see: $list$(if ($others.Count -gt 5) { ", and $($others.Count - 5) more" }). Query one directly: Invoke-AACApplicationInsightQuery -ApplicationInsightsName '$($others[0].Name)'$tableArgument -Last $Last"
        }
        else {
            "No $what in $($run.Source.Name) over the last ${Last}, and no Application Insights resource is visible to your account."
        }
        Write-Warning $message
    }

    $scope = [ordered]@{
        Source = "$($run.Source.Name) ($(if ($kind -eq 'Workspace') { 'Log Analytics workspace' } else { 'Application Insights' }), $($run.Source.ResourceGroup))"
        Range  = "last $Last"
    }
    if ($Query) { $scope['Query'] = ($Query -replace '\s+', ' ').Trim() }
    else {
        if ($mode -eq 'Table') { $scope['Table'] = $table.Name }
        if ($MinimumSeverity) { $scope['Severity'] = "$MinimumSeverity or worse" }
        if ($ExceptionType) { $scope['Types'] = $ExceptionType -join ', ' }
        if ($AppRoleName) { $scope['Apps'] = $AppRoleName -join ', ' }
        if ($Search) { $scope['Search'] = $Search }
    }

    $reportTitle = if ($Title) { $Title } else {
        switch ($mode) { 'Query' { "Query: $($run.Source.Name)" } 'Exceptions' { "Exceptions: $($run.Source.Name)" } default { "$($table.Name): $($run.Source.Name)" } }
    }
    $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $objects -Noun $(if ($mode -eq 'Exceptions') { 'exception' } else { 'row' }) -HtmlPath $htmlFullPath -WriteHtml {
        if ($mode -eq 'Exceptions') { Write-AACExceptionHtml -Exception $objects -Path $htmlFullPath -Title $reportTitle -Detail $scope }
        else { Write-AACQueryResultHtml -Row $objects -Path $htmlFullPath -Title $reportTitle -Detail $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            switch ($mode) {
                'Exceptions' { Show-AACExceptionView -Exception $objects -Scope $scope -Range $range }
                'Table' { Show-AACQueryResultView -Row $objects -Scope $scope -PreferredColumn $table.Columns -Title $table.Name }
                default { Show-AACQueryResultView -Row $objects -Scope $scope }
            }
            [Spectre.Console.AnsiConsole]::WriteLine()
            Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath or -HtmlPath for a report; -TableName for another table (requests, traces, ...); -Query for any KQL.[/]'
        }
    }

    if ($returnObjects) {
        $objects
    }
}
