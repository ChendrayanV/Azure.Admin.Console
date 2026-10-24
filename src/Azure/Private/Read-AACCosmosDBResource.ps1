function Read-AACCosmosDBResource {
    <#
    .SYNOPSIS
        Reads what Invoke-AACCosmosDBAssessment needs from each Cosmos DB
        account through Resource Manager - its databases and containers (in
        the account's API), their throughput, and where its logs go - many
        requests at once.
    .DESCRIPTION
        Each API names its levels differently:
          NoSQL      sqlDatabases / containers
          MongoDB    mongodbDatabases / collections
          Cassandra  cassandraKeyspaces / tables
          Gremlin    gremlinDatabases / graphs
          Table      tables (no database level)
        Three rounds through Invoke-AACArmParallel (Reader is enough):
          1. per account: the diagnostic settings, and its databases (or,
             Table, its tables)
          2. per database: its containers, and the database's shared
             throughput
          3. per container: its own throughput
        Throughput isn't read for serverless accounts (they have none). A
        throughputSettings answer of 404 or 400 means none at that level.

        -Account: @(@{ Id; Api (NoSQL, MongoDB, Cassandra, Gremlin, Table);
        Serverless }). Returns @{ account id = @{ Logs (the diagnostic
        settings' result); Error (why the databases couldn't be read);
        Databases = @(@{ Name; Id; Throughput; Containers = @(@{ Name; Id;
        Resource (the container's resource properties); Throughput }) }) } }
        - Throughput being Invoke-AACArmParallel's result, or $null.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Account,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress
    )

    $api = 'api-version=2024-05-15'
    $levels = @{ NoSQL = @('sqlDatabases', 'containers'); MongoDB = @('mongodbDatabases', 'collections'); Cassandra = @('cassandraKeyspaces', 'tables'); Gremlin = @('gremlinDatabases', 'graphs'); Table = @('', 'tables') }
    $run = { param([System.Collections.IDictionary] $Uris) if ($Uris.Count) { Invoke-AACArmParallel -Uri @($Uris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} } }
    $itemsOf = { param($Answer) @(if ($Answer -and -not $Answer['Error']) { $Answer['Items'] | Where-Object { $_ } }) }

    $out = @{}
    $byId = @{}
    $first = [ordered]@{}
    foreach ($a in $Account) {
        $out[$a.Id] = @{ Logs = $null; Error = ''; Databases = [System.Collections.Generic.List[hashtable]]::new() }
        $byId[$a.Id] = $a
        $level = $levels[[string]$a.Api]
        $first["$($a.Id)|Logs"] = "$($a.Id)/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
        $first["$($a.Id)|List"] = if ($level[0]) { "$($a.Id)/$($level[0])?$api" } else { "$($a.Id)/$($level[1])?$api" }
    }
    $answers = & $run $first

    # Round 2: each database's containers and shared throughput - or, for Table, each table's throughput.
    $second = [ordered]@{}
    foreach ($a in $Account) {
        $out[$a.Id].Logs = $answers[$first["$($a.Id)|Logs"]]
        $list = $answers[$first["$($a.Id)|List"]]
        if (-not $list -or $list['Error']) { $out[$a.Id].Error = $(if ($list) { [string]$list['Error'] } else { 'No answer.' }); continue }
        $level = $levels[[string]$a.Api]
        if (-not $level[0]) {
            # Table: one implicit database holding the tables.
            $database = @{ Name = ''; Id = $a.Id; Throughput = $null; Containers = [System.Collections.Generic.List[hashtable]]::new() }
            foreach ($t in (& $itemsOf $list)) {
                $container = @{ Name = [string]$t['name']; Id = [string]$t['id']; Resource = $t['properties']; Throughput = $null }
                $database.Containers.Add($container)
                if (-not $a.Serverless) { $second["$($a.Id)|$($container.Id)|ct"] = "$($container.Id)/throughputSettings/default?$api" }
            }
            $out[$a.Id].Databases.Add($database)
            continue
        }
        foreach ($d in (& $itemsOf $list)) {
            $database = @{ Name = [string]$d['name']; Id = [string]$d['id']; Throughput = $null; Containers = [System.Collections.Generic.List[hashtable]]::new() }
            $out[$a.Id].Databases.Add($database)
            $second["$($a.Id)|$($database.Id)|children"] = "$($database.Id)/$($level[1])?$api"
            if (-not $a.Serverless) { $second["$($a.Id)|$($database.Id)|dt"] = "$($database.Id)/throughputSettings/default?$api" }
        }
    }
    $answers = & $run $second
    $third = [ordered]@{}
    foreach ($key in $second.Keys) {
        $accountId, $resourceId, $what = $key -split '\|', 3
        $answer = $answers[$second[$key]]
        $databases = $out[$accountId].Databases
        switch ($what) {
            'ct' { foreach ($db in $databases) { foreach ($c in $db.Containers) { if ($c.Id -eq $resourceId) { $c.Throughput = $answer } } } }
            'dt' { foreach ($db in $databases) { if ($db.Id -eq $resourceId) { $db.Throughput = $answer } } }
            'children' {
                foreach ($db in $databases) {
                    if ($db.Id -ne $resourceId) { continue }
                    foreach ($c in (& $itemsOf $answer)) {
                        $container = @{ Name = [string]$c['name']; Id = [string]$c['id']; Resource = $c['properties']; Throughput = $null }
                        $db.Containers.Add($container)
                        if (-not $byId[$accountId].Serverless) { $third["$accountId|$($container.Id)"] = "$($container.Id)/throughputSettings/default?$api" }
                    }
                }
            }
        }
    }

    # Round 3: each container's own throughput.
    $answers = & $run $third
    foreach ($key in $third.Keys) {
        $accountId, $containerId = $key -split '\|', 2
        foreach ($db in $out[$accountId].Databases) { foreach ($c in $db.Containers) { if ($c.Id -eq $containerId) { $c.Throughput = $answers[$third[$key]] } } }
    }
    $out
}
