function Invoke-AACLogQuery {
    <#
    .SYNOPSIS
        Runs a KQL query against a Log Analytics workspace or an Application
        Insights resource, and returns the rows as ordered hashtables.
    .DESCRIPTION
        Uses each service's documented query API, with a token for that API
        from the Connect-AAC sign-in (Get-AACAccessToken -Resource):

          Workspace   POST https://api.loganalytics.azure.com/v1/workspaces/{workspace ID}/query
          Component   POST https://api.applicationinsights.io/v1/apps/{app ID}/query

        -Id is the workspace ID (its customerId GUID) or the Application
        Insights app ID - Resolve-AACLogResource's QueryId. The body is
        { query, timespan }: -Timespan is an ISO 8601 duration ('PT2H') that
        bounds the query as well as any time filter inside it. Only the first
        result table is returned. Needs Log Analytics Reader (or Reader) on
        the workspace or resource.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Workspace', 'Component')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Id,

        [Parameter(Mandatory)]
        [string] $Query,

        [string] $Timespan
    )

    if (-not $Id) {
        throw "Azure Resource Graph returned no $(if ($Kind -eq 'Workspace') { 'workspace ID (customerId)' } else { 'app ID' }) for it, so it can't be queried."
    }
    $api = @{
        Workspace = @{ Uri = "https://api.loganalytics.azure.com/v1/workspaces/$Id/query"; Resource = 'https://api.loganalytics.io' }
        Component = @{ Uri = "https://api.applicationinsights.io/v1/apps/$Id/query"; Resource = 'https://api.applicationinsights.io' }
    }[$Kind]
    $body = @{ query = $Query }
    if ($Timespan) { $body.timespan = $Timespan }
    $uri = $api.Uri
    Write-Verbose "POST $uri (timespan $Timespan)`n$Query"
    $response = Invoke-AACArmRequest -Method Post -Uri $uri -Resource $api.Resource -Body ($body | ConvertTo-Json -Depth 5)
    # A reply without result tables is not "no rows": say so rather than
    # return an empty result that looks like a quiet workspace.
    if (-not ($response -is [System.Collections.IDictionary] -and $response.Contains('tables') -and @($response['tables']).Count)) {
        $shown = if ($null -eq $response) { 'an empty reply' } else { ConvertTo-Json -InputObject $response -Depth 3 -Compress }
        if ($shown.Length -gt 300) { $shown = $shown.Substring(0, 300) + '...' }
        throw "The $Kind query API returned no result table ($shown)."
    }
    $table = @($response['tables'])[0]
    $columns = @($table['columns'] | ForEach-Object { [string]$_['name'] })
    foreach ($row in @($table['rows'])) {
        $record = [ordered]@{}
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $record[$columns[$i]] = $row[$i]
        }
        $record
    }
}
