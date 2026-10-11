<#
    Unit tests for Get-AACSecurityAlert: the alerts built from made-up
    Defender for Cloud rows (Fixtures\ContosoAlert.ps1) - order, resources,
    MITRE tactics, entities, extended properties, recurring alerts, plans -
    the Resource Graph query, and the command with Resource Graph faked: the
    filters, the pipeline, the view and the reports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoAlert.ps1')
    $script:f = Get-AACContosoAlert
    $script:build = { param([hashtable] $Read = $script:f.Read) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $Read; F = $f } { param($R, $F) ConvertTo-AACSecurityAlert -Read $R -SubscriptionName $F.Names } }
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

Describe 'Azure Admin Console - security alerts' {
    BeforeAll { $script:r = & $script:build }

    It 'lists the alerts in scope, open before closed, then by severity, newest first' {
        @($script:r.Alerts | ForEach-Object { "$($_.Severity) | $($_.Status) | $($_.Alert) | $($_.Resource)" }) | Should -Be @(
            'High | Active | Suspicious sign-in | vm-web'
            'High | InProgress | Lateral movement | kv-app'
            'Medium | Active | Port scan | vm-web'
            'Medium | Active | Port scan | vm-web'
            'Low | Active | On-premises malware | contoso-onprem-01'
            'Medium | Resolved | Port scan | vm-web'
            'Low | Dismissed | Old storage access | stdata'
        )
        $script:r.Alerts[0].PSObject.TypeNames | Should -Contain 'AAC.SecurityAlert'
        @($script:r.Alerts.Alert) | Should -Not -Contain 'Elsewhere' -Because 'its subscription is not in scope'
    }

    It 'names the resource, its type, group and subscription, and falls back to the compromised entity' {
        $first = $script:r.Alerts[0]
        "$($first.ResourceType) | $($first.ResourceGroup) | $($first.SubscriptionName) | $($first.Open) | $($first.AgeDays)" | Should -Be 'microsoft.compute/virtualmachines | rg-app | sub-prod | True | 1'
        ($script:r.Alerts | Where-Object Alert -EQ 'Lateral movement').ResourceId | Should -Be $script:f.Kv -Because 'the identifier''s key came back in camelCase'
        $onPrem = $script:r.Alerts | Where-Object Alert -EQ 'On-premises malware'
        "$($onPrem.Resource) | $($onPrem.ResourceId) | $($onPrem.ResourceType)" | Should -Be 'contoso-onprem-01 |  | '
    }

    It 'reads the tactics, techniques, entities, extended properties and remediation' {
        $first = $script:r.Alerts[0]
        $first.Intent | Should -Be 'InitialAccess, CredentialAccess'
        $first.Techniques | Should -Be 'T1078, T1110, T1078.004'
        "$($first.Hosts) | $($first.IpAddresses) | $($first.Accounts)" | Should -Be 'vm-web.contoso.local | 203.0.113.7 | CONTOSO\alice' -Because 'a bare $ref and a repeated IP add nothing'
        $first.Entities | Should -Be 'host: vm-web.contoso.local; ip: 203.0.113.7; account: CONTOSO\alice'
        $first.ExtendedProperties['Attempts'] | Should -Be '42'
        @($first.ExtendedProperties.Keys) | Should -Be @('Attempts', 'Client IP')
        $first.Description | Should -Be "A sign-in from 203.0.113.7 was seen.`nCheck it."
        $first.Remediation | Should -Be "Check the sign-in.`nReset the password."
        ($script:r.Alerts | Where-Object Alert -EQ 'Lateral movement').Entities | Should -Be 'azure-resource: kv-app; account: bob@contoso.com'
        ($script:r.Alerts | Where-Object Alert -EQ 'On-premises malware').Entities | Should -Be 'file: C:\Temp\evil.exe; process: evil.exe -run'
        ($script:r.Alerts | Where-Object Alert -EQ 'Lateral movement').Incident | Should -BeTrue
    }

    It 'counts the occurrences and lists the recurring alerts' {
        @($script:r.Alerts | Where-Object Alert -EQ 'Port scan' | ForEach-Object Occurrences) | Should -Be @(3, 3, 3)
        $script:r.Alerts[0].Occurrences | Should -Be 1
        $script:r.Recurring.Count | Should -Be 1
        "$($script:r.Recurring[0].Alert) | $($script:r.Recurring[0].Resource) | $($script:r.Recurring[0].Occurrences) | $($script:r.Recurring[0].Open)" | Should -Be 'Port scan | vm-web | 3 | 2'
    }

    It 'points out the subscriptions with no Defender plan on, and the stats' {
        $script:r.Notices[0] | Should -BeLike 'No Defender plan is on in 1 subscription(s) (sub-dev)*'
        $s = $script:r.Stats
        "$($s.Alerts) $($s.Open) $($s.High) $($s.Medium) $($s.Incidents) $($s.Resources) $($s.OldestOpen) $($s.Unprotected)" | Should -Be '7 5 2 2 1 3 5 1'
    }

    It 'says when the plans couldn''t be read' {
        $read = @{ Errors = @{ plans = 'denied' }; Rows = @{ alerts = $script:f.Read.Rows.alerts; plans = @() } }
        (& $script:build $read).Notices[0] | Should -BeLike "The Defender plans couldn't be read*"
    }
}

