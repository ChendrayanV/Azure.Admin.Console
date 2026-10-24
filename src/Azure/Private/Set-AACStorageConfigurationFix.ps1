function Set-AACStorageConfigurationFix {
    <#
    .SYNOPSIS
        A copy of a storage account configuration with the automatic PSRule
        fixes (Get-AACStorageRuleFix, Kind Auto) applied - what
        -UseSuggestedFix deploys, and the configuration snippet the view
        suggests.
    .DESCRIPTION
        Each fix's Setting is a path in the configuration: allowSharedKeyAccess,
        networkAcls.defaultAction, blobServices.containers[name=raw].publicAccess.
        Missing levels are created; a container given only by its name
        becomes @{ name = ... }. The input configuration is not changed.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a changed copy of a hashtable; nothing outside the process changes.')]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Configuration,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Fix
    )

    # A deep copy: hashtables and lists rebuilt, values kept.
    $copy = {
        param($Value)
        if ($Value -is [System.Collections.IDictionary]) { $out = [ordered]@{}; foreach ($key in $Value.Keys) { $out[[string]$key] = & $copy $Value[$key] }; return , $out }
        if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) { return , @(foreach ($item in $Value) { & $copy $item }) }
        $Value
    }
    $result = & $copy $Configuration
    foreach ($item in @($Fix | Where-Object { $_.Kind -eq 'Auto' -and $_.Setting })) {
        $parts = @([regex]::Matches($item.Setting, '[^.\[\]]+(\[name=[^\]]+\])?') | ForEach-Object { $_.Value })
        $node = $result
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $part = $parts[$i]
            $last = $i -eq $parts.Count - 1
            if ($part -match '^(?<key>[^\[]+)\[name=(?<name>[^\]]+)\]$') {
                # An item of a list, by its name (a string item becomes a hashtable).
                $key = $Matches['key']; $name = $Matches['name']
                $list = @(if ($node.Contains($key)) { $node[$key] })
                $index = -1
                for ($j = 0; $j -lt $list.Count; $j++) {
                    $entryName = if ($list[$j] -is [System.Collections.IDictionary]) { [string]$list[$j]['name'] } else { [string]$list[$j] }
                    if ($entryName -eq $name) { $index = $j; break }
                }
                if ($index -lt 0) { $list += [ordered]@{ name = $name }; $index = $list.Count - 1 }
                if ($list[$index] -isnot [System.Collections.IDictionary]) { $list[$index] = [ordered]@{ name = [string]$list[$index] } }
                $node[$key] = $list
                $node = $list[$index]
                continue
            }
            if ($last) { $node[$part] = $item.Value; break }
            if ($node[$part] -isnot [System.Collections.IDictionary]) {
                # blobServices given replaces AVM's default blob settings whole:
                # start from them, so one fix doesn't drop the others.
                $node[$part] = if ($i -eq 0 -and $part -eq 'blobServices') { [ordered]@{ containerDeleteRetentionPolicyEnabled = $true; containerDeleteRetentionPolicyDays = 7; deleteRetentionPolicyEnabled = $true; deleteRetentionPolicyDays = 6 } } else { [ordered]@{} }
            }
            $node = $node[$part]
        }
    }
    $result
}
