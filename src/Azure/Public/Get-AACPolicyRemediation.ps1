function Get-AACPolicyRemediation {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the DeployIfNotExists and Modify policies with non-compliant
        resources they could fix - and what their remediation tasks did:
        never run, failed, succeeded yet drifted again, or still running.
    .DESCRIPTION
        Reads, read-only:
          Resource Graph     the resources DeployIfNotExists and Modify
                             policies find non-compliant, per assignment and
                             policy; every assignment (tenant-wide) with its
                             identity and enforcement; the policies' names
          Resource Manager   the remediation tasks of each subscription and
                             management group in scope
        Each policy (AAC.PolicyRemediation): its assignment and where it is
        assigned, effect, non-compliant resources, the latest remediation
        task (state, when, deployments succeeded and failed), the
        assignment's identity, and a finding:
          High    the latest task failed or had failed deployments; or the
                  assignment has no managed identity
          Medium  never remediated
          Low     remediated, yet non-compliant again
          Info    a task is running; enforcement off
        Invoke-AACPolicyAssessment checks the identities' roles, deprecated
        and missing definitions and unused custom ones; this is the
        remediation side. Reader is enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Severity
        Only these severities (High, Medium, Low, Info).
    .PARAMETER CsvPath
        Write the policies to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the policies.
    .PARAMETER NoDisplay
        Return the policies without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACPolicyRemediation
        Every policy that could fix what it finds, the failing ones first.
    .EXAMPLE
        Get-AACPolicyRemediation -Severity High, Medium -NoDisplay | Select-Object Assignment, Policy, NonCompliant, LastTask
        What to remediate, as objects.
    .OUTPUTS
        AAC.PolicyRemediation
    #>
    [CmdletBinding()]
    [OutputType('AAC.PolicyRemediation')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('High', 'Medium', 'Low', 'Info')]
        [string[]] $Severity,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Policy remediation',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }) }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Policy remediation' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $query = Get-AACPolicyRemediationQuery
        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the non-compliant resources DeployIfNotExists and Modify policies could fix'
        $read = Invoke-AACGraphBatch -Query $query -SubscriptionId $scope.GraphScope -AllowFailure @('assignments')
        $fixable = @($read.Rows['fixable'] | Where-Object { $_ })
        Update-AACProgress -Id 'read' -Complete -Description ('{0:N0} polic(ies) could fix non-compliant resources' -f $fixable.Count)

        # The policies' names.
        $definitions = @{}
        $ids = @($fixable | ForEach-Object { [string]$_['definitionId'] } | Where-Object { $_ } | Select-Object -Unique)
        if ($ids.Count) {
            $nameQuery = Get-AACPolicyAssessmentQuery -Stage Definitions -Id $ids
            # Names only make the list easier to read: a failed read leaves the definition IDs.
            $names = Invoke-AACGraphBatch -Query $nameQuery -AllowFailure @($nameQuery.Keys)
            foreach ($key in @($names.Rows.Keys)) { foreach ($row in @($names.Rows[$key] | Where-Object { $_ })) { $definitions[([string]$row['id']).ToLowerInvariant()] = $row } }
        }

        # The remediation tasks: each subscription's, and each management group's above them.
        $uris = [ordered]@{}
        foreach ($id in $scope.Ids) { $uris[$scope.Names[$id.ToLowerInvariant()]] = "/subscriptions/$id/providers/Microsoft.PolicyInsights/remediations?api-version=2021-10-01" }
        $groups = @($scope.Subscriptions | ForEach-Object { @($_['chain']) | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { [string]$_['name'] } } | Select-Object -Unique)
        foreach ($g in $groups) { $uris["management group $g"] = "/providers/Microsoft.Management/managementGroups/$g/providers/Microsoft.PolicyInsights/remediations?api-version=2021-10-01" }
        Update-AACProgress -Id 'tasks' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading the remediation tasks of $($uris.Count) scope(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($TaskDone, $TaskTotal) Update-AACProgress -Id 'tasks' -Increment 1 }
        $tasks = [System.Collections.Generic.List[object]]::new()
        $unread = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $uris.Keys) {
            $answer = $answers[$uris[$name]]
            if (-not $answer -or $answer.Error) { if ($name -notlike 'management group *') { $unread.Add("$name ($(if ($answer) { $answer.Error } else { 'no answer' }))") }; continue }
            foreach ($t in @($answer.Items | Where-Object { $null -ne $_ })) { $tasks.Add($t) }
        }
        Update-AACProgress -Id 'tasks' -Complete -Description ('Read {0:N0} remediation task(s)' -f $tasks.Count)
        @{ Result = (ConvertTo-AACPolicyRemediation -Read $read -Definition $definitions -Task $tasks.ToArray() -Unread $unread.ToArray()); Scope = $scope }
    }

    $rows = @($outcome.Result.Remediations)
    if ($Severity) { $rows = @($rows | Where-Object { $Severity -contains $_.Severity }) }
    $s = $outcome.Result.Stats
    $rank = Get-AACSeverityRank
    $taskTones = @{ Never = 'warn'; Succeeded = 'good'; Failed = 'bad'; Canceled = 'neutral'; Running = 'info'; Accepted = 'info'; Evaluating = 'info' }
    $report = @{
        Subtitle = 'Policy remediation: DeployIfNotExists and Modify policies with resources they could fix, and what their remediation tasks did'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label }
        Status   = $(if ($s.High) { 'Failed' } elseif ($s.Never) { 'Warning' } else { 'Success' })
        Headline = $(if ($rows.Count) { "$($s.Policies) polic(ies) could fix $($s.Fixable) non-compliant resource(s): $($s.Never) never remediated, $($s.Failed) with failed remediation" } else { 'No DeployIfNotExists or Modify policy has non-compliant resources to fix.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Policies; Label = 'policies to remediate'; Tone = $(if ($s.Policies) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $s.Fixable; Label = 'fixable resources'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $s.Never; Label = 'never remediated'; Tone = $(if ($s.Never) { 'warn' } else { 'good' }); Table = 'remediations'; Filters = @{ LastTask = 'Never' } }
            @{ Value = '{0:N0}' -f $s.Failed; Label = 'failed'; Tone = $(if ($s.Failed) { 'bad' } else { 'good' }); Table = 'remediations'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Most fixable resources'; Items = @($rows | Select-Object -First 12 | Sort-Object NonCompliant -Descending | ForEach-Object { @{ Label = "$($_.Policy) ($($_.Assignment))"; Value = $_.NonCompliant } }); Tone = 'warn'; Console = $true }
            @{ Title = 'Latest task'; Kind = 'donut'; CenterLabel = 'policies'; Items = @($rows | Group-Object LastTask | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $taskTones[$_.Name]; Filter = $_.Name } }); Table = 'remediations'; Column = 'LastTask' }
        )
        Tables   = @(
            @{ Id = 'remediations'; Title = 'Policies to remediate'; Section = 'Remediation'; Rows = $rows; Noun = 'policies'; GroupBy = @('Assignment'); ConsoleLimit = 25
                Empty = 'No DeployIfNotExists or Modify policy has non-compliant resources to fix.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Assignment'; Label = 'Assignment'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Policy'; Label = 'Policy'; Console = $true; Pdf = $true }
                    @{ Key = 'Effect'; Label = 'Effect'; Facet = $true; Console = $true }
                    @{ Key = 'NonCompliant'; Label = 'Non-compliant'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'LastTask'; Label = 'Latest task'; Type = 'badge'; Tones = $taskTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LastTaskOn'; Label = 'On'; Type = 'date' }
                    @{ Key = 'Deployments'; Label = 'Deployments' }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'AssignedAt'; Label = 'Assigned at' }
                    @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
                    @{ Key = 'AssignmentId'; Label = 'Assignment ID'; Type = 'mono' }
                ) }
        )
        Hint     = '-Severity narrows it; Invoke-AACPolicyAssessment checks the identities'' roles; -NoDisplay returns the policies; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'policy' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
