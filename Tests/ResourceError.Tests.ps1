<#
    Unit tests for Get-AACResourceError: made-up Activity Log events - access
    denied, a deployment failing on a quota, a policy deny, no capacity, a
    lock, throttling, an unparseable error - read into one error per
    correlation ID with its category and fix, and the command with the
    Activity Log faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoResourceError.ps1')
    $f = Get-AACContosoResourceError
    $script:sub = $f.Sub
    $script:events = $f.Events
    $script:names = $f.Names
    $script:build = { $e = $script:events; $n = $script:names; InModuleScope 'Azure.Admin.Console' -Parameters @{ E = $e; N = $n } { param($E, $N) ConvertTo-AACResourceError -Entry $E -SubscriptionName $N } }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 200
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - resource errors' {
    BeforeAll { $script:r = & $script:build }

    It 'keeps one error per correlation ID, failed or denied by policy, in scope, newest first' {
        @($script:r.Errors | ForEach-Object { "$($_.Category) | $($_.ErrorCode) | $($_.Resource) | $($_.Caller) | $($_.Events)" }) | Should -Be @(
            'Authorization | AuthorizationFailed | vm1 | sp-pipeline | 1'
            'Quota | QuotaExceeded | main | alice@contoso.com | 1'
            'Policy | RequestDisallowedByPolicy | st1 | bob@contoso.com | 2'
            'Capacity | SkuNotAvailable | vm1 | alice@contoso.com | 1'
            'Lock | ScopeLocked | st1 | alice@contoso.com | 1'
            'Throttling | TooManyRequests | vm1 | sp-monitor | 1'
            'Other | InternalServerError | st1 | alice@contoso.com | 1'
        )
        $script:r.Errors[0].PSObject.TypeNames | Should -Contain 'AAC.ResourceError'
    }

    It 'reads the refused action and scope, the innermost deployment error, and the fix' {
        $auth = $script:r.Errors[0]
        "$($auth.Action) | $($auth.Scope -replace '^.*/', '') | $($auth.ClientIp) | $($auth.Subscription)" | Should -Be 'Microsoft.Compute/virtualMachines/write | vm1 | 203.0.113.9 | sub-prod'
        $auth.Remediation | Should -BeLike 'Grant the caller a role*'
        $script:r.Errors[1].Message | Should -BeLike 'Operation could not be completed as it results in exceeding approved Total Regional Cores quota.'
        $script:r.Errors[1].Remediation | Should -BeLike 'Request a quota increase*'
        ($script:r.Errors | Where-Object ErrorCode -EQ 'InternalServerError').Message | Should -Be 'Something odd happened'
        "$($script:r.Stats.Errors) $($script:r.Stats.Authorization) $($script:r.Stats.Policy) $($script:r.Stats.Quota) $($script:r.Stats.Deployments) $($script:r.Stats.Callers)" | Should -Be '7 1 1 2 1 4'
    }
}

Describe 'Azure Admin Console - Get-AACResourceError' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-prod'; state = 'Enabled' }) }; Errors = @{} } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) { $script:uris.Add($u); $answers[$u] = @{ Status = 200; Error = $null; Body = $null; Items = $script:events } }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads each subscription''s Activity Log for the window, and filters by kind, caller, type and resource group' {
        @(Get-AACResourceError -Hours 48 -ResourceGroupName 'rg-app' -NoDisplay).Resource | Should -Be @('vm1', 'main', 'vm1', 'vm1')
        $script:uris[0] | Should -Match ([regex]::Escape('/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&$filter=eventTimestamp%20ge%20'))
        $script:uris[0] | Should -Match ([regex]::Escape("resourceGroupName%20eq%20%27rg-app%27"))
        @(Get-AACResourceError -Category Authorization, Policy -NoDisplay).ErrorCode | Should -Be @('AuthorizationFailed', 'RequestDisallowedByPolicy')
        @(Get-AACResourceError -Caller 'sp-*' -NoDisplay).Caller | Should -Be @('sp-pipeline', 'sp-monitor')
        @(Get-AACResourceError -ResourceType '*/storageaccounts' -NoDisplay).Count | Should -Be 3
    }

    It 'shows the errors at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACResourceError -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Resource errors', '7 failed operation(s) by 4 caller(s): 1 access denied, 1 policy deny, 2 quota or capacity', 'By error code (7)', 'Failed operations (7)', 'AuthorizationFailed') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the errors to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'errors.csv'
        $html = Join-Path $TestDrive 'errors.html'
        $null = & $script:capture { Get-AACResourceError -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].ErrorCode | Should -Be 'AuthorizationFailed'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('codes', 'errors')
    }
}
