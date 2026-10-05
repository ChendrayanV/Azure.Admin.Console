<#
    Unit tests for Invoke-AACAksAssessment: Azure Policy for Kubernetes
    consolidated by namespace, workload, policy and cluster (the AKS Policy
    Compliance Toolkit's view), the assessment of made-up Contoso clusters
    (Fixtures\ContosoAks.ps1) through every lens, Gatekeeper's counts through
    AKS run command, and the command with Azure mocked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoAks.ps1')
    $script:f = Get-AACContosoAks
    $script:names = @{}
    foreach ($c in $script:f.Clusters) { $script:names[$c.id.ToLowerInvariant()] = $c.name }
    $script:comply = {
        param([hashtable] $With = @{})
        $p = @{ Component = $script:f.Rows.components; ClusterState = $script:f.Rows.clusterStates; Assignment = $script:f.Rows.assignments; DefinitionName = $script:f.DefinitionNames; ClusterName = $script:names; SubscriptionName = @{ $script:f.SubscriptionId = 'sub-aks' } }
        foreach ($k in $With.Keys) { $p[$k] = $With[$k] }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $p } { param($P) ConvertTo-AACAksPolicyCompliance @P }
    }
    $script:policy = & $script:comply
    $script:assess = {
        param([hashtable] $With = @{}, [object[]] $Clusters = $script:f.Clusters)
        $p = @{
            Cluster = $Clusters; UpgradeProfile = $script:f.UpgradeProfiles; PoolUpgrade = $script:f.PoolUpgrades; KubernetesVersion = $script:f.Versions; Subnet = $script:f.Subnets
            Advisor = $script:f.Rows.advisor; Defender = $script:f.Rows.defender; PSRule = $script:f.PSRule; Policy = $script:policy
            Constraint = @{ $script:f.ProdId.ToLowerInvariant() = $script:f.Constraint }; SubscriptionName = @{ $script:f.SubscriptionId = 'sub-aks' }; Now = [datetime]'2026-10-05'
        }
        foreach ($k in $With.Keys) { $p[$k] = $With[$k] }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $p } { param($P) ConvertTo-AACAksAssessment @P }
    }
    $script:a = & $script:assess
    $script:cluster = { param([string] $Name, $From = $script:a) @($From.Clusters | Where-Object Name -EQ $Name)[0] }
    $script:checkOf = { param([string] $Cluster, [string] $Check, $From = $script:a) @($From.Checks | Where-Object { $_.Cluster -eq $Cluster -and $_.Check -eq $Check })[0] }
    $script:copy = { param($Object) ConvertTo-Json -InputObject $Object -Depth 20 | ConvertFrom-Json -AsHashtable }
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

