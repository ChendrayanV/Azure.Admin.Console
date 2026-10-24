<#
    Unit tests for Export-AACDiagnosticBundle: secrets redacted by name and
    by value, what Resource Graph and Resource Manager returned organized per
    resource, and the command end to end with Azure faked - the zip, its
    files, the summary, -Force, -WhatIf and resource groups.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoBundle.ps1')
    $f = Get-AACContosoBundle
    $script:sub = $f.Sub
    $script:vm = $f.Vm
    $script:st = $f.St
    $script:gone = $f.Gone
    $script:read = $f.Read
    $script:armFor = $f.ArmFor
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
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - redaction' {
    It 'redacts secrets by name and by value, and keeps what only names where a secret lives' {
        $result = InModuleScope 'Azure.Admin.Console' {
            $n = 0
            $clean = ConvertTo-AACRedactedObject -Count ([ref]$n) -InputObject @{
                adminPassword = 'x'; properties = @{ primaryKey = 'k1'; keyVaultUri = 'https://kv.vault.azure.net/'; keySource = 'Microsoft.Keyvault'; publicKey = 'ssh-rsa AAAA'; connectionString = 'Server=x' }
                url = 'https://st1.blob.core.windows.net/c?sv=2022&sig=abcdef'; plain = 'hello'; token = 'eyJhbGciOi.eyJzdWIiOi.c2ln'; items = @('a', 'Endpoint=sb://x/;SharedAccessKeyName=r;SharedAccessKey=abc=')
                count = 3; empty = ''
            }
            @{ Clean = $clean; Count = $n }
        }
        $c = $result.Clean
        "$($c.adminPassword) $($c.properties.primaryKey) $($c.properties.connectionString) $($c.url) $($c.token) $($c.items[1])" | Should -Be '[REDACTED] [REDACTED] [REDACTED] [REDACTED] [REDACTED] [REDACTED]'
        "$($c.properties.keyVaultUri) $($c.properties.keySource) $($c.properties.publicKey) $($c.plain) $($c.items[0]) $($c.count)" | Should -Be 'https://kv.vault.azure.net/ Microsoft.Keyvault ssh-rsa AAAA hello a 3'
        $result.Count | Should -Be 6
    }
}

Describe 'Azure Admin Console - diagnostic bundle sections' {
    It 'puts each resource''s sections together, with a summary and what couldn''t be read' {
        $arm = @{}
        foreach ($id in $script:vm, $script:st, $script:gone) {
            $l = $id.ToLowerInvariant()
            $arm[$l] = @{ Activity = (& $script:armFor "/subscriptions/x/providers/Microsoft.Insights/eventtypes/management/values?`$filter=$([System.Uri]::EscapeDataString("resourceUri eq '$l'"))"); Diagnostics = (& $script:armFor "$l/providers/Microsoft.Insights/diagnosticSettings"); Locks = (& $script:armFor "$l/providers/Microsoft.Authorization/locks"); History = (& $script:armFor "$l/providers/Microsoft.ResourceHealth/availabilityStatuses") }
        }
        $arm[$script:st.ToLowerInvariant()].History = $null
        $r = InModuleScope 'Azure.Admin.Console' -Parameters @{ Ids = @($script:vm, $script:st, $script:gone); R = $script:read; A = $arm } { param($Ids, $R, $A) ConvertTo-AACDiagnosticBundle -ResourceId $Ids -Read $R -Arm $A }
        @($r.Resources | ForEach-Object { $s = $_.Summary; "$($s.Status) | $($s.Resource) | $($s.Health) | $($s.FailedOperations) | $($s.Alerts) | $($s.Locks) | $($s.DiagnosticSettings) | $($s.Issues)" }) | Should -Be @(
            'Failed | vm1 | Unavailable | 1 | 2 | 0 | 1 | health unavailable, 1 failed operation(s), 2 alert(s)'
            'Warning | st1 | Available | 0 | 0 | 1 | 0 | no diagnostic settings'
            'Failed | gone |  | 0 | 0 | 0 | 1 | not found'
        )
        @($r.Resources[0].Sections.Keys) | Should -Be @('config.json', 'health.json', 'activity-log.json', 'diagnostic-settings.json', 'locks.json', 'advisor.json', 'defender.json', 'policy.json', 'alerts.json', 'changes.json', 'role-assignments.json')
        $r.Resources[0].Sections['health.json'].current.state | Should -Be 'Unavailable'
        $r.Warnings | Should -Contain 'Resource Graph: the changes couldn''t be read: Too many requests'
        $r.Warnings | Should -Contain 'gone wasn''t found in Resource Graph (deleted, a typo, or no access): its configuration is missing.'
    }
}

