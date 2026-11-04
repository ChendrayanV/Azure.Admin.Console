<#
    What Get-AACAksWorkload's commands answer for the made-up cluster in
    ContosoAksKubernetes.json, one record per line as jq writes them:

      shop      a healthy namespace: web (2 replicas, spread, disruption budget) and every
                namespace safeguard
      payments  everything wrong: api (crash looping, privileged, on the host, latest tag, no
                requests or probes), a pod with no controller, a failed CronJob run, the
                community ingress controller, a public service, a stray PVC
      kube-system  coredns, privileged: left out unless -IncludeSystemNamespace
      RBAC      cluster-admin for a group and a default service account, a wildcard role, a role
                for every signed-in user, and AKS's own binding and an unused role, which don't count

    The test in Tests\Azure\AksWorkload.Tests.ps1 checks these lines against the real jq filters,
    where jq is installed.
#>
function Get-AACContosoAksKubernetes {
    $workloads = @(
        '{"ns":"payments","ok":"CronJob","on":"nightly","ph":{"Failed":1},"rs":0,"wt":[],"oom":false,"sa":"ops","at":null,"hn":false,"hp":false,"hi":false,"sp":false,"af":false,"ps":{},"sy":[],"hv":[],"aan":false,"c":[{"n":"job","init":false,"img":"contoso/job:3.1","rc":"10m","rm":"10Mi","lm":"10Mi","rp":false,"lp":false,"nr":true,"esc":false,"cap":[],"hpt":[],"se":0}],"t":"pod","n":1}'
        '{"ns":"kube-system","ok":"Deployment","on":"coredns","ph":{"Running":1},"rs":0,"wt":[],"oom":false,"sa":"coredns","at":null,"hn":false,"hp":false,"hi":false,"sp":false,"af":false,"ps":{},"sy":[],"hv":[],"aan":false,"c":[{"n":"coredns","init":false,"img":"mcr.microsoft.com/oss/kubernetes/coredns:v1.11","rp":false,"lp":false,"pv":true,"cap":[],"hpt":[],"se":0}],"t":"pod","n":1}'
        '{"ns":"payments","ok":"","on":"debug","ph":{"Pending":1},"rs":0,"wt":[],"oom":false,"sa":"ops","at":null,"hn":false,"hp":false,"hi":false,"sp":false,"af":false,"ps":{},"sy":[],"hv":[],"aan":false,"c":[{"n":"shell","init":false,"img":"contoso/tools:2.0","rc":"10m","rm":"10Mi","lm":"10Mi","rp":true,"lp":true,"nr":true,"esc":false,"cap":[],"hpt":[],"se":0}],"t":"pod","n":1}'
        '{"ns":"payments","ok":"Deployment","on":"api","ph":{"Running":1},"rs":12,"wt":["CrashLoopBackOff"],"oom":true,"sa":"default","at":null,"hn":true,"hp":false,"hi":false,"sp":false,"af":false,"ps":{},"sy":["kernel.msgmax"],"hv":["/var/run/docker.sock"],"aan":false,"c":[{"n":"api","init":false,"img":"contoso/api:latest","rp":false,"lp":false,"pv":true,"cap":["SYS_ADMIN","NET_BIND_SERVICE"],"hpt":[8080],"sc":"Unconfined","pm":"Unmasked","aa":"Unconfined","se":1},{"n":"seed","init":true,"img":"contoso/seed:1.0","rp":false,"lp":false,"uid":0,"cap":[],"hpt":[],"se":0}],"t":"pod","n":1}'
        '{"ns":"payments","ok":"Deployment","on":"ingress-nginx-controller","ph":{"Running":1},"rs":0,"wt":[],"oom":false,"sa":"ingress","at":null,"hn":false,"hp":false,"hi":false,"sp":false,"af":false,"ps":{},"sy":[],"hv":[],"aan":false,"c":[{"n":"controller","init":false,"img":"registry.k8s.io/ingress-nginx/controller:v1.9.0","rc":"100m","rm":"90Mi","lm":"256Mi","rp":true,"lp":true,"nr":true,"esc":false,"cap":[],"hpt":[],"se":0}],"t":"pod","n":1}'
        '{"ns":"shop","ok":"Deployment","on":"web","ph":{"Running":2},"rs":1,"wt":[],"oom":false,"sa":"web","at":false,"hn":false,"hp":false,"hi":false,"sp":true,"af":false,"ps":{"nr":true,"uid":1000,"sc":"RuntimeDefault"},"sy":[],"hv":[],"aan":false,"c":[{"n":"web","init":false,"img":"contoso.azurecr.io/web:1.2","rc":"100m","rm":"128Mi","lm":"256Mi","rp":true,"lp":true,"esc":false,"cap":[],"hpt":[],"se":0}],"t":"pod","n":2}'
        '{"t":"workload","kind":"Deployment","ns":"shop","name":"web","want":2,"ready":2,"labels":{"app":"web"}}'
        '{"t":"workload","kind":"Deployment","ns":"payments","name":"api","want":3,"ready":1,"labels":{"app":"api"}}'
        '{"t":"workload","kind":"Deployment","ns":"payments","name":"ingress-nginx-controller","want":1,"ready":1,"labels":{"app":"ingress"}}'
        '{"t":"workload","kind":"DaemonSet","ns":"shop","name":"agent","want":2,"ready":2,"labels":{"app":"agent"}}'
        '{"t":"pdb","ns":"shop","name":"web","sel":{"app":"web"},"min":null,"max":1}'
        '{"t":"pdb","ns":"payments","name":"api","sel":{"app":"api"},"min":3,"max":null}'
        '{"t":"hpa","ns":"shop","name":"web","tk":"Deployment","tn":"web"}'
        '{"t":"hpa","ns":"payments","name":"old","tk":"Deployment","tn":"gone"}'
        'AAC_END'
    )
    $cluster = @(
        '{"t":"node","name":"aks-apps-1","ready":true,"press":[]}'
        '{"t":"node","name":"aks-apps-2","ready":false,"press":["MemoryPressure"]}'
        '{"t":"ns","name":"default","psa":false}'
        '{"t":"ns","name":"kube-system","psa":false}'
        '{"t":"ns","name":"payments","psa":false}'
        '{"t":"ns","name":"shop","psa":true}'
        '{"t":"has","k":"networkpolicies","ns":"shop"}'
        '{"t":"has","k":"resourcequotas","ns":"shop"}'
        '{"t":"has","k":"limitranges","ns":"shop"}'
        '{"t":"svc","ns":"shop","name":"web","type":"ClusterIP","sel":{"app":"web"},"ext":0,"int":false}'
        '{"t":"svc","ns":"shop","name":"legacy","type":"ClusterIP","sel":null,"ext":1,"int":false}'
        '{"t":"svc","ns":"payments","name":"api","type":"LoadBalancer","sel":{"app":"api"},"ext":0,"int":false}'
        '{"t":"svc","ns":"payments","name":"api-copy","type":"ClusterIP","sel":{"app":"api"},"ext":0,"int":false}'
        '{"t":"svc","ns":"payments","name":"private","type":"LoadBalancer","sel":null,"ext":0,"int":true}'
        '{"t":"ep","ns":"shop","name":"web","up":true}'
        '{"t":"ep","ns":"payments","name":"api-copy","up":true}'
        '{"t":"ing","ns":"payments","name":"api","cls":"nginx"}'
        '{"t":"sc","name":"managed-csi","prov":"disk.csi.azure.com"}'
        '{"t":"sc","name":"old-disk","prov":"kubernetes.io/azure-disk"}'
        '{"t":"pvc","ns":"shop","name":"data","ph":"Bound"}'
        '{"t":"pvc","ns":"payments","name":"ledger","ph":"Pending"}'
        '{"t":"bind","kind":"ClusterRoleBinding","name":"system:basic-user","rk":"ClusterRole","rn":"system:basic-user","sub":[{"k":"Group","n":"system:authenticated","ns":null}]}'
        '{"t":"bind","kind":"ClusterRoleBinding","name":"aks-cluster-admin-binding","rk":"ClusterRole","rn":"cluster-admin","sub":[{"k":"User","n":"clusterAdmin","ns":null}]}'
        '{"t":"bind","kind":"ClusterRoleBinding","name":"ops-admins","rk":"ClusterRole","rn":"cluster-admin","sub":[{"k":"Group","n":"ops","ns":null}]}'
        '{"t":"bind","kind":"ClusterRoleBinding","name":"everyone","rk":"ClusterRole","rn":"edit","sub":[{"k":"Group","n":"system:authenticated","ns":null}]}'
        '{"t":"bind","kind":"ClusterRoleBinding","name":"default-admin","rk":"ClusterRole","rn":"cluster-admin","sub":[{"k":"ServiceAccount","n":"default","ns":"payments"}]}'
        '{"t":"bind","kind":"ClusterRoleBinding","name":"act-as","rk":"ClusterRole","rn":"impersonator","sub":[{"k":"User","n":"bob","ns":null}]}'
        '{"t":"bind","kind":"RoleBinding","ns":"payments","name":"all-of-it","rk":"Role","rn":"payments-all","sub":[{"k":"User","n":"alice","ns":null}]}'
        '{"t":"role","kind":"ClusterRole","name":"unused-wide","rules":[{"v":["*"],"r":["*"]}]}'
        '{"t":"role","kind":"ClusterRole","name":"impersonator","rules":[{"v":["impersonate"],"r":["users"]}]}'
        '{"t":"role","kind":"Role","ns":"payments","name":"payments-all","rules":[{"v":["*"],"r":["*"]}]}'
        'AAC_END'
    )
    @{ Workloads = $workloads -join "`n"; Cluster = $cluster -join "`n" }
}
