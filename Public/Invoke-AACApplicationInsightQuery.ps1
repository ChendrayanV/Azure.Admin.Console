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
        Resource Graph, then runs the query through Azure Resource Manager
        with the Connect-AAC sign-in - no Az modules and no separate Log
        Analytics token. Needs Log Analytics Reader (or Reader) on it.

        Without -Query it reads exceptions: the AppExceptions table of a
        workspace (workspace-based Application Insights) or the exceptions
        table of an Application Insights resource - newest first, from the
        last -Last (default 2 hours), narrowed by -MinimumSeverity,
        -ExceptionType (wildcards), -AppRoleName and -Search. Each row is
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
    .PARAMETER MinimumSeverity
        Only exceptions of at least this severity: Verbose, Information,
        Warning, Error or Critical.
    .PARAMETER ExceptionType
        Only these exception types; wildcards work, e.g. '*SqlException' or
        'System.Net.*'.
    .PARAMETER AppRoleName
        Only exceptions from these apps / cloud roles.
    .PARAMETER Search
        Only exceptions whose type or messages contain this text.
    .PARAMETER Top
        At most this many exceptions, newest first (default 1000).
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
        Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Query 'AppRequests | where Success == false | summarize Failed = count() by Name | top 10 by Failed'
        Any KQL query: the ten most failed requests.
    .EXAMPLE
        Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -NoDisplay | Group-Object ExceptionType | Sort-Object Count -Descending
        The exceptions as objects, grouped by type.
    .OUTPUTS
        AAC.ApplicationInsightsException, or the query's rows with -Query
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

        [ValidateSet('Verbose', 'Information', 'Warning', 'Error', 'Critical')]
        [string] $MinimumSeverity,

        [SupportsWildcards()]
        [string[]] $ExceptionType,

        [string[]] $AppRoleName,

        [string] $Search,

        [ValidateRange(1, 30000)]
        [int] $Top = 1000,

        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $Title,

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    $filters = @('MinimumSeverity', 'ExceptionType', 'AppRoleName', 'Search', 'Top') | Where-Object { $PSBoundParameters.ContainsKey($_) }
    if ($Query -and $filters) {
        throw "-$($filters -join ', -') narrow the exceptions query; with -Query, write them into the query itself."
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

    $kind = if ($PSCmdlet.ParameterSetName -eq 'Workspace') { 'Workspace' } else { 'Component' }
    $name = if ($kind -eq 'Workspace') { $LogWorkspaceName } else { $ApplicationInsightsName }

    # --- The exceptions query, from the parameters -----------------------------------------------
    # Values go into KQL string literals, escaped; wildcards become an
    # anchored, case-insensitive regular expression.
    $kqlText = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $kqlRegex = {
        param([string[]] $Patterns)
        $alternatives = @($Patterns | ForEach-Object { [regex]::Escape($_) -replace '\\\*', '.*' -replace '\\\?', '.' })
        "@'(?i)^(" + (($alternatives -join '|') -replace "'", "''") + ")$'"
    }
    if (-not $Query) {
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
        $lines.Add("| top $Top by $($col.Time) desc")
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

        Update-AACProgress -Id 'query' -Description "Running the $(if ($Query) { 'query' } else { 'exceptions query' }) over the last $Last" -Indeterminate
        $rows = @(Invoke-AACLogQuery -ResourceId $source.Id -Kind $kind -Query $kql -Timespan $isoRange)
        $objects = if ($Query) {
            @(foreach ($row in $rows) { [pscustomobject]$row })
        }
        else {
            @(foreach ($row in $rows) { ConvertTo-AACExceptionRecord -Row $row -Source $source.Name })
        }
        $noun = if ($Query) { 'row' } else { 'exception' }
        Update-AACProgress -Id 'query' -Complete -Description ('Read {0:N0} {1}(s) from {2} over the last {3}' -f $objects.Count, $noun, $source.Name, $Last)
        @{ Source = $source; Objects = $objects }
    }
    $objects = @($run.Objects)

    $scope = [ordered]@{
        Source = "$($run.Source.Name) ($(if ($kind -eq 'Workspace') { 'Log Analytics workspace' } else { 'Application Insights' }), $($run.Source.ResourceGroup))"
        Range  = "last $Last"
    }
    if ($Query) { $scope['Query'] = ($Query -replace '\s+', ' ').Trim() }
    else {
        if ($MinimumSeverity) { $scope['Severity'] = "$MinimumSeverity or worse" }
        if ($ExceptionType) { $scope['Types'] = $ExceptionType -join ', ' }
        if ($AppRoleName) { $scope['Apps'] = $AppRoleName -join ', ' }
        if ($Search) { $scope['Search'] = $Search }
    }

    $reportTitle = if ($Title) { $Title } elseif ($Query) { "Query: $($run.Source.Name)" } else { "Exceptions: $($run.Source.Name)" }
    $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $objects -Noun $(if ($Query) { 'row' } else { 'exception' }) -HtmlPath $htmlFullPath -WriteHtml {
        if ($Query) { Write-AACQueryResultHtml -Row $objects -Path $htmlFullPath -Title $reportTitle -Detail $scope }
        else { Write-AACExceptionHtml -Exception $objects -Path $htmlFullPath -Title $reportTitle -Detail $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            if ($Query) { Show-AACQueryResultView -Row $objects -Scope $scope }
            else { Show-AACExceptionView -Exception $objects -Scope $scope -Range $range }
            [Spectre.Console.AnsiConsole]::WriteLine()
            Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath or -HtmlPath for a report; -Query for any KQL.[/]'
        }
    }

    if ($returnObjects) {
        $objects
    }
}
