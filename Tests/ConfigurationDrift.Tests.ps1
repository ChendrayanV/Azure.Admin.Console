<#
    Unit tests for Get-AACConfigurationDrift: snapshots (what's compared and
    what isn't), drift against a baseline (changed, added, removed; created
    and deleted resources), desired-state rules (built-in and from a file),
    Terraform's resource_drift, who changed what and the strategy - and the
    command: save, compare, the history trend, with Resource Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $sub = '11111111-1111-1111-1111-111111111111'
    $script:id = { param([string] $Type, [string] $Name) "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app/providers/$Type/$Name" }
    $storage = { param([string] $Tls, [bool] $Public, [string] $Sku = 'Standard_ZRS') @{ id = (& $script:id 'Microsoft.Storage/storageAccounts' 'stapp'); name = 'stapp'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope'; sku = @{ name = $Sku }; kind = 'StorageV2'; tags = @{ env = 'prod' }; identity = $null; properties = @{ minimumTlsVersion = $Tls; supportsHttpsTrafficOnly = $true; allowBlobPublicAccess = $Public; allowSharedKeyAccess = $false; provisioningState = 'Succeeded'; creationTime = '2025-01-01T00:00:00Z'; networkAcls = @{ defaultAction = 'Deny'; ipRules = @(@{ value = '203.0.113.0/24' }) } } } }
    $vault = { param([bool] $Purge) @{ id = (& $script:id 'Microsoft.KeyVault/vaults' 'kv-app'); name = 'kv-app'; type = 'Microsoft.KeyVault/vaults'; location = 'westeurope'; sku = @{ name = 'standard' }; kind = ''; tags = $null; identity = $null; properties = @{ enableSoftDelete = $true; enablePurgeProtection = $Purge; enableRbacAuthorization = $true } } }
    $web = { param([string] $Plan) @{ id = (& $script:id 'Microsoft.Web/sites' 'app-web'); name = 'app-web'; type = 'Microsoft.Web/sites'; location = 'westeurope'; sku = $null; kind = 'app'; tags = @{ env = 'prod' }; identity = @{ type = 'SystemAssigned'; principalId = 'p1' }; properties = @{ httpsOnly = $true; serverFarmId = $Plan; state = 'Running'; lastModifiedTimeUtc = '2026-10-01T00:00:00Z' } } }
    $old = @{ id = (& $script:id 'Microsoft.Web/sites' 'app-old'); name = 'app-old'; type = 'Microsoft.Web/sites'; location = 'westeurope'; sku = $null; kind = 'app'; tags = $null; identity = $null; properties = @{ httpsOnly = $true } }
    $new = @{ id = (& $script:id 'Microsoft.Cache/Redis' 'redis-new'); name = 'redis-new'; type = 'Microsoft.Cache/Redis'; location = 'westeurope'; sku = @{ name = 'Basic' }; kind = ''; tags = $null; identity = $null; properties = @{ enableNonSslPort = $true; minimumTlsVersion = '1.2' } }
    $script:before = @((& $storage 'TLS1_2' $false), (& $vault $true), (& $web 'plan-a'), $old)
    $script:after = @((& $storage 'TLS1_0' $false 'Standard_LRS'), (& $vault $false), (& $web 'plan-b'), $new)
    $stId = (& $script:id 'Microsoft.Storage/storageAccounts' 'stapp').ToLowerInvariant()
    $kvId = (& $script:id 'Microsoft.KeyVault/vaults' 'kv-app').ToLowerInvariant()
    $webId = (& $script:id 'Microsoft.Web/sites' 'app-web').ToLowerInvariant()
    $script:changes = @(
        @{ id = 'c1'; at = '2026-10-08T09:00:00Z'; resourceId = $stId; changedBy = 'ada@contoso.example'; clientType = 'Azure Portal'; changes = @{ 'properties.minimumTlsVersion' = @{ beforeValue = 'TLS1_2'; afterValue = 'TLS1_0'; changeCategory = 'User' } } }
        @{ id = 'c2'; at = '2026-10-07T09:00:00Z'; resourceId = $stId; changedBy = 'Microsoft.Storage'; clientType = ''; changes = @{ 'sku.name' = @{ beforeValue = 'Standard_ZRS'; afterValue = 'Standard_LRS'; changeCategory = 'System' } } }
        @{ id = 'c3'; at = '2026-10-06T09:00:00Z'; resourceId = $webId; changedBy = 'aaaaaaaa-0000-0000-0000-00000000c1c1'; clientType = 'Azure CLI'; changes = @{ 'properties.serverFarmId' = @{ beforeValue = 'plan-a'; afterValue = 'plan-b'; changeCategory = 'User' } } }
    )
    $script:snap = { param([object[]] $Rows) InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $Rows } { param($R) ConvertTo-AACConfigurationSnapshot -Resource $R } }
    $script:drift = { param([hashtable] $Arguments) InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $Arguments } { param($A) ConvertTo-AACConfigurationDrift @A } }
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
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - configuration drift' {
    It 'snapshots the settings that are configuration, not what changes by itself' {
        $s = (& $script:snap $script:before)[(& $script:id 'Microsoft.Storage/storageAccounts' 'stapp').ToLowerInvariant()]
        @($s.Settings.Keys | Sort-Object) | Should -Be @('kind', 'location', 'properties.allowBlobPublicAccess', 'properties.allowSharedKeyAccess', 'properties.minimumTlsVersion', 'properties.networkAcls.defaultAction', 'properties.networkAcls.ipRules', 'properties.supportsHttpsTrafficOnly', 'sku.name', 'tags.env')
        $s.Settings['properties.allowBlobPublicAccess'] | Should -Be 'false'
        $s.Settings['properties.networkAcls.ipRules'] | Should -Be '[{"value":"203.0.113.0/24"}]'
        @((& $script:snap $script:before)[(& $script:id 'Microsoft.Web/sites' 'app-web').ToLowerInvariant()].Settings.Keys) | Should -Not -Contain 'properties.lastModifiedTimeUtc'
    }

    It 'compares with a baseline - each setting changed, added or removed, resources created and deleted - and says who changed it and what to do' {
        $r = & $script:drift @{ Current = (& $script:snap $script:after); Baseline = (& $script:snap $script:before); Change = $script:changes }
        @($r.Drift | ForEach-Object { "$($_.Severity) | $($_.Resource) | $($_.Category) | $($_.Property) | $($_.Detail) | $($_.Origin) | $($_.Strategy)" }) | Should -Be @(
            'High | kv-app | Changed | properties.enablePurgeProtection | true -> false | Unknown | Review'
            'High | stapp | Changed | properties.minimumTlsVersion | TLS1_2 -> TLS1_0 | Manual | Revert'
            'Medium | app-old | Deleted resource |  |  | Unknown | Review'
            'Medium | app-web | Changed | properties.serverFarmId | plan-a -> plan-b | Automation | Update the baseline'
            'Medium | stapp | Changed | sku.name | Standard_ZRS -> Standard_LRS | Azure | Update the baseline'
            'Low | redis-new | New resource |  |  | Unknown | Review'
        )
        ($r.Drift | Where-Object Property -EQ 'properties.minimumTlsVersion').ChangedBy | Should -Be 'ada@contoso.example'
        $r.Drift[0].PSObject.TypeNames | Should -Contain 'AAC.ConfigurationDrift'
        "$($r.Stats.Checked) $($r.Stats.Resources) $($r.Stats.Items)" | Should -Be '5 5 6' -Because 'the resource deleted since the baseline was checked too'
    }

    It 'checks the built-in security baseline and rules from a file' {
        $rules = @(InModuleScope 'Azure.Admin.Console' { Get-AACDriftRule -Default })
        $r = & $script:drift @{ Current = (& $script:snap $script:after); Rule = $rules; Change = $script:changes }
        @($r.Drift | ForEach-Object { "$($_.Severity) $($_.Resource) $($_.Property) | $($_.Expected) | $($_.Actual) | $($_.Strategy)" }) | Should -Be @(
            'High redis-new properties.enableNonSslPort | false | true | Fix'
            'High stapp properties.minimumTlsVersion | one of TLS1_2, TLS1_3 | TLS1_0 | Fix'
            'Medium kv-app properties.enablePurgeProtection | true | false | Fix'
        )
        $file = Join-Path $TestDrive 'desired.psd1'
        Set-Content -LiteralPath $file -Value "@{ Rules = @( @{ ResourceType = 'microsoft.web/sites'; Property = 'tags.env'; Operator = 'Exists'; Severity = 'Low'; Remediation = 'Tag it with env.' }, @{ ResourceType = 'microsoft.storage/*'; Property = 'sku.name'; Operator = 'Match'; Expected = 'ZRS|GZRS'; Severity = 'Medium' } ) }"
        $own = @(InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $file } { param($F) Get-AACDriftRule -Path $F })
        $r = & $script:drift @{ Current = (& $script:snap $script:after); Rule = $own }
        @($r.Drift | ForEach-Object { "$($_.Resource) $($_.Property) $($_.Actual)" }) | Should -Be @('stapp sku.name Standard_LRS')
        Set-Content -LiteralPath $file -Value "@{ Rules = @( @{ ResourceType = 'x'; Property = 'y'; Operator = 'Bigger' } ) }"
        { InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $file } { param($F) Get-AACDriftRule -Path $F } } | Should -Throw "*unknown Operator 'Bigger'*"
    }

    It 'reads what changed outside Terraform' {
        $drifted = @(@{ address = 'azurerm_storage_account.app'; type = 'azurerm_storage_account'; change = @{ actions = @('update'); before = @{ id = (& $script:id 'Microsoft.Storage/storageAccounts' 'stapp'); min_tls_version = 'TLS1_2'; tags = @{ env = 'prod' } }; after = @{ id = (& $script:id 'Microsoft.Storage/storageAccounts' 'stapp'); min_tls_version = 'TLS1_0'; tags = @{ env = 'prod' } } } })
        $r = & $script:drift @{ TerraformDrift = $drifted; Change = $script:changes }
        @($r.Drift | ForEach-Object { "$($_.Severity) | $($_.Resource) | $($_.Property) | $($_.Detail) | $($_.Strategy)" }) | Should -Be @('High | azurerm_storage_account.app | min_tls_version | TLS1_2 -> TLS1_0 | Re-deploy') -Because 'changed by hand outside Terraform: apply the code again'
    }
}

