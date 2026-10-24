function Merge-AACObject {
    <#
    .SYNOPSIS
        A copy of -Base with -Overlay's values laid over it, at every level of
        nested dictionaries; lists and plain values in -Overlay replace
        -Base's.
    .DESCRIPTION
        Keys match case-insensitively; -Overlay's spelling wins. Neither input
        is changed. Used to send a resource's current settings with the
        desired ones merged in, so the settings a deployment doesn't manage
        stay as they are.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()]
        [System.Collections.IDictionary] $Base,

        [AllowNull()]
        [System.Collections.IDictionary] $Overlay
    )

    $out = [ordered]@{}
    if ($Base) { foreach ($key in $Base.Keys) { $out[[string]$key] = $Base[$key] } }
    if ($Overlay) {
        foreach ($key in $Overlay.Keys) {
            $existing = @($out.Keys | Where-Object { $_ -ieq [string]$key }) | Select-AACFirst 1
            $value = $Overlay[$key]
            if ($null -ne $existing) {
                $old = $out[$existing]
                $out.Remove($existing)
                $out[[string]$key] = if ($value -is [System.Collections.IDictionary] -and $old -is [System.Collections.IDictionary]) { Merge-AACObject -Base $old -Overlay $value } else { $value }
            }
            else { $out[[string]$key] = $value }
        }
    }
    $out
}
