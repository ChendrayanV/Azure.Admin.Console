<#
    Unit tests for Get-AACNetworkSecurityGroup: the assessment of made-up
    Contoso NSGs (Fixtures\ContosoNsg.ps1) - rules, associations, flow logs,
    diagnostic settings and every check - and the command with Azure
    Resource Graph and Resource Manager mocked: scope, filters, the view and
    the exports.
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
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoNsg.ps1')
    $script:f = Get-AACContosoNsg
    $script:assess = {
        param([hashtable] $With = @{})
        $p = @{ NetworkSecurityGroup = $script:f.NetworkSecurityGroups; NetworkInterface = $script:f.NetworkInterfaces; Subnet = $script:f.Subnets; FlowLog = $script:f.FlowLogs; Diagnostic = $script:f.Diagnostics; SubscriptionName = @{ $script:f.SubscriptionId = 'sub-corp-apps' } }
        foreach ($key in $With.Keys) { $p[$key] = $With[$key] }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $p } { param($P) ConvertTo-AACNsgAssessment @P }
    }
    $script:a = & $script:assess
    $script:nsg = { param([string] $Name) $script:a.Groups | Where-Object Name -EQ $Name }
    $script:findings = { param([string] $Nsg, [string] $Check) , @($script:a.Findings | Where-Object { $_.Nsg -eq $Nsg -and $_.Check -eq $Check }) }
    $script:capture = {
        param([scriptblock] $Render, [switch] $Ascii)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 180
        $console.Profile.Capabilities.Unicode = -not $Ascii
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - NSG assessment' {
    It 'reads every rule, custom then default by priority, with application security groups by name' {
        $web = & $script:nsg 'nsg-web'
        @($web.Rules | Where-Object Direction -EQ 'Inbound' | ForEach-Object Name) | Should -Be @('Allow-HTTPS-In', 'Allow-SSH-Anywhere', 'Allow-App-Range', 'Allow-VNet-All', 'Allow-HTTPS-Again', 'AllowVnetInBound', 'AllowAzureLoadBalancerInBound', 'DenyAllInBound')
        ($web.Rules | Where-Object Name -EQ 'Allow-HTTPS-In').Destination | Should -Be 'asg:asg-web'
        $web.InboundRules | Should -Be 5
        $web.OutboundRules | Should -Be 1
        ($web.Rules | Where-Object Name -EQ 'DenyAllInBound').IsDefault | Should -BeTrue
    }

    It 'captures what each NSG is applied to' {
        $web = & $script:nsg 'nsg-web'
        $web.Subnets[0].VirtualNetwork | Should -Be 'vnet-spoke'
        $web.Subnets[0].Prefix | Should -Be '10.1.1.0/24'
        $mgmt = & $script:nsg 'nsg-mgmt'
        $mgmt.NetworkInterfaces[0].VirtualMachine | Should -Be 'vm-web-02'
        $mgmt.NetworkInterfaces[0].PrivateIp | Should -Be '10.1.1.5'
        $mgmt.AppliedTo | Should -Be 'NIC nic-web-02 (vm-web-02)'
        (& $script:nsg 'nsg-unused').Associated | Should -BeFalse
        $web.VirtualMachines | Should -Be 2 -Because 'both VMs have a NIC in snet-web'
        $mgmt.VirtualMachines | Should -Be 1
        (& $script:nsg 'nsg-unused').VirtualMachines | Should -Be 0
    }

    It 'flags what is open to the internet: management ports and every port High, a wide range Medium' {
        $ssh = & $script:findings 'nsg-web' 'Open to the internet'
        @($ssh | Where-Object Severity -EQ 'High').Rule | Should -Be @('Allow-SSH-Anywhere')
        @($ssh | Where-Object Severity -EQ 'Medium').Rule | Should -Be @('Allow-App-Range')
        ($ssh | Where-Object Severity -EQ 'Medium').Detail | Should -BeLike '*1,001 ports*'
        (& $script:findings 'nsg-mgmt' 'Open to the internet')[0].Detail | Should -Be "Allows RDP (3389) from '0.0.0.0/0'."
        (& $script:findings 'nsg-unused' 'Open to the internet')[0].Detail | Should -BeLike 'Allows * on every port*'
        ((& $script:nsg 'nsg-web').Rules | Where-Object Name -EQ 'Allow-HTTPS-In').Risk | Should -BeNullOrEmpty -Because 'HTTPS from the internet is what a web tier is for'
        (& $script:findings 'nsg-data' 'Open to the internet').Count | Should -Be 0 -Because 'SQL is open only to the app subnet'
    }

    It 'finds a shadowed rule and a rule open to the whole virtual network' {
        $shadowed = & $script:findings 'nsg-web' 'Shadowed rule'
        $shadowed.Count | Should -Be 1
        $shadowed[0].Rule | Should -Be 'Allow-HTTPS-Again'
        $shadowed[0].Detail | Should -BeLike '*Allow-HTTPS-In (priority 100) matches the same traffic first and already does the same.'
        (& $script:findings 'nsg-web' 'Open inside the network')[0].Rule | Should -Be 'Allow-VNet-All'
        (& $script:findings 'nsg-data' 'Shadowed rule').Count | Should -Be 0 -Because 'Deny-Internet has another source than Allow-Sql-From-App'
    }

    It 'evaluates a NIC''s NSG and its subnet''s NSG as Azure does, and reports where they disagree' {
        $conflicts = & $script:findings 'nsg-mgmt' 'Subnet and NIC conflict'
        $conflicts.Count | Should -Be 4
        ($conflicts | Where-Object Detail -Like '*Tcp 443*').Detail | Should -Be 'Internet -> Tcp 443 to nic-web-02 (10.1.1.5): the subnet NSG nsg-web allows it (Allow-HTTPS-In), the NIC NSG nsg-mgmt denies it (DenyAllInBound) - so it is blocked.'
        ($conflicts | Where-Object Detail -Like '*Tcp 3389*').Detail | Should -BeLike '*subnet NSG nsg-web denies it (DenyAllInBound), the NIC NSG nsg-mgmt allows it (Allow-RDP)*'
        (& $script:findings 'nsg-web' 'Subnet and NIC conflict').Count | Should -Be 4 -Because 'both NSGs get the finding'
        $script:a.Stats.Conflicts | Should -Be 4
    }

    It 'counts a virtual network flow log on the VNet as flow logs for the NSG, and flags the gaps' {
        (& $script:nsg 'nsg-web').FlowLogs | Should -Be 'Enabled (VNet flow log)'
        (& $script:nsg 'nsg-mgmt').FlowLogs | Should -Be 'Enabled (VNet flow log)' -Because 'its NIC is in vnet-spoke'
        (& $script:nsg 'nsg-web').TrafficAnalytics | Should -BeTrue
        (& $script:findings 'nsg-web' 'Flow log retention')[0].Detail | Should -BeLike '*30 days*'
        (& $script:nsg 'nsg-data').FlowLogs | Should -Be 'None'
        (& $script:findings 'nsg-data' 'No flow logs')[0].Severity | Should -Be 'Medium'
        (& $script:nsg 'nsg-legacy').FlowLogs | Should -Be 'Enabled (NSG flow log)'
        (& $script:findings 'nsg-legacy' 'NSG flow log retiring')[0].Detail | Should -BeLike '*30 September 2027*'
        (& $script:findings 'nsg-legacy' 'Traffic Analytics off').Count | Should -Be 1
        (& $script:findings 'nsg-unused' 'No flow logs').Count | Should -Be 0 -Because 'an unassociated NSG is flagged as such instead'
    }

    It 'reads diagnostic settings, and flags an NSG without them' {
        $web = & $script:nsg 'nsg-web'
        $web.Diagnostics | Should -Be 'Enabled'
        $web.LogDestinations | Should -Be 'Log Analytics: law-security'
        (& $script:nsg 'nsg-data').LogDestinations | Should -Be 'Storage: staudit'
        (& $script:findings 'nsg-mgmt' 'No diagnostic settings')[0].Severity | Should -Be 'Low'
        $unread = & $script:assess @{ Diagnostic = $null }
        ($unread.Groups | Where-Object Name -EQ 'nsg-web').Diagnostics | Should -Be 'Not checked'
        @($unread.Findings | Where-Object Check -EQ 'No diagnostic settings').Count | Should -Be 0
    }

    It 'flags an NSG applied to nothing, rates each NSG, and counts it all' {
        (& $script:findings 'nsg-unused' 'Unassociated')[0].Severity | Should -Be 'Medium'
        (& $script:nsg 'nsg-web').Risk | Should -Be 'High'
        (& $script:nsg 'nsg-data').Risk | Should -Be 'Medium'
        (& $script:nsg 'nsg-legacy').Risk | Should -Be 'Low'
        $script:a.Groups[0].Risk | Should -Be 'High' -Because 'most at risk first'
        $script:a.Findings[0].Severity | Should -Be 'High' -Because 'most severe first'
        "$($script:a.Stats.High)/$($script:a.Stats.Medium)/$($script:a.Stats.Low)/$($script:a.Stats.Info)" | Should -Be '3/11/7/2'
        $script:a.Stats.Unassociated | Should -Be 1
        $script:a.Stats.WithoutFlowLogs | Should -Be 1
        $script:a.Stats.WithoutDiagnostics | Should -Be 3
    }
}