Describe 'Azure Admin Console - AKS policy compliance (the toolkit''s view)' {
    It 'infers each pod''s workload from its name, and leaves out the system namespaces' {
        $rows = @($script:policy.Components)
        $rows.Count | Should -Be 4 -Because 'coredns in kube-system is left out'
        @($rows | ForEach-Object { "$($_.WorkloadKind):$($_.Workload)" } | Sort-Object -Unique) | Should -Be @('CronJob:nightly', 'Deployment:api', 'StatefulSet:ledger')
        @($rows.Namespace | Sort-Object -Unique) | Should -Be @('payments')
        @((& $script:comply @{ IncludeSystemNamespace = $true }).Components | Where-Object Namespace -EQ 'kube-system')[0].Workload | Should -Be 'coredns'
    }

    It 'names each policy and initiative, and resolves its effect (DoNotEnforce is audit)' {
        $api = @($script:policy.Components | Where-Object Workload -EQ 'api')[0]
        "$($api.Policy)|$($api.Effect)|$($api.Assignment)|$($api.Initiative)" | Should -Be 'Kubernetes cluster containers should run with a read only root file system|deny|AKS pod security baseline|Kubernetes cluster pod security baseline standards for Linux-based workloads'
        @($script:policy.Components | Where-Object Workload -EQ 'nightly')[0].Effect | Should -Be 'audit (DoNotEnforce)'
        $unnamed = & $script:comply @{ DefinitionName = @{} }
        @($unnamed.Components)[0].Policy | Should -Be 'df49d893-a74c-421d-bc95-c663042e5b80' -Because 'without its name, the definition''s ID'
    }

    It 'rolls them up by namespace, workload, policy and cluster' {
        $ns = @($script:policy.ByNamespace)[0]
        "$($ns.Namespace) $($ns.Violations) $($ns.Workloads) $($ns.Policies) $($ns.Deny)" | Should -Be 'payments 4 3 2 2'
        $api = @($script:policy.ByWorkload | Where-Object Workload -EQ 'api')[0]
        "$($api.Violations) $($api.Components) $($api.Deny)" | Should -Be '2 2 2'
        @($script:policy.ByPolicy).Count | Should -Be 2
        @($script:policy.ByCluster | Where-Object Capped).Count | Should -Be 0
    }

    It 'flags a cluster and policy at Azure Policy''s 500-record cap' {
        $many = @(1..500 | ForEach-Object { @{ clusterId = $script:f.ProdId.ToLowerInvariant(); assignmentId = $script:f.Rows.assignments[0].assignmentId; definitionId = '/providers/microsoft.authorization/policydefinitions/x'; setId = ''; refId = ''; componentType = 'pod'; componentId = "team-$($_ % 7)/web-7d9f8b6c5d-$('{0:00000}' -f $_)" } })
        $capped = & $script:comply @{ Component = $many }
        "$(@($capped.ByCluster)[0].Capped) $($capped.Stats.Capped)" | Should -Be 'True 1'
    }

    It 'lists the policies on each cluster resource, and the assignments that reach them' {
        $dev = @($script:policy.ClusterStates | Where-Object Cluster -EQ 'aks-dev')[0]
        "$($dev.State)|$($dev.Scope)|$($dev.Policy)" | Should -Be 'NonCompliant|Cluster|Azure Kubernetes Service Clusters should have local authentication methods disabled'
        @($script:policy.ClusterStates | Where-Object { $_.Cluster -eq 'aks-prod-weu' -and $_.Scope -eq 'Workloads' }).Count | Should -Be 2
        $limits = @($script:policy.Assignments | Where-Object Assignment -EQ 'AKS resource limits')[0]
        "$($limits.EnforcementMode) $($limits.Policies) $($limits.NonCompliant) $($limits.Clusters)" | Should -Be 'DoNotEnforce 2 2 2'
    }
}

