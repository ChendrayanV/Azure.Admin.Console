<#
    Unit tests for Get-AACChangeHistory: the timeline built from a made-up
    Contoso morning (Fixtures\ContosoChange.ps1) - operations grouped by
    correlation ID, property changes before and after, risk, origin, how to
    undo, incidents that followed - and the command with the Activity Log
    and Resource Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoChange.ps1')
    $script:f = Get-AACContosoChange
    $script:history = { param([hashtable] $More = @{}) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $f; M = $More } { param($F, $M) ConvertTo-AACChangeHistory -ActivityEvent $F.Events -Change $F.Changes -Alert $F.Alerts -Health $F.Health -SubscriptionName $F.Names @M } }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 220
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - the change history' {
    BeforeAll { $script:r = & $script:history }

    It 'makes one change per operation - writes, deletes and actions, newest first - leaving out reads, Policy and failures' {
        @($script:r.Changes | ForEach-Object { "$($_.Time.ToString('HH:mm')) $($_.Category) $($_.Resource) $($_.Severity) $($_.Origin)" }) | Should -Be @(
            '11:00 Delete allow-https High Manual'
            '10:00 Action stdata High Manual'
            '09:00 Update vm-web-1 High Manual'
            '07:00 Create stnew Low Automation'
            '06:00 Delete kv-old High Automation'
        )
        $script:r.Changes[0].PSObject.TypeNames | Should -Contain 'AAC.ChangeRecord'
        "$($script:r.Changes[2].Caller) $($script:r.Changes[2].ClientIp) $($script:r.Changes[2].CorrelationId) $($script:r.Changes[2].Status)" | Should -Be 'ada@contoso.example 203.0.113.7 c1 Succeeded'
    }

    It 'shows what the caller changed - before and after - and how to set it back' {
        $vm = $script:r.Changes | Where-Object Resource -EQ 'vm-web-1'
        $vm.Detail | Should -Be 'properties.hardwareProfile.vmSize: Standard_D2s_v5 -> Standard_D4s_v5' -Because 'the provisioning state is Azure''s, not the caller''s'
        $vm.Revert | Should -Be 'Set back: properties.hardwareProfile.vmSize = Standard_D2s_v5'
        ($script:r.Changes | Where-Object Resource -EQ 'kv-old').Revert | Should -BeLike 'Recover the soft-deleted vault*'
        ($script:r.Changes | Where-Object Resource -EQ 'allow-https').Effort | Should -Be 'High'
        ($script:r.Changes | Where-Object Resource -EQ 'stdata').Revert | Should -BeLike 'Not reversible: the keys were read*'
    }

    It 'links the alert and health event that followed a change, and raises its risk' {
        $vm = $script:r.Changes | Where-Object Resource -EQ 'vm-web-1'
        $vm.RelatedIncidents | Should -Be 2
        $vm.Impact | Should -Be 'Followed by: Alert CPU over 90% (Sev1) at 09:10; Resource Health Degraded (Sev2) at 09:15'
        $vm.Severity | Should -Be 'High' -Because 'a resize is Medium, but an incident followed it'
        $quiet = & $script:history @{ CorrelationMinutes = 5 }
        ($quiet.Changes | Where-Object Resource -EQ 'vm-web-1').Severity | Should -Be 'Medium' -Because 'nothing happened in the 5 minutes after it'
        @($script:r.Incidents).Count | Should -Be 2
    }

    It 'filters by resource group, resource type and caller (wildcards), and keeps failures when asked' {
        @((& $script:history @{ ResourceGroupName = @('rg-a*') }).Changes.Resource) | Should -Be @('stdata', 'vm-web-1', 'stnew')
        @((& $script:history @{ ResourceType = @('microsoft.keyvault/*') }).Changes.Resource) | Should -Be @('kv-old')
        @((& $script:history @{ Caller = @('bob@*') }).Changes.Resource) | Should -Be @('allow-https')
        $failed = (& $script:history @{ IncludeFailed = $true }).Changes | Where-Object Resource -EQ 'app-web'
        "$($failed.Status) $($failed.Severity)" | Should -Be 'Failed Info'
    }
}

Describe 'Azure Admin Console - Get-AACChangeHistory' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        $script:queries = $null
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            $script:queries = $Query
            @{ Rows = @{ changes = $script:f.Changes; alerts = $script:f.Alerts; health = $script:f.Health }; Errors = @{ alerts = '' } }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) { $script:uris.Add($u); $answers[$u] = @{ Status = 200; Items = @($script:f.Events); Error = '' } }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the Activity Log for the window, then the property changes and incidents' {
        $changes = @(Get-AACChangeHistory -StartTime '2026-10-09 00:00Z' -EndTime '2026-10-09 12:00Z' -ResourceGroupName 'rg-app' -NoDisplay)
        $decoded = [System.Uri]::UnescapeDataString($script:uris[0])
        $decoded | Should -BeLike "/subscriptions/$($script:f.Subscription)/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=eventTimestamp ge '2026-10-09T00:00:00Z' and eventTimestamp le '2026-10-09T12:00:00Z' and resourceGroupName eq 'rg-app'&`$select=*"
        $script:queries.alerts | Should -BeLike '*where fired between (datetime(2026-10-09T00:00:00Z) .. datetime(2026-10-09T14:00:00Z))*' -Because 'incidents up to -CorrelationMinutes after the window count'
        @($changes.Resource) | Should -Be @('stdata', 'vm-web-1', 'stnew')
        { Get-AACChangeHistory -StartTime '2026-10-09 12:00' -EndTime '2026-10-09 10:00' -NoDisplay } | Should -Throw '*must be before*'
    }

    It 'shows the timeline at the prompt, and writes the reports' {
        $text = (& $script:capture { Get-AACChangeHistory -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Change history', 'x 5 change(s) by 4 caller(s): 2 delete(s), 4 high risk, 3 made by hand - 1 followed by an alert or health event', 'Timeline (5)', 'vm-web-1', 'Standard_D2s_v5 -> Standard_D4s_v5', 'Alerts and health events (2)', 'Changes by caller') { $text | Should -Match ([regex]::Escape($expected)) }
        $html = Join-Path $TestDrive 'changes.html'
        $null = & $script:capture { Get-AACChangeHistory -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('changes', 'incidents')
        ($model.tiles | Where-Object label -EQ 'made by hand').filters.Origin | Should -Be 'Manual'
    }
}
