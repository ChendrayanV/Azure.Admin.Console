function ConvertTo-AACAksPolicyCompliance {
    <#
    .SYNOPSIS
        Consolidates Azure Policy for Kubernetes compliance into one view -
        by namespace, workload, policy and cluster - the way the AKS Policy
        Compliance Toolkit (github.com/sam-cogan/aks-policy-compliance-toolkit)
        does, for Invoke-AACAksAssessment.
    .DESCRIPTION
        In the portal, Kubernetes policy compliance is read one policy at a
        time, then per cluster, then per component. This puts the
        non-compliant components (pods, services, network policies, ...) of
        every cluster side by side:
          Components   one row per non-compliant component and policy: its
                       cluster, namespace, workload (inferred from the pod's
                       name: a Deployment's ReplicaSet hash, a CronJob's
                       schedule suffix, a StatefulSet's ordinal, a
                       DaemonSet's or Job's suffix), policy, effect,
                       assignment and initiative
          ByNamespace  per namespace (team or tenant): violations, workloads,
                       policies, clusters, how many under Deny
          ByWorkload   per cluster, namespace and workload
          ByPolicy     per policy: violations, clusters, namespaces, workloads
          ByCluster    per cluster and policy - Capped where Azure Policy's
                       limit of 500 non-compliant records per policy and
                       cluster was reached (the in-cluster counts are complete)
          ClusterStates  every policy evaluated on each cluster resource
                       itself (Compliant or NonCompliant), with its effect
          Assignments  the assignments that reach the clusters: scope,
                       enforcement mode, effect, policies, non-compliant ones
        Effect: 'audit (DoNotEnforce)' when the assignment doesn't enforce,
        else the effect the cluster's policy state reports, else the
        assignment's effect parameter, else 'unresolved'.
        System namespaces (kube-system, gatekeeper-system, azure-arc,
        azure-extensions-usage-system, flux-system, ...) are left out unless
        -IncludeSystemNamespace.

        Rows are Resource Graph rows (Get-AACAksQuery); -DefinitionName maps
        a policy or initiative definition ID (lower case) to its display name.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $Component = @(),
        [AllowEmptyCollection()] [object[]] $ClusterState = @(),
        [AllowEmptyCollection()] [object[]] $Assignment = @(),
        [hashtable] $DefinitionName = @{},
        # Cluster ID (lower case) -> name; only these clusters are kept when given.
        [hashtable] $ClusterName = @{},
        [hashtable] $SubscriptionName = @{},
        [switch] $IncludeSystemNamespace,
        [string[]] $SystemNamespace = @('kube-system', 'gatekeeper-system', 'azure-arc', 'azure-extensions-usage-system', 'flux-system', 'kube-public', 'kube-node-lease', 'calico-system', 'tigera-operator', 'aks-command', 'app-routing-system', 'aks-istio-system', 'kube-egress-gateway-system', 'dapr-system')
    )

    $value = { param($Row, [string] $Key) if ($Row -is [System.Collections.IDictionary]) { if ($Row.Contains($Key)) { $Row[$Key] } } elseif ($null -ne $Row) { Get-AACPropertyValue -InputObject $Row -Name $Key } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) if ($Id) { ([string]$Id).TrimEnd('/') -replace '^.*/', '' } else { '' } }
    $clusterOf = { param([string] $Id) $key = & $lower $Id; if ($ClusterName.Contains($key)) { $ClusterName[$key] } elseif ($Id -match '(?i)/managedclusters/([^/]+)') { $Matches[1] } else { $Id } }
    $keep = { param([string] $Id) -not $ClusterName.Count -or $ClusterName.Contains((& $lower $Id)) }
    $nameOf = { param([string] $Id) $key = & $lower $Id; if ($key -and $DefinitionName.Contains($key) -and $DefinitionName[$key]) { [string]$DefinitionName[$key] } else { '' } }
    $object = { param([string] $TypeName, [System.Collections.IDictionary] $Property) $item = [pscustomobject]$Property; $item.PSObject.TypeNames.Insert(0, $TypeName); $item }

    # --- Assignments and the effect each cluster's policy state reports -----------------------------------------------
    $assignments = @{}
    foreach ($row in $Assignment) { $assignments[(& $lower (& $value $row 'assignmentId'))] = $row }
    $stateEffect = @{}
    foreach ($row in $ClusterState) {
        $key = "$(& $lower (& $value $row 'clusterId'))|$(& $lower (& $value $row 'assignmentId'))|$(& $lower (& $value $row 'refId'))"
        $effect = [string](& $value $row 'effect')
        if ($effect) { $stateEffect[$key] = $effect }
    }
    $effectOf = {
        param([string] $ClusterId, [string] $AssignmentId, [string] $RefId)
        $row = $assignments[(& $lower $AssignmentId)]
        if ($row -and [string](& $value $row 'enforcementMode') -eq 'DoNotEnforce') { return 'audit (DoNotEnforce)' }
        $key = "$(& $lower $ClusterId)|$(& $lower $AssignmentId)|$(& $lower $RefId)"
        if ($stateEffect.Contains($key)) { return ([string]$stateEffect[$key]).ToLowerInvariant() }
        if ($row -and (& $value $row 'effect')) { return ([string](& $value $row 'effect')).ToLowerInvariant() }
        'unresolved'
    }
    $assignmentName = { param([string] $Id) $row = $assignments[(& $lower $Id)]; if ($row -and (& $value $row 'displayName')) { [string](& $value $row 'displayName') } else { & $leaf $Id } }

    # --- The non-compliant components ----------------------------------------------------------------------------
    # Pod names: <deployment>-<replicaset hash>-<pod hash>, <cronjob>-<schedule time>-<hash>,
    # <statefulset>-<ordinal>, <daemonset or job>-<hash>.
    $safe = '[bcdfghjklmnpqrstvwxz2456789]'
    $system = [System.Collections.Generic.HashSet[string]]::new([string[]]@($SystemNamespace), [System.StringComparer]::OrdinalIgnoreCase)
    $components = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $Component) {
        $clusterId = [string](& $value $row 'clusterId')
        if (-not (& $keep $clusterId)) { continue }
        $componentId = [string](& $value $row 'componentId')
        $kind = [string](& $value $row 'componentType')
        $namespace = if ($componentId.Contains('/')) { ($componentId -split '/', 2)[0] } else { '(cluster-scoped)' }
        if (-not $IncludeSystemNamespace -and $system.Contains($namespace)) { continue }
        $name = if ($componentId.Contains('/')) { ($componentId -split '/', 2)[1] } else { $componentId }
        $workload = $name; $workloadKind = if ($kind) { $kind } else { 'Component' }
        if ($kind -eq 'pod') {
            if ($name -match "^(.+)-[0-9]{8,}-$safe{5}$") { $workload = $Matches[1]; $workloadKind = 'CronJob' }
            elseif ($name -match "^(.+)-$safe{5,10}-$safe{5}$") { $workload = $Matches[1]; $workloadKind = 'Deployment' }
            elseif ($name -match '^(.+)-[0-9]{1,3}$') { $workload = $Matches[1]; $workloadKind = 'StatefulSet' }
            elseif ($name -match "^(.+)-$safe{5}$") { $workload = $Matches[1]; $workloadKind = 'DaemonSet / Job' }
            else { $workloadKind = 'Pod' }
        }
        $definitionId = [string](& $value $row 'definitionId')
        $refId = [string](& $value $row 'refId')
        $policy = @((& $nameOf $definitionId), $refId, (& $leaf $definitionId)) | Where-Object { $_ } | Select-Object -First 1
        $setId = [string](& $value $row 'setId')
        $assignmentId = [string](& $value $row 'assignmentId')
        $subscription = if ($clusterId -match '^/subscriptions/([^/]+)') { $Matches[1].ToLowerInvariant() } else { '' }
        $components.Add((& $object 'AAC.AksPolicyViolation' ([ordered]@{
                        Cluster       = & $clusterOf $clusterId
                        Namespace     = $namespace
                        WorkloadKind  = $workloadKind
                        Workload      = $workload
                        ObjectKind    = $kind
                        Component     = $name
                        Policy        = [string]$policy
                        Effect        = & $effectOf $clusterId $assignmentId $refId
                        Assignment    = & $assignmentName $assignmentId
                        Initiative    = $(if ($setId) { @((& $nameOf $setId), (& $leaf $setId)) | Where-Object { $_ } | Select-Object -First 1 } else { '' })
                        LastEvaluated = [string](& $value $row 'evaluated')
                        Subscription  = $(if ($SubscriptionName.Contains($subscription)) { $SubscriptionName[$subscription] } else { $subscription })
                        ClusterId     = $clusterId
                        PolicyId      = $definitionId
                    })))
    }
    $isDeny = { param($Effect) [string]$Effect -eq 'deny' }
    $joinTop = { param([object[]] $Values, [int] $Top) $distinct = @($Values | Where-Object { $_ } | Sort-Object -Unique); ((@($distinct | Select-Object -First $Top)) -join ', ') + $(if ($distinct.Count -gt $Top) { ", +$($distinct.Count - $Top)" } else { '' }) }

    $byNamespace = @(foreach ($group in $components | Group-Object Namespace) {
            & $object 'AAC.AksPolicyNamespace' ([ordered]@{
                    Namespace  = $group.Name
                    Violations = $group.Count
                    Workloads  = @($group.Group | ForEach-Object { "$($_.Cluster)/$($_.Workload)" } | Sort-Object -Unique).Count
                    Policies   = @($group.Group | ForEach-Object Policy | Sort-Object -Unique).Count
                    Deny       = @($group.Group | Where-Object { & $isDeny $_.Effect }).Count
                    Clusters   = & $joinTop @($group.Group | ForEach-Object Cluster) 20
                    PolicyNames = & $joinTop @($group.Group | ForEach-Object Policy) 50
                })
        }) | Sort-Object -Property @{ Expression = 'Violations'; Descending = $true }, Namespace
    $byWorkload = @(foreach ($group in $components | Group-Object Cluster, Namespace, Workload) {
            $first = $group.Group[0]
            & $object 'AAC.AksPolicyWorkload' ([ordered]@{
                    Cluster      = $first.Cluster
                    Namespace    = $first.Namespace
                    WorkloadKind = $first.WorkloadKind
                    Workload     = $first.Workload
                    Violations   = $group.Count
                    Components   = @($group.Group | ForEach-Object Component | Sort-Object -Unique).Count
                    Policies     = @($group.Group | ForEach-Object Policy | Sort-Object -Unique).Count
                    Deny         = @($group.Group | Where-Object { & $isDeny $_.Effect }).Count
                    PolicyNames  = & $joinTop @($group.Group | ForEach-Object Policy) 50
                })
        }) | Sort-Object -Property @{ Expression = 'Violations'; Descending = $true }, Cluster, Namespace, Workload
    $byPolicy = @(foreach ($group in $components | Group-Object Policy) {
            & $object 'AAC.AksPolicySummary' ([ordered]@{
                    Policy     = $group.Name
                    Effect     = & $joinTop @($group.Group | ForEach-Object Effect) 5
                    Violations = $group.Count
                    Clusters   = @($group.Group | ForEach-Object Cluster | Sort-Object -Unique).Count
                    Namespaces = @($group.Group | ForEach-Object Namespace | Sort-Object -Unique).Count
                    Workloads  = @($group.Group | ForEach-Object { "$($_.Cluster)/$($_.Namespace)/$($_.Workload)" } | Sort-Object -Unique).Count
                    Assignment = & $joinTop @($group.Group | ForEach-Object Assignment) 5
                    Initiative = & $joinTop @($group.Group | ForEach-Object Initiative) 5
                })
        }) | Sort-Object -Property @{ Expression = 'Violations'; Descending = $true }, Policy
    $byCluster = @(foreach ($group in $components | Group-Object Cluster, Policy) {
            $first = $group.Group[0]
            & $object 'AAC.AksPolicyCluster' ([ordered]@{
                    Cluster    = $first.Cluster
                    Policy     = $first.Policy
                    Effect     = & $joinTop @($group.Group | ForEach-Object Effect) 5
                    Violations = $group.Count
                    Namespaces = @($group.Group | ForEach-Object Namespace | Sort-Object -Unique).Count
                    Workloads  = @($group.Group | ForEach-Object { "$($_.Namespace)/$($_.Workload)" } | Sort-Object -Unique).Count
                    # Azure Policy keeps 500 non-compliant records per policy and cluster (system namespaces included).
                    Capped     = $group.Count -ge 500
                    ClusterId  = $first.ClusterId
                })
        }) | Sort-Object -Property @{ Expression = 'Violations'; Descending = $true }, Cluster, Policy

    # --- The policies evaluated on each cluster resource ----------------------------------------------------------------
    # A policy with non-compliant components is a Kubernetes (workload) policy.
    $workloadPolicies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $components) { if ($item.PolicyId) { [void]$workloadPolicies.Add($item.PolicyId) } }
    $clusterStates = @(foreach ($row in $ClusterState) {
            $clusterId = [string](& $value $row 'clusterId')
            if (-not (& $keep $clusterId)) { continue }
            $definitionId = [string](& $value $row 'definitionId')
            $setId = [string](& $value $row 'setId')
            $assignmentId = [string](& $value $row 'assignmentId')
            & $object 'AAC.AksPolicyState' ([ordered]@{
                    Cluster    = & $clusterOf $clusterId
                    State      = [string](& $value $row 'state')
                    Policy     = [string](@((& $nameOf $definitionId), [string](& $value $row 'refId'), (& $leaf $definitionId)) | Where-Object { $_ } | Select-Object -First 1)
                    Effect     = & $effectOf $clusterId $assignmentId ([string](& $value $row 'refId'))
                    Assignment = & $assignmentName $assignmentId
                    Initiative = $(if ($setId) { [string](@((& $nameOf $setId), (& $leaf $setId)) | Where-Object { $_ } | Select-Object -First 1) } else { '' })
                    Scope      = $(if ($workloadPolicies.Contains($definitionId)) { 'Workloads' } else { 'Cluster' })
                    Evaluated  = [string](& $value $row 'evaluated')
                    ClusterId  = $clusterId
                    AssignmentId = $assignmentId
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.State -eq 'NonCompliant') { 0 } else { 1 } } }, Cluster, Policy

    # --- The assignments that reach the clusters ------------------------------------------------------------------------
    $assignmentRows = @(foreach ($group in $clusterStates | Group-Object { & $lower $_.AssignmentId }) {
            $row = $assignments[$group.Name]
            & $object 'AAC.AksPolicyAssignment' ([ordered]@{
                    Assignment      = $group.Group[0].Assignment
                    Scope           = [string](& $value $row 'scope')
                    EnforcementMode = $(if ($row) { [string](& $value $row 'enforcementMode') } else { '' })
                    Effect          = $(if ($row) { [string](& $value $row 'effect') } else { '' })
                    Policies        = @($group.Group | ForEach-Object Policy | Sort-Object -Unique).Count
                    NonCompliant    = @($group.Group | Where-Object State -EQ 'NonCompliant' | ForEach-Object Policy | Sort-Object -Unique).Count
                    Clusters        = @($group.Group | ForEach-Object Cluster | Sort-Object -Unique).Count
                    Violations      = @($components | Where-Object { $_.Assignment -eq $group.Group[0].Assignment }).Count
                    AssignmentId    = $group.Group[0].AssignmentId
                })
        }) | Sort-Object -Property @{ Expression = 'NonCompliant'; Descending = $true }, Assignment

    @{
        Components    = $components.ToArray()
        ByNamespace   = @($byNamespace)
        ByWorkload    = @($byWorkload)
        ByPolicy      = @($byPolicy)
        ByCluster     = @($byCluster)
        ClusterStates = @($clusterStates)
        Assignments   = @($assignmentRows)
        Stats         = [ordered]@{
            Violations            = $components.Count
            Namespaces            = @($byNamespace).Count
            Workloads             = @($byWorkload).Count
            Policies              = @($byPolicy).Count
            Deny                  = @($components | Where-Object { & $isDeny $_.Effect }).Count
            Capped                = @($byCluster | Where-Object Capped).Count
            ClusterPolicies       = @($clusterStates).Count
            NonCompliantPolicies  = @($clusterStates | Where-Object State -EQ 'NonCompliant').Count
            Assignments           = @($assignmentRows).Count
        }
    }
}