Describe 'Azure Admin Console - AKS assessment' {
    It 'reads each version''s support, the upgrades available and how far behind it is' {
        $prod = & $script:cluster 'aks-prod-weu'
        "$($prod.Support) $($prod.Upgrade)" | Should -Be 'Supported 1.31.2' -Because 'a preview upgrade is left out'
        $plane = @($script:a.Upgrades | Where-Object { $_.Cluster -eq 'aks-prod-weu' -and $_.Component -eq 'Control plane' })[0]
        "$($plane.Behind) $($plane.LatestMinor) $($plane.LatestPatch)" | Should -Be '1 1.31 1.30.6'
        (& $script:cluster 'aks-dev').Support | Should -Be 'Out of support (LTS only)'
        $lts = & $script:copy $script:f.Clusters[1]; $lts.properties.supportPlan = 'AKSLongTermSupport'; $lts.sku.tier = 'Premium'
        (& $script:cluster 'aks-dev' (& $script:assess -Clusters @($lts))).Support | Should -Be 'Long-term support'
        $old = & $script:copy $script:f.Clusters[1]; $old.properties.currentKubernetesVersion = '1.26.3'
        (& $script:cluster 'aks-dev' (& $script:assess -Clusters @($old))).Support | Should -Be 'Out of support'
    }

    It 'passes a well-run cluster on every Well-Architected check' {
        $prod = & $script:cluster 'aks-prod-weu'
        "$($prod.WafScore) $($prod.Reliability) $($prod.Security) $($prod.CostOptimization) $($prod.OperationalExcellence) $($prod.PerformanceEfficiency)" | Should -Be '100 100 100 100 100 100'
        @($script:a.Checks | Where-Object Cluster -EQ 'aks-prod-weu').Count | Should -BeGreaterThan 30
    }

    It 'fails a neglected cluster where it falls short, with what to do' {
        $failed = @($script:a.Checks | Where-Object { $_.Cluster -eq 'aks-dev' -and $_.Status -eq 'Fail' } | ForEach-Object Check)
        foreach ($expected in 'Uptime SLA (Standard or Premium tier)', 'Node pools across availability zones', 'System node pool with at least 2 nodes', 'Kubernetes version supported', 'Local accounts disabled', 'Entra ID integration', 'API server not open to the internet', 'Network policy', 'Azure Policy add-on', 'No public IPs on nodes', 'No pod-managed identity (deprecated)', 'Automatic cluster upgrades', 'Control plane logs (kube-audit)', 'No HTTP application routing add-on (retired)', 'Ephemeral OS disks', 'Node images patched (60 days or newer)', 'Subnets fit the pools at full scale') {
            $failed | Should -Contain $expected
        }
        (& $script:checkOf 'aks-dev' 'Subnets fit the pools at full scale').Detail | Should -BeLike '*vnet-aks-dev/snet-nodes (10.20.0.0/27: 27 usable, 186 needed at full scale)*'
        (& $script:checkOf 'aks-dev' 'Node images patched (60 days or newer)').Detail | Should -BeLike '*nodepool1 (633 days)*'
        (& $script:checkOf 'aks-dev' 'API server not open to the internet').Recommendation | Should -Not -BeNullOrEmpty
        $plugin = & $script:copy $script:f.Clusters[1]; $plugin.properties.networkProfile.networkPlugin = 'kubenet'
        (& $script:checkOf 'aks-dev' 'Supported network plugin (not kubenet)' (& $script:assess -Clusters @($plugin))).Status | Should -Be 'Fail'
    }

    It 'brings in the other lenses as findings: PSRule, Advisor, Defender, Azure Policy' {
        $dev = @($script:a.Findings | Where-Object { $_.Cluster -eq 'aks-dev' -and $_.Source -ne 'Well-Architected' })
        @($dev | ForEach-Object { "$($_.Source):$($_.Severity)" } | Sort-Object) | Should -Be @('Advisor:High', 'Azure Policy:Medium', 'Defender:High', 'PSRule:High', 'PSRule:Medium') -Because 'Critical PSRule rules are High, Important ones Medium'
        $prod = @($script:a.Findings | Where-Object { $_.Cluster -eq 'aks-prod-weu' -and $_.Source -eq 'Azure Policy' })
        @($prod.Severity | Sort-Object) | Should -Be @('High', 'Medium') -Because 'a policy under Deny is High'
        $script:a.Findings[0].Severity | Should -Be 'High'
    }

    It 'lists the node pools, current settings, diagnostics, maintenance and Gatekeeper''s counts' {
        $pool = @($script:a.NodePools | Where-Object Pool -EQ 'apps')[0]
        "$($pool.Autoscale) $($pool.Min) $($pool.Max) $($pool.Zones) $($pool.NodeImageAge) $($pool.Subnet)" | Should -Be 'Yes 2 10 1, 2, 3 15 vnet-aks/snet-nodes'
        $setting = { param([string] $Cluster, [string] $Name) @($script:a.Settings | Where-Object { $_.Cluster -eq $Cluster -and $_.Setting -eq $Name })[0].Value }
        & $setting 'aks-prod-weu' 'Network plugin' | Should -Be 'azure (overlay)'
        & $setting 'aks-prod-weu' 'Log Analytics workspace' | Should -Be 'law-aks'
        & $setting 'aks-dev' 'Local accounts' | Should -Be 'Enabled'
        @($script:a.Settings | ForEach-Object Area | Sort-Object -Unique) | Should -Be @('Add-ons', 'Autoscaler', 'General', 'Identity and access', 'Monitoring', 'Networking', 'Security', 'Upgrades')
        @($script:a.Diagnostics)[0].Logs | Should -Be 'kube-audit-admin, kube-apiserver'
        @($script:a.Maintenance)[0].Configuration | Should -Be 'aksManagedAutoUpgradeSchedule'
        "$(@($script:a.Constraints)[0].TotalViolations) $($script:a.Stats.GatekeeperViolations)" | Should -Be '612 612'
    }

    It 'scores each pillar, and assesses no clusters without failing' {
        @($script:a.Pillars.Pillar) | Should -Be @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')
        (@($script:a.Pillars | Where-Object Pillar -EQ 'Security')[0]).Failed | Should -BeGreaterThan 10
        $empty = InModuleScope 'Azure.Admin.Console' { ConvertTo-AACAksAssessment -Cluster @() }
        "$($empty.Stats.Clusters) $($empty.Stats.WafScore)" | Should -Be '0 '
    }
}