Describe 'Azure Admin Console - Get-AACNetworkSecurityGroup' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { & $script:graphBatchShim $Query $SubscriptionId $ManagementGroupId $AsObject $AllowFailure }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $results = @{}
            foreach ($target in $Uri) {
                $key = ($target -replace '/providers/Microsoft.Insights/diagnosticSettings.*$', '').ToLowerInvariant()
                $d = $script:f.Diagnostics[$key]
                $items = [System.Collections.Generic.List[object]]::new()
                foreach ($setting in @($d.Settings | Where-Object { $_ })) { $items.Add(@{ name = $setting.Name; properties = @{ workspaceId = $(if ($setting.Workspace) { "/x/workspaces/$($setting.Workspace)" }); storageAccountId = $(if ($setting.Storage) { "/x/storageAccounts/$($setting.Storage)" }); logs = @(@{ categoryGroup = $setting.Categories; enabled = $true }) } }) }
                $results[$target] = @{ Status = 200; Body = @{ value = @($items) }; Items = $items; Error = '' }
            }
            $results
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            $query = ($Body | ConvertFrom-Json).query
            $data = if ($query -match 'resourcecontainers') { @(@{ subscriptionId = $script:f.SubscriptionId; name = 'sub-corp-apps' }) }
            elseif ($query -match 'networksecuritygroups') { $script:f.NetworkSecurityGroups | Where-Object { $query -notmatch 'resourceGroup in~' -or $query -match "'$($_.resourceGroup)'" } }
            elseif ($query -match 'networkinterfaces') {
                @($script:f.NetworkInterfaces | ForEach-Object { @{ id = $_.id; name = $_.name; resourceGroup = $_.resourceGroup; nsg = $_.nsg.ToLowerInvariant(); vm = $_.vm.ToLowerInvariant(); ipConfigurations = @(@{ properties = @{ privateIPAddress = $_.ips[0]; subnet = @{ id = $_.subnet }; applicationSecurityGroups = @($_.asgs | ForEach-Object { @{ id = $_ } }) } }) } })
            }
            elseif ($query -match 'virtualnetworks') { @($script:f.Subnets | ForEach-Object { @{ subnetId = $_.subnetId.ToLowerInvariant(); name = $_.name; vnetId = $_.vnetId.ToLowerInvariant(); vnetName = $_.vnetName; prefix = $_.prefix; nsg = $_.nsg.ToLowerInvariant() } }) }
            elseif ($query -match 'flowlogs') { $script:f.FlowLogs }
            @{ data = @($data) }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'assesses every NSG with no parameters, and returns the objects' {
        $groups = @(Get-AACNetworkSecurityGroup -NoDisplay)
        $groups.Count | Should -Be 5
        $groups[0].PSObject.TypeNames | Should -Contain 'AAC.NetworkSecurityGroup'
        ($groups | Where-Object Name -EQ 'nsg-web').Diagnostics | Should -Be 'Enabled'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -like '*diagnosticSettings*' }).Count -eq 5 } -Times 1 -Exactly -Because 'all five are read in one parallel batch'
    }

    It 'filters by subscription, resource group and name (with wildcards), and says what it can''t find' {
        $null = Get-AACNetworkSecurityGroup -SubscriptionId $script:f.SubscriptionId -ResourceGroupName 'rg-network' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $b = $Body | ConvertFrom-Json; $b.query -match 'networksecuritygroups' -and $b.query -match "resourceGroup in~ \('rg-network'\)" -and @($b.subscriptions) -contains $script:f.SubscriptionId }
        @((Get-AACNetworkSecurityGroup -Name 'nsg-w*', 'nsg-data' -NoDisplay).Name) | Sort-Object | Should -Be @('nsg-data', 'nsg-web')
        $null = Get-AACNetworkSecurityGroup -Name 'nsg-web', 'nsg-typo' -NoDisplay -WarningVariable warnings -WarningAction SilentlyContinue
        "$warnings" | Should -BeLike "*No network security group named 'nsg-typo'*"
        { Get-AACNetworkSecurityGroup -Name 'nsg-nope' -NoDisplay } | Should -Throw "*No network security group named 'nsg-nope'*"
    }

    It 'skips the diagnostic settings with -NoDiagnosticSetting' {
        $groups = @(Get-AACNetworkSecurityGroup -NoDiagnosticSetting -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 0 -Exactly
        @($groups.Diagnostics | Select-Object -Unique) | Should -Be @('Not checked')
    }

    It 'shows the NSGs, the findings and - for a few - their rules, in characters any console can show' {
        $text = (& $script:capture { Get-AACNetworkSecurityGroup -NoPaging } -Ascii).Text
        foreach ($expected in 'Network security groups', 'nsg-web', 'HIGH', 'Open to the internet', 'Subnet and NIC conflict', '-Name shows an NSG in detail') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
        $detail = (& $script:capture { Get-AACNetworkSecurityGroup -Name 'nsg-web' -NoPaging }).Text
        foreach ($expected in 'Inbound rules', 'Allow-SSH-Anywhere', 'DenyAllInBound', 'Outbound rules', 'vnet-spoke/snet-web', 'Enabled (VNet flow log)') { $detail | Should -BeLike "*$expected*" }
    }

    It 'writes every rule to CSV, and an HTML report with the NSGs, findings, rules, associations and logging' {
        $csv = Join-Path $TestDrive 'nsg.csv'
        $html = Join-Path $TestDrive 'nsg.html'
        $null = & $script:capture { Get-AACNetworkSecurityGroup -CsvPath $csv -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 41
        ($rows | Where-Object Name -EQ 'Allow-SSH-Anywhere').Risk | Should -Be 'High'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('nsgs', 'findings', 'rules', 'associations', 'logging')
        ($model.tables | Where-Object id -EQ 'findings').rows[0].Severity | Should -Be 'High'
        ($model.tiles | Where-Object label -EQ 'high-severity findings').value | Should -Be '3'
        @(($model.tables | Where-Object id -EQ 'logging').rows | Where-Object Kind -EQ 'NSG flow log').Count | Should -Be 1
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'nsg.pdf'
        $null = & $script:capture { Get-AACNetworkSecurityGroup -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 2000
    }
}
