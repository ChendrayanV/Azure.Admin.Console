<#
    Unit tests for Get-AACSkuAvailability: the availability built from
    made-up Microsoft.Compute SKUs, usage and zone mappings
    (Fixtures\ContosoSku.ps1) - restrictions, zones, quota, AKS's rules and
    a cluster's node pools - and the command with REST and Resource Graph
    faked: what it reads, the console view and the exports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoSku.ps1')
    $script:sku = Get-AACContosoSku
    $script:read = @(@{ SubscriptionId = $script:sku.Corp; SubscriptionName = 'sub-corp-apps'; Location = 'uksouth'; Skus = $script:sku.Skus; Usages = $script:sku.Usages; ZoneMappings = $script:sku.Locations[0].availabilityZoneMappings })
    $script:convert = {
        param([hashtable] $Options = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:read; O = $Options } { param($R, $O) ConvertTo-AACSkuAvailability -Read $R @O }
    }
    $script:status = { param($Result) $map = @{}; foreach ($row in $Result.Skus) { $map[$row.Sku] = $row.Status }; $map }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 180
        $console.Profile.Capabilities.Unicode = $false
        try {
            [Spectre.Console.AnsiConsole]::Console = $console
            $output = @(& $Render)
        }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - VM size availability' {
    It 'reads only VM sizes, with their capabilities, and marks each available when nothing stops it' {
        $a = & $script:convert
        $a.Skus.Count | Should -Be 7 -Because 'the disk SKU is not a VM size'
        $a.Skus[0].PSObject.TypeNames | Should -Contain 'AAC.SkuAvailability'
        $d4 = $a.Skus | Where-Object Sku -EQ 'Standard_D4s_v5'
        "$($d4.Status) $($d4.Series) $($d4.Version) $($d4.vCPUs) $($d4.MemoryGB) $($d4.Zones)" | Should -Be 'Available D v5 4 16 1,2,3'
        $d4.EphemeralOSDisk | Should -BeTrue
        $d4.FamilyVCpuFree | Should -Be 88
        $status = & $script:status $a
        $status['Standard_M8ms'] | Should -Be 'Available' -Because 'no zones were asked for'
        $status['Standard_NC24ads_A100_v4'] | Should -Be 'Restricted'
        ($a.Skus | Where-Object Sku -EQ 'Standard_NC24ads_A100_v4').Reason | Should -BeLike '*NotAvailableForSubscription*'
    }

    It 'judges the zones asked for, less those restricted for the subscription' {
        $a = & $script:convert @{ Zone = @('1', '2', '3') }
        $status = & $script:status $a
        $status['Standard_D4s_v5'] | Should -Be 'Available'
        $status['Standard_D2s_v5'] | Should -Be 'Partial'
        $d2 = $a.Skus | Where-Object Sku -EQ 'Standard_D2s_v5'
        "$($d2.Zones)|$($d2.ZonesMissing)|$($d2.RestrictedZones)" | Should -Be '1,2|3|3'
        $d2.Reason | Should -BeLike '*restricted for this subscription*'
        $status['Standard_D4ps_v5'] | Should -Be 'Partial'
        $status['Standard_M8ms'] | Should -Be 'ZoneUnavailable'
    }

    It 'checks the family and regional vCPU quota for vCPUs x the node count' {
        $a = & $script:convert
        (& $script:status $a)['Standard_E8s_v5'] | Should -Be 'NoQuota' -Because '8 vCPUs are needed and the family has 2 free'
        ($a.Skus | Where-Object Sku -EQ 'Standard_E8s_v5').Reason | Should -Be 'family quota: 2 of 10 vCPUs free, 8 needed'
        $a = & $script:convert @{ NodeCount = 25 }
        (& $script:status $a)['Standard_D4s_v5'] | Should -Be 'NoQuota' -Because '100 vCPUs are needed and the region has 80 free'
        ($a.Quotas | Where-Object { -not $_.Family }).Free | Should -Be 80
        $a.Quotas[0].Quota | Should -Be 'Total Regional vCPUs' -Because 'the region first'
    }

    It "applies AKS's rules: at least 2 vCPUs, and notes for system node pools" {
        $a = & $script:convert @{ Service = 'Aks' }
        (& $script:status $a)['Standard_B1s'] | Should -Be 'NotSupported'
        ($a.Skus | Where-Object Sku -EQ 'Standard_B1s').Reason | Should -Be 'AKS needs at least 2 vCPUs per node'
        (& $script:status (& $script:convert))['Standard_B1s'] | Should -Be 'Available' -Because 'a VM can have one vCPU'
    }

    It 'filters by series, size (with or without its prefix, wildcards allowed) and architecture' {
        @((& $script:convert @{ Series = @('D') }).Skus.Sku) | Should -Be @('Standard_D2s_v5', 'Standard_D4ps_v5', 'Standard_D4s_v5')
        @((& $script:convert @{ Sku = @('*s_v5') }).Skus).Count | Should -Be 4
        @((& $script:convert @{ Sku = @('D4s_v5') }).Skus.Sku) | Should -Be @('Standard_D4s_v5')
        @((& $script:convert @{ Architecture = 'Arm64' }).Skus.Sku) | Should -Be @('Standard_D4ps_v5')
    }

    It 'maps logical zones to physical ones, and sorts usable sizes first' {
        $a = & $script:convert @{ Zone = @('1', '2', '3') }
        @($a.Zones | Sort-Object LogicalZone | ForEach-Object PhysicalZone) | Should -Be @('uksouth-az2', 'uksouth-az1', 'uksouth-az3')
        @($a.Skus.Status | Select-Object -Unique) | Should -Be @('Available', 'Partial', 'NoQuota', 'ZoneUnavailable', 'Restricted')
        "$($a.Stats.Sizes) $($a.Stats.Available) $($a.Stats.Partial) $($a.Stats.Usable)" | Should -Be '7 2 2 4'
    }
}