Describe 'Azure Admin Console - Get-AACConfigurationDrift' {
    BeforeEach {
        $script:resourceRows = $script:before
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            $script:queries = $Query
            @{ Rows = @{ resources = $script:resourceRows; changes = $script:changes }; Errors = @{} }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'saves a baseline, compares with it later - the same file - and tracks the trend' {
        $baseline = Join-Path $TestDrive 'base/app.json'
        $history = Join-Path $TestDrive 'base/history.csv'
        $saved = @(Get-AACConfigurationDrift -ResourceGroupName 'rg-app' -SaveBaseline $baseline -HistoryPath $history -NoDisplay)
        $saved.Count | Should -Be 0
        (Get-Content -LiteralPath $baseline -Raw | ConvertFrom-Json -AsHashtable).Resources.Count | Should -Be 4
        $script:queries.resources | Should -BeLike "*where resourceGroup in~ ('rg-app')*"
        $script:resourceRows = $script:after
        $drift = @(Get-AACConfigurationDrift -ResourceGroupName 'rg-app' -BaselinePath $baseline -SaveBaseline $baseline -HistoryPath $history -NoDisplay)
        $drift.Count | Should -Be 6
        @(Import-Csv -LiteralPath $history).Items | Should -Be @('0', '6')
        $again = @(Get-AACConfigurationDrift -BaselinePath $baseline -HistoryPath $history -NoDisplay)
        $again.Count | Should -Be 0 -Because 'the baseline was replaced after the comparison'
    }

    It 'needs a desired state, and says what''s wrong with the files given' {
        { Get-AACConfigurationDrift -NoDisplay } | Should -Throw '*Nothing to compare with*'
        { Get-AACConfigurationDrift -BaselinePath (Join-Path $TestDrive 'nope.json') -NoDisplay } | Should -Throw '*Save one first with -SaveBaseline*'
        $notPlan = Join-Path $TestDrive 'notplan.json'; Set-Content -LiteralPath $notPlan -Value '{ "hello": 1 }'
        { Get-AACConfigurationDrift -TerraformPlanPath $notPlan -NoDisplay } | Should -Throw '*isn''t a Terraform plan in JSON*'
    }

    It 'shows the drift at the prompt' {
        $script:resourceRows = $script:after
        $text = (& $script:capture { Get-AACConfigurationDrift -UseDefaultRules -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Configuration drift', '3 of 4 resource(s) drifted', 'rule violations', 'Drift (3)', 'properties.minimumTlsVersion', 'Fix') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}
