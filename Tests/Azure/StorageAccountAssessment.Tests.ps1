<#
    Unit tests for Invoke-AACStorageAccountAssessment: the Storage accounts
    workbook's Overview (transactions, latency, response types) and Capacity
    tabs, plus availability, posture, data protection, cost, findings and
    the heat map - with Resource Graph, Azure Monitor and the storage
    services' settings mocked (Fixtures\ContosoStorageAssessment.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoStorageAssessment.ps1')
    $script:st = Get-AACContosoStorageAssessment
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
}

Describe 'Azure Admin Console - Invoke-AACStorageAccountAssessment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { $script:st.Scope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @($script:st.Graph[$n]) }; @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $path = ($u -split '\?', 2)[0]
                if ($path -match '/providers/Microsoft\.Insights/metrics$') {
                    $resource = ($u -split '/providers/Microsoft.Insights/metrics', 2)[0]
                    $names = [System.Uri]::UnescapeDataString(($u -split 'metricnames=')[1])
                    $call = if ($u -match 'ResponseType') { 'Responses' } elseif ($names -match 'Capacity|Count') { 'Capacity' } else { 'Core' }
                    $body = $script:st.Metrics["$resource|$call"]
                    $out[$u] = if ($body) { @{ Status = 200; Body = $body; Items = $null; Error = '' } } else { @{ Status = 400; Body = $null; Items = $null; Error = 'Failed to find metric configuration.' } }
                    continue
                }
                $account, $part = switch -Regex ($path) {
                    '^(.+)/blobServices/default/providers/Microsoft\.Insights/diagnosticSettings$' { $Matches[1], 'Logs'; break }
                    '^(.+)/blobServices/default$' { $Matches[1], 'Blob'; break }
                    '^(.+)/fileServices/default$' { $Matches[1], 'File'; break }
                    '^(.+)/managementPolicies/default$' { $Matches[1], 'Lifecycle'; break }
                }
                $answer = $script:st.Settings["$account|$part"]
                $out[$u] = if ($null -eq $answer) { @{ Status = 404; Body = $null; Items = $null; Error = 'The resource was not found.' } }
                elseif ($part -eq 'Logs') { @{ Status = 200; Body = @{}; Items = @($answer); Error = '' } }
                else { @{ Status = 200; Body = @{ properties = $answer }; Items = $null; Error = '' } }
            }
            $out
        }
    }

    It 'reads the workbook''s Overview: transactions, availability, latency, response types and traffic' {
        $a = @(Invoke-AACStorageAccountAssessment -NoDisplay)
        $prod = $a | Where-Object Account -EQ 'stprod'
        "$($prod.Availability) $($prod.Transactions) $($prod.Successes) $($prod.Throttled) $($prod.ServerErrors) $($prod.AuthErrors) $($prod.ClientErrors)" | Should -Be '99.97 10000 9700 150 20 30 100'
        $prod.ErrorRate | Should -Be 2 -Because 'throttling, server and authorization errors count; ClientOther (404) does not'
        "$($prod.E2ELatencyMs) $($prod.ServerLatencyMs) $($prod.ClientLatencyMs) $($prod.IngressGB) $($prod.EgressGB)" | Should -Be '50 15 35 2 5'
        $prod.ResponseTypes | Should -Be 'ClientThrottlingError 150, ClientOtherError 100, AuthorizationError 30, ServerTimeoutError 20'
        $prod.PSObject.TypeNames | Should -Contain 'AAC.StorageAccountAssessment'
    }

    It 'reads the workbook''s Capacity: the latest value by service, hourly over at least two days' {
        $a = @(Invoke-AACStorageAccountAssessment -TimeRange 4h -NoDisplay)
        $prod = $a | Where-Object Account -EQ 'stprod'
        "$($prod.UsedGB) $($prod.BlobGB) $($prod.FileGB) $($prod.Blobs) $($prod.Containers) $($prod.FileShares)" | Should -Be '500 400 100 1000000 12 3'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter {
            $blob = @($Uri | Where-Object { $_ -match 'BlobCapacity' })[0]
            $blob -and $blob -match 'interval=PT1H' -and $blob -match 'timespan=(\S+?)/' -and ([datetime]::UtcNow - [datetime]$Matches[1]).TotalHours -ge 47
        }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -match 'interval=PT15M' -and $_ -match 'SuccessE2ELatency' }).Count -eq 3 }
    }

    It 'reads posture and data protection' {
        $a = @(Invoke-AACStorageAccountAssessment -NoDisplay)
        $prod = $a | Where-Object Account -EQ 'stprod'
        "$($prod.Network) $($prod.PrivateEndpoints) $($prod.MinTls) $($prod.SharedKeyAccess) $($prod.Redundancy) $($prod.Defender) $($prod.LogsTo)" | Should -Be 'Private 1 TLS1_2 False GZRS On law-prod'
        "$($prod.BlobSoftDeleteDays) $($prod.ContainerSoftDeleteDays) $($prod.Versioning) $($prod.ChangeFeed) $($prod.ShareSoftDeleteDays) $($prod.LifecycleRules)" | Should -Be '14 7 True True 7 2'
        $legacy = $a | Where-Object Account -EQ 'stlegacy'
        "$($legacy.Network) $($legacy.Redundancy) $($legacy.KeyAgeDays) $($legacy.LifecycleRules) [$($legacy.LogsTo)] $($legacy.Defender) $($legacy.Transactions)" | Should -Be 'Public LRS 200 0 [] Off 0'
        ($a | Where-Object Account -EQ 'starchive').Network | Should -Be 'Firewall'
    }

    It 'finds what to fix: health, security, protection and cost' {
        $f = @(Invoke-AACStorageAccountAssessment -View Finding -NoDisplay)
        $one = { param($Account, $Finding) $f | Where-Object { $_.Account -eq $Account -and $_.Finding -eq $Finding } }
        (& $one 'stprod' 'Requests throttled').Severity | Should -Be 'High' -Because '150 of 10,000 is 1.5%'
        (& $one 'stprod' 'Authorization or authentication failures').Severity | Should -Be 'Medium'
        (& $one 'stprod' 'Server errors and timeouts').Severity | Should -Be 'Medium'
        @($f | Where-Object { $_.Account -eq 'stprod' -and $_.Signal -in 'Security', 'Protection', 'Cost' }) | Should -BeNullOrEmpty
        foreach ($finding in 'HTTP allowed', 'TLS below 1.2 accepted', 'Anonymous blob access allowed', 'Open to every network', 'Shared key access allowed', 'Account keys not rotated in 90+ days', 'No key expiration policy', 'No SAS expiration policy', 'Cross-tenant replication allowed', 'No blob logs to Log Analytics', 'Defender for Storage off', 'Locally redundant only (LRS)', 'Blob soft delete off', 'Container soft delete off', 'File share soft delete off', 'General-purpose v1 account', 'No lifecycle management', 'No transactions in the period') {
            & $one 'stlegacy' $finding | Should -Not -BeNullOrEmpty -Because $finding
        }
        foreach ($finding in 'Hot tier with little activity', 'Blob soft delete under 7 days', 'No lifecycle management') { & $one 'starchive' $finding | Should -Not -BeNullOrEmpty -Because $finding }
        (& $one 'starchive' 'Hot tier with little activity').Detail | Should -BeLike '*2,000 GB*500 transactions a day*'
        $f[0].Severity | Should -Be 'High'
        $f[0].PSObject.TypeNames | Should -Contain 'AAC.StorageAccountFinding'
    }

    It 'shows the heat map and findings at the prompt, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACStorageAccountAssessment -NoPaging }).Text
        foreach ($expected in 'Storage accounts by signal', 'Protection', 'stprod', 'stlegacy', 'Requests throttled', 'Findings') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes CSV by -View and an HTML report with the heat map and the workbook''s tabs' {
        $csv = Join-Path $TestDrive 'st.csv'
        $html = Join-Path $TestDrive 'st.html'
        $null = & $script:capture { Invoke-AACStorageAccountAssessment -View Finding -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -BeGreaterThan 20
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.heatmaps[0].title | Should -Be 'Storage accounts by signal'
        @($model.heatmaps[0].columns) | Should -Be @('Availability', 'Errors', 'Throttling', 'Latency', 'Security', 'Protection', 'Cost')
        @($model.tables.id) | Should -Be @('accounts', 'capacity', 'protection', 'findings')
    }

    It 'narrows by -Name, and writes a PDF report' -Skip:(-not $script:canWritePdf) {
        @(Invoke-AACStorageAccountAssessment -Name 'stp*' -NoDisplay).Account | Should -Be @('stprod')
        $pdf = Join-Path $TestDrive 'st.pdf'
        $null = & $script:capture { Invoke-AACStorageAccountAssessment -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