Describe 'Azure Admin Console - security alert query' {
    It 'filters status, severity and age in Resource Graph, and reads the plans' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACSecurityAlertQuery -Status Active, InProgress -Severity High -Days 7 }
        @($q.Keys) | Should -Be @('alerts', 'plans')
        $q.alerts | Should -Match ([regex]::Escape("| where status in~ ('Active', 'InProgress') | where severity in~ ('High') | where time > ago(7d)"))
        $q.alerts | Should -Match 'entities = coalesce\(p\.Entities, p\.entities\)'
        $q.plans | Should -Match 'microsoft.security/pricings'
        $all = InModuleScope 'Azure.Admin.Console' { Get-AACSecurityAlertQuery }
        $all.alerts | Should -Not -Match 'where (status|severity|time) '
    }
}

Describe 'Azure Admin Console - Get-AACSecurityAlert' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:calls.Add(@{ Query = $Query; SubscriptionId = @($SubscriptionId | Where-Object { $_ }); AllowFailure = @($AllowFailure) })
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Prod; name = 'sub-prod'; state = 'Enabled' }, @{ subscriptionId = $script:f.Dev; name = 'sub-dev'; state = 'Enabled' }) }; Errors = @{} } }
            $script:f.Read
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the open alerts by default, every status for one asked for by name, and the plans may fail' {
        $alerts = @(Get-AACSecurityAlert -NoDisplay)
        $alerts.Count | Should -Be 7 -Because 'the status filter is Resource Graph''s, faked here'
        $script:calls[1].Query.alerts | Should -Match ([regex]::Escape("status in~ ('Active', 'InProgress')"))
        $script:calls[1].AllowFailure | Should -Be @('plans')
        $null = Get-AACSecurityAlert -Name '2517001*' -NoDisplay
        $script:calls[-1].Query.alerts | Should -Not -Match 'where status'
        $null = Get-AACSecurityAlert -Status Dismissed -Severity Low -Days 60 -NoDisplay
        $script:calls[-1].Query.alerts | Should -Match ([regex]::Escape("| where status in~ ('Dismissed') | where severity in~ ('Low') | where time > ago(60d)"))
    }

    It 'filters by name, alert type, tactic, incident and resource group' {
        @(Get-AACSecurityAlert -Name '2517001*' -NoDisplay).Alert | Should -Be @('Suspicious sign-in')
        @(Get-AACSecurityAlert -Name 'Port*' -NoDisplay).Count | Should -Be 3 -Because 'the display name matches too'
        @(Get-AACSecurityAlert -AlertType 'VM_Lateral*' -NoDisplay).Alert | Should -Be @('Lateral movement')
        @(Get-AACSecurityAlert -Tactic 'Credential*' -NoDisplay).Alert | Should -Be @('Suspicious sign-in')
        @(Get-AACSecurityAlert -Incident -NoDisplay).Alert | Should -Be @('Lateral movement')
        @(Get-AACSecurityAlert -ResourceGroupName 'RG-DATA' -NoDisplay).Alert | Should -Be @('Lateral movement', 'Old storage access')
    }

    It 'takes resources from the pipeline, by ResourceId or Id, and matches what is under them' {
        @([pscustomobject]@{ ResourceId = $script:f.Kv.ToUpperInvariant() } | Get-AACSecurityAlert -NoDisplay).Alert | Should -Be @('Lateral movement')
        @([pscustomobject]@{ Id = $script:f.VmWeb } | Get-AACSecurityAlert -NoDisplay).Count | Should -Be 4
        @(Get-AACSecurityAlert -ResourceId "/subscriptions/$($script:f.Prod)/resourceGroups/rg-data/" -NoDisplay).Count | Should -Be 2
    }

    It 'shows the alerts at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACSecurityAlert -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Security alerts', '5 open alert(s) on 3 resource(s): 2 high, 2 medium; 1 incident(s) - the oldest is 5 day(s) old', 'No Defender plan is on in 1 subscription(s) (sub-dev)', 'By MITRE ATT&CK tactic', 'Security alerts (7)', 'Suspicious sign-in', 'Recurring alerts (1)') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the alerts to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'alerts.csv'
        $html = Join-Path $TestDrive 'alerts.html'
        $null = & $script:capture { Get-AACSecurityAlert -CsvPath $csv -HtmlPath $html }
        $first = @(Import-Csv -LiteralPath $csv)[0]
        "$($first.Alert) | $($first.Incident) | $($first.ExtendedProperties)" | Should -Be 'Suspicious sign-in | No | Attempts: 42; Client IP: 203.0.113.7'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('alerts', 'recurring')
        ($model.tiles | Where-Object label -EQ 'incidents').filters.Incident | Should -Be 'Yes'
    }
}
