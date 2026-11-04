function Invoke-AACAksRunCommand {
    <#
    .SYNOPSIS
        Runs one command inside an AKS cluster with AKS's run command, no kubectl
        or network path to the cluster needed, and returns its output.
    .DESCRIPTION
        POST .../runCommand, then the command's result until it finishes,
        -TimeoutMinutes at most. Returns @{ Logs; Status }: Status is 'OK', or why
        it couldn't run.

        A cluster with Entra ID integration needs a token for the AKS server app
        (6dae42f8-4368-4678-94ff-3960e28e3630) - Get-AACAccessToken gets it from
        the sign-in - and the command then has that person's rights in the
        cluster. Running a command needs the
        Microsoft.ContainerService/managedClusters/runCommand/action permission
        (Azure Kubernetes Service Cluster Admin, Contributor) and a cluster with
        run command allowed. It starts a short-lived pod in the aks-command
        namespace. AKS cuts the output off at 512 kB, so a caller has to notice
        when that happened.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $ClusterId,

        [Parameter(Mandatory)]
        [string] $Command,

        [switch] $EntraId,

        [ValidateRange(1, 30)]
        [int] $TimeoutMinutes = 5,

        [ValidateRange(1, 60)]
        [int] $PollSeconds = 5
    )

    $result = @{ Logs = ''; Status = '' }
    $body = @{ command = $Command; context = '' }
    if ($EntraId) { $body.clusterToken = Get-AACAccessToken -Resource '6dae42f8-4368-4678-94ff-3960e28e3630' }
    try {
        $start = Invoke-AACHttp -Method Post -Uri "$ClusterId/runCommand?api-version=2024-02-01" -Body (ConvertTo-Json -InputObject $body -Compress) -ContentType 'application/json'
    }
    catch {
        $result.Status = "Couldn't start the command: $($_.Exception.Message)"
        return $result
    }
    # 200 with the result, or 202 with where to read it.
    $answer = if ($start.Content) { $start.Content | ConvertFrom-Json -AsHashtable -ErrorAction Ignore }
    $location = [string]$(if ($start.Headers) { @($start.Headers['Location'])[0] })
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((-not $answer -or [string]$answer['properties']['provisioningState'] -notin 'Succeeded', 'Failed') -and $location) {
        if ((Get-Date) -gt $deadline) { $result.Status = "The command didn't finish within $TimeoutMinutes minute(s)."; return $result }
        Start-Sleep -Seconds $PollSeconds
        try { $poll = Invoke-AACHttp -Method Get -Uri $location } catch { $result.Status = "Couldn't read the command's result: $($_.Exception.Message)"; return $result }
        if ($poll.Status -eq 200 -and $poll.Content) { $answer = $poll.Content | ConvertFrom-Json -AsHashtable -ErrorAction Ignore }
    }
    $properties = if ($answer -and $answer.Contains('properties')) { $answer['properties'] } else { @{} }
    if ([string]$properties['provisioningState'] -ne 'Succeeded' -or [int]$properties['exitCode'] -ne 0) {
        $result.Status = "The command failed: $(@([string]$properties['reason'], [string]$properties['logs']) | Where-Object { $_ } | Select-Object -First 1)".Trim()
        return $result
    }
    $result.Logs = [string]$properties['logs']
    $result.Status = 'OK'
    $result
}
