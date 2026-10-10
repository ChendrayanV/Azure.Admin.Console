function ConvertTo-AACConfigurationSnapshot {
    <#
    .SYNOPSIS
        Turns resources (Resource Graph rows) into a configuration snapshot:
        each resource's settings flattened to 'path = value' - SKU, kind,
        location, tags and properties - without what changes on its own
        (provisioning states, timestamps, counters, status), so two
        snapshots differ only where the configuration does.
    .DESCRIPTION
        Paths are dotted, as Resource Graph's change history writes them:
        'properties.minimumTlsVersion', 'sku.name', 'tags.CostCenter'.
        Arrays are kept whole, as compact JSON. Returns a hashtable:
        resource ID (lower case) -> @{ Type; Name; Settings (path -> text) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Resource = @()
    )

    $volatile = '(?i)(provisioningstate|creationtime|createdat|createdon|timecreated|lastmodified|changedtime|modifiedtime|timestamp|lastupdated|\.etag$|statusof|\.status$|\.state$|instanceview|\.extended\.|statistics|usage|count$|\.resourceguid$|uniqueid|\.version$|powerstate|\.lastsync|primaryendpoints|secondaryendpoints|\.id$)'
    $flatten = {
        param($Value, [string] $Path, [hashtable] $Into)
        if ($Path -and $Path -match $volatile -and $Path -notmatch '(?i)^(sku|kind|location)$') { return }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($k in @($Value.Keys | Sort-Object)) { & $flatten $Value[$k] $(if ($Path) { "$Path.$k" } else { [string]$k }) $Into }
        }
        elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $Into[$Path] = ConvertTo-Json -InputObject @($Value) -Depth 20 -Compress
        }
        elseif ($null -ne $Value) { $Into[$Path] = $(if ($Value -is [bool]) { $Value.ToString().ToLowerInvariant() } else { [string]$Value }) }
    }
    $snapshot = @{}
    foreach ($r in $Resource) {
        $get = { param([string] $Name) if ($r -is [System.Collections.IDictionary]) { $r[$Name] } else { $p = $r.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
        $values = @{}
        foreach ($part in 'sku', 'kind', 'location', 'tags', 'identity', 'properties') {
            $v = & $get $part
            if ($null -eq $v) { continue }
            if ($part -eq 'identity' -and $v -is [System.Collections.IDictionary]) { $values['identity.type'] = [string]$v['type']; continue }
            & $flatten $v $part $values
        }
        $snapshot[([string](& $get 'id')).ToLowerInvariant()] = @{ Type = ([string](& $get 'type')).ToLowerInvariant(); Name = [string](& $get 'name'); Settings = $values }
    }
    $snapshot
}
