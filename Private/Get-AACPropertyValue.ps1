function Get-AACPropertyValue {
    <#
    .SYNOPSIS
        Safely reads a possibly-absent property from an object, without
        tripping Set-StrictMode -Version Latest.
    .DESCRIPTION
        ConvertFrom-Json (used under the hood by Invoke-RestMethod) only
        creates a property for a key that was actually present in the JSON -
        an optional field that the server omitted, like Azure Resource
        Manager's "nextLink" (present only when there is a next page), the
        token endpoint's "refresh_token"/"id_token" (present only when
        offline_access/openid were granted), or a JWT claim like
        "preferred_username" (not guaranteed by every tenant/token config),
        does not exist on the resulting object at all - not just hold $null.

        Ordinary dot-notation property access ($obj.name) throws under
        Set-StrictMode -Version Latest when the property doesn't exist.
        $obj.PSObject.Properties[<name>] is a safe, explicit lookup that
        returns $null instead, which is what this wraps.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}
