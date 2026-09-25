<#
    Unit tests for Get-AACAdvisorRecommendation. Resource Graph responses
    are hand-built JSON shaped like the advisorresources rows the cmdlet's
    queries project, and every Azure call is mocked, so no network call or
    active Connect-AAC session is required.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

Describe 'Azure Admin Console - Get-AACAdvisorRecommendation' {
    BeforeAll {
        # Runs a script block with the Spectre console swapped for one that
        # writes plain text into a buffer, and returns that text.
        $script:renderToText = {
            param([scriptblock] $Render)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            $capture = [Spectre.Console.AnsiConsole]::Create($settings)
            $capture.Profile.Width = 160
            $capture.Profile.Capabilities.Unicode = $true
            try {
                [Spectre.Console.AnsiConsole]::Console = $capture
                & $Render
            }
            finally {
                [Spectre.Console.AnsiConsole]::Console = $real
            }
            $buffer.ToString()
        }
    }

    BeforeEach {
        $sub = '11111111-1111-1111-1111-111111111111'
        $vm = "/subscriptions/$sub/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-app01"
        $recommendations = @"
[
  {"id":"$vm/providers/Microsoft.Advisor/recommendations/aaa","name":"aaa","subscriptionId":"$sub","resourceGroup":"rg-app",
   "category":"Cost","impact":"High","impactedField":"Microsoft.Compute/virtualMachines","impactedValue":"vm-app01",
   "resourceId":"$vm","resourceType":"Microsoft.Compute/virtualMachines",
   "problem":"Right-size or shutdown underutilized virtual machines","solution":"Right-size or shutdown underutilized virtual machines",
   "potentialBenefits":"","recommendationTypeId":"e10b1381","learnMoreLink":"https://aka.ms/aa_lowusagerec","lastUpdated":"2026-09-20T04:10:00Z",
   "extendedProperties":{"savingsAmount":"123.45","annualSavingsAmount":"1481.4","savingsCurrency":"USD","targetSku":"Standard_B2s"}},
  {"id":"$vm/providers/Microsoft.Advisor/recommendations/bbb","name":"bbb","subscriptionId":"$sub","resourceGroup":"rg-app",
   "category":"HighAvailability","impact":"Medium","impactedField":"Microsoft.Compute/virtualMachines","impactedValue":"vm-app01",
   "resourceId":"$vm","resourceType":"Microsoft.Compute/virtualMachines",
   "problem":"Migrate to managed disks","solution":"Migrate to managed disks before retirement",
   "potentialBenefits":"","recommendationTypeId":"f0bf9ae6","learnMoreLink":"","lastUpdated":"2026-09-21T00:00:00Z",
   "extendedProperties":{"recommendationSubCategory":"ServiceUpgradeAndRetirement","retirementDate":"2027-03-31","retirementFeatureName":"Unmanaged disks"}},
  {"id":"/subscriptions/$sub/providers/Microsoft.Advisor/recommendations/ccc","name":"ccc","subscriptionId":"$sub","resourceGroup":"",
   "category":"Security","impact":"Low","impactedField":"Microsoft.Subscriptions/subscriptions","impactedValue":"",
   "resourceId":"/subscriptions/$sub","resourceType":"",
   "problem":"Enable Defender for Storage","solution":"Enable it","potentialBenefits":"","recommendationTypeId":"x","learnMoreLink":"","lastUpdated":"",
   "extendedProperties":null}
]
"@ | ConvertFrom-Json
        $suppressions = @"
[{"recommendationId":"/subscriptions/$($sub.ToLowerInvariant())/providers/microsoft.advisor/recommendations/ccc","ttl":"-1","expires":""}]
"@ | ConvertFrom-Json
        $subscriptions = "[{`"subscriptionId`":`"$sub`",`"name`":`"sub-prod`"}]" | ConvertFrom-Json

        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACStatus -MockWith { & $ScriptBlock }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Write-AACMarkup -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match "microsoft.advisor/recommendations'" } -MockWith { $recommendations }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'microsoft.advisor/suppressions' } -MockWith { $suppressions }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match '^resourcecontainers' } -MockWith { $subscriptions }.GetNewClosure()
    }

    It 'flattens each recommendation into one row with typed savings, dates and portal category names' {
        $rows = @(Get-AACAdvisorRecommendation -NoDisplay)

        $rows.Count | Should -Be 2 -Because 'the dismissed recommendation is left out by default'
        $cost = $rows | Where-Object Category -eq 'Cost'
        $cost.SubscriptionName | Should -BeExactly 'sub-prod'
        $cost.ResourceName | Should -BeExactly 'vm-app01'
        $cost.MonthlySavings | Should -Be 123.45
        $cost.AnnualSavings | Should -Be 1481.4
        $cost.SavingsCurrency | Should -BeExactly 'USD'
        $cost.LastUpdated | Should -Be ([datetime]::new(2026, 9, 20, 4, 10, 0, [DateTimeKind]::Utc))
        $cost.ExtendedProperties | Should -BeExactly 'annualSavingsAmount=1481.4; savingsAmount=123.45; savingsCurrency=USD; targetSku=Standard_B2s'

        $reliability = $rows | Where-Object Category -eq 'Reliability'
        $reliability.SubCategory | Should -BeExactly 'ServiceUpgradeAndRetirement'
        $reliability.RetirementDate.Date | Should -Be ([datetime]'2027-03-31')
        $reliability.RetiringFeature | Should -BeExactly 'Unmanaged disks'
        $reliability.MonthlySavings | Should -BeNullOrEmpty

        $rows[0].Category | Should -BeExactly 'Cost' -Because 'rows are sorted by category order'
    }

    It 'includes postponed and dismissed recommendations with -IncludeSuppressed' {
        $security = @(Get-AACAdvisorRecommendation -IncludeSuppressed | Where-Object Category -eq 'Security')

        $security.Count | Should -Be 1
        $security[0].Status | Should -BeExactly 'Dismissed'
        $security[0].ResourceName | Should -Not -BeNullOrEmpty -Because 'a subscription-level recommendation falls back to the ID'
    }

    It 'filters by category and impact' {
        @(Get-AACAdvisorRecommendation -Category Reliability -NoDisplay).Category | Should -Be @('Reliability')
        @(Get-AACAdvisorRecommendation -Impact High -NoDisplay).Impact | Should -Be @('High')
    }

    It 'gives every row the same columns, so Export-Csv keeps every Ext_ column' {
        $csv = Join-Path -Path $TestDrive -ChildPath 'out/advisor.csv'
        $null = Get-AACAdvisorRecommendation -ExpandExtendedProperty -IncludeSuppressed -CsvPath $csv -NoDisplay

        $imported = @(Import-Csv -LiteralPath $csv)
        $imported.Count | Should -Be 3
        $columns = $imported[0].PSObject.Properties.Name
        foreach ($name in 'Ext_targetSku', 'Ext_retirementDate', 'Ext_savingsAmount', 'MonthlySavings', 'ExtendedProperties') {
            $columns | Should -Contain $name
        }
        $columns | Should -Not -Contain '_Extended'
        ($imported | Where-Object Category -eq 'Reliability').Ext_retirementFeatureName | Should -BeExactly 'Unmanaged disks'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path -Path $TestDrive -ChildPath 'advisor.pdf'
        $rows = @(Get-AACAdvisorRecommendation -IncludeSuppressed -PdfPath $pdf -NoDisplay)

        $rows.Count | Should -Be 3
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
        [System.IO.File]::ReadAllBytes($pdf)[0..3] | Should -Be ([byte[]][char[]]'%PDF')
    }

    Context 'summary or objects' {
        BeforeEach {
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACAdvisorSummary -MockWith { }
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACAdvisorTable -MockWith { }
        }

        It 'shows the summary and returns nothing when run on its own' {
            $out = @(Get-AACAdvisorRecommendation)
            $out.Count | Should -Be 0
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACAdvisorSummary -Times 1 -Exactly
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACAdvisorTable -Times 1 -Exactly
        }

        It 'returns the objects without the summary when piped onward' {
            $out = @(Get-AACAdvisorRecommendation | ForEach-Object { $_ })
            $out.Count | Should -Be 2
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACAdvisorSummary -Times 0 -Exactly
        }

        It 'shows the summary and returns the objects with -PassThru' {
            $out = @(Get-AACAdvisorRecommendation -PassThru)
            $out.Count | Should -Be 2
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACAdvisorSummary -Times 1 -Exactly
        }

        It 'returns the objects without the summary with -NoDisplay' {
            $out = @(Get-AACAdvisorRecommendation -NoDisplay)
            $out.Count | Should -Be 2
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACAdvisorSummary -Times 0 -Exactly
        }
    }

    It 'renders the summary tiles' {
        $text = InModuleScope 'Azure.Admin.Console' {
            $rows = @(Get-AACAdvisorRecommendation -NoDisplay)
            & $args[0] { Show-AACAdvisorSummary -Recommendation $rows -Scope ([ordered]@{ Subscriptions = 'all' }) }
        } -ArgumentList $script:renderToText

        foreach ($expected in 'Azure Advisor', 'recommendations', 'high impact', 'medium impact', 'resources affected', 'USD 123') {
            $text | Should -BeLike "*$expected*"
        }
    }

    It 'renders one table per category, grouped by recommendation with savings and retirement dates' {
        $text = InModuleScope 'Azure.Admin.Console' {
            $rows = @(Get-AACAdvisorRecommendation -NoDisplay -IncludeSuppressed)
            & $args[0] { Show-AACAdvisorTable -Recommendation $rows }
        } -ArgumentList $script:renderToText

        foreach ($expected in '● Cost', '● Security', '● Reliability', ' HIGH ', ' MEDIUM ', ' LOW ',
            'Right-size or shutdown underutilized', 'vm-app01', 'virtualMachines', 'sub-prod · rg-app',
            'USD 123.45', '31 Mar 2027', 'Unmanaged disks', 'dismissed') {
            $text | Should -BeLike "*$expected*"
        }
        $text.IndexOf('● Cost') | Should -BeLessThan $text.IndexOf('● Security') -Because 'categories keep the portal order'
    }
}
