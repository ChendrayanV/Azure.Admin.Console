function ConvertTo-AACFlatObject {
    <#
    .SYNOPSIS
        Flattens parsed JSON into one level: 'properties.networkAcls.defaultAction'
        -> 'Deny'.
    .DESCRIPTION
        Dictionaries become dotted names. A list of plain values becomes one
        value, joined with '; '. A list of objects becomes 'name[0].x',
        'name[1].x'... for its first -MaxItems items, plus 'name.count', so a
        resource with 300 IP rules doesn't turn into 300 columns. Empty values
        are left out.

        Returns an ordered dictionary (name -> value). -Prefix starts every name.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()]
        $InputObject,

        [string] $Prefix = '',

        [ValidateRange(0, 100)]
        [int] $MaxItems = 3
    )

    $flat = [ordered]@{}
    $walk = {
        param($Value, [string] $Path)
        if ($null -eq $Value) { return }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in $Value.Keys) { & $walk $Value[$key] $(if ($Path) { "$Path.$key" } else { [string]$key }) }
            return
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $items = @($Value)
            if (-not $items.Count) { return }
            if (@($items | Where-Object { $_ -is [System.Collections.IDictionary] -or ($_ -is [System.Collections.IEnumerable] -and $_ -isnot [string]) }).Count) {
                $flat["$Path.count"] = $items.Count
                for ($i = 0; $i -lt [Math]::Min($items.Count, $MaxItems); $i++) { & $walk $items[$i] "$Path[$i]" }
            }
            else { $flat[$Path] = ($items | ForEach-Object { [string]$_ }) -join '; ' }
            return
        }
        if ($Value -is [string] -and -not $Value) { return }
        $flat[$Path] = $Value
    }
    & $walk $InputObject $Prefix
    $flat
}
