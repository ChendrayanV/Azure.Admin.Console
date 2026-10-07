<#
    Unit tests for Invoke-AACDefenderAssessment: what it reads (Resource Graph
    queries and REST calls by section), the assessment of a made-up Contoso
    tenant's Defender for Cloud (Fixtures\ContosoDefender.ps1) - recommendations,
    attack paths, alerts, inventory, vulnerabilities, plans, settings,
    compliance and the findings - and the command with Azure mocked: the
    object, the view, the CSV files and the tabbed HTML report.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoDefender.ps1')
    $script:f = Get-AACContosoDefender
    $script:assess = {
        param([hashtable] $With = @{})
        $p = @{ Rows = $script:f.Rows; Rest = $script:f.Rest; SubscriptionName = $script:f.Names; Now = $script:f.Now }
        foreach ($k in $With.Keys) { $p[$k] = $With[$k] }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $p } { param($P) ConvertTo-AACDefenderAssessment @P }
    }
    $script:a = & $script:assess
    $script:findingsOf = { param([string] $Area, $From = $script:a) @($From.Findings | Where-Object Area -EQ $Area | ForEach-Object { "$($_.Severity) $($_.Finding) | $($_.SubscriptionName)" }) }
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
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - what the Defender for Cloud assessment reads' {
    It 'reads every section by default - each Resource Graph query with an id column, so it is paged' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACDefenderAssessmentQuery }
        @($q.Graph.Keys) | Should -Be @('subscriptions', 'Plans', 'Scores', 'Controls', 'ControlAssessments', 'RecommendationSummary', 'Unhealthy', 'InventorySummary', 'AttackPaths', 'Alerts', 'Vulnerabilities', 'Standards', 'ComplianceControls', 'ComplianceAssessments')
        foreach ($name in $q.Graph.Keys) { $q.Graph[$name] | Should -Match '\bid\b' -Because "$name must be pageable" }
        @($q.Rest.Keys | Sort-Object) | Should -Be @('Connectors', 'Contacts', 'Jit', 'Settings', 'Suppression')
        $q.Rest['Contacts'] -f 'abc' | Should -Be '/subscriptions/abc/providers/Microsoft.Security/securityContacts?api-version=2023-12-01-preview'
    }

    It 'reads only what the sections need, and the alerts of -AlertDays' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACDefenderAssessmentQuery -Section Alerts -AlertDays 7 }
        @($q.Graph.Keys) | Should -Be @('subscriptions', 'Plans', 'Alerts')
        $q.Graph['Alerts'] | Should -Match 'ago\(7d\)'
        @($q.Rest.Keys) | Should -Be @('Suppression')
    }
}

