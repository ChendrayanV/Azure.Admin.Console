function Read-AACMetric {
    <#
    .SYNOPSIS
        Reads Azure Monitor metrics, several calls at once, and returns them
        as series by resource and call - for Get-AACNetworkHealth and the
        storage, Service Bus and Cosmos DB assessments.
    .DESCRIPTION
        -Call: @(@{ Id (resource ID); Key (a name for the call); Metric
        (names); Aggregation; Filter (a $filter splitting by dimensions, or
        empty) }). A call fails on its own - a metric a resource doesn't have,
        say - and the others carry on.

        Returns @{ resource ID = @{ call key = @{ Error; Series = @(@{ Name
        (metric); Dims (@{ dimension (lower case) = value }); Points (data
        points: average, maximum, total, minimum) }) } } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Call,

        [Parameter(Mandatory)]
        [string] $Timespan,

        [Parameter(Mandatory)]
        [string] $Interval,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress
    )

    $uris = [ordered]@{}
    foreach ($c in $Call) {
        $uri = "$($c.Id)/providers/Microsoft.Insights/metrics?api-version=2023-10-01&timespan=$Timespan&interval=$Interval&metricnames=$([System.Uri]::EscapeDataString(($c.Metric -join ',')))&aggregation=$($c.Aggregation -join ',')"
        if ($c.Filter) { $uri += "&`$filter=$([System.Uri]::EscapeDataString($c.Filter))" }
        $uris["$($c.Id)|$($c.Key)"] = $uri
    }
    $answers = if ($uris.Count) { Invoke-AACArmParallel -Uri @($uris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} }
    $out = @{}
    foreach ($key in $uris.Keys) {
        $id, $callKey = $key -split '\|', 2
        if (-not $out.Contains($id)) { $out[$id] = @{} }
        $answer = $answers[$uris[$key]]
        $failure = if ($answer -is [System.Collections.IDictionary] -and $answer.Contains('Error')) { [string]$answer['Error'] } else { '' }
        $body = if ($answer -is [System.Collections.IDictionary] -and $answer.Contains('Body')) { $answer['Body'] } else { $null }
        $series = [System.Collections.Generic.List[object]]::new()
        if (-not $failure -and $body -is [System.Collections.IDictionary]) {
            foreach ($m in @($body['value'] | Where-Object { $null -ne $_ })) {
                foreach ($ts in @($m['timeseries'] | Where-Object { $null -ne $_ })) {
                    $dims = @{}
                    foreach ($d in @($ts['metadatavalues'] | Where-Object { $null -ne $_ })) { $dims[([string]$d['name']['value']).ToLowerInvariant()] = [string]$d['value'] }
                    $series.Add(@{ Name = [string]$m['name']['value']; Dims = $dims; Points = @($ts['data'] | Where-Object { $null -ne $_ }) })
                }
            }
        }
        elseif (-not $failure) { $failure = 'No metrics returned.' }
        $out[$id][$callKey] = @{ Error = $failure; Series = $series.ToArray() }
    }
    $out
}
