function Write-AACAksHtml {
    <#
    .SYNOPSIS
        Writes Invoke-AACAksAssessment's report as one interactive HTML page.
    .DESCRIPTION
        Tiles (clusters, nodes, the WAF score, findings by severity, out of
        support, policy violations, PSRule failures - each opening its
        table), charts (WAF score per pillar, findings by source, policy
        violations by namespace and by policy) and the tables, under their
        lens in the contents - each collapsible, searchable, filterable,
        groupable and downloadable as CSV:
          Overview        clusters, findings
          Settings        current settings, node pools, upgrades,
                          diagnostic settings, maintenance windows
          Well-Architected  the pillars, every check
          PSRule          PSRule for Azure's results
          Azure Policy    by namespace, by workload, by policy, by cluster,
                          every non-compliant component, cluster states,
                          assignments, Gatekeeper's counts
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Assessment.Stats
    $policy = $Assessment.Policy
    $severity = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Info = 'neutral' }
    $passFail = @{ Pass = 'good'; Fail = 'bad' }
    $support = @{ Supported = 'good'; 'Long-term support' = 'good'; Preview = 'warn'; 'Out of support' = 'bad'; 'Out of support (LTS only)' = 'bad'; Unknown = 'neutral' }
    $effect = @{ deny = 'bad'; audit = 'warn'; 'audit (DoNotEnforce)' = 'warn'; dryrun = 'warn'; warn = 'warn'; unresolved = 'neutral' }
    $yesNo = @{ Yes = 'good'; No = 'warn'; Enabled = 'warn'; Disabled = 'good' }
    $col = { param([string] $Key, [string] $Label, [hashtable] $More = @{}) $c = @{ Key = $Key; Label = $Label }; foreach ($k in $More.Keys) { $c[$k] = $More[$k] }; $c }
    $num = @{ Type = 'number' }
    $facet = @{ Facet = $true }

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Clusters; Label = "clusters, $('{0:N0}' -f $stats.Nodes) nodes"; Tone = 'info'; Table = 'clusters' }
        @{ Value = $(if ($null -ne $stats.WafScore) { "$($stats.WafScore)%" } else { '-' }); Label = 'Well-Architected checks passed'; Tone = $(if ($stats.WafScore -ge 80) { 'good' } elseif ($stats.WafScore -ge 60) { 'warn' } else { 'bad' }); Table = 'checks'; Filters = @{ Status = 'Fail' } }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high-severity findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium-severity findings'; Tone = $(if ($stats.Medium) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'Medium' } }
        @{ Value = '{0:N0}' -f $stats.OutOfSupport; Label = 'clusters out of support'; Tone = $(if ($stats.OutOfSupport) { 'bad' } else { 'good' }); Table = 'upgrades' }
        @{ Value = '{0:N0}' -f $stats.PSRuleFailed; Label = "PSRule rules failed ($($stats.PSRulePassed) passed)"; Tone = $(if ($stats.PSRuleFailed) { 'warn' } else { 'good' }); Table = 'psrule'; Filters = @{ Outcome = 'Fail' } }
        if ($policy) { @{ Value = '{0:N0}' -f $policy.Stats.Violations; Label = "policy violations in $($policy.Stats.Workloads) workload(s), $($policy.Stats.Namespaces) namespace(s)"; Tone = $(if ($policy.Stats.Violations) { 'warn' } else { 'good' }); Table = 'policy-namespace' } }
        if ($stats.GatekeeperViolations) { @{ Value = '{0:N0}' -f $stats.GatekeeperViolations; Label = 'Gatekeeper violations (complete count)'; Tone = 'warn'; Table = 'gatekeeper' } }
    )
    $charts = @(
        @{ Title = 'Well-Architected score per pillar (%)'; Items = @($Assessment.Pillars | Where-Object { $null -ne $_.Score } | ForEach-Object { @{ Label = $_.Pillar; Value = $_.Score; Display = "$($_.Score)% ($($_.Passed) of $($_.Checks))"; Tone = $(if ($_.Score -ge 80) { 'good' } elseif ($_.Score -ge 60) { 'warn' } else { 'bad' }); Filter = $_.Pillar } }); Table = 'checks'; Column = 'Pillar' }
        @{ Title = 'Findings by source'; Items = @($Assessment.Findings | Group-Object Source | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Source'; Tone = 'warn' }
        if ($policy -and @($policy.ByNamespace).Count) { @{ Title = 'Policy violations by namespace'; Items = @($policy.ByNamespace | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Namespace; Value = $_.Violations; Filter = $_.Namespace } }); Table = 'policy-violations'; Column = 'Namespace'; Tone = 'warn' } }
        if ($policy -and @($policy.ByPolicy).Count) { @{ Title = 'Policy violations by policy'; Items = @($policy.ByPolicy | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Policy; Value = $_.Violations; Filter = $_.Policy } }); Table = 'policy-violations'; Column = 'Policy'; Tone = 'warn'; Wide = $true } }
    )
    $clusterColumns = @(
        & $col 'Name' 'Cluster' @{ Type = 'resource'; IdKey = 'ResourceId' }
        & $col 'High' 'High' @{ Type = 'number'; Tone = 'bad'; Sum = $true }
        & $col 'Medium' 'Medium' @{ Type = 'number'; Tone = 'warn'; Sum = $true }
        & $col 'Low' 'Low' @{ Type = 'number'; Sum = $true }
        & $col 'WafScore' 'WAF %' @{ Type = 'score' }
        & $col 'Reliability' 'Reliability' @{ Type = 'score' }
        & $col 'Security' 'Security' @{ Type = 'score' }
        & $col 'CostOptimization' 'Cost' @{ Type = 'score' }
        & $col 'OperationalExcellence' 'Operations' @{ Type = 'score' }
        & $col 'PerformanceEfficiency' 'Performance' @{ Type = 'score' }
        & $col 'Version' 'Version'
        & $col 'Support' 'Support' @{ Type = 'badge'; Tones = $support; Facet = $true }
        & $col 'Upgrade' 'Upgrade to'
        & $col 'Tier' 'Tier' $facet
        & $col 'Nodes' 'Nodes' @{ Type = 'number'; Sum = $true }
        & $col 'MaxNodes' 'Max nodes' $num
        & $col 'NodePools' 'Pools' $num
        & $col 'Network' 'Network' $facet
        & $col 'NetworkPolicy' 'Network policy' $facet
        & $col 'ApiServer' 'API server' $facet
        & $col 'LocalAccounts' 'Local accounts' @{ Type = 'badge'; Tones = $yesNo; Facet = $true }
        & $col 'AutoUpgrade' 'Upgrade channel' $facet
        & $col 'NodeOsUpgrade' 'Node OS channel' $facet
        & $col 'Monitoring' 'Monitoring'
        & $col 'PolicyViolations' 'Policy violations' @{ Type = 'number'; Sum = $true }
        & $col 'PSRuleFailed' 'PSRule failed' @{ Type = 'number'; Sum = $true }
        & $col 'PowerState' 'Power' $facet
        & $col 'Location' 'Location' $facet
        & $col 'ResourceGroup' 'Resource group' $facet
        & $col 'Subscription' 'Subscription' $facet
    )
    $nested = 'NodePools', 'Settings', 'Checks', 'Findings', 'Upgrades', 'PolicyViolations', 'PSRule'
    $tables = [System.Collections.Generic.List[hashtable]]::new()
    $add = { param([hashtable] $Table) if (@($Table.Rows).Count) { $tables.Add($Table) } }
    & $add @{ Id = 'clusters'; Section = 'Overview'; Title = 'Clusters'; Noun = 'clusters'; File = 'aks-clusters'; Rows = @($Assessment.Clusters | Select-Object -Property * -ExcludeProperty $nested); Columns = $clusterColumns; GroupBy = @('Subscription', 'Location', 'Support', 'Tier') }
    & $add @{
        Id = 'findings'; Section = 'Overview'; Title = 'Findings'; Note = 'Every lens: Well-Architected checks, PSRule for Azure, Advisor, Defender for Cloud, Azure Policy, retirements. Most severe first.'; Noun = 'findings'; File = 'aks-findings'; Rows = @($Assessment.Findings); GroupBy = @('Cluster', 'Pillar', 'Source', 'Severity')
        Columns = @((& $col 'Severity' 'Severity' @{ Type = 'badge'; Tones = $severity; Facet = $true }), (& $col 'Pillar' 'Pillar' $facet), (& $col 'Source' 'Source' $facet), (& $col 'Cluster' 'Cluster' @{ Type = 'resource'; IdKey = 'ClusterId'; Facet = $true }), (& $col 'Check' 'Finding' @{ Type = 'wide' }), (& $col 'Item' 'Item'), (& $col 'Detail' 'What was found' @{ Type = 'wide' }), (& $col 'Recommendation' 'What to do' @{ Type = 'wide' }), (& $col 'Link' 'Docs' @{ Type = 'link' }), (& $col 'ResourceGroup' 'Resource group' @{ Hidden = $true }))
    }
    & $add @{ Id = 'settings'; Section = 'Current settings'; Title = 'Settings'; Note = 'Every cluster setting that matters, by area.'; Noun = 'settings'; File = 'aks-settings'; Rows = @($Assessment.Settings); GroupBy = @('Cluster', 'Area'); Group = 'Area'; Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Area' 'Area' $facet), (& $col 'Setting' 'Setting'), (& $col 'Value' 'Value' @{ Type = 'wide' })) }
    & $add @{
        Id = 'nodepools'; Section = 'Current settings'; Title = 'Node pools'; Noun = 'pools'; File = 'aks-node-pools'; Rows = @($Assessment.NodePools); GroupBy = @('Cluster', 'Mode', 'VmSize', 'OsSku')
        Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Pool' 'Pool'), (& $col 'Mode' 'Mode' $facet), (& $col 'VmSize' 'Size' $facet), (& $col 'OsType' 'OS' $facet), (& $col 'OsSku' 'OS SKU' $facet), (& $col 'Nodes' 'Nodes' @{ Type = 'number'; Sum = $true }), (& $col 'Autoscale' 'Autoscale' @{ Type = 'badge'; Tones = @{ Yes = 'good'; No = 'warn' }; Facet = $true }), (& $col 'Min' 'Min' $num), (& $col 'Max' 'Max' $num), (& $col 'Zones' 'Zones' $facet), (& $col 'MaxPods' 'Max pods' $num), (& $col 'Version' 'Version' $facet), (& $col 'NodeImage' 'Node image'), (& $col 'NodeImageAge' 'Image age (days)' $num), (& $col 'LatestNodeImage' 'Newest image'), (& $col 'OsDiskType' 'OS disk' $facet), (& $col 'OsDiskGB' 'OS disk (GB)' $num), (& $col 'Priority' 'Priority' $facet), (& $col 'MaxSurge' 'Max surge'), (& $col 'Subnet' 'Subnet'), (& $col 'PodSubnet' 'Pod subnet'), (& $col 'PublicIp' 'Node public IP' @{ Type = 'badge'; Tones = @{ Yes = 'bad'; No = 'good' }; Facet = $true }), (& $col 'EncryptionAtHost' 'Encryption at host' $facet), (& $col 'Taints' 'Taints'), (& $col 'PowerState' 'Power' $facet))
    }
    & $add @{
        Id = 'upgrades'; Section = 'Current settings'; Title = 'Versions and upgrades'; Note = 'The control plane''s version and its support in the region, the upgrades available; each pool''s version and node image.'; Noun = 'rows'; File = 'aks-upgrades'; Rows = @($Assessment.Upgrades); GroupBy = @('Cluster', 'Support')
        Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Component' 'Component'), (& $col 'Current' 'Version'), (& $col 'Support' 'Support' @{ Type = 'badge'; Tones = $support; Facet = $true }), (& $col 'Behind' 'Minor versions behind' $num), (& $col 'Available' 'Upgrades available'), (& $col 'LatestMinor' 'Newest in region'), (& $col 'LatestPatch' 'Newest patch'), (& $col 'Channel' 'Channel' $facet), (& $col 'NodeImage' 'Node image'), (& $col 'NodeImageAge' 'Image age (days)' $num), (& $col 'LatestNodeImage' 'Newest image'))
    }
    & $add @{ Id = 'diagnostics'; Section = 'Current settings'; Title = 'Diagnostic settings'; Noun = 'settings'; File = 'aks-diagnostics'; Rows = @($Assessment.Diagnostics); Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Setting' 'Setting'), (& $col 'Workspace' 'Log Analytics'), (& $col 'Destination' 'Tables' $facet), (& $col 'Storage' 'Storage'), (& $col 'EventHub' 'Event hub'), (& $col 'Logs' 'Logs' @{ Type = 'wide' })) }
    & $add @{ Id = 'maintenance'; Section = 'Current settings'; Title = 'Maintenance windows'; Noun = 'windows'; File = 'aks-maintenance'; Rows = @($Assessment.Maintenance); Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Configuration' 'Configuration' $facet), (& $col 'Schedule' 'Schedule' @{ Type = 'wide' }), (& $col 'Duration' 'Duration'), (& $col 'Start' 'Start'), (& $col 'TimeZone' 'UTC offset')) }
    & $add @{ Id = 'pillars'; Section = 'Well-Architected'; Title = 'Pillars'; Noun = 'pillars'; File = 'aks-pillars'; Rows = @($Assessment.Pillars); Columns = @((& $col 'Pillar' 'Pillar'), (& $col 'Score' 'Score' @{ Type = 'score' }), (& $col 'Checks' 'Checks' $num), (& $col 'Passed' 'Passed' $num), (& $col 'Failed' 'Failed' @{ Type = 'number'; Tone = 'bad' }), (& $col 'PSRuleFailed' 'PSRule failed' $num), (& $col 'Findings' 'Findings' $num)) }
    & $add @{
        Id = 'checks'; Section = 'Well-Architected'; Title = 'Checks'; Note = 'Each Well-Architected check on each cluster, Pass or Fail, with what to do.'; Noun = 'checks'; File = 'aks-checks'; Rows = @($Assessment.Checks); GroupBy = @('Cluster', 'Pillar', 'Status'); Group = 'Pillar'
        Columns = @((& $col 'Status' 'Status' @{ Type = 'badge'; Tones = $passFail; Facet = $true }), (& $col 'Pillar' 'Pillar' $facet), (& $col 'Check' 'Check'), (& $col 'Severity' 'Severity' @{ Type = 'badge'; Tones = $severity; Facet = $true }), (& $col 'Cluster' 'Cluster' $facet), (& $col 'Detail' 'What was found' @{ Type = 'wide' }), (& $col 'Recommendation' 'What to do' @{ Type = 'wide' }), (& $col 'Link' 'Docs' @{ Type = 'link' }))
    }
    & $add @{
        Id = 'psrule'; Section = 'PSRule for Azure'; Title = 'PSRule for Azure'; Noun = 'results'; File = 'aks-psrule'; Rows = @($Assessment.PSRule); GroupBy = @('ResourceName', 'Pillar', 'Outcome', 'Severity')
        Columns = @((& $col 'Outcome' 'Outcome' @{ Type = 'badge'; Tones = @{ Pass = 'good'; Fail = 'bad'; Error = 'warn' }; Facet = $true }), (& $col 'Pillar' 'Pillar' $facet), (& $col 'RuleName' 'Rule'), (& $col 'Title' 'Title' @{ Type = 'wide' }), (& $col 'Severity' 'Severity' $facet), (& $col 'ResourceName' 'Cluster' $facet), (& $col 'Reason' 'Reason' @{ Type = 'wide' }), (& $col 'Recommendation' 'Recommendation' @{ Type = 'wide' }), (& $col 'Link' 'Docs' @{ Type = 'link' }))
    }
    if ($policy) {
        $note = 'Azure Policy for Kubernetes, one view: as the AKS Policy Compliance Toolkit consolidates it.'
        & $add @{ Id = 'policy-namespace'; Section = 'Azure Policy'; Title = 'By namespace'; Note = $note; Noun = 'namespaces'; File = 'aks-policy-by-namespace'; Rows = @($policy.ByNamespace); Columns = @((& $col 'Namespace' 'Namespace'), (& $col 'Violations' 'Violations' @{ Type = 'number'; Sum = $true }), (& $col 'Workloads' 'Workloads' $num), (& $col 'Policies' 'Policies' $num), (& $col 'Deny' 'Under Deny' @{ Type = 'number'; Tone = 'bad' }), (& $col 'Clusters' 'Clusters'), (& $col 'PolicyNames' 'Policies violated' @{ Type = 'wide' })) }
        & $add @{ Id = 'policy-workload'; Section = 'Azure Policy'; Title = 'By workload'; Noun = 'workloads'; File = 'aks-policy-by-workload'; Rows = @($policy.ByWorkload); GroupBy = @('Cluster', 'Namespace', 'WorkloadKind'); Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Namespace' 'Namespace' $facet), (& $col 'WorkloadKind' 'Kind' $facet), (& $col 'Workload' 'Workload'), (& $col 'Violations' 'Violations' @{ Type = 'number'; Sum = $true }), (& $col 'Components' 'Components' $num), (& $col 'Policies' 'Policies' $num), (& $col 'Deny' 'Under Deny' @{ Type = 'number'; Tone = 'bad' }), (& $col 'PolicyNames' 'Policies violated' @{ Type = 'wide' })) }
        & $add @{ Id = 'policy-policy'; Section = 'Azure Policy'; Title = 'By policy'; Noun = 'policies'; File = 'aks-policy-by-policy'; Rows = @($policy.ByPolicy); Columns = @((& $col 'Policy' 'Policy' @{ Type = 'wide' }), (& $col 'Effect' 'Effect' @{ Type = 'badge'; Tones = $effect; Facet = $true }), (& $col 'Violations' 'Violations' @{ Type = 'number'; Sum = $true }), (& $col 'Clusters' 'Clusters' $num), (& $col 'Namespaces' 'Namespaces' $num), (& $col 'Workloads' 'Workloads' $num), (& $col 'Assignment' 'Assignment'), (& $col 'Initiative' 'Initiative')) }
        & $add @{ Id = 'policy-cluster'; Section = 'Azure Policy'; Title = 'By cluster and policy'; Note = 'Capped: Azure Policy keeps 500 non-compliant records per policy and cluster - run with -IncludeConstraint for Gatekeeper''s complete counts.'; Noun = 'rows'; File = 'aks-policy-by-cluster'; Rows = @($policy.ByCluster | Select-Object -Property *, @{ Name = 'CappedText'; Expression = { if ($_.Capped) { 'Yes' } else { 'No' } } }); GroupBy = @('Cluster'); Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Policy' 'Policy' @{ Type = 'wide' }), (& $col 'Effect' 'Effect' @{ Type = 'badge'; Tones = $effect; Facet = $true }), (& $col 'Violations' 'Violations' @{ Type = 'number'; Sum = $true }), (& $col 'Namespaces' 'Namespaces' $num), (& $col 'Workloads' 'Workloads' $num), (& $col 'CappedText' 'Capped' @{ Type = 'badge'; Tones = @{ Yes = 'warn'; No = 'neutral' }; Facet = $true })) }
        & $add @{ Id = 'policy-violations'; Section = 'Azure Policy'; Title = 'Every non-compliant component'; Note = 'The workload is inferred from the pod''s name (a Deployment''s ReplicaSet hash, a CronJob''s schedule, a StatefulSet''s ordinal).'; Noun = 'components'; File = 'aks-policy-violations'; Rows = @($policy.Components); GroupBy = @('Cluster', 'Namespace', 'Workload', 'Policy'); Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Namespace' 'Namespace' $facet), (& $col 'WorkloadKind' 'Kind' $facet), (& $col 'Workload' 'Workload'), (& $col 'ObjectKind' 'Object' $facet), (& $col 'Component' 'Component'), (& $col 'Policy' 'Policy' @{ Type = 'wide'; Facet = $true }), (& $col 'Effect' 'Effect' @{ Type = 'badge'; Tones = $effect; Facet = $true }), (& $col 'Assignment' 'Assignment' $facet), (& $col 'Initiative' 'Initiative' $facet), (& $col 'LastEvaluated' 'Evaluated' @{ Type = 'datetime' }), (& $col 'Subscription' 'Subscription' @{ Hidden = $true })) }
        & $add @{ Id = 'policy-states'; Section = 'Azure Policy'; Title = 'Policies on the clusters'; Note = 'Every policy evaluated on each cluster resource. Scope Workloads: a Kubernetes policy, whose components are in the views above.'; Noun = 'states'; File = 'aks-policy-states'; Rows = @($policy.ClusterStates); GroupBy = @('Cluster', 'State', 'Scope'); Columns = @((& $col 'State' 'State' @{ Type = 'badge'; Tones = @{ Compliant = 'good'; NonCompliant = 'bad'; Exempt = 'neutral' }; Facet = $true }), (& $col 'Cluster' 'Cluster' $facet), (& $col 'Policy' 'Policy' @{ Type = 'wide' }), (& $col 'Scope' 'Scope' $facet), (& $col 'Effect' 'Effect' @{ Type = 'badge'; Tones = $effect; Facet = $true }), (& $col 'Assignment' 'Assignment' $facet), (& $col 'Initiative' 'Initiative' $facet), (& $col 'Evaluated' 'Evaluated' @{ Type = 'datetime' })) }
        & $add @{ Id = 'policy-assignments'; Section = 'Azure Policy'; Title = 'Assignments'; Noun = 'assignments'; File = 'aks-policy-assignments'; Rows = @($policy.Assignments); Columns = @((& $col 'Assignment' 'Assignment'), (& $col 'Scope' 'Scope' @{ Type = 'mono' }), (& $col 'EnforcementMode' 'Enforcement' @{ Type = 'badge'; Tones = @{ Default = 'good'; DoNotEnforce = 'warn' }; Facet = $true }), (& $col 'Effect' 'Effect' $facet), (& $col 'Policies' 'Policies' $num), (& $col 'NonCompliant' 'Non-compliant' @{ Type = 'number'; Tone = 'bad' }), (& $col 'Clusters' 'Clusters' $num), (& $col 'Violations' 'Violations' $num)) }
    }
    & $add @{ Id = 'gatekeeper'; Section = 'Azure Policy'; Title = 'Gatekeeper constraints (in the clusters)'; Note = 'Complete counts from Gatekeeper, beyond Azure Policy''s 500-record cap. dryrun is Audit.'; Noun = 'constraints'; File = 'aks-gatekeeper'; Rows = @($Assessment.Constraints); Columns = @((& $col 'Cluster' 'Cluster' $facet), (& $col 'Kind' 'Constraint kind'), (& $col 'Constraint' 'Constraint'), (& $col 'Action' 'Action' @{ Type = 'badge'; Tones = $effect; Facet = $true }), (& $col 'TotalViolations' 'Violations' @{ Type = 'number'; Sum = $true }), (& $col 'Assignment' 'Assignment' $facet), (& $col 'ReferenceId' 'Reference')) }

    $notices = @(foreach ($line in @($Assessment['Notices'])) { @{ Tone = 'warn'; Text = $line } })
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'AKS clusters through every lens: settings, Well-Architected, PSRule, Azure Policy, versions, Advisor and Defender' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables.ToArray() -Notice $notices
}
