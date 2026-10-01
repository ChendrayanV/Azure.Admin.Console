function Get-AACPolicyResourceType {
    <#
    .SYNOPSIS
        The resource types a policy definition's rule applies to, read from
        its 'if' condition - with [parameters('...')] resolved to the values
        the assignment gives them.
    .DESCRIPTION
        Walks the rule's 'if' (allOf, anyOf, not, count) and collects:
          Include  the types in "field": "type" conditions - equals, in,
                   like, match - outside a 'not'
          Exclude  the types in negated ones - notEquals, notIn, notLike,
                   notMatch, or any of the above inside a 'not' (as
                   "Allowed resource types" does: not in the allowed list)
          Aliased  the types of the property aliases the rule reads, e.g.
                   Microsoft.Storage/storageAccounts/minimumTlsVersion ->
                   Microsoft.Storage/storageAccounts
        A value of "[parameters('name')]" is replaced by -Parameter[name]
        (the effective value: assigned, else the default); other template
        expressions are left out. The 'then' block (deployIfNotExists'
        related resource, say) isn't the policy's target and is ignored.

        Returns @{ Include; Exclude; Aliased; Text }. Text is what the
        AAC.AssignedPolicy rows show: the included types, else the aliased
        ones, else 'All except ...', else 'All'.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        $Rule,

        # Parameter name -> effective value.
        [System.Collections.IDictionary] $Parameter = @{}
    )

    $include = [System.Collections.Generic.List[string]]::new()
    $exclude = [System.Collections.Generic.List[string]]::new()
    $aliased = [System.Collections.Generic.List[string]]::new()
    $positive = 'equals', 'in', 'like', 'match', 'matchInsensitively'
    $negative = 'notEquals', 'notIn', 'notLike', 'notMatch', 'notMatchInsensitively'

    $resolve = {
        param($Value)
        foreach ($item in @($Value)) {
            if ($item -is [string] -and $item -match "^\[parameters\('([^']+)'\)\]$") {
                $name = $Matches[1]
                $key = @($Parameter.Keys | Where-Object { $_ -eq $name }) | Select-Object -First 1
                if ($null -ne $key) { foreach ($v in @($Parameter[$key])) { if ($v -is [string] -and $v) { $v } } }
            }
            elseif ($item -is [string] -and $item -and -not $item.StartsWith('[')) { $item }
        }
    }
    # Microsoft.Compute/virtualMachines/storageProfile.osDisk.osType ->
    # Microsoft.Compute/virtualMachines: the type segments run until one
    # holds a '.' or '[' - or, with none, all but the last (the property).
    $aliasType = {
        param([string] $Alias)
        $segments = $Alias.Split('/')
        $types = [System.Collections.Generic.List[string]]::new()
        $stopped = $false
        for ($i = 1; $i -lt $segments.Count; $i++) {
            if ($segments[$i] -match '[.\[]') { $stopped = $true; break }
            $types.Add($segments[$i])
        }
        if (-not $stopped -and $types.Count) { $types.RemoveAt($types.Count - 1) }
        if ($types.Count) { "$($segments[0])/$($types -join '/')" }
    }
    # Policy JSON is case-insensitive ('allOf' or 'AllOf'); the hashtables
    # from ConvertFrom-Json -AsHashtable aren't.
    $get = {
        param([System.Collections.IDictionary] $Map, [string] $Name)
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return $Map[$k] } }
    }
    $isAlias = { param([string] $Field) $Field -match '^[A-Za-z0-9]+(\.[A-Za-z0-9]+)+/[^/]' }

    $walk = $null
    $walk = {
        param($Node, [bool] $Negated)
        if ($Node -is [System.Collections.IList]) { foreach ($child in $Node) { & $walk $child $Negated }; return }
        if ($Node -isnot [System.Collections.IDictionary]) { return }
        foreach ($key in @($Node.Keys)) {
            switch ($key) {
                'not' { & $walk $Node[$key] (-not $Negated) }
                { $_ -in 'allOf', 'anyOf' } { & $walk $Node[$key] $Negated }
                'count' {
                    $count = $Node[$key]
                    if ($count -is [System.Collections.IDictionary]) {
                        $field = [string](& $get $count 'field')
                        if ($field -and (& $isAlias $field)) { $type = & $aliasType $field; if ($type) { $aliased.Add($type) } }
                        & $walk (& $get $count 'where') $Negated
                    }
                }
            }
        }
        $field = & $get $Node 'field'
        if ($field -isnot [string] -or -not $field) { return }
        if ($field -eq 'type') {
            foreach ($operator in $positive + $negative) {
                $match = @($Node.Keys | Where-Object { $_ -eq $operator }) | Select-Object -First 1
                if ($null -eq $match) { continue }
                $toExclude = $Negated -xor ($operator -in $negative)
                foreach ($value in @(& $resolve $Node[$match])) { if ($toExclude) { $exclude.Add($value) } else { $include.Add($value) } }
            }
        }
        elseif (& $isAlias $field) {
            $type = & $aliasType $field
            if ($type) { $aliased.Add($type) }
        }
    }
    if ($Rule -is [System.Collections.IDictionary]) {
        & $walk (& $get $Rule 'if') $false
    }

    $includeList = @($include | Sort-Object -Unique)
    $excludeList = @($exclude | Sort-Object -Unique)
    $aliasedList = @($aliased | Sort-Object -Unique)
    $text = if ($includeList.Count) { $includeList -join ', ' }
    elseif ($aliasedList.Count) { $aliasedList -join ', ' }
    elseif ($excludeList.Count) { "All except $($excludeList -join ', ')" }
    else { 'All' }
    @{ Include = $includeList; Exclude = $excludeList; Aliased = $aliasedList; Text = $text }
}
