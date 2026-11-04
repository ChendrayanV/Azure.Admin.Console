function ConvertTo-AACAksWorkload {
    <#
    .SYNOPSIS
        Assesses what runs inside one AKS cluster, from Get-AACAksWorkload's read,
        and how ready it is to move to a new AKS Automatic cluster.
    .DESCRIPTION
        No Azure calls. Many of the checks follow KubeBuddy's Kubernetes checks
        (github.com/KubeDeckio/KubeBuddy). They are kept apart from the
        Well-Architected checks, and not in that score: a score must not depend
        on whether -IncludeWorkload was used.

        A check has Status Pass, Fail, or Not checked when part of what it needs
        couldn't be read (refused, or past run command's 512 kB). What could be
        read still fails it, but nothing passes on the strength of a gap.

        Pods of a workload share one row, so a finding is about the workload as
        its first pod shows it. An image's own USER can't be seen from here, so
        'may run as root' means nothing rules it out.

        Readiness is from Microsoft's Deployment Safeguards and baseline Pod
        Security Standards, which AKS Automatic turns on in Enforce: 'Fix first'
        would be refused, 'Changed by Automatic' would be admitted but altered
        (default requests, added anti-affinity), and 'Review' needs a look. It is
        about moving workloads to a new cluster, not converting this one.

        Returns @{ Checks (AAC.AksWorkloadCheck); Items (AAC.AksWorkloadItem: what
        each check found, one row per workload or object); Readiness
        (AAC.AksAutomaticReadiness) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [string] $ClusterName,

        [string] $ClusterId = '',

        [string] $ClusterSku = '',

        [switch] $IncludeSystemNamespace,

        [string[]] $SystemNamespace = @(Get-AACAksSystemNamespace)
    )

    $k8s = 'https://kubernetes.io/docs'
    $aks = 'https://learn.microsoft.com/azure/aks'
    $safeguards = "$aks/deployment-safeguards"
    $podSecurity = "$k8s/concepts/security/pod-security-standards/"
    $system = [System.Collections.Generic.HashSet[string]]::new([string[]]@($SystemNamespace), [System.StringComparer]::OrdinalIgnoreCase)
    $inScope = { param($Namespace) $IncludeSystemNamespace -or -not $Namespace -or -not $system.Contains([string]$Namespace) }
    $rowsOf = { param([string] $Type) @($Read.Rows | Where-Object { $_['t'] -eq $Type }) }
    $scoped = { param([string] $Type) @(& $rowsOf $Type | Where-Object { & $inScope $_['ns'] }) }
    $podRows = @(& $scoped 'pod')
    $workloadRows = @(& $scoped 'workload')
    $services = @(& $scoped 'svc')
    $pdbs = @(& $scoped 'pdb')
    $namespaces = @(& $rowsOf 'ns' | Where-Object { & $inScope $_['name'] })
    $kindOf = { param($Pod) if ($Pod['ok']) { [string]$Pod['ok'] } else { 'Pod' } }

    $checks = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()
    # One check: what it needs read, and what it found (@{ Namespace; Kind; Name; Detail }).
    $record = {
        param([string] $Area, [string] $Pillar, [string] $Check, [string] $Severity, [string[]] $Needs, [object[]] $Found, [string] $Action, [string] $Link, [string] $Readiness = '')
        $gaps = @($Needs | Where-Object { $_ -in @($Read.Unread) })
        $names = @($Found | ForEach-Object { if ($_.Namespace) { "$($_.Namespace)/$($_.Name)" } else { $_.Name } })
        $status = if ($names.Count) { 'Fail' } elseif ($gaps.Count) { 'Not checked' } else { 'Pass' }
        $shown = ($names | Select-Object -First 5) -join ', '
        $detail = switch ($status) {
            'Fail' { "$($names.Count) found: $shown$(if ($names.Count -gt 5) { ', ...' })$(if ($gaps.Count) { " There may be more: $($gaps -join ', ') couldn't be fully read." })" }
            'Not checked' { "$($gaps -join ', ') couldn't be fully read." }
            default { 'None found.' }
        }
        $checks.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.AksWorkloadCheck'; Cluster = $ClusterName; Area = $Area; Pillar = $Pillar; Check = $Check; Severity = $Severity; Status = $status; Affected = $names.Count; Readiness = $Readiness; Detail = $detail; Recommendation = $Action; Link = $Link; ClusterId = $ClusterId })
        foreach ($hit in $Found) {
            $items.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.AksWorkloadItem'; Cluster = $ClusterName; Area = $Area; Check = $Check; Severity = $Severity; Namespace = [string]$hit.Namespace; Kind = [string]$hit.Kind; Name = [string]$hit.Name; Detail = [string]$hit.Detail; Readiness = $Readiness; ClusterId = $ClusterId })
        }
    }
    $hit = { param([string] $Namespace, [string] $Kind, [string] $Name, [string] $Detail = '') [pscustomobject]@{ Namespace = $Namespace; Kind = $Kind; Name = $Name; Detail = $Detail } }
    # The workloads with a container that fails a test. -Init takes in init containers, which security rules also apply to.
    $byContainer = {
        param([scriptblock] $Test, [switch] $Init)
        foreach ($pod in $podRows) {
            $bad = @(foreach ($c in @($pod['c'])) { if ($c -and ($Init -or -not $c['init'])) { $why = & $Test $c $pod; if ($why) { "$($c['n']): $why" } } })
            if ($bad.Count) { & $hit $pod['ns'] (& $kindOf $pod) $pod['on'] ($bad -join '; ') }
        }
    }
    $byPod = {
        param([scriptblock] $Test)
        foreach ($pod in $podRows) { $why = & $Test $pod; if ($why) { & $hit $pod['ns'] (& $kindOf $pod) $pod['on'] ([string]$why) } }
    }
    # A setting on the container wins over the pod's.
    $effective = { param($Container, $Pod, [string] $Key) if ($null -ne $Container[$Key]) { $Container[$Key] } elseif ($Pod['ps']) { $Pod['ps'][$Key] } }
    $replicated = @($workloadRows | Where-Object { $_['kind'] -in 'Deployment', 'StatefulSet' -and [int]$_['want'] -gt 1 })
    $podOf = { param($Row) $podRows | Where-Object { $_['ns'] -eq $Row['ns'] -and $_['ok'] -eq $Row['kind'] -and $_['on'] -eq $Row['name'] } | Select-Object -First 1 }
    $selects = { param($Selector, $Labels) $Selector -and $Labels -and @($Selector.Keys).Count -and -not @($Selector.Keys | Where-Object { [string]$Labels[$_] -ne [string]$Selector[$_] }).Count }

    # --- Health ------------------------------------------------------------------------------------------------------------
    $broken = 'CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull', 'CreateContainerConfigError', 'CreateContainerError', 'InvalidImageName', 'RunContainerError'
    & $record 'Health' 'Reliability' 'Containers failing to start or run' 'High' 'pods' @(& $byPod { param($Pod) $reasons = @($Pod['wt'] | Where-Object { $_ -in $broken }); if ($reasons.Count) { $reasons -join ', ' } }) 'Read the pod''s events and logs: kubectl describe pod, kubectl logs --previous.' "$k8s/tasks/debug/debug-application/debug-pods/"
    & $record 'Health' 'Reliability' 'Failed pods' 'High' 'pods' @(& $byPod { param($Pod) if ($Pod['ph'] -and $Pod['ph']['Failed']) { "$($Pod['ph']['Failed']) failed" } }) 'Find out why they failed, then delete them: failed pods stay until something removes them.' "$k8s/tasks/debug/debug-application/debug-pods/"
    & $record 'Health' 'Reliability' 'Pending pods' 'Medium' 'pods' @(& $byPod { param($Pod) if ($Pod['ph'] -and $Pod['ph']['Pending']) { "$($Pod['ph']['Pending']) pending" } }) 'Check the pods'' events: not enough capacity, a taint, or a volume that won''t attach.' "$k8s/tasks/debug/debug-application/debug-pods/"
    & $record 'Health' 'Reliability' 'Containers killed for memory' 'High' 'pods' @(& $byPod { param($Pod) if ($Pod['oom']) { 'last ended OOMKilled' } }) 'Raise the memory limit, or find the leak.' "$k8s/tasks/configure-pod-container/assign-memory-resource/"
    & $record 'Health' 'Reliability' 'Containers restarting often' 'Medium' 'pods' @(& $byPod { param($Pod) if ([int]$Pod['rs'] -ge 10) { "$($Pod['rs']) restarts" } }) 'Look at why they restart: kubectl logs --previous.' "$k8s/tasks/debug/debug-application/debug-pods/"
    & $record 'Health' 'Reliability' 'Workloads short of replicas' 'Medium' 'deployments,statefulsets,daemonsets' @(foreach ($row in $workloadRows) { if ([int]$row['ready'] -lt [int]$row['want']) { & $hit $row['ns'] $row['kind'] $row['name'] "$([int]$row['ready']) of $([int]$row['want']) ready" } }) 'Look at the pods of each one: a stuck rollout, or nodes it can''t be placed on.' "$k8s/concepts/workloads/controllers/deployment/#failed-deployment"
    & $record 'Health' 'Reliability' 'Nodes not ready' 'High' 'nodes' @(foreach ($row in (& $rowsOf 'node')) { if (-not $row['ready']) { & $hit '' 'Node' $row['name'] } }) 'Check the node''s conditions and Resource Health. AKS node auto-repair handles most cases.' "$aks/node-auto-repair"
    & $record 'Health' 'Reliability' 'Nodes under pressure' 'Medium' 'nodes' @(foreach ($row in (& $rowsOf 'node')) { if (@($row['press']).Count -and @($row['press'])[0]) { & $hit '' 'Node' $row['name'] (@($row['press']) -join ', ') } }) 'Pods get evicted from a node under pressure: set requests and limits, or add capacity.' "$k8s/concepts/scheduling-eviction/node-pressure-eviction/"
    $endpointRows = @(& $rowsOf 'ep')
    & $record 'Health' 'Reliability' 'Services with no ready endpoints' 'Medium' 'services', 'endpoints' @(foreach ($row in $services) { if ($row['sel'] -and @($row['sel'].Keys).Count) { $ep = $endpointRows | Where-Object { $_['ns'] -eq $row['ns'] -and $_['name'] -eq $row['name'] } | Select-Object -First 1; if (-not $ep -or -not $ep['up']) { & $hit $row['ns'] 'Service' $row['name'] } } }) 'Check the selector matches the pods, and that they are ready.' "$k8s/tasks/debug/debug-application/debug-service/"
    & $record 'Health' 'Reliability' 'Persistent volume claims not bound' 'Medium' 'persistentvolumeclaims' @(foreach ($row in (& $scoped 'pvc')) { if ($row['ph'] -ne 'Bound') { & $hit $row['ns'] 'PersistentVolumeClaim' $row['name'] ([string]$row['ph']) } }) 'Check the claim''s events and its storage class.' "$aks/concepts-storage"
    & $record 'Health' 'Reliability' 'Autoscalers with no target' 'High' 'horizontalpodautoscalers', 'deployments,statefulsets,daemonsets' @(foreach ($row in (& $scoped 'hpa')) { if ($row['tk'] -in 'Deployment', 'StatefulSet' -and -not @($workloadRows | Where-Object { $_['ns'] -eq $row['ns'] -and $_['kind'] -eq $row['tk'] -and $_['name'] -eq $row['tn'] }).Count) { & $hit $row['ns'] 'HorizontalPodAutoscaler' $row['name'] "$($row['tk'])/$($row['tn']) doesn't exist" } }) 'Point it at the workload, or delete it.' "$k8s/tasks/run-application/horizontal-pod-autoscale/"

    # --- Workload design -----------------------------------------------------------------------------------------------------
    & $record 'Workload design' 'Performance Efficiency' 'Resource requests' 'Medium' 'pods' @(& $byContainer { param($C) $gone = @(if (-not $C['rc']) { 'CPU' }; if (-not $C['rm']) { 'memory' }); if ($gone.Count) { "no $($gone -join ' or ') request" } }) 'Set CPU and memory requests, so pods are placed on nodes that can hold them. AKS Automatic gives pods without them 500m CPU and 2 GiB, which may not suit them.' "$aks/developer-best-practices-resource-management" 'Changed by Automatic'
    & $record 'Workload design' 'Reliability' 'Memory limits' 'Low' 'pods' @(& $byContainer { param($C) if (-not $C['lm']) { 'no memory limit' } }) 'Set a memory limit, so one container can''t take a node''s memory from the others.' "$aks/developer-best-practices-resource-management"
    & $record 'Workload design' 'Reliability' 'Readiness and liveness probes' 'Medium' 'pods' @(& $byPod { param($Pod) if ((& $kindOf $Pod) -notin 'CronJob', 'Job') { $bad = @(foreach ($c in @($Pod['c'])) { if ($c -and -not $c['init'] -and -not ($c['rp'] -and $c['lp'])) { "$($c['n']): $(if (-not $c['rp'] -and -not $c['lp']) { 'neither' } elseif (-not $c['rp']) { 'no readiness' } else { 'no liveness' })" } }); $bad -join '; ' } }) 'Add both, so traffic only reaches ready pods and stuck ones are restarted.' "$k8s/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/" 'Fix first'
    & $record 'Workload design' 'Reliability' 'Single-replica workloads' 'Low' 'deployments,statefulsets,daemonsets' @(foreach ($row in $workloadRows) { if ($row['kind'] -in 'Deployment', 'StatefulSet' -and [int]$row['want'] -eq 1) { & $hit $row['ns'] $row['kind'] $row['name'] } }) 'Run two or more where the workload can: one replica goes down with its node, and in every upgrade.' "$aks/best-practices-app-cluster-reliability"
    & $record 'Workload design' 'Reliability' 'Replicas spread across nodes' 'Medium' 'pods', 'deployments,statefulsets,daemonsets' @(foreach ($row in $replicated) { $pod = & $podOf $row; if ($pod -and -not $pod['sp'] -and -not $pod['af']) { & $hit $row['ns'] $row['kind'] $row['name'] "$([int]$row['want']) replicas" } }) 'Add topology spread constraints or pod anti-affinity: nothing stops the replicas sharing a node. AKS Automatic adds them where neither is set.' "$aks/best-practices-app-cluster-reliability" 'Changed by Automatic'
    & $record 'Workload design' 'Reliability' 'Pod disruption budgets' 'Medium' 'poddisruptionbudgets', 'deployments,statefulsets,daemonsets' @(foreach ($row in $replicated) { if (-not @($pdbs | Where-Object { $_['ns'] -eq $row['ns'] -and (& $selects $_['sel'] $row['labels']) }).Count) { & $hit $row['ns'] $row['kind'] $row['name'] "$([int]$row['want']) replicas" } }) 'Add a pod disruption budget, so upgrades and node drains keep enough replicas up.' "$aks/best-practices-app-cluster-reliability"
    & $record 'Workload design' 'Operational Excellence' 'Disruption budgets that block node drains' 'Medium' 'poddisruptionbudgets', 'deployments,statefulsets,daemonsets' @(foreach ($row in $pdbs) { $targets = @($workloadRows | Where-Object { $_['ns'] -eq $row['ns'] -and (& $selects $row['sel'] $_['labels']) }); $want = ($targets | ForEach-Object { [int]$_['want'] } | Measure-Object -Sum).Sum; if ([string]$row['max'] -in '0', '0%' -or ($targets.Count -and $row['min'] -is [ValueType] -and [int]$row['min'] -ge $want) -or [string]$row['min'] -eq '100%') { & $hit $row['ns'] 'PodDisruptionBudget' $row['name'] "minAvailable $($row['min']), maxUnavailable $($row['max']), $want replica(s)" } }) 'Leave room for at least one pod to move: a budget that allows none makes node upgrades stall.' "$aks/upgrade-aks-cluster"
    & $record 'Workload design' 'Reliability' 'Pods with no controller' 'Low' 'pods' @(& $byPod { param($Pod) if (-not $Pod['ok']) { 'not recreated if its node goes' } }) 'Run them under a Deployment, or a Job for one-off work.' "$k8s/concepts/configuration/overview/"
    & $record 'Workload design' 'Operational Excellence' 'Workloads in the default namespace' 'Low' 'pods' @($podRows | Where-Object { $_['ns'] -eq 'default' } | ForEach-Object { & $hit 'default' (& $kindOf $_) $_['on'] }) 'Give each application a namespace, so quotas, policy and access can apply to it.' "$aks/operator-best-practices-cluster-isolation"
    & $record 'Workload design' 'Operational Excellence' 'Images without a version' 'Medium' 'pods' @(& $byContainer -Init { param($C) $image = [string]$C['img']; if ($image -notmatch '@sha256:' -and ($image -match ':latest$' -or ($image -split '/')[-1] -notmatch ':')) { $image } }) 'Use a versioned tag or a digest: latest can change under a running workload.' $safeguards 'Fix first'

    # --- Pod security -----------------------------------------------------------------------------------------------------------
    & $record 'Pod security' 'Security' 'Privileged containers' 'High' 'pods' @(& $byContainer -Init { param($C) if ($C['pv']) { 'privileged' } }) 'Remove privileged: true, and add only the capabilities the container needs.' $podSecurity 'Fix first'
    & $record 'Pod security' 'Security' 'Host namespaces' 'High' 'pods' @(& $byPod { param($Pod) @(if ($Pod['hn']) { 'hostNetwork' }; if ($Pod['hp']) { 'hostPID' }; if ($Pod['hi']) { 'hostIPC' }) -join ', ' }) 'Remove them: they share the node''s network or processes with the pod.' $podSecurity 'Fix first'
    & $record 'Pod security' 'Security' 'hostPath volumes' 'High' 'pods' @(& $byPod { param($Pod) @($Pod['hv']) -join ', ' }) 'Use a persistent volume, or a CSI driver: a hostPath reaches into the node.' $podSecurity 'Fix first'
    & $record 'Pod security' 'Security' 'Host ports' 'Medium' 'pods' @(& $byContainer -Init { param($C) @($C['hpt']) -join ', ' }) 'Use a Service: a host port ties the pod to a node, and to that port on it.' $podSecurity 'Fix first'
    $allowedCapabilities = 'AUDIT_WRITE', 'CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'FSETID', 'KILL', 'MKNOD', 'NET_BIND_SERVICE', 'SETFCAP', 'SETGID', 'SETPCAP', 'SETUID', 'SYS_CHROOT'
    & $record 'Pod security' 'Security' 'Added Linux capabilities' 'Medium' 'pods' @(& $byContainer -Init { param($C) @($C['cap'] | Where-Object { $_ -and ([string]$_ -replace '^CAP_', '') -notin $allowedCapabilities }) -join ', ' }) 'Remove capabilities beyond the baseline Pod Security Standard''s list.' $podSecurity 'Fix first'
    & $record 'Pod security' 'Security' 'Unconfined seccomp profile' 'High' 'pods' @(& $byContainer -Init { param($C, $Pod) if ((& $effective $C $Pod 'sc') -eq 'Unconfined') { 'Unconfined' } }) 'Use RuntimeDefault.' $podSecurity 'Fix first'
    & $record 'Pod security' 'Security' 'Unconfined AppArmor profile' 'Medium' 'pods' @(& $byPod { param($Pod) $profiled = @(foreach ($c in @($Pod['c'])) { if ($c -and (& $effective $c $Pod 'aa') -eq 'Unconfined') { $c['n'] } }); if ($Pod['aan'] -or $profiled.Count) { $(if ($profiled.Count) { $profiled -join ', ' } else { 'by annotation' }) } }) 'Remove it, so the default profile applies.' $podSecurity 'Fix first'
    & $record 'Pod security' 'Security' 'Non-default /proc mount' 'Medium' 'pods' @(& $byContainer -Init { param($C) if ($C['pm'] -and $C['pm'] -ne 'Default') { [string]$C['pm'] } }) 'Remove procMount, or set it to Default.' $podSecurity 'Fix first'
    $safeSysctls = 'kernel.shm_rmid_forced', 'net.ipv4.ip_local_port_range', 'net.ipv4.ip_unprivileged_port_start', 'net.ipv4.tcp_syncookies', 'net.ipv4.ping_group_range', 'net.ipv4.ip_local_reserved_ports', 'net.ipv4.tcp_keepalive_time'
    & $record 'Pod security' 'Security' 'Sysctls outside the safe list' 'Medium' 'pods' @(& $byPod { param($Pod) @($Pod['sy'] | Where-Object { $_ -and $_ -notin $safeSysctls }) -join ', ' }) 'Remove them, or set them another way.' $podSecurity 'Fix first'
    & $record 'Pod security' 'Security' 'Containers that may run as root' 'Medium' 'pods' @(& $byContainer -Init { param($C, $Pod) $uid = & $effective $C $Pod 'uid'; if ($null -ne $uid -and [long]$uid -eq 0) { 'runAsUser 0' } elseif ($null -eq $uid -and -not (& $effective $C $Pod 'nr')) { 'nothing rules it out' } }) 'Set runAsNonRoot: true, and a non-zero runAsUser. The baseline standard allows root, so this won''t stop a move to AKS Automatic.' "$k8s/tasks/configure-pod-container/security-context/" 'Review'
    & $record 'Pod security' 'Security' 'Privilege escalation not turned off' 'Low' 'pods' @(& $byContainer -Init { param($C) if ($C['esc'] -ne $false) { 'allowPrivilegeEscalation isn''t false' } }) 'Set allowPrivilegeEscalation: false.' "$k8s/tasks/configure-pod-container/security-context/"
    & $record 'Pod security' 'Security' 'Workloads on the default service account' 'Low' 'pods' @(& $byPod { param($Pod) if ([string]$Pod['sa'] -in '', 'default') { 'default service account' } }) 'Give each workload its own service account, so its access can be set on its own.' "$aks/operator-best-practices-identity"
    & $record 'Pod security' 'Security' 'Secrets in environment variables' 'Low' 'pods' @(& $byContainer -Init { param($C) if ([int]$C['se']) { "$($C['se']) variable(s) from a secret" } }) 'Mount secrets as files, or use the Key Vault secrets provider: environment variables end up in logs and crash dumps.' "$aks/csi-secrets-store-driver"

    # --- Namespaces -------------------------------------------------------------------------------------------------------------
    $has = { param([string] $Key) @(& $rowsOf 'has' | Where-Object { $_['k'] -eq $Key } | ForEach-Object { $_['ns'] }) }
    $without = { param([string] $Key) $present = & $has $Key; foreach ($row in $namespaces) { if ($row['name'] -notin $present) { & $hit '' 'Namespace' $row['name'] } } }
    & $record 'Namespaces' 'Security' 'Namespaces with no network policy' 'Medium' 'namespaces', 'networkpolicies' @(& $without 'networkpolicies') 'Add a default-deny policy per namespace, then allow what is needed.' "$aks/use-network-policies"
    & $record 'Namespaces' 'Reliability' 'Namespaces with no resource quota' 'Low' 'namespaces', 'resourcequotas' @(& $without 'resourcequotas') 'Set a quota where several teams share a cluster.' "$aks/operator-best-practices-scheduler"
    & $record 'Namespaces' 'Reliability' 'Namespaces with no limit range' 'Low' 'namespaces', 'limitranges' @(& $without 'limitranges') 'Set a limit range, so pods with no requests get sensible defaults.' "$aks/developer-best-practices-resource-management"
    & $record 'Namespaces' 'Security' 'Namespaces with no Pod Security label' 'Low' 'namespaces' @(foreach ($row in $namespaces) { if (-not $row['psa']) { & $hit '' 'Namespace' $row['name'] } }) 'Label them pod-security.kubernetes.io/enforce, or use Deployment Safeguards.' "$k8s/concepts/security/pod-security-admission/"

    # --- RBAC ---------------------------------------------------------------------------------------------------------------------
    # AKS's own bindings and system subjects aren't yours to fix. Only roles someone holds count: a role nobody is bound to does nothing.
    $roleOf = {
        param($Binding)
        & $rowsOf 'role' | Where-Object { $_['name'] -eq $Binding['rn'] -and $_['kind'] -eq $Binding['rk'] -and ($_['kind'] -eq 'ClusterRole' -or $_['ns'] -eq $Binding['ns']) } | Select-Object -First 1
    }
    $bindings = @(& $rowsOf 'bind' | Where-Object { [string]$_['name'] -notmatch '^(system:|aks-)' -and (& $inScope $_['ns']) })
    $people = { param($Binding) @($Binding['sub'] | Where-Object { $_ -and [string]$_['n'] -notlike 'system:*' -and (& $inScope $_['ns']) }) }
    $describe = { param($Subjects) @($Subjects | ForEach-Object { "$($_['k']) $(if ($_['ns']) { "$($_['ns'])/" })$($_['n'])" }) -join ', ' }
    $wildcard = { param($Role) $Role -and @($Role['rules'] | Where-Object { $_ -and @($_['v']) -contains '*' -and @($_['r']) -contains '*' }).Count }
    $broadGroups = 'system:anonymous', 'system:unauthenticated', 'system:authenticated'
    $rbacKinds = 'clusterrolebindings', 'rolebindings'
    & $record 'RBAC' 'Security' 'Roles bound to anyone or every signed-in user' 'High' $rbacKinds @(foreach ($row in @(& $rowsOf 'bind')) { $open = @($row['sub'] | Where-Object { $_ -and [string]$_['n'] -in $broadGroups }); if ($open.Count -and $row['rn'] -notmatch '^system:(public-info-viewer|discovery|basic-user)' -and (& $inScope $row['ns'])) { & $hit ([string]$row['ns']) $row['kind'] $row['name'] "$($row['rn']) for $(@($open | ForEach-Object { $_['n'] }) -join ', ')" } }) 'Remove the binding, unless the role really is meant for everyone.' "$aks/concepts-identity"
    & $record 'RBAC' 'Security' 'cluster-admin bindings to review' 'Medium' $rbacKinds @(foreach ($row in $bindings) { if ($row['rn'] -eq 'cluster-admin') { $who = @(& $people $row); if ($who.Count) { & $hit ([string]$row['ns']) $row['kind'] $row['name'] (& $describe $who) } } }) 'Keep cluster-admin for those who need it, and give others a narrower role.' "$aks/operator-best-practices-identity"
    & $record 'RBAC' 'Security' 'Default service accounts with wide access' 'High' 'clusterrolebindings', 'rolebindings', 'clusterroles', 'roles' @(foreach ($row in $bindings) { $default = @(& $people $row | Where-Object { $_['k'] -eq 'ServiceAccount' -and $_['n'] -eq 'default' }); if ($default.Count -and ($row['rn'] -eq 'cluster-admin' -or (& $wildcard (& $roleOf $row)))) { & $hit ([string]$row['ns']) $row['kind'] $row['name'] "$($row['rn']) for $(& $describe $default)" } }) 'Every pod that names no service account gets this access: bind the role to a service account of its own.' "$aks/operator-best-practices-identity"
    & $record 'RBAC' 'Security' 'Wildcard roles in use' 'Medium' 'clusterrolebindings', 'rolebindings', 'clusterroles', 'roles' @(foreach ($row in $bindings) { $who = @(& $people $row); if ($who.Count -and $row['rn'] -ne 'cluster-admin' -and (& $wildcard (& $roleOf $row))) { & $hit ([string]$row['ns']) $row['kind'] $row['name'] "$($row['rn']) for $(& $describe $who)" } }) 'List the verbs and resources it needs instead of *.' "$k8s/concepts/security/rbac-good-practices/"
    & $record 'RBAC' 'Security' 'Roles that can gain more access' 'Medium' 'clusterrolebindings', 'rolebindings', 'clusterroles', 'roles' @(foreach ($row in $bindings) {
            $who = @(& $people $row)
            $role = & $roleOf $row
            if (-not $who.Count -or -not $role -or $row['rn'] -eq 'cluster-admin') { continue }
            $risky = @(foreach ($rule in @($role['rules'])) { if ($rule) { @($rule['v'] | Where-Object { $_ -in 'escalate', 'bind', 'impersonate' }); if (@($rule['r']) -contains 'nodes/proxy') { 'nodes/proxy' } } }) | Select-Object -Unique
            if (@($risky).Count) { & $hit ([string]$row['ns']) $row['kind'] $row['name'] "$($row['rn']): $(@($risky) -join ', '), for $(& $describe $who)" }
        }) 'Remove these unless the subject really has to grant access: each is a way to more rights than the role lists.' "$k8s/concepts/security/rbac-good-practices/"

    # --- Network --------------------------------------------------------------------------------------------------------------------
    & $record 'Network' 'Security' 'Public load balancer services' 'Medium' 'services' @(foreach ($row in $services) { if ($row['type'] -eq 'LoadBalancer' -and -not $row['int']) { & $hit $row['ns'] 'Service' $row['name'] } }) 'Make it internal if it needn''t be public, or put it behind an ingress or gateway with a WAF.' "$aks/internal-lb"
    & $record 'Network' 'Security' 'Services with external IPs' 'Medium' 'services' @(foreach ($row in $services) { if ([int]$row['ext']) { & $hit $row['ns'] 'Service' $row['name'] "$($row['ext']) external IP(s)" } }) 'Remove them, or use a load balancer: they can take traffic meant for those addresses.' "$k8s/concepts/services-networking/service/#external-ips"
    $selectorText = { param($Row) (@($Row['sel'].Keys | Sort-Object | ForEach-Object { "$_=$($Row['sel'][$_])" }) -join ',') }
    & $record 'Network' 'Reliability' 'Services sharing a selector' 'Medium' 'services' @($services | Where-Object { $_['sel'] -and @($_['sel'].Keys).Count } | Group-Object -Property { "$($_['ns'])|$(& $selectorText $_)" } | Where-Object Count -GT 1 | ForEach-Object { $names = @($_.Group | ForEach-Object { $_['name'] }); foreach ($row in $_.Group) { & $hit $row['ns'] 'Service' $row['name'] "same selector as $(@($names | Where-Object { $_ -ne $row['name'] }) -join ', ')" } }) 'Give each Service a selector of its own.' $safeguards 'Fix first'
    & $record 'Network' 'Operational Excellence' 'Community ingress-nginx in use' 'Medium' 'pods' @(& $byContainer { param($C) if ([string]$C['img'] -match 'ingress-nginx/controller') { [string]$C['img'] } }) 'The community project has retired: move to the application routing add-on or the Gateway API.' "$aks/app-routing"
    & $record 'Network' 'Operational Excellence' 'Ingress resources to plan for' 'Low' 'ingresses' @(foreach ($row in (& $scoped 'ing')) { & $hit $row['ns'] 'Ingress' $row['name'] ([string]$row['cls']) }) 'Check the destination has an ingress or Gateway API route for them before moving.' "$aks/app-routing" 'Review'

    # --- Storage ----------------------------------------------------------------------------------------------------------------------
    & $record 'Storage' 'Operational Excellence' 'In-tree storage provisioners' 'Medium' 'storageclasses' @(foreach ($row in (& $rowsOf 'sc')) { if ([string]$row['prov'] -in 'kubernetes.io/azure-disk', 'kubernetes.io/azure-file') { & $hit '' 'StorageClass' $row['name'] ([string]$row['prov']) } }) 'Use the CSI drivers: disk.csi.azure.com and file.csi.azure.com.' "$aks/csi-storage-drivers" 'Fix first'

    # --- Moving to AKS Automatic -------------------------------------------------------------------------------------------------------
    $counted = @($checks | Where-Object Readiness)
    $count = { param([string] $Kind) @($items | Where-Object Readiness -EQ $Kind).Count }
    $fixFirst = & $count 'Fix first'
    $unknown = @($counted | Where-Object Status -EQ 'Not checked').Count
    $verdict = if ($ClusterSku -eq 'Automatic') { 'Already AKS Automatic' } elseif ($fixFirst) { 'Fix first' } elseif ($unknown) { 'Not fully checked' } else { 'No blockers found' }
    @{
        Checks    = $checks.ToArray()
        Items     = $items.ToArray()
        Readiness = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.AksAutomaticReadiness'; Cluster = $ClusterName; Verdict = $verdict; FixFirst = $fixFirst; ChangedByAutomatic = (& $count 'Changed by Automatic'); Review = (& $count 'Review'); NotChecked = $unknown
            Workloads = @($podRows).Count; Namespaces = @($namespaces).Count; ClusterId = $ClusterId
        }
    }
}
