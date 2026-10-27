<#
    Unit tests for the Architecture area: the probe questions and the brief,
    the pattern ranking, the design model, its validation (WAF, inherited
    Azure Policy, guardrails, PSRule mapping), the Mermaid and draw.io
    diagrams and the decision records - for made-up Contoso workloads
    (Fixtures\ContosoArchitecture.ps1), offline, with only the landing zone's
    Resource Graph read mocked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoArchitecture.ps1')
    $script:f = Get-AACContosoArchitecture
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
    $script:modelOf = { param([string] $Path) [regex]::Match((Get-Content -LiteralPath $Path -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json }
    $script:brief = { param([System.Collections.IDictionary] $Answer, [string] $Name = 'orders-api') New-AACArchitectureBrief -Name $Name -Answer $Answer -NonInteractive -NoDisplay }
}

Describe 'Azure Admin Console - the architecture catalog' {
    It 'has questions, patterns and rules that are complete and point at Microsoft''s documentation' {
        $catalog = InModuleScope 'Azure.Admin.Console' { Get-AACArchitectureCatalog }
        $catalog.Version | Should -Match '^\d{4}\.\d{1,2}\.\d+$'
        @($catalog.Questions | Group-Object Id | Where-Object Count -GT 1) | Should -BeNullOrEmpty
        foreach ($q in $catalog.Questions) { "$($q.Id) $($q.Text.Length -gt 10) $($q.Pillar -in $catalog.Pillars) $([bool]$q.Help)" | Should -Be "$($q.Id) True True True" }
        foreach ($p in $catalog.Patterns) { $p.Link | Should -BeLike 'https://learn.microsoft.com/azure/architecture/patterns/*'; @($p.Effect.Keys | Sort-Object) | Should -Be @($catalog.Pillars | Sort-Object) }
        foreach ($r in $catalog.Rules) { "$($r.Id) $($r.Severity -in 'Blocking', 'High', 'Medium', 'Low') $($r.Pillar -in $catalog.Pillars) $([bool]$r.Remediation) $($r.Link -like 'https://*')" | Should -Be "$($r.Id) True True True True" }
        @($catalog.Rules | Group-Object Id | Where-Object Count -GT 1) | Should -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - New-AACArchitectureBrief' {
    It 'takes the answers given, defaults the rest as assumptions, and keeps "don''t know" open' {
        $b = & $script:brief $script:f.Orders
        $b.PSObject.TypeNames | Should -Contain 'AAC.ArchitectureBrief'
        "$($b.Answers['BUS-01']) | $($b.Answers['SEC-01']) | $($b.Answers['PERF-02']) | $($b.Answers['SEC-02'] -join ',')" | Should -Be 'Web or API | Confidential | 80 | ISO 27001'
        $b.Answers['REL-03'] | Should -Be '99.95' -Because 'the SLA defaults from the criticality'
        $b.Answers['OPS-02'] | Should -Be 'Full' -Because 'critical workloads default to full observability'
        $b.Open | Should -Be @('COST-01')
        $b.Answers['COST-01'] | Should -Be 0
        $b.Assumed | Should -Contain 'REL-02'
        $b.Assumed | Should -Not -Contain 'BUS-01'
    }

    It 'asks about regulatory frameworks only for confidential or regulated data' {
        (& $script:brief $script:f.Reports 'reports').Answers.Contains('SEC-02') | Should -BeFalse
        (& $script:brief $script:f.Orders).Answers.Contains('SEC-02') | Should -BeTrue
    }

    It 'says which answers it can''t use, and which questions don''t exist' {
        { & $script:brief @{ 'BUS-02' = 'Very important' } } | Should -Throw '*choose ''Mission-critical'', ''Business-critical''*'
        { & $script:brief @{ 'REL-01' = 'soon' } } | Should -Throw '*give a number*'
        { & $script:brief @{ 'XYZ-01' = 'x' } } | Should -Throw '*doesn''t know the question ''XYZ-01''*'
    }

    It 'saves the brief and reads it back, from JSON and from a .psd1 of answers' {
        $json = Join-Path $TestDrive 'orders.brief.json'
        $null = New-AACArchitectureBrief -Name 'orders-api' -Answer $script:f.Orders -NonInteractive -NoDisplay -OutPath $json
        $again = New-AACArchitectureBrief -AnswerPath $json -NonInteractive -NoDisplay
        "$($again.Name) $($again.Answers['PERF-02'])" | Should -Be 'orders-api 80'
        $psd1 = Join-Path $TestDrive 'answers.psd1'
        Set-Content -LiteralPath $psd1 -Value "@{ 'BUS-01' = 'Event-driven'; 'SEC-01' = 'Public' }"
        (New-AACArchitectureBrief -AnswerPath $psd1 -NonInteractive -NoDisplay).Answers['BUS-01'] | Should -Be 'Event-driven'
    }

    It 'asks a question at the prompt: a number picks a choice, Enter keeps the default, ? leaves it open, a wrong answer is asked again' {
        $script:replies = [System.Collections.Generic.Queue[string]]::new([string[]]@('9', '2'))
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-Host -MockWith { $script:replies.Dequeue() }
        $question = InModuleScope 'Azure.Admin.Console' { (Get-AACArchitectureCatalog).Questions | Where-Object Id -EQ 'BUS-02' }
        $null = & $script:capture { $script:answer = InModuleScope 'Azure.Admin.Console' -Parameters @{ Q = $question } { param($Q) Read-AACArchitectureAnswer -Question $Q -Default 'Internal' -Guided } }
        "$($script:answer.Value) $($script:answer.Unknown)" | Should -Be 'Business-critical False'
        $script:replies = [System.Collections.Generic.Queue[string]]::new([string[]]@(''))
        $null = & $script:capture { $script:answer = InModuleScope 'Azure.Admin.Console' -Parameters @{ Q = $question } { param($Q) Read-AACArchitectureAnswer -Question $Q -Default 'Internal' } }
        $script:answer.Value | Should -Be 'Internal'
        $script:replies = [System.Collections.Generic.Queue[string]]::new([string[]]@('?'))
        $null = & $script:capture { $script:answer = InModuleScope 'Azure.Admin.Console' -Parameters @{ Q = $question } { param($Q) Read-AACArchitectureAnswer -Question $Q -Default 'Internal' } }
        "$($script:answer.Value) $($script:answer.Unknown)" | Should -Be 'Internal True'
    }

    It 'shows a short summary at the prompt and still returns the brief, so $brief = ... works' {
        $run = & $script:capture { New-AACArchitectureBrief -Name 'orders-api' -Answer $script:f.Orders -NonInteractive -NoPaging }
        foreach ($expected in 'Architecture brief', 'open decision', 'assumed', 'Get-AACArchitecturePattern') { $run.Text | Should -BeLike "*$expected*" }
        $run.Text | Should -Not -BeLike '*Unknown - default used*' -Because 'the full answer table stays out of the summary'
        $run.Output[0].PSObject.TypeNames | Should -Contain 'AAC.ArchitectureBrief'
        $design = (& $script:capture { New-AACArchitectureDesign -Brief $run.Output[0] -Offline -NoPaging }).Output
        $design[0].PSObject.TypeNames | Should -Contain 'AAC.ArchitectureDesign'
    }
}

Describe 'Azure Admin Console - Get-AACArchitecturePattern' {
    It 'ranks the patterns that fit first, with why and what they cost' {
        $rows = @(Get-AACArchitecturePattern -Brief (& $script:brief $script:f.Orders) -NoDisplay)
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.ArchitecturePattern'
        $cache = $rows | Where-Object Id -EQ 'cache-aside'
        "$($cache.Rank) $($cache.Recommended) $($cache.Why)" | Should -Be '1 Yes read-heavy workload; response target under 100 ms (80 ms)'
        $cache.TradeOffs | Should -Be 'Cost +1, Operations -1, Performance +2'
        ($rows | Where-Object Id -EQ 'queue-based-load-leveling').Recommended | Should -Be 'Yes'
        ($rows | Where-Object Id -EQ 'geodes').Recommended | Should -Be 'No' -Because 'the users are in one geography'
        @(Get-AACArchitecturePattern -Brief (& $script:brief $script:f.Orders) -RecommendedOnly -NoDisplay | Where-Object Recommended -NE 'Yes') | Should -BeNullOrEmpty
        @(Get-AACArchitecturePattern -Brief (& $script:brief $script:f.Orders) -Top 3 -NoDisplay).Count | Should -Be 3
    }

    It 'writes the ranking as an HTML report' {
        $html = Join-Path $TestDrive 'patterns.html'
        $null = & $script:capture { Get-AACArchitecturePattern -Brief (& $script:brief $script:f.Orders) -HtmlPath $html }
        (& $script:modelOf $html).tables[0].title | Should -Be 'Patterns, best first'
    }
}

Describe 'Azure Admin Console - New-AACArchitectureDesign' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($key in @($Query.Keys)) { $rows[$key] = @($script:f.LandingZone[$key]) }
            @{ Rows = $rows; Errors = @{} }
        }
    }

    It 'builds a confidential web API: a WAF in front, private endpoints, zone redundancy, the patterns'' components and a PSRule gate' {
        $b = & $script:brief $script:f.Orders
        $design = Get-AACArchitecturePattern -Brief $b -RecommendedOnly -NoDisplay | New-AACArchitectureDesign -Brief $b -Offline -NoDisplay
        $design.PSObject.TypeNames | Should -Contain 'AAC.ArchitectureDesign'
        $node = { param([string] $Id) $design.Nodes | Where-Object Id -EQ $Id }
        "$((& $node 'edge').Name) $((& $node 'edge').Settings.Waf)" | Should -Be 'Application Gateway True'
        "$((& $node 'data').Name) $((& $node 'data').PrivateEndpoint) $((& $node 'data').PublicAccess) $((& $node 'data').ZoneRedundant)" | Should -Be 'Azure SQL Database True False True'
        (& $node 'cache').Name | Should -Be 'Azure Cache for Redis' -Because 'Cache-Aside was chosen'
        "$((& $node 'queue').Name) $((& $node 'worker').Name)" | Should -Be 'Service Bus Worker (Functions)'
        (& $node 'compute').Identity | Should -Be 'Secrets'
        @($design.Nodes | Where-Object Zone -EQ 'Hub' | ForEach-Object Name) | Should -Be @('Hub virtual network', 'Private DNS zones')
        (& $node 'gate').Name | Should -Be 'PSRule for Azure gate'
        $design.Notices | Should -BeLike '*second region*' -Because 'an RTO of 30 minutes needs one, and only one region was given'
        @($design.Regions) | Should -Be @('westeurope')
    }

    It 'designs other workloads to fit them: batch with no network, AI in two regions behind Front Door' {
        $batch = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Reports 'reports') -Offline -NoDisplay
        "$(($batch.Nodes | Where-Object Id -EQ 'compute').Name) $(@($batch.Nodes | Where-Object Kind -EQ 'network').Count) $(@($batch.Nodes | Where-Object Kind -EQ 'gateway').Count)" | Should -Be 'Container Apps job 0 0'
        ($batch.Nodes | Where-Object Id -EQ 'budget').Name | Should -Be 'Budget (500 a month)'
        $chat = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Chat 'chat') -Region westeurope, northeurope -Offline -NoDisplay
        @($chat.Regions) | Should -Be @('westeurope', 'northeurope')
        ($chat.Nodes | Where-Object Id -EQ 'edge').Name | Should -Be 'Front Door Premium'
        @($chat.Nodes | Where-Object Kind -In 'openai', 'search' | ForEach-Object Id | Sort-Object) | Should -Be @('openai', 'openai-2', 'search', 'search-2')
        @($chat.Connections | Where-Object Label -EQ 'geo-replication').Count | Should -Be 1
        ($chat.Nodes | Where-Object Id -EQ 'data').Name | Should -Be 'Cosmos DB'
    }

    It 'changes components with -Override, and says which components exist when one doesn''t' {
        $b = & $script:brief $script:f.Orders
        $design = New-AACArchitectureDesign -Brief $b -Offline -Override @{ kv = @{ Settings = @{ PurgeProtection = $false } }; data = @{ Sku = 'Hyperscale' } } -NoDisplay
        "$(($design.Nodes | Where-Object Id -EQ 'kv').Settings.PurgeProtection) $(($design.Nodes | Where-Object Id -EQ 'data').Sku)" | Should -Be 'False Hyperscale'
        { New-AACArchitectureDesign -Brief $b -Offline -Override @{ nope = @{ Sku = 'x' } } -NoDisplay } | Should -Throw '*no such component*kv*'
        { New-AACArchitectureDesign -Brief $b -Offline -Pattern 'not-a-pattern' -NoDisplay } | Should -Throw '*doesn''t know the pattern*'
    }

    It 'reads the landing zone''s inherited policy and allowed locations - unless -Offline' {
        $design = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Orders) -LandingZone 'mg-landingzones' -NoDisplay
        @($design.ManagementGroups) | Should -Be @('contoso', 'mg-landingzones')
        @($design.AllowedLocations) | Should -Be @('northeurope', 'westeurope')
        @($design.Policies | ForEach-Object { "$($_.Name) ($($_.Enforcement))" }) | Should -Contain 'Deny public IP addresses (Not enforced)'
        $design.LandingZone | Should -Be 'mg-landingzones'
        $null = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Orders) -LandingZone 'mg-landingzones' -Offline -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 2 -Exactly -Because 'the offline design reads nothing'
    }

    It 'notes a landing zone it couldn''t read and designs on' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ group = @() }; Errors = @{} } }
        $design = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Orders) -LandingZone 'mg-nope' -NoDisplay
        ($design.Notices -join ' ') | Should -BeLike "*mg-nope couldn't be read*"
    }

    It 'saves the design and reads it back' {
        $path = Join-Path $TestDrive 'orders.design.json'
        $null = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Orders) -Offline -NoDisplay -OutPath $path
        $model = InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $path } { param($P) Resolve-AACArchitectureInput -InputObject $P -Kind Design }
        "$(@($model.Nodes).Count -gt 10) $($model.Nodes[0].Settings -is [System.Collections.IDictionary]) $($model.Name)" | Should -Be 'True True orders-api'
    }
}

