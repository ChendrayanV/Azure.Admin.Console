function ConvertTo-AACPSObject {
    <#
    .SYNOPSIS
        Turns parsed JSON hashtables (ConvertFrom-Json -AsHashtable) into
        PSCustomObjects, all the way down.
    .DESCRIPTION
        PSRule for Azure's PowerShell rules read child settings as object
        properties ($TargetObject.resources), which hashtables don't have, so
        its input must be PSCustomObjects. ConvertFrom-Json can't make them
        straight from ARM's JSON when a resource has keys differing only by
        case ('Owner' and 'owner' tags): PSCustomObject property names are
        case-insensitive. Here the first of such keys wins and the others
        are dropped.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject], [object[]])]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        $InputObject
    )

    process {
        if ($InputObject -is [System.Collections.IDictionary]) {
            $object = [pscustomobject]@{}
            foreach ($key in $InputObject.Keys) {
                $name = [string]$key
                if ($null -eq $object.PSObject.Properties[$name]) {
                    $object.PSObject.Properties.Add([psnoteproperty]::new($name, (ConvertTo-AACPSObject -InputObject $InputObject[$key])))
                }
            }
            return $object
        }
        if ($InputObject -is [System.Collections.IList]) {
            # The comma keeps an array (even of one) an array.
            return , @(foreach ($item in $InputObject) { ConvertTo-AACPSObject -InputObject $item })
        }
        $InputObject
    }
}
