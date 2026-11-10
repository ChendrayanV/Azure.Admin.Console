function Read-AACApplicationInsightIngestion {
    <#
    .SYNOPSIS
        Reads what workspace-based Application Insights components ingested
        - billed GB by table and by day, sampling, trace severity and health
        probe requests - from the workspaces they write to.
    .DESCRIPTION
        Four queries per workspace (Invoke-AACLogQueryBatch), over the App*
        tables, by _ResourceId (the component):
          tables    billed GB, rows and ItemCount by table - ItemCount above
                    the rows means the SDK sampled
          daily     billed GB by day, for the average, peak and spikes
          traces    AppTraces billed GB by SeverityLevel (0 Verbose,
                    1 Information, 2 Warning, 3 Error, 4 Critical)
          requests  AppRequests rows, and how many look like health probes
                    (health, healthz, ready, live, ping, alive in the name)
        _BilledSize is what is billed, so it matches the invoice better than
        the Usage table (which can't be split by component).

        -Workspace: @{ workspace query ID (customerId) = @(component IDs) }.
        Returns @{ Rows = @{ tables; daily; traces; requests = rows[] };
        Errors = @{ customerId = reason } }. Needs Log Analytics Reader on
        the workspaces (or Reader on the components, with resource-context
        access).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Workspace,

        [Parameter(Mandatory)]
        [string] $Duration
    )

    $rows = @{ tables = [System.Collections.Generic.List[object]]::new(); daily = [System.Collections.Generic.List[object]]::new(); traces = [System.Collections.Generic.List[object]]::new(); requests = [System.Collections.Generic.List[object]]::new() }
    $errors = @{}
    foreach ($customerId in @($Workspace.Keys)) {
        $ids = (@($Workspace[$customerId] | ForEach-Object { ConvertTo-AACKqlLiteral -Text ([string]$_).ToLowerInvariant() }) -join ', ')
        $queries = [ordered]@{
            tables   = "union isfuzzy=true withsource=Table App* | where tolower(_ResourceId) in ($ids) | summarize GB = sum(_BilledSize) / 1e9, Rows = count(), Items = sum(todouble(coalesce(column_ifexists('ItemCount', int(null)), 1))) by ResourceId = tolower(_ResourceId), Table"
            daily    = "union isfuzzy=true App* | where tolower(_ResourceId) in ($ids) | summarize GB = sum(_BilledSize) / 1e9 by ResourceId = tolower(_ResourceId), Day = startofday(TimeGenerated)"
            traces   = "AppTraces | where tolower(_ResourceId) in ($ids) | summarize GB = sum(_BilledSize) / 1e9 by ResourceId = tolower(_ResourceId), SeverityLevel = toint(SeverityLevel)"
            requests = "AppRequests | where tolower(_ResourceId) in ($ids) | summarize Rows = count(), Health = countif(Name matches regex @'(?i)(health|healthz|ready|readiness|live|liveness|ping|alive)') by ResourceId = tolower(_ResourceId)"
        }
        $answer = Invoke-AACLogQueryBatch -WorkspaceId $customerId -Query $queries -Timespan $Duration
        # The tables query is the one that matters; the others only add detail.
        if ($answer.Errors.Contains('tables')) { $errors[$customerId] = [string]$answer.Errors['tables']; continue }
        foreach ($name in @($queries.Keys)) { foreach ($r in @($answer.Rows[$name])) { if ($null -ne $r) { $rows[$name].Add($r) } } }
    }
    @{ Rows = @{ tables = $rows.tables.ToArray(); daily = $rows.daily.ToArray(); traces = $rows.traces.ToArray(); requests = $rows.requests.ToArray() }; Errors = $errors }
}