Describe 'Azure Admin Console - Get-AACSkuAvailability' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $q = [string]$Query['cluster']
            @{ Rows = @{ cluster = @(if ($q -match "name =~ 'aks-contoso'") { $script:sku.Cluster }) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $result = @{}
            foreach ($target in $Uri) {
                $items = switch -Regex ($target) {
                    '^/subscriptions\?' { $script:sku.Subscriptions }
                    '/locations\?' { $script:sku.Locations }
                    'Microsoft.Compute/skus' { if ($target -match 'uksouth') { $script:sku.Skus } else { @() } }
                    '/usages\?' { $script:sku.Usages }
                }
                $result[$target] = @{ Status = 200; Body = @{}; Items = [System.Collections.Generic.List[object]]@($items); Error = '' }
            }
            $result
        }
    }

    It 'reads sizes, quota and zones over REST for the only subscription, with the region in the filter' {
        $rows = @(Get-AACSkuAvailability -Location 'UK South' -NoDisplay)
        $rows.Count | Should -Be 7
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter {
            $all = $Uri -join ' '
            $all.Contains('/subscriptions/22222222-2222-2222-2222-222222222222/providers/Microsoft.Compute/skus?api-version=2021-07-01&$filter=location%20eq%20%27uksouth%27') -and $all.Contains('/Microsoft.Compute/locations/uksouth/usages') -and $all.Contains('/subscriptions/22222222-2222-2222-2222-222222222222/locations?')
        } -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 0 -Exactly
    }

    It 'stops quietly when the pipeline has what it needs (Select-Object -First)' {
        $Error.Clear()
        $first = @(Get-AACSkuAvailability -Location uksouth -NoDisplay | Select-Object -First 2)
        $after = 'the caller carries on'
        $first.Count | Should -Be 2
        $after | Should -Be 'the caller carries on'
        $Error.Count | Should -Be 0
    }

    It "checks an AKS cluster's region with AKS's rules, and its node pools" {
        $rows = @(Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -NoDisplay)
        ($rows | Where-Object Sku -EQ 'Standard_B1s').Status | Should -Be 'NotSupported'
        ($rows | Where-Object Sku -EQ 'Standard_D4s_v5').InUse | Should -Be 'system'
        $text = (& $script:capture { Get-AACSkuAvailability -ClusterName 'aks-contoso' -NoPaging }).Text
        foreach ($expected in "The cluster's node pools", 'system', 'memory', 'No quota', 'uksouth-az2') { $text | Should -BeLike "*$expected*" }
    }

    It 'says what is wrong: no region, an unknown cluster, a region with no sizes' {
        { Get-AACSkuAvailability -NoDisplay -ErrorAction Stop } | Should -Throw '*-Location*'
        { Get-AACSkuAvailability -ClusterName 'aks-nope' -NoDisplay -ErrorAction Stop } | Should -Throw "*No AKS cluster named 'aks-nope'*"
        $text = (& $script:capture { Get-AACSkuAvailability -Location 'ukwest' -NoPaging }).Text
        $text | Should -BeLike "*No VM sizes were returned for 'ukwest'*"
    }

    It 'draws the view in characters any console can show' {
        $text = (& $script:capture { Get-AACSkuAvailability -Location uksouth -Zone 1, 2, 3 -NoPaging }).Text
        foreach ($expected in 'sizes checked', 'Availability zones', 'vCPU quota', 'Total Regional vCPUs', 'VM sizes', 'Standard_D2s_v5', 'Some zones', 'Restricted') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'writes every size to CSV, and an HTML report with sizes, quota, zones and node pools' {
        $csv = Join-Path $TestDrive 'skus.csv'
        $html = Join-Path $TestDrive 'skus.html'
        $null = & $script:capture { Get-AACSkuAvailability -ClusterName 'aks-contoso' -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 7
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('sizes', 'quota', 'zones', 'pools')
        ($model.charts | Where-Object title -EQ 'VM sizes by status').kind | Should -Be 'donut'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'skus.pdf'
        $null = & $script:capture { Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
