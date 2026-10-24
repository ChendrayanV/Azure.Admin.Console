function Get-AACTableSuggestion {
    <#
    .SYNOPSIS
        Says which tables a workspace or Application Insights resource does
        have, for the error when a query names one it doesn't - closest
        names first, with how many rows each has in the period.
    .DESCRIPTION
        Reads the table names from the query API's metadata:

          Workspace   GET https://api.loganalytics.azure.com/v1/workspaces/{workspace ID}/metadata
          Component   GET https://api.applicationinsights.io/v1/apps/{app ID}/metadata

        then counts the rows of the tables worth naming (an Application
        Insights resource's tables; a workspace's Application Insights
        tables and those with a similar name) over -Last, in one query.
        Returns one line, e.g.

          Did you mean 'requests'? Tables in appi-prod with data in the last
          15d: requests (1,204), traces (873). No data: customEvents, ...

        If the metadata can't be read, returns the Application Insights
        table names instead; this helper never throws.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Workspace', 'Component')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $Id,

        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        [string] $SourceName,

        [Parameter(Mandatory)]
        [string] $Last
    )

    $api = @{
        Workspace = @{ Uri = "https://api.loganalytics.azure.com/v1/workspaces/$Id/metadata"; Resource = 'https://api.loganalytics.io' }
        Component = @{ Uri = "https://api.applicationinsights.io/v1/apps/$Id/metadata"; Resource = 'https://api.applicationinsights.io' }
    }[$Kind]
    $fallback = if ($Kind -eq 'Workspace') {
        'AppRequests', 'AppDependencies', 'AppExceptions', 'AppTraces', 'AppEvents', 'AppPageViews', 'AppAvailabilityResults', 'AppPerformanceCounters', 'AppMetrics', 'AppBrowserTimings'
    }
    else {
        'requests', 'dependencies', 'exceptions', 'traces', 'customEvents', 'pageViews', 'availabilityResults', 'performanceCounters', 'customMetrics', 'browserTimings'
    }

    # Every table the source has, with its time column.
    $tables = @()
    try {
        $metadata = Invoke-AACArmRequest -Uri $api.Uri -Resource $api.Resource
        $tables = @(@($metadata['tables']) | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['name'] } | ForEach-Object {
                [pscustomobject]@{ Name = [string]$_['name']; Time = $(if ($_['timespanColumn']) { [string]$_['timespanColumn'] } else { '' }) }
            } | Sort-Object -Property Name -Unique)
    }
    catch {
        Write-Debug "The table list couldn't be read: $($_.Exception.Message)"
    }
    if ($tables.Count -eq 0) {
        return "$SourceName's Application Insights tables are: $($fallback -join ', ')."
    }

    # Closest names first: containment, then the edit distance.
    $distance = {
        param([string] $A, [string] $B)
        $A = $A.ToLowerInvariant(); $B = $B.ToLowerInvariant()
        $previous = 0..$B.Length
        for ($i = 1; $i -le $A.Length; $i++) {
            $current = @($i) + @(0) * $B.Length
            for ($j = 1; $j -le $B.Length; $j++) {
                $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
                $current[$j] = [Math]::Min([Math]::Min($current[$j - 1] + 1, $previous[$j] + 1), $previous[$j - 1] + $cost)
            }
            $previous = $current
        }
        $previous[$B.Length]
    }
    $similar = @($tables | ForEach-Object {
            $score = if ($_.Name -like "*$TableName*" -or $TableName -like "*$($_.Name)*") { 0 } else { & $distance $TableName $_.Name }
            [pscustomobject]@{ Table = $_; Score = $score }
        } | Where-Object { $_.Score -le [Math]::Max(2, [int]($TableName.Length / 3)) } | Sort-Object -Property Score, { $_.Table.Name } | Select-Object -First 3 | ForEach-Object { $_.Table })

    # The tables worth naming: the source's Application Insights tables (a
    # workspace can have hundreds of others) and the similar ones.
    $named = @(@($similar) + @($tables | Where-Object { $_.Name -in $fallback }) | Sort-Object -Property Name -Unique)
    if ($Kind -eq 'Component') { $named = $tables }
    $named = @($named | Select-Object -First 15)

    # How many rows each has in the period, in one query; tables without a
    # time column are named without a count.
    $counts = @{}
    $countable = @($named | Where-Object { $_.Time })
    if ($countable.Count) {
        $parts = @($countable | ForEach-Object { "($($_.Name) | where $($_.Time) > ago($Last))" })
        $kql = "union isfuzzy=true withsource=AACTable $($parts -join ', ') | summarize Rows = count() by AACTable"
        try {
            foreach ($row in @(Invoke-AACLogQuery -Kind $Kind -Id $Id -Query $kql)) {
                $counts[[string]$row['AACTable']] = [long]$row['Rows']
            }
        }
        catch {
            Write-Debug "The tables' rows couldn't be counted: $($_.Exception.Message)"
        }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($similar.Count) {
        $parts.Add("Did you mean $(($similar | ForEach-Object { "'$($_.Name)'" }) -join ' or ')?")
    }
    $withData = @($named | Where-Object { $counts[$_.Name] -gt 0 } | Sort-Object -Property { $counts[$_.Name] } -Descending)
    $withoutData = @($named | Where-Object { -not ($counts[$_.Name] -gt 0) })
    if ($counts.Count -and $withData.Count) {
        $parts.Add("Tables in $SourceName with data in the last ${Last}: $(($withData | ForEach-Object { '{0} ({1:N0})' -f $_.Name, $counts[$_.Name] }) -join ', ').")
        if ($withoutData.Count) { $parts.Add("No data: $(($withoutData.Name) -join ', ').") }
    }
    else {
        $parts.Add("Tables in ${SourceName}: $(($named.Name) -join ', ').")
    }
    $others = $tables.Count - $named.Count
    if ($others -gt 0) { $parts.Add("($others more in its metadata.)") }
    $parts -join ' '
}
