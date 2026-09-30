<#
    Unit tests for Get-AACInventory: the tenant tree built from a made-up
    Contoso tenant (Fixtures\ContosoTenant.ps1) - nesting, rolled-up counts,
    pruned management groups, empty resource groups - and the command with
    Azure Resource Graph mocked: its scope, the console tree and the exports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/GraphBatchShim.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoTenant.ps1')
    $script:tenant = Get-AACContosoTenant
    $script:build = {
        param([hashtable] $With = @{})
        $t = $script:tenant
        $parameters = @{ TenantId = $t.TenantId; TenantName = 'Contoso'; ManagementGroup = $t.ManagementGroups; Subscription = $t.Subscriptions; ResourceGroup = $t.ResourceGroups; Resource = $t.Resources }
        foreach ($key in $With.Keys) { $parameters[$key] = $With[$key] }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $parameters } { param($P) ConvertTo-AACInventory @P }
    }
    $script:item = { param($Inventory, [string] $Name) $Inventory.Items | Where-Object Name -EQ $Name | Select-Object -First 1 }
    $script:capture = {
        param([scriptblock] $Render, [switch] $Ascii)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 160
        $console.Profile.Capabilities.Unicode = -not $Ascii
        try {
            [Spectre.Console.AnsiConsole]::Console = $console
            $output = @(& $Render)
        }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - inventory tree' {
    BeforeAll { $script:inventory = & $script:build }

    It 'nests tenant > management groups > subscriptions > resource groups > resources' {
        $corp = & $script:item $script:inventory 'sub-corp-apps'
        $corp.Path | Should -Be 'Contoso / Tenant Root Group / Landing Zones / Corp / sub-corp-apps'
        $corp.ManagementGroup | Should -Be 'Corp'
        (& $script:item $script:inventory 'rg-app').Path | Should -Be 'Contoso / Tenant Root Group / Landing Zones / Corp / sub-corp-apps / rg-app'
        (& $script:item $script:inventory 'vm-web-01').Level | Should -Be 'Resource'
        (& $script:item $script:inventory 'vm-web-01').ResourceGroup | Should -Be 'rg-app'
        @($script:inventory.Items.Level | Select-Object -First 3) | Should -Be @('Tenant', 'ManagementGroup', 'ManagementGroup') -Because 'items come in tree order'
    }

    It 'rolls the counts up every level' {
        $root = $script:inventory.Items[0]
        $root.Level | Should -Be 'Tenant'
        $root.Subscriptions | Should -Be 3
        $root.ResourceGroups | Should -Be 5
        $root.Resources | Should -Be 17
        $root.ManagementGroups | Should -Be 5
        $landingZones = & $script:item $script:inventory 'Landing Zones'
        $landingZones.Subscriptions | Should -Be 1
        $landingZones.ResourceGroups | Should -Be 3
        $landingZones.Resources | Should -Be 10
        (& $script:item $script:inventory 'rg-app').TopTypes | Should -Be 'disks 2, virtualmachines 2, networkinterfaces 2' -Because 'by count, then by full type (microsoft.compute before microsoft.network)'
        $script:inventory.Stats.Types | Should -Be 13
        $script:inventory.Stats.Locations | Should -Be 3
    }

    It 'leaves out management groups with no subscriptions, unless asked for' {
        & $script:item $script:inventory 'Sandbox' | Should -BeNullOrEmpty
        $kept = & $script:build @{ KeepManagementGroup = @('mg-sandbox') }
        (& $script:item $kept 'Sandbox').Path | Should -Be 'Contoso / Tenant Root Group / Sandbox'
    }

    It 'puts a subscription whose management group it can''t read under the tenant' {
        (& $script:item $script:inventory 'sub-legacy').Path | Should -Be 'Contoso / sub-legacy'
        (& $script:item $script:inventory 'sub-legacy').State | Should -Be 'Warned'
        $noGroups = & $script:build @{ ManagementGroup = @() }
        @($noGroups.Items | Where-Object Level -EQ 'Subscription' | ForEach-Object { $_.Path }) | Sort-Object | Should -Be @('Contoso / sub-connectivity', 'Contoso / sub-corp-apps', 'Contoso / sub-legacy')
    }

    It 'flags empty resource groups, and adds a group seen only through its resources' {
        (& $script:item $script:inventory 'rg-empty').Resources | Should -Be 0
        $script:inventory.Stats.EmptyGroups | Should -Be 1
        $orphaned = & $script:build @{ ResourceGroup = @($script:tenant.ResourceGroups | Where-Object name -NE 'rg-data') }
        (& $script:item $orphaned 'rg-data').Resources | Should -Be 3
    }
}

