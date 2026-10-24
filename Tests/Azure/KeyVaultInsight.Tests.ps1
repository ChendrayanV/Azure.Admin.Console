<#
    Unit tests for Get-AACKeyVaultInsight: health from metrics (availability,
    status codes, saturation), posture and audit-log coverage, operations and
    callers from the logs, objects from the data plane, findings and the heat
    map - with Resource Graph, Azure Monitor, Log Analytics and the Key Vault
    data plane mocked (Fixtures\ContosoKeyVault.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoKeyVault.ps1')
    $script:kv = Get-AACContosoKeyVault
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 160
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Get-AACKeyVaultInsight' {
    BeforeEach {
        $script:logCalls = 0
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { $script:kv.Scope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @($script:kv.Graph[$n]) }; @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $vault = ($u -split '/providers/microsoft.insights/', 2, 'IgnoreCase')[0]
                $out[$u] = if ($u -match 'diagnosticSettings') { @{ Status = 200; Body = @{}; Items = @($script:kv.Settings[$vault]); Error = '' } }
                else {
                    $part = if ($u -match 'StatusCode') { 'Results' } elseif ($u -match 'ActivityType') { 'Types' } else { 'Core' }
                    @{ Status = 200; Body = $script:kv.Metrics["$vault|$part"]; Items = $null; Error = '' }
                }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith {
            $script:logCalls++; $script:logQuery = $Query['audit']; $script:logWorkspace = $WorkspaceId
            @{ Rows = @{ audit = @($script:kv.Logs) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttpBatch -MockWith {
            $failures = @{}
            foreach ($req in $Request) {
                $base = ($req.Uri -split '\?')[0]
                if ($base -like 'https://kv-dev*') { $failures[$req.Key] = 'Caller is not authorized to perform action on resource (Forbidden).'; continue }
                $null = & $OnResponse $req.Key (ConvertTo-Json -InputObject $script:kv.DataPlane[$base] -Depth 10)
                $failures[$req.Key] = ''
            }
            $failures
        }
    }

    It 'reads health from metrics: availability, transactions, status codes, latency and saturation' {
        $v = @(Get-AACKeyVaultInsight -NoDisplay)
        $prod = $v | Where-Object Vault -EQ 'kv-prod'
        "$($prod.Availability) $($prod.Transactions) $($prod.Successes) $($prod.Unauthorized) $($prod.Forbidden) $($prod.Throttled)" | Should -Be '99.98 1000 900 50 20 30'
        $prod.FailureRate | Should -Be 5 -Because '403 and 429 count, the 401 SDK challenge does not'
        "$($prod.LatencyAvgMs) $($prod.LatencyMaxMs) $($prod.SaturationAvg) $($prod.SaturationMax)" | Should -Be '25 120 35 80'
        $prod.RequestTypes | Should -Be 'SecretGet 800, KeyGet 200'
        $prod.PSObject.TypeNames | Should -Contain 'AAC.KeyVaultInsight'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 1 -Exactly -ParameterFilter { @($Uri | Where-Object { $_ -match 'SaturationShoebox' }).Count -eq 2 }
    }

    It 'reads posture and where the audit logs go' {
        $v = @(Get-AACKeyVaultInsight -NoDisplay)
        $prod = $v | Where-Object Vault -EQ 'kv-prod'
        "$($prod.Network) $($prod.PrivateEndpoints) $($prod.PermissionModel) $($prod.Defender) $($prod.AuditLogsTo) $($prod.AuditTable)" | Should -Be 'Private 1 RBAC On law-prod AZKVAuditLogs'
        $dev = $v | Where-Object Vault -EQ 'kv-dev'
        "$($dev.Network) $($dev.PermissionModel) $($dev.PurgeProtection) $($dev.Defender) [$($dev.AuditLogsTo)] $($dev.Transactions)" | Should -Be 'Public Access policies False Off [] 0'
    }

    It 'finds what to fix: throttling, saturation, 403s, purge protection, open networks, no audit logs, idle vaults' {
        $f = @(Get-AACKeyVaultInsight -View Finding -NoDisplay)
        $one = { param($Vault, $Finding) $f | Where-Object { $_.Vault -eq $Vault -and $_.Finding -eq $Finding } }
        (& $one 'kv-prod' 'Requests throttled (429)').Severity | Should -Be 'High' -Because '30 of 1,000 is 3%'
        (& $one 'kv-prod' 'Vault close to its limits').Severity | Should -Be 'High' -Because 'saturation peaked at 80%'
        (& $one 'kv-prod' 'Requests denied (403)').Severity | Should -Be 'Medium'
        foreach ($finding in 'Purge protection off', 'Open to every network', 'Access policies, not RBAC', 'No audit logs to Log Analytics', 'Defender for Key Vault off', 'No transactions in the period') { & $one 'kv-dev' $finding | Should -Not -BeNullOrEmpty -Because $finding }
        @($f | Where-Object { $_.Vault -eq 'kv-prod' -and $_.Signal -eq 'Posture' }) | Should -BeNullOrEmpty
        $f[0].Severity | Should -Be 'High'
    }

    It 'reads operations and callers from the audit logs with -IncludeOperations, both tables, without the SDK challenge' {
        $null = Get-AACKeyVaultInsight -NoDisplay
        $script:logCalls | Should -Be 0
        $ops = @(Get-AACKeyVaultInsight -IncludeOperations -View Operation -NoDisplay)
        $script:logWorkspace | Should -Be 'cust-1'
        $script:logQuery | Should -Match 'AZKVAuditLogs'
        $script:logQuery | Should -Match 'AzureDiagnostics'
        $script:logQuery | Should -Match "not \(Operation == 'Authentication' and Status == 401\)"
        $ops.Count | Should -Be 2
        ($ops | Where-Object Caller -EQ 'app-2').AuthDenied | Should -Be 25
        $f = @(Get-AACKeyVaultInsight -IncludeOperations -View Finding -NoDisplay)
        ($f | Where-Object Finding -EQ 'A caller is repeatedly denied').Detail | Should -BeLike '*25 denied request(s) from app-2 (10.0.0.9): SecretGet*'
    }

    It 'reads secrets, keys and certificates with -IncludeObjects: expired, expiring, no expiry, and vaults it can''t read' {
        $null = Get-AACKeyVaultInsight -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttpBatch -Times 0 -Exactly
        $o = @(Get-AACKeyVaultInsight -IncludeObjects -View Object -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttpBatch -ParameterFilter { $Resource -eq 'https://vault.azure.net' }
        @($o | ForEach-Object { "$($_.Kind) $($_.Name) $($_.Status)" } | Sort-Object) | Should -Be @('Certificate web-tls Expired', 'Key cmk No expiry', 'Secret db-password Expiring') -Because 'the certificate''s managed secret is left out'
        $v = @(Get-AACKeyVaultInsight -IncludeObjects -NoDisplay)
        ($v | Where-Object Vault -EQ 'kv-dev').ObjectAccess | Should -Be 'Denied'
        ($v | Where-Object Vault -EQ 'kv-prod').Expired | Should -Be 1
        $f = @(Get-AACKeyVaultInsight -IncludeObjects -View Finding -NoDisplay)
        ($f | Where-Object Finding -EQ 'Expired secrets, keys or certificates').Severity | Should -Be 'High'
        ($f | Where-Object Finding -EQ 'Objects not read: denied').Vault | Should -Be 'kv-dev'
    }

    It 'shows the heat map and findings at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACKeyVaultInsight -IncludeObjects -NoPaging }).Text
        foreach ($expected in 'Vaults by signal', 'Saturation', 'kv-prod', 'kv-dev', 'Requests throttled (429)', 'Findings') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes CSV by -View and an HTML report with the heat map and tabs' {
        $csv = Join-Path $TestDrive 'kv.csv'
        $html = Join-Path $TestDrive 'kv.html'
        $null = & $script:capture { Get-AACKeyVaultInsight -IncludeOperations -IncludeObjects -View Object -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 3
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.heatmaps[0].title | Should -Be 'Vaults by signal'
        @($model.heatmaps[0].columns) | Should -Be @('Availability', 'Failures', 'Throttling', 'Saturation', 'Posture', 'Objects')
        @($model.tables.id) | Should -Be @('vaults', 'findings', 'operations', 'objects')
    }

    It 'narrows by -Name, and writes a PDF report' -Skip:(-not $script:canWritePdf) {
        @(Get-AACKeyVaultInsight -Name 'kv-p*' -NoDisplay).Vault | Should -Be @('kv-prod')
        $pdf = Join-Path $TestDrive 'kv.pdf'
        $null = & $script:capture { Get-AACKeyVaultInsight -IncludeObjects -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