Describe 'Azure Admin Console - the Defender for Cloud assessment' {
    It 'lists every recommendation with its unhealthy, healthy and not applicable resources, highest risk first' {
        $r = $script:a.Recommendations
        @($r.Recommendation) | Should -Be @('Management ports should be closed on your virtual machines', 'Storage accounts should restrict network access', 'Something already healthy')
        "$($r[0].Status) $($r[0].RiskLevel) $($r[0].UnhealthyResources)/$($r[0].HealthyResources) $($r[0].HealthyPercent)% $($r[0].AttackPaths) $($r[0].Control)" | Should -Be 'Unhealthy Critical 2/1 33% 1 Secure management ports'
        $r[0].Description | Should -Be 'Open ports invite attacks.' -Because 'the HTML is turned into plain text'
        $r[0].Remediation | Should -Be "1. Go to the VM`n2. Close the port"
        $r[0].Link | Should -Be 'https://portal.azure.com/#blade/k-ports'
        $r[2].Status | Should -Be 'Healthy'
    }

    It 'lists each unhealthy resource with its risk level and factors, Critical first' {
        $u = $script:a.UnhealthyResources
        @($u.Resource) | Should -Be @('vm1', 'vm2', 'st1')
        "$($u[0].RiskLevel) | $($u[0].RiskFactors) | $($u[0].Type) | $($u[0].ResourceGroup) | $($u[0].SubscriptionName)" | Should -Be 'Critical | Internet exposure, Vulnerabilities | microsoft.compute/virtualmachines | rg-web | sub-prod'
    }

    It 'follows an attack path''s connections from the entry point to the target' {
        $p = $script:a.AttackPaths[0]
        $p.Path | Should -Be 'Internet → vm1 (virtualmachine) → st2 (storageaccount)'
        "$($p.EntryPoint) | $($p.Target) | $($p.Steps) | $($p.RiskLevel) | $($p.Tactics)" | Should -Be 'Internet | st2 (storageaccount) | 3 | Critical | Initial Access, Lateral Movement'
        $p.Remediation | Should -Be "Close port 22 on vm1.`nRemove the VM identity's access to st2."
    }

    It 'lists the alerts, active ones first, with their age, techniques and remediation steps' {
        $al = $script:a.Alerts
        @($al.Alert) | Should -Be @('SuspiciousLogin', 'PortScan', 'OldThing')
        "$($al[0].Active) $($al[0].AgeDays) $($al[0].Resource) $($al[0].Techniques)" | Should -Be 'Yes 3 vm1 T1078, T1078.004'
        $al[0].Description | Should -Be 'SuspiciousLogin detected.'
        $al[0].Remediation | Should -Be "Check the sign-ins.`nReset the password."
        $al[2].Active | Should -Be 'No'
    }

    It 'builds the inventory: the plan protecting each resource, and its vulnerabilities, alerts and attack paths' {
        $vm1 = $script:a.Inventory | Where-Object Resource -EQ 'vm1'
        "$($vm1.Plan) $($vm1.PlanState) $($vm1.Status) $($vm1.High) $($vm1.Vulnerabilities) $($vm1.Alerts) $($vm1.AttackPaths)" | Should -Be 'Servers On Unhealthy 1 1 2 1'
        ($script:a.Inventory | Where-Object Resource -EQ 'st2').PlanState | Should -Be 'Off'
        $script:a.Inventory[0].Resource | Should -Be 'vm1' -Because 'resources on attack paths come first'
    }

    It 'lists the vulnerabilities with their CVEs and the recommendation they belong to' {
        $v = $script:a.Vulnerabilities[0]
        "$($v.Vulnerability) | $($v.CVEs) | $($v.Patchable) | $($v.Resource) | $($v.Recommendation)" | Should -Be 'OpenSSL buffer overflow | CVE-2026-1234 | Yes | vm1 | Management ports should be closed on your virtual machines'
    }

    It 'lists the plans with their sub-plan, extensions and the resources they cover' {
        $servers = $script:a.Plans | Where-Object { $_.SubscriptionName -eq 'sub-prod' -and $_.Plan -eq 'Servers' }
        "$($servers.State) $($servers.SubPlan) $($servers.Extensions) $($servers.Resources)" | Should -Be 'On P2 AgentlessVmScanning 2'
        ($script:a.Plans | Where-Object { $_.SubscriptionName -eq 'sub-dev' -and $_.Plan -eq 'Storage' }).Resources | Should -Be 1
    }

    It 'flags the plans: off for resources that need them, CSPM and Resource Manager off, Servers Plan 1' {
        & $script:findingsOf 'Plans' | Sort-Object | Should -Be @(
            'High Defender for Storage is off | sub-dev'
            'High Defender for Storage is off | sub-prod'
            'Low Defender for Servers on Plan 1 | sub-dev'
            'Medium Defender CSPM is off | sub-dev'
            'Medium Defender for Resource Manager is off | sub-dev'
        )
    }

    It 'flags the notifications and integrations, from the REST settings' {
        & $script:findingsOf 'Notifications' | Should -Be @('Medium No security contact e-mail | sub-dev')
        & $script:findingsOf 'Integrations' | Sort-Object | Should -Be @('High Defender for Endpoint integration is off | sub-dev', 'Low Defender for Cloud Apps integration is off | sub-prod')
        $alertMail = $script:a.Settings | Where-Object { $_.SubscriptionName -eq 'sub-prod' -and $_.Setting -eq 'Alert e-mails' }
        "$($alertMail.Value) | $($alertMail.Status)" | Should -Be 'On, Medium and above | Good'
        ($script:a.Settings | Where-Object { $_.SubscriptionName -eq 'sub-prod' -and $_.Setting -eq 'Notify roles' }).Value | Should -Be 'Owner'
    }

    It 'flags attack paths, alerts, the secure score, suppression rules and just-in-time ports' {
        & $script:findingsOf 'Attack paths' | Should -Be @('Critical Critical attack path | sub-prod')
        & $script:findingsOf 'Alerts' | Should -Be @('High High-severity alerts still active | sub-prod', 'Medium Medium-severity alerts active for over a week | sub-prod')
        & $script:findingsOf 'Secure score' | Should -Be @('Medium Secure score 60% | sub-prod')
        & $script:findingsOf 'Suppression' | Should -Be @('Low Alert suppression rule with no expiry | sub-prod')
        & $script:findingsOf 'Just-in-time' | Should -Be @('Medium Just-in-time port open to any source | sub-prod')
        $script:a.Findings[0].Severity | Should -Be 'Critical' -Because 'the most severe come first'
    }

    It 'reads the connectors, just-in-time ports and suppression rules - and says what it couldn''t read' {
        "$($script:a.Connectors[0].Environment) $($script:a.Connectors[0].Offerings)" | Should -Be 'AWS CspmMonitorAws, DefenderForServersAws'
        "$($script:a.JitPolicies[0].VirtualMachine):$($script:a.JitPolicies[0].Port) $($script:a.JitPolicies[0].AllowedSource)" | Should -Be 'vm1:22 *'
        $script:a.SuppressionRules[0].Status | Should -Be 'No expiry'
        $script:a.Notices | Should -Match 'multicloud connectors couldn''t be read'
    }

    It 'adds up the secure score as Defender does, and rolls up per subscription' {
        $script:a.Stats.SecureScore | Should -Be 75 -Because '(30 + 45) / (50 + 50)'
        $prod = $script:a.Subscriptions | Where-Object Subscription -EQ 'sub-prod'
        "$($prod.SecureScore) $($prod.PlansOn)/$($prod.Plans) $($prod.UnhealthyResources) $($prod.AttackPaths) $($prod.ActiveAlerts)" | Should -Be '60 4/5 2 1 2'
        $script:a.Subscriptions[0].Subscription | Should -Be 'sub-prod' -Because 'the lowest score comes first'
        $script:a.Controls[0].Control | Should -Be 'Enable MFA' -Because 'the largest potential increase comes first'
    }

    It 'lists regulatory compliance: standards, failed controls first, and the failed assessments with their recommendation' {
        $script:a.Standards[0].PassRate | Should -Be 80
        $script:a.ComplianceControls[0].State | Should -Be 'Failed'
        "$($script:a.ComplianceAssessments[0].Control) $($script:a.ComplianceAssessments[0].FailedResources) $($script:a.ComplianceAssessments[0].Severity)" | Should -Be 'NS-1 2 High'
    }

    It 'leaves out the subscriptions not in scope, and copes with sections not read' {
        $one = & $script:assess @{ SubscriptionName = @{ $script:f.Prod = 'sub-prod' } }
        @($one.Subscriptions).Count | Should -Be 1
        @($one.UnhealthyResources | Where-Object SubscriptionName -EQ 'sub-dev').Count | Should -Be 0
        $bare = & $script:assess @{ Rows = @{ Plans = $script:f.Rows.Plans }; Rest = @{} }
        @($bare.Recommendations).Count | Should -Be 0
        @($bare.Settings).Count | Should -Be 0
        $bare.Stats.SecureScore | Should -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - Invoke-AACDefenderAssessment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($name in @($Query.Keys)) {
                $rows[$name] = if ($name -eq 'subscriptions') { @(@{ id = "/subscriptions/$($script:f.Prod)"; subscriptionId = $script:f.Prod; name = 'sub-prod' }, @{ id = "/subscriptions/$($script:f.Dev)"; subscriptionId = $script:f.Dev; name = 'sub-dev' }) } else { @($script:f.Rows[$name]) }
                if ($OnProgress) { & $OnProgress $name 1 1 }
            }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $names = @{ securityContacts = 'Contacts'; settings = 'Settings'; securityConnectors = 'Connectors'; jitNetworkAccessPolicies = 'Jit'; alertsSuppressionRules = 'Suppression' }
            $out = @{}
            foreach ($u in $Uri) {
                $null = $u -match '^/subscriptions/([^/]+)/providers/Microsoft\.Security/([^?]+)\?'
                $out[$u] = $script:f.Rest[$names[$Matches[2]]][$Matches[1]]
            }
            $out
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'returns the assessment as one object with every table' {
        $result = Invoke-AACDefenderAssessment -NoDisplay
        $result.PSObject.TypeNames[0] | Should -Be 'AAC.DefenderAssessment'
        @($result.Recommendations).Count | Should -Be 3
        @($result.AttackPaths).Count | Should -Be 1
        @($result.Settings).Count | Should -BeGreaterThan 4
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmParallel -Times 1 -Exactly -ParameterFilter { @($Uri).Count -eq 10 } -Because 'five settings in two subscriptions, in one parallel batch'
    }

    It 'reads one subscription, and says when none is found' {
        $result = Invoke-AACDefenderAssessment -SubscriptionId $script:f.Prod -NoDisplay
        @($result.Subscriptions.Subscription) | Should -Be @('sub-prod')
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACGraphBatch -ParameterFilter { @($SubscriptionId) -contains $script:f.Prod }
        { Invoke-AACDefenderAssessment -SubscriptionId '99999999-9999-9999-9999-999999999999' -NoDisplay -WarningAction SilentlyContinue } | Should -Throw '*None of those subscriptions*'
    }

    It 'shows the view at the prompt' {
        $text = (& $script:capture { Invoke-AACDefenderAssessment -NoPaging }).Text
        $text | Should -Match 'secure score'
        $text | Should -Match 'Management ports should be closed'
        $text | Should -Match 'Internet (→|->) vm1 \(virtualmachine\)'
        $text | Should -Match 'SuspiciousLogin'
        $text | Should -Match 'Defender for Storage is off'
    }

    It 'writes a CSV per table and the tabbed HTML report' {
        $csv = Join-Path $TestDrive 'defender'
        $html = Join-Path $TestDrive 'defender.html'
        $null = & $script:capture { Invoke-AACDefenderAssessment -CsvPath $csv -HtmlPath $html }
        @(Get-ChildItem -LiteralPath $csv -Filter '*.csv').Name | Should -Contain 'defender-attack-paths.csv'
        @(Get-ChildItem -LiteralPath $csv -Filter '*.csv').Count | Should -Be 17
        $page = Get-Content -LiteralPath $html -Raw
        foreach ($tab in 'Findings', 'Recommendations', 'Attack path analysis', 'Security alerts', 'Inventory', 'Vulnerabilities', 'Security posture', 'Regulatory compliance', 'Environment settings') { $page | Should -Match ([regex]::Escape("`"name`":`"$tab`"")) }
        $page | Should -Match '"type":"path"'
    }
}
