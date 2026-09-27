function Invoke-AACLogQuery {
    <#
    .SYNOPSIS
        Runs a KQL query against a Log Analytics workspace or an Application
        Insights resource, through Azure Resource Manager, and returns the
        rows as ordered hashtables.
    .DESCRIPTION
        Azure Resource Manager proxies both query APIs, so the Connect-AAC
        sign-in (an ARM token) is enough - no separate Log Analytics or
        Application Insights token:

          POST {workspace ID}/api/query?api-version=2020-08-01
          POST {Application Insights ID}/api/query?api-version=2018-04-20

        with { query, timespan }. -Timespan is an ISO 8601 duration ('PT2H')
        that bounds the query as well as any time filter inside it. Only
        the first result table is returned. Needs Log Analytics Reader (or
        Reader) on the workspace or resource.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceId,

        [Parameter(Mandatory)]
        [ValidateSet('Workspace', 'Component')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $Query,

        [string] $Timespan
    )

    $apiVersion = @{ Workspace = '2020-08-01'; Component = '2018-04-20' }[$Kind]
    $body = @{ query = $Query }
    if ($Timespan) { $body.timespan = $Timespan }
    $response = Invoke-AACArmRequest -Method Post -Uri "$($ResourceId)/api/query?api-version=$apiVersion" -Body ($body | ConvertTo-Json -Depth 5)
    $table = @($response['tables'])[0]
    if (-not $table) {
        return
    }
    $columns = @($table['columns'] | ForEach-Object { [string]$_['name'] })
    foreach ($row in @($table['rows'])) {
        $record = [ordered]@{}
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $record[$columns[$i]] = $row[$i]
        }
        $record
    }
}
