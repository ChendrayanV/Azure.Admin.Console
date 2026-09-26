<#
    Unit tests for Connect-AAC, Disconnect-AAC and the token helper. The
    browser (Start-Process) and Microsoft's token endpoint (Invoke-RestMethod)
    are mocked; everything between them runs for real - the PKCE code, the
    localhost listener receiving the redirect, state validation and the token
    exchange.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - sign-in' {
    BeforeAll {
        # Keep the real Connect-AAC sign-in (if any); the tests replace it.
        $script:savedSession = $global:AACSession

        $script:base64Url = { param([string] $Text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
        $script:idToken = "$(& $script:base64Url '{"alg":"none"}').$(& $script:base64Url '{"preferred_username":"tester@contoso.com","tid":"72f988bf-0000-0000-0000-000000000000"}').sig"

        # The fake browser: reads the sign-in URL Connect-AAC opens and calls
        # its localhost redirect with a code - or whatever the test asks for.
        $global:AACTestBrowserReply = { param($State) "code=test-code&state=$([uri]::EscapeDataString($State))" }
    }

    AfterAll {
        $global:AACSession = $script:savedSession
        Remove-Variable -Name AACTestBrowserReply, AACTestAuthorizeUrl, AACTestTokenBody, AACTestBrowser, AACTestIdToken -Scope Global -ErrorAction Ignore
    }

    BeforeEach {
        $global:AACSession = $null
        $global:AACTestIdToken = $script:idToken

        Mock -ModuleName 'Azure.Admin.Console' -CommandName Write-AACRule -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Write-AACMarkup -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACPanel -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Process -MockWith {
            $global:AACTestAuthorizeUrl = $FilePath
            $redirect = [uri]::UnescapeDataString([regex]::Match($FilePath, 'redirect_uri=([^&]+)').Groups[1].Value)
            $state = [uri]::UnescapeDataString([regex]::Match($FilePath, 'state=([^&]+)').Groups[1].Value)
            $global:AACTestBrowser = [System.Net.Http.HttpClient]::new()
            # Not awaited: Connect-AAC is about to wait on its listener.
            $null = $global:AACTestBrowser.GetAsync("$($redirect)?$(& $global:AACTestBrowserReply $state)")
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -ParameterFilter { $Uri -like '*/oauth2/v2.0/token' } -MockWith {
            $global:AACTestTokenBody = $Body
            [pscustomobject]@{ access_token = 'access-123'; refresh_token = 'refresh-456'; expires_in = 3600; id_token = $global:AACTestIdToken }
        }
    }

    It 'signs in with PKCE: the listener gets the code, the verifier matches the challenge, the session is stored' {
        $session = Connect-AAC -TenantId 'contoso.onmicrosoft.com' -TimeoutSeconds 30 -PassThru

        $session.Account | Should -BeExactly 'tester@contoso.com'
        $session.TenantId | Should -BeExactly '72f988bf-0000-0000-0000-000000000000'
        $session.AccessToken | Should -BeExactly 'access-123'
        $session.RefreshToken | Should -BeExactly 'refresh-456'
        $session.ExpiresOn | Should -BeGreaterThan (Get-Date).AddMinutes(55)
        $global:AACSession.AccessToken | Should -BeExactly 'access-123'

        $global:AACTestAuthorizeUrl | Should -BeLike 'https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/authorize?*code_challenge_method=S256*'
        $global:AACTestTokenBody.grant_type | Should -BeExactly 'authorization_code'
        $global:AACTestTokenBody.code | Should -BeExactly 'test-code'
        # RFC 7636: challenge = base64url(SHA-256(verifier)).
        $challenge = [uri]::UnescapeDataString([regex]::Match($global:AACTestAuthorizeUrl, 'code_challenge=([^&]+)').Groups[1].Value)
        $hash = [System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes($global:AACTestTokenBody.code_verifier))
        [Convert]::ToBase64String($hash).TrimEnd('=').Replace('+', '-').Replace('/', '_') | Should -BeExactly $challenge
    }

    It 'reports a sign-in the user cancelled' {
        $global:AACTestBrowserReply = { param($State) "error=access_denied&error_description=User%20cancelled&state=$([uri]::EscapeDataString($State))" }
        try {
            { Connect-AAC -TimeoutSeconds 30 } | Should -Throw '*Sign-in failed: User cancelled*'
            $global:AACSession | Should -BeNullOrEmpty
        }
        finally {
            $global:AACTestBrowserReply = { param($State) "code=test-code&state=$([uri]::EscapeDataString($State))" }
        }
    }

    It 'refuses a redirect whose state does not match (CSRF)' {
        $global:AACTestBrowserReply = { param($State) 'code=test-code&state=forged' }
        try {
            { Connect-AAC -TimeoutSeconds 30 } | Should -Throw '*state validation*'
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -Times 0 -Exactly -Because 'no token is requested for a forged redirect'
        }
        finally {
            $global:AACTestBrowserReply = { param($State) "code=test-code&state=$([uri]::EscapeDataString($State))" }
        }
    }

    It 'Disconnect-AAC forgets the sign-in, and is harmless when signed out' {
        $global:AACSession = [pscustomobject]@{ Account = 'tester@contoso.com'; AccessToken = 'x' }
        Disconnect-AAC
        $global:AACSession | Should -BeNullOrEmpty
        { Disconnect-AAC } | Should -Not -Throw
    }
}

Describe 'Azure Admin Console - access token' {
    BeforeAll { $script:savedSession = $global:AACSession }
    AfterAll { $global:AACSession = $script:savedSession }

    It 'needs a sign-in' {
        $global:AACSession = $null
        { InModuleScope 'Azure.Admin.Console' { Get-AACAccessToken } } | Should -Throw '*Connect-AAC*'
    }

    It 'returns the current token while it is valid' {
        $global:AACSession = [pscustomobject]@{ AccessToken = 'current'; RefreshToken = 'r'; ExpiresOn = (Get-Date).AddHours(1); TenantId = 't'; ClientId = 'c'; Scope = @('s') }
        InModuleScope 'Azure.Admin.Console' { Get-AACAccessToken } | Should -BeExactly 'current'
    }

    It 'refreshes an expiring token with the refresh token' {
        $global:AACSession = [pscustomobject]@{ AccessToken = 'old'; RefreshToken = 'r1'; ExpiresOn = (Get-Date).AddSeconds(30); TenantId = 't'; ClientId = 'c'; Scope = @('s') }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -MockWith {
            [pscustomobject]@{ access_token = 'new'; refresh_token = 'r2'; expires_in = 3600 }
        }
        InModuleScope 'Azure.Admin.Console' { Get-AACAccessToken } | Should -BeExactly 'new'
        $global:AACSession.RefreshToken | Should -BeExactly 'r2'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -ParameterFilter { $Body.grant_type -eq 'refresh_token' -and $Body.refresh_token -eq 'r1' } -Times 1 -Exactly
    }
}
