function ConvertTo-AACSentinelWatchlist {
    <#
    .SYNOPSIS
        Turns a workspace's watchlists, their item counts and the queries that
        could use them into AAC.SentinelWatchlist objects, each with findings.
    .DESCRIPTION
        No Azure calls, so it can be tested with made-up data.

          -Watchlist    the watchlists (Resource Manager), hashtables
          -ItemRow      KQL rows: WatchlistAlias, Items, LastItemUpdate
                        ($null when the items couldn't be counted)
          -RuleQuery    enabled analytics rules: @{ Name; Query }
          -HuntingQuery hunting queries: @{ Name; Query }

        A query uses a watchlist when it calls _GetWatchlist('alias'). One that
        reads the Watchlist table directly isn't counted, so Unused is a
        prompt to check, not proof.

        Findings: upload failed, no items, used by no rule or hunting query,
        not updated for -StaleAfterDays (180).
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelWatchlist')]
    param(
        [AllowEmptyCollection()]
        [object[]] $Watchlist = @(),

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $ItemRow,

        [AllowEmptyCollection()]
        [object[]] $RuleQuery = @(),

        [AllowEmptyCollection()]
        [object[]] $HuntingQuery = @(),

        [int] $StaleAfterDays = 180,

        [datetime] $Now = [datetime]::UtcNow
    )

    $inv = [cultureinfo]::InvariantCulture
    $get = {
        param($Object, [string[]] $Path)
        $value = $Object
        foreach ($key in $Path) {
            if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($key)) { return $null }
            $value = $value[$key]
        }
        $value
    }
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    # Who made a change: email, else name, else object ID.
    $who = { param($Person) if ($Person -is [System.Collections.IDictionary]) { [string](@($Person['email'], $Person['name'], $Person['objectId'] | Where-Object { $_ }) | Select-AACFirst 1) } else { '' } }
    $countsRead = $null -ne $ItemRow
    $items = @{}
    foreach ($row in @($ItemRow | Where-Object { $null -ne $_ })) { $items[([string]$row['WatchlistAlias']).ToLowerInvariant()] = $row }
    $users = {
        param([object[]] $Queries, [string] $Alias)
        $pattern = "(?i)_GetWatchlist\s*\(\s*['""]$([regex]::Escape($Alias))['""]"
        @($Queries | Where-Object { $_ -and [string]$_.Query -match $pattern } | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
    }

    $result = @(foreach ($item in @($Watchlist | Where-Object { $null -ne $_ })) {
            $properties = & $get $item 'properties'
            $alias = [string](& $get $properties 'watchlistAlias')
            if (-not $alias) { $alias = [string]$item['name'] }
            $count = $items[$alias.ToLowerInvariant()]
            $itemCount = if ($count) { [int]$count['Items'] } elseif ($countsRead) { 0 }
            $updated = & $date (& $get $properties 'updated')
            $created = & $date (& $get $properties 'created')
            $lastChange = @($updated, $created, $(if ($count) { & $date $count['LastItemUpdate'] }) | Where-Object { $_ } | Sort-Object -Descending | Select-AACFirst 1)
            $daysSince = if ($lastChange.Count) { [int][Math]::Floor(($Now - $lastChange[0]).TotalDays) }
            $rules = @(& $users $RuleQuery $alias)
            $hunting = @(& $users $HuntingQuery $alias)
            $provisioning = [string](& $get $properties 'provisioningState')
            $upload = [string](& $get $properties 'uploadStatus')
            $findings = [System.Collections.Generic.List[string]]::new()
            if ($provisioning -eq 'Failed' -or $upload -match '(?i)fail') { $findings.Add('Upload failed') }
            if ($countsRead -and $itemCount -eq 0) { $findings.Add('No items') }
            if (-not $rules.Count -and -not $hunting.Count) { $findings.Add('Unused') }
            if ($null -ne $daysSince -and $daysSince -gt $StaleAfterDays) { $findings.Add("Not updated for $daysSince days") }
            [pscustomobject][ordered]@{
                PSTypeName      = 'AAC.SentinelWatchlist'
                Name            = [string](& $get $properties 'displayName')
                Alias           = $alias
                Items           = $itemCount
                SearchKey       = [string](& $get $properties 'itemsSearchKey')
                Rules           = $rules.Count
                HuntingQueries  = $hunting.Count
                UsedBy          = (@($rules) + @($hunting)) -join ', '
                Findings        = $findings -join '; '
                Provider        = [string](& $get $properties 'provider')
                Source          = [string](& $get $properties 'source')
                SourceType      = [string](& $get $properties 'sourceType')
                Labels          = @(& $get $properties 'labels' | Where-Object { $_ }) -join ', '
                ItemExpiry      = [string](& $get $properties 'defaultDuration')
                Created         = $created
                CreatedBy       = & $who (& $get $properties 'createdBy')
                Updated         = $updated
                UpdatedBy       = & $who (& $get $properties 'updatedBy')
                DaysSinceUpdate = $daysSince
                Description     = [string](& $get $properties 'description')
                WatchlistId     = [string]$item['name']
            }
        })
    @($result | Sort-Object -Property @{ Expression = { [bool]$_.Findings }; Descending = $true }, 'Name')
}