Describe 'Azure Admin Console - Test-AACArchitectureDesign' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($key in @($Query.Keys)) { $rows[$key] = @($script:f.LandingZone[$key]) }
            @{ Rows = $rows; Errors = @{} }
        }
        $script:orders = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Orders) -Offline -NoDisplay
    }

    It 'finds what to fix, each with its pillar, policy, PSRule rule and remedy' {
        $findings = @(Test-AACArchitectureDesign -Design $script:orders -NoDisplay)
        $findings[0].PSObject.TypeNames | Should -Contain 'AAC.ArchitectureFinding'
        @($findings | ForEach-Object { "$($_.Severity) $($_.Rule) $($_.Component)" }) | Should -Be @(
            'High REL-MR-01 Design'
            'High SEC-ID-01 App Service'
            'High SEC-ID-01 Worker (Functions)'
            'Low COST-BUD-01 Design'
        )
        $identity = $findings | Where-Object Rule -EQ 'SEC-ID-01' | Select-Object -First 1
        "$($identity.Pillar) | $($identity.Policy) | $($identity.PSRule)" | Should -Be 'Security | App Service apps should use managed identity | Azure.AppService.ManagedIdentity'
        $identity.Remediation | Should -BeLike '*managed identity*'
    }

    It 'blocks what the landing zone''s policy or the guardrails would refuse' {
        $inLz = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Orders) -LandingZone 'mg-landingzones' -Region eastus -NoDisplay
        @(Test-AACArchitectureDesign -Design $inLz -NoDisplay | Where-Object Severity -EQ 'Blocking').Rule | Should -Be 'GOV-LOC-01' -Because 'eastus is outside the inherited allowed locations'
        $guarded = @(Test-AACArchitectureDesign -Design $script:orders -Guardrail @{ AllowedRegions = @('northeurope'); RequiredTags = @('CostCenter'); DenyPublicEndpoint = $true; DeniedSkus = @('P1*') } -NoDisplay | Where-Object Severity -EQ 'Blocking')
        @($guarded.Rule | Sort-Object -Unique) | Should -Be @('GOV-LOC-01', 'GRD-SKU-01', 'GRD-TAG-01')
        ($guarded | Where-Object Rule -EQ 'GRD-SKU-01').Component | Should -Be 'App Service'
        $file = Join-Path $TestDrive 'guardrails.psd1'
        Set-Content -LiteralPath $file -Value "@{ RequiredTags = @('CostCenter') }"
        @(Test-AACArchitectureDesign -Design $script:orders -GuardrailPath $file -NoDisplay | Where-Object Severity -EQ 'Blocking').Rule | Should -Be 'GRD-TAG-01'
    }

    It 'flags what a design changed by hand breaks: purge protection off, TLS 1.0, no WAF' {
        $changed = New-AACArchitectureDesign -Brief (& $script:brief $script:f.Orders) -Offline -Override @{ kv = @{ Settings = @{ PurgeProtection = $false } }; data = @{ Settings = @{ MinTls = '1.0' }; PublicAccess = $true }; edge = @{ Settings = @{ Waf = $false } } } -NoDisplay
        $rules = @(Test-AACArchitectureDesign -Design $changed -NoDisplay | ForEach-Object Rule)
        foreach ($expected in 'SEC-KV-01', 'SEC-TLS-01', 'SEC-PE-01', 'SEC-WAF-01') { $rules | Should -Contain $expected }
    }

    It 'keeps accepted risks out of the scores and -FailOnGap, and fails a pipeline on what is left' {
        $accepted = @(Test-AACArchitectureDesign -Design $script:orders -Accept 'REL-MR-01', 'SEC-ID-01:worker' -NoDisplay)
        @($accepted | Where-Object Status -EQ 'Accepted' | ForEach-Object { "$($_.Rule) $($_.Component)" }) | Should -Be @('REL-MR-01 Design', 'SEC-ID-01 Worker (Functions)')
        { $null = Test-AACArchitectureDesign -Design $script:orders -NoDisplay -FailOnGap } | Should -Throw '*0 blocking and 3 high*'
        { $null = Test-AACArchitectureDesign -Design $script:orders -Accept 'REL-MR-01', 'SEC-ID-01' -NoDisplay -FailOnGap } | Should -Not -Throw
    }

    It 'passes a design that answers its own requirements' {
        $answers = [ordered]@{}; foreach ($k in $script:f.Orders.Keys) { $answers[$k] = $script:f.Orders[$k] }
        $answers['SEC-04'] = 'Managed identity'; $answers['REL-01'] = 240; $answers['COST-01'] = 3000
        $clean = New-AACArchitectureDesign -Brief (& $script:brief $answers) -Offline -NoDisplay
        @(Test-AACArchitectureDesign -Design $clean -NoDisplay) | Should -BeNullOrEmpty
    }

    It 'writes a tabbed report - findings, pillars, components, inherited policy, open decisions - and a PDF' {
        $html = Join-Path $TestDrive 'validation.html'
        $pdf = Join-Path $TestDrive 'validation.pdf'
        $null = & $script:capture { Test-AACArchitectureDesign -Design $script:orders -HtmlPath $html -PdfPath $(if ($script:canWritePdf) { $pdf }) }
        $model = & $script:modelOf $html
        @($model.tabs.name) | Should -Be @('Findings', 'Pillars', 'Components', 'Inherited policy', 'Open decisions')
        ($model.tables | Where-Object id -EQ 'findings').section | Should -Be 'Findings'
        if ($script:canWritePdf) { (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000 }
    }

    It 'shows the findings and the score by pillar at the prompt' {
        $text = (& $script:capture { Test-AACArchitectureDesign -Design $script:orders -NoPaging }).Text
        foreach ($expected in 'Architecture validation', 'Secrets instead of managed identities', 'Score by pillar', 'Security') { $text | Should -BeLike "*$expected*" }
    }
}

