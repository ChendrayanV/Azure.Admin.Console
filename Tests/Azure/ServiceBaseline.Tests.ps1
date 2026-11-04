<#
    Unit tests for Get-AACAlertBaseline and Get-AACResiliencyRecommendation,
    against the AMBA and APRL data that ships with the module. Nothing is mocked
    and nothing signs in: these commands read only that file.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
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
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:dataPath = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'src/Azure/Private/ServiceBaseline.json'
}

Describe 'Azure Admin Console - the AMBA and APRL data' {
    BeforeAll { $script:data = Get-Content -LiteralPath $script:dataPath -Raw | ConvertFrom-Json -AsHashtable }

    It 'names the commit and licence of each project, so a copy can be traced' {
        foreach ($set in 'Alerts', 'Resiliency', 'LandingZone') {
            $script:data.Sources[$set].Commit | Should -Match '^[0-9a-f]{40}$'
            $script:data.Sources[$set].License | Should -Be 'MIT'
        }
    }

    It 'has every field the commands read, on every record' {
        foreach ($row in $script:data.Alerts) {
            foreach ($key in 'ResourceType', 'Name', 'Type', 'Verified', 'Severity', 'Metric', 'Aggregation', 'Operator', 'Threshold', 'Window', 'Frequency', 'Criterion', 'Kinds', 'Description', 'Query', 'Link', 'Guid') { $row.ContainsKey($key) | Should -BeTrue -Because "$($row.Name) needs $key" }
            $row.ResourceType | Should -Match '^[\w.]+/[\w./]+$'
        }
        foreach ($row in $script:data.Resiliency) {
            foreach ($key in 'ResourceType', 'Name', 'Impact', 'Control', 'Description', 'Benefit', 'Verified', 'Automated', 'Link', 'Guid') { $row.ContainsKey($key) | Should -BeTrue -Because "$($row.Name) needs $key" }
            $row.Impact | Should -BeIn 'High', 'Medium', 'Low'
        }
    }

    It 'covers what a blueprint''s templates plan' {
        foreach ($type in 'Microsoft.Web/serverFarms', 'Microsoft.Web/sites', 'Microsoft.Storage/storageAccounts', 'Microsoft.EventHub/namespaces', 'Microsoft.EventGrid/topics') {
            @($script:data.Alerts | Where-Object { $_.ResourceType -ieq $type }).Count | Should -BeGreaterThan 0 -Because "AMBA has $type"
            @($script:data.Resiliency | Where-Object { $_.ResourceType -ieq $type }).Count | Should -BeGreaterThan 0 -Because "APRL has $type"
        }
    }
}

Describe 'Azure Admin Console - Get-AACAlertBaseline' {
    It 'returns typed alerts for a type, whatever its case, and a wildcard' {
        $rows = @(Get-AACAlertBaseline -ResourceType 'MICROSOFT.EVENTHUB/NAMESPACES' -NoDisplay)
        $rows.Count | Should -BeGreaterThan 0
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.AlertBaseline'
        @($rows.ResourceType | Select-Object -Unique) | Should -Be 'Microsoft.EventHub/namespaces'
        @(Get-AACAlertBaseline -ResourceType 'Microsoft.Web/*' -NoDisplay).ResourceType | Select-Object -Unique | Should -Contain 'Microsoft.Web/sites'
    }

    It 'says the condition in words, and keeps to the severities asked for' {
        $metric = @(Get-AACAlertBaseline -ResourceType 'Microsoft.EventGrid/topics' -NoDisplay | Where-Object Name -EQ 'PublishFailCount')[0]
        $metric.Severity | Should -Be 'Sev3'
        $metric.Condition | Should -Be 'Total PublishFailCount GreaterThan 5'
        @(Get-AACAlertBaseline -Severity Sev0, Sev1 -NoDisplay).Severity | Select-Object -Unique | Should -Not -Contain 'Sev3'
    }

    It 'shows the view, returns nothing unasked, and needs no sign-in' {
        $result = & $script:capture { Get-AACAlertBaseline -ResourceType 'Microsoft.EventGrid/topics' -NoPaging }
        $result.Output | Should -BeNullOrEmpty
        foreach ($expected in 'Baseline alerts', 'PublishFailCount', 'nothing here says what you already have') { $result.Text | Should -Match ([regex]::Escape($expected)) }
    }

    It 'reports a type AMBA doesn''t cover, rather than failing' {
        @(Get-AACAlertBaseline -ResourceType 'Microsoft.Contoso/widgets' -NoDisplay).Count | Should -Be 0
        (& $script:capture { Get-AACAlertBaseline -ResourceType 'Microsoft.Contoso/widgets' -NoPaging }).Text | Should -Match 'AMBA suggests no alert'
    }

    It 'tab completes the types' {
        $line = 'Get-AACAlertBaseline -ResourceType Microsoft.EventG'
        @((TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches.CompletionText) | Should -Contain 'Microsoft.EventGrid/topics'
    }

    It 'writes CSV and HTML' {
        $csv = Join-Path $TestDrive 'alerts.csv'
        $html = Join-Path $TestDrive 'alerts.html'
        $null = & $script:capture { Get-AACAlertBaseline -ResourceType 'Microsoft.EventGrid/topics' -CsvPath $csv -HtmlPath $html -NoDisplay }
        @(Import-Csv -LiteralPath $csv).Name | Should -Contain 'PublishFailCount'
        Get-Content -LiteralPath $html -Raw | Should -Match 'PublishFailCount'
    }

    It 'writes PDF' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'alerts.pdf'
        $null = & $script:capture { Get-AACAlertBaseline -ResourceType 'Microsoft.EventGrid/topics' -PdfPath $pdf -NoDisplay }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}

Describe 'Azure Admin Console - Get-AACResiliencyRecommendation' {
    It 'returns typed recommendations for a type, whatever its case' {
        $rows = @(Get-AACResiliencyRecommendation -ResourceType 'microsoft.storage/storageaccounts' -NoDisplay)
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.ResiliencyRecommendation'
        $rows.Name | Should -Contain 'Ensure that storage accounts are zone or region redundant'
    }

    It 'leaves out what APRL has disabled' {
        (Get-AACResiliencyRecommendation -ResourceType 'Microsoft.Storage/storageAccounts' -NoDisplay).Name | Should -Not -Contain 'Use premium performance block blob storage for high performance workloads'
    }

    It 'keeps to the impact asked for' {
        @(Get-AACResiliencyRecommendation -Impact High -NoDisplay).Impact | Select-Object -Unique | Should -Be 'High'
    }

    It 'shows the view, and says these are not results' {
        $text = (& $script:capture { Get-AACResiliencyRecommendation -ResourceType 'Microsoft.Storage/storageAccounts' -NoPaging }).Text
        foreach ($expected in 'Resiliency recommendations', 'zone or region redundant', 'to review, not results') { $text | Should -Match ([regex]::Escape($expected)) }
    }

    It 'writes CSV and HTML' {
        $csv = Join-Path $TestDrive 'resiliency.csv'
        $html = Join-Path $TestDrive 'resiliency.html'
        $null = & $script:capture { Get-AACResiliencyRecommendation -ResourceType 'Microsoft.Storage/storageAccounts' -CsvPath $csv -HtmlPath $html -NoDisplay }
        @(Import-Csv -LiteralPath $csv).Count | Should -BeGreaterThan 0
        Get-Content -LiteralPath $html -Raw | Should -Match 'zone or region redundant'
    }
}
