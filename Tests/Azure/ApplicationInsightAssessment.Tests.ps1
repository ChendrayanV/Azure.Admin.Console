<#
    Unit tests for Invoke-AACApplicationInsightAssessment: workspace and
    architecture, ingestion and cost, security, identity and access, audit
    and lifecycle, findings and the heat map - with Resource Graph, Resource
    Manager, Azure Monitor, Log Analytics and the Activity Log mocked
    (Fixtures\ContosoApplicationInsight.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoApplicationInsight.ps1')
    $script:ai = Get-AACContosoApplicationInsight
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 170
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Invoke-AACApplicationInsightAssessment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { $script:ai.Scope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @($script:ai.Graph[$n]) }; @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $path = ($u -split '\?', 2)[0]
                if ($path -match '/providers/Microsoft\.Insights/metrics$') {
                    $body = $script:ai.Metrics["$(($u -split '/providers/Microsoft.Insights/metrics', 2)[0])|Telemetry"]
                    $out[$u] = if ($body) { @{ Status = 200; Body = $body; Items = $null; Error = '' } } else { @{ Status = 400; Body = $null; Items = $null; Error = 'Failed to find metric configuration.' } }
                    continue
                }
                $answer = $script:ai.Arm[$path]
                $out[$u] = if ($answer) { $answer } else { @{ Status = 404; Body = $null; Items = $null; Error = 'The resource was not found.' } }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith {
            $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @($script:ai.Logs[$WorkspaceId][$n]) }; @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACActivityLog -MockWith { @{ Rows = @($script:ai.Activity); Coverage = @(); Notices = @(); Events = @() } }
    }

    It 'reads each component: mode, workspace, telemetry, daily cap, security, tests, alerts, access and lock' {
        $rows = @(Invoke-AACApplicationInsightAssessment -NoDisplay)
        $rows.Count | Should -Be 4
        $orders = $rows | Where-Object Component -EQ 'appi-orders'
        "$($orders.Mode) $($orders.Workspace) $($orders.Requests) $($orders.DailyCapGB) $($orders.LocalAuth) $($orders.IpMasking) $($orders.PrivateLinkScope)" | Should -Be 'Workspace-based law-prod 100000 10 Disabled On True'
        "$($orders.AvailabilityTests) $($orders.AlertRules) $($orders.SmartDetection) $($orders.Publishers) $($orders.Lock) $($orders.Findings) $($orders.Score)" | Should -Be '1 2 True 1 True 0 100'
        $orders.PSObject.TypeNames | Should -Contain 'AAC.ApplicationInsightAssessment'
        $legacy = $rows | Where-Object Component -EQ 'appi-legacy'
        "$($legacy.Mode) $($legacy.LocalAuth) $($legacy.IpMasking) $($legacy.ApiKeys) $($legacy.DirectAssignments) $($legacy.Lock)" | Should -Be 'Classic Allowed Off 1 1 False'
        $rows[0].Component | Should -Not -Be 'appi-orders' -Because 'the worst score comes first'
        ($rows | Where-Object Component -EQ 'appi-web').IngestedGB | Should -BeNullOrEmpty -Because 'ingestion is read only with -IncludeIngestion'
    }

    It 'finds what to fix in all five signals' {
        $have = @(Invoke-AACApplicationInsightAssessment -IncludeIngestion -IncludeActivityLog -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.Component) | $($_.Signal) | $($_.Finding)" })
        foreach ($expected in @(
                'High | appi-legacy | Architecture | Classic resource (not workspace-based)'
                'High | appi-legacy | Architecture | URL ping test retired'
                'Low | appi-legacy | Architecture | Availability test in too few locations'
                'Medium | appi-legacy | Architecture | No alert rule'
                'Medium | appi-legacy | Security | Local authentication allowed'
                'Medium | appi-legacy | Security | Client IP addresses stored'
                'High | appi-legacy | Security | API key that can write'
                'Medium | appi-legacy | Identity & access | Owner granted on the component'
                'Low | appi-legacy | Identity & access | Access granted to individual users'
                'Low | appi-legacy | Ingestion & cost | No effective daily cap'
                'Low | appi-legacy | Audit & lifecycle | No delete lock'
                'Low | appi-legacy | Audit & lifecycle | No owner tag'
                'High | appi-web | Ingestion & cost | Daily cap reached: telemetry dropped'
                'Medium | appi-web | Ingestion & cost | No sampling on a busy app'
                'Medium | appi-web | Ingestion & cost | Ingestion spike'
                'Low | appi-web | Ingestion & cost | Verbose and information traces dominate'
                'Low | appi-web | Ingestion & cost | Health probes fill the requests'
                'Medium | appi-web | Ingestion & cost | Telemetry sent twice by a diagnostic setting'
                'Medium | appi-web | Architecture | No availability test'
                'Low | appi-web | Architecture | Alert rules tell no one'
                'Low | appi-web | Architecture | Failure Anomalies smart detection off'
                'High | appi-web | Identity & access | Local authentication off, but nothing may publish'
                'Medium | appi-web | Audit & lifecycle | Telemetry purged'
                'Medium | appi-web | Audit & lifecycle | API key created'
                'Low | appi-web | Audit & lifecycle | Changed by hand'
                'Low | appi-web | Audit & lifecycle | Failed changes'
                'Low | appi-idle | Architecture | Workspace in another region'
                'Medium | appi-idle | Architecture | No alert rule'
                'Low | appi-idle | Identity & access | Workspace needs workspace-wide read'
                'Low | appi-idle | Audit & lifecycle | No telemetry in the period'
            )) { $have | Should -Contain $expected }
        @($have | Where-Object { $_ -like '* | appi-orders | *' }) | Should -BeNullOrEmpty
        @($have | Where-Object { $_ -like '*Changed by hand*' }).Count | Should -Be 1 -Because "appi-web-2's changes aren't appi-web's"
    }

    It 'returns ingestion by table, role assignments and changes by -View' {
        $tables = @(Invoke-AACApplicationInsightAssessment -IncludeIngestion -View Ingestion -NoDisplay)
        @($tables | Where-Object Component -EQ 'appi-web' | ForEach-Object { "$($_.Table) $($_.GB) $($_.Share) $($_.RetainedPct)" }) | Should -Be @('AppTraces 9 60 100', 'AppRequests 4 26.7 100', 'AppDependencies 2 13.3 100')
        $web = Invoke-AACApplicationInsightAssessment -IncludeIngestion -NoDisplay | Where-Object Component -EQ 'appi-web'
        "$($web.IngestedGB) $($web.GBPerDay) $($web.PeakDayGB) $($web.RetainedPct)" | Should -Be '15 2.143 6 100'
        $access = @(Invoke-AACApplicationInsightAssessment -View Access -NoDisplay)
        ($access | Where-Object Component -EQ 'appi-legacy') | ForEach-Object { "$($_.Role) $($_.PrincipalType) $($_.Level)" } | Should -Be 'Owner User This component'
        $changes = @(Invoke-AACApplicationInsightAssessment -IncludeActivityLog -View Change -NoDisplay)
        $changes.Count | Should -Be 4
        @($changes | Where-Object CallerType -EQ 'Person').Count | Should -Be 2
    }

    It 'shows the heat map and findings at the prompt, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACApplicationInsightAssessment -NoPaging }).Text
        foreach ($expected in 'Application Insights by signal', 'appi-legacy', 'Classic resource (not workspace-based)', 'Findings') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes CSV by -View and an HTML report with the heat map and tabs' {
        $csv = Join-Path $TestDrive 'ai.csv'
        $html = Join-Path $TestDrive 'ai.html'
        $null = & $script:capture { Invoke-AACApplicationInsightAssessment -IncludeIngestion -View Ingestion -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 5
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.heatmaps[0].title | Should -Be 'Application Insights by signal'
        @($model.heatmaps[0].columns) | Should -Be @('Ingestion & cost', 'Architecture', 'Security', 'Identity & access', 'Audit & lifecycle')
        @($model.tables.id) | Should -Be @('components', 'findings', 'ingestion', 'access') -Because 'changes are empty without -IncludeActivityLog'
    }

    It 'narrows by -Name, and writes a PDF report' -Skip:(-not $script:canWritePdf) {
        @(Invoke-AACApplicationInsightAssessment -Name 'appi-o*' -NoDisplay).Component | Should -Be @('appi-orders')
        $pdf = Join-Path $TestDrive 'ai.pdf'
        $null = & $script:capture { Invoke-AACApplicationInsightAssessment -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