Describe 'Azure Admin Console - Export-AACDiagnosticBundle' {
    BeforeEach {
        $script:batches = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:batches.Add(@{ Keys = @($Query.Keys); SubscriptionId = @($SubscriptionId) })
            if ($Query.Contains('resources')) { return @{ Errors = @{}; Rows = @{ resources = @(@{ id = $script:vm; name = 'vm1' }, @{ id = $script:st; name = 'st1' }) } } }
            $script:read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { $answers = @{}; foreach ($u in $Uri) { $answers[$u] = & $script:armFor $u }; $answers }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'writes a zip with each resource''s files, the summary and the README, secrets redacted' {
        $zip = Join-Path $TestDrive 'case.zip'
        $bundle = Export-AACDiagnosticBundle -ResourceId $script:vm, $script:st -Path $zip -NoDisplay
        $bundle.PSObject.TypeNames | Should -Contain 'AAC.DiagnosticBundle'
        "$($bundle.Resources) $($bundle.Redacted) $($bundle.Files)" | Should -Be '2 2 25' -Because '11 files per resource, summary.json, README.md and summary.html'
        $out = Join-Path $TestDrive 'case'
        Expand-Archive -LiteralPath $zip -DestinationPath $out
        foreach ($file in 'README.md', 'summary.json', 'summary.html', 'resources/vm1/config.json', 'resources/vm1/activity-log.json', 'resources/st1/locks.json') { Join-Path $out $file | Should -Exist }
        $config = Get-Content -LiteralPath (Join-Path $out 'resources/vm1/config.json') -Raw | ConvertFrom-Json
        $config.properties.osProfile.adminPassword | Should -Be '[REDACTED]'
        $config.properties.osProfile.adminUsername | Should -Be 'azureuser'
        (Get-Content -LiteralPath (Join-Path $out 'resources/st1/config.json') -Raw) | Should -Not -Match 'abc123'
        (Get-Content -LiteralPath (Join-Path $out 'README.md') -Raw) | Should -Match ([regex]::Escape('| vm1 | microsoft.compute/virtualmachines | Unavailable | 1 | 2 |'))
        (Get-Content -LiteralPath (Join-Path $out 'summary.json') -Raw | ConvertFrom-Json).warnings | Should -Contain 'Resource Graph: the changes couldn''t be read: Too many requests'
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'aac-bundle-*' -Directory).Count | Should -Be 0 -Because 'the work folder is removed'
    }

    It 'refuses to overwrite without -Force, and writes nothing under -WhatIf' {
        $zip = Join-Path $TestDrive 'exists.zip'
        Set-Content -LiteralPath $zip -Value 'x'
        { Export-AACDiagnosticBundle -ResourceId $script:vm -Path $zip -NoDisplay } | Should -Throw '*already exists*-Force*'
        $null = Export-AACDiagnosticBundle -ResourceId $script:vm -Path $zip -Force -NoDisplay
        (Get-Item -LiteralPath $zip).Length | Should -BeGreaterThan 100
        $whatIf = Join-Path $TestDrive 'whatif.zip'
        Export-AACDiagnosticBundle -ResourceId $script:vm -Path $whatIf -WhatIf
        $whatIf | Should -Not -Exist
    }

    It 'bundles a resource group''s resources, and takes resources from the pipeline' {
        $zip = Join-Path $TestDrive 'rg.zip'
        (Export-AACDiagnosticBundle -ResourceGroupName 'rg-app' -SubscriptionId $script:sub -Path $zip -NoDisplay).Resources | Should -Be 2
        $script:batches[0].Keys | Should -Be @('resources')
        $script:batches[0].SubscriptionId | Should -Be @($script:sub)
        $piped = Join-Path $TestDrive 'piped.zip'
        ([pscustomobject]@{ Id = $script:vm } | Export-AACDiagnosticBundle -Path $piped -NoDisplay).Resources | Should -Be 1
    }

    It 'shows the summary at the prompt, in characters any console can show' {
        $zip = Join-Path $TestDrive 'shown.zip'
        $text = (& $script:capture { Export-AACDiagnosticBundle -ResourceId $script:vm -Path $zip -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Diagnostic bundle', 'Bundled 1 resource(s) into', 'Resources in the bundle (1)', 'vm1') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }
}
