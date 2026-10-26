<#
    Unit tests for Get-AACIPAMReport: a made-up Contoso estate
    (Fixtures\ContosoIpam.ps1) measured against an address plan - blocks,
    networks, subnets, every IP address, overlaps, free space, the next
    ranges and CIDR checks - the plan read from a hashtable, .psd1, .json and
    .csv (and the private ranges when none is given), and the console view
    and the reports, with Azure Resource Graph mocked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoIpam.ps1')
    $script:f = Get-AACContosoIpam
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 170
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:modelOf = { param([string] $Path) [regex]::Match((Get-Content -LiteralPath $Path -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json }
}

Describe 'Azure Admin Console - Get-AACIPAMReport' {
    BeforeEach {
        $script:failQuery = @()
        $script:graphCalls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:graphCalls.Add(@{ Keys = @($Query.Keys); SubscriptionId = @($SubscriptionId); ManagementGroupId = @($ManagementGroupId) })
            $rows = @{}
            $errors = @{}
            foreach ($key in @($Query.Keys)) {
                $rows[$key] = [System.Collections.Generic.List[object]]::new()
                if ($script:failQuery -contains $key) { $errors[$key] = 'Forbidden'; continue }
                foreach ($row in @($script:f.Rows[$key])) {
                    if ($key -in 'vnets', 'hubs' -and $SubscriptionId -and @($SubscriptionId) -notcontains $row.subscriptionId) { continue }
                    $rows[$key].Add($row)
                }
            }
            @{ Rows = $rows; Errors = $errors }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'measures each block: networks, address space allocated (overlaps once), free space, the next range and how many fit' {
        $blocks = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -NoDisplay)
        @($blocks | ForEach-Object { "$($_.Space)/$($_.Block) | $($_.Networks) | $($_.Allocated) | $($_.AllocatedPercent) | $($_.LargestFree) | $($_.Next) | $($_.Fits) | $($_.IpsUsed) | $($_.Status)" }) | Should -Be @(
            'Corp/Azure-EU | 6 | 3328 | 5.1 | 10.20.64.0/18 | 10.20.251.0/24 | 243 | 17 | OK'
            'Corp/Azure-US | 2 | 2304 | 56.2 | 10.30.8.0/22 | 10.30.14.0/24 | 7 | 3 | OK'
            'Lab/Lab-1 | 0 | 0 | 0 | 172.16.0.0/22 | 172.16.0.0/24 | 4 | 0 | Unused'
        )
        $blocks[0].PSObject.TypeNames | Should -Contain 'AAC.IpamBlock'
        $blocks[0].Range | Should -Be '10.20.0.0 - 10.20.255.255'
        # A tighter threshold turns the US block (56%) into a warning, with a finding.
        $warned = Get-AACIPAMReport -AddressPlan $script:f.Plan -WarningPercent 50 -CriticalPercent 70 -NoDisplay | Where-Object Block -EQ 'Azure-US'
        $warned.Status | Should -Be 'Warning'
        @(Get-AACIPAMReport -AddressPlan $script:f.Plan -WarningPercent 50 -CriticalPercent 70 -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.Item) | $($_.Finding)" }) | Should -Contain 'Medium | Azure-US | Block filling up'
    }

    It 'places every network in the plan - managed, partly, outside - with Virtual WAN hubs, external ranges, DNS servers and peerings' {
        $networks = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -View Network -NoDisplay)
        @($networks | ForEach-Object { "$($_.Network) | $($_.Kind) | $($_.Status) | $($_.Block)" }) | Should -Be @(
            'London DC | External | Managed | Azure-EU'
            'vhub-weu | Virtual WAN hub | Managed | Azure-EU'
            'vnet-hub-weu | Virtual network | Managed | Azure-EU'
            'vnet-legacy | Virtual network | Managed | Azure-EU'
            'vnet-spoke-app | Virtual network | Managed | Azure-EU'
            'vnet-spoke-dup | Virtual network | Managed | Azure-EU'
            'vnet-straddle | Virtual network | Partly managed | Azure-US'
            'vnet-us | Virtual network | Managed | Azure-US'
            'vnet-rogue | Virtual network | Unmanaged | '
        )
        $hub = $networks | Where-Object Network -EQ 'vnet-hub-weu'
        "$($hub.DnsServers) | $($hub.Subnets) | $($hub.Used)/$($hub.Usable) | $($hub.Unallocated) | $($hub.PeeredWith) | $($hub.Subscription)" | Should -Be '10.20.1.4 | 3 | 5/337 | 672 | vnet-spoke-app | Contoso Connectivity'
        ($networks | Where-Object Network -EQ 'vnet-us').DnsServers | Should -Be 'Azure-provided'
        ($networks | Where-Object Network -EQ 'vnet-spoke-app').IpamReservation | Should -Be 'res-123'
    }

    It 'lists every address Azure counts in a subnet - so the count and the list agree, unattached interfaces included' {
        $subnets = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -View Subnet -NoDisplay)
        $ips = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -View IpAddress -NoDisplay)
        foreach ($s in $subnets) { @($ips | Where-Object { $_.Network -eq $s.Network -and $_.Subnet -eq $s.Subnet }).Count | Should -Be $s.Used -Because "$($s.Network)/$($s.Subnet) counts $($s.Used)" }
        $web = $subnets | Where-Object Subnet -EQ 'snet-web'
        "$($web.Prefix) | $($web.UsableRange) | $($web.Usable) | $($web.Used) | $($web.Available) | $($web.UsedPercent) | $($web.Status)" | Should -Be '10.20.4.0/28 | 10.20.4.4 - 10.20.4.14 | 11 | 10 | 1 | 90.9 | Critical'
        ($subnets | Where-Object Subnet -EQ 'snet-func').Purpose | Should -Be 'Delegated: Microsoft.Web/serverFarms'
        ($subnets | Where-Object Subnet -EQ 'snet-pe').Purpose | Should -Be 'Private endpoints'
        ($subnets | Where-Object Subnet -EQ 'snet-shared').Kinds | Should -Be 'Virtual machine 2, Network interface (not attached) 1'
        $have = @($ips | ForEach-Object { "$($_.PrivateIp) | $($_.Kind) | $($_.Resource) | $($_.Attached) | $($_.PublicIp) | $($_.Allocation)" })
        foreach ($expected in '10.20.1.4 | Virtual machine | nic-vm1 | vm1 | 20.50.1.10 | Static', '10.20.1.6 | Network interface (not attached) | nic-orphan |  |  | Dynamic', '10.20.5.4 | Private endpoint | pe-sql.nic | pe-sql -> sql-prod |  | Dynamic', '10.20.6.4 | Load balancer | lb-int |  |  | Static', '10.20.0.68 | Azure Firewall | fw-hub |  |  | Dynamic', '10.30.0.5 | VM scale set instance | vmss-api_1 | vmss-api |  | Dynamic') { $have | Should -Contain $expected }
        $ips[0].PSObject.TypeNames | Should -Contain 'AAC.IpamIpAddress'
    }

    It 'finds every overlap - High when peered, Medium with an external range - and the findings that go with them' {
        $overlaps = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -View Overlap -NoDisplay)
        @($overlaps | ForEach-Object { "$($_.Severity) | $($_.NetworkA) $($_.PrefixA) | $($_.NetworkB) $($_.PrefixB) | $($_.Overlap) | $($_.Peered)" }) | Should -Be @(
            'High | vnet-spoke-app 10.20.4.0/22 | vnet-spoke-dup 10.20.4.0/24 | 10.20.4.0 - 10.20.4.255 | True'
            'Medium | London DC 10.20.200.0/22 | vnet-legacy 10.20.200.0/24 | 10.20.200.0 - 10.20.200.255 | False'
        )
        @(Get-AACIPAMReport -AddressPlan $script:f.Plan -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.Category) | $($_.Item) | $($_.Finding)" }) | Should -Be @(
            'High | Overlap | vnet-spoke-app / vnet-spoke-dup | Overlapping peered networks'
            'Medium | Capacity | vnet-spoke-app / snet-web | Subnet nearly full'
            'Medium | Overlap | London DC / vnet-legacy | Overlaps an external range'
            'Medium | Plan | vnet-rogue | Network outside the plan'
            'Medium | Plan | vnet-straddle | Network straddles the plan'
            'Low | Hygiene | vnet-hub-weu | Unattached network interfaces hold addresses'
            'Low | Plan | vnet-rogue | IPAM reservation tag on an unplanned network'
            'Info | Plan | Lab-1 | Unused block'
        )
    }

    It 'finds the next ranges of each size - the best fit and the lowest address - and every free range' {
        $next = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -NextAvailable 24, 22 -View NextAvailable -NoDisplay | Where-Object Block -EQ 'Azure-EU')
        @($next | ForEach-Object { "$($_.Size) | $($_.Candidate) | $($_.Fit) | $($_.FromFreeRange) | $($_.Fits)" }) | Should -Be @(
            '/24 | 10.20.251.0/24 | Best fit | 10.20.251.0/24 | 243'
            '/24 | 10.20.8.0/24 | Lowest address | 10.20.8.0/21 | 243'
            '/22 | 10.20.204.0/22 | Best fit | 10.20.204.0/22 | 60'
            '/22 | 10.20.8.0/22 | Lowest address | 10.20.8.0/21 | 60'
        )
        $free = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -View FreeRange -NoDisplay | Where-Object Block -EQ 'Azure-US')
        @($free.FreeRange) | Should -Be @('10.30.8.0/22', '10.30.12.0/23', '10.30.14.0/24')
        # No room left: a /20 doesn't fit the /20 block that is half used.
        @(Get-AACIPAMReport -AddressPlan $script:f.Plan -NextAvailable 20 -View NextAvailable -NoDisplay | Where-Object Block -EQ 'Azure-US').Fit | Should -Be 'No room'
    }

    It 'checks ranges with -TestCidr - free, taken, or outside every block - and returns the checks' {
        $checks = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -TestCidr '10.20.8.0/22', '10.20.4.128/25', '10.99.0.0/24' -NoDisplay)
        @($checks | ForEach-Object { "$($_.Cidr) | $($_.Status) | $($_.Block) | $($_.ConflictsWith)" }) | Should -Be @(
            '10.20.8.0/22 | Free | Azure-EU | '
            '10.20.4.128/25 | Taken | Azure-EU | vnet-spoke-app (10.20.4.0/22), vnet-spoke-dup (10.20.4.0/24)'
            '10.99.0.0/24 | Free, outside every block |  | '
        )
        $checks[0].PSObject.TypeNames | Should -Contain 'AAC.IpamCidrCheck'
    }

    It 'reads the address plan from a .psd1, a .json and a .csv file alike - and the private ranges when none is given' {
        $psd1 = Join-Path $TestDrive 'plan.psd1'
        Set-Content -LiteralPath $psd1 -Value "@{ Spaces = @(@{ Name = 'Corp'; Blocks = @(@{ Name = 'Azure-EU'; Cidr = '10.20.0.0/16' }, @{ Name = 'Azure-US'; Cidr = '10.30.0.0/20' }) }, @{ Name = 'Lab'; Blocks = @(@{ Name = 'Lab-1'; Cidr = '172.16.0.0/22' }) }); External = @(@{ Name = 'London DC'; Cidr = '10.20.200.0/22' }) }"
        $json = Join-Path $TestDrive 'plan.json'
        $script:f.Plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $json
        $csv = Join-Path $TestDrive 'plan.csv'
        @('Space,Block,Cidr,Kind', 'Corp,Azure-EU,10.20.0.0/16,', 'Corp,Azure-US,10.30.0.0/20,Block', 'Lab,Lab-1,172.16.0.0/22,', ',London DC,10.20.200.0/22,External') | Set-Content -LiteralPath $csv
        $expected = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -NoDisplay | ForEach-Object { "$($_.Space)/$($_.Block) $($_.Allocated) $($_.Next)" })
        foreach ($file in $psd1, $json, $csv) { @(Get-AACIPAMReport -AddressPlan $file -NoDisplay | ForEach-Object { "$($_.Space)/$($_.Block) $($_.Allocated) $($_.Next)" }) | Should -Be $expected -Because (Split-Path -Leaf $file) }
        $default = @(Get-AACIPAMReport -View Space -NoDisplay)
        @($default.Space) | Should -Be @('Private (RFC 1918)', 'Shared (RFC 6598)')
        @(Get-AACIPAMReport -View Network -NoDisplay | Where-Object Status -NE 'Managed').Network | Should -BeNullOrEmpty -Because 'every Contoso network is in a private range'
    }

    It 'says what to fix in an address plan it can''t use' {
        { Get-AACIPAMReport -AddressPlan (Join-Path $TestDrive 'missing.psd1') -NoDisplay } | Should -Throw '*can''t find the address plan*'
        { Get-AACIPAMReport -AddressPlan @{ Spaces = @(@{ Name = 'A'; Blocks = @(@{ Name = 'x'; Cidr = '10.0.0.0/8' }, @{ Name = 'y'; Cidr = '10.1.0.0/16' }) }) } -NoDisplay } | Should -Throw '*overlapping*must not overlap*'
        { Get-AACIPAMReport -AddressPlan @{ Spaces = @(@{ Name = 'A'; Blocks = @(@{ Name = 'x'; Cidr = '10.0.0.300/8' }) }) } -NoDisplay } | Should -Throw '*IPv4 CIDR range*'
        { Get-AACIPAMReport -AddressPlan @{ Spaces = @() } -NoDisplay } | Should -Throw '*no block*'
        { Get-AACIPAMReport -AddressPlan $script:f.Plan -WarningPercent 95 -CriticalPercent 90 -NoDisplay } | Should -Throw '*-WarningPercent*'
    }

    It 'reads only the subscriptions asked for, and lists addresses from their IDs when an owner can''t be read' {
        $null = Get-AACIPAMReport -AddressPlan $script:f.Plan -SubscriptionId 'bbbbbbbb-0000-0000-0000-00000000000b' -NoDisplay
        @($script:graphCalls[0].SubscriptionId) | Should -Be 'bbbbbbbb-0000-0000-0000-00000000000b'
        @($script:graphCalls[1].SubscriptionId) | Should -Be 'bbbbbbbb-0000-0000-0000-00000000000b' -Because 'the details are read where the networks are'
        $script:failQuery = @('nics')
        $ips = @(Get-AACIPAMReport -AddressPlan $script:f.Plan -View IpAddress -NoDisplay -WarningAction SilentlyContinue)
        ($ips | Where-Object Resource -EQ 'nic-orphan').Kind | Should -Be 'Network interface'
        $ips.Count | Should -Be 21 -Because 'the subnets still list every address'
    }

    It 'shows the view at the prompt, and writes the CSV, a tabbed HTML report with hover cards and the plan as a tree' {
        $text = (& $script:capture { Get-AACIPAMReport -AddressPlan $script:f.Plan -NoPaging }).Text
        foreach ($expected in 'IP address management', 'Azure-EU', 'Overlapping peered networks') { $text | Should -BeLike "*$expected*" }
        $csv = Join-Path $TestDrive 'ips.csv'; $html = Join-Path $TestDrive 'ipam.html'
        $null = & $script:capture { Get-AACIPAMReport -AddressPlan $script:f.Plan -View IpAddress -CsvPath $csv -HtmlPath $html -TestCidr '10.20.8.0/22' }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 21
        $model = & $script:modelOf $html
        @($model.tables.id) | Should -Be @('spaces', 'blocks', 'networks', 'subnets', 'ipaddresses', 'overlaps', 'next', 'free', 'checks', 'findings')
        @($model.tabs.name) | Should -Contain 'Free space'
        foreach ($t in $model.tables) { @($t.hover).Count | Should -BeGreaterThan 0 -Because "$($t.id) has a hover card" }
        ($model.tables | Where-Object id -EQ 'blocks').rows[0].FreeRanges | Should -Not -BeNullOrEmpty -Because 'hover fields reach the page even when the column is hidden'
        "$($model.scope.key) | $($model.scope.card) | $(@($model.scope.values) -join ', ')" | Should -Be 'Space | spaces | Corp, Lab'
        $model.tree.root.k[0].n | Should -Be 'Corp'
        $model.tree.root.k[0].k[0].k.n | Should -Contain 'vnet-spoke-app'
        (Get-Content -LiteralPath $html -Raw) | Should -Match 'hovercard'
    }

    It 'opens the HTML report with -Open - in a temporary file when no -HtmlPath is given' {
        $null = & $script:capture { Get-AACIPAMReport -AddressPlan $script:f.Plan -Open -NoDisplay }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 1 -Exactly -ParameterFilter { $Path -like '*AAC-IPAM-*.html' -and (Test-Path -LiteralPath $Path) }
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'ipam.pdf'
        $null = & $script:capture { Get-AACIPAMReport -AddressPlan $script:f.Plan -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
