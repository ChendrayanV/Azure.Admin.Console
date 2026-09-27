function Write-AACPesterReportHtml {
    <#
    .SYNOPSIS
        Writes a Pester v5 result as a single, self-contained HTML report.
        Used by Invoke-AACPester -HtmlPath.
    .DESCRIPTION
        One file, no external scripts, styles or fonts - it opens offline,
        from a pipeline artifact or an e-mail attachment. The page has:

          - the verdict, total/passed/failed/skipped/pass-rate tiles (click
            one to filter) and a proportion bar;
          - where the failures are: by area, by check and (when the tests
            name Azure resources) by resource - click a bar to see those
            tests;
          - what was run: account, tenant, settings, computer;
          - every test, searchable ('/' to search), filterable by outcome and
            severity, grouped by check, by resource or by file, with failed
            groups first. Tests of Azure resources link to the resource in
            the Azure portal (and copy its ID); PSRule rules link to their
            documentation, with the rule's recommendation. The filters are
            kept in the page address, so a filtered view can be shared.

        Light and dark themes follow the browser, with a switch. Resource
        details come from the tests' -ForEach data when it has them
        (ResourceId, Name, Type, RG, Subscription, RuleName, Link, Severity,
        Pillar, Recommendation - as the bundled checks provide); any other
        Pester tests are shown by file, block and name.

        With -FailedOnly only failed tests are written; the counts still
        cover every test.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $PesterResult,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Azure Admin Console test report',

        [System.Collections.IDictionary] $Detail,

        [switch] $FailedOnly
    )

    process {
        if (-not (Get-AACPropertyValue -InputObject $PesterResult -Name 'Containers')) {
            throw 'PesterResult must be the object returned by Invoke-AACPester -PassThru or Invoke-Pester -PassThru.'
        }
        $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

        $errorText = {
            param([object] $Record, [int] $MaxLines = 60)
            $errors = @(Get-AACPropertyValue -InputObject $Record -Name 'ErrorRecord')
            if ($errors.Count -eq 0 -or -not $errors[0]) {
                return ''
            }
            $lines = @(([string]$errors[0].Exception.Message).Trim() -split "`r?`n")
            if ($lines.Count -gt $MaxLines) {
                $lines = @($lines | Select-Object -First $MaxLines) + "... ($($lines.Count - $MaxLines) more lines)"
            }
            $lines -join "`n"
        }
        # A value from the test's -ForEach data, as text ('' when absent).
        $dataValue = {
            param($Data, [string[]] $Names)
            if ($Data -isnot [System.Collections.IDictionary]) {
                return ''
            }
            foreach ($name in $Names) {
                if ($Data.Contains($name) -and $null -ne $Data[$name]) {
                    $value = $Data[$name]
                    if ($value -is [string] -or $value -is [ValueType]) {
                        return [string]$value
                    }
                }
            }
            ''
        }

        # --- Every test, in the order it ran ---------------------------------------
        $tests = [System.Collections.Generic.List[object]]::new()
        $files = [System.Collections.Generic.List[object]]::new()
        $counter = @{ n = 0 }
        $collect = {
            param([object] $Block, [string] $File, [string] $Top, [string[]] $Trail)
            foreach ($test in $Block.Tests) {
                $result = [string]$test.Result
                if ($result -notin 'Passed', 'Failed', 'Skipped') {
                    continue
                }
                $counter.n++
                if ($FailedOnly -and $result -ne 'Failed') {
                    continue
                }
                $data = Get-AACPropertyValue -InputObject $test -Name 'Data'
                $message = if ($result -eq 'Failed') { & $errorText $test }
                elseif ($result -eq 'Skipped') { ((& $errorText $test 3) -replace '^is skipped, because ', '') }
                else { '' }

                # PSRule results carry their reasons; the recommendation and rule
                # link are shown once per rule in the page, not in every message.
                if ($result -eq 'Failed' -and $data -is [System.Collections.IDictionary] -and $data.Contains('Reason') -and @($data['Reason']).Count -gt 0) {
                    $message = @($data['Reason'] | ForEach-Object { [string]$_ }) -join "`n"
                }

                $rule = & $dataValue $data 'RuleName'
                $because = & $dataValue $data 'Because'
                if (-not $rule) {
                    # The bundled estate check names the PSRule rule it mirrors.
                    $match = [regex]::Match("$because`n$message", 'PSRule[^A-Za-z0-9]{1,3}(Azure\.[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)')
                    if ($match.Success) { $rule = $match.Groups[1].Value }
                }
                $link = & $dataValue $data 'Link'
                if (-not $link -and $rule) { $link = "https://azure.github.io/PSRule.Rules.Azure/en/rules/$rule/" }
                $resourceId = & $dataValue $data 'ResourceId'

                $tests.Add([ordered]@{
                        order          = $counter.n
                        file           = $File
                        block          = $Top
                        check          = ($Trail -join '  ›  ')
                        name           = [string]$test.ExpandedName
                        result         = $result
                        ms             = [math]::Round($test.Duration.TotalMilliseconds, 1)
                        message        = $message
                        resourceId     = $resourceId
                        resource       = $(if ($resourceId) { & $dataValue $data 'Name' } else { '' })
                        resourceType   = $(if ($resourceId) { & $dataValue $data 'Type' } else { '' })
                        rg             = $(if ($resourceId) { & $dataValue $data 'RG' } else { '' })
                        subscription   = $(if ($resourceId) { & $dataValue $data 'Subscription' } else { '' })
                        rule           = $rule
                        ruleLink       = $link
                        severity       = & $dataValue $data 'Severity'
                        pillar         = & $dataValue $data 'Pillar'
                        recommendation = & $dataValue $data 'Recommendation'
                    })
            }
            foreach ($child in $Block.Blocks) {
                & $collect $child $File $Top (@($Trail) + [string]$child.ExpandedName)
            }
        }
        foreach ($container in @(Get-AACPropertyValue -InputObject $PesterResult -Name 'Containers')) {
            $fileName = Split-Path -Path ([string]$container.Item) -Leaf
            $isBroken = [string]$container.Result -eq 'Failed' -and @($container.Blocks).Count -eq 0
            $files.Add([ordered]@{
                    name   = $fileName
                    broken = $isBroken
                    error  = $(if ($isBroken) { & $errorText $container } else { '' })
                })
            foreach ($block in $container.Blocks) {
                & $collect $block $fileName ([string]$block.ExpandedName) @()
            }
        }

        $brokenCount = @($files | Where-Object { $_.broken }).Count
        $counts = [ordered]@{
            passed  = [int]$PesterResult.PassedCount
            failed  = [int]$PesterResult.FailedCount + $brokenCount
            skipped = [int]$PesterResult.SkippedCount
        }
        $counts['total'] = $counts.passed + $counts.failed + $counts.skipped

        # --- What was run ------------------------------------------------------------
        $facts = [System.Collections.Generic.List[object]]::new()
        $session = Get-Variable -Name 'AACSession' -Scope Global -ValueOnly -ErrorAction Ignore
        $account = ''
        $tenantId = ''
        if ($session) {
            $account = [string]$session.Account
            $tenantId = [string]$session.TenantId
            $facts.Add([ordered]@{ k = 'Azure account'; v = $account })
            $facts.Add([ordered]@{ k = 'Tenant'; v = $tenantId })
        }
        $facts.Add([ordered]@{ k = 'Test files'; v = (@($files | ForEach-Object { $_.name }) -join ', ') })
        if ($Detail) {
            foreach ($key in $Detail.Keys) { $facts.Add([ordered]@{ k = [string]$key; v = [string]$Detail[$key] }) }
        }
        $pester = Get-Module -Name Pester | Sort-Object -Property Version -Descending | Select-Object -First 1
        $psrule = Get-Module -Name 'PSRule.Rules.Azure' | Sort-Object -Property Version -Descending | Select-Object -First 1
        $environment = "PowerShell $($PSVersionTable.PSVersion)$(if ($pester) { " · Pester $($pester.Version)" })$(if ($psrule) { " · PSRule for Azure $($psrule.Version)" })"
        $facts.Add([ordered]@{ k = 'Computer'; v = "$([Environment]::MachineName) · $environment" })

        $moduleInfo = $MyInvocation.MyCommand.Module
        $model = [ordered]@{
            title            = $Title
            generated        = [datetime]::UtcNow.ToString('o', [cultureinfo]::InvariantCulture)
            durationMs       = [math]::Round($PesterResult.Duration.TotalMilliseconds)
            account          = $account
            tenantId         = $tenantId
            moduleVersion    = $(if ($moduleInfo) { "v$($moduleInfo.Version)" } else { '' })
            environment      = $environment
            counts           = $counts
            onlyFailedListed = [bool]$FailedOnly
            files            = $files.ToArray()
            facts            = $facts.ToArray()
            tests            = $tests.ToArray()
        }

        # EscapeHtml turns < > & ' into \u escapes, so no value can close the
        # <script> element the data sits in.
        $json = ConvertTo-Json -InputObject $model -Depth 6 -Compress -EscapeHandling EscapeHtml
        $template = [System.IO.File]::ReadAllText((Join-Path -Path $script:AACModuleRoot -ChildPath 'Private/PesterReport.html'))
        $html = $template.Replace('__AAC_TITLE__', [System.Net.WebUtility]::HtmlEncode($Title)).Replace('__AAC_DATA__', $json)

        $folder = Split-Path -Path $fullPath -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($fullPath, $html, [System.Text.UTF8Encoding]::new($false))
        Get-Item -LiteralPath $fullPath
    }
}
