<#
    Unit tests for the PSRule for Azure data reader (Get-AACRuleData) and
    ConvertTo-AACPSObject. Azure Resource Manager is mocked at
    Invoke-AACArmRequest, so no Azure call is made and PSRule itself isn't
    needed.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - Get-AACRuleData' {
    BeforeAll {
        $script:sub = '11111111-1111-1111-1111-111111111111'
        $script:rgId = "/subscriptions/$script:sub/resourceGroups/rg-data"
        $script:storageId = "$script:rgId/providers/Microsoft.Storage/storageAccounts/stdata01"
        $script:vaultId = "$script:rgId/providers/Microsoft.KeyVault/vaults/kv-data"
        $script:connectionId = "$script:rgId/providers/Microsoft.Network/connections/vpn-hub"
        $script:blobServiceId = "$script:storageId/blobServices/default"
    }

    BeforeEach {
        # Resource Graph: one query for resources, one for resource groups,
        # one for subscriptions - told apart by their text.
        Mock -ModuleName 'Azure.Admin.Console' Invoke-AACArmRequest -ParameterFilter { $Method -eq 'Post' } -MockWith {
            $query = (ConvertFrom-Json -InputObject $Body -AsHashtable).query
            $rows = if ($query -like '*resourcegroups*') {
                @(@{ id = $rgId; name = 'rg-data'; location = 'uksouth'; subscriptionId = $sub; tags = $null; properties = @{ provisioningState = 'Succeeded' } })
            }
            elseif ($query -like "*'microsoft.resources/subscriptions'*") {
                @(@{ subscriptionId = $sub; name = 'sub-contoso-prod'; tenantId = 'tenant'; properties = @{ state = 'Enabled' } })
            }
            else {
                @(
                    @{ id = $storageId; name = 'stdata01'; type = 'microsoft.storage/storageaccounts'; kind = 'StorageV2'; location = 'uksouth'; resourceGroup = 'rg-data'; subscriptionId = $sub; tags = $null; properties = @{ minimumTlsVersion = 'TLS1_2' } }
                    @{ id = $vaultId; name = 'kv-data'; type = 'microsoft.keyvault/vaults'; location = 'uksouth'; resourceGroup = 'rg-data'; subscriptionId = $sub; properties = @{ enableSoftDelete = $true } }
                    @{ id = $connectionId; name = 'vpn-hub'; type = 'microsoft.network/connections'; location = 'uksouth'; resourceGroup = 'rg-data'; subscriptionId = $sub; properties = @{ sharedKey = 'secret-psk' } }
                )
            }
            @{ data = $rows }
        }
        # ARM reads (-Method is left at its Get default, so the filter
        # can't test for 'Get'): blob services and containers; anything
        # else is empty.
        Mock -ModuleName 'Azure.Admin.Console' Invoke-AACArmRequest -ParameterFilter { $Method -ne 'Post' } -MockWith {
            if ($Uri.StartsWith("$blobServiceId/containers?")) {
                return @{ value = @(@{ id = "$blobServiceId/containers/logs"; name = 'logs'; type = 'Microsoft.Storage/storageAccounts/blobServices/containers' }) }
            }
            if ($Uri.StartsWith("$storageId/blobServices?")) {
                return @{ value = @(@{ id = $blobServiceId; name = 'default'; type = 'Microsoft.Storage/storageAccounts/blobServices'; properties = @{ deleteRetentionPolicy = @{ enabled = $true } } }) }
            }
            if ($Uri -like '*DefenderForStorageSettings*') {
                $exception = [System.Exception]::new('Not found')
                $exception.Data['StatusCode'] = 404
                throw $exception
            }
            if ($Uri -like "$vaultId/providers/microsoft.insights/diagnosticSettings?*") {
                $exception = [System.Exception]::new('The client does not have authorization')
                $exception.Data['StatusCode'] = 403
                throw $exception
            }
            @{ value = @() }
        }
    }

    It 'returns resources in the Export-AzRuleData shape' {
        $data = InModuleScope 'Azure.Admin.Console' { Get-AACRuleData }
        $storage = $data.Resources | Where-Object { $_['name'] -eq 'stdata01' }
        $storage['resourceGroupName'] | Should -Be 'rg-data'
        $storage.Contains('resourceGroup') | Should -BeFalse
        $storage.Contains('tags') | Should -BeFalse -Because 'null fields are left out, as Export-AzRuleData does'
        $data.SubscriptionNames[$script:sub] | Should -Be 'sub-contoso-prod'
    }

    It 'adds resource groups and subscriptions as PSRule for Azure types' {
        $data = InModuleScope 'Azure.Admin.Console' { Get-AACRuleData }
        @($data.Resources | Where-Object { $_['type'] -eq 'Microsoft.Resources/resourceGroups' }).Count | Should -Be 1
        $subscription = $data.Resources | Where-Object { $_['type'] -eq 'Microsoft.Subscription' }
        $subscription['id'] | Should -Be "/subscriptions/$script:sub"
        $subscription['displayName'] | Should -Be 'sub-contoso-prod'
    }

    It 'expands a storage account with its blob services and containers' {
        $data = InModuleScope 'Azure.Admin.Console' { Get-AACRuleData }
        $storage = $data.Resources | Where-Object { $_['name'] -eq 'stdata01' }
        $children = @($storage['resources'])
        $children.Count | Should -Be 2
        $children[0]['type'] | Should -Be 'Microsoft.Storage/storageAccounts/blobServices'
        $children[1]['name'] | Should -Be 'logs'
    }

    It 'treats a missing setting (404) as none, and reports one it may not read (403)' {
        $data = InModuleScope 'Azure.Admin.Console' { Get-AACRuleData }
        @($data.Warnings).Count | Should -Be 1
        $data.Warnings[0] | Should -BeLike 'vaults/kv-data: could not read providers/microsoft.insights/diagnosticSettings (HTTP 403)*'
    }

    It 'masks the shared key of a network connection' {
        $data = InModuleScope 'Azure.Admin.Console' { Get-AACRuleData }
        $connection = $data.Resources | Where-Object { $_['name'] -eq 'vpn-hub' }
        $connection['properties']['sharedKey'] | Should -Be '*** MASKED ***'
    }

    It 'limits the resources to -ResourceType, leaving out resource groups and subscriptions' {
        $data = InModuleScope 'Azure.Admin.Console' { Get-AACRuleData -ResourceType 'microsoft.keyvault/*' }
        @($data.Resources).Count | Should -Be 1
        $data.Resources[0]['name'] | Should -Be 'kv-data'
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmRequest -ParameterFilter { $Uri -like '*blobServices*' } -Times 0 -Exactly
    }
}

