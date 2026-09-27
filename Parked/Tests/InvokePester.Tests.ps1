<#
    Unit tests for Invoke-AACPester. Pester can't safely run inside a Pester
    run, so each test runs Invoke-AACPester in a child pwsh process against a
    small sample test file, and reads back its result as JSON.
#>

BeforeDiscovery {
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

Describe 'Azure Admin Console - Invoke-AACPester' {
    BeforeAll {
        $script:manifest = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../Azure.Admin.Console.psd1')).Path
        $script:sample = Join-Path -Path $TestDrive -ChildPath 'Sample.Tests.ps1'
        Set-Content -LiteralPath $script:sample -Encoding utf8 -Value @'
param([string] $Greeting = 'hello')

Describe 'Sample' {
    It 'passes' { 1 | Should -Be 1 }
    It 'gets -Data' { $Greeting | Should -Be 'hi' }
    It 'fails' { 1 | Should -Be 2 }
    It 'is skipped' -Skip { }
}
'@

        # Runs Invoke-AACPester in a child process with these arguments (a
        # PowerShell expression) and returns the result counts and the output.
        $script:run = {
            param([string] $Arguments)
            $command = @"
Import-Module '$script:manifest'
`$r = Invoke-AACPester -Path '$script:sample' -NoPaging -PassThru $Arguments
'RESULT=' + (@{ Passed = `$r.PassedCount; Failed = `$r.FailedCount; Skipped = `$r.SkippedCount } | ConvertTo-Json -Compress)
"@
            $output = @(& pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" })
            $json = $output | Where-Object { $_ -like 'RESULT=*' } | Select-Object -Last 1
            [pscustomobject]@{
                Result = if ($json) { $json.Substring(7) | ConvertFrom-Json } else { $null }
                Output = $output -join "`n"
            }
        }
    }

    It 'runs the tests, shows the report and returns the Pester result' {
        $run = & $script:run ''
        $run.Result.Passed | Should -Be 1
        $run.Result.Failed | Should -Be 2 -Because 'without -Data, $Greeting keeps its default'
        $run.Result.Skipped | Should -Be 1
        $run.Output | Should -BeLike '*FAILED*'
        $run.Output | Should -BeLike '*Pester: 4 tests*'
    }

    It 'passes -Data to the test file''s parameters and lists only failures with -FailedOnly' {
        $run = & $script:run "-Data @{ Greeting = 'hi' } -FailedOnly"
        $run.Result.Passed | Should -Be 2
        $run.Result.Failed | Should -Be 1
        $run.Output | Should -BeLike '*fails*'
    }

    It 'writes JUnit XML with -CI' {
        $xml = Join-Path -Path $TestDrive -ChildPath 'results.xml'
        $null = & $script:run "-CI -OutputPath '$xml'"
        ([xml](Get-Content -LiteralPath $xml -Raw)).testsuites.tests | Should -Be 4
    }

    It 'writes a PDF report with -PdfPath' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path -Path $TestDrive -ChildPath 'report.pdf'
        $null = & $script:run "-PdfPath '$pdf'"
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }

    It 'writes a self-contained HTML report with -HtmlPath' {
        $html = Join-Path -Path $TestDrive -ChildPath 'report.html'
        $null = & $script:run "-HtmlPath '$html'"
        $text = Get-Content -LiteralPath $html -Raw
        $text | Should -Not -Match '<script[^>]+src=' -Because 'the page must work offline'
        $text | Should -Not -Match '<link[^>]+stylesheet'
        $json = [regex]::Match($text, '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value
        $model = $json | ConvertFrom-Json
        $model.counts.total | Should -Be 4
        $model.counts.failed | Should -Be 2
        @($model.tests).Count | Should -Be 4
        ($model.tests | Where-Object name -EQ 'fails').message | Should -BeLike '*Expected 2*'
    }

    It 'keeps test data that looks like HTML inside the HTML report''s data' {
        $file = Join-Path -Path $TestDrive -ChildPath 'Resource.Tests.ps1'
        Set-Content -LiteralPath $file -Encoding utf8 -Value @'
Describe 'Area' {
    Context 'Check' {
        It '<Name>' -ForEach @(@{ Name = 'st01'; ResourceId = '/subscriptions/1/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st01'; Type = 'microsoft.storage/storageaccounts'; RG = 'rg'; Subscription = 'sub'; Because = 'PSRule Azure.Storage.MinTLS' }) {
            throw '</script><b>not markup</b>'
        }
    }
}
'@
        $html = Join-Path -Path $TestDrive -ChildPath 'resource.html'
        & pwsh -NoProfile -NonInteractive -Command "Import-Module '$script:manifest'; `$null = Invoke-AACPester -Path '$file' -NoPaging -HtmlPath '$html' -FailedOnly" 2>&1 | Out-Null
        $text = Get-Content -LiteralPath $html -Raw
        $json = [regex]::Match($text, '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value
        $json | Should -Not -BeLike '*<b>*' -Because '< and > are escaped, so the data cannot close its <script> element'
        $test = @(($json | ConvertFrom-Json).tests)[0]
        $test.message | Should -Be '</script><b>not markup</b>'
        $test.resourceId | Should -BeLike '*/storageAccounts/st01'
        $test.check | Should -Be 'Check'
        $test.rule | Should -Be 'Azure.Storage.MinTLS'
        $test.ruleLink | Should -Be 'https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.Storage.MinTLS/'
    }

    It 'runs the PSRule for Azure check with -PSRule, skipping it without a sign-in' {
        $run = & pwsh -NoProfile -NonInteractive -Command "Import-Module '$script:manifest'; `$r = Invoke-AACPester -PSRule -NoPaging -PassThru; 'RESULT=' + `$r.Containers[0].Item + '|' + `$r.SkippedCount + '|' + `$r.FailedCount" 2>&1
        $result = ($run | Where-Object { "$_" -like 'RESULT=*' } | Select-Object -Last 1) -replace '^RESULT=', ''
        $item, $skipped, $failed = $result -split '\|'
        $item | Should -BeLike '*PSRuleForAzure.Tests.ps1'
        $skipped | Should -Be 1
        $failed | Should -Be 0
    }

    It 'passes -SubscriptionId to the test file, and refuses it in -Data as well' {
        $file = Join-Path -Path $TestDrive -ChildPath 'Subscription.Tests.ps1'
        Set-Content -LiteralPath $file -Encoding utf8 -Value @'
param([string[]] $SubscriptionId = @())
Describe 'Subscriptions' {
    It 'gets both' { $SubscriptionId | Should -Be @('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002') }
}
'@
        $command = "Import-Module '$script:manifest'; `$r = Invoke-AACPester -Path '$file' -NoPaging -PassThru -SubscriptionId '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002'; 'RESULT=' + `$r.PassedCount; try { Invoke-AACPester -Path '$file' -SubscriptionId '00000000-0000-0000-0000-000000000001' -Data @{ SubscriptionId = 'x' } } catch { 'ERROR=' + `$_.Exception.Message }"
        $output = @(& pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" })
        ($output | Where-Object { $_ -like 'RESULT=*' }) | Should -Be 'RESULT=1'
        ($output | Where-Object { $_ -like 'ERROR=*' }) | Should -BeLike '*not both*'
    }

    It 'fails clearly for a path that does not exist' {
        $run = & pwsh -NoProfile -NonInteractive -Command "Import-Module '$script:manifest'; try { Invoke-AACPester -Path './no-such-folder' } catch { 'ERROR=' + `$_.Exception.Message }" 2>&1
        ($run | Where-Object { "$_" -like 'ERROR=*' }) | Should -BeLike '*do not exist*'
    }
}
