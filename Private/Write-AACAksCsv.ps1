function Write-AACAksCsv {
    <#
    .SYNOPSIS
        Writes Invoke-AACAksAssessment's tables to CSV files in a folder, and
        returns the files.
    .DESCRIPTION
        clusters, node-pools, settings, checks (the Well-Architected checks),
        findings, upgrades, psrule, diagnostics, maintenance, gatekeeper, and
        the Azure Policy views - policy-violations (every non-compliant
        component), policy-by-namespace, policy-by-workload, policy-by-policy,
        policy-by-cluster, policy-cluster-states, policy-assignments - plus
        policy-namespaces\<namespace>.csv: each namespace's non-compliant
        workloads, to hand to the team that owns it (as the AKS Policy
        Compliance Toolkit exports them). Empty tables are left out.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $write = {
        param([string] $File, [object[]] $Rows)
        if (-not @($Rows).Count) { return }
        $target = Join-Path -Path $Path -ChildPath "$File.csv"
        $folder = Split-Path -Path $target -Parent
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        # The nested lists (a cluster's node pools...) have files of their own.
        $Rows | Select-Object -Property * -ExcludeProperty NodePools, Settings, Checks, Findings, Upgrades, PolicyViolations, PSRule | Export-Csv -LiteralPath $target -NoTypeInformation -Encoding utf8
        Get-Item -LiteralPath $target
    }
    & $write 'clusters' $Assessment.Clusters
    & $write 'node-pools' $Assessment.NodePools
    & $write 'settings' $Assessment.Settings
    & $write 'checks' $Assessment.Checks
    & $write 'findings' $Assessment.Findings
    & $write 'upgrades' $Assessment.Upgrades
    & $write 'psrule' $Assessment.PSRule
    & $write 'diagnostics' $Assessment.Diagnostics
    & $write 'maintenance' $Assessment.Maintenance
    & $write 'gatekeeper' $Assessment.Constraints
    $policy = $Assessment.Policy
    if ($policy) {
        & $write 'policy-violations' $policy.Components
        & $write 'policy-by-namespace' $policy.ByNamespace
        & $write 'policy-by-workload' $policy.ByWorkload
        & $write 'policy-by-policy' $policy.ByPolicy
        & $write 'policy-by-cluster' $policy.ByCluster
        & $write 'policy-cluster-states' $policy.ClusterStates
        & $write 'policy-assignments' $policy.Assignments
        $invalid = [regex]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
        foreach ($group in @($policy.Components) | Group-Object Namespace) {
            & $write (Join-Path -Path 'policy-namespaces' -ChildPath ($group.Name -replace "[$invalid]", '-')) @($group.Group | Select-Object -Property Cluster, Namespace, WorkloadKind, Workload, ObjectKind, Component, Policy, Effect, Assignment, Initiative, LastEvaluated, Subscription)
        }
    }
}
