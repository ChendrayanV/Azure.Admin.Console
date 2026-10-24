function ConvertFrom-AACJwt {
    <#
    .SYNOPSIS
        Decodes the claims (payload) of a JWT, without validating its signature.
    .DESCRIPTION
        This is for reading display-only information out of an id_token (like the
        signed-in account name and tenant ID) after it has already been received
        directly from Microsoft's token endpoint over TLS. It is not a general
        purpose token validator and must never be used to authorize anything on
        its own - the access_token itself is what the resource server (Azure
        Resource Manager) validates.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Token
    )

    $segments = $Token.Split('.')
    if ($segments.Count -lt 2) {
        throw 'The supplied token is not a well-formed JWT (expected at least a header and a payload segment).'
    }

    $payload = $segments[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
    }

    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
    return $json | ConvertFrom-Json
}
