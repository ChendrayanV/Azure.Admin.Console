function Read-AACGraphQuery {
    <#
    .SYNOPSIS
        Reads many Microsoft Graph URIs at once with the Connect-AAC sign-in
        (one Graph token for all of them), each followed through its pages.
    .DESCRIPTION
        -Query maps a name to a Graph URI, or to @{ Uri; MaxItems }. A list
        ('value') is read to the end, following @odata.nextLink (or until
        MaxItems are read); anything else is kept as the single object it
        is. One failing call (no permission, no licence, a 404)
        doesn't stop the others: it is in Errors with Graph's own reason.

        Returns @{ Data (name -> the items, or the object); Errors (name ->
        the reason) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Query,

        [scriptblock] $OnDone,

        [ValidateRange(1, 16)]
        [int] $ThrottleLimit = 6
    )

    # The script blocks below run inside Invoke-AACHttpBatch, whose own
    # variables ($OnDone, $errors...) would hide ours: every name they use
    # here is prefixed 'graph'.
    $graphLists = @{}; $graphObjects = @{}; $graphOnDone = $OnDone; $graphMax = @{}
    foreach ($name in $Query.Keys) { $graphLists[$name] = [System.Collections.Generic.List[object]]::new() }
    $graphPages = {
        param($Key, [string] $Content)
        $graphPage = if ($Content) { ConvertFrom-Json -InputObject $Content -AsHashtable -Depth 64 } else { @{} }
        if ($graphPage -is [System.Collections.IDictionary] -and $graphPage.Contains('value') -and ($graphPage['value'] -is [System.Collections.IList] -or $null -eq $graphPage['value'])) {
            foreach ($graphItem in @($graphPage['value'])) { if ($null -ne $graphItem) { $graphLists[$Key].Add($graphItem) } }
            $graphEnough = $graphMax.Contains($Key) -and $graphLists[$Key].Count -ge $graphMax[$Key]
            if ($graphPage['@odata.nextLink'] -and -not $graphEnough) { return @{ Uri = [string]$graphPage['@odata.nextLink'] } }
        }
        else { $graphObjects[$Key] = $graphPage }
    }
    # A query is a URI, or @{ Uri; MaxItems } to stop following pages after that many.
    $requests = @(foreach ($name in $Query.Keys) {
            $graphSpec = $Query[$name]
            if ($graphSpec -is [System.Collections.IDictionary]) { if ($graphSpec['MaxItems']) { $graphMax[$name] = [int]$graphSpec['MaxItems'] }; $graphSpec = $graphSpec['Uri'] }
            @{ Key = $name; Body = $null; Uri = [string]$graphSpec }
        })
    $failures = Invoke-AACHttpBatch -Request $requests -OnResponse $graphPages -Resource 'https://graph.microsoft.com' -ThrottleLimit $ThrottleLimit -OnDone {
        param($Key, $Failure, $Done, $Total)
        if ($graphOnDone) { & $graphOnDone $Key $Failure $Done $Total }
    }
    $data = @{}; $graphErrors = @{}
    foreach ($name in $Query.Keys) {
        if ($failures[$name]) { $graphErrors[$name] = [string]$failures[$name]; continue }
        $data[$name] = if ($graphObjects.Contains($name)) { $graphObjects[$name] } else { $graphLists[$name].ToArray() }
    }
    @{ Data = $data; Errors = $graphErrors }
}
