function ConvertTo-AACPolicyRemediation {
    <#
    .SYNOPSIS
        Builds Get-AACPolicyRemediation's list (AAC.PolicyRemediation): each
        DeployIfNotExists or Modify policy with non-compliant resources it
        could fix, and what its remediation tasks did.
    .DESCRIPTION
        No Azure calls.
          -Read         Invoke-AACGraphBatch's result (fixable, assignments)
          -Definition   definition ID (lower case) -> its row (displayName),
                        for the policies' names
          -Task         the remediation tasks (Microsoft.PolicyInsights/
                        remediations items) of the subscriptions and
                        management groups in scope
        Each row: the assignment, the policy, its effect, the non-compliant
        resources, the latest remediation task (state, when, deployments
        succeeded and failed) and a finding:
          High    the latest task failed, or failed deployments; or the
                  assignment has no managed identity (nothing can remediate)
          Medium  never remediated
          Low     remediated, yet resources are non-compliant again (new
                  resources, or the existence condition never matches)
          Info    a task is running; enforcement off (DoNotEnforce: new
                  resources aren't remediated, existing ones can be)
        Returns @{ Remediations; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Definition = @{},

        [AllowEmptyCollection()]
        [object[]] $Task = @(),

        [string[]] $Unread = @(),

        [datetime] $Now = [datetime]::UtcNow
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $number = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v -or '' -eq $v) { 0 } else { [int64]$v } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(@{ fixable = 'non-compliant resources'; assignments = 'policy assignments' }[$key]) couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }
    foreach ($u in @($Unread | Where-Object { $_ })) { $notices.Add("The remediation tasks couldn't be read for $u - its policies may show as never remediated.") }

    $assignments = @{}
    foreach ($row in (& $rowsOf 'assignments')) { $assignments[(& $text $row 'id')] = $row }
    $scopeName = { param([string] $Scope) if ($Scope -match '/managementgroups/([^/]+)$') { "management group $($Matches[1])" } elseif ($Scope -match '^/subscriptions/([^/]+)$') { "subscription $($Matches[1])" } elseif ($Scope -match '/resourcegroups/([^/]+)$') { "resource group $($Matches[1])" } else { $Scope } }

    # The latest task per assignment and policy reference.
    $latest = @{}
    foreach ($t in @($Task | Where-Object { $_ })) {
        $p = & $get $t 'properties'
        $key = "$((& $text $p 'policyAssignmentId').ToLowerInvariant())|$(& $text $p 'policyDefinitionReferenceId')"
        $when = & $date (& $text $p 'createdOn')
        if (-not $latest.Contains($key) -or ($when -and $latest[$key].When -lt $when)) { $latest[$key] = @{ When = $when; P = $p } }
    }

    $rank = (Get-AACSeverityRank).Rank
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($row in (& $rowsOf 'fixable')) {
        $assignmentId = & $text $row 'assignmentId'
        $reference = & $text $row 'referenceId'
        $definitionId = & $text $row 'definitionId'
        $a = if ($assignments.Contains($assignmentId)) { $assignments[$assignmentId] } else { $null }
        $policy = if ($Definition.Contains($definitionId)) { & $text $Definition[$definitionId] 'displayName' } else { ($definitionId -split '/')[-1] }
        $count = & $number $row 'nonCompliant'
        $latestTask = if ($latest.Contains("$assignmentId|$reference")) { $latest["$assignmentId|$reference"] } elseif ($latest.Contains("$assignmentId|")) { $latest["$assignmentId|"] } else { $null }
        $state = if ($latestTask) { & $text $latestTask.P 'provisioningState' } else { '' }
        $total = if ($latestTask) { & $number $latestTask.P 'deploymentStatus.totalDeployments' } else { 0 }
        $ok = if ($latestTask) { & $number $latestTask.P 'deploymentStatus.successfulDeployments' } else { 0 }
        $failed = if ($latestTask) { & $number $latestTask.P 'deploymentStatus.failedDeployments' } else { 0 }
        $identity = if ($a) { & $text $a 'identityType' } else { '' }
        $findings = [System.Collections.Generic.List[object]]::new()
        if ($a -and (-not $identity -or $identity -eq 'None')) { $findings.Add(@{ S = 'High'; T = 'The assignment has no managed identity: nothing can deploy or modify for it. Assign it a system- or user-assigned identity with the roles its policies list.' }) }
        if ($latestTask -and ($state -eq 'Failed' -or $failed -gt 0)) { $findings.Add(@{ S = 'High'; T = "The latest remediation task $(if ($state -eq 'Failed') { 'failed' } else { "had $failed failed deployment(s)" }) - check the identity's roles (Invoke-AACPolicyAssessment) and the deployment errors in the task." }) }
        elseif (-not $latestTask) { $findings.Add(@{ S = 'Medium'; T = "Never remediated: $count resource(s) could be fixed by a remediation task." }) }
        elseif ($state -in 'Accepted', 'Running', 'Evaluating') { $findings.Add(@{ S = 'Info'; T = 'A remediation task is running.' }) }
        elseif ($latestTask.When -and ($Now - $latestTask.When).TotalDays -ge 1) { $findings.Add(@{ S = 'Low'; T = "Remediated on $($latestTask.When.ToString('yyyy-MM-dd')), yet $count resource(s) are non-compliant again: run it again, or check the policy's existence condition can be met." }) }
        if ($a -and (& $text $a 'enforcement') -eq 'DoNotEnforce') { $findings.Add(@{ S = 'Info'; T = 'Enforcement is off (DoNotEnforce): new resources aren''t remediated automatically - existing ones still can be with a task.' }) }
        $worst = @($findings | Sort-Object { $rank[$_.S] } | Select-Object -First 1)
        $item = [pscustomobject][ordered]@{
            Severity     = $(if ($worst.Count) { $worst[0].S } else { 'Info' })
            Assignment   = $(if ($a -and (& $text $a 'displayName')) { & $text $a 'displayName' } else { ($assignmentId -split '/')[-1] })
            Policy       = $policy
            Effect       = $(if ((& $text $row 'effect') -eq 'modify') { 'Modify' } else { 'DeployIfNotExists' })
            AssignedAt   = $(if ($a) { & $scopeName (& $text $a 'scope') } else { '' })
            NonCompliant = $count
            Subscriptions = & $number $row 'subscriptions'
            LastTask     = $(if ($latestTask) { $state } else { 'Never' })
            LastTaskOn   = $(if ($latestTask) { $latestTask.When } else { $null })
            Deployments  = $(if ($latestTask) { "$ok of $total succeeded" } else { '' })
            Failed       = $failed
            Findings     = (@($findings | ForEach-Object { $_.T }) -join ' ')
            Identity     = $(if ($identity) { $identity } else { 'None' })
            AssignmentId = $assignmentId
            DefinitionId = $definitionId
            ReferenceId  = $reference
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.PolicyRemediation')
        $rows.Add($item)
    }
    $sorted = @($rows | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = 'NonCompliant'; Descending = $true }, Assignment, Policy)
    $fixable = 0; foreach ($r in $sorted) { $fixable += $r.NonCompliant }
    @{
        Remediations = $sorted
        Notices      = @($notices)
        Stats        = @{
            Policies = $sorted.Count
            Fixable  = $fixable
            Never    = @($sorted | Where-Object LastTask -EQ 'Never').Count
            Failed   = @($sorted | Where-Object { $_.Failed -gt 0 -or $_.LastTask -eq 'Failed' }).Count
            High     = @($sorted | Where-Object Severity -EQ 'High').Count
        }
    }
}