Describe 'Azure Admin Console - inventory security posture' {
    BeforeAll { $script:secured = & $script:build @{ Security = $script:tenant.Security } }

    It 'uses Defender''s secure score for subscriptions, and adds them up for management groups and the tenant' {
        (& $script:item $script:secured 'sub-corp-apps').SecureScore | Should -Be 36
        (& $script:item $script:secured 'sub-corp-apps').ScorePoints | Should -Be '18.0 / 50.0'
        (& $script:item $script:secured 'sub-connectivity').SecureScore | Should -Be 76
        (& $script:item $script:secured 'Corp').SecureScore | Should -Be 36
        $script:secured.Items[0].SecureScore | Should -Be 56 -Because '(38 + 18) / (50 + 50)'
        $script:secured.Stats.Rating | Should -Be 'Fair'
        (& $script:item $script:secured 'sub-legacy').SecureScore | Should -BeNullOrEmpty -Because 'no Defender data'
    }

    It 'scores a resource by its healthy share, and rolls findings up by severity' {
        $vm = & $script:item $script:secured 'vm-web-01'
        $vm.SecureScore | Should -Be 60 -Because '6 healthy of 10 assessed'
        $vm.Rating | Should -Be 'Fair'
        $vm.Severity | Should -Be 'High'
        "$($vm.High)/$($vm.Medium)/$($vm.Low)" | Should -Be '2/1/1'
        $vm.TopFindings | Should -BeLike 'Machines should have vulnerability findings resolved;*' -Because 'most severe first'
        (& $script:item $script:secured 'kv-app').Severity | Should -Be 'Healthy'
        (& $script:item $script:secured 'kv-app').Rating | Should -Be 'Good'
        $group = & $script:item $script:secured 'rg-app'
        "$($group.High)/$($group.Medium)/$($group.Low)" | Should -Be '2/3/1'
        $group.SecureScore | Should -Be 75 -Because '18 healthy of 24 assessed'
        (& $script:item $script:secured 'rg-empty').SecureScore | Should -BeNullOrEmpty
        $script:secured.Stats.High | Should -Be 2
    }

    It 'rates scores: Good 70+, Fair 40-69, Poor under 40' {
        (& $script:item $script:secured 'sub-connectivity').Rating | Should -Be 'Good'
        (& $script:item $script:secured 'rg-hub').Rating | Should -Be 'Fair'
        (& $script:item $script:secured 'sub-corp-apps').Rating | Should -Be 'Poor'
    }

    It 'lists the controls with their potential increase, and the recommendations most severe first' {
        $ports = $script:secured.Controls | Where-Object { $_.Control -eq 'Secure management ports' -and $_.SubscriptionName -eq 'sub-corp-apps' }
        $ports.PotentialIncrease | Should -Be 16 -Because '(8 - 0) of the subscription''s 50 points'
        $ports.Score | Should -Be 0
        @($script:secured.Recommendations.Severity | Select-Object -Unique) | Should -Be @('High', 'Medium', 'Low')
        $script:secured.Recommendations[0].Resource | Should -Be 'vm-web-01'
        $script:secured.Recommendations[0].ResourceGroup | Should -Be 'rg-app'
    }

    It 'has no security posture without Defender data' {
        $none = & $script:build
        $none.Stats.HasSecurity | Should -BeFalse
        $none.Items[0].SecureScore | Should -BeNullOrEmpty
        @($none.Controls).Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - inventory cost' {
    BeforeAll {
        $script:cost = Get-AACContosoCost
        $script:costed = & $script:build @{ Cost = $script:cost }
    }

    It 'gives each resource its cost this month and last' {
        $vm = & $script:item $script:costed 'vm-web-01'
        $vm.CostMonthToDate | Should -Be 100
        $vm.CostLastMonth | Should -Be 150
        $vm.Currency | Should -Be 'USD'
        (& $script:item $script:costed 'kv-app').CostMonthToDate | Should -Be 0 -Because 'a resource with no cost row costs nothing'
    }

    It 'bills a child resource''s cost to the closest resource above it' {
        (& $script:item $script:costed 'sql-orders').CostMonthToDate | Should -Be 30 -Because 'the database is not in the inventory; its server is'
    }

    It 'puts deleted resources and charges not tied to a resource under their subscription' {
        $deleted = @($script:costed.Items | Where-Object Level -EQ 'DeletedResources')
        $deleted.Count | Should -Be 1
        $deleted[0].SubscriptionName | Should -Be 'sub-corp-apps'
        $deleted[0].CostMonthToDate | Should -Be 32 -Because 'the deleted VM (20), a deleted storage account (7) and a charge with no resource (5)'
        $deleted[0].Path | Should -BeLike '*sub-corp-apps / Deleted resources'
        $deleted[0].Depth | Should -Be ((& $script:item $script:costed 'rg-app').Depth) -Because 'it sits beside the resource groups'
        @($script:costed.Items | Where-Object Level -EQ 'ResourceGroup').Count | Should -Be 5 -Because 'it is not a resource group'
    }

    It 'rolls the costs up, and never adds different currencies' {
        (& $script:item $script:costed 'rg-app').CostMonthToDate | Should -Be 150
        $corp = & $script:item $script:costed 'sub-corp-apps'
        $corp.CostMonthToDate | Should -Be 212
        $corp.CostLastMonth | Should -Be 150
        (& $script:item $script:costed 'Tenant Root Group').CostMonthToDate | Should -Be 1012
        (& $script:item $script:costed 'Tenant Root Group').Currency | Should -Be 'USD'
        (& $script:item $script:costed 'sub-legacy').Currency | Should -Be 'EUR'
        $tenant = $script:costed.Items[0]
        $tenant.Currency | Should -Be 'mixed'
        $tenant.CostMonthToDate | Should -BeNullOrEmpty -Because 'USD and EUR are not added up'
        @($script:costed.Stats.Cost | ForEach-Object { "$($_.Currency) $($_.MonthToDate) $($_.LastMonth)" }) | Should -Be @('USD 1012 1050', 'EUR 10 0')
        $script:costed.TopSpend[0].Name | Should -Be 'afw-hub'
    }

    It 'leaves out costs outside the resource groups read, when they were chosen' {
        $t = $script:tenant
        $cost = Get-AACContosoCost
        $cost.FilterGroups = $true
        $filtered = & $script:build @{ Cost = $cost; ResourceGroup = @($t.ResourceGroups | Where-Object name -EQ 'rg-app'); Resource = @($t.Resources | Where-Object resourceGroup -EQ 'rg-app'); Subscription = @($t.Subscriptions | Where-Object name -EQ 'sub-corp-apps') }
        (@($filtered.Items | Where-Object Level -EQ 'DeletedResources'))[0].CostMonthToDate | Should -Be 20 -Because 'only the deleted VM was in rg-app'
        (& $script:item $filtered 'sub-corp-apps').CostMonthToDate | Should -Be 170
    }

    It 'says which subscriptions had no cost and which couldn''t be read' {
        $cost = Get-AACContosoCost
        $cost.Rows = @($cost.Rows | Where-Object SubscriptionId -NE '11111111-1111-1111-1111-111111111111')
        $cost.Status['33333333-3333-3333-3333-333333333333'] = 'Cost Management does not support this offer.'
        $cost.Rows = @($cost.Rows | Where-Object SubscriptionId -NE '33333333-3333-3333-3333-333333333333')
        $read = & $script:build @{ Cost = $cost }
        (& $script:item $read 'sub-connectivity').CostStatus | Should -Be 'No cost'
        (& $script:item $read 'sub-corp-apps').CostStatus | Should -Be 'OK'
        (& $script:item $read 'sub-legacy').CostStatus | Should -Be 'Cost Management does not support this offer.'
    }

    It 'has no cost columns filled without cost' {
        $plain = & $script:build
        $plain.Stats.HasCost | Should -BeFalse
        (& $script:item $plain 'vm-web-01').CostMonthToDate | Should -BeNullOrEmpty
        @($plain.Items | Where-Object Level -EQ 'DeletedResources').Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - Get-AACInventory' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { & $script:graphBatchShim $Query $SubscriptionId $ManagementGroupId $AsObject $AllowFailure }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            if ($Uri -like '/tenants*') { return @{ value = @(@{ tenantId = $script:tenant.TenantId; displayName = 'Contoso'; defaultDomain = 'contoso.onmicrosoft.com' }) } }
            $request = $Body | ConvertFrom-Json
            $query = $request.query
            $data = if ($query -match 'securityresources') {
                if ($script:noDefender) { @() }
                elseif ($query -match "securescores' and") { $script:tenant.Security.Scores }
                elseif ($query -match 'securescorecontrols') { $script:tenant.Security.Controls }
                elseif ($query -match 'summarize healthy') { $script:tenant.Security.Summary }
                else { $script:tenant.Security.Recommendations }
            }
            elseif ($query -match 'managementgroups') { $script:tenant.ManagementGroups }
            elseif ($query -match "subscriptions'") { $script:tenant.Subscriptions }
            elseif ($query -match 'resourcegroups') { $script:tenant.ResourceGroups | Where-Object { $query -notmatch 'name in~' -or $query -match "'$($_.name)'" } }
            else { $script:tenant.Resources | Where-Object { $query -notmatch 'resourceGroup in~' -or $query -match "'$($_.resourceGroup)'" } }
            @{ data = @($data) }
        }
        $script:noDefender = $false
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 'aaaaaaaa-0000-0000-0000-00000000c0de'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'returns every node as an object, the tenant named' {
        $items = @(Get-AACInventory -NoDisplay)
        $items.Count | Should -Be 31
        $items[0].PSObject.TypeNames | Should -Contain 'AAC.InventoryItem'
        $items[0].Name | Should -Be 'Contoso'
        @($items | Where-Object Level -EQ 'Resource').Count | Should -Be 17
    }

    It 'reads the management groups tenant-wide, and scopes everything else' {
        $null = Get-AACInventory -ManagementGroupId 'mg-corp' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Body -and ($b = $Body | ConvertFrom-Json) -and $b.query -match 'managementgroups' -and -not $b.managementGroups -and -not $b.subscriptions } -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Body -and ($b = $Body | ConvertFrom-Json) -and $b.query -match '^resources' -and @($b.managementGroups) -contains 'mg-corp' } -Times 1 -Exactly
        $null = Get-AACInventory -SubscriptionId '22222222-2222-2222-2222-222222222222' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Body -and ($b = $Body | ConvertFrom-Json) -and $b.query -match '^resources' -and @($b.subscriptions) -contains '22222222-2222-2222-2222-222222222222' } -Times 1 -Exactly
    }

    It 'keeps only the resource groups asked for, and their subscriptions' {
        $items = @(Get-AACInventory -ResourceGroupName 'rg-app', 'rg-typo' -NoDisplay -WarningVariable warnings -WarningAction SilentlyContinue)
        @($items | Where-Object Level -EQ 'ResourceGroup').Name | Should -Be @('rg-app')
        @($items | Where-Object Level -EQ 'Subscription').Name | Should -Be @('sub-corp-apps')
        @($items | Where-Object Level -EQ 'Resource').Count | Should -Be 7
        "$warnings" | Should -BeLike "*No resource group named 'rg-typo'*"
        { Get-AACInventory -ResourceGroupName 'rg-nope' -NoDisplay } | Should -Throw "*No resource group named 'rg-nope'*"
    }

    It 'says so when a management group ID isn''t found' {
        { Get-AACInventory -ManagementGroupId 'Corp' -NoDisplay } | Should -Throw "*No management group with the ID 'Corp'*not its display name*"
    }

    It 'draws the tree at the console, down to -Depth, in characters any console can show' {
        $text = (& $script:capture { Get-AACInventory -NoPaging -NoSecurity } -Ascii).Text
        foreach ($expected in 'TENANT', 'Contoso', 'MG Landing Zones mg-landingzones', 'SUB sub-corp-apps', 'RG rg-app uksouth', 'rg-empty', 'empty', 'Most common resource types') {
            $text | Should -BeLike "*$expected*"
        }
        $text | Should -Not -BeLike '*vm-web-01*' -Because 'resources are listed with -Depth Resource only'
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
        (& $script:capture { Get-AACInventory -NoPaging -Depth Resource }).Text | Should -BeLike '*vm-web-01*'
        (& $script:capture { Get-AACInventory -NoPaging -Depth Subscription -NoSecurity }).Text | Should -Not -BeLike '*rg-app*'
    }

    It 'writes every node to CSV, and an HTML report with the tree and four tables' {
        $csv = Join-Path $TestDrive 'inventory.csv'
        $html = Join-Path $TestDrive 'inventory.html'
        $null = & $script:capture { Get-AACInventory -CsvPath $csv -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 31
        @($rows | Where-Object Level -EQ 'ResourceGroup').Count | Should -Be 5
        $rows[0].PSObject.Properties.Name | Should -Contain 'Path'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('managementGroups', 'subscriptions', 'groups', 'resources', 'controls', 'recommendations')
        $model.tree.root.n | Should -Be 'Contoso'
        $model.tree.root.l | Should -Be 't'
        $corpSub = $model.tree.root.k[0].k | Where-Object n -EQ 'Landing Zones' | ForEach-Object { $_.k } | ForEach-Object { $_.k } | Select-Object -First 1
        $corpSub.n | Should -Be 'sub-corp-apps'
        $corpSub.f.table | Should -Be 'groups'
        ($corpSub.k | Where-Object n -EQ 'rg-empty').x | Should -Be 1
        ($model.tiles | Where-Object label -EQ 'empty resource groups').value | Should -Be '1'
        ($model.tiles | Where-Object label -Like 'secure score*').value | Should -Be '56%'
        $corpSub.p | Should -Be 36
        $corpSub.h | Should -Be 2
        ($model.tables | Where-Object id -EQ 'recommendations').rows[0].Severity | Should -Be 'High'
        (($model.tables | Where-Object id -EQ 'resources').columns | Where-Object key -EQ 'SecureScore').type | Should -Be 'score'
    }

    It 'shows the security posture at the console, and can skip it' {
        $text = (& $script:capture { Get-AACInventory -NoPaging }).Text
        $text | Should -BeLike '*56%*secure score (fair)*'
        $text | Should -BeLike '*sub-corp-apps*36%*H2*'
        $text | Should -BeLike '*Security controls with the most to gain*Secure management ports*+16%*'
        $text | Should -BeLike '*High-severity findings (2)*'
        $null = Get-AACInventory -NoSecurity -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Body -and ($Body | ConvertFrom-Json).query -match 'securityresources' } -Times 4 -Exactly -Because 'only the first run read Defender'
    }

    It 'says so, and leaves the security columns out, when there is no Defender data' {
        $script:noDefender = $true
        $html = Join-Path $TestDrive 'no-defender.html'
        $null = & $script:capture { Get-AACInventory -HtmlPath $html }
        $content = Get-Content -LiteralPath $html -Raw
        $model = [regex]::Match($content, '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Not -Contain 'controls'
        @(($model.tables | Where-Object id -EQ 'resources').columns.key) | Should -Not -Contain 'SecureScore'
        @($model.notices.text) -join ' ' | Should -BeLike '*No Microsoft Defender for Cloud data*'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'inventory.pdf'
        $null = & $script:capture { Get-AACInventory -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }

    Context '-Cost' {
        BeforeEach {
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostBatch -MockWith { & $script:costBatchShim $Scope $Body }
            $script:costRows = (Get-AACContosoCost).Rows
            $script:costGroupRows = $null
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -MockWith {
                if ($SubscriptionId -eq '33333333-3333-3333-3333-333333333333') { throw 'Cost Management does not support the offer of this subscription.' }
                @($script:costRows | Where-Object SubscriptionId -EQ $SubscriptionId)
            }
        }
        AfterEach { $script:costGroupRows = $null }

        It 'asks once for the whole tenant when Cost Management allows it' {
            $script:costGroupRows = @{ 'aaaaaaaa-0000-0000-0000-00000000c0de' = $script:costRows }
            $items = @(Get-AACInventory -Cost -NoDisplay -NoSecurity)
            ($items | Where-Object Name -EQ 'sub-corp-apps').CostMonthToDate | Should -Be 212
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostBatch -Times 1 -Exactly -ParameterFilter { @($Scope) -join ',' -eq '/providers/Microsoft.Management/managementGroups/aaaaaaaa-0000-0000-0000-00000000c0de' }
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -Times 0 -Exactly
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostBatch -Times 1 -Exactly -ParameterFilter {
                $Body.timePeriod.from -eq ([datetime]::new((Get-Date).Year, (Get-Date).Month, 1).AddMonths(-1).ToString('yyyy-MM-ddT00:00:00Z', [cultureinfo]::InvariantCulture)) -and
                (($Body.dataset.grouping | ForEach-Object { $_.name }) -join ',') -eq 'ResourceId,SubscriptionId' -and $Body.dataset.granularity -eq 'Monthly'
            }
        }

        It 'falls back to each subscription when the management group can''t be asked, and says which failed' {
            $items = @(Get-AACInventory -Cost -NoDisplay -NoSecurity)
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostBatch -Times 2 -Exactly -Because 'the management group, then the subscriptions'
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostQuery -Times 3 -Exactly
            ($items | Where-Object Name -EQ 'sub-connectivity').CostMonthToDate | Should -Be 800
            ($items | Where-Object Name -EQ 'sub-legacy').CostStatus | Should -BeLike '*does not support*'
            ($items | Where-Object Name -EQ 'sub-legacy').CostMonthToDate | Should -Be 0
        }

        It 'asks each subscription straight away for a subscription or resource group selection' {
            $null = Get-AACInventory -Cost -SubscriptionId '22222222-2222-2222-2222-222222222222' -NoDisplay -NoSecurity
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostBatch -Times 0 -Exactly -ParameterFilter { @($Scope) -match 'managementGroups' }
        }

        It 'shows the costs at the console: tiles, each node, deleted resources and the top spenders' {
            $text = (& $script:capture { Get-AACInventory -Cost -NoPaging -NoSecurity -Depth Resource } -Ascii).Text
            foreach ($expected in 'month to date', 'SUB sub-connectivity', '800.00 USD MTD', 'DEL Deleted resources', 'cost not read', 'Top spend this month (USD)', "each subscription's billing currency") {
                $text | Should -BeLike "*$expected*"
            }
        }

        It 'adds the costs to the HTML report: tiles, tree pills and money columns' {
            $script:costGroupRows = @{ 'aaaaaaaa-0000-0000-0000-00000000c0de' = $script:costRows }
            $html = Join-Path $TestDrive 'inventory-cost.html'
            $csv = Join-Path $TestDrive 'inventory-cost.csv'
            $null = & $script:capture { Get-AACInventory -Cost -HtmlPath $html -CsvPath $csv -NoSecurity }
            $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
            ($model.tiles | Where-Object label -EQ 'cost month to date' | Select-Object -First 1).value | Should -Be '1,012.00 USD'
            $corpSub = $model.tree.root.k[0].k | Where-Object n -EQ 'Landing Zones' | ForEach-Object { $_.k } | ForEach-Object { $_.k } | Select-Object -First 1
            $corpSub.co | Should -Be '212.00 USD'
            ($corpSub.k | Where-Object l -EQ 'd').n | Should -Be 'Deleted resources'
            $model.tree.root.co | Should -Be 'several currencies'
            $column = ($model.tables | Where-Object id -EQ 'resources').columns | Where-Object key -EQ 'CostMonthToDate'
            $column.type | Should -Be 'money'
            $column.currencyKey | Should -Be 'Currency'
            @(($model.tables | Where-Object id -EQ 'resources').rows | Where-Object Type -EQ '(deleted resources)').Count | Should -Be 1
            @(Import-Csv -LiteralPath $csv | Where-Object Level -EQ 'DeletedResources').Count | Should -Be 1
        }

        It 'writes the cost section to the PDF' -Skip:(-not $script:canWritePdf) {
            $pdf = Join-Path $TestDrive 'inventory-cost.pdf'
            $null = & $script:capture { Get-AACInventory -Cost -PdfPath $pdf -NoSecurity }
            (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
        }
    }
}

Describe 'Azure Admin Console - inventory insights' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoInsight.ps1')
        $script:insightRows = Get-AACContosoInsight
        $script:buildInsight = {
            param([string[]] $RequiredTag = @())
            $items = @((& $script:build).Items)
            # A cost on the unattached disk, as -Cost would give it.
            $disk = [pscustomobject]@{ Level = 'Resource'; Id = $script:insightRows.DiskId; Name = 'disk-old'; CostMonthToDate = 14.5; Currency = 'USD'; Tags = 'owner=platform'; SubscriptionId = '22222222-2222-2222-2222-222222222222' }
            $rows = @{}
            foreach ($key in @($script:insightRows.Keys | Where-Object { $_ -like 'insight*' })) { $rows[$key] = $script:insightRows[$key] }
            InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $rows; I = @($items) + @($disk); T = $RequiredTag } { param($R, $I, $T) ConvertTo-AACInventoryInsight -Rows $R -Item $I -RequiredTag $T }
        }
        $script:ins = & $script:buildInsight
    }

    It 'breaks the estate down: sizes, operating systems, power states, Azure and Arc, storage, databases' {
        $b = $script:ins.Breakdowns
        @($b.VmSizes | ForEach-Object { "$($_.Label) $($_.Value)" }) | Should -Be @('Standard_D2s_v5 2', 'Standard_B2s 1')
        @($b.OsVersions | ForEach-Object { "$($_.Label) $($_.Value)" }) | Should -Be @('Ubuntu 22.04 2', 'Ubuntu 20.04 1', 'Windows Server 2019 1', 'Windows Server 2022 1') -Because 'from the instance view, or the image when there is none'
        @($b.PowerStates.Label) | Should -Contain 'Stopped (still billed)'
        @($b.Hybrid | ForEach-Object { "$($_.Label) $($_.Value)" }) | Should -Be @('Azure VMs 3', 'Arc servers (connected) 1', 'Arc servers (not connected) 1')
        @($b.StorageReplication.Label | Sort-Object) | Should -Be @('LRS', 'RA-GRS', 'ZRS')
        @($b.DatabaseTiers.Label | Sort-Object) | Should -Be @('Azure SQL - GeneralPurpose', 'Azure SQL - GeneralPurpose (serverless)', 'Cosmos DB - serverless', 'PostgreSQL - Burstable')
    }

    It 'lists what needs attention, most serious first, with its cost' {
        $f = @($script:ins.Findings)
        @($f.Finding | Select-Object -Unique | Sort-Object) | Should -Be @('Classic resource', 'Connection down', 'Disconnected Arc server', 'Empty resource group', 'Stopped VM (still billed)', 'Subnet nearly full', 'Unattached disk', 'Unused network interface', 'Unused public IP')
        $f[0].Severity | Should -Be 'High'
        $disk = $f | Where-Object Finding -EQ 'Unattached disk'
        $disk.Detail | Should -BeLike '128 GB Premium_LRS*'
        $disk.CostMonthToDate | Should -Be 14.5
        ($f | Where-Object Finding -EQ 'Subnet nearly full').Resource | Should -Be 'vnet-app / snet-app'
        ($f | Where-Object Finding -EQ 'Subnet nearly full').Severity | Should -Be 'Medium'
        ($f | Where-Object Finding -EQ 'Connection down').Resource | Should -Be 'cn-branch'
        ($f | Where-Object Finding -EQ 'Empty resource group').Resource | Should -Be 'rg-empty'
        $script:ins.Stats.UnattachedDiskGb | Should -Be 128
        $script:ins.Stats.WasteCost | Should -Be 14.5
        $f[0].PSObject.TypeNames | Should -Contain 'AAC.InventoryFinding'
    }

    It 'counts each subnet''s used and usable IPs (Azure keeps 5)' {
        $app = $script:ins.Subnets | Where-Object Subnet -EQ 'snet-app'
        "$($app.Used)/$($app.Usable)/$($app.UsedPercent)" | Should -Be '10/11/91'
        $script:ins.Subnets[0].Subnet | Should -Be 'snet-app' -Because 'fullest first'
        ($script:ins.Subnets | Where-Object Subnet -EQ 'snet-data').Used | Should -Be 0
    }

    It 'measures tag coverage: the required tags, or else the most used' {
        $script:ins.Breakdowns.TagCoverage[0].Label | Should -Be 'owner'
        $script:ins.Breakdowns.TagCoverage[0].Value | Should -Be 100
        $required = & $script:buildInsight @('owner', 'CostCenter')
        @($required.Breakdowns.TagCoverage.Label) | Should -Be @('owner', 'CostCenter')
        ($required.Breakdowns.TagCoverage | Where-Object Label -EQ 'CostCenter').Value | Should -Be 0
        $required.Stats.TagCompliant | Should -Be 0
    }
}

