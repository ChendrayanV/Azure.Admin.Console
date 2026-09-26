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

    It 'fails clearly for a path that does not exist' {
        $run = & pwsh -NoProfile -NonInteractive -Command "Import-Module '$script:manifest'; try { Invoke-AACPester -Path './no-such-folder' } catch { 'ERROR=' + `$_.Exception.Message }" 2>&1
        ($run | Where-Object { "$_" -like 'ERROR=*' }) | Should -BeLike '*do not exist*'
    }
}
