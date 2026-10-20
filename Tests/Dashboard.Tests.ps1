<#
    Unit tests for Show-AACDashboard's second edition: the Estate score,
    security, policy, governance, Advisor, the estate by type and
    subscription, the change timeline, cost (-IncludeCost), what to do next,
    the HTML report, -Section and -Watch - on a made-up estate whose numbers
    make the score easy to check, with Resource Graph and Cost Management
    faked. (The first edition's tests are in ConsoleExperience.Tests.ps1.)
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $prod = '11111111-1111-1111-1111-111111111111'; $dev = '22222222-2222-2222-2222-222222222222'
    $script:prod = $prod
    $now = [datetime]'2026-10-19T10:00:00'
    $script:now = $now
    $day = { param([int] $Ago) $now.Date.AddDays(-$Ago).ToString('yyyy-MM-dd') }
    $script:subs = @(@{ subscriptionId = $prod; name = 'sub-prod'; state = 'Enabled' }, @{ subscriptionId = $dev; name = 'sub-dev'; state = 'Enabled' })
    # Health 95% available, secure score 61%, policy 78% compliant, Advisor 84: (95 + 61 + 78 + 84) / 4 = 79.5 -> 80, less 5 for sub-prod at 97.5% of the role assignment limit = 75.
    $script:rows = @{
        totals          = @(@{ resources = 100; types = 12; groups = 9; regions = 3 })
        regions         = @(@{ location = 'westeurope'; resources = 70 }, @{ location = 'northeurope'; resources = 30 })
        health          = @(@{ state = 'Available'; resources = 95 }, @{ state = 'Degraded'; resources = 3 }, @{ state = 'Unavailable'; resources = 2 })
        unhealthy       = @(@{ resourceId = "/subscriptions/$prod/resourceGroups/rg-batch/providers/Microsoft.Compute/virtualMachines/vm-batch-03"; state = 'Unavailable'; summary = 'Stopped'; reason = 'Unplanned'; since = '2026-10-19T08:00:00Z' })
        serviceIssues   = @()
        advisor         = @(@{ category = 'Cost'; impact = 'High'; recommendations = 3 })
        changes         = @(@{ changeType = 'Create'; changes = 4 }, @{ changeType = 'Update'; changes = 20 }, @{ changeType = 'Delete'; changes = 12 })
        recentChanges   = @()
        types           = @(@{ type = 'microsoft.network/networkinterfaces'; resources = 30 }, @{ type = 'microsoft.compute/virtualmachines'; resources = 20 })
        bySubscription  = @(@{ subscriptionId = $prod; resources = 80 }, @{ subscriptionId = $dev; resources = 20 })
        tagged          = @(@{ total = 100; tagged = 40 })
        secureScore     = @(@{ current = 61; max = 100 })
        alerts          = @(@{ severity = 'High'; alerts = 4 }, @{ severity = 'Medium'; alerts = 10 }, @{ severity = 'Low'; alerts = 6 })
        recommendations = @(@{ severity = 'High'; recommendations = 6 }, @{ severity = 'Medium'; recommendations = 20 })
        defenderPlans   = @(@{ on = 9; total = 12 })
        policy          = @(@{ nonCompliant = 220; compliant = 780 })
        policyTop       = @(@{ assignment = 'Baseline'; scope = '/providers/Microsoft.Management/managementGroups/mg-platform'; resources = 150 })
        advisorScore    = @(@{ score = 84 })
        advisorSavings  = @(@{ currency = 'EUR'; savings = 12345.6; recommendations = 3 })
        unused          = @(@{ type = 'microsoft.compute/disks'; resources = 5 }, @{ type = 'microsoft.network/publicipaddresses'; resources = 2 })
        roleAssignments = @(@{ subscriptionId = $prod; used = 3900 }, @{ subscriptionId = $dev; used = 300 }, @{ subscriptionId = '99999999-9999-9999-9999-999999999999'; used = 4000 })
        privileged      = @(@{ principalType = 'User'; subscriptionId = $prod; assignments = 3 }, @{ principalType = 'Group'; subscriptionId = ''; assignments = 2 }, @{ principalType = 'User'; subscriptionId = '99999999-9999-9999-9999-999999999999'; assignments = 9 })
        changeDays      = @(@{ day = (& $day 0); changeType = 'Update'; changes = 20 }, @{ day = (& $day 3); changeType = 'Delete'; changes = 12 }, @{ day = (& $day 30); changeType = 'Create'; changes = 99 })
        changers        = @(@{ changedBy = 'alice@contoso.example'; changes = 14; deletes = 12 }, @{ changedBy = 'pipeline-sp'; changes = 22; deletes = 0 })
    }
    $script:cost = @{ MonthToDate = 2090.0; LastMonthToDate = 1900.0; LastMonth = 3000.0; Forecast = 3410.0; ChangePercent = 10.0; Currency = 'EUR'; Daily = @(0..29 | ForEach-Object { [pscustomobject]@{ Day = $now.Date.AddDays(-29 + $_); Cost = 100 + $_ } }); TopServices = @([pscustomobject]@{ Service = 'Virtual Machines'; Cost = 1500.0 }); Unread = [ordered]@{} }
    $script:build = {
        param([hashtable] $Rows = $script:rows, $Cost = $null)
        InModuleScope 'Azure.Admin.Console' -Parameters @{ R = @{ Rows = $Rows; Errors = @{} }; S = $script:subs; C = $Cost; N = $script:now } {
            param($R, $S, $C, $N)
            ConvertTo-AACDashboard -Read $R -Subscription $S -Hours 24 -Cost $C -Now $N -Session ([pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1' })
        }
    }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new(); $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer); $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings); $console.Profile.Width = 200; $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) } finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - the dashboard, second edition' {
    BeforeAll { $script:d = & $script:build $script:rows $script:cost }

    It 'scores the estate from health, security, policy and Advisor, less the limit penalty' {
        $s = $script:d.Score
        "$($s.Value) | $($s.Health) $($s.Security) $($s.Policy) $($s.Advisor) | $($s.Penalty)" | Should -Be '75 | 95 61 78 84 | 5'
        (& $script:build @{ totals = $script:rows.totals }).Score.Value | Should -BeNullOrEmpty -Because 'nothing the score is made of was read'
        # A tenant with no Advisor score: Resource Graph's avg() over no rows is NaN - not a number to score with.
        $noAdvisor = @{} + $script:rows; $noAdvisor.advisorScore = @(@{ score = 'NaN' }); $noAdvisor.secureScore = @(@{ current = 'NaN'; max = 'NaN' })
        $d = & $script:build $noAdvisor
        "$($d.AdvisorScore) | $($d.Security.SecureScore) | $($d.Score.Value)" | Should -Be ' |  | 81' -Because '(95 + 78) / 2 = 86.5 -> 86 (to even), less 5 for the limit'
    }

    It 'sums up security, policy, governance, Advisor and the estate' {
        $d = $script:d
        "$($d.Security.SecureScore) | $($d.Security.Alerts.High)/$($d.Security.Alerts.Medium)/$($d.Security.Alerts.Low) | $($d.Security.Recommendations.High) | $($d.Security.DefenderPlans)" | Should -Be '61 | 4/10/6 | 6 | 9 of 12'
        "$($d.Policy.Compliance) | $($d.Policy.NonCompliant) | $($d.Policy.Top[0].Assignment) $($d.Policy.Top[0].Scope) $($d.Policy.Top[0].Resources)" | Should -Be '78 | 220 | Baseline mg-platform 150'
        $g = $d.Governance
        "$($g.ClosestLimit.Scope) $($g.ClosestLimit.Used) $($g.ClosestLimit.Percent) | $($g.PrivilegedAssignments) | $($g.Unused) | $($g.TagCoverage)" | Should -Be 'sub-prod 3900 97.5 | 5 | 7 | 40' -Because 'a subscription out of scope counts for neither the limit nor privileged access'
        "$($d.AdvisorScore) | $($d.AdvisorSavings.Annual) $($d.AdvisorSavings.Currency)" | Should -Be '84 | 12346 EUR'
        "$($d.TopTypes[0].Name) $($d.TopTypes[0].Resources) | $($d.BySubscription[0].Subscription) $($d.BySubscription[0].Resources)" | Should -Be 'networkinterfaces 30 | sub-prod 80'
    }

    It 'lays out the last 14 days of changes, and who made the most' {
        $t = @($script:d.ChangeTimeline)
        $t.Count | Should -Be 14
        "$($t[-1].Updated) $($t[-4].Deleted) $(($t | Measure-Object -Property Created -Sum).Sum)" | Should -Be '20 12 0' -Because 'a change 30 days ago is outside the window'
        $script:d.TopChangers[0].ChangedBy | Should -Be 'alice@contoso.example'
    }

    It 'ranks what to do next across every section, each with the command that goes deeper' {
        @($script:d.Actions | ForEach-Object { "$($_.Severity) | $($_.Area) | $($_.Command)" }) | Should -Be @(
            'High | Health | Get-AACResourceHealth'
            'High | Security | Get-AACSecurityAlert'
            'High | Limits | Test-AACAzureLimit'
            'Medium | Health | Get-AACResourceHealth'
            'Medium | Security | Invoke-AACDefenderAssessment'
            'Medium | Policy | Invoke-AACPolicyAssessment'
            'Medium | Advisor | Get-AACAdvisorRecommendation'
            'Medium | Governance | Get-AACUnusedResource -IncludeCost'
            'Medium | Changes | Get-AACChangeHistory'
            'Low | Access | Get-AACRoleAssignment -Privileged'
            'Low | Governance | Get-AACTagUsage'
        )
        $script:d.Actions[0].Action | Should -Be '2 resource(s) unavailable: vm-batch-03'
        ($script:d.Actions | Where-Object Area -EQ 'Advisor').Action | Should -Be '3 High-impact Advisor recommendation(s) - 12,346 EUR a year to save'
    }

    It 'says what needs attention in the headline, the new sections included' {
        $script:d.Status | Should -Be 'Failed'
        foreach ($expected in '4 high-severity security alert(s)', 'policy compliance 78%', 'sub-prod at 97.5% of the role assignment limit') { $script:d.Headline | Should -BeLike "*$expected*" }
        $script:d.Headline | Should -Not -BeLike '*spend*' -Because '+10% is not above 10%'
    }

    It 'carries the cost card, and flags spend well above last month' {
        "$($script:d.Cost.MonthToDate) $($script:d.Cost.Forecast) $($script:d.Cost.ChangePercent) $($script:d.Cost.Currency)" | Should -Be '2090 3410 10 EUR'
        $high = @{} + $script:cost; $high.ChangePercent = 25.0
        $d = & $script:build $script:rows $high
        $d.Headline | Should -BeLike '*spend 25% above last month*'
        "$($d.Score.Penalty) $($d.Score.Value)" | Should -Be '8 72'
        ($d.Actions | Where-Object Area -EQ 'Cost').Command | Should -Be 'Get-AACCostAnomaly'
    }
}

