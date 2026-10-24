function Invoke-AACLogQueryBatch {
    <#
    .SYNOPSIS
        Runs several KQL queries against one Log Analytics workspace at once
        and returns each one's rows - or why it failed - by name.
    .DESCRIPTION
        Each query is its own POST to the Log Analytics query API
        (https://api.loganalytics.azure.com/v1/workspaces/{workspace ID}/query,
        as Invoke-AACLogQuery sends one), up to 5 in flight - the API runs at
        most 5 queries at a time per user - through Invoke-AACHttpBatch:
        throttling and server errors are retried, and one query failing
        (a table the workspace doesn't have, a timeout) doesn't stop the
        others. The query API's own $batch endpoint is deprecated, so it
        isn't used.

        -Query maps a name to a KQL query, or to @{ Query; Timespan } to
        bound one query by another ISO 8601 duration than -Timespan.
        Rows are ordered hashtables, one per row of the first result table.
        Returns @{ Rows = @{ name = rows[] }; Errors = @{ name = reason } }.
        -OnProgress is called with (name, done, total) as each finishes.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Query,

        [string] $Timespan,

        [scriptblock] $OnProgress,

        [ValidateRange(1, 5)]
        [int] $ThrottleLimit = 5
    )

    # Named so that nothing in Invoke-AACHttpBatch - where the callbacks
    # below run - hides them ($errors, $done and $total are its own).
    $logRows = @{}
    $logErrors = @{}
    $requests = foreach ($name in @($Query.Keys)) {
        $item = $Query[$name]
        $text = if ($item -is [System.Collections.IDictionary]) { [string]$item['Query'] } else { [string]$item }
        $span = if ($item -is [System.Collections.IDictionary] -and $item['Timespan']) { [string]$item['Timespan'] } else { $Timespan }
        $body = @{ query = $text }
        if ($span) { $body.timespan = $span }
        $logRows[$name] = @()
        @{ Key = $name; Uri = "https://api.loganalytics.azure.com/v1/workspaces/$WorkspaceId/query"; Body = (ConvertTo-Json -InputObject $body -Compress -Depth 5) }
    }
    if (-not @($requests).Count) { return @{ Rows = $logRows; Errors = $logErrors } }

    $onResponse = {
        param($Name, [string] $Content)
        $response = ConvertFrom-Json -InputObject $Content -AsHashtable -Depth 100
        $table = if ($response -is [System.Collections.IDictionary]) { @($response['tables'])[0] }
        if ($table -isnot [System.Collections.IDictionary]) {
            $logErrors[$Name] = 'The query API returned no result table.'
            return
        }
        $columns = @($table['columns'] | ForEach-Object { [string]$_['name'] })
        $logRows[$Name] = @(foreach ($row in @($table['rows'])) {
                $record = [ordered]@{}
                for ($i = 0; $i -lt $columns.Count; $i++) { $record[$columns[$i]] = $row[$i] }
                $record
            })
    }
    # Invoke-AACHttpBatch counts the finished requests itself and passes the
    # count in: this block runs inside it, where a counter of our own named
    # like one of its variables would be hidden by it.
    $onDone = {
        param($Name, [string] $Failure, [int] $Finished, [int] $Of)
        if ($OnProgress) { & $OnProgress $Name $Finished $Of }
    }
    $failures = Invoke-AACHttpBatch -Request @($requests) -OnResponse $onResponse -OnDone $onDone -ThrottleLimit $ThrottleLimit -Resource 'https://api.loganalytics.io'
    foreach ($name in @($failures.Keys)) {
        if ($failures[$name]) { $logErrors[$name] = $failures[$name]; $logRows[$name] = @() }
    }
    @{ Rows = $logRows; Errors = $logErrors }
}
