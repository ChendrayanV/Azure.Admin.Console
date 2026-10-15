<#
    Unit tests for Invoke-AACWafAssessment: the Reliability and Security
    checks evaluated against a made-up Contoso estate (Fixtures\ContosoWaf.ps1)
    - catalogue, Advisor and Defender checks, weighted scores by check,
    principle and pillar, the heat maps - and the command with Resource Graph
    mocked: its one batch, the view, the reports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoWaf.ps1')
    $script:read = Get-AACContosoWaf
    $script:names = (Get-AACContosoWafScope).Names
    $script:build = {
        param([hashtable] $Options = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Read = $script:read; Names = $script:names; Options = $Options } {
            param($Read, $Names, $Options)
            ConvertTo-AACWafAssessment -Read $Read -Catalog (Get-AACWafCatalog) -SubscriptionName $Names @Options
        }
    }
    $script:check = { param($Result, [string] $Id) $Result.Checks | Where-Object CheckId -EQ $Id }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 160
        $console.Profile.Capabilities.Unicode = $false
        try {
            [Spectre.Console.AnsiConsole]::Console = $console
            $output = @(& $Render)
        }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Well-Architected checks and scores' {
    BeforeAll { $script:r = & $script:build }

    It 'evaluates the catalogue checks on each resource of their type' {
        $vm = & $script:check $script:r 'RE-01'
        "$($vm.Evaluated) $($vm.Passed) $($vm.Failed) $($vm.Score)" | Should -Be '2 1 1 50'
        (& $script:check $script:r 'RE-02').Failed | Should -Be 1 -Because 'vm-dev-01 has no backup'
        (& $script:check $script:r 'SE-18').Failed | Should -Be 1 -Because 'nsg-dev opens RDP to anywhere; nsg-prod opens SSH to 10.0.0.0/8 only'
        (& $script:check $script:r 'RE-10').Failed | Should -Be 1
        (& $script:check $script:r 'RE-12').Status | Should -Be 'Not assessed' -Because 'there is no AKS cluster'
        ($script:r.Results | Where-Object { $_.CheckId -eq 'SE-06' -and $_.Status -eq 'Fail' }).Resource | Should -Be 'stdev'
        $script:r.Results[0].PSObject.TypeNames | Should -Contain 'AAC.WafCheckResult'
    }

    It 'checks Defender plans and the secure score per subscription' {
        @($script:r.Results | Where-Object CheckId -EQ 'SE-01' | ForEach-Object { "$($_.Resource)=$($_.Status)" } | Sort-Object) | Should -Be @('Contoso Dev=Fail', 'Contoso Prod=Pass')
        @($script:r.Results | Where-Object CheckId -EQ 'SE-04' | ForEach-Object { "$($_.Resource)=$($_.Status)" } | Sort-Object) | Should -Be @('Contoso Dev=Fail', 'Contoso Prod=Pass')
        (& $script:check $script:r 'SE-03').Score | Should -Be 0 -Because 'neither subscription has Defender CSPM'
    }

    It 'folds Advisor recommendations and Defender assessments into one check per pillar, per resource' {
        $advisor = & $script:check $script:r 'AD-HA'
        "$($advisor.Source) $($advisor.Pillar) $($advisor.Severity) $($advisor.Passed) $($advisor.Failed)" | Should -Be 'Advisor Reliability High 2 1' -Because 'the two other storage accounts in rg-app pass'
        $defender = @($script:r.Checks | Where-Object Source -EQ 'Defender')
        $defender.Count | Should -Be 1
        "$($defender[0].CheckId) $($defender[0].Evaluated) $($defender[0].Failed) $($defender[0].Principle)" | Should -Be 'DF-HIGH 2 1 Sustain and evolve your security posture'
        ($script:r.Results | Where-Object { $_.CheckId -eq 'DF-HIGH' -and $_.Status -eq 'Fail' }).Detail | Should -Be '1 open: Machines should have vulnerability findings resolved'
        ($script:r.Results | Where-Object { $_.CheckId -eq 'AD-HA' }).Detail | Should -Be '1 open: Enable soft delete for blobs (High)'
    }

    It 'scores principles and pillars by severity, and shows principles no check covers as not assessed' {
        ($script:r.Principles | Where-Object Principle -EQ 'Design for business requirements').Coverage | Should -BeLike 'Not assessed*'
        ($script:r.Principles | Where-Object Principle -EQ 'Design for business requirements').Score | Should -BeNullOrEmpty
        $reliability = $script:r.Pillars | Where-Object Pillar -EQ 'Reliability'
        $reliability.Score | Should -BeGreaterThan 0
        $reliability.PSObject.TypeNames | Should -Contain 'AAC.WafPillarScore'
        $script:r.Overall | Should -Be ([Math]::Round((@($script:r.Pillars | ForEach-Object Score) | Measure-Object -Average).Average, 1))
    }

    It 'builds the heat maps: pillars and principles by subscription, each cell weighted by severity' {
        $script:r.HeatMaps.Count | Should -Be 2
        @($script:r.HeatMaps[0].Columns | Sort-Object) | Should -Be @('Contoso Dev', 'Contoso Prod')
        $pillars = $script:r.HeatMaps[0]
        $prodColumn = [array]::IndexOf(@($pillars.Columns), 'Contoso Prod')
        $devColumn = [array]::IndexOf(@($pillars.Columns), 'Contoso Dev')
        $reliability = $pillars.Rows | Where-Object Label -EQ 'Reliability'
        # Prod: RE-01, RE-02 (High) and RE-03, RE-04, RE-18 (Medium) pass; Advisor (High) 2 of 3: 1400 / 15.
        $reliability.Cells[$prodColumn].Score | Should -Be 93.3
        $reliability.Cells[$devColumn].Score | Should -Be 13.3
        $principles = $script:r.HeatMaps[1]
        @($principles.Rows | ForEach-Object Group | Select-Object -Unique) | Should -Be @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')
        ($principles.Rows | Where-Object Label -EQ 'Design for business requirements').Total | Should -BeNullOrEmpty
    }

    It 'checks cost: allocation tags, unattached disks, VMs stopped but billed, old snapshots, and Advisor''s cost recommendations' {
        $status = { param([string] $Id) @($script:r.Results | Where-Object CheckId -EQ $Id | ForEach-Object { "$($_.Resource)=$($_.Status)" } | Sort-Object) }
        & $status 'CO-01' | Should -Be @('vm-dev-01=Fail', 'vm-prod-01=Pass')
        & $status 'CO-03' | Should -Be @('disk-old=Fail')
        & $status 'CO-05' | Should -Be @('vm-dev-01=Fail', 'vm-prod-01=Pass')
        & $status 'CO-07' | Should -Be @('snap-2024=Fail')
        & $status 'CO-10' | Should -Be @('vm-dev-01=Fail', 'vm-prod-01=Pass') -Because 'Standard_D2_v2 is an old generation'
        & $status 'CO-11' | Should -Be @('rg-app=Pass', 'rg-dev=Fail')
        (& $script:check $script:r 'AD-COST').Pillar | Should -Be 'Cost Optimization'
        (& $script:check $script:r 'CO-08').Status | Should -Be 'Not assessed' -Because 'there is no Windows VM'
    }

    It 'checks operations and performance: tags, the monitoring agent, alerts, patching, SSD disks' {
        $status = { param([string] $Id) @($script:r.Results | Where-Object CheckId -EQ $Id | ForEach-Object { "$($_.Resource)=$($_.Status)" } | Sort-Object) }
        & $status 'OE-01' | Should -Be @('rg-app=Pass', 'rg-dev=Fail')
        & $status 'OE-02' | Should -Be @('vm-dev-01=Fail', 'vm-prod-01=Pass')
        & $status 'OE-05' | Should -Be @('Contoso Dev=Fail', 'Contoso Prod=Pass')
        & $status 'OE-06' | Should -Be @('Contoso Dev=Fail', 'Contoso Prod=Pass')
        & $status 'OE-08' | Should -Be @('vm-dev-01=Fail', 'vm-prod-01=Pass')
        & $status 'PE-06' | Should -Be @('vm-dev-01=Fail', 'vm-prod-01=Pass')
        ($script:r.Principles | Where-Object Principle -EQ 'Negotiate realistic performance targets').Coverage | Should -BeLike 'Not assessed*'
        ($script:r.Principles | Where-Object Principle -EQ 'Embrace DevOps culture').Coverage | Should -BeLike 'Not assessed*'
        @($script:r.Pillars.Pillar) | Should -Be @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')
    }

    It 'scores the questionnaire''s answers: Yes, Partly and No, in an Attested column' {
        $csv = Join-Path $TestDrive 'answers.csv'
        $null = & $script:capture { Export-AACWafQuestionnaire -Path $csv }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 24
        ($rows | Where-Object Principle -EQ 'Design for business requirements').Answer = 'Yes'
        ($rows | Where-Object Principle -EQ 'Negotiate realistic performance targets').Answer = 'partly'
        ($rows | Where-Object Principle -EQ 'Design to protect availability').Answer = 'No'
        ($rows | Where-Object Principle -EQ 'Design to protect availability').Evidence = 'No WAF yet'
        ($rows | Where-Object Principle -EQ 'Keep it simple').Answer = 'Maybe'
        $rows | Export-Csv -LiteralPath $csv -NoTypeInformation
        $answers = InModuleScope 'Azure.Admin.Console' -Parameters @{ Path = $csv } { param($Path) Read-AACWafAttestation -Path $Path -Catalog (Get-AACWafCatalog) -WarningVariable seen -WarningAction SilentlyContinue; "$seen" }
        $answers[-1] | Should -BeLike "*answers 'Maybe' for 'Keep it simple'*"
        $attested = InModuleScope 'Azure.Admin.Console' -Parameters @{ Read = $script:read; Names = $script:names; Answers = @($answers | Select-Object -SkipLast 1) } {
            param($Read, $Names, $Answers)
            ConvertTo-AACWafAssessment -Read $Read -Catalog (Get-AACWafCatalog) -SubscriptionName $Names -Attestation $Answers
        }
        $principle = { param([string] $Name) $attested.Principles | Where-Object Principle -EQ $Name }
        "$((& $principle 'Design for business requirements').Score) $((& $principle 'Design for business requirements').Coverage)" | Should -Be '100 Attested'
        (& $principle 'Negotiate realistic performance targets').Score | Should -Be 50
        "$((& $principle 'Design to protect availability').Score)" | Should -Be '0'
        ($attested.Results | Where-Object CheckId -EQ 'AT-SE-4').Detail | Should -Be 'Evidence: No WAF yet'
        $attested.HeatMaps[0].Columns | Should -Contain 'Attested'
        { Export-AACWafQuestionnaire -Path $csv } | Should -Throw '*exists*'
    }

    It 'counts a finding once when Advisor or Defender repeat a catalogue check on the same resource' {
        (& $script:check $script:r 'AD-HA').Failed | Should -Be 1 -Because 'Advisor''s availability-zone item on vm-dev-01 is RE-01'
        @($script:r.Results | Where-Object { $_.CheckId -eq 'DF-HIGH' -and $_.Resource -eq 'stdev' }) | Should -BeNullOrEmpty -Because 'Defender''s public-access item on stdev is SE-07'
        ($script:r.Results | Where-Object { $_.CheckId -eq 'RE-01' -and $_.Resource -eq 'vm-dev-01' }).Detail | Should -Be 'Also flagged by Advisor: Use Availability zones for better resiliency and availability (Medium)'
        ($script:r.Results | Where-Object { $_.CheckId -eq 'SE-07' -and $_.Resource -eq 'stdev' }).Detail | Should -Be 'Also flagged by Defender: Storage account public access should be disallowed'
        $script:r.Stats.Duplicates | Should -Be 2
        $kept = & $script:build @{ KeepDuplicates = $true }
        (& $script:check $kept 'AD-HA').Failed | Should -Be 2
        @($kept.Results | Where-Object { $_.CheckId -eq 'DF-HIGH' -and $_.Resource -eq 'stdev' }).Status | Should -Be 'Fail'
        $kept.Stats.Duplicates | Should -Be 0
    }

    It 'groups the heat maps by resource type or resource group, leaves checks out, and assesses one pillar' {
        $byType = & $script:build @{ HeatMapBy = 'ResourceType' }
        $byType.HeatMaps[0].Columns | Should -Contain 'storage/storageaccounts'
        $byGroup = & $script:build @{ HeatMapBy = 'ResourceGroup' }
        $byGroup.HeatMaps[0].Columns | Should -Contain 'rg-dev (Contoso Dev)'
        $fewer = & $script:build @{ ExcludeCheck = @('AD-*', 'DF-*') }
        @($fewer.Checks | Where-Object Source -NE 'Catalogue') | Should -BeNullOrEmpty
        $one = & $script:build @{ Pillar = 'Reliability' }
        @($one.Pillars.Pillar) | Should -Be @('Reliability')
        @($one.Checks | Where-Object Pillar -EQ 'Security') | Should -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - Invoke-AACWafAssessment' {
    BeforeEach {
        $script:queries = $null
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { Get-AACContosoWafScope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:queries = $Query
            $rows = @{}
            foreach ($name in @($Query.Keys)) { $rows[$name] = @(if ($script:read.Contains($name)) { $script:read[$name] }) }
            @{ Rows = $rows; Errors = @{} }
        }
    }

    It 'reads everything in one Resource Graph batch and returns a result per check and resource' {
        $results = @(Invoke-AACWafAssessment -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 1 -Exactly
        @($script:queries.Keys) | Should -Be @('resources', 'inventory', 'groups', 'extensions', 'autoscale', 'slots', 'backup', 'advisor', 'pricing', 'secureScore', 'assessments')
        $script:queries['resources'] | Should -Match "microsoft.storage/storageaccounts"
        $script:queries['advisor'] | Should -Match "'HighAvailability', 'Security', 'Cost', 'OperationalExcellence', 'Performance'"
        @($results | Where-Object Status -EQ 'Fail').Count | Should -BeGreaterThan 0
        @($results.Status | Select-Object -Unique | Sort-Object) | Should -Be @('Fail', 'Pass')
    }

    It 'asks only what one pillar needs' {
        $null = Invoke-AACWafAssessment -Pillar Reliability -ResourceGroupName 'rg-app' -NoDisplay
        @($script:queries.Keys) | Should -Be @('resources', 'inventory', 'groups', 'extensions', 'autoscale', 'slots', 'backup', 'advisor')
        $script:queries['advisor'] | Should -Match "in~ \('HighAvailability'\)"
        $script:queries['resources'] | Should -Match "resourceGroup in~ \('rg-app'\)"
        $script:queries['resources'] | Should -Not -Match 'networksecuritygroups' -Because 'that type is only checked for Security'
    }

    It 'shows the heat maps at the prompt, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACWafAssessment -NoPaging }).Text
        foreach ($expected in 'Pillars by subscription', 'Design principles by subscription', 'Contoso Prod', 'Design for resilience', 'Design principles', 'Findings', 'nsg-dev', 'not assessed') {
            $text | Should -BeLike "*$expected*"
        }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'writes the CSV and an HTML report with the heat maps, principles, checks and findings' {
        $csv = Join-Path $TestDrive 'waf.csv'
        $html = Join-Path $TestDrive 'waf.html'
        $null = & $script:capture { Invoke-AACWafAssessment -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].PSObject.Properties.Name | Should -Contain 'Principle'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.heatmaps.title) | Should -Be @('Pillars by subscription', 'Design principles by subscription')
        $model.heatmaps[0].rowKey | Should -Be 'Pillar'
        @($model.heatmaps[0].rows[0].cells | Where-Object { $_ }).score | Should -Not -BeNullOrEmpty
        @($model.tables.id) | Should -Be @('principles', 'checks', 'findings')
    }

    It 'keeps a line per run with -HistoryPath and shows the change since the last' {
        $history = Join-Path $TestDrive 'history.csv'
        $null = & $script:capture { Invoke-AACWafAssessment -HistoryPath $history -CsvPath (Join-Path $TestDrive 'h1.csv') }
        $text = (& $script:capture { Invoke-AACWafAssessment -HistoryPath $history -NoPaging }).Text
        $text | Should -BeLike '*+0.0 since*'
        $lines = @(Import-Csv -LiteralPath $history)
        $lines.Count | Should -Be 2
        @($lines[0].PSObject.Properties.Name) | Should -Be @('Date', 'Scope', 'Overall', 'Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency', 'Failed', 'High')
    }

    It 'writes a PDF report with the heat maps' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'waf.pdf'
        $null = & $script:capture { Invoke-AACWafAssessment -HeatMapBy ResourceType -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}

Describe 'Azure Admin Console - Get-AACWafCheck' {
    It 'lists the catalogue, Advisor, Defender and questionnaire checks, and the principles with their coverage' {
        $all = @(Get-AACWafCheck)
        @($all | Where-Object Source -EQ 'Catalogue').Count | Should -Be @(InModuleScope 'Azure.Admin.Console' { (Get-AACWafCatalog).Checks }).Count
        @($all | Where-Object Source -EQ 'Attestation').Count | Should -Be 24
        @($all.Id | Where-Object { $_ -like 'AD-*' } | Sort-Object) | Should -Be @('AD-COST', 'AD-HA', 'AD-OPS', 'AD-PERF', 'AD-SEC')
        @(Get-AACWafCheck -Id 'CO-*').Id | ForEach-Object { $_ | Should -BeLike 'CO-*' }
        @(Get-AACWafCheck -Pillar Security -Severity High | Where-Object Source -EQ 'Catalogue').Id | Should -Contain 'SE-18'
        $principles = @(Get-AACWafCheck -Principle)
        $principles.Count | Should -Be 24
        ($principles | Where-Object Principle -EQ 'Negotiate realistic performance targets').Checks | Should -Be 0
        $principles[0].PSObject.TypeNames | Should -Contain 'AAC.WafPrinciple'
    }
}

Describe 'Azure Admin Console - Test-AACGoLiveReadiness' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { Get-AACContosoWafScope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($name in @($Query.Keys)) { $rows[$name] = @(if ($script:read.Contains($name)) { $script:read[$name] }) }
            @{ Rows = $rows; Errors = @{} }
        }
    }

    It 'says Not ready, with the blockers: pillar scores, high-severity findings and failing required checks' {
        $r = Test-AACGoLiveReadiness -RequiredCheck 'RE-02', 'RE-12' -NoDisplay
        $r.PSObject.TypeNames | Should -Contain 'AAC.GoLiveReadiness'
        $r.Ready | Should -BeFalse
        $r.Verdict | Should -Be 'Not ready'
        @($r.Gates | Where-Object { $_.Gate -eq 'High-severity findings' }).Status | Should -Be 'Fail'
        ($r.Gates | Where-Object { $_.Gate -eq 'Required check' -and $_.Requirement -eq 'RE-02 passes' }).Status | Should -Be 'Fail'
        ($r.Gates | Where-Object { $_.Gate -eq 'Required check' -and $_.Requirement -eq 'RE-12 passes' }).Status | Should -Be 'Warning' -Because 'there is no AKS cluster to test'
        ($r.Gates | Where-Object { $_.Gate -eq 'Principles covered' }).Status | Should -Be 'Warning'
        $r.Blockers.Count | Should -BeGreaterThan 0
    }

    It 'says Ready when the bar allows it, and fails the pipeline with -FailOnGap when not' {
        $r = Test-AACGoLiveReadiness -MinimumScore 0 -AllowHighFinding -NoDisplay
        $r.Ready | Should -BeTrue
        @($r.Warnings).Count | Should -BeGreaterThan 0
        { Test-AACGoLiveReadiness -NoDisplay -FailOnGap } | Should -Throw "*isn't ready to go live*"
        $strict = Test-AACGoLiveReadiness -MinimumScore 0 -AllowHighFinding -RequireAttestation -NoDisplay
        $strict.Ready | Should -BeFalse -Because 'some principles are covered by no check or answer'
    }

    It 'writes the gates to CSV and a report with a Go-live tab first' {
        $csv = Join-Path $TestDrive 'gates.csv'
        $html = Join-Path $TestDrive 'golive.html'
        $null = & $script:capture { Test-AACGoLiveReadiness -PillarMinimum @{ Security = 90 } -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Gate | Should -Contain 'Pillar score'
        (@(Import-Csv -LiteralPath $csv) | Where-Object { $_.Pillar -eq 'Security' }).Requirement | Should -Be '90 or more'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id)[0] | Should -Be 'gates'
        $model.tabs[0].name | Should -Be 'Go-live'
        { Test-AACGoLiveReadiness -PillarMinimum @{ Speed = 1 } -NoDisplay } | Should -Throw "*doesn't know the pillar 'Speed'*"
    }

    It 'shows the verdict at the prompt' {
        $text = (& $script:capture { Test-AACGoLiveReadiness -NoPaging }).Text
        foreach ($expected in 'Not ready', 'Go-live gates', 'High-severity findings', 'Pillars by resource group') { $text | Should -BeLike "*$expected*" }
    }
}