Describe 'Azure Admin Console - the dashboard''s cost card' {
    It 'compares month to date with the same days last month, and carries the daily average to a forecast' {
        $r = InModuleScope 'Azure.Admin.Console' {
            Mock -CommandName Invoke-AACCostBatch -MockWith {
                $rows = [System.Collections.Generic.List[object]]::new()
                for ($d = [datetime]'2026-09-01'; $d -le [datetime]'2026-10-19'; $d = $d.AddDays(1)) {
                    $daily = if ($d.Month -eq 10) { 110 } else { 100 }
                    $rows.Add([pscustomobject]@{ Cost = $daily * 0.6; UsageDate = [int]$d.ToString('yyyyMMdd'); ServiceName = 'Virtual Machines'; Currency = 'EUR' })
                    $rows.Add([pscustomobject]@{ Cost = $daily * 0.4; UsageDate = [int]$d.ToString('yyyyMMdd'); ServiceName = 'Storage'; Currency = 'EUR' })
                }
                @{ '/subscriptions/a' = @{ Rows = $rows; Status = 'OK' }; '/subscriptions/b' = @{ Rows = @(); Status = 'Forbidden' } }
            }
            Mock -CommandName Update-AACProgress -MockWith { }
            Read-AACDashboardCost -SubscriptionId 'a', 'b' -SubscriptionName @{ b = 'sub-b' } -Today ([datetime]'2026-10-19')
        }
        "$($r.MonthToDate) $($r.LastMonthToDate) $($r.LastMonth) $($r.Forecast) $($r.ChangePercent) $($r.Currency)" | Should -Be '2090 1900 3000 3410 10 EUR'
        "$(@($r.Daily).Count) $($r.Daily[-1].Cost) $($r.TopServices[0].Service) $($r.TopServices[0].Cost)" | Should -Be '30 110 Virtual Machines 1254'
        $r.Unread['sub-b'] | Should -Be 'Forbidden'
    }
}

