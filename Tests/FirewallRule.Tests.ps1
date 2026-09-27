<#
    Unit tests for Get-AACFirewallRule. Resource Graph responses are hand-built
    JSON shaped like the rows the cmdlet's queries project, and every Azure
    call is mocked, so no network call or active Connect-AAC session is needed.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

Describe 'Azure Admin Console - Get-AACFirewallRule' {
    BeforeAll {
        # Runs a script block with the Spectre console swapped for one that
        # writes plain text into a buffer, and returns that text.
        $script:renderToText = {
            param([scriptblock] $Render, [switch] $Ascii)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            # No CI detection: on GitHub Actions (or Azure Pipelines...) Spectre's
            # default enrichers would switch on ANSI colour and Unicode, overriding
            # what this console is set to - and the text checks would fail.
            $settings.Enrichment.UseDefaultEnrichers = $false
            $capture = [Spectre.Console.AnsiConsole]::Create($settings)
            $capture.Profile.Width = 180
            # -Ascii: a console that isn't UTF-8 (code page 437, 850...).
            $capture.Profile.Capabilities.Unicode = -not $Ascii
            try {
                [Spectre.Console.AnsiConsole]::Console = $capture
                & $Render
            }
            finally {
                [Spectre.Console.AnsiConsole]::Console = $real
            }
            $buffer.ToString()
        }
    }

    BeforeEach {
        $sub = '11111111-1111-1111-1111-111111111111'
        $hub = "/subscriptions/$sub/resourcegroups/rg-net/providers/microsoft.network/firewallpolicies/fwpol-hub"
        $base = "/subscriptions/$sub/resourcegroups/rg-net/providers/microsoft.network/firewallpolicies/fwpol-base"
        $ipg = "/subscriptions/$sub/resourcegroups/rg-net/providers/microsoft.network/ipgroups/ipg-spokes"
        $rcg = "$hub/ruleCollectionGroups/rcg-platform"

        $rows = @"
[
  {"subscriptionId":"$sub","resourceGroup":"rg-net","location":"uksouth","firewallPolicyId":"$hub","ruleCollectionGroupId":"$rcg",
   "ruleCollectionGroup":"rcg-platform","ruleCollectionGroupPriority":100,"ruleCollection":"Allow-Web","ruleCollectionPriority":200,
   "ruleCollectionType":"FirewallPolicyFilterRuleCollection","action":"Allow","ruleIndex":0,
   "rule":{"name":"web-out","ruleType":"ApplicationRule","sourceIpGroups":["$ipg"],"targetFqdns":["*.contoso.com"],
           "protocols":[{"protocolType":"Https","port":443}],"terminateTLS":false}},
  {"subscriptionId":"$sub","resourceGroup":"rg-net","location":"uksouth","firewallPolicyId":"$hub","ruleCollectionGroupId":"$rcg",
   "ruleCollectionGroup":"rcg-platform","ruleCollectionGroupPriority":100,"ruleCollection":"Allow-Web","ruleCollectionPriority":200,
   "ruleCollectionType":"FirewallPolicyFilterRuleCollection","action":"Allow","ruleIndex":1,
   "rule":{"name":"any-dns","ruleType":"NetworkRule","sourceAddresses":["*"],"destinationAddresses":["10.0.0.4"],
           "ipProtocols":["UDP"],"destinationPorts":["53"]}},
  {"subscriptionId":"$sub","resourceGroup":"rg-net","location":"uksouth","firewallPolicyId":"$hub","ruleCollectionGroupId":"$rcg",
   "ruleCollectionGroup":"rcg-platform","ruleCollectionGroupPriority":100,"ruleCollection":"Block-Legacy","ruleCollectionPriority":300,
   "ruleCollectionType":"FirewallPolicyFilterRuleCollection","action":"Deny","ruleIndex":0,
   "rule":{"name":"no-telnet","ruleType":"NetworkRule","sourceAddresses":["*"],"destinationAddresses":["*"],
           "ipProtocols":["TCP"],"destinationPorts":["23"],"description":"Legacy protocols"}},
  {"subscriptionId":"$sub","resourceGroup":"rg-net","location":"uksouth","firewallPolicyId":"$hub","ruleCollectionGroupId":"$rcg",
   "ruleCollectionGroup":"rcg-platform","ruleCollectionGroupPriority":100,"ruleCollection":"Inbound-NAT","ruleCollectionPriority":100,
   "ruleCollectionType":"FirewallPolicyNatRuleCollection","action":"DNAT","ruleIndex":0,
   "rule":{"name":"rdp-jump","ruleType":"NatRule","sourceAddresses":["203.0.113.10"],"destinationAddresses":["20.50.1.1"],
           "ipProtocols":["TCP"],"destinationPorts":["3389"],"translatedAddress":"10.0.1.4","translatedPort":"3389"}},
  {"subscriptionId":"$sub","resourceGroup":"rg-net","location":"uksouth","firewallPolicyId":"$base","ruleCollectionGroupId":"$base/ruleCollectionGroups/rcg-base",
   "ruleCollectionGroup":"rcg-base","ruleCollectionGroupPriority":100,"ruleCollection":"Deny-All-Out","ruleCollectionPriority":65000,
   "ruleCollectionType":"FirewallPolicyFilterRuleCollection","action":"Deny","ruleIndex":0,
   "rule":{"name":"deny-internet","ruleType":"NetworkRule","sourceAddresses":["10.0.0.0/8"],"destinationAddresses":["*"],
           "ipProtocols":["Any"],"destinationPorts":["*"]}}
]
"@ | ConvertFrom-Json
        $policies = @"
[
  {"id":"$hub","name":"fwpol-hub","basePolicyId":"$base","firewalls":[{"id":"/subscriptions/$sub/resourceGroups/rg-net/providers/Microsoft.Network/azureFirewalls/afw-hub"}],"tier":"Premium"},
  {"id":"$base","name":"fwpol-base","basePolicyId":"","firewalls":[],"tier":"Premium"}
]
"@ | ConvertFrom-Json
        $ipGroups = "[{`"id`":`"$ipg`",`"name`":`"ipg-spokes`",`"addresses`":[`"10.1.0.0/16`",`"10.2.0.0/16`"]}]" | ConvertFrom-Json
        $subscriptions = "[{`"subscriptionId`":`"$sub`",`"name`":`"sub-connectivity`"}]" | ConvertFrom-Json

        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Write-AACMarkup -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'rulecollectiongroups' } -MockWith { $rows }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match "firewallpolicies'" } -MockWith { $policies }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'ipgroups' } -MockWith { $ipGroups }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match '^resourcecontainers' } -MockWith { $subscriptions }.GetNewClosure()
    }

    It 'returns one object per rule in portal order, with IP Groups, base policy and firewalls resolved' {
        $rules = @(Get-AACFirewallRule -NoDisplay)

        $rules.Count | Should -Be 5
        # fwpol-base sorts before fwpol-hub; in the hub, collection priority 100 (DNAT) comes first.
        ($rules | ForEach-Object RuleName) | Should -Be @('deny-internet', 'rdp-jump', 'web-out', 'any-dns', 'no-telnet')

        $web = $rules | Where-Object RuleName -eq 'web-out'
        $web.FirewallPolicy | Should -BeExactly 'fwpol-hub'
        $web.BasePolicy | Should -BeExactly 'fwpol-base'
        $web.Firewalls | Should -BeExactly 'afw-hub'
        $web.SubscriptionName | Should -BeExactly 'sub-connectivity'
        $web.SourceIpGroups | Should -BeExactly 'ipg-spokes'
        $web.SourceIpGroupAddresses | Should -BeExactly 'ipg-spokes: 10.1.0.0/16, 10.2.0.0/16'
        $web.Protocols | Should -BeExactly 'Https:443'

        $nat = $rules | Where-Object RuleName -eq 'rdp-jump'
        $nat.RuleCollectionType | Should -BeExactly 'DNAT'
        $nat.TranslatedAddress | Should -BeExactly '10.0.1.4'
    }

    It 'filters by policy name' {
        @(Get-AACFirewallRule -FirewallPolicyName 'fwpol-base' -NoDisplay).RuleName | Should -Be @('deny-internet')
    }

    Context 'view or objects' {
        BeforeEach {
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACFirewallRuleView -MockWith { }
        }

        It 'shows the view and returns nothing when run on its own' {
            @(Get-AACFirewallRule -NoPaging).Count | Should -Be 0
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACFirewallRuleView -Times 1 -Exactly
        }

        It 'returns the objects without the view when piped onward' {
            @(Get-AACFirewallRule | ForEach-Object { $_ }).Count | Should -Be 5
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACFirewallRuleView -Times 0 -Exactly
        }

        It 'shows the view and returns the objects with -PassThru' {
            @(Get-AACFirewallRule -PassThru -NoPaging).Count | Should -Be 5
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACFirewallRuleView -Times 1 -Exactly
        }

        It 'writes the CSV instead of showing the view' {
            $csv = Join-Path -Path $TestDrive -ChildPath 'out/rules.csv'
            @(Get-AACFirewallRule -CsvPath $csv -NoPaging).Count | Should -Be 0
            $imported = @(Import-Csv -LiteralPath $csv)
            $imported.Count | Should -Be 5
            $imported[0].PSObject.Properties.Name | Should -Contain 'SourceIpGroupAddresses'
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACFirewallRuleView -Times 0 -Exactly
        }

        It 'writes an interactive HTML report, flagging Allow rules open to any address' {
            $html = Join-Path -Path $TestDrive -ChildPath 'out/rules.html'
            @(Get-AACFirewallRule -HtmlPath $html -PassThru).Count | Should -Be 5 -Because '-PassThru still returns the objects'
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACFirewallRuleView -Times 0 -Exactly
            $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
            $table = $model.tables[0]
            $table.rows.Count | Should -Be 5
            @($table.columns.key) | Should -Contain 'Exposure'
            @($model.tiles.label) | Should -Contain 'allow'
            $table.rows | ForEach-Object { if ($_.Action -eq 'Allow' -and $_.Sources -match '(^|, )\*($|,|;)') { $_.Exposure | Should -Be 'Open to any' } }
        }
    }

    It 'renders tiles, the policies table and one colour-coded table per rule collection' {
        $text = InModuleScope 'Azure.Admin.Console' {
            $rules = @(Get-AACFirewallRule -NoDisplay)
            & $args[0] { Show-AACFirewallRuleView -Rule $rules -Scope ([ordered]@{ Subscriptions = 'all' }) }
        } -ArgumentList $script:renderToText

        foreach ($expected in 'Azure Firewall', 'Firewall policies', 'fwpol-hub', 'base: fwpol-base', 'firewalls: afw-hub',
            ' ALLOW ', ' DENY ', ' DNAT ', 'Allow-Web', 'Block-Legacy', 'Inbound-NAT', 'Deny-All-Out',
            'ipg-spokes', '10.1.0.0/16, 10.2.0.0/16', 'fqdn *.contoso.com', '* (any)', '→ 10.0.1.4:3389', 'TLS inspection off', 'Legacy protocols') {
            $text | Should -BeLike "*$expected*"
        }
        # '*' is only called out on Allow rules: the Deny rule's '*' destination stays plain.
        ([regex]::Matches($text, [regex]::Escape('* (any)'))).Count | Should -Be 1
        $text.IndexOf('Inbound-NAT') | Should -BeLessThan $text.IndexOf('Allow-Web') -Because 'collections are in priority order'
    }

    Context 'search' {
        It 'finds rules whose source covers an address: CIDR, IP Group and *' {
            # 10.1.2.3 is in 10.0.0.0/8 (deny-internet), in ipg-spokes (web-out) and in '*' (any-dns,
            # no-telnet) - but not 203.0.113.10 (rdp-jump).
            @(Get-AACFirewallRule -SourceAddress 10.1.2.3 -NoDisplay).RuleName | Sort-Object |
                Should -Be @('any-dns', 'deny-internet', 'no-telnet', 'web-out')
        }

        It 'answers "can this source reach that destination on this port and protocol?"' {
            @(Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP -NoDisplay).RuleName |
                Should -Be @('deny-internet', 'any-dns') -Because 'deny-internet (fwpol-base, Any/*) and any-dns (UDP 53) both cover it, in portal order'
        }

        It 'matches ranges by overlap and ports by range' {
            @(Get-AACFirewallRule -DestinationAddress 20.50.1.0/24 -NoDisplay).RuleName | Should -Contain 'rdp-jump'
            @(Get-AACFirewallRule -Port 3000-3500 -Action DNAT -NoDisplay).RuleName | Should -Be @('rdp-jump')
            # deny-internet is Any protocol on every port, so it covers HTTPS 443 too.
            @(Get-AACFirewallRule -Port 443 -Protocol Https -NoDisplay).RuleName | Should -Be @('deny-internet', 'web-out')
        }

        It 'finds application rules by host name, including wildcard FQDNs' {
            @(Get-AACFirewallRule -Fqdn www.contoso.com -NoDisplay).RuleName | Should -Be @('web-out')
            @(Get-AACFirewallRule -Fqdn www.fabrikam.com -NoDisplay) | Should -BeNullOrEmpty
        }

        It 'filters by action and rule name, and shows the filters in the view scope' {
            @(Get-AACFirewallRule -Action Deny -RuleName 'no-*' -NoDisplay).RuleName | Should -Be @('no-telnet')
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACFirewallRuleView -MockWith { $script:shownScope = $Scope }
            $null = Get-AACFirewallRule -SourceAddress 10.1.2.3 -Port 53 -NoPaging
            $script:shownScope['Source'] | Should -BeExactly '10.1.2.3'
            $script:shownScope['Port'] | Should -BeExactly '53'
        }
    }

    It 'draws only characters a legacy console (code page 437/850) can show' {
        $text = InModuleScope 'Azure.Admin.Console' {
            $rules = @(Get-AACFirewallRule -NoDisplay)
            & $args[0] { Show-AACFirewallRuleView -Rule $rules -Scope ([ordered]@{ Subscriptions = 'all' }) } -Ascii
        } -ArgumentList $script:renderToText

        $text | Should -BeLike '*-> 10.0.1.4:3389*' -Because 'the DNAT arrow becomes ->'
        $text | Should -BeLike '*rcg-platform - 100 > Allow-Web*'
        # Every character must exist in the legacy code pages Windows consoles
        # use (437, 850) - anything else would be printed as '?'.
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ } | ForEach-Object { 'U+{0:X4}' -f [int]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path -Path $TestDrive -ChildPath 'rules.pdf'
        $null = Get-AACFirewallRule -PdfPath $pdf -NoDisplay
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
