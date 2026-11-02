function Get-AACHuntingQueryHash {
    <#
    .SYNOPSIS
        A hash of a query's text, ignoring line endings and outer white space.
    .DESCRIPTION
        Deploy-AACSentinelHuntingQuery stores it in a tag on the saved search,
        so a later run can tell a query someone edited in the workspace from one
        that is simply behind the catalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string] $Query
    )

    [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes(($Query -replace "`r`n", "`n").Trim()))).Substring(0, 16).ToLowerInvariant()
}

function Get-AACHuntingQueryTag {
    <#
    .SYNOPSIS
        One tag's value from a saved search, or '' when it has none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [System.Collections.IDictionary] $SavedSearch,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $tags = if ($SavedSearch -and $SavedSearch['properties'] -is [System.Collections.IDictionary]) { @($SavedSearch['properties']['tags'] | Where-Object { $_ -is [System.Collections.IDictionary] }) } else { @() }
    foreach ($tag in $tags) { if ([string]$tag['name'] -eq $Name) { return [string]$tag['value'] } }
    ''
}

function ConvertTo-AACHuntingQueryState {
    <#
    .SYNOPSIS
        Works out, for each catalog query, whether a workspace is ready for it
        and how it stands there.
    .DESCRIPTION
        No Azure calls: -Workspace is what Read-AACHuntingWorkspace read.

        Readiness:
          Ready              the tables it needs have data, its watchlists exist
          Missing data       a table it needs had no data in the period
          Missing watchlist  a watchlist it reads doesn't exist
          Unknown            the tables or watchlists couldn't be read
        Deployment:
          New                not on the workspace
          Current            on the workspace, with the same query
          Update available   deployed by this module, unedited, and the
                             catalog's query has moved on
          Changed            on the workspace with another query, edited there
                             or not deployed by this module
          Other copy         a hunting query with this name under another ID,
                             such as one installed from Content hub

        Returns copies: the catalog's own objects aren't changed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Query = @(),

        [Parameter(Mandatory)]
        [hashtable] $Workspace
    )

    $savedById = @{}
    $savedByName = @{}
    foreach ($saved in @($Workspace.SavedSearches)) {
        $savedById[([string]$saved['name']).ToLowerInvariant()] = $saved
        $savedByName[([string]$saved['properties']['displayName']).ToLowerInvariant()] = $saved
    }
    foreach ($item in $Query) {
        $copy = $item.PSObject.Copy()
        $needs = @(([string]$item.DataTypes -split ',\s*') | Where-Object { $_ })
        $reads = @(([string]$item.Watchlists -split ',\s*') | Where-Object { $_ })
        $noData = @(if ($null -ne $Workspace.Tables) { $needs | Where-Object { -not $Workspace.Tables.Contains($_.ToLowerInvariant()) } })
        $noList = @(if ($null -ne $Workspace.Watchlists) { $reads | Where-Object { -not $Workspace.Watchlists.Contains($_.ToLowerInvariant()) } })
        $unknown = ($null -eq $Workspace.Tables -and $needs.Count) -or ($null -eq $Workspace.Watchlists -and $reads.Count)
        $copy.Readiness = if ($noData.Count) { 'Missing data' } elseif ($noList.Count) { 'Missing watchlist' } elseif ($unknown) { 'Unknown' } else { 'Ready' }
        $copy.Ready = $copy.Readiness -eq 'Ready'
        $copy.Missing = @(@($noData) + @($noList | ForEach-Object { "watchlist $_" })) -join ', '

        $saved = $savedById[([string]$item.Id).ToLowerInvariant()]
        $copy.Deployment = if ($saved) {
            $savedHash = Get-AACHuntingQueryHash -Query ([string]$saved['properties']['query'])
            $deployedHash = Get-AACHuntingQueryTag -SavedSearch $saved -Name 'aacQueryHash'
            if ($savedHash -eq (Get-AACHuntingQueryHash -Query ([string]$item.Query))) { 'Current' }
            elseif ($deployedHash -and $deployedHash -eq $savedHash) { 'Update available' }
            else { 'Changed' }
        }
        elseif ($savedByName[([string]$item.Name).ToLowerInvariant()]) { 'Other copy' }
        else { 'New' }
        $copy
    }
}
