function Get-AACAksConstraint {
    <#
    .SYNOPSIS
        Reads the Gatekeeper constraints the Azure Policy add-on installs in
        one AKS cluster - their complete violation counts and a sample of the
        violations - with AKS's run command, no kubectl or network path to
        the cluster needed.
    .DESCRIPTION
        Azure Policy keeps at most 500 non-compliant records per policy and
        cluster; Gatekeeper's status.totalViolations is the full count (the
        AKS Policy Compliance Toolkit's 04-constraint-violations script).
        This runs, in the cluster (POST .../runCommand, then the command's
        result until it finishes, -TimeoutMinutes at most):
          kubectl get <every constraint kind> -o jsonpath=...
        and returns:
          Totals      per constraint: Kind, Name, Action (dryrun = Audit,
                      deny, warn), TotalViolations, Assignment, ReferenceId
          Violations  the sampled violations: Constraint, Namespace, Object,
                      Message
          Status      'OK', 'NoGatekeeper' (the add-on isn't installed) or
                      why it couldn't run
        A cluster with Entra ID integration needs a token for the AKS
        server app (6dae42f8-4368-4678-94ff-3960e28e3630) - Get-AACAccessToken
        gets it from the sign-in. Running a command needs the
        Microsoft.ContainerService/managedClusters/runCommand/action
        permission (Azure Kubernetes Service Cluster Admin, Contributor) and
        a cluster with run command allowed; it starts a short-lived pod in
        the aks-command namespace and changes nothing else.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $ClusterId,

        [switch] $EntraId,

        [ValidateRange(1, 30)]
        [int] $TimeoutMinutes = 5,

        [ValidateRange(1, 60)]
        [int] $PollSeconds = 5
    )

    $result = @{ Totals = @(); Violations = @(); Status = '' }
    $jsonPath = '{range .items[*]}T{"\t"}{.kind}{"\t"}{.metadata.name}{"\t"}{.spec.enforcementAction}{"\t"}{.status.totalViolations}{"\t"}{.metadata.annotations.azure-policy-assignment-id}{"\t"}{.metadata.annotations.azure-policy-definition-reference-id}{"\n"}{range .status.violations[*]}V{"\t"}{.namespace}{"\t"}{.kind}{"\t"}{.name}{"\t"}{.message}{"\n"}{end}{end}'
    $command = "kinds=`$(kubectl api-resources --categories=constraint -o name | paste -sd, -); if [ -z `"`$kinds`" ]; then echo NO_GATEKEEPER; else kubectl get `"`$kinds`" -o jsonpath='$jsonPath'; fi"
    $run = Invoke-AACAksRunCommand -ClusterId $ClusterId -Command $command -EntraId:$EntraId -TimeoutMinutes $TimeoutMinutes -PollSeconds $PollSeconds
    if ($run.Status -ne 'OK') {
        $result.Status = $run.Status
        return $result
    }
    $logs = $run.Logs
    if ($logs -match 'NO_GATEKEEPER') { $result.Status = 'NoGatekeeper'; return $result }

    $totals = [System.Collections.Generic.List[object]]::new()
    $violations = [System.Collections.Generic.List[object]]::new()
    $current = ''
    foreach ($line in $logs -split '\r?\n') {
        $cells = $line -split "`t"
        if ($cells[0] -eq 'T' -and $cells.Count -ge 5) {
            $current = $cells[1]
            $totals.Add([pscustomobject]@{
                    Kind            = $cells[1]
                    Name            = $cells[2]
                    Action          = $(if ($cells[3]) { $cells[3] } else { 'deny' })
                    TotalViolations = $(if ($cells[4] -match '^\d+$') { [int]$cells[4] } else { 0 })
                    Assignment      = $(if ($cells.Count -gt 5 -and $cells[5]) { ($cells[5] -split '/')[-1] } else { '' })
                    ReferenceId     = $(if ($cells.Count -gt 6) { $cells[6] } else { '' })
                })
        }
        elseif ($cells[0] -eq 'V' -and $cells.Count -ge 5) {
            $violations.Add([pscustomobject]@{ Constraint = $current; Namespace = $(if ($cells[1]) { $cells[1] } else { '(cluster)' }); Object = "$($cells[2])/$($cells[3])"; Message = ($cells[4..($cells.Count - 1)] -join "`t") })
        }
    }
    $result.Totals = $totals.ToArray()
    $result.Violations = $violations.ToArray()
    $result.Status = 'OK'
    $result
}