Describe 'Azure Admin Console - Gatekeeper through AKS run command' {
    It 'runs kubectl in the cluster, follows the command to its result and reads the constraints' {
        $logs = "T`tK8sAzureV1ReadOnlyRootFilesystem`tazurepolicy-ro`tdryrun`t612`t/providers/x/policyAssignments/aks-baseline`treadOnlyRoot`nV`tpayments`tPod`tapi-1`tonly read-only root filesystem`nT`tK8sAzureV1Limits`tazurepolicy-limits`t`t3`t`t`n"
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'aks-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith {
            if ($Method -eq 'Post') { $script:sent = $Body | ConvertFrom-Json; return @{ Status = 202; Content = ''; Headers = @{ Location = 'https://management.azure.com/x/commandResults/1?api-version=2024-02-01' } } }
            @{ Status = 200; Content = (@{ properties = @{ provisioningState = 'Succeeded'; exitCode = 0; logs = $logs } } | ConvertTo-Json -Depth 5); Headers = @{} }
        }
        $result = InModuleScope 'Azure.Admin.Console' { Get-AACAksConstraint -ClusterId '/subscriptions/s/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks' -EntraId }
        $result.Status | Should -Be 'OK'
        @($result.Totals | ForEach-Object { "$($_.Kind):$($_.Action):$($_.TotalViolations):$($_.Assignment)" }) | Should -Be @('K8sAzureV1ReadOnlyRootFilesystem:dryrun:612:aks-baseline', 'K8sAzureV1Limits:deny:3:')
        "$(@($result.Violations)[0].Constraint) $(@($result.Violations)[0].Namespace) $(@($result.Violations)[0].Object)" | Should -Be 'K8sAzureV1ReadOnlyRootFilesystem payments Pod/api-1'
        $script:sent.command | Should -BeLike '*kubectl api-resources --categories=constraint*'
        $script:sent.clusterToken | Should -Be 'aks-token'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -ParameterFilter { $Resource -eq '6dae42f8-4368-4678-94ff-3960e28e3630' } -Times 1 -Exactly
    }

    It 'says when Gatekeeper isn''t there, or the command failed' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith { @{ Status = 200; Content = (@{ properties = @{ provisioningState = 'Succeeded'; exitCode = 0; logs = "NO_GATEKEEPER`n" } } | ConvertTo-Json); Headers = @{} } }
        (InModuleScope 'Azure.Admin.Console' { Get-AACAksConstraint -ClusterId '/x' }).Status | Should -Be 'NoGatekeeper'
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith { throw 'Run command is disabled for this cluster' }
        (InModuleScope 'Azure.Admin.Console' { Get-AACAksConstraint -ClusterId '/x' }).Status | Should -BeLike "Couldn't start the command: Run command is disabled*"
    }
}

