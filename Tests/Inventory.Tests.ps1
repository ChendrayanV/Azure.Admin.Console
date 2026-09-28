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

Describe 'Azure Admin Console - Get-AACInventory' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
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
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $b = $Body | ConvertFrom-Json; $b.query -match 'managementgroups' -and -not $b.managementGroups -and -not $b.subscriptions } -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $b = $Body | ConvertFrom-Json; $b.query -match '^resources' -and @($b.managementGroups) -contains 'mg-corp' } -Times 1 -Exactly
        $null = Get-AACInventory -SubscriptionId '22222222-2222-2222-2222-222222222222' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $b = $Body | ConvertFrom-Json; $b.query -match '^resources' -and @($b.subscriptions) -contains '22222222-2222-2222-2222-222222222222' } -Times 1 -Exactly
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
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { ($Body | ConvertFrom-Json).query -match 'securityresources' } -Times 4 -Exactly -Because 'only the first run read Defender'
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
}