Describe 'Azure Admin Console - the dashboard''s views' {
    It 'draws the scores, security, governance, cost, the timeline and what to do next - in characters any console can show' {
        $d = & $script:build $script:rows $script:cost
        $text = (& $script:capture { InModuleScope 'Azure.Admin.Console' -Parameters @{ D = $d } { param($D) Show-AACDashboardView -Dashboard $D } }).Text
        foreach ($expected in 'estate score (of 100)', 'secure score', 'Security', 'Governance', 'Closest limit', 'Cost', '2,090 EUR', 'Resources by type', 'Changes, 14 days', 'What to do next', 'Test-AACAzureLimit', 'Potential savings') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
        $only = (& $script:capture { InModuleScope 'Azure.Admin.Console' -Parameters @{ D = $d } { param($D) Show-AACDashboardView -Dashboard $D -Section Health } }).Text
        $only | Should -Match 'Resource Health'
        $only | Should -Not -Match 'Resources by type|Closest limit|Changes, 14 days|secure score'
        $only | Should -Match 'What to do next' -Because 'what to do next always shows'
    }

    It 'builds the report: an Overview, then a tab per section' {
        $d = & $script:build $script:rows $script:cost
        $r = InModuleScope 'Azure.Admin.Console' -Parameters @{ D = $d } { param($D) ConvertTo-AACDashboardReport -Dashboard $D }
        @($r.Tabs.Name) | Should -Be @('What to do next', 'Health', 'Security', 'Policy', 'Governance', 'Advisor', 'Estate', 'Changes', 'Cost')
        @($r.Tiles.Label) | Should -Contain 'Estate score (of 100)'
        @($r.Tables.Id) | Should -Contain 'services'
        $noCost = InModuleScope 'Azure.Admin.Console' -Parameters @{ D = (& $script:build) } { param($D) ConvertTo-AACDashboardReport -Dashboard $D }
        @($noCost.Tabs.Name) | Should -Not -Contain 'Cost'
    }
}