Describe 'Azure Admin Console - Invoke-AACAksAssessment' {
    BeforeEach {
        $script:graphCalls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:graphCalls.Add(@{ Keys = @($Query.Keys); SubscriptionId = @($SubscriptionId | Where-Object { $_ }) })
            $rows = @{}
            foreach ($key in @($Query.Keys)) { $rows[$key] = @(if ($script:f.Rows.Contains($key)) { $script:f.Rows[$key] }) }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACRuleData -MockWith { $script:ruleDataIds = @($ResourceId); @{ Resources = @($script:f.Clusters | Where-Object { @($ResourceId) -contains $_.id }); Warnings = @() } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($target in $Uri) {
                $body = switch -Regex ($target) {
                    '/agentPools/([^/]+)/upgradeProfiles' { $key = "$((($target -split '/agentPools/')[0]).ToLowerInvariant())/$($Matches[1].ToLowerInvariant())"; $script:f.PoolUpgrades[$key]; break }
                    '/upgradeProfiles/default' { $script:f.UpgradeProfiles[(($target -split '/upgradeProfiles')[0]).ToLowerInvariant()]; break }
                    'kubernetesVersions' { @{ values = $script:f.Versions['westeurope'] }; break }
                    'policy(set)?definitions' { $id = ($target -split '\?')[0]; if ($script:f.DefinitionNames.Contains($id)) { @{ properties = @{ displayName = $script:f.DefinitionNames[$id] } } }; break }
                    'subnets' { @{ id = ($target -split '\?')[0]; properties = @{ addressPrefix = '10.10.0.0/24' } }; break }
                }
                $answers[$target] = @{ Status = $(if ($body) { 200 } else { 404 }); Body = $body; Items = $null; Error = $(if ($body) { '' } else { 'Not found' }) }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-Module -ParameterFilter { $Name -eq 'PSRule.Rules.Azure' } -MockWith { [pscustomobject]@{ Name = 'PSRule.Rules.Azure'; Version = [version]'1.47.0' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -MockWith { @{ Results = $script:f.PSRule; Warnings = @(); Rules = 3; Objects = 2 } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAksConstraint -MockWith { $script:f.Constraint }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 'tenant-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'assesses every cluster and returns them with their node pools, settings, checks, findings and policy violations' {
        $clusters = @((& $script:capture { Invoke-AACAksAssessment -NoDisplay }).Output)
        $clusters.Count | Should -Be 2
        $clusters[0].PSObject.TypeNames | Should -Contain 'AAC.AksCluster'
        $prod = @($clusters | Where-Object Name -EQ 'aks-prod-weu')[0]
        "$(@($prod.NodePools).Count) $(@($prod.PolicyViolations).Count) $($prod.Upgrade)" | Should -Be '2 4 1.31.2'
        @($prod.Checks).Count | Should -BeGreaterThan 30
        $script:ruleDataIds | Should -Be @($script:f.ProdId, $script:f.DevId) -Because 'PSRule''s data is read for the chosen clusters only'
        @($script:graphCalls | Where-Object { $_.Keys -contains 'components' })[0].SubscriptionId | Should -Be @($script:f.SubscriptionId)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAksConstraint -Times 0 -Exactly -Because 'run command only with -IncludeConstraint'
    }

    It 'picks clusters by name, and says when none matches' {
        @((& $script:capture { Invoke-AACAksAssessment -Name 'aks-prod*' -NoDisplay }).Output).Name | Should -Be 'aks-prod-weu'
        { & $script:capture { Invoke-AACAksAssessment -Name 'aks-nope' -NoDisplay } } | Should -Throw "*No AKS cluster named 'aks-nope'*"
    }

    It 'runs PSRule unless -SkipPSRule, and says when it isn''t installed' {
        $null = & $script:capture { Invoke-AACAksAssessment -SkipPSRule -NoDisplay }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -Times 0 -Exactly
        $null = & $script:capture { Invoke-AACAksAssessment -Baseline 'Azure.GA_2024_12' -ExcludeRule 'Azure.AKS.UptimeSLA' -NoDisplay }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -ParameterFilter { $Baseline -eq 'Azure.GA_2024_12' -and $ExcludeRule -contains 'Azure.AKS.UptimeSLA' -and @($InputObject).Count -eq 2 } -Times 1 -Exactly
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-Module -ParameterFilter { $Name -eq 'PSRule.Rules.Azure' } -MockWith { }
        $html = Join-Path $TestDrive 'nopsrule.html'
        $null = & $script:capture { Invoke-AACAksAssessment -HtmlPath $html }
        (Get-Content -LiteralPath $html -Raw) | Should -BeLike '*PSRule for Azure is not installed*'
    }

    It 'reads Gatekeeper in each cluster with -IncludeConstraint, with an Entra ID token where the cluster needs one' {
        $null = & $script:capture { Invoke-AACAksAssessment -IncludeConstraint -NoDisplay }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAksConstraint -ParameterFilter { $ClusterId -eq $script:f.ProdId -and $EntraId } -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAksConstraint -ParameterFilter { $ClusterId -eq $script:f.DevId -and -not $EntraId } -Times 1 -Exactly
    }

    It 'writes the CSV files (and a file per namespace), the HTML report and the PDF' {
        $csv = Join-Path $TestDrive 'aks'
        $html = Join-Path $TestDrive 'aks.html'
        $pdf = Join-Path $TestDrive 'aks.pdf'
        $null = & $script:capture { Invoke-AACAksAssessment -CsvPath $csv -HtmlPath $html -PdfPath $(if ($script:canWritePdf) { $pdf } else { $null }) }
        foreach ($name in 'clusters.csv', 'node-pools.csv', 'settings.csv', 'checks.csv', 'findings.csv', 'policy-by-namespace.csv', 'policy-violations.csv', 'policy-namespaces\payments.csv') { Join-Path $csv $name | Should -Exist }
        @(Import-Csv -LiteralPath (Join-Path $csv 'policy-namespaces\payments.csv')).Count | Should -Be 4
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.section | Select-Object -Unique) | Should -Be @('Overview', 'Current settings', 'Well-Architected', 'PSRule for Azure', 'Azure Policy')
        @($model.tables.id) | Should -Contain 'policy-namespace'
        if ($script:canWritePdf) { (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 2000 }
    }

    It 'shows the clusters, pillars, findings and policy by namespace, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACAksAssessment -NoPaging } -Ascii).Text
        foreach ($expected in 'AKS cluster assessment', 'aks-prod-weu', 'Out of support', 'Well-Architected checks passed per pillar', 'HIGH', 'Azure Policy for Kubernetes by namespace', 'payments', 'Node pools') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }
}
