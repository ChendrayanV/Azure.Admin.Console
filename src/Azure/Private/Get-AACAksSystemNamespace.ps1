function Get-AACAksSystemNamespace {
    <#
    .SYNOPSIS
        The namespaces AKS and its add-ons run in, which the AKS assessment's
        workload views leave out unless asked (-IncludeSystemNamespace).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    @('kube-system', 'gatekeeper-system', 'azure-arc', 'azure-extensions-usage-system', 'flux-system', 'kube-public', 'kube-node-lease', 'calico-system', 'tigera-operator', 'aks-command', 'app-routing-system', 'aks-istio-system', 'kube-egress-gateway-system', 'dapr-system')
}