Describe 'Azure Admin Console - Show-AACDashboard, second edition' {
    BeforeEach {
        $script:reads = 0
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = $script:subs }; Errors = @{} } }
            $script:reads++
            @{ Rows = $script:rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACDashboardCost -MockWith { $script:cost }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the cost only with -IncludeCost' {
        (Show-AACDashboard -NoDisplay).Cost | Should -BeNullOrEmpty
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACDashboardCost -Times 0
        (Show-AACDashboard -IncludeCost -NoDisplay).Cost.MonthToDate | Should -Be 2090
    }

    It 'writes the report with a tab per section, and what to do next as CSV' {
        $html = Join-Path $TestDrive 'dash.html'; $csv = Join-Path $TestDrive 'actions.csv'
        $null = & $script:capture { Show-AACDashboard -IncludeCost -HtmlPath $html -CsvPath $csv }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tabs.name) | Should -Contain 'Cost'
        @(Import-Csv -LiteralPath $csv)[0].Command | Should -Be 'Get-AACResourceHealth'
    }

    It 'refreshes with -Watch until stopped' {
        $script:sleeps = 0
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { $script:sleeps++; if ($script:sleeps -ge 2) { throw [System.Management.Automation.PipelineStoppedException]::new() } }
        $null = & $script:capture { Show-AACDashboard -Watch 60 }
        $script:reads | Should -Be 2
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -ParameterFilter { $Seconds -eq 60 } -Times 2 -Exactly
    }
}
