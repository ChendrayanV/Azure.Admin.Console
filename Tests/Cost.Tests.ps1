<#
    Unit tests for Show-AACCost. Resource Graph and the Cost Management Query
    API are mocked with hand-built rows (months relative to today) and the
    Spectre console is captured, so no Azure call is made. The cost rows go
    through ConvertFrom-Json, as Invoke-RestMethod's do, so month values
    arrive as [datetime] exactly as they do from Azure.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

Describe 'Azure Admin Console - Show-AACCost' {
    BeforeAll {
        $script:capture = {
            param([scriptblock] $Render, [switch] $Ascii)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            $console = [Spectre.Console.AnsiConsole]::Create($settings)
            $console.Profile.Width = 140
            # -Ascii: a console that isn't UTF-8 (code page 437, 850...).
            $console.Profile.Capabilities.Unicode = -not $Ascii
            try {
                [Spectre.Console.AnsiConsole]::Console = $console
                $output = @(& $Render)
            }
            finally {
                [Spectre.Console.AnsiConsole]::Console = $real
            }
            [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
        }
        $script:thisMonth = [datetime]::new((Get-Date).Year, (Get-Date).Month, 1)
        $script:key = { param([int] $Back) $script:thisMonth.AddMonths(-$Back).ToString('yyyy-MM', [cultureinfo]::InvariantCulture) }

        # Cost Management rows as JSON text, then ConvertFrom-Json like
        # Invoke-RestMethod: ISO BillingMonth strings become [datetime].
        $script:costRows = {
            param([object[]] $Rows)
            ($Rows | ConvertTo-Json -Depth 5 -AsArray) | ConvertFrom-Json
        }
    }

    BeforeEach {
        $prod = '11111111-1111-1111-1111-111111111111'
        $web = '44444444-4444-4444-4444-444444444444'
        $dev = '22222222-2222-2222-2222-222222222222'
        $old = '33333333-3333-3333-3333-333333333333'
        $subscriptions = @"
[{"subscriptionId":"$prod","name":"sub-prod","state":"Enabled"},
 {"subscriptionId":"$web","name":"sub-web","state":"Enabled"},
 {"subscriptionId":"$dev","name":"sub-dev","state":"Enabled"},
 {"subscriptionId":"$old","name":"sub-old","state":"Disabled"}]
"@ | ConvertFrom-Json
        $month = $script:thisMonth
        $iso = { param([int] $Back) $month.AddMonths(-$Back).ToString('yyyy-MM-ddT00:00:00', [cultureinfo]::InvariantCulture) }

        # sub-prod: 100, 200 ... 500 over the last five months (VMs in rg-app),
        # then this month VMs 30.50 + Storage 12.25 (rg-app) + Key Vault 2.25 (rg-sec).
        $prodRows = & $script:costRows @(
            for ($i = 5; $i -ge 1; $i--) { @{ Cost = 100 * (6 - $i); BillingMonth = (& $iso $i); ServiceName = 'Virtual Machines'; ResourceGroupName = 'rg-app'; Currency = 'GBP' } }
            @{ Cost = 30.5; BillingMonth = (& $iso 0); ServiceName = 'Virtual Machines'; ResourceGroupName = 'rg-app'; Currency = 'GBP' }
            @{ Cost = 12.25; BillingMonth = (& $iso 0); ServiceName = 'Storage'; ResourceGroupName = 'rg-app'; Currency = 'GBP' }
            @{ Cost = 2.25; BillingMonth = (& $iso 0); ServiceName = 'Key Vault'; ResourceGroupName = 'rg-sec'; Currency = 'GBP' }
        )
        # sub-web: months as a number (20260701) and as a plain date string.
        $webRows = @(
            [pscustomobject]@{ Cost = 7; BillingMonth = [long]$month.ToString('yyyyMMdd', [cultureinfo]::InvariantCulture); ServiceName = 'App Service'; ResourceGroupName = 'rg-web'; Currency = 'GBP' }
            [pscustomobject]@{ Cost = 3; BillingMonth = $month.AddMonths(-1).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture); ServiceName = 'App Service'; ResourceGroupName = 'rg-web'; Currency = 'GBP' }
        )

        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -MockWith { $subscriptions }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -ParameterFilter { $SubscriptionId -eq $prod } -MockWith { $prodRows }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -ParameterFilter { $SubscriptionId -eq $web } -MockWith { $webRows }.GetNewClosure()
        # sub-dev: Cost Management refuses, as it does for some offer types.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -ParameterFilter { $SubscriptionId -eq $dev } -MockWith {
            throw 'Cost Management data is not available for subscription offer type MS-AZR-0036P.'
        }
    }

    It 'reads months that arrive as [datetime] - Invoke-RestMethod''s conversion of ISO dates - as well as numbers and strings' {
        (& $script:costRows @(@{ BillingMonth = '2026-07-01T00:00:00' }))[0].BillingMonth | Should -BeOfType [datetime] -Because 'this is what Azure''s rows look like'

        $costs = (& $script:capture { Show-AACCost -PassThru }).Output
        $prodCost = $costs | Where-Object SubscriptionName -eq 'sub-prod'
        $prodCost.($script:key.Invoke(1)) | Should -Be 500
        $prodCost.($script:key.Invoke(5)) | Should -Be 100
        $prodCost.MonthToDate | Should -Be 45
        $prodCost.Total | Should -Be 1545

        $webCost = $costs | Where-Object SubscriptionName -eq 'sub-web'
        $webCost.MonthToDate | Should -Be 7
        $webCost.($script:key.Invoke(1)) | Should -Be 3
    }

    It 'returns each enabled subscription with its status and top services' {
        $costs = (& $script:capture { Show-AACCost -PassThru }).Output

        $costs.SubscriptionName | Sort-Object | Should -Be @('sub-dev', 'sub-prod', 'sub-web') -Because 'the disabled subscription is left out'
        $prodCost = $costs | Where-Object SubscriptionName -eq 'sub-prod'
        $prodCost.Currency | Should -BeExactly 'GBP'
        $prodCost.TopServices | Should -BeLike 'Virtual Machines (30.50)*'
        $prodCost.Status | Should -BeExactly 'OK'
        ($costs | Where-Object SubscriptionName -eq 'sub-dev').Status | Should -BeLike '*not available*'
    }

    It 'draws the tiles, charts and the month table with totals, and lists what could not be read' {
        $text = (& $script:capture { Show-AACCost }).Text

        foreach ($expected in 'Azure cost', 'month to date', '52.00 GBP', 'Month to date by subscription (GBP)', 'sub-prod', 'sub-web',
            'Month to date by service (GBP)', 'Virtual Machines', 'Month to date by resource group', 'rg-app', 'Last 6 months (GBP)',
            '(to date)', 'Actual cost by subscription and month (GBP)', 'Total', '1,555.00',
            'sub-dev: Cost Management data is not available') {
            $text | Should -BeLike "*$expected*"
        }
    }

    It 'draws only characters a legacy console (code page 437/850) can show' {
        $text = (& $script:capture { Show-AACCost } -Ascii).Text
        $text | Should -BeLike '*Actual cost by subscription and month*'
        # Every character must exist in the legacy code pages Windows consoles
        # use (437, 850) - anything else would be printed as '?'.
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ } | ForEach-Object { 'U+{0:X4}' -f [int]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'says so when Cost Management reports no cost, instead of drawing empty charts' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -ParameterFilter { $SubscriptionId -eq '44444444-4444-4444-4444-444444444444' } -MockWith {
            [pscustomobject]@{ Cost = 0; BillingMonth = [datetime]::Today; ServiceName = 'Log Analytics'; ResourceGroupName = 'rg-siem'; Currency = 'GBP' }
        }
        $text = (& $script:capture { Show-AACCost -SubscriptionId '44444444-4444-4444-4444-444444444444' -Months 3 }).Text
        $text | Should -BeLike '*Cost Management reports no cost*'
        $text | Should -Not -BeLike '*Last 3 months (GBP)*' -Because 'no empty charts are drawn'
        $text | Should -Not -BeLike '*Actual cost by subscription and month*'
    }

    It 'flags rows whose month cannot be read instead of showing a silent zero' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -ParameterFilter { $SubscriptionId -eq '44444444-4444-4444-4444-444444444444' } -MockWith {
            [pscustomobject]@{ Cost = 9; BillingMonth = 'not a date'; ServiceName = 'Storage'; ResourceGroupName = 'rg'; Currency = 'GBP' }
        }
        $costs = (& $script:capture { Show-AACCost -SubscriptionId '44444444-4444-4444-4444-444444444444' -PassThru }).Output
        $costs[0].Status | Should -BeLike "*month that couldn't be read*"
    }

    It 'writes the detail to CSV: one row per subscription, month, resource group and service' {
        $csv = Join-Path -Path $TestDrive -ChildPath 'out/cost.csv'
        $null = & $script:capture { Show-AACCost -CsvPath $csv }

        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 10 -Because 'sub-prod has 5 + 3 rows and sub-web 2; sub-dev could not be read'
        $rows[0].PSObject.Properties.Name | Should -Be @('SubscriptionName', 'SubscriptionId', 'Month', 'ResourceGroup', 'Service', 'Cost', 'Currency')
        $keyVault = $rows | Where-Object Service -eq 'Key Vault'
        $keyVault.Month | Should -BeExactly ($script:key.Invoke(0))
        $keyVault.ResourceGroup | Should -BeExactly 'rg-sec'
        [double]$keyVault.Cost | Should -Be 2.25
    }

    It 'writes a PDF report, and only the progress and the file on the console' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path -Path $TestDrive -ChildPath 'cost.pdf'
        $text = (& $script:capture { Show-AACCost -PdfPath $pdf -Months 3 }).Text
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
        $text | Should -BeLike "*PDF: $pdf*"
        $text | Should -Not -BeLike '*Month to date by*' -Because 'an export shows no view'
    }

    It 'writes an interactive HTML report of the detail' {
        $html = Join-Path -Path $TestDrive -ChildPath 'cost.html'
        $text = (& $script:capture { Show-AACCost -HtmlPath $html -Months 3 }).Text
        $text | Should -BeLike "*HTML: $html*"
        $text | Should -Not -BeLike '*Month to date by*'
        $page = Get-Content -LiteralPath $html -Raw
        $model = [regex]::Match($page, '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('subscriptions', 'detail')
        ($model.tables | Where-Object id -EQ 'detail').rows.Count | Should -BeGreaterThan 0
        $model.notices.text | Should -BeLike '*sub-dev*'
    }

    It 'asks Cost Management once per subscription, for the -Months period, by service and resource group' {
        $null = & $script:capture { Show-AACCost -SubscriptionId '11111111-1111-1111-1111-111111111111' -Months 3 }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -ParameterFilter {
            $Body.timePeriod.from -eq $script:thisMonth.AddMonths(-2).ToString('yyyy-MM-ddT00:00:00Z', [cultureinfo]::InvariantCulture) -and
            $Body.dataset.granularity -eq 'Monthly' -and
            (($Body.dataset.grouping | ForEach-Object { $_.name }) -join ',') -eq 'ServiceName,ResourceGroupName'
        } -Times 1 -Exactly
    }
}

