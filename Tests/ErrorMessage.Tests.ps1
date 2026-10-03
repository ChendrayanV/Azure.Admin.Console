<#
    Unit tests for Get-AACErrorMessage: Azure's own reason from an error
    response, in each shape the module meets.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:message = { param([string] $Content) InModuleScope 'Azure.Admin.Console' -Parameters @{ C = $Content } { param($C) Get-AACErrorMessage -Content $C -Fallback 'fallback' } }
}

Describe 'Azure Admin Console - Azure error messages' {
    It 'gives Resource Graph''s real reason from its details, the support line last' {
        $body = '{"error":{"code":"BadRequest","message":"Please provide below info when asking for support: timestamp = 2026-10-02T15:47:17.8507086Z, correlationId = 70d86cbb-fbc8-427a-a51e-92a92bd3cc42.","details":[{"code":"InvalidQuery","message":"Query is invalid. Please refer to the documentation for the Azure Resource Graph service and fix the error before retrying."},{"code":"ParserFailure","message":"ParserFailure","line":1,"characterPositionInLine":52,"token":"kind"}]}}'
        $text = & $script:message $body
        $text | Should -Match '^Query is invalid\. Please refer to the documentation'
        $text | Should -Match 'ParserFailure'
        $text | Should -Match 'correlationId = 70d86cbb.*\.$' -Because 'the support details stay, at the end'
    }

    It 'still reads the query APIs'' nested innererror' {
        $body = '{"error":{"code":"BadArgumentError","message":"The request had some invalid properties","innererror":{"code":"SemanticError","message":"A semantic error occurred.","innererror":{"code":"SEM0100","message":"Failed to resolve table or column expression named ''LAQueryLogs''"}}}}'
        & $script:message $body | Should -Be "The request had some invalid properties A semantic error occurred. Failed to resolve table or column expression named 'LAQueryLogs'"
    }

    It 'reads Resource Manager''s plain error, and falls back when the body isn''t JSON' {
        & $script:message '{"error":{"code":"AuthorizationFailed","message":"The client does not have authorization."}}' | Should -Be 'The client does not have authorization.'
        & $script:message 'Service Unavailable' | Should -Be 'fallback'
    }
}
