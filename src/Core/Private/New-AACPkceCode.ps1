function New-AACPkceCode {
    <#
    .SYNOPSIS
        Generates an RFC 7636 PKCE code_verifier / code_challenge pair for the S256 method.
    .DESCRIPTION
        The code_verifier is 32 cryptographically random bytes, base64url-encoded
        (43 characters - within RFC 7636's required 43-128 character range). The
        code_challenge is the base64url-encoded SHA-256 hash of that verifier,
        exactly as the spec defines the "S256" transform.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a random verifier and its challenge; nothing changes.')]
    [OutputType([pscustomobject])]
    param()

    $verifierBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($verifierBytes)
    $verifier = ConvertTo-AACBase64Url -Bytes $verifierBytes

    $challengeBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($verifier))
    $challenge = ConvertTo-AACBase64Url -Bytes $challengeBytes

    [pscustomobject]@{
        Verifier  = $verifier
        Challenge = $challenge
        Method    = 'S256'
    }
}
