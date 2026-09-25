<#
    Unit tests for the PKCE, query-string and JWT-claim helpers behind
    Connect-AAC. These exercise pure logic only - no network call, no browser,
    no interactive sign-in - so they run the same in CI as on a workstation.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - PKCE code generation' {
    It 'ConvertTo-AACBase64Url matches the RFC 7636 Appendix B test vector' {
        InModuleScope 'Azure.Admin.Console' {
            $verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'
            $expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'

            $challengeBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($verifier))
            $actualChallenge = ConvertTo-AACBase64Url -Bytes $challengeBytes

            $actualChallenge | Should -BeExactly $expectedChallenge
        }
    }

    It 'New-AACPkceCode produces a verifier of RFC 7636-compliant length and charset' {
        InModuleScope 'Azure.Admin.Console' {
            $pkce = New-AACPkceCode
            $pkce.Verifier.Length | Should -BeGreaterOrEqual 43 -Because 'RFC 7636 requires at least 43 characters'
            $pkce.Verifier.Length | Should -BeLessOrEqual 128 -Because 'RFC 7636 allows at most 128 characters'
            $pkce.Verifier | Should -Match '^[A-Za-z0-9_-]+$' -Because 'the verifier must use only the base64url alphabet'
            $pkce.Method | Should -BeExactly 'S256'
        }
    }

    It 'New-AACPkceCode produces a challenge that is the SHA-256(verifier), base64url-encoded' {
        InModuleScope 'Azure.Admin.Console' {
            $pkce = New-AACPkceCode
            $expectedChallenge = ConvertTo-AACBase64Url -Bytes ([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($pkce.Verifier)))

            $pkce.Challenge | Should -BeExactly $expectedChallenge
        }
    }

    It 'New-AACPkceCode produces a different verifier on every call' {
        InModuleScope 'Azure.Admin.Console' {
            $first = New-AACPkceCode
            $second = New-AACPkceCode

            $first.Verifier | Should -Not -BeExactly $second.Verifier
        }
    }
}

Describe 'Azure Admin Console - OAuth redirect query string parsing' {
    It 'parses a typical successful redirect' {
        InModuleScope 'Azure.Admin.Console' {
            $result = ConvertFrom-AACQueryString -Query '?code=abc123&state=xyz&scope=a%20b'

            $result['code'] | Should -BeExactly 'abc123'
            $result['state'] | Should -BeExactly 'xyz'
            $result['scope'] | Should -BeExactly 'a b'
        }
    }

    It 'parses an error redirect' {
        InModuleScope 'Azure.Admin.Console' {
            $result = ConvertFrom-AACQueryString -Query '?error=access_denied&error_description=The%20user%20cancelled'

            $result['error'] | Should -BeExactly 'access_denied'
            $result['error_description'] | Should -BeExactly 'The user cancelled'
        }
    }

    It 'returns an empty hashtable for an empty query string' {
        InModuleScope 'Azure.Admin.Console' {
            (ConvertFrom-AACQueryString -Query '').Count | Should -Be 0
        }
    }
}

Describe 'Azure Admin Console - JWT claim decoding' {
    It 'decodes the payload claims of a JWT without validating its signature' {
        InModuleScope 'Azure.Admin.Console' {
            $payloadJson = '{"name":"Test User","tid":"11111111-1111-1111-1111-111111111111"}'
            $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payloadJson)
            $payloadBase64Url = ([Convert]::ToBase64String($payloadBytes)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            $token = "header.$payloadBase64Url.signature"

            $claims = ConvertFrom-AACJwt -Token $token

            $claims.name | Should -BeExactly 'Test User'
            $claims.tid | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'throws a clear error for a malformed token' {
        InModuleScope 'Azure.Admin.Console' {
            { ConvertFrom-AACJwt -Token 'not-a-jwt' } | Should -Throw
        }
    }
}
