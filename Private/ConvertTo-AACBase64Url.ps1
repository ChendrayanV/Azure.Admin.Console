function ConvertTo-AACBase64Url {
    <#
    .SYNOPSIS
        Base64url-encodes a byte array (RFC 4648 §5): standard base64 with '+'
        and '/' replaced by '-' and '_', and no '=' padding.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [byte[]] $Bytes
    )

    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
