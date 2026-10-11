<#
    Unit tests for Export-AACResource: the Resource Graph query and its filters,
    flattening (properties, tags, management groups, the details per type) on
    made-up resources (Fixtures\ContosoResource.ps1), and the command with
    Resource Graph faked - the parallel queries, the filters it applies itself,
    the CSV's columns, the view and the reports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoResource.ps1')
    $script:f = Get-AACContosoResource
    $script:build = { param([switch] $Flatten) $rows = $script:f.Rows; InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $rows; F = [bool]$Flatten } { param($R, $F) ConvertTo-AACResourceExport -Row $R -Flatten:$F } }
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

Describe 'Azure Admin Console - resource export query' {
    It 'joins resources to their subscription and resource group in resourcecontainers' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACResourceExportQuery }
        $q | Should -Match '^resources \| extend groupKey'
        $q | Should -Match ([regex]::Escape("join kind=leftouter (resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, subscriptionName = name"))
        $q | Should -Match ([regex]::Escape('managementGroupChain = properties.managementGroupAncestorsChain'))
        $q | Should -Match ([regex]::Escape("on groupKey"))
    }

    It 'filters in Resource Graph what it can, and leaves wildcards to the command' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACResourceExportQuery -ResourceType 'Microsoft.Compute/virtualMachines' -ResourceGroupName 'rg-*' -Name 'vm1' -Location 'UK South' -Tag @{ Environment = "it's prod"; Owner = '*' } -MissingTag 'CostCenter' -Filter "tostring(properties.provisioningState) != 'Succeeded'" }
        $q | Should -Match ([regex]::Escape("| where type in~ ('Microsoft.Compute/virtualMachines')"))
        $q | Should -Not -Match 'resourceGroup in~' -Because 'a wildcard is filtered afterwards'
        $q | Should -Match ([regex]::Escape("| where name in~ ('vm1')"))
        $q | Should -Match ([regex]::Escape("| where location in~ ('UKSouth')"))
        $q | Should -Match ([regex]::Escape("| where tostring(tags['Environment']) =~ 'it\'s prod'"))
        $q | Should -Match ([regex]::Escape("| where isnotempty(tags['Owner'])"))
        $q | Should -Match ([regex]::Escape("| where isempty(tags['CostCenter'])"))
        $q | Should -Match ([regex]::Escape("| where tostring(properties.provisioningState) != 'Succeeded'"))
    }
}

Describe 'Azure Admin Console - resource export' {
    BeforeAll { $script:r = & $script:build }

    It 'lists the resources by subscription, resource group, type and name' {
        @($script:r.Resources | ForEach-Object Name) | Should -Be @('disk-old', 'ag-oncall', 'pip-old', 'aks-contoso', 'vm-web-01', 'nic-web', 'sqldb-orders', 'stcontosodata', 'kv-contoso')
        $script:r.Resources[0].PSObject.TypeNames | Should -Contain 'AAC.Resource'
    }

    It 'names the subscription and the management group, with its path from the root' {
        $vm = $script:r.Resources | Where-Object Name -EQ 'vm-web-01'
        "$($vm.Subscription) | $($vm.ManagementGroup) | $($vm.ManagementGroupId) | $($vm.ManagementGroupPath)" | Should -Be 'sub-contoso-prod | Landing zones | mg-landingzones | Tenant Root Group > Contoso > Landing zones'
        "$($vm.Zones) | $($vm.Identity) | $($vm.ProvisioningState) | $($vm.Created.ToString('yyyy-MM-dd'))" | Should -Be '1 | SystemAssigned | Succeeded | 2025-03-01'
        $vm.ResourceGroupTags | Should -Be 'Owner=platform'
    }

    It 'puts each type''s key settings in Details' {
        $details = @{}
        foreach ($res in $script:r.Resources) { $details[$res.Name] = $res.Details }
        $details['vm-web-01'] | Should -Be 'Size: Standard_D2s_v5; OS: Linux; OS name: ubuntu; Image: 0001-com-ubuntu-server-jammy; Image SKU: 22_04-lts-gen2; Power: VM running; Data disks: 2'
        $details['nic-web'] | Should -Be 'Private IP: 10.0.1.4; VM: vm-web-01; NSG: nsg-web; Subnet: snet-web; Accelerated networking: True'
        $details['stcontosodata'] | Should -Be 'Access tier: Hot; HTTPS only: True; Minimum TLS: TLS1_2; Blob public access: False; Shared key: True; Default network action: Deny; Data Lake: True'
        $details['sqldb-orders'] | Should -Be 'Status: Online; Max size (GB): 32; Zone redundant: False'
        $details['aks-contoso'] | Should -Be 'Kubernetes: 1.30.3; Node pools: 2; Nodes: 5; Network plugin: azure; Private: True'
        $details['disk-old'] | Should -Be 'Size (GiB): 128; State: Unattached'
        $details['pip-old'] | Should -Be 'IP: 20.0.0.9; Allocation: Static'
        $details['ag-oncall'] | Should -Be '' -Because 'a type with no entry in the details table has no Details, and no error'
        ($script:r.Resources | Where-Object Name -EQ 'sqldb-orders').Parent | Should -Be 'sql-contoso'
        ($script:r.Resources | Where-Object Name -EQ 'sqldb-orders').Sku | Should -Be 'GP_S_Gen5 / GeneralPurpose'
    }

    It 'reads the tags as a dictionary, counts the keys without case, most used first' {
        $st = $script:r.Resources | Where-Object Name -EQ 'stcontosodata'
        $st.Tags['CostCenter'] | Should -Be 'CC-1001'
        $st.TagText | Should -Be 'CostCenter=CC-1001; Environment=prod'
        $script:r.TagKeys | Should -Be @('Environment', 'Owner', 'CostCenter')
        "$($script:r.Stats.Resources) $($script:r.Stats.Types) $($script:r.Stats.Subscriptions) $($script:r.Stats.ResourceGroups) $($script:r.Stats.Untagged)" | Should -Be '9 9 2 5 4'
    }

    It 'flattens every property with -Flatten, lists of objects capped with their count' {
        $st = (& $script:build -Flatten).Resources | Where-Object Name -EQ 'stcontosodata'
        $st.Properties['networkAcls.defaultAction'] | Should -Be 'Deny'
        $st.Properties['networkAcls.ipRules.count'] | Should -Be 2
        $st.Properties['networkAcls.ipRules[1].value'] | Should -Be '198.51.100.7'
        $flat = InModuleScope 'Azure.Admin.Console' { ConvertTo-AACFlatObject -MaxItems 1 -InputObject @{ list = @('a', 'b'); objects = @(@{ x = 1 }, @{ x = 2 }); empty = ''; none = $null } }
        "$($flat['list']) | $($flat['objects.count']) | $($flat['objects[0].x']) | $($flat.Contains('objects[1].x')) | $($flat.Contains('empty'))" | Should -Be 'a; b | 2 | 1 | False | False'
    }
}

