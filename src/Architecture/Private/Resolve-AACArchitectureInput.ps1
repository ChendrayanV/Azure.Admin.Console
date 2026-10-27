function Resolve-AACArchitectureInput {
    <#
    .SYNOPSIS
        Accepts a brief or a design however it is given - the object a
        command returned, a hashtable, or the path of a file -OutPath wrote
        (.json) or a .psd1 - and returns it in one shape.
    .DESCRIPTION
        -Kind Brief returns @{ Name; CatalogVersion; Answers (hashtable);
        Open; Assumed }. A file or hashtable with no Answers key is taken to
        be the answers themselves.
        -Kind Design returns the design as a hashtable: Name; CatalogVersion;
        Answers; Open; Patterns; Regions; LandingZone; Policies;
        AllowedLocations; Tags; Commitment; Nodes (hashtables, each with a
        Settings hashtable); Connections; Notices.
        The path is resolved against the current location by the caller.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateSet('Brief', 'Design')]
        [string] $Kind
    )

    # Objects and JSON alike become nested hashtables.
    $toHash = {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [System.Collections.IDictionary]) { $h = [ordered]@{}; foreach ($k in $Value.Keys) { $h[[string]$k] = & $toHash $Value[$k] }; return $h }
        if ($Value -is [psobject] -and $Value.PSObject.BaseObject -is [System.Management.Automation.PSCustomObject]) { $h = [ordered]@{}; foreach ($p in $Value.PSObject.Properties) { if ($p.Name -ne 'PSTypeName') { $h[$p.Name] = & $toHash $p.Value } }; return $h }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return , @(foreach ($item in $Value) { & $toHash $item }) }
        $Value
    }
    $data = if ($InputObject -is [string]) { Read-AACArchitectureFile -Path $InputObject -What "the $($Kind.ToLowerInvariant())" } else { & $toHash $InputObject }
    if ($data -isnot [System.Collections.IDictionary]) { throw "Azure Admin Console can't use that as a $($Kind.ToLowerInvariant()): give the object New-AACArchitecture$Kind returned, or the path of the file its -OutPath wrote." }
    $list = { param($Value) @(if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) { $Value } elseif ($null -ne $Value) { , $Value }) | Where-Object { $null -ne $_ } }
    $field = { param([string] $Key, $Default) if ($data.Contains($Key) -and $null -ne $data[$Key]) { $data[$Key] } else { $Default } }

    if ($Kind -eq 'Brief') {
        if (-not $data.Contains('Answers')) { return @{ Name = 'workload'; CatalogVersion = ''; Answers = $data; Open = @(); Assumed = @() } }
        return @{ Name = [string](& $field 'Name' 'workload'); CatalogVersion = [string](& $field 'CatalogVersion' ''); Answers = (& $field 'Answers' @{}); Open = @(& $list (& $field 'Open' @())); Assumed = @(& $list (& $field 'Assumed' @())) }
    }
    if (-not $data.Contains('Nodes')) { throw "Azure Admin Console can't use that as a design: it has no Nodes. Give the object New-AACArchitectureDesign returned, or the file its -OutPath wrote." }
    $nodes = @(foreach ($n in & $list $data['Nodes']) {
            if (-not $n.Contains('Settings') -or $n['Settings'] -isnot [System.Collections.IDictionary]) { $n['Settings'] = @{} }
            foreach ($key in 'Region', 'Sku', 'Identity', 'Pattern') { if (-not $n.Contains($key)) { $n[$key] = '' } }
            foreach ($key in 'ZoneRedundant', 'PrivateEndpoint', 'PublicAccess') { $n[$key] = [bool]$(if ($n.Contains($key)) { $n[$key] } else { $false }) }
            $n
        })
    @{
        Name = [string](& $field 'Name' 'workload'); CatalogVersion = [string](& $field 'CatalogVersion' ''); Answers = (& $field 'Answers' @{}); Open = @(& $list (& $field 'Open' @())); Assumed = @(& $list (& $field 'Assumed' @()))
        Created = [string](& $field 'Created' ''); ManagementGroups = @(& $list (& $field 'ManagementGroups' @()))
        Patterns = @(& $list (& $field 'Patterns' @())); Regions = @(& $list (& $field 'Regions' @())); LandingZone = [string](& $field 'LandingZone' '')
        Policies = @(& $list (& $field 'Policies' @())); AllowedLocations = @(& $list (& $field 'AllowedLocations' @())); Tags = (& $field 'Tags' @{}); Commitment = [string](& $field 'Commitment' '')
        Nodes = $nodes; Connections = @(& $list (& $field 'Connections' @())); Notices = @(& $list (& $field 'Notices' @()))
    }
}
