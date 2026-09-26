function Invoke-AACPester {
    <#
    .SYNOPSIS
        Runs any Pester v5 tests and renders the results with Spectre.Console:
        a table of every test, a tree grouped by file and block with the
        failures called out, a pass/fail chart, a summary and a banner.
    .DESCRIPTION
        A generic front end to Invoke-Pester. Point it at any test file or
        folder - this module's bundled Checks folder (the Azure estate
        check) is only the default. You
        get back a normal Pester result object (with -PassThru) that CI
        already understands, and a readable report for whoever is watching
        the console.

        -Data passes values to the test files' own param() blocks, e.g. the
        subscriptions to check in AzureEstate.Tests.ps1. Each file is given only
        the values its param() block declares, so -Data works on a whole
        folder: files that don't take a value simply don't get it.

        While Pester runs, a Spectre.Console progress display shows what is
        happening: a line for the Pester run, and lines of their own for test
        files that report progress - the bundled estate check shows reading
        the estate and evaluating its rules, rule by rule, with a percentage
        and elapsed time. PowerShell's own progress bars and the REST calls'
        verbose output are kept out of the way. Spectre.Console allows only
        one live display at a time, so if the tests themselves draw a Spectre
        spinner, progress bar or live display, run with -NoSpinner.

        Tests that talk to Azure use the Connect-AAC sign-in from this session.
        Run Connect-AAC first; the bundled Azure test reports Skipped without it.

        A report longer than the terminal is shown one screen at a time:
        press any key for the next page, or A to show the rest. Paging is
        skipped automatically when output is redirected or with -CI, and can
        be turned off with -NoPaging.

        -PdfPath also saves the results as an A4 PDF report - a summary
        with the verdict, pass/fail counts per check, and every test with
        its failure message - honouring -FailedOnly.
    .PARAMETER Path
        One or more test files or folders. Folders are searched recursively
        for *.Tests.ps1 files. Defaults to this module's bundled Checks
        folder (AzureEstate.Tests.ps1).
    .PARAMETER Tag
        Only run tests (or blocks) with at least one of these tags.
    .PARAMETER ExcludeTag
        Skip tests (or blocks) with any of these tags.
    .PARAMETER TestName
        Only run tests whose full name (Describe, Context and It joined with
        dots) matches one of these wildcard patterns. For data-driven tests
        (-ForEach), Pester matches the name template, e.g. "<Name>", not the
        expanded value, so filter those with -Tag instead.
    .PARAMETER Data
        Values for the test files' param() blocks.
    .PARAMETER CI
        Also write a JUnit XML result file for CI pipelines.
    .PARAMETER OutputPath
        Where -CI writes the JUnit file. Defaults to TestResults.xml in the
        current directory.
    .PARAMETER NoSpinner
        Run Pester without the spinner, for tests that draw their own
        Spectre.Console live output.
    .PARAMETER NoPaging
        Show the whole report at once instead of a page at a time.
    .PARAMETER FailedOnly
        List only failed tests in the report (and the -PdfPath PDF). The
        counts, summary and verdict still cover every test, and the -PassThru
        result and -CI file are unchanged.
    .PARAMETER PdfPath
        Also write the results to this PDF file. Needs Windows and PowerShell
        7.4 or later.
    .PARAMETER PassThru
        Also return the Pester result object, in addition to rendering the report.
    .EXAMPLE
        Invoke-AACPester -Path .\Tests
        Runs every *.Tests.ps1 file under .\Tests and shows the report.
    .EXAMPLE
        Connect-AAC
        Invoke-AACPester -Tag 'Governance' -Data @{ AllowedLocation = 'uksouth', 'global' }
        Runs the bundled estate check's governance rules, accepting resources in UK South or the "global" location.
    .EXAMPLE
        Connect-AAC
        Invoke-AACPester -Data @{ SubscriptionId = '00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111' }
        Runs the bundled estate check against those two subscriptions only.
    .EXAMPLE
        Invoke-AACPester -Path .\Tests -Tag 'Smoke' -ExcludeTag 'Slow'
        Runs only the tests tagged Smoke, leaving out any tagged Slow.
    .EXAMPLE
        Invoke-AACPester -Path .\Tests -CI -OutputPath .\out\results.xml
        Runs the tests, shows the report and writes JUnit results for the pipeline.
    .EXAMPLE
        Connect-AAC
        Invoke-AACPester -FailedOnly -Data @{ ResourceType = 'microsoft.network/*' }
        Checks only networking resources and lists only what failed.
    .EXAMPLE
        Invoke-AACPester -PdfPath .\out\AzureEstate.pdf
        Shows the report and saves it as a PDF as well.
    .EXAMPLE
        $result = Invoke-AACPester -Path .\Tests -PassThru
        if ($result.FailedCount -gt 0) { exit 1 }
        Fails a build script when any test fails.
    .OUTPUTS
        Pester.Run (with -PassThru)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]] $Path = (Join-Path -Path $script:AACModuleRoot -ChildPath 'Checks'),

        [string[]] $Tag,

        [string[]] $ExcludeTag,

        [string[]] $TestName,

        [hashtable] $Data,

        [switch] $CI,

        [string] $OutputPath = (Join-Path -Path (Get-Location) -ChildPath 'TestResults.xml'),

        [switch] $NoSpinner,

        [switch] $NoPaging,

        [switch] $FailedOnly,

        [string] $PdfPath,

        [switch] $PassThru
    )

    if (-not (Get-Module -Name Pester -ListAvailable | Where-Object Version -ge '5.0.0')) {
        throw 'Pester 5.0.0 or later is required. Run: Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser'
    }

    $missingPaths = @($Path | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missingPaths.Count -gt 0) {
        throw "The following Pester test path(s) do not exist: $($missingPaths -join ', ')"
    }

    Write-AACRule -Title 'Azure Admin Console :: Pester' -Color 'deepskyblue3_1'

    $pesterConfiguration = New-PesterConfiguration
    $pesterConfiguration.Run.PassThru = $true
    $pesterConfiguration.Output.Verbosity = 'None'

    if ($Data) {
        # Data can only be given per container, so expand folders into their
        # test files. Pester rejects a value for a parameter the file doesn't
        # declare, so each file gets only the keys in its own param() block.
        $testFiles = @(foreach ($item in $Path) {
                if (Test-Path -LiteralPath $item -PathType Container) {
                    Get-ChildItem -LiteralPath $item -Filter '*.Tests.ps1' -File -Recurse | Select-Object -ExpandProperty FullName
                }
                else {
                    (Resolve-Path -LiteralPath $item).Path
                }
            })
        if ($testFiles.Count -eq 0) {
            throw "No *.Tests.ps1 files were found under: $($Path -join ', ')"
        }
        $usedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $pesterConfiguration.Run.Container = @(foreach ($testFile in $testFiles) {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($testFile, [ref]$null, [ref]$null)
                $declared = @(if ($ast.ParamBlock) { $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath } })

                $fileData = @{}
                foreach ($key in $Data.Keys) {
                    if ($key -in $declared) {
                        $fileData[$key] = $Data[$key]
                        $usedKeys.Add($key) | Out-Null
                    }
                }

                if ($fileData.Count -gt 0) {
                    New-PesterContainer -Path $testFile -Data $fileData
                }
                else {
                    New-PesterContainer -Path $testFile
                }
            })

        $unused = @($Data.Keys | Where-Object { -not $usedKeys.Contains($_) })
        if ($unused.Count -gt 0) {
            Write-Warning "No test file declares these -Data parameters, so they were ignored: $($unused -join ', ')"
        }
    }
    else {
        $pesterConfiguration.Run.Path = $Path
    }

    if ($Tag) {
        $pesterConfiguration.Filter.Tag = $Tag
    }
    if ($ExcludeTag) {
        $pesterConfiguration.Filter.ExcludeTag = $ExcludeTag
    }
    if ($TestName) {
        $pesterConfiguration.Filter.FullName = $TestName
    }

    if ($CI) {
        $pesterConfiguration.TestResult.Enabled = $true
        $pesterConfiguration.TestResult.OutputFormat = 'JUnitXml'
        $pesterConfiguration.TestResult.OutputPath = $OutputPath
    }

    # PowerShell's own progress bars (web requests, Write-Progress in tests)
    # would draw over the Spectre display.
    $ProgressPreference = 'SilentlyContinue'
    $pesterResult = if ($NoSpinner) {
        Write-AACMarkup '[grey58]Running Pester tests...[/]'
        Invoke-Pester -Configuration $pesterConfiguration
    }
    else {
        Invoke-AACProgress -ScriptBlock {
            Update-AACProgress -Id 'pester' -Description 'Running Pester tests' -Indeterminate
            $result = Invoke-Pester -Configuration $pesterConfiguration
            Update-AACProgress -Id 'pester' -Complete -Description ('Pester: {0:N0} tests - {1:N0} passed, {2:N0} failed, {3:N0} skipped' -f $result.TotalCount, $result.PassedCount, $result.FailedCount, $result.SkippedCount)
            $result
        }
    }

    Invoke-AACPagedOutput -NoPaging:($NoPaging -or $CI) -ScriptBlock {
        Write-AACPesterReport -PesterResult $pesterResult -FailedOnly:$FailedOnly
    }

    if ($CI) {
        Write-AACMarkup "[grey58]JUnit results written to $([Spectre.Console.Markup]::Escape($OutputPath))[/]"
    }

    if ($PdfPath) {
        # What was run, for the PDF's summary page.
        $detail = [ordered]@{ 'Test path' = ($Path -join ', ') }
        if ($Tag) { $detail['Tag'] = $Tag -join ', ' }
        if ($ExcludeTag) { $detail['Excluded tag'] = $ExcludeTag -join ', ' }
        if ($TestName) { $detail['Test name'] = $TestName -join ', ' }
        if ($Data) {
            $detail['Settings'] = (@($Data.Keys | Sort-Object | ForEach-Object { "$_ = $(@($Data[$_]) -join ', ')" }) -join '; ')
        }
        # A failed export is reported but doesn't lose the run: the console
        # report is already shown and -PassThru still returns the result.
        try {
            $pdfFullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PdfPath)
            $null = Invoke-AACExport -PdfPath $pdfFullPath -WritePdf {
                Write-AACPesterReportPdf -PesterResult $pesterResult -Path $pdfFullPath -Detail $detail -FailedOnly:$FailedOnly
            }
        }
        catch {
            Write-Error -Message "Could not write the PDF report: $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    if ($PassThru) {
        return $pesterResult
    }
}