Describe 'Azure Admin Console - Export-AACResource' {
    BeforeEach {
        $script:batches = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Prod; name = 'sub-contoso-prod'; state = 'Enabled' }, @{ subscriptionId = $script:f.Dev; name = 'sub-contoso-dev'; state = 'Enabled' }) }; Errors = @{} } }
            $script:batches.Add($Query)
            $rows = @{}
            foreach ($key in $Query.Keys) { $subs = @($Query[$key].SubscriptionId); $rows[$key] = @($script:f.Rows | Where-Object { $subs -contains $_.subscriptionId }) }
            @{ Rows = $rows; Errors = @{} }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the subscriptions in parallel queries, one share each' {
        @(Export-AACResource -NoDisplay).Count | Should -Be 9
        @($script:batches[0].Keys) | Should -Be @('resources1', 'resources2')
        @($script:batches[0]['resources1'].SubscriptionId) | Should -Be @($script:f.Prod)
        @(Export-AACResource -SubscriptionId $script:f.Dev -NoDisplay).Name | Should -Be @('disk-old', 'ag-oncall', 'pip-old')
        @($script:batches[-1].Keys) | Should -Be @('resources')
    }

    It 'filters wildcards, searches text and stops at -First' {
        @(Export-AACResource -ResourceGroupName 'rg-d*' -NoDisplay).Name | Should -Be @('disk-old', 'ag-oncall', 'pip-old', 'sqldb-orders', 'stcontosodata')
        @(Export-AACResource -ResourceType 'microsoft.network/*' -NoDisplay).Name | Should -Be @('pip-old', 'nic-web')
        @(Export-AACResource -Name '*-old' -NoDisplay).Name | Should -Be @('disk-old', 'pip-old')
        @(Export-AACResource -Search 'jammy' -NoDisplay).Name | Should -Be @('vm-web-01') -Because 'the details are searched too'
        @(Export-AACResource -Search 'CC-1001' -NoDisplay).Name | Should -Be @('stcontosodata') -Because 'and the tags'
        @(Export-AACResource -First 3 -NoDisplay).Count | Should -Be 3
    }

    It 'writes a CSV with the tags as columns (without case), and every property with -Flatten' {
        $csv = Join-Path $TestDrive 'resources.csv'
        $null = & $script:capture { Export-AACResource -CsvPath $csv }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 9
        $columns = @($rows[0].PSObject.Properties.Name)
        $columns[0..3] | Should -Be @('Name', 'ResourceType', 'Kind', 'ResourceGroup')
        @($columns | Where-Object { $_ -like 'Tag: *' }) | Should -Be @('Tag: Environment', 'Tag: Owner', 'Tag: CostCenter')
        ($rows | Where-Object Name -EQ 'disk-old').'Tag: Environment' | Should -Be 'dev' -Because "'environment' is the same tag"
        ($rows | Where-Object Name -EQ 'vm-web-01').ManagementGroupPath | Should -Be 'Tenant Root Group > Contoso > Landing zones'
        $flat = Join-Path $TestDrive 'flat.csv'
        $null = & $script:capture { Export-AACResource -ResourceType 'microsoft.storage/storageaccounts' -Flatten -TagColumn Environment -CsvPath $flat }
        $row = @(Import-Csv -LiteralPath $flat)[0]
        $row.'properties.networkAcls.defaultAction' | Should -Be 'Deny'
        @($row.PSObject.Properties.Name | Where-Object { $_ -like 'Tag: *' }) | Should -Be @('Tag: Environment')
    }

    It 'shows the resources at the prompt, in characters any console can show' {
        $text = (& $script:capture { Export-AACResource -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Resources', '9 resource(s) of 9 type(s) in 5 resource group(s) across 2 subscription(s); 4 untagged', 'Top types', 'Resources (9)', 'vm-web-01') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes an HTML report with tag columns to filter on' {
        $html = Join-Path $TestDrive 'resources.html'
        $null = & $script:capture { Export-AACResource -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('resources')
        @($model.tables[0].columns.key) | Should -Contain 'Tag: Environment'
        ($model.tables[0].rows | Where-Object Name -EQ 'kv-contoso').Details | Should -BeLike 'Soft delete: True; Purge protection: True; RBAC: True*'
    }
}