Describe 'Azure Admin Console - New-AACArchitectureDiagram and Export-AACArchitectureDecision' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($key in @($Query.Keys)) { $rows[$key] = @($script:f.LandingZone[$key]) }
            @{ Rows = $rows; Errors = @{} }
        }
        $b = & $script:brief $script:f.Orders
        $script:design = Get-AACArchitecturePattern -Brief $b -RecommendedOnly -NoDisplay | New-AACArchitectureDesign -Brief $b -LandingZone 'mg-landingzones' -NoDisplay
    }

    It 'draws Mermaid, Markdown and draw.io with every compliance layer' {
        $files = @(New-AACArchitectureDiagram -Design $script:design -Path (Join-Path $TestDrive 'diagrams'))
        @($files.Name) | Should -Be @('orders-api.mmd', 'orders-api.md', 'orders-api.drawio')
        $mermaid = Get-Content -LiteralPath $files[0].FullName -Raw
        $mermaid | Should -BeLike 'flowchart LR*'
        foreach ($expected in 'subgraph LZ["Landing zone: mg-landingzones<br/>policy: Allowed locations', 'guardrail zone · allowed: northeurope, westeurope', 'PSRule for Azure gate</b><br/>baseline Azure.Default', 'Azure Advisor and Defender for Cloud', 'stroke-dasharray', 'n_compute["<b>App Service</b><br/>P1v3<br/>WAF S!!', ':::bad', 'classDef ok') {
            $mermaid.Contains($expected) | Should -BeTrue -Because "the diagram has: $expected"
        }
        $mermaid | Should -Not -BeLike '*|"diagnostics"|*' -Because 'diagnostics edges would clutter the diagram'
        $mermaid | Should -Not -Match '->\|[^"]' -Because 'a bare edge label with brackets, such as egress (route table), is a Mermaid syntax error'
        $md = Get-Content -LiteralPath $files[1].FullName -Raw
        $md | Should -BeLike '*```mermaid*'
        $md | Should -BeLike '*| High | Secrets instead of managed identities | App Service | Security |*'
        $md | Should -BeLike '*- **COST-01***'
        $xml = [xml](Get-Content -LiteralPath $files[2].FullName -Raw)
        @($xml.mxfile.diagram | ForEach-Object name) | Should -Be @('Cover', 'Architecture', 'Policy and compliance', 'Findings', 'Legend')
        $architecture = @($xml.mxfile.diagram)[1].mxGraphModel.root
        @($architecture.mxCell | Where-Object { $_.parent -eq '0' } | ForEach-Object value) | Should -Be @('Architecture', 'WAF', 'Azure Policy', 'Guardrails', 'PSRule', 'Recommendations')
        $compute = @($architecture.object | Where-Object { $_.id -eq 'n-compute' })
        $compute.Count | Should -Be 1
        $compute[0].mxCell.style | Should -BeLike 'image;*image=data:image/svg+xml,*' -Because 'components are drawn with their Azure icon'
        $compute[0].aacService | Should -Be 'Microsoft.Web/sites'
        @($architecture.object | Where-Object { $_.id -eq 'n-spoke' }).Count | Should -Be 1 -Because 'the spoke virtual network is the box holding the workload'
        @($architecture.mxCell | Where-Object { $_.edge -eq '1' -and $_.value -eq 'diagnostics' }).Count | Should -Be 0
        $policy = @($xml.mxfile.diagram)[2].mxGraphModel.root
        $policyText = (@($policy.mxCell | ForEach-Object value) + @($policy.object | ForEach-Object label)) -join "`n"
        foreach ($expected in 'Inherited Azure Policy - Landing zone: mg-landingzones', 'Allowed locations', 'Deny public IP addresses', 'SEC-ID-01', 'Open - High', 'Pass') {
            $policyText.Contains($expected) | Should -BeTrue -Because "the policy page has: $expected"
        }
        $legend = @($xml.mxfile.diagram)[4].mxGraphModel.root
        @($legend.mxCell | ForEach-Object value) | Should -Contain 'App Service'
        @(@($xml.mxfile.diagram)[0].mxGraphModel.root.object | ForEach-Object link) | Should -Contain 'data:page/id,policy'
    }

    It 'draws only the formats and layers asked for' {
        $files = @(New-AACArchitectureDiagram -Design $script:design -Path (Join-Path $TestDrive 'some') -Format Mermaid -Layer Waf)
        $files.Name | Should -Be 'orders-api.mmd'
        $mermaid = Get-Content -LiteralPath $files[0].FullName -Raw
        $mermaid | Should -Not -BeLike '*PSRule for Azure gate</b><br/>baseline*'
        $mermaid | Should -Not -BeLike '*guardrail zone*'
        $mermaid | Should -BeLike '*WAF S!!*'
    }

    It 'writes a decision record for the topology, each pattern and each accepted risk, with the open decisions' {
        $files = @(Export-AACArchitectureDecision -Design $script:design -Path (Join-Path $TestDrive 'adr') -Accept 'REL-MR-01' -Reason 'One region for phase 1' -Owner 'Orders team' -ReviewBy ([datetime]'2027-03-31'))
        $files[0].Name | Should -Be '0001-hosting-and-topology.md'
        $files[1].Name | Should -Be '0002-use-cache-aside.md'
        $files[-2].Name | Should -Be "$('{0:D4}' -f ($files.Count - 1))-accept-risk-rel-mr-01-on-design.md"
        $files[-1].Name | Should -Be 'README.md'
        $topology = Get-Content -LiteralPath $files[0].FullName -Raw
        foreach ($expected in '- Status: Accepted', '- Owner: Orders team', 'Compute and entry: Application Gateway (WAF_v2), App Service (P1v3)', 'hub and spoke, private endpoints with private DNS in the hub', 'Inherited policy: Allowed locations; Microsoft cloud security benchmark; Deny public IP addresses') { $topology | Should -BeLike "*$expected*" }
        $risk = Get-Content -LiteralPath $files[-2].FullName -Raw
        foreach ($expected in 'The risk is accepted: One region for phase 1', 'Review by: 2027-03-31', "-Accept 'REL-MR-01'") { $risk | Should -BeLike "*$expected*" }
        $readme = Get-Content -LiteralPath $files[-1].FullName -Raw
        foreach ($expected in '| 0001 | [Hosting and topology](0001-hosting-and-topology.md) | Accepted |', '- **COST-01**', '## Assumptions (defaults no one answered)', '- **REL-02**') { $readme.Contains($expected) | Should -BeTrue -Because "README.md has: $expected" }
    }
}