Describe 'Azure Admin Console - ConvertTo-AACPSObject' {
    It 'turns nested hashtables into objects, keeping arrays as arrays' {
        $object = InModuleScope 'Azure.Admin.Console' {
            ConvertTo-AACPSObject -InputObject (ConvertFrom-Json -InputObject '{"name":"a","resources":[{"type":"x","properties":{"on":true}}],"zones":["1"]}' -AsHashtable)
        }
        $object | Should -BeOfType [pscustomobject]
        $object.resources[0].properties.on | Should -BeTrue
        , $object.zones | Should -BeOfType [object[]]
        $object.zones.Count | Should -Be 1
    }

    It 'keeps the first of keys differing only by case' {
        $object = InModuleScope 'Azure.Admin.Console' {
            ConvertTo-AACPSObject -InputObject (ConvertFrom-Json -InputObject '{"tags":{"Owner":"ops","owner":"dup"}}' -AsHashtable)
        }
        @($object.tags.PSObject.Properties).Count | Should -Be 1
        $object.tags.Owner | Should -Be 'ops'
    }
}

Describe 'Azure Admin Console - PSRule runner' {
    BeforeAll {
        $script:runner = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../PSRule/PSRuleRunner.ps1')).Path
        $script:psrule = Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
    }

    It 'keeps going when a rule fails on one resource, reporting it as that rule''s Error' -Skip:(-not (Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable)) {
        # A virtual network without an address space makes Azure.VNET.LocalDNS
        # throw; the storage account must still be checked.
        $sub = '11111111-1111-1111-1111-111111111111'
        $objects = @(
            @{ id = "/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet1"; name = 'vnet1'; type = 'microsoft.network/virtualnetworks'; location = 'uksouth'; resourceGroupName = 'rg'; subscriptionId = $sub; properties = @{ dhcpOptions = @{ dnsServers = @('10.0.0.4') } } }
            @{ id = "/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st1"; name = 'st1'; type = 'microsoft.storage/storageaccounts'; kind = 'StorageV2'; location = 'uksouth'; resourceGroupName = 'rg'; subscriptionId = $sub; sku = @{ name = 'Standard_LRS' }; properties = @{ minimumTlsVersion = 'TLS1_0' } }
        )
        $in = Join-Path -Path $TestDrive -ChildPath 'input.json'
        $settings = Join-Path -Path $TestDrive -ChildPath 'settings.json'
        $out = Join-Path -Path $TestDrive -ChildPath 'results.json'
        ConvertTo-Json -InputObject $objects -Depth 20 | Set-Content -LiteralPath $in -Encoding utf8
        '{"Rule":[],"ExcludeRule":[],"Baseline":"","Configuration":{}}' | Set-Content -LiteralPath $settings -Encoding utf8

        $output = @(& pwsh -NoProfile -NonInteractive -File $script:runner -ModulePath $script:psrule.Path -InputPath $in -SettingPath $settings -OutputPath $out 2>&1 | ForEach-Object { "$_" })
        $LASTEXITCODE | Should -Be 0 -Because ($output -join ' ')
        $results = @(Get-Content -LiteralPath $out -Raw | ConvertFrom-Json)
        @($results | Where-Object { $_.Name -eq 'st1' -and $_.RuleName -eq 'Azure.Storage.MinTLS' }).Outcome | Should -Be 'Fail'
        @($results | Where-Object { $_.Name -eq 'vnet1' -and $_.Outcome -eq 'Error' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Azure Admin Console - PSRule runner: custom rules and exclusions' {
    BeforeAll {
        $script:runner = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../PSRule/PSRuleRunner.ps1')).Path
        $script:bundled = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../PSRule/Rules')).Path
        $script:psrule = Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
        $script:runWith = {
            param([hashtable] $Settings)
            $sub = '11111111-1111-1111-1111-111111111111'
            $objects = @(
                @{ id = "/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st1"; name = 'st1'; type = 'microsoft.storage/storageaccounts'; kind = 'StorageV2'; location = 'uksouth'; resourceGroupName = 'rg'; subscriptionId = $sub; sku = @{ name = 'Standard_LRS' }; tags = @{ Owner = 'ops'; Environment = 'staging' }; properties = @{ minimumTlsVersion = 'TLS1_0' } }
                @{ id = "/subscriptions/$sub/resourceGroups/rg"; name = 'rg'; type = 'Microsoft.Resources/resourceGroups'; location = 'uksouth'; subscriptionId = $sub; tags = @{ Owner = 'ops' }; properties = @{} }
            )
            $in = Join-Path -Path $TestDrive -ChildPath 'in.json'
            $settingFile = Join-Path -Path $TestDrive -ChildPath 'set.json'
            $out = Join-Path -Path $TestDrive -ChildPath 'out.json'
            ConvertTo-Json -InputObject $objects -Depth 20 | Set-Content -LiteralPath $in -Encoding utf8
            $Settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingFile -Encoding utf8
            $output = @(& pwsh -NoProfile -NonInteractive -File $script:runner -ModulePath $script:psrule.Path -InputPath $in -SettingPath $settingFile -OutputPath $out 2>&1 | ForEach-Object { "$_" })
            [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $output; Results = @(Get-Content -LiteralPath $out -Raw | ConvertFrom-Json) }
        }
    }

    It 'runs the module''s tag rules when configured, including -Type rules, with their help' -Skip:(-not (Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable)) {
        $run = & $script:runWith @{
            Rule = @('AAC.*'); ExcludeRule = @(); Baseline = ''; RulePath = @($script:bundled)
            Configuration = @{ AAC_REQUIRED_TAGS = @('Owner', 'CostCenter'); AAC_ALLOWED_TAG_VALUES = @{ Environment = @('prod', 'dev') } }
        }
        $run.Exit | Should -Be 0 -Because ($run.Output -join ' ')
        @($run.Results.RuleName | Select-Object -Unique) | Should -Not -Contain 'Azure.Storage.MinTLS' -Because '-Rule AAC.* runs only those'
        $required = $run.Results | Where-Object { $_.RuleName -eq 'AAC.Resource.RequiredTags' }
        $required.Outcome | Should -Be 'Fail'
        $required.Reason | Should -BeLike "*'CostCenter'*"
        $required.Link | Should -BeLike '*AAC.Resource.RequiredTags.md'
        ($run.Results | Where-Object { $_.RuleName -eq 'AAC.ResourceGroup.RequiredTags' }).Outcome | Should -Be 'Fail' -Because 'custom rules can use -Type with PSRule for Azure''s binding'
        ($run.Results | Where-Object { $_.RuleName -eq 'AAC.Resource.AllowedTagValues' -and $_.Name -eq 'st1' }).Reason | Should -BeLike "*'staging'*"
    }

    It 'leaves out rules by wildcard' -Skip:(-not (Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable)) {
        $run = & $script:runWith @{ Rule = @(); ExcludeRule = @('Azure.Storage.*', 'AAC.*'); Baseline = ''; RulePath = @($script:bundled); Configuration = @{} }
        $run.Exit | Should -Be 0 -Because ($run.Output -join ' ')
        @($run.Results | Where-Object { $_.RuleName -like 'Azure.Storage.*' -or $_.RuleName -like 'AAC.*' }).Count | Should -Be 0
        @($run.Results).Count | Should -BeGreaterThan 0 -Because 'other rules (e.g. Azure.Resource.UseTags) still run'
    }
}

Describe 'Azure Admin Console - Invoke-AACPSRule' {
    BeforeAll {
        $script:fakeResults = {
            $make = {
                param($Outcome, $Rule, $Resource, $Pillar, $Severity, $Reason)
                [pscustomobject]@{
                    PSTypeName = 'AAC.PSRuleResult'; Outcome = $Outcome; Pillar = $Pillar; RuleName = $Rule; Title = "Title of $Rule"; Severity = $Severity
                    ResourceName = $Resource; ResourceType = 'microsoft.storage/storageaccounts'; ResourceGroup = 'rg-data'; SubscriptionName = 'sub-prod'
                    SubscriptionId = '11111111-1111-1111-1111-111111111111'; Reason = $Reason; Recommendation = 'Fix it.'; Synopsis = ''; Ref = 'AZR-1'
                    Link = "https://azure.github.io/PSRule.Rules.Azure/en/rules/$Rule/"; Source = 'PSRule for Azure'
                    ResourceId = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/$Resource"
                }
            }
            @{
                Results  = @(
                    & $make 'Fail' 'Azure.Storage.MinTLS' 'st1' 'Security' 'Critical' 'Minimum TLS is 1.0.'
                    & $make 'Fail' 'Azure.Storage.MinTLS' 'st2' 'Security' 'Critical' 'Minimum TLS is 1.0.'
                    & $make 'Error' 'Azure.Storage.Firewall' 'st2' 'Security' 'Important' 'The rule could not be evaluated: x'
                    & $make 'Pass' 'Azure.Storage.SoftDelete' 'st1' 'Reliability' 'Important' ''
                )
                Warnings = @(); Rules = 3; Objects = 2; Version = '1.47.0'
            }
        }
    }

    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -MockWith $script:fakeResults
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACPSRuleView -MockWith { }
    }

    It 'shows the view and returns nothing at the prompt; returns every result with -NoDisplay' {
        @(Invoke-AACPSRule -NoPaging).Count | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACPSRuleView -Times 1 -Exactly
        $all = @(Invoke-AACPSRule -NoDisplay)
        $all.Count | Should -Be 4
        $all[0].PSObject.TypeNames | Should -Contain 'AAC.PSRuleResult'
    }

    It 'returns only failures and errors with -FailedOnly' {
        @(Invoke-AACPSRule -NoDisplay -FailedOnly).Outcome | Should -Be @('Fail', 'Fail', 'Error')
    }

    It 'passes the rule settings to the engine' {
        $null = Invoke-AACPSRule -NoDisplay -Rule 'Azure.Storage.*' -ExcludeRule 'AAC.*' -Baseline 'Azure.Pillar.Security' -Configuration @{ AAC_REQUIRED_TAGS = @('Owner') } -SubscriptionId '11111111-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -Times 1 -Exactly -ParameterFilter {
            $Rule -eq 'Azure.Storage.*' -and $ExcludeRule -eq 'AAC.*' -and $Baseline -eq 'Azure.Pillar.Security' -and $Configuration.AAC_REQUIRED_TAGS -eq 'Owner' -and $SubscriptionId -eq '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'refuses a -RulePath that does not exist' {
        { Invoke-AACPSRule -NoDisplay -RulePath (Join-Path $TestDrive 'no-such-rules') } | Should -Throw '*does not exist*'
    }

    It 'writes CSV and an HTML report that opens on the failures, instead of the view' {
        $csv = Join-Path -Path $TestDrive -ChildPath 'psrule.csv'
        $html = Join-Path -Path $TestDrive -ChildPath 'psrule.html'
        @(Invoke-AACPSRule -CsvPath $csv -HtmlPath $html).Count | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACPSRuleView -Times 0 -Exactly
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 4
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.tables[0].filters.Outcome | Should -Be 'Fail'
        $model.tables[0].group | Should -Be 'RuleName'
        $model.tables[0].rows.Count | Should -Be 4
        ($model.tiles | Where-Object label -EQ 'failed').value | Should -Be '2'
    }
}
