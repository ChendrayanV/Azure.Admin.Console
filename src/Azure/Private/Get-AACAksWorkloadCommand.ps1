function Get-AACAksWorkloadCommand {
    <#
    .SYNOPSIS
        The commands Get-AACAksWorkload runs in a cluster: @{ Command; Kinds }.
    .DESCRIPTION
        jq is one of the tools Microsoft documents in the run command's pod. The
        filters go in single quotes in the shell, so they can't contain one. The
        file Tests\Fixtures\ContosoAksKubernetes.json and its expected answer
        check them where jq is installed.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $container = '{n:.name,init:.init,img:.image,rc:.resources.requests.cpu,rm:.resources.requests.memory,lm:.resources.limits.memory,rp:(.readinessProbe!=null),lp:(.livenessProbe!=null),pv:.securityContext.privileged,nr:.securityContext.runAsNonRoot,uid:.securityContext.runAsUser,esc:.securityContext.allowPrivilegeEscalation,cap:(.securityContext.capabilities.add//[]),hpt:[.ports[]?.hostPort//empty],sc:.securityContext.seccompProfile.type,pm:.securityContext.procMount,aa:.securityContext.appArmorProfile.type,se:([.env[]?|select(.valueFrom.secretKeyRef!=null)]|length)}|with_entries(select(.value!=null))'
    $podFilter = '.items|map(select(.metadata.namespace!="aks-command")|(.metadata.ownerReferences[0].kind//"") as $k|(.metadata.ownerReferences[0].name//.metadata.name) as $o|{ns:.metadata.namespace,ok:(if $k=="ReplicaSet" then "Deployment" elif $k=="Job" and ($o|test("-[0-9]+$")) then "CronJob" else $k end),on:(if $k=="ReplicaSet" then ($o|sub("-[a-z0-9]+$";"")) elif $k=="Job" then ($o|sub("-[0-9]+$";"")) else $o end),ph:(.status.phase//"Unknown"),rs:([.status.containerStatuses[]?.restartCount]|max//0),wt:[.status.containerStatuses[]?.state.waiting.reason//empty],oom:([.status.containerStatuses[]?.lastState.terminated.reason//empty]|index("OOMKilled")!=null),sa:.spec.serviceAccountName,at:.spec.automountServiceAccountToken,hn:(.spec.hostNetwork//false),hp:(.spec.hostPID//false),hi:(.spec.hostIPC//false),sp:((.spec.topologySpreadConstraints//[])|length>0),af:(.spec.affinity.podAntiAffinity!=null),ps:(.spec.securityContext|{nr:.runAsNonRoot,uid:.runAsUser,sc:.seccompProfile.type,aa:.appArmorProfile.type}|with_entries(select(.value!=null))),sy:[.spec.securityContext.sysctls[]?.name],hv:[.spec.volumes[]?.hostPath.path//empty],aan:([(.metadata.annotations//{})|to_entries[]|select((.key|startswith("container.apparmor.security.beta"))and .value=="unconfined")]|length>0),c:[((.spec.containers//[])|map(.+{init:false})[]),((.spec.initContainers//[])|map(.+{init:true})[])|' + $container + ']})|group_by([.ns,.ok,.on])|map(.[0]+{t:"pod",n:length,ph:(map(.ph)|group_by(.)|map({key:.[0],value:length})|from_entries),rs:(map(.rs)|max),wt:(map(.wt)|add|unique),oom:(map(.oom)|any)})|.[]'
    $hasIn = { param([string] $Key) "[.items[].metadata.namespace]|unique|.[]|{t:`"has`",k:`"$Key`",ns:.}" }
    $sections = @(
        [ordered]@{
            'pods'                               = $podFilter
            'deployments,statefulsets,daemonsets' = '.items[]|{t:"workload",kind:.kind,ns:.metadata.namespace,name:.metadata.name,want:(if .kind=="DaemonSet" then .status.desiredNumberScheduled else .spec.replicas end),ready:(if .kind=="DaemonSet" then .status.numberReady else (.status.readyReplicas//0) end),labels:.spec.template.metadata.labels}'
            'poddisruptionbudgets'               = '.items[]|{t:"pdb",ns:.metadata.namespace,name:.metadata.name,sel:.spec.selector.matchLabels,min:.spec.minAvailable,max:.spec.maxUnavailable}'
            'horizontalpodautoscalers'           = '.items[]|{t:"hpa",ns:.metadata.namespace,name:.metadata.name,tk:.spec.scaleTargetRef.kind,tn:.spec.scaleTargetRef.name}'
        }
        [ordered]@{
            'nodes'                  = '.items[]|{t:"node",name:.metadata.name,ready:([.status.conditions[]?|select(.type=="Ready")|.status]|.[0]=="True"),press:[.status.conditions[]?|select(.status=="True" and (.type|test("Pressure|NetworkUnavailable")))|.type]}'
            'namespaces'             = '.items[]|{t:"ns",name:.metadata.name,psa:((.metadata.labels//{})|has("pod-security.kubernetes.io/enforce"))}'
            'networkpolicies'        = (& $hasIn 'networkpolicies')
            'resourcequotas'         = (& $hasIn 'resourcequotas')
            'limitranges'            = (& $hasIn 'limitranges')
            'services'               = '.items[]|{t:"svc",ns:.metadata.namespace,name:.metadata.name,type:.spec.type,sel:.spec.selector,ext:((.spec.externalIPs//[])|length),int:((.metadata.annotations//{})["service.beta.kubernetes.io/azure-load-balancer-internal"]=="true")}'
            'endpoints'              = '.items[]|{t:"ep",ns:.metadata.namespace,name:.metadata.name,up:(([.subsets[]?.addresses[]?]|length)>0)}'
            'ingresses'              = '.items[]|{t:"ing",ns:.metadata.namespace,name:.metadata.name,cls:.spec.ingressClassName}'
            'storageclasses'         = '.items[]|{t:"sc",name:.metadata.name,prov:.provisioner}'
            'persistentvolumeclaims' = '.items[]|{t:"pvc",ns:.metadata.namespace,name:.metadata.name,ph:.status.phase}'
            'clusterrolebindings'    = '.items[]|{t:"bind",kind:.kind,name:.metadata.name,rk:.roleRef.kind,rn:.roleRef.name,sub:[.subjects[]?|{k:.kind,n:.name,ns:.namespace}]}'
            'rolebindings'           = '.items[]|{t:"bind",kind:.kind,ns:.metadata.namespace,name:.metadata.name,rk:.roleRef.kind,rn:.roleRef.name,sub:[.subjects[]?|{k:.kind,n:.name,ns:.namespace}]}'
            'clusterroles'           = '.items|map(select(.metadata.name|startswith("system:")|not))|.[]|{t:"role",kind:.kind,name:.metadata.name,rules:[.rules[]?|{v:.verbs,r:.resources}]}'
            'roles'                  = '.items[]|{t:"role",kind:.kind,ns:.metadata.namespace,name:.metadata.name,rules:[.rules[]?|{v:.verbs,r:.resources}]}'
        }
    )
    # A kind kubectl can't list, or may not, becomes a line saying so; the others still answer.
    $reader = 'q() { if o=$(kubectl get "$1" -A -o json 2>/dev/null); then printf "%s" "$o" | jq -c "$2" || echo "{\"t\":\"error\",\"k\":\"$1\"}"; else echo "{\"t\":\"error\",\"k\":\"$1\"}"; fi; }'
    foreach ($section in $sections) {
        $lines = @($reader) + @(foreach ($kind in $section.Keys) { "q $kind '$($section[$kind])'" }) + 'echo AAC_END'
        @{ Command = $lines -join "`n"; Kinds = @($section.Keys) }
    }
}
