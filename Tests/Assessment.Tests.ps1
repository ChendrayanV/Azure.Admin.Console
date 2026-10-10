<#
    Unit tests for Invoke-AACAssessment: the resource catalog and its
    queries, the assessment of a made-up Contoso tenant
    (Fixtures\ContosoAssessment.ps1) - inventory sheets, overview, Advisor,
    retirements, Defender, Policy, outages, quotas, reservations, cost -
    the organization diagram, the app-only sign-ins (service principal and
    managed identity) and the command end to end with Resource Graph,
    Resource Manager and Cost Management mocked: scope, options, the
    reports, the upload and the view.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoAssessment.ps1')
    $script:f = Get-AACContosoAssessment
    $script:inModule = { param([scriptblock] $Script, [hashtable] $Parameters = @{}) InModuleScope 'Azure.Admin.Console' -Parameters $Parameters $Script }
    # The fixture's sheets as their queries return them (c0, r1, ...).
    $script:catalog = & $script:inModule { Get-AACAssessmentCatalog }
    $script:compiled = @{}
    $script:queryRows = @{}
    foreach ($sheet in $script:catalog) {
        $script:compiled[$sheet.Sheet] = & $script:inModule { param($Sheet) Get-AACAssessmentQuery -Sheet $Sheet } @{ Sheet = $sheet }
        if ($script:f.Sheets.Contains($sheet.Sheet)) { $script:queryRows[$sheet.Sheet] = @(ConvertTo-AACAssessmentFixtureRow -Compiled $script:compiled[$sheet.Sheet] -Rows $script:f.Sheets[$sheet.Sheet]) }
    }
    $script:assess = {
        param([hashtable] $With = @{})
        $p = @{
            Catalog = $script:catalog; Compiled = $script:compiled; SheetRow = $script:queryRows; Resource = $script:f.Resources; Subscription = $script:f.Subscriptions
            ResourceGroup = $script:f.Groups; ManagementGroup = $script:f.ManagementGroups; Advisor = $script:f.Advisor; Security = $script:f.Security; SecureScore = $script:f.SecureScores
            Policy = $script:f.Policy; SupportTicket = $script:f.SupportTickets; Arm = $script:f.Arm; Cost = $script:f.Cost; TenantId = 'tenant-1'; TenantName = 'Contoso'
            IncludeTag = $true; AdvisorRead = $true; SecurityRead = $true; PolicyRead = $true
        }
        foreach ($key in $With.Keys) { $p[$key] = $With[$key] }
        & $script:inModule { param($P) ConvertTo-AACAssessment @P } @{ P = $p }
    }
    $script:a = & $script:assess
    $script:sheet = { param([string] $Name, $From = $script:a) @($From.Sheets | Where-Object { $_.Sheet -eq $Name }) | Select-Object -First 1 }
    $script:rowOf = { param([string] $Sheet, [string] $Name) @((& $script:sheet $Sheet).Rows | Where-Object { $_.Name -eq $Name -or $_.Resource -eq $Name }) | Select-Object -First 1 }
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
    # A JWT with these claims (unsigned - only read for display).
    $script:jwt = {
        param([hashtable] $Claims)
        $encode = { param([string] $Text) [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
        "$(& $encode '{"alg":"none"}').$(& $encode ($Claims | ConvertTo-Json -Compress)).sig"
    }
}

Describe 'Azure Admin Console - assessment catalog and queries' {
    It 'describes each sheet once, with a category, a type, columns and key columns' {
        $names = @($script:catalog | ForEach-Object { $_.Sheet })
        $names.Count | Should -BeGreaterThan 90
        @($names | Group-Object | Where-Object Count -GT 1).Name | Should -BeNullOrEmpty
        foreach ($sheet in $script:catalog) {
            $sheet.Category | Should -BeIn @('Compute', 'Hybrid', 'Containers', 'Databases', 'Analytics', 'AI', 'Integration', 'IoT', 'Management', 'Monitoring', 'Networking', 'Security', 'Storage', 'Web')
            @($sheet.Type).Count | Should -BeGreaterThan 0
            $sheet.Columns.Count | Should -BeGreaterThan 0
            foreach ($key in $sheet.Key) { $sheet.Columns.Keys | Should -Contain $key -Because "$($sheet.Sheet)'s key column $key" }
            foreach ($spec in $sheet.Columns.Values) { [string]$spec | Should -Match '^(kql|int|num|gb|len|join|leaf|vnet|subnet|date|x):|^@(names|leafs|subnets|pick|pickleaf|sum|keys):|^[A-Za-z][A-Za-z0-9_.\[\]]*$' }
        }
    }

    It 'builds a projection per sheet - KQL values as c0.., arrays as r.., and nothing for values filled in later' {
        $vm = $script:compiled['Virtual machines']
        $vm.Query | Should -BeLike "resources | where type =~ 'microsoft.compute/virtualmachines' | extend nicId = *| join kind=leftouter *| project id, name, resourceGroup, subscriptionId, location, c0 = tostring(properties.hardwareProfile.vmSize), *"
        $vm.Columns['Size'].Column | Should -Be 'c0'
        $vm.Columns['vCPUs'].Column | Should -BeNullOrEmpty
        $vm.Columns['Data disks (GB)'].Column | Should -Match '^r\d+$'
        $vm.Query | Should -Match "r\d+ = properties.storageProfile.dataDisks"
        $vm.Query | Should -Match "extract\(@'\(\?i\)/virtualnetworks/\(\[\^/\]\+\)', 1, tostring\(nicSubnet\)\)"
        $script:compiled['Subnets'].Query | Should -Match '\| mv-expand subnet = properties.subnets \| project'
        $script:compiled['Backup items'].Query | Should -BeLike 'recoveryservicesresources | where type =~*'
        $script:compiled['Event Grid'].Query | Should -BeLike "resources | where type in~ ('microsoft.eventgrid/topics', 'microsoft.eventgrid/domains', 'microsoft.eventgrid/namespaces')*"
    }

    It 'writes properties named like KQL keywords in brackets - pool.count is a ParserFailure in Resource Graph' {
        $script:compiled['AKS node pools'].Query | Should -Match "toint\(pool\['count'\]\)"
        $script:compiled['Backup policies'].Query | Should -Match "retentionDuration\['count'\]"
        $script:compiled['AKS node pools'].Query | Should -Match "'microsoft\.containerservice/managedclusters'" -Because 'quoted text is left alone'
        foreach ($name in $script:compiled.Keys) {
            $outsideQuotes = [regex]::Replace($script:compiled[$name].Query, "@?'(?:[^'\\]|\\.)*'|@?`"(?:[^`"\\]|\\.)*`"", "''")
            $outsideQuotes | Should -Not -Match '[A-Za-z0-9_\]]\.(count|type|kind|title)\b' -Because "$name's query"
        }
    }

    It 'filters by resource group and tag (any case), and adds the tags when asked' {
        $query = & $script:inModule { param($Sheet) (Get-AACAssessmentQuery -Sheet $Sheet -ResourceGroupName 'rg-app', "rg'x" -TagKey 'Env' -TagValue 'Prod' -IncludeTag).Query } @{ Sheet = @($script:catalog | Where-Object Sheet -EQ 'Key vaults')[0] }
        $query | Should -BeLike "*| where resourceGroup in~ ('rg-app', 'rg\'x')*"
        $query.Contains("| mv-expand aacTag | extend aacTagKey = tostring(bag_keys(aacTag)[0]) | where aacTagKey =~ 'Env' and tostring(aacTag[aacTagKey]) =~ 'Prod' | project-away aacTag, aacTagKey") | Should -BeTrue
        $query | Should -BeLike '*, tags'
        & $script:inModule { Get-AACAssessmentQuery -Filter } | Should -BeNullOrEmpty
        (& $script:inModule { Get-AACAssessmentQuery -Filter -TagValue 'Prod' }).Contains("| where tostring(aacTag[aacTagKey]) =~ 'Prod' |") | Should -BeTrue
    }

    It 'reads the estate, Advisor (retirements only with -SkipAdvisor), Defender, Policy and the diagram' {
        $estate = & $script:inModule { Get-AACAssessmentExtraQuery -Stage Estate -SecurityCenter }
        @($estate.Keys) | Should -Be @('types', 'resources', 'groups', 'advisor', 'security', 'secureScores', 'policy', 'policyByGroup', 'policyResources', 'supportTickets')
        $estate.policy | Should -BeLike '*| summarize nonCompliant = countif(*| extend id = strcat(assignmentId, *'
        $estate.policyByGroup | Should -BeLike '*by resourceId, subscriptionId, resourceGroup | summarize resources = count(), nonCompliant = countif(nc > 0)*| extend id = *'
        $estate.policyResources | Should -BeLike "*complianceState) =~ 'NonCompliant'*reasonCode = tostring(properties.complianceReasonCode)*| take 5000*description = tostring(properties.description)*"
        @((& $script:inModule { Get-AACAssessmentExtraQuery -Stage Estate -SkipPolicy }).Keys) | Should -Not -Contain 'policyResources'
        (& $script:inModule { Get-AACAssessmentExtraQuery -Stage Estate -SkipAdvisor -SkipPolicy }).advisor | Should -BeLike "*| where subCategory == 'ServiceUpgradeAndRetirement' |*"
        @((& $script:inModule { Get-AACAssessmentExtraQuery -Stage Estate -SkipPolicy }).Keys) | Should -Not -Contain 'policy'
        (& $script:inModule { Get-AACAssessmentExtraQuery -Stage Scope }).managementGroups.Tenant | Should -BeTrue
        (& $script:inModule { Get-AACAssessmentExtraQuery -Stage Diagram }).diagram | Should -BeLike "resources | where type in~ ('microsoft.network/virtualnetworks', *"
        (& $script:inModule { Get-AACAssessmentExtraQuery -Stage Diagram -FullEnvironment }).diagram | Should -BeLike 'resources | where isnotempty(resourceGroup) | project*'
    }
}

Describe 'Azure Admin Console - the assessment' {
    It 'fills each inventory sheet from its query, by label, with Yes/No, dates and sums' {
        $vm = & $script:rowOf 'Virtual machines' 'vm-web-1'
        "$($vm.Subscription)/$($vm.'Resource group')/$($vm.Size)/$($vm.'Power state')" | Should -Be 'sub-landingzone-app/rg-app/Standard_D2s_v5/VM running'
        $vm.'Data disks (GB)' | Should -Be 384
        $vm.'Boot diagnostics' | Should -Be 'Yes'
        $vm.Created | Should -Be '2024-03-01 10:15'
        (& $script:rowOf 'Virtual machines' 'vm-web-2').'Boot diagnostics' | Should -Be 'No'
        (& $script:rowOf 'Storage accounts' 'stcontosoapp').'Minimum TLS' | Should -Be 'TLS1_0'
        (& $script:rowOf 'Virtual networks' 'vnet-hub-weu').'Subnet names' | Should -Be 'GatewaySubnet, snet-dns'
    }

    It 'adds what is filled in after the query: VM sizes from the Compute SKUs, subnets'' free IPs' {
        $vm = & $script:rowOf 'Virtual machines' 'vm-web-1'
        "$($vm.vCPUs)/$($vm.'Memory (GB)')" | Should -Be '2/8'
        (& $script:rowOf 'Virtual machines' 'vm-web-2').vCPUs | Should -BeNullOrEmpty -Because 'its size is not in the SKUs read'
        $subnets = @((& $script:sheet 'Subnets').Rows)
        "$($subnets[0].Subnet) $($subnets[0].'Usable IPs') $($subnets[0].'Available IPs')" | Should -Be 'GatewaySubnet 27 25'
        $subnets[0].'Virtual network' | Should -Be 'vnet-hub-weu'
    }

    It 'adds the retirement, the Advisor count, the cost and the tags to every inventory row' {
        (& $script:rowOf 'Public IP addresses' 'pip-web-2').Retirement | Should -Be 'Basic SKU public IP addresses (2025-09-30)'
        $vm = & $script:rowOf 'Virtual machines' 'vm-web-1'
        "$($vm.Advisor)/$($vm.'Cost (month to date)')/$($vm.'Cost (last month)')/$($vm.Currency)" | Should -Be '1/41.25/120.5/EUR'
        (& $script:sheet 'Virtual machines').Columns | Should -Contain 'Tags'
        (& $script:sheet 'Virtual machines' (& $script:assess @{ IncludeTag = $false; Cost = $null; AdvisorRead = $false })).Columns | Should -Not -Contain 'Tags'
    }

    It 'leaves out the sheets with no rows, and keeps one that could not be read, with why' {
        (& $script:sheet 'AKS clusters') | Should -BeNullOrEmpty
        $failed = & $script:assess @{ SheetError = @{ 'Key vaults' = 'Forbidden' } }
        (& $script:sheet 'Key vaults' $failed).Error | Should -Be 'Forbidden'
        $failed.Notices | Should -Contain "Key vaults couldn't be read: Forbidden"
        $failed.Stats.FailedSheets | Should -Be 1
    }

    It 'gives the overview: subscriptions with their management groups, resource groups, types and every resource' {
        $sub = @((& $script:sheet 'Subscriptions').Rows | Where-Object Subscription -EQ 'sub-landingzone-app')[0]
        "$($sub.'Management groups')|$($sub.'Resource groups')|$($sub.Resources)|$($sub.Advisor)|$($sub.'Advisor (High)')|$($sub.'Secure score (%)')|$($sub.'Cost (month to date)')" | Should -Be 'Tenant Root Group > Landing zones|2|7|2|1|70|41.25'
        $empty = @((& $script:sheet 'Resource groups').Rows | Where-Object 'Resource group' -EQ 'rg-empty')[0]
        "$($empty.Resources) $($empty.Empty)" | Should -Be '0 Yes'
        $type = @((& $script:sheet 'Resource types').Rows | Where-Object 'Resource type' -EQ 'microsoft.logic/workflows')[0]
        "$($type.Category)|$($type.Sheet)" | Should -Be 'Integration|' -Because 'logic apps have no sheet, but a category from their provider'
        @((& $script:sheet 'Resource types').Rows | Where-Object 'Resource type' -EQ 'microsoft.compute/virtualmachines')[0].Sheet | Should -Be 'Virtual machines'
        $all = @((& $script:sheet 'All resources').Rows)
        $all.Count | Should -Be 10
        @($all | Where-Object Tagged -EQ 'No').Count | Should -Be 4
        (@($all | Where-Object Name -EQ 'pip-web-2')[0]).Retirement | Should -BeLike 'Basic SKU public IP*'
    }

    It 'lists Advisor recommendations (most impact first), the Advisor score and the retirements' {
        $advisor = @((& $script:sheet 'Advisor recommendations').Rows)
        @($advisor.Impact) | Should -Be @('High', 'Low') -Because 'the retirement has its own sheet'
        "$($advisor[0].Resource) $($advisor[0].'Annual savings') $($advisor[0].Currency)" | Should -Be 'vm-web-1 412.5 EUR'
        $retirement = @((& $script:sheet 'Retirements').Rows)[0]
        "$($retirement.'Retirement date')|$($retirement.Retiring)|$($retirement.Resource)" | Should -Be '2025-09-30|Basic SKU public IP addresses|pip-web-2'
        $score = @((& $script:sheet 'Advisor score').Rows)[0]
        "$($score.Category) $($score.'Score (%)') $($score.'Potential increase')" | Should -Be 'Cost 62 12'
    }

    It 'lists Defender recommendations, secure scores and policy compliance' {
        $security = @((& $script:sheet 'Security recommendations').Rows)[0]
        "$($security.Severity)|$($security.Resource)|$($security.'Resource type')" | Should -Be 'High|stcontosoapp|microsoft.storage/storageaccounts'
        @((& $script:sheet 'Secure score').Rows)[0].'Secure score (%)' | Should -Be 70 -Because 'the lowest score first'
        $policy = @((& $script:sheet 'Policy compliance').Rows)[0]
        "$($policy.Assignment)|$($policy.Effect)|$($policy.'Non-compliant')|$($policy.'Compliance (%)')" | Should -Be 'Allowed locations|deny|3|70'
    }

    It 'lists outages once across subscriptions (service issues only), quotas in use, reservations and tickets' {
        $outages = @((& $script:sheet 'Outages').Rows)
        $outages.Count | Should -Be 1
        "$($outages[0].'Tracking ID')|$($outages[0].Subscriptions)|$($outages[0].Services)|$($outages[0].Regions)|$($outages[0].Summary)" | Should -Be 'TRK-1ZZ|sub-connectivity, sub-landingzone-app|Virtual Machines|West Europe|Some VMs restarted .'
        $quotas = @((& $script:sheet 'Quotas').Rows)
        "$($quotas.Count) $($quotas[0].Quota) $($quotas[0].'Used (%)')" | Should -Be '1 Standard DSv5 Family vCPUs 80'
        @((& $script:sheet 'Reservation recommendations').Rows)[0].'Net savings' | Should -Be 420
        @((& $script:sheet 'Support tickets').Rows)[0].Title | Should -Be 'VM cannot start'
    }

    It 'counts it all, and builds the tenant tree for the report' {
        $s = $script:a.Stats
        "$($s.Subscriptions)/$($s.ResourceGroups)/$($s.EmptyResourceGroups)/$($s.Resources)/$($s.ResourceTypes)/$($s.Orphans)/$($s.AdvisorHigh)/$($s.Retirements)/$($s.SecurityHigh)/$($s.PolicyNonCompliant)/$($s.Outages)" | Should -Be '2/3/1/10/8/2/1/1/1/3/1'
        "$($s.CostMonthToDate) $($s.CostLastMonth) $($s.Currency)" | Should -Be '42.35 120.5 EUR'
        $root = $script:a.Tree
        $root.n | Should -Be 'Contoso'
        $tenantRoot = $root.k[0]
        "$($tenantRoot.l) $($tenantRoot.n)" | Should -Be 'm Tenant Root Group'
        @($tenantRoot.k | ForEach-Object { $_.n }) | Should -Be @('Landing zones', 'Platform', 'Sandbox')
        $app = $tenantRoot.k[0].k[0]
        "$($app.l) $($app.n) $($app.c[0][0])" | Should -Be 's sub-landingzone-app 7'
        @($app.k | Where-Object { $_.x }).n | Should -Be 'rg-empty'
    }

    It 'assesses an empty estate without failing' {
        $empty = & $script:inModule { ConvertTo-AACAssessment -Catalog @() }
        $empty.Stats.Resources | Should -Be 0
        @($empty.Sheets | Where-Object { @($_.Rows).Count }).Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - the assessment''s governance sheets' {
    BeforeAll {
        $sub = '22222222-2222-2222-2222-222222222222'
        $rid = { param([string] $Type, [string] $Name) "/subscriptions/$sub/resourceGroups/rg-app/providers/$Type/$Name" }
        $set = '/providers/microsoft.authorization/policysetdefinitions/cis'
        $asg = '/subscriptions/22222222-2222-2222-2222-222222222222/providers/microsoft.authorization/policyassignments/cis'
        $state = { param([string] $Definition, [string] $Effect, [int] $Bad, [int] $Good, [int] $Other = 0) @{ assignmentId = $asg; assignmentName = 'cis'; assignment = 'CIS benchmark'; assignmentScope = "/subscriptions/$sub"; definitionId = "/providers/microsoft.authorization/policydefinitions/$Definition"; policy = $Definition; setId = $set; policySet = 'CIS Microsoft Azure Foundations Benchmark'; effect = $Effect; nonCompliant = $Bad; compliant = $Good; exempt = 0; other = $Other; subscriptions = 1 } }
        $member = { param([string] $Definition, [string] $Effect, [string] $Groups) [pscustomobject]@{ AssignmentId = $asg; AssignmentDisplayName = 'CIS benchmark'; PolicyId = "/providers/microsoft.authorization/policydefinitions/$Definition"; ReferenceId = $Definition; PolicyDisplayName = $Definition; PolicySetDisplayName = 'CIS Microsoft Azure Foundations Benchmark'; Effect = $Effect; Category = 'Storage'; PolicyType = 'BuiltIn'; ResourceType = 'Microsoft.Storage/storageAccounts'; Groups = $Groups; ScopeType = 'Subscription'; ScopeName = 'sub-app' } }
        $script:input = @{
            Policy           = @((& $state 'https' 'audit' 2 3), (& $state 'tls' 'audit' 0 5), (& $state 'mfa-attest' 'manual' 0 0 1))
            AssignedPolicy   = @{
                Assignments = @([pscustomobject]@{ AssignmentId = $asg; AssignmentDisplayName = 'CIS benchmark'; DefinitionDisplayName = 'CIS Microsoft Azure Foundations Benchmark'; DefinitionType = 'PolicySet'; EnforcementMode = 'Default'; ScopeType = 'Subscription'; ScopeName = 'sub-app'; Inherited = $false; Members = 4; Category = 'Regulatory Compliance'; PolicyType = 'BuiltIn'; ResourceType = ''; NotScopes = '' })
                # One per parameter: https comes twice.
                Members     = @((& $member 'https' 'Audit' 'CIS_3.1'), (& $member 'https' 'Audit' 'CIS_3.1'), (& $member 'tls' 'Audit' 'CIS_3.1, CIS_3.15'), (& $member 'mfa-attest' 'Manual' 'CIS_1.1'), (& $member 'old' 'Disabled' 'CIS_9.9'), (& $member 'unseen' 'Audit' ''))
            }
            PolicyResource   = @(@{ resourceId = (& $rid 'Microsoft.Storage/storageAccounts' 'stapp').ToLowerInvariant(); subscriptionId = $sub; resourceGroup = 'rg-app'; resourceType = 'Microsoft.Storage/storageAccounts'; assignmentId = $asg; assignment = 'CIS benchmark'; definitionId = '/providers/microsoft.authorization/policydefinitions/https'; policy = 'Secure transfer to storage accounts should be enabled'; description = 'Use HTTPS only.'; effect = 'deployifnotexists'; reasonCode = 'Type:NotFound'; groups = 'CIS_3.1'; policySet = 'CIS Microsoft Azure Foundations Benchmark' })
            PolicyByGroup    = @(@{ subscriptionId = $sub; resourceGroup = ''; resources = 2; nonCompliant = 0; compliant = 2; exempt = 0; nonCompliantStates = 0 })
            PSRuleResult     = @(
                [pscustomobject]@{ Outcome = 'Fail'; RuleName = 'Azure.Storage.SecureTransfer'; Title = 'Use secure transfer'; Pillar = 'Security'; Severity = 'Important'; ResourceName = 'stapp'; ResourceType = 'Microsoft.Storage/storageAccounts'; ResourceGroup = 'rg-app'; SubscriptionName = 'sub-app'; Reason = @('Secure transfer is off.'); Recommendation = 'Turn it on.'; Link = 'https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.Storage.SecureTransfer/'; ResourceId = (& $rid 'Microsoft.Storage/storageAccounts' 'stapp') }
                [pscustomobject]@{ Outcome = 'Pass'; RuleName = 'Azure.Storage.SecureTransfer'; Title = 'Use secure transfer'; Pillar = 'Security'; Severity = 'Important'; ResourceName = 'stdata'; ResourceType = 'Microsoft.Storage/storageAccounts'; ResourceGroup = 'rg-app'; SubscriptionName = 'sub-app'; Reason = @(); Recommendation = 'Turn it on.'; Link = ''; ResourceId = (& $rid 'Microsoft.Storage/storageAccounts' 'stdata') }
                [pscustomobject]@{ Outcome = 'Fail'; RuleName = 'Azure.VM.Standalone'; Title = 'Use availability zones'; Pillar = 'Reliability'; Severity = 'Critical'; ResourceName = 'vm1'; ResourceType = 'Microsoft.Compute/virtualMachines'; ResourceGroup = 'rg-app'; SubscriptionName = 'sub-app'; Reason = 'Not zonal.'; Recommendation = 'Deploy across zones.'; Link = ''; ResourceId = (& $rid 'Microsoft.Compute/virtualMachines' 'vm1') }
            )
            Sheet            = @(
                @{ Sheet = 'Advisor recommendations'; Kind = 'Advisor'; Columns = @(); Rows = @([pscustomobject]@{ Impact = 'Medium'; Category = 'HighAvailability'; Problem = 'Use zones'; Solution = 'Zone it'; Resource = 'vm1'; 'Resource type' = 'microsoft.compute/virtualmachines'; Subscription = 'sub-app'; 'Resource group' = 'rg-app'; ResourceId = (& $rid 'Microsoft.Compute/virtualMachines' 'vm1') }) }
                @{ Sheet = 'Retirements'; Kind = 'Advisor'; Columns = @(); Rows = @(
                        [pscustomobject]@{ 'Retirement date' = '2026-11-01'; Retiring = 'Basic public IPs'; Resource = 'pip1'; 'Resource type' = ''; Subscription = 'sub-app'; 'Resource group' = 'rg-app'; 'What to do' = 'Upgrade to Standard'; ResourceId = (& $rid 'Microsoft.Network/publicIPAddresses' 'pip1') }
                        [pscustomobject]@{ 'Retirement date' = '2028-09-30'; Retiring = 'Old API'; Resource = 'app1'; 'Resource type' = ''; Subscription = 'sub-app'; 'Resource group' = 'rg-app'; 'What to do' = 'Move on'; ResourceId = (& $rid 'Microsoft.Web/sites' 'app1') }
                    ) }
                @{ Sheet = 'Public IP addresses'; Kind = 'Inventory'; Category = 'Networking'; Columns = @('Name', 'Orphaned'); Rows = @([pscustomobject]@{ Name = 'pip2'; Orphaned = 'Yes'; ResourceId = (& $rid 'Microsoft.Network/publicIPAddresses' 'pip2') }, [pscustomobject]@{ Name = 'pip1'; Orphaned = 'No'; ResourceId = '' }) }
                @{ Sheet = 'Resource groups'; Kind = 'Overview'; Columns = @('Empty'); Rows = @([pscustomobject]@{ 'Resource group' = 'rg-old'; Empty = 'Yes'; ResourceId = "/subscriptions/$sub/resourceGroups/rg-old" }) }
            )
        }
        $script:governance = InModuleScope 'Azure.Admin.Console' -Parameters @{ I = $script:input } {
            param($I)
            ConvertTo-AACAssessmentGovernance -Sheet $I.Sheet -Policy $I.Policy -PolicyByGroup $I.PolicyByGroup -PolicyResource $I.PolicyResource -AssignedPolicy $I.AssignedPolicy `
                -PSRuleResult $I.PSRuleResult -SubscriptionName @{ '22222222-2222-2222-2222-222222222222' = 'sub-app' } -PolicyRead -PSRuleRead -PolicyResourceLimit 1 -Now ([datetime]'2026-10-09T00:00:00Z')
        }
        $script:rowsOf = { param([string] $Name) @(@($script:governance.Sheets | Where-Object Sheet -EQ $Name)[0].Rows) }
    }

    It 'adds the policy, inventory, PSRule and recommendation sheets, each under its tab''s category' {
        @($script:governance.Sheets | ForEach-Object { "$($_.Category): $($_.Sheet)" }) | Should -Be @(
            'Policy: Compliance by initiative', 'Policy: Compliance by resource group', 'Policy: Non-compliant resources', 'Policy inventory: Policy assignments', 'Policy inventory: Policies'
            'Policy: Compliance by standard', 'PSRule: PSRule rules', 'PSRule: PSRule results', 'Recommendations: Resource recommendations')
    }

    It 'gives every policy in force a status: Failed, Manual review, Passed, Not evaluated or Disabled - once per assignment' {
        @(& $script:rowsOf 'Policies' | ForEach-Object { "$($_.Policy) $($_.Status) $($_.'Non-compliant')" }) | Should -Be @('https Failed 2', 'mfa-attest Manual review 0', 'unseen Not evaluated 0', 'tls Passed 0', 'old Disabled 0')
        $initiative = (& $script:rowsOf 'Compliance by initiative')[0]
        "$($initiative.Kind) $($initiative.Status) $($initiative.Policies) $($initiative.'Failed policies') $($initiative.'Compliance (%)')" | Should -Be 'Initiative Failed 3 1 80'
        (& $script:rowsOf 'Policy assignments')[0].Inherited | Should -Be 'No'
        (& $script:rowsOf 'Compliance by resource group')[0].'Resource group' | Should -Be '(the subscription)'
    }

    It 'maps the policies to the standard''s controls' {
        @(& $script:rowsOf 'Compliance by standard' | ForEach-Object { "$($_.Control) $($_.Status) $($_.Policies) $($_.'Failing policies')" }) | Should -Be @('CIS_3.1 Failed 2 https', 'CIS_1.1 Manual review 1 ', 'CIS_3.15 Passed 1 ', 'CIS_9.9 Disabled 1 ')
    }

    It 'says why each resource fails, and how to fix it - and when the list was cut short' {
        $row = (& $script:rowsOf 'Non-compliant resources')[0]
        "$($row.Resource) | $($row.Effect) | $($row.Controls)" | Should -Be 'stapp | DeployIfNotExists | CIS_3.1'
        $row.Reason | Should -Be 'The related resource or setting the policy deploys is missing, or not configured as it requires. Reason code: Type:NotFound. The policy: Use HTTPS only.'
        $row.Remediation | Should -BeLike 'Create a remediation task*'
        $row.Link | Should -BeLike '*/remediate-resources'
        $script:governance.Notices | Should -BeLike '*stops at 1 resource-and-policy pairs*'
    }

    It 'counts each PSRule rule''s checks, and lists the failures with their reasons' {
        $rule = & $script:rowsOf 'PSRule rules' | Where-Object Name -EQ 'Azure.Storage.SecureTransfer'
        "$($rule.Status) $($rule.Checked) $($rule.Passed) $($rule.Failed) $($rule.'Pass (%)')" | Should -Be 'Failed 2 1 1 50'
        @(& $script:rowsOf 'PSRule results').Count | Should -Be 2
        (& $script:rowsOf 'PSRule results' | Where-Object Resource -EQ 'stapp').Reason | Should -Be 'Secure transfer is off.'
        "$($script:governance.Stats.PSRuleRules) $($script:governance.Stats.PSRulePassed) $($script:governance.Stats.PSRuleFailed)" | Should -Be '2 1 2'
    }

    It 'puts every recommendation in one list, most severe first, with a category and what to do' {
        @(& $script:rowsOf 'Resource recommendations' | ForEach-Object { "$($_.Severity)|$($_.Category)|$($_.Source)|$($_.Resource)" }) | Should -Be @(
            'Critical|Reliability|PSRule for Azure|vm1'
            'High|Reliability|Retirements|pip1'
            'High|Security|PSRule for Azure|stapp'
            'Medium|Governance|Azure Policy|stapp'
            'Medium|Reliability|Azure Advisor|vm1'
            'Low|Cost|Inventory|pip2'
            'Low|Operational excellence|Inventory|rg-old'
            'Low|Reliability|Retirements|app1'
        )
        $pip = & $script:rowsOf 'Resource recommendations' | Where-Object Resource -EQ 'pip2'
        "$($pip.'Resource type') $($pip.'Resource group') $($pip.Subscription)" | Should -Be 'microsoft.network/publicipaddresses rg-app sub-app'
        $script:governance.Stats.RecommendationsUrgent | Should -Be 3
    }

    It 'leaves out what wasn''t read' {
        $none = InModuleScope 'Azure.Admin.Console' { ConvertTo-AACAssessmentGovernance }
        @($none.Sheets.Sheet) | Should -Be @('Resource recommendations')
        $none.Stats.PSRuleRules | Should -BeNullOrEmpty
        @($none.Sheets[0].Rows).Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - the organization diagram' {
    It 'nests management groups and subscriptions as boxes, with resource groups as nodes' {
        $map = & $script:inModule { param($O) ConvertTo-AACOrganizationMap @O } @{ O = @{ ManagementGroup = $script:a.Organization.ManagementGroup; Subscription = $script:a.Organization.Subscription; ResourceGroup = $script:a.Organization.ResourceGroup; ResourceCount = $script:a.Organization.ResourceCount } }
        @($map.Clusters | Where-Object kind -EQ 'managementgroup').name | Sort-Object | Should -Be @('Landing zones', 'Platform', 'Tenant Root Group')
        $sandbox = @($map.Nodes | Where-Object name -EQ 'Sandbox')[0]
        $sandbox.typeLabel | Should -Be 'Management group' -Because 'an empty management group is a node'
        $app = @($map.Clusters | Where-Object { $_.kind -eq 'subscription' -and $_.name -eq 'sub-landingzone-app' })[0]
        $app.parent | Should -Be '/providers/Microsoft.Management/managementGroups/mg-landingzones'
        $empty = @($map.Nodes | Where-Object name -EQ 'rg-empty')[0]
        "$($empty.parent) $($empty.orphan)" | Should -Be "/subscriptions/$($script:f.AppSubscriptionId) an empty resource group"
        $small = & $script:inModule { param($O) ConvertTo-AACOrganizationMap @O -MaxGroups 1 } @{ O = @{ ManagementGroup = $script:a.Organization.ManagementGroup; Subscription = $script:a.Organization.Subscription; ResourceGroup = $script:a.Organization.ResourceGroup } }
        @($small.Nodes | Where-Object type -EQ 'microsoft.resources/subscriptions').Count | Should -Be 2 -Because 'too many resource groups: subscriptions are drawn as nodes'
    }
}

Describe 'Azure Admin Console - the resources diagram' {
    It 'draws each subscription with a node per resource type and its count' {
        $map = & $script:inModule { param($R) ConvertTo-AACResourceSummaryMap -Resource $R -SubscriptionName @{ '22222222-2222-2222-2222-222222222222' = 'sub-landingzone-app' } -IconType @{ 'microsoft.compute/virtualmachines' = 'vm' } -IconLabel @{ vm = 'Virtual Machine' } } @{ R = $script:f.Resources }
        @($map.Clusters).Count | Should -Be 2
        $vms = @($map.Nodes | Where-Object type -EQ 'microsoft.compute/virtualmachines')[0]
        "$($vms.name)|$($vms.icon)|$($vms.parent)|$($vms.facts[0])" | Should -Be 'Virtual Machine (2)|vm|/subscriptions/22222222-2222-2222-2222-222222222222|2 resource(s)'
        @($map.Nodes | Where-Object type -EQ 'microsoft.logic/workflows')[0].name | Should -Be 'workflows (1)' -Because 'a type with no icon is named after itself'
    }
}

Describe 'Azure Admin Console - app-only sign-in' {
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null }; Remove-Item Env:IDENTITY_ENDPOINT, Env:IDENTITY_HEADER -ErrorAction Ignore }

    It 'resolves a tenant domain to its ID from Entra ID''s public metadata' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -MockWith { if ($Uri -like '*nope*') { throw 'Not found' }; [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/33333333-3333-3333-3333-333333333333/v2.0' } }
        & $script:inModule { Resolve-AACTenantId -Tenant 'contoso.onmicrosoft.com' } | Should -Be '33333333-3333-3333-3333-333333333333'
        & $script:inModule { Resolve-AACTenantId -Tenant '44444444-4444-4444-4444-44444444444A' } | Should -Be '44444444-4444-4444-4444-44444444444a'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -Times 1 -Exactly -Because 'a GUID needs no lookup'
        { & $script:inModule { Resolve-AACTenantId -Tenant 'nope.example' } } | Should -Throw "*No Entra ID tenant was found for 'nope.example'*"
    }

    It 'asks for a service principal token with its secret' {
        $token = & $script:jwt @{ tid = 'tenant-1'; appid = 'app-1' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -MockWith { [pscustomobject]@{ access_token = $token; expires_in = 3599 } }
        $result = & $script:inModule { param($T) Get-AACAppToken -Flow ClientSecret -TenantId 'contoso.onmicrosoft.com' -ClientId 'app-1' -ClientSecret (ConvertTo-SecureString 's3cret' -AsPlainText -Force) -Resource 'https://storage.azure.com/' } @{ T = $token }
        $result.AccessToken | Should -Be $token
        $result.Claims.tid | Should -Be 'tenant-1'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token' -and $Body.grant_type -eq 'client_credentials' -and $Body.client_secret -eq 's3cret' -and $Body.scope -eq 'https://storage.azure.com/.default' } -Times 1 -Exactly
    }

    It 'signs a client assertion with a certificate, which its public key verifies' {
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=aac-test', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $script:cert = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddHours(1))
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -MockWith { $script:sent = $Body; [pscustomobject]@{ access_token = 'x.eyJ0aWQiOiJ0In0.y'; expires_in = 3599 } }
        $null = & $script:inModule { param($C) Get-AACAppToken -Flow Certificate -TenantId 'tenant-1' -ClientId 'app-1' -Certificate $C } @{ C = $script:cert }
        $script:sent.client_assertion_type | Should -Be 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        $parts = $script:sent.client_assertion -split '\.'
        $decode = { param([string] $Text) $t = $Text.Replace('-', '+').Replace('_', '/'); $t += '=' * ((4 - $t.Length % 4) % 4); [Convert]::FromBase64String($t) }
        $claims = [System.Text.Encoding]::UTF8.GetString((& $decode $parts[1])) | ConvertFrom-Json
        "$($claims.iss) $($claims.sub) $($claims.aud)" | Should -Be 'app-1 app-1 https://login.microsoftonline.com/tenant-1/oauth2/v2.0/token'
        [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($script:cert).VerifyData([System.Text.Encoding]::UTF8.GetBytes("$($parts[0]).$($parts[1])"), (& $decode $parts[2]), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should -BeTrue
    }

    It 'asks the managed identity endpoint of an Automation account, retrying without an api-version' {
        $env:IDENTITY_ENDPOINT = 'http://127.0.0.1:40342/msi/token'
        $env:IDENTITY_HEADER = 'h-1'
        $token = & $script:jwt @{ tid = 'tenant-1'; appid = 'mi-1' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -MockWith { if ($Uri -like '*api-version*') { throw 'Bad request' }; [pscustomobject]@{ access_token = $token; expires_on = '1900000000' } }
        $result = & $script:inModule { Get-AACAppToken -Flow ManagedIdentity }
        $result.AccessToken | Should -Be $token
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -ParameterFilter { $Uri -eq 'http://127.0.0.1:40342/msi/token?resource=https%3A%2F%2Fmanagement.azure.com' -and $Headers['X-IDENTITY-HEADER'] -eq 'h-1' } -Times 1 -Exactly
    }

    It 'connects as a service principal, and gets a new token when it runs out - no refresh token' {
        $token = & $script:jwt @{ tid = '33333333-3333-3333-3333-333333333333'; appid = 'app-1' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -MockWith { [pscustomobject]@{ access_token = $token; expires_in = 3599 } }
        $null = & $script:capture { Connect-AAC -TenantId 'contoso.onmicrosoft.com' -ClientId 'app-1' -ClientSecret (ConvertTo-SecureString 's3cret' -AsPlainText -Force) }
        $session = InModuleScope 'Azure.Admin.Console' { $script:AACSession }
        "$($session.Account)|$($session.TenantId)|$($session.Flow)" | Should -Be 'service principal app-1|33333333-3333-3333-3333-333333333333|ClientSecret'
        $session.RefreshToken | Should -BeNullOrEmpty
        InModuleScope 'Azure.Admin.Console' { $script:AACSession.ExpiresOn = (Get-Date).AddMinutes(-1) }
        InModuleScope 'Azure.Admin.Console' { Get-AACAccessToken } | Should -Be $token
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -Times 2 -Exactly -Because 'one token to connect, one when it expired'
        InModuleScope 'Azure.Admin.Console' { Get-AACAccessToken -Resource 'https://storage.azure.com' } | Should -Be $token
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-RestMethod -ParameterFilter { $Body.scope -eq 'https://storage.azure.com/.default' } -Times 1 -Exactly
    }
}

Describe 'Azure Admin Console - Invoke-AACAssessment' {
    BeforeEach {
        $script:failSheet = ''
        $script:graphCalls = [System.Collections.Generic.List[object]]::new()
        $script:armUris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:graphCalls.Add(@{ Keys = @($Query.Keys); SubscriptionId = @($SubscriptionId | Where-Object { $_ }) })
            $rows = @{}; $errors = @{}
            foreach ($key in @($Query.Keys)) {
                $rows[$key] = @(switch ($key) {
                        'subscriptions' { $script:f.Subscriptions } 'managementGroups' { $script:f.ManagementGroups } 'types' { $script:f.Types } 'resources' { $script:f.Resources }
                        'groups' { $script:f.Groups } 'advisor' { $script:f.Advisor } 'security' { $script:f.Security } 'secureScores' { $script:f.SecureScores } 'policy' { $script:f.Policy }
                        'policyByGroup' { $script:f.PolicyByGroup } 'policyResources' { $script:f.PolicyResources }
                        'supportTickets' { $script:f.SupportTickets } 'diagram' { $script:f.Diagram }
                        default { if ($script:queryRows.Contains($key)) { $script:queryRows[$key] } }
                    })
                if ($key -eq $script:failSheet) { $rows[$key] = @(); $errors[$key] = 'Forbidden' }
            }
            @{ Rows = $rows; Errors = $errors }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($target in $Uri) {
                $script:armUris.Add($target)
                $sub = if ($target -match '^/subscriptions/([^/]+)') { $Matches[1] } else { '' }
                $items = switch -Regex ($target) {
                    'advisorScore' { $script:f.Arm.AdvisorScore[$sub] }
                    'reservationRecommendations' { $script:f.Arm.Reservation[$sub] }
                    'ResourceHealth/events' { $script:f.Arm.Outage[$sub] }
                    'Compute/skus' { $script:f.Arm.Sku['westeurope'] }
                    'locations/([^/]+)/usages' { $script:f.Arm.Quota["$sub|$($Matches[1])"] }
                }
                $answers[$target] = @{ Status = 200; Items = @($items | Where-Object { $_ }); Error = '' }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACInventoryCost -MockWith { $script:f.Cost }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACAssignedPolicyData -MockWith { $script:f.PolicyData }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 'tenant-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'assesses everything the account can see and writes every report' {
        $outputs = @('Html', 'Csv', 'Diagram') + @(if ($script:canWritePdf) { 'Pdf' })
        $result = (& $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -ReportName 'Contoso' -Output $outputs -IncludeCost -QuotaUsage -SecurityCenter -NoDisplay }).Output[0]
        $result.PSObject.TypeNames | Should -Contain 'AAC.Assessment'
        "$($result.Subscriptions) $($result.Resources) $($result.Retirements)" | Should -Be '2 10 1'
        $result.ReportFolder | Should -BeLike "$TestDrive*Contoso-*"
        $names = @($result.Files | ForEach-Object Name)
        foreach ($name in 'Contoso.html', 'Contoso-Network.html', 'Contoso-Organization.html', 'Contoso-Resources.html', 'Virtual machines.csv', 'Advisor recommendations.csv', 'Quotas.csv') { $names | Should -Contain $name }
        if ($script:canWritePdf) { $names | Should -Contain 'Contoso.pdf' }
        $result.Sheets['Virtual machines'][0].vCPUs | Should -Be 2
        @($result.Sheets['Outages']).Count | Should -Be 1
        $html = Get-Content -LiteralPath (Join-Path $result.ReportFolder 'Contoso.html') -Raw
        $model = [regex]::Match($html, '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables | ForEach-Object section | Select-Object -Unique) | Should -Be @('Resources', 'Inventory', 'Security', 'Advisor', 'Policy compliance', 'Health', 'Cost', 'Policy inventory', 'Resource recommendations')
        $model.overviewTab | Should -Be 'Executive summary'
        @($model.tabs.name)[0..3] | Should -Be @('Policy compliance', 'Policy inventory', 'PSRule results', 'Resource recommendations')
        ($model.tables | Where-Object id -EQ 'virtual-machines').title | Should -Be 'Compute: Virtual machines' -Because 'the inventory''s categories share a tab'
        $donut = $model.charts | Where-Object title -EQ 'Policies by compliance status'
        "$($donut.kind) $($donut.table) $($donut.column)" | Should -Be 'donut policies Status'
        @($donut.items | ForEach-Object { "$($_.label) $($_.value) $($_.tone)" }) | Should -Be @('Failed 1 bad')
        ($model.charts | Where-Object title -EQ 'Non-compliant resources by resource group').items[0].label | Should -Be 'rg-app'
        ($model.charts | Where-Object title -EQ 'Recommendations by severity').table | Should -Be 'resource-recommendations'
        ($model.tiles | Where-Object { $_.label -like 'failed of*' }).filters.Status | Should -Be 'Failed'
        (($model.tables | Where-Object id -EQ 'resource-recommendations').columns | Where-Object key -EQ 'Link').type | Should -Be 'link'
        $policy = @($result.Sheets['Policies'])[0]
        "$($policy.Policy) | $($policy.Status) | $($policy.Effect) | $($policy.'Non-compliant')" | Should -Be 'Allowed locations | Failed | Deny | 3'
        @($result.Sheets['Policy assignments'])[0].Inherited | Should -Be 'Yes'
        $failing = @($result.Sheets['Non-compliant resources'])[0]
        "$($failing.Resource) | $($failing.Effect)" | Should -Be 'vm-web-1 | Deny'
        $failing.Reason | Should -BeLike '*doesn''t match what the policy requires*Restrict the locations*'
        $names | Should -Contain 'Resource recommendations.csv'
        ($model.tiles | Where-Object label -EQ 'resources without tags').table | Should -Be 'all-resources'
        $model.tree.root.n | Should -Be 'Tenant Root Group'
        @($script:graphCalls | Where-Object { $_.Keys -contains 'types' })[0].SubscriptionId.Count | Should -Be 0 -Because 'with no scope, every query covers everything the account can see'
    }

    It 'runs PSRule for Azure with -PSRule, on the resource groups asked for - and says when it isn''t installed' {
        $script:engine = $null
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-Module -ParameterFilter { $Name -eq 'PSRule.Rules.Azure' } -MockWith { [pscustomobject]@{ Name = 'PSRule.Rules.Azure'; Version = [version]'1.40.0' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -MockWith {
            $script:engine = @{ Baseline = $Baseline; SubscriptionId = @($SubscriptionId) }
            $result = { param([string] $Group, [string] $Outcome) [pscustomobject]@{ Outcome = $Outcome; RuleName = 'Azure.VM.Standalone'; Title = 'Use availability zones'; Pillar = 'Reliability'; Severity = 'Critical'; ResourceName = "vm-$Group"; ResourceType = 'Microsoft.Compute/virtualMachines'; ResourceGroup = $Group; SubscriptionName = 'sub-landingzone-app'; Reason = 'Not zonal.'; Recommendation = 'Deploy across zones.'; Link = 'https://azure.github.io/PSRule.Rules.Azure/'; ResourceId = "/subscriptions/x/resourceGroups/$Group/providers/Microsoft.Compute/virtualMachines/vm-$Group" } }
            @{ Results = @((& $result 'rg-app' 'Fail'), (& $result 'rg-app' 'Pass'), (& $result 'rg-other' 'Fail')) }
        }
        $result = (& $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Csv -PSRule -PSRuleBaseline 'Azure.Pillar.Reliability' -ResourceGroupName 'rg-app' -NoDisplay }).Output[0]
        $script:engine.Baseline | Should -Be 'Azure.Pillar.Reliability'
        $script:engine.SubscriptionId.Count | Should -Be 2
        @($result.Sheets['PSRule results'].Resource) | Should -Be @('vm-rg-app')
        (@($result.Sheets['Resource recommendations']) | Where-Object Source -EQ 'PSRule for Azure').Severity | Should -Be 'Critical'
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-Module -ParameterFilter { $Name -eq 'PSRule.Rules.Azure' } -MockWith { }
        $without = (& $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Csv -PSRule -NoDisplay }).Output[0]
        $without.Notices | Should -Contain 'PSRule for Azure is not installed, so its rules were not run: Install-PSResource PSRule.Rules.Azure -Scope CurrentUser'
        $without.Sheets.Contains('PSRule results') | Should -BeFalse
    }

    It 'reads a sheet only for the resource types present, and only the categories asked for' {
        $null = & $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Csv -Category Compute, Storage -NoDisplay }
        $sheetCall = @($script:graphCalls | Where-Object { $_.Keys -contains 'Virtual machines' })[0]
        @($sheetCall.Keys | Sort-Object) | Should -Be @('Disks', 'Storage accounts', 'Virtual desktop session hosts', 'Virtual machines')
    }

    It 'scopes to subscriptions or management groups, and says what it can''t find' {
        $output = (& $script:capture { Invoke-AACAssessment -SubscriptionId $script:f.HubSubscriptionId, '99999999-9999-9999-9999-999999999999' -ReportDir $TestDrive -Output Csv -NoDisplay -WarningVariable warned -WarningAction SilentlyContinue; $warned }).Output
        $output[0].Subscriptions | Should -Be 1
        "$($output[1..($output.Count - 1)])" | Should -BeLike '*99999999-9999-9999-9999-999999999999*left out*'
        @($script:graphCalls | Where-Object { $_.Keys -contains 'types' })[0].SubscriptionId | Should -Be @($script:f.HubSubscriptionId)
        $byGroup = (& $script:capture { Invoke-AACAssessment -ManagementGroupId 'mg-landingzones' -ReportDir $TestDrive -Output Csv -NoDisplay }).Output[0]
        $byGroup.Subscriptions | Should -Be 1
        { & $script:capture { Invoke-AACAssessment -ManagementGroupId 'mg-nope' -ReportDir $TestDrive -Output Csv -NoDisplay } } | Should -Throw '*under management group mg-nope*'
    }

    It 'asks the Azure APIs as told: none with -SkipApi, quotas with -QuotaUsage, no VM sizes with -SkipVMDetail' {
        $null = & $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Csv -SkipApi -NoDisplay }
        $script:armUris.Count | Should -Be 0
        $null = & $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Csv -QuotaUsage -SkipVMDetail -NoDisplay }
        @($script:armUris | Where-Object { $_ -like '*usages*' }).Count | Should -Be 1
        @($script:armUris | Where-Object { $_ -like '*Compute/skus*' }).Count | Should -Be 0
        @($script:armUris | Where-Object { $_ -like '*ResourceHealth/events*queryStartTime=*' }).Count | Should -Be 2
    }

    It 'carries on when a sheet can''t be read, and says so' {
        $script:failSheet = 'Storage accounts'
        $result = (& $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Csv -NoDisplay }).Output[0]
        $result.Notices | Should -Contain "Storage accounts couldn't be read: Forbidden"
        @($result.Sheets['Virtual machines']).Count | Should -Be 2
    }

    It 'uploads the reports to blob storage' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Send-AACBlobFile -MockWith { foreach ($p in $Path) { @{ File = $p; Blob = "$Prefix/$(Split-Path $p -Leaf)"; Status = 'Uploaded'; Error = '' } } }
        $result = (& $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Html -StorageAccount 'stcontosoreports' -StorageContainer 'assessments' -NoDisplay }).Output[0]
        @($result.Uploads).Count | Should -Be 1
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACBlobFile -ParameterFilter { $StorageAccount -eq 'stcontosoreports' -and $Container -eq 'assessments' -and $Prefix -eq 'AzureAssessment' } -Times 1 -Exactly
        { Invoke-AACAssessment -StorageAccount 'only' -NoDisplay } | Should -Throw '*both -StorageAccount and -StorageContainer*'
    }

    It 'signs in to -TenantId only when the session is for another tenant, by its domain too' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACTenantId -MockWith { if ($Tenant -eq 'contoso.onmicrosoft.com') { 'tenant-1' } else { 'tenant-2' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Connect-AAC -MockWith { }
        $null = & $script:capture { Invoke-AACAssessment -TenantId 'contoso.onmicrosoft.com' -ReportDir $TestDrive -Output Csv -NoDisplay }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Connect-AAC -Times 0 -Exactly -Because 'the session is for that tenant already'
        $null = & $script:capture { Invoke-AACAssessment -TenantId 'fabrikam.onmicrosoft.com' -ReportDir $TestDrive -Output Csv -NoDisplay }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Connect-AAC -ParameterFilter { $TenantId -eq 'tenant-2' } -Times 1 -Exactly
    }

    It 'signs in with the managed identity in Automation when there is no session' {
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Connect-AAC -MockWith { InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'managed identity mi-1'; TenantId = 'tenant-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } } }
        $output = (& $script:capture { Invoke-AACAssessment -Automation -ReportDir $TestDrive -Output Csv -WarningAction SilentlyContinue }).Output
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Connect-AAC -ParameterFilter { $Identity } -Times 1 -Exactly
        "$output" | Should -BeLike 'Assessed 10 resource(s) in 2 subscription(s)*'
    }

    It 'shows what it found, what needs attention and the reports, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACAssessment -ReportDir $TestDrive -Output Csv -NoPaging } -Ascii).Text
        foreach ($expected in 'Azure environment assessment', 'Inventory by category', 'Networking', 'Most common resource types', 'Needs attention', 'RETIRING', 'pip-web-2', 'Reports', 'CSV') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }
}