Describe 'Azure Admin Console - Get-AACInventory -Insight' {
    BeforeAll { . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoInsight.ps1'); $script:insightRows = Get-AACContosoInsight }
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            if ($Uri -like '/tenants*') { return @{ value = @(@{ tenantId = $script:tenant.TenantId; displayName = 'Contoso' }) } }
            $query = ($Body | ConvertFrom-Json).query
            $data = if ($query -match 'managementgroups') { $script:tenant.ManagementGroups }
            elseif ($query -match "subscriptions'") { $script:tenant.Subscriptions }
            elseif ($query -match 'resourcegroups') { $script:tenant.ResourceGroups }
            else { $script:tenant.Resources }
            @{ data = @($data) }
        }
        # The inventory's own queries through the shim; the insights' from the fixture.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rest = [ordered]@{}
            foreach ($key in @($Query.Keys)) { if ($key -notlike 'insight*') { $rest[$key] = $Query[$key] } }
            $result = & $script:graphBatchShim $rest $SubscriptionId $ManagementGroupId $AsObject $AllowFailure
            foreach ($key in @($Query.Keys)) { if ($key -like 'insight*') { $result.Rows[$key] = @($script:insightRows[$key]) } }
            $result
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 'aaaaaaaa-0000-0000-0000-00000000c0de'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the insights in the same batch as the inventory, narrowed to the resource groups asked for' {
        $null = Get-AACInventory -Insight -NoSecurity -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 1 -Exactly -ParameterFilter { $Query.Contains('resources') -and $Query.Contains('insightVms') -and $Query.Contains('insightSubnets') }
        $null = Get-AACInventory -Insight -NoSecurity -ResourceGroupName 'rg-app' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 1 -Exactly -ParameterFilter { ([string]$Query['insightDisks']).Contains("resourceGroup in~ ('rg-app')") }
        $null = Get-AACInventory -NoSecurity -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 2 -Exactly -ParameterFilter { $Query.Contains('insightVms') } -Because 'without -Insight, no insight query'
    }

    It 'shows the insights at the console, in characters any console can show' {
        $text = (& $script:capture { Get-AACInventory -Insight -NoSecurity -NoPaging } -Ascii).Text
        foreach ($expected in 'Insights', 'Azure VMs', 'VM sizes', 'Operating systems', 'VM power states', 'Storage account replication', 'Database tiers', 'Needs attention', 'Unattached disk', 'Stopped VM (still billed)', 'Classic resource', 'Subnet nearly full', 'VPN and ExpressRoute', 'cn-branch') {
            $text | Should -BeLike "*$expected*"
        }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'adds donut charts and the insight tables to the HTML report' {
        $html = Join-Path $TestDrive 'insight.html'
        $null = & $script:capture { Get-AACInventory -Insight -NoSecurity -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        foreach ($id in 'attention', 'machines', 'subnets', 'connections') { @($model.tables.id) | Should -Contain $id }
        $sizes = $model.charts | Where-Object title -EQ 'VM sizes'
        $sizes.kind | Should -Be 'donut'
        $sizes.table | Should -Be 'machines'
        $sizes.column | Should -Be 'Size'
        ($model.tiles | Where-Object label -EQ 'Azure VMs').value | Should -Be '3'
    }

    It 'writes the insights to the PDF' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'insight.pdf'
        $null = & $script:capture { Get-AACInventory -Insight -NoSecurity -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