Describe 'Azure Admin Console - Invoke-AACCostQuery' {
    It 'turns Cost Management columns and rows into objects and follows nextLink' {
        InModuleScope 'Azure.Admin.Console' {
            Mock Get-AACAccessToken { 'fake-token' }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*api-version=2023-11-01' } -MockWith {
                [pscustomobject]@{ properties = [pscustomobject]@{
                        columns  = @([pscustomobject]@{ name = 'Cost' }, [pscustomobject]@{ name = 'ServiceName' }, [pscustomobject]@{ name = 'Currency' })
                        rows     = @(, @(10.5, 'Storage', 'USD'))
                        nextLink = 'https://management.azure.com/next-page'
                    }
                }
            }
            Mock Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://management.azure.com/next-page' } -MockWith {
                [pscustomobject]@{ properties = [pscustomobject]@{
                        columns = @([pscustomobject]@{ name = 'Cost' }, [pscustomobject]@{ name = 'ServiceName' }, [pscustomobject]@{ name = 'Currency' })
                        rows    = @(, @(2, 'Key Vault', 'USD'))
                    }
                }
            }

            $rows = @(Invoke-AACCostQuery -SubscriptionId '11111111-1111-1111-1111-111111111111' -Body @{ type = 'ActualCost' })
            $rows.Count | Should -Be 2
            $rows[0].ServiceName | Should -BeExactly 'Storage'
            $rows[0].Cost | Should -Be 10.5
            $rows[1].ServiceName | Should -BeExactly 'Key Vault'
        }
    }
}
