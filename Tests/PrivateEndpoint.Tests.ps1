<#
    Unit tests for Get-AACPrivateEndpoint: made-up endpoints, zones,
    networks and targets (Fixtures\ContosoPrivateEndpoint.ps1) - connection
    states, orphans, DNS zone groups and links (peered, custom DNS, wrong
    zone, duplicates), public targets - the queries, and the command with
    Resource Graph and the zone group calls faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoPrivateEndpoint.ps1')
    $script:f = Get-AACContosoPrivateEndpoint
    $script:build = { param([hashtable] $ZoneGroup = $script:f.ZoneGroup) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $f; Z = $ZoneGroup } { param($F, $Z) ConvertTo-AACPrivateEndpoint -Read $F.Read -ZoneGroup $Z -SubscriptionName $F.Names } }
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

Describe 'Azure Admin Console - private endpoints' {
    BeforeAll { $script:r = & $script:build }

    It 'rates every connection in scope, the broken ones first' {
        @($script:r.Endpoints | ForEach-Object { "$($_.Status) | $($_.Endpoint) | $($_.ConnectionState) | $($_.ZoneLinked) | $($_.Issues)" }) | Should -Be @(
            'Failed | pe-gone | Disconnected | Peered network | connection Disconnected, target deleted'
            'Failed | pe-sql | Pending | No zone group | connection Pending, no zone group'
            'Failed | pe-unlinked | Approved | No | zone not linked'
            'Warning | pe-kv | Approved | Yes | target public'
            'Warning | pe-wrong | Approved | Yes | wrong zone'
            'Review | pe-custom | Approved | No zone group | custom DNS'
            'Healthy | pe-blob | Approved | Peered network | '
            'Healthy | pe-unread | Approved | Not checked | '
        )
        $script:r.Endpoints[0].PSObject.TypeNames | Should -Contain 'AAC.PrivateEndpoint'
    }

    It 'names the target, the sub-resource, IPs, zones and the zone the service needs' {
        $sql = $script:r.Endpoints | Where-Object Endpoint -EQ 'pe-sql'
        "$($sql.Target) | $($sql.TargetType) | $($sql.GroupId) | $($sql.ExpectedZone) | $($sql.IpAddresses) | $($sql.VirtualNetwork)/$($sql.Subnet)" | Should -Be 'sql-srv | microsoft.sql/servers | sqlServer | privatelink.database.windows.net | 10.1.0.4 | vnet-spoke/snet-pe'
        ($script:r.Endpoints | Where-Object Endpoint -EQ 'pe-wrong').DnsZones | Should -Be 'privatelink.file.core.windows.net'
        ($script:r.Endpoints | Where-Object Endpoint -EQ 'pe-gone').TargetPublicAccess | Should -Be 'Deleted'
        ($script:r.Endpoints | Where-Object Endpoint -EQ 'pe-custom').CustomDns | Should -Be '10.0.0.4'
    }

    It 'lists the findings, each with what to do, and the duplicated zone' {
        @($script:r.Findings | ForEach-Object { "$($_.Severity) | $($_.Category) | $($_.Resource) | $($_.Finding)" }) | Should -Be @(
            'High | Connection | pe-gone | Private endpoint connection Disconnected'
            'High | Connection | pe-sql | Private endpoint connection Pending'
            'High | DNS | pe-unlinked | Private DNS zone not linked to the endpoint''s network'
            'High | Orphaned | pe-gone | Private endpoint to a deleted resource'
            'Medium | DNS | pe-sql | Private endpoint without a DNS zone group'
            'Medium | DNS | pe-wrong | Private DNS zone group uses the wrong zone'
            'Medium | DNS | privatelink.blob.core.windows.net | Private DNS zone defined more than once'
            'Medium | Exposure | pe-kv | Target still open to public networks'
            'Low | DNS | pe-custom | Private endpoint relies on custom DNS'
        )
        ($script:r.Findings | Where-Object Resource -EQ 'pe-sql' | Select-Object -First 1).Remediation | Should -BeLike 'Approve it on the target*'
        $script:r.Findings[0].PSObject.TypeNames | Should -Contain 'AAC.PrivateEndpointFinding'
        $script:r.Notices | Should -Contain "The DNS zone groups of 1 private endpoint(s) couldn't be read: their DNS isn't checked."
        "$($script:r.Stats.Endpoints) $($script:r.Stats.Failed) $($script:r.Stats.Pending) $($script:r.Stats.Orphaned) $($script:r.Stats.Public)" | Should -Be '8 3 1 1 1'
    }

    It 'checks no DNS when the zone groups weren''t read' {
        $r = & $script:build @{}
        @($r.Endpoints | Where-Object ZoneLinked -NE 'Not checked').Count | Should -Be 0
        @($r.Findings | Where-Object { $_.Category -eq 'DNS' -and $_.Finding -notlike '*more than once' }).Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - private endpoint queries' {
    It 'narrows only the endpoints to the resource groups' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACPrivateEndpointQuery -ResourceGroupName 'rg-app' }
        @($q.Keys) | Should -Be @('endpoints', 'zones', 'links', 'vnets', 'targets')
        $q.endpoints | Should -Match ([regex]::Escape("resourceGroup in~ ('rg-app')"))
        $q.zones | Should -Not -Match 'rg-app'
        $q.targets | Should -Match 'privateEndpointConnections'
    }
}

Describe 'Azure Admin Console - Get-AACPrivateEndpoint' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled' }) }; Errors = @{} } }
            @{ Errors = @{}; Rows = @{} + $script:f.Read.Rows }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) {
                $script:uris.Add($u)
                $id = $u -replace '/privateDnsZoneGroups\?.*$', ''
                $groups = $script:f.ZoneGroup[$id]
                $answers[$u] = if ($null -eq $groups) { @{ Status = 403; Error = 'denied'; Body = $null; Items = $null } } else { @{ Status = 200; Error = $null; Body = $null; Items = $groups } }
            }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the zone groups of the endpoints in scope, and filters by name, target type and status' {
        @(Get-AACPrivateEndpoint -NoDisplay).Count | Should -Be 8
        $script:uris.Count | Should -Be 8 -Because 'one call per endpoint in scope'
        @(Get-AACPrivateEndpoint -Name 'pe-k*' -NoDisplay).Endpoint | Should -Be @('pe-kv')
        @(Get-AACPrivateEndpoint -TargetType '*/vaults', '*/servers' -NoDisplay).Endpoint | Should -Be @('pe-sql', 'pe-kv')
        @(Get-AACPrivateEndpoint -Status Failed -NoDisplay).Endpoint | Should -Be @('pe-gone', 'pe-sql', 'pe-unlinked')
    }

    It 'skips the zone groups with -SkipDnsZoneGroup' {
        $null = Get-AACPrivateEndpoint -SkipDnsZoneGroup -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 0
    }

    It 'shows the endpoints at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACPrivateEndpoint -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Private endpoints', '8 private endpoint connection(s): 3 failed, 2 with warnings, 2 healthy', 'Findings (9)', 'Private endpoint connections (8)', 'pe-unlinked') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the connections to CSV and an HTML report with the findings' {
        $csv = Join-Path $TestDrive 'pe.csv'
        $html = Join-Path $TestDrive 'pe.html'
        $null = & $script:capture { Get-AACPrivateEndpoint -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Endpoint | Should -Be 'pe-gone'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('findings', 'endpoints')
        ($model.tiles | Where-Object label -EQ 'pending approval').filters.ConnectionState | Should -Be 'Pending'
    }
}
