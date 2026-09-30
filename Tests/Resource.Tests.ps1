<#
    Unit tests for Show-AACResource. Resource Graph is mocked with hand-built
    rows and the Spectre console is captured, so no Azure call is made.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - Show-AACResource' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/GraphBatchShim.ps1')
        # Runs a script block with the Spectre console writing plain text into
        # a buffer; returns the text and whatever the script block output.
        $script:capture = {
            param([scriptblock] $Render, [switch] $Ascii)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            # No CI detection: on GitHub Actions (or Azure Pipelines...) Spectre's
            # default enrichers would switch on ANSI colour and Unicode, overriding
            # what this console is set to - and the text checks would fail.
            $settings.Enrichment.UseDefaultEnrichers = $false
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
    }

    BeforeEach {
        $sub = '11111111-1111-1111-1111-111111111111'
        $byType = '[{"name":"microsoft.compute/virtualmachines","n":40},{"name":"microsoft.network/networkinterfaces","n":38},{"name":"microsoft.storage/storageaccounts","n":12},{"name":"microsoft.keyvault/vaults","n":6},{"name":"microsoft.web/sites","n":4}]' | ConvertFrom-Json
        $byGroup = "[{`"subscriptionId`":`"$sub`",`"name`":`"rg-app`",`"n`":70},{`"subscriptionId`":`"$sub`",`"name`":`"rg-net`",`"n`":30}]" | ConvertFrom-Json
        $totals = '[{"resources":100,"types":5,"locations":2,"groups":2,"subscriptions":1}]' | ConvertFrom-Json
        $subscriptions = "[{`"subscriptionId`":`"$sub`",`"name`":`"sub-prod`"}]" | ConvertFrom-Json

        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { & $script:graphBatchShim $Query $SubscriptionId $ManagementGroupId $AsObject $AllowFailure }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'by name = tolower\(type\)' } -MockWith { $byType }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'by subscriptionId, name = tolower\(resourceGroup\)' } -MockWith { $byGroup }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'dcount' } -MockWith { $totals }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match '^resourcecontainers' } -MockWith { $subscriptions }.GetNewClosure()
    }

    It 'writes an interactive HTML inventory instead of the view' {
        $inventory = "[{`"id`":`"/subscriptions/$sub/resourceGroups/rg-app/providers/Microsoft.Web/sites/app1`",`"name`":`"app1`",`"type`":`"microsoft.web/sites`",`"location`":`"uksouth`",`"resourceGroup`":`"rg-app`",`"subscriptionId`":`"$sub`",`"kind`":`"app`",`"sku`":`"`",`"tags`":`"{\`"Owner\`":\`"ops\`"}`"}]" | ConvertFrom-Json
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match '\| project id, name' } -MockWith { $inventory }.GetNewClosure()
        $html = Join-Path -Path $TestDrive -ChildPath 'inventory.html'
        $text = (& $script:capture { Show-AACResource -HtmlPath $html }).Text
        $text | Should -BeLike "*HTML: $html*"
        $text | Should -Not -BeLike '*Resources by type*' -Because 'an export shows no view'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $row = $model.tables[0].rows[0]
        $row.Name | Should -Be 'app1'
        $row.SubscriptionName | Should -Be 'sub-prod'
        $row.Tags | Should -Be 'Owner=ops'
        $row.ResourceId | Should -BeLike '*/sites/app1'
    }

    It 'returns every count, largest first, with its share' {
        $counts = (& $script:capture { Show-AACResource -PassThru }).Output

        $counts.Count | Should -Be 5
        $counts[0].Name | Should -BeExactly 'compute/virtualmachines'
        $counts[0].Count | Should -Be 40
        $counts[0].Share | Should -Be 40
        ($counts | Measure-Object Count -Sum).Sum | Should -Be 100
    }

    It 'draws the tiles and a bar per type, with the rest summed in one bar' {
        $text = (& $script:capture { Show-AACResource -Top 3 }).Text

        foreach ($expected in 'Azure resources', 'resources', 'resource types', 'Resources by type (top 3 of 5)', 'compute/virtualmachines', 'network/networkinterfaces', '2 other types') {
            $text | Should -BeLike "*$expected*"
        }
        $text | Should -Not -BeLike '*keyvault/vaults*' -Because 'types beyond -Top are summed into the last bar'
    }

    It 'counts by resource group, naming each group''s subscription' {
        $counts = (& $script:capture { Show-AACResource -By ResourceGroup -PassThru }).Output
        $counts.Name | Should -Be @('rg-app (sub-prod)', 'rg-net (sub-prod)')
    }

    It 'turns -ResourceType wildcards into a Resource Graph filter' {
        $null = & $script:capture { Show-AACResource -ResourceType 'microsoft.network/*' }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter {
            $Query -match [regex]::Escape("matches regex @'^microsoft\.network/.*$'")
        } -Times 2 -Exactly
    }

    It 'says so when nothing matches' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'by name = tolower\(type\)' } -MockWith { }
        $result = & $script:capture { Show-AACResource -ResourceType 'microsoft.nothing/*' -PassThru }
        $result.Output | Should -BeNullOrEmpty
        $result.Text | Should -BeLike '*No resources*'
    }

    It 'draws only characters a legacy console (code page 437/850) can show' {
        $text = (& $script:capture { Show-AACResource } -Ascii).Text
        $text | Should -BeLike '*Resources by type*'
        # Every character must exist in the legacy code pages Windows consoles
        # use (437, 850) - anything else would be printed as '?'.
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ } | ForEach-Object { 'U+{0:X4}' -f [int]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'rejects a -ResourceType that could break the query' {
        { Show-AACResource -ResourceType "x' | take 1" } | Should -Throw
    }
}
