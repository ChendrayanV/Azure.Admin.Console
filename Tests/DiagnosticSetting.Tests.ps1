<#
    Unit tests for Get-AACDiagnosticSetting over a made-up Contoso estate
    (Fixtures\ContosoDiagnostics.ps1): Resource Graph and Resource Manager
    are faked; which resources have logs, every status, the misconfigurations,
    the flattened settings, the filters, the view and the exports run for real.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
    $script:contoso = & (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoDiagnostics.ps1')
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 220
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:row = { param([object[]] $Rows, [string] $Resource) $Rows | Where-Object Resource -EQ $Resource }
}

Describe 'Azure Admin Console - Get-AACDiagnosticSetting' {
    BeforeEach {
        $script:graphQueries = @{}
        $script:armUris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($name in @($Query.Keys)) {
                $script:graphQueries[$name] = $Query[$name]
                $text = if ($Query[$name] -is [System.Collections.IDictionary]) { [string]$Query[$name]['Query'] } else { [string]$Query[$name] }
                $all = @($script:contoso.Graph[$name])
                if ($name -eq 'resources' -and $text -match 'resourceGroup in~ \(([^)]+)\)') {
                    $groups = @([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
                    $all = @($all | Where-Object { $groups -contains $_['resourceGroup'] })
                }
                if ($name -eq 'resources' -and $SubscriptionId) { $all = @($all | Where-Object { $SubscriptionId -contains $_['subscriptionId'] }) }
                $rows[$name] = $all
            }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $script:armUris.Add($u)
                $target = ($u -split '/providers/Microsoft.Insights/')[0]
                if ($u -match 'diagnosticSettingsCategories') {
                    $type = if ($target -match '^/subscriptions/[^/]+$') { 'microsoft.resources/subscriptions' }
                    elseif ($target -match '/storageAccounts/[^/]+/(\w+)/default$') { "microsoft.storage/storageaccounts/$($Matches[1].ToLowerInvariant())" }
                    else { ($script:contoso.Graph.resources | Where-Object { $_['id'] -eq $target })['type'] }
                    $out[$u] = $script:contoso.Categories[$type]
                }
                else {
                    $out[$u] = $script:contoso.Settings[$target]
                }
            }
            $out
        }
    }

    It 'gives every resource with logs its status' {
        $rows = @(Get-AACDiagnosticSetting -NoDisplay)
        $rows[0].PSObject.TypeNames[0] | Should -Be 'AAC.DiagnosticCoverage'
        $expected = [ordered]@{
            'kv-app' = 'Exported'; 'kv-old' = 'Partial'; 'app-api' = 'No setting'; 'app-empty' = 'Not to workspace'; 'agw-edge' = 'Not to workspace'
            'app-locked' = 'Unknown'; 'stcontoso (blob)' = 'Not to workspace'; 'stcontoso (file)' = 'Exported'; 'stcontoso (queue)' = 'No setting'; 'stcontoso (table)' = 'No setting'
            'law-central' = 'Exported'; 'sub-prod (activity log)' = 'Partial'; 'sub-dev (activity log)' = 'No setting'
        }
        foreach ($name in $expected.Keys) { (& $script:row $rows $name).Status | Should -Be $expected[$name] -Because $name }
        @($rows | ForEach-Object Resource) | Should -Not -Contain 'disk-data' -Because 'disks have no diagnostic settings'
        @($rows | ForEach-Object Resource) | Should -Not -Contain 'stcontoso' -Because 'a storage account has only metrics; its services have the logs'
        (& $script:row $rows 'app-locked').Error | Should -Match 'authorization'
    }

    It 'counts a category reached by name, or through allLogs or audit, and lists what is missing' {
        $rows = @(Get-AACDiagnosticSetting -NoDisplay)
        $old = & $script:row $rows 'kv-old'
        $old.LogCategories | Should -Be 2
        $old.CategoriesToWorkspace | Should -Be 1
        $old.MissingCategories | Should -Be 'AzurePolicyEvaluationDetails'
        (& $script:row $rows 'kv-app').CategoriesToWorkspace | Should -Be 2 -Because 'allLogs covers both'
        (& $script:row $rows 'sub-prod (activity log)').MissingCategories | Should -Be 'ServiceHealth, Alert, Recommendation, Policy, Autoscale, ResourceHealth'
        (& $script:row $rows 'kv-app').Workspaces | Should -Be 'law-central'
        (& $script:row $rows 'stcontoso (blob)').Reason | Should -Be "to-old-law: workspace law-deleted doesn't exist"
        (& $script:row $rows 'app-empty').Reason | Should -Be 'empty: no log category enabled'
        (& $script:row $rows 'agw-edge').Reason | Should -Be 'to-storage: to Storage'
        (& $script:row $rows 'app-api').Reason | Should -Be '3 log categories, no diagnostic setting'
    }

    It 'finds <Finding> (<Severity>) on <Resource>' -ForEach @(
        @{ Finding = 'No diagnostic setting'; Severity = 'High'; Resource = 'app-api' }
        @{ Finding = 'Activity log not exported'; Severity = 'High'; Resource = 'sub-dev (activity log)' }
        @{ Finding = 'No resource logs reach Log Analytics'; Severity = 'High'; Resource = 'agw-edge' }
        @{ Finding = 'Sends to a workspace that doesn''t exist'; Severity = 'High'; Resource = 'stcontoso (blob)' }
        @{ Finding = 'Some log categories don''t reach Log Analytics'; Severity = 'Medium'; Resource = 'kv-old' }
        @{ Finding = 'Diagnostic setting with nothing enabled'; Severity = 'Medium'; Resource = 'app-empty' }
        @{ Finding = 'The same logs sent to a workspace twice'; Severity = 'Medium'; Resource = 'stcontoso (file)' }
        @{ Finding = 'Workspace in another region'; Severity = 'Low'; Resource = 'kv-app' }
        @{ Finding = 'Deprecated retention policy on a diagnostic setting'; Severity = 'Low'; Resource = 'agw-edge' }
    ) {
        $row = & $script:row @(Get-AACDiagnosticSetting -NoDisplay) $Resource
        $row.Findings | Should -Match ([regex]::Escape($Finding))
        @('High', 'Medium', 'Low').IndexOf($row.Severity) | Should -BeLessOrEqual @('High', 'Medium', 'Low').IndexOf($Severity) -Because 'the worst finding sets the severity'
    }

    It 'checks the destination against -ExpectedWorkspace' {
        @(Get-AACDiagnosticSetting -ExpectedWorkspace 'law-central' -NoDisplay | Where-Object Findings -Match 'other than the expected').Count | Should -Be 0
        $off = @(Get-AACDiagnosticSetting -ExpectedWorkspace 'law-security' -NoDisplay | Where-Object Findings -Match 'other than the expected')
        @($off | ForEach-Object Resource) | Should -Contain 'kv-app'
        @(Get-AACDiagnosticSetting -ExpectedWorkspace $script:contoso.LawCentral -NoDisplay | Where-Object Findings -Match 'other than the expected').Count | Should -Be 0 -Because 'a resource ID matches too'
    }

    It 'flattens every diagnostic setting with -ExpandSetting' {
        $settings = @(Get-AACDiagnosticSetting -ExpandSetting -NoDisplay)
        $settings[0].PSObject.TypeNames[0] | Should -Be 'AAC.DiagnosticSettingDetail'
        $agw = $settings | Where-Object Resource -EQ 'agw-edge'
        $agw.Destinations | Should -Be 'Storage'
        $agw.StorageAccount | Should -Be 'starchive'
        $agw.RetentionDays | Should -Be '30'
        $agw.LogsEnabled | Should -Be 'ApplicationGatewayAccessLog, ApplicationGatewayFirewallLog'
        $app = $settings | Where-Object { $_.Resource -eq 'kv-app' }
        $app.Workspace | Should -Be 'law-central'
        $app.WorkspaceFound | Should -BeTrue
        $app.DestinationTable | Should -Be 'Resource-specific'
        $app.LogsEnabled | Should -Be 'group:allLogs'
        $app.MetricsEnabled | Should -Be 'AllMetrics'
        ($settings | Where-Object Resource -EQ 'kv-old').DestinationTable | Should -Be 'AzureDiagnostics'
        ($settings | Where-Object Resource -EQ 'kv-old').LogsDisabled | Should -Be 'AzurePolicyEvaluationDetails'
        ($settings | Where-Object Resource -EQ 'stcontoso (blob)').WorkspaceFound | Should -BeFalse
        @($settings | Where-Object Resource -EQ 'stcontoso (file)').Count | Should -Be 2
    }

    It 'returns only what isn''t exported with -NotExportedOnly, and the types without logs with -IncludeUnsupported' {
        @(Get-AACDiagnosticSetting -NotExportedOnly -NoDisplay | ForEach-Object Status | Select-Object -Unique | Sort-Object) | Should -Be @('No setting', 'Not to workspace', 'Partial')
        $all = @(Get-AACDiagnosticSetting -IncludeUnsupported -NoDisplay)
        (& $script:row $all 'disk-data').Status | Should -Be 'No logs'
        (& $script:row $all 'stcontoso').Status | Should -Be 'No logs'
    }

    It 'sends KQL that Resource Graph accepts: no output column named after the keyword kind' {
        $null = Get-AACDiagnosticSetting -NoDisplay
        foreach ($name in @($script:graphQueries.Keys)) {
            $text = if ($script:graphQueries[$name] -is [System.Collections.IDictionary]) { [string]$script:graphQueries[$name]['Query'] } else { [string]$script:graphQueries[$name] }
            $text | Should -Not -Match '[\s,(]kind\s*=' -Because "Resource Graph rejects 'kind = ...' ($name): 'kind' must be bracketed or renamed"
        }
        $script:graphQueries['resources'] | Should -Match 'resourceKind = tolower\(kind\)'
    }

    It 'reads each type''s categories once, and settings only where there are logs' {
        $null = Get-AACDiagnosticSetting -NoDisplay
        $categoryCalls = @($script:armUris | Where-Object { $_ -match 'diagnosticSettingsCategories' })
        $categoryCalls.Count | Should -Be 11 -Because 'one per type and kind (both web apps are kind app), the 4 storage services and subscriptions included'
        @($script:armUris | Where-Object { $_ -match 'disk-data/providers/Microsoft.Insights/diagnosticSettings\?' }).Count | Should -Be 0
        @($script:armUris | Where-Object { $_ -match "/storageAccounts/stcontoso/providers/Microsoft.Insights/diagnosticSettings\?" }).Count | Should -Be 0
        @($script:armUris | Where-Object { $_ -match 'diagnosticSettings\?api-version=2021-05-01-preview$' }).Count | Should -Be 13
    }

    It 'narrows to -ResourceType (wildcards) and -ResourceGroupName, leaving out activity logs for resource groups' {
        @(Get-AACDiagnosticSetting -ResourceType 'microsoft.keyvault/*' -NoDisplay | ForEach-Object Resource | Sort-Object) | Should -Be @('kv-app', 'kv-old')
        @(Get-AACDiagnosticSetting -ResourceType 'microsoft.resources/subscriptions' -NoDisplay | ForEach-Object Resource | Sort-Object) | Should -Be @('sub-dev (activity log)', 'sub-prod (activity log)')
        $group = @(Get-AACDiagnosticSetting -ResourceGroupName 'rg-data' -NoDisplay | ForEach-Object Resource | Sort-Object)
        $group | Should -Be @('stcontoso (blob)', 'stcontoso (file)', 'stcontoso (queue)', 'stcontoso (table)')
    }

    It 'shows coverage by type, the workspaces, the misconfigurations and what isn''t exported' {
        $text = (& $script:capture { Get-AACDiagnosticSetting -NoPaging }).Text
        foreach ($expected in 'Coverage by resource type', 'microsoft.keyvault/vaults', 'Workspaces receiving logs', 'law-central', 'law-deleted', 'not found', 'Misconfigurations', 'Sends to a workspace that doesn''t exist', 'Logs not (all) reaching Log Analytics', 'app-api', "couldn't be read") {
            $text | Should -Match ([regex]::Escape($expected))
        }
    }

    It 'writes the rows to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'diag.csv'
        $html = Join-Path $TestDrive 'diag.html'
        $null = & $script:capture { Get-AACDiagnosticSetting -CsvPath $csv -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 13
        $rows[0].PSObject.Properties.Name | Should -Not -Contain 'Detail'
        $page = Get-Content -LiteralPath $html -Raw
        foreach ($expected in 'Misconfigurations', 'Diagnostic settings', 'Coverage by resource type', 'Workspaces receiving logs', 'starchive') { $page | Should -Match ([regex]::Escape($expected)) }
    }

    It 'writes a PDF, with a bookmark per section and resource type' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'diag.pdf'
        $null = & $script:capture { Get-AACDiagnosticSetting -PdfPath $pdf }
        $pdf | Should -Exist
        $titles = InModuleScope 'Azure.Admin.Console' -Parameters @{ Path = $pdf } {
            param($Path)
            $document = [PdfSharp.Pdf.IO.PdfReader]::Open($Path, [PdfSharp.Pdf.IO.PdfDocumentOpenMode]::Import)
            @($document.Outlines | ForEach-Object { $_.Title; foreach ($child in $_.Outlines) { "  $($child.Title)" } })
        }
        $titles | Should -Contain 'Coverage by resource type'
        $titles | Should -Contain 'Misconfigurations'
        @($titles | Where-Object { $_ -match 'Logs not \(all\) reaching Log Analytics' }).Count | Should -Be 1
        @($titles | Where-Object { $_ -match '^\s+microsoft\.web/sites \(\d+\)' }).Count | Should -Be 1
    }
}
