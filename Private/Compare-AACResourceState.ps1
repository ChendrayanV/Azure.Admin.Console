function Compare-AACResourceState {
    <#
    .SYNOPSIS
        Compares one resource's desired state with what Azure has, property
        by property, and works out what to send: the heart of
        Deploy-AACStorageAccount's idempotency.
    .DESCRIPTION
        -Node is one of Get-AACStorageDesiredState's nodes; -Current the
        resource as Azure returns it, or $null when it doesn't exist.

        Only the node's Managed properties are compared, each by its Mode:
          Value    one value; strings case-insensitive (CaseSensitive for
                   tag and metadata values)
          Map      a dictionary, keys case-insensitive (tags, metadata)
          Set      a list compared regardless of order (IP rules, subnets,
                   diagnostic categories, lifecycle rules)
          Object   a nested object
        A missing current value counts as the spec's Absent value - what
        Azure means when it leaves a property out (no infrastructure
        encryption, shared key access allowed). Inside objects and list
        items only the keys the desired state names are compared, so fields
        Azure adds by itself (a rule's state, a category's retention policy)
        don't show as changes; disabled entries Azure echoes back are
        dropped when the desired list names only enabled ones.

        Returns @{ Action; Differences; Method; Body }:
          Create     it doesn't exist: PUT the desired body
          Update     something differs: PATCH the changed top-level
                     properties, or PUT the current settings with the
                     desired ones merged in (Put nodes - a service's other
                     settings stay as they are) or the desired body as it
                     is (settings, locks, policies - replaced whole)
          Replace    a property Azure can't change in place differs: nothing
                     is sent, and the plan stops
          NoChange
        Differences: @{ Property; Current; Desired; Immutable } per property
        that differs (on Create: every managed property, Current empty).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Node,

        [System.Collections.IDictionary] $Current
    )

    $get = {
        param($Object, [string] $Path)
        $value = $Object
        foreach ($part in $Path.Split('.')) {
            if ($value -isnot [System.Collections.IDictionary]) { return $null }
            $key = @($value.Keys | Where-Object { [string]$_ -ieq $part }) | Select-AACFirst 1
            if ($null -eq $key) { return $null }
            $value = $value[$key]
        }
        , $value
    }
    # The current value narrowed to the keys the desired value names, at
    # every level.
    $project = {
        param($CurrentValue, $DesiredValue)
        if ($DesiredValue -is [System.Collections.IDictionary] -and $CurrentValue -is [System.Collections.IDictionary]) {
            $out = [ordered]@{}
            foreach ($key in $DesiredValue.Keys) {
                $match = @($CurrentValue.Keys | Where-Object { [string]$_ -ieq [string]$key }) | Select-AACFirst 1
                # Not through $( ): it would unroll a one-item list to its item.
                $value = $null
                if ($null -ne $match) { $value = $CurrentValue[$match] }
                $out[[string]$key] = & $project $value $DesiredValue[$key]
            }
            return , $out
        }
        if ($DesiredValue -is [System.Collections.IList] -and $DesiredValue -isnot [string] -and $CurrentValue -is [System.Collections.IList] -and $CurrentValue -isnot [string]) {
            $shape = @($DesiredValue | Where-Object { $_ -is [System.Collections.IDictionary] })
            if (-not $shape.Count) { return , @($CurrentValue) }
            $keys = [ordered]@{}
            foreach ($item in $shape) { foreach ($key in $item.Keys) { $keys[[string]$key] = $item[$key] } }
            return , @(foreach ($item in $CurrentValue) { & $project $item $keys })
        }
        $CurrentValue
    }
    $canonical = {
        param($Value, [bool] $CaseSensitive, [bool] $AsSet)
        if ($null -eq $Value) { return 'null' }
        if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
        if ($Value -is [string]) { $text = $Value; if (-not $CaseSensitive) { $text = $text.ToLowerInvariant() }; return [System.Text.Json.JsonEncodedText]::Encode($text).ToString() }
        if ($Value -is [System.Collections.IDictionary]) {
            $keys = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object { $_.ToLowerInvariant() })
            return '{' + (@(foreach ($key in $keys) { $key.ToLowerInvariant() + ':' + (& $canonical $Value[$key] $CaseSensitive $false) }) -join ',') + '}'
        }
        if ($Value -is [System.Collections.IList]) {
            $items = @(foreach ($item in $Value) { & $canonical $item $CaseSensitive $false })
            if ($AsSet) { $items = @($items | Sort-Object) }
            return '[' + ($items -join ',') + ']'
        }
        if ($Value -is [System.IFormattable]) { return $Value.ToString($null, [cultureinfo]::InvariantCulture) }
        [string]$Value
    }
    $dropDisabled = {
        param($List, $Desired)
        $named = @($Desired | Where-Object { $_ -is [System.Collections.IDictionary] })
        if (-not $named.Count -or @($named | Where-Object { -not $_.Contains('enabled') -or -not $_['enabled'] }).Count) { return , @($List) }
        , @($List | Where-Object { -not ($_ -is [System.Collections.IDictionary] -and $_.Contains('enabled') -and $false -eq $_['enabled']) })
    }
    $show = {
        param($Value)
        if ($null -eq $Value) { return '' }
        if ($Value -is [string]) { return $Value }
        if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
        ConvertTo-Json -InputObject $Value -Depth 20 -Compress
    }

    $desiredBody = $Node.Desired
    $differences = [System.Collections.Generic.List[object]]::new()
    if (-not $Current) {
        foreach ($spec in $Node.Managed) {
            $desired = & $get $desiredBody $spec.Path
            if ($null -eq $desired) { continue }
            $differences.Add([pscustomobject]@{ Property = $spec.Path; Current = ''; Desired = (& $show $desired); Immutable = $false })
        }
        return @{ Action = 'Create'; Differences = $differences.ToArray(); Method = 'Put'; Body = $desiredBody }
    }

    foreach ($spec in $Node.Managed) {
        $want = & $get $desiredBody $spec.Path
        if ($null -eq $want -and $spec.Mode -ne 'Map') { continue }
        $have = & $get $Current $spec.Path
        if ($null -eq $have -or ($have -is [string] -and $have -eq '' -and $null -ne $spec.Absent)) { $have = $spec.Absent }
        $asSet = $spec.Mode -eq 'Set'
        if ($spec.Mode -in 'Set', 'Object') {
            $have = & $project $have $want
            if ($asSet) { $have = & $dropDisabled $have $want; $want = & $dropDisabled $want $want }
        }
        if ($spec.Mode -eq 'Set' -and $null -eq $have) { $have = @() }
        if ($spec.Mode -eq 'Set' -and $have -is [string]) { $have = @($have -split '\s*,\s*' | Where-Object { $_ }) }
        if ($spec.Mode -eq 'Set' -and $want -is [string]) { $want = @($want -split '\s*,\s*' | Where-Object { $_ }) }
        if ($spec.Mode -eq 'Map' -and $null -eq $have) { $have = @{} }
        if ($spec.Mode -eq 'Map' -and $null -eq $want) { $want = @{} }
        if ((& $canonical $have $spec.CaseSensitive $asSet) -cne (& $canonical $want $spec.CaseSensitive $asSet)) {
            $immutable = $spec.Immutable -or ($spec.Contains('ImmutableWhen') -and $spec.ImmutableWhen -and [bool](& $spec.ImmutableWhen $have $want))
            $differences.Add([pscustomobject]@{ Property = $spec.Path; Current = (& $show $have); Desired = (& $show $want); Immutable = $immutable })
        }
    }
    if (-not $differences.Count) { return @{ Action = 'NoChange'; Differences = @(); Method = ''; Body = $null } }
    if (@($differences | Where-Object Immutable).Count) { return @{ Action = 'Replace'; Differences = $differences.ToArray(); Method = ''; Body = $null } }

    if ($Node.UpdateMethod -eq 'Patch') {
        # The changed top-level properties - a nested one is sent whole, the
        # current value with the desired merged in.
        $body = [ordered]@{}
        foreach ($difference in $differences) {
            $parts = $difference.Property.Split('.')
            if ($parts[0] -eq 'properties' -and $parts.Count -gt 1) {
                if (-not $body.Contains('properties')) { $body['properties'] = [ordered]@{} }
                $key = $parts[1]
                $desiredValue = & $get $desiredBody "properties.$key"
                $currentValue = & $get $Current "properties.$key"
                $body['properties'][$key] = if ($desiredValue -is [System.Collections.IDictionary] -and $currentValue -is [System.Collections.IDictionary]) { Merge-AACObject -Base $currentValue -Overlay $desiredValue } else { $desiredValue }
            }
            else {
                $body[$parts[0]] = & $get $desiredBody $parts[0]
            }
        }
        return @{ Action = 'Update'; Differences = $differences.ToArray(); Method = 'Patch'; Body = $body }
    }
    $body = if ($Node.Kind -in 'blobService', 'fileService', 'queueService', 'tableService') {
        [ordered]@{ properties = Merge-AACObject -Base $(if ($Current['properties'] -is [System.Collections.IDictionary]) { $Current['properties'] } else { @{} }) -Overlay $desiredBody['properties'] }
    }
    else { $desiredBody }
    @{ Action = 'Update'; Differences = $differences.ToArray(); Method = 'Put'; Body = $body }
}
