function Get-AACFailoverReadiness {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        How ready you are to recover: each workload's backups (fresh,
        succeeding, ever restored) and Site Recovery replication (healthy,
        within its RPO, failover tested and possible), the vaults' settings,
        and the recovery plans and their runbooks - with a recovery
        confidence score and RPO on track or at risk.
    .DESCRIPTION
        Reads, read-only:
          Resource Graph     the VMs, the Recovery Services vaults (redundancy,
                             cross-region restore, soft delete, immutability),
                             every backed-up item (last backup, its status,
                             protection state) and the restore jobs
          Resource Manager   each vault's Site Recovery replicated items
                             (replication health, RPO, last test failover,
                             what operations are allowed now) and recovery
                             plans; each runbook a plan runs (does it exist,
                             is it published?)
        Each workload (AAC.FailoverReadiness) - every VM, and every other
        backed-up item - gets its protection (Backup, Site Recovery, both or
        none), its findings, a confidence score (0-100), and its RPO against
        the target: -RpoMinutes for replication, -BackupRpoHours for backup.
        The vaults and recovery plans add their own findings.

        Nothing is failed over, test or otherwise: a recovery plan's
        runbooks are checked to exist and be published - the part that
        breaks silently - and the last test failover's date is reported. The
        measured RTO comes from a test failover; run one with the plan.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only the VMs and vaults in these resource groups.
    .PARAMETER RpoMinutes
        The replication RPO target, in minutes (15 by default).
    .PARAMETER BackupRpoHours
        The backup RPO target: the oldest a last backup may be, in hours (24
        by default).
    .PARAMETER TestFailoverDays
        A test failover older than this (or none) is a finding (180 by
        default).
    .PARAMETER RestoreTestDays
        No successful restore in this many days is a finding (180 by
        default).
    .PARAMETER CsvPath
        Write the workloads to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the workloads.
    .PARAMETER NoDisplay
        Return the workloads without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACFailoverReadiness
        Every workload's recovery readiness, least ready first.
    .EXAMPLE
        Get-AACFailoverReadiness -ResourceGroupName 'rg-erp-prod' -RpoMinutes 5 -BackupRpoHours 12 -HtmlPath .\out\DR.html
        The ERP workloads against tighter targets, as a report.
    .EXAMPLE
        Get-AACFailoverReadiness -NoDisplay | Where-Object Rpo -EQ 'At risk'
        The workloads that would lose more data than the target allows.
    .OUTPUTS
        AAC.FailoverReadiness
    #>
    [CmdletBinding()]
    [OutputType('AAC.FailoverReadiness')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [ValidateRange(1, 1440)]
        [int] $RpoMinutes = 15,

        [ValidateRange(1, 720)]
        [int] $BackupRpoHours = 24,

        [ValidateRange(1, 3650)]
        [int] $TestFailoverDays = 180,

        [ValidateRange(1, 3650)]
        [int] $RestoreTestDays = 180,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Failover readiness',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); RestoreTestDays = $RestoreTestDays }
    $targets = @{ RpoMinutes = $RpoMinutes; BackupRpoHours = $BackupRpoHours; TestFailoverDays = $TestFailoverDays; RestoreTestDays = $RestoreTestDays }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Failover readiness' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
        $groupFilter = if ($request.ResourceGroupName.Count) { " | where resourceGroup in~ ($((@($request.ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
        $queries = [ordered]@{
            vms      = "resources | where type =~ 'microsoft.compute/virtualmachines'$groupFilter | project id = tolower(id), name, resourceGroup, subscriptionId, location"
            vaults   = "resources | where type =~ 'microsoft.recoveryservices/vaults'$groupFilter | project id = tolower(id), name, resourceGroup, subscriptionId, location, redundancy = tostring(properties.redundancySettings.standardTierStorageRedundancy), crossRegionRestore = tostring(properties.redundancySettings.crossRegionRestore), softDelete = tostring(properties.securitySettings.softDeleteSettings.softDeleteState), immutability = tostring(properties.securitySettings.immutabilitySettings.state)"
            items    = "recoveryservicesresources | where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' | project id = tolower(id), vault = tolower(tostring(split(id, '/backupFabrics/')[0])), item = tostring(properties.friendlyName), sourceId = tolower(tostring(properties.sourceResourceId)), workloadType = tostring(properties.workloadType), protectionState = tostring(properties.protectionState), lastBackupStatus = tostring(properties.lastBackupStatus), lastBackupTime = tostring(properties.lastBackupTime), policy = tostring(properties.policyName)"
            restores = "recoveryservicesresources | where type =~ 'microsoft.recoveryservices/vaults/backupjobs' | where tostring(properties.operation) has 'Restore' and todatetime(properties.startTime) > ago($($request.RestoreTestDays)d) | project id, entity = tostring(properties.entityFriendlyName), status = tostring(properties.status), start = tostring(properties.startTime)"
        }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading the VMs, vaults, backups and restores'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('items', 'restores') -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total)" }
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $read.Errors.Keys) { if ($read.Errors[$key]) { $notices.Add("The $(@{ items = 'backup items'; restores = 'restore jobs' }[$key]) couldn't be read: $($read.Errors[$key])") } }
        $vaults = @($read.Rows['vaults'] | Where-Object { $_ })
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} VM(s), {1:N0} vault(s), {2:N0} backup item(s)' -f @($read.Rows['vms']).Count, $vaults.Count, @($read.Rows['items']).Count)

        # --- Site Recovery, per vault; then the runbooks the recovery plans run -----------------------------------------
        $replicated = [System.Collections.Generic.List[object]]::new()
        $plans = [System.Collections.Generic.List[object]]::new()
        $runbooks = @{}
        if ($vaults.Count) {
            $uris = [ordered]@{}
            foreach ($v in $vaults) {
                $uris["$($v['id'])|items"] = "$($v['id'])/replicationProtectedItems?api-version=2023-08-01"
                $uris["$($v['id'])|plans"] = "$($v['id'])/replicationRecoveryPlans?api-version=2023-08-01"
            }
            Update-AACProgress -Id 'asr' -Total $uris.Count -Description "Reading Site Recovery in $($vaults.Count) vault(s)"
            $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($AsrDone, $AsrTotal) Update-AACProgress -Id 'asr' -Increment 1 }
            foreach ($key in $uris.Keys) {
                $vaultId, $kind = $key.Split('|')
                $answer = $answers[$uris[$key]]
                if (-not $answer -or $answer.Error) { $notices.Add("Site Recovery $kind of $(($vaultId -replace '^.*/', '')) couldn't be read: $(if ($answer) { $answer.Error })"); continue }
                foreach ($item in @($answer.Items | Where-Object { $_ })) { $item['vault'] = $vaultId; if ($kind -eq 'items') { $replicated.Add($item) } else { $plans.Add($item) } }
            }
            $runbookIds = @(foreach ($plan in $plans) { foreach ($g in @($plan['properties']['groups'])) { foreach ($a in @(@($g['startGroupActions']) + @($g['endGroupActions']) | Where-Object { $_ })) { if ($a['customDetails'] -and [string]$a['customDetails']['instanceType'] -eq 'AutomationRunbookActionDetails') { ([string]$a['customDetails']['runbookId']).ToLowerInvariant() } } } }) | Select-Object -Unique
            if (@($runbookIds).Count) {
                $runbookAnswers = Invoke-AACArmParallel -Uri @($runbookIds | ForEach-Object { "$($_)?api-version=2023-11-01" })
                foreach ($id in $runbookIds) {
                    $answer = $runbookAnswers["$($id)?api-version=2023-11-01"]
                    $runbooks[$id] = if (-not $answer -or $answer.Error) { @{ State = ''; Error = $(if ($answer) { $answer.Error } else { 'no answer' }) } } else { @{ State = [string]$answer.Body['properties']['state']; Error = '' } }
                }
            }
            Update-AACProgress -Id 'asr' -Complete -Description ('Read {0:N0} replicated item(s), {1:N0} recovery plan(s), {2:N0} runbook(s)' -f $replicated.Count, $plans.Count, $runbooks.Count)
        }
        $result = ConvertTo-AACFailoverReadiness -Vm @($read.Rows['vms'] | Where-Object { $_ }) -Vault $vaults -BackupItem @($read.Rows['items'] | Where-Object { $_ }) -RestoreJob @($read.Rows['restores'] | Where-Object { $_ }) `
            -ReplicatedItem $replicated.ToArray() -RecoveryPlan $plans.ToArray() -Runbook $runbooks -SubscriptionName $scope.Names @targets
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $result = $state.Result
    $workloads = @($result.Workloads)
    $s = $result.Stats
    $rank = Get-AACSeverityRank
    $report = @{
        Subtitle = 'Failover readiness: backups, Site Recovery, vaults and recovery plans'
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'RPO targets' = "replication $RpoMinutes min, backup $BackupRpoHours h"; 'Tests within' = "$TestFailoverDays days (failover), $RestoreTestDays days (restore)" }
        Status   = $(if ($s.High) { 'Failed' } elseif ($s.Ready -lt $s.Workloads) { 'Warning' } else { 'Success' })
        Headline = $(if ($s.Workloads) { "Recovery confidence $($s.Confidence)/100 across $($s.Workloads) workload(s): $($s.Unprotected) unprotected, $($s.AtRisk) with RPO at risk, $($s.Ready) ready" } else { 'No workloads in scope.' })
        Tiles    = @(
            @{ Value = $(if ($null -ne $s.Confidence) { "$($s.Confidence)" } else { '-' }); Label = 'recovery confidence (of 100)'; Tone = $(if ($null -eq $s.Confidence) { 'neutral' } elseif ($s.Confidence -ge 80) { 'good' } elseif ($s.Confidence -ge 50) { 'warn' } else { 'bad' }) }
            @{ Value = '{0:N0}' -f $s.Unprotected; Label = 'unprotected'; Tone = $(if ($s.Unprotected) { 'bad' } else { 'good' }); Table = 'workloads'; Filters = @{ Protection = 'None' } }
            @{ Value = '{0:N0}' -f $s.AtRisk; Label = 'RPO at risk'; Tone = $(if ($s.AtRisk) { 'bad' } else { 'good' }); Table = 'workloads'; Filters = @{ Rpo = 'At risk' } }
            @{ Value = '{0:N0}' -f $s.Replicated; Label = 'replicated (Site Recovery)'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $s.Ready; Label = 'ready'; Tone = 'good' }
            @{ Value = '{0:N0}' -f $s.Plans; Label = 'recovery plans'; Tone = 'violet'; Table = 'findings' }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Workloads by protection'; Kind = 'donut'; CenterLabel = 'workloads'; Items = @($workloads | Group-Object Protection | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = @{ None = 'bad'; Backup = 'warn'; 'Site Recovery' = 'info'; 'Backup and Site Recovery' = 'good' }[$_.Name]; Filter = $_.Name } }); Table = 'workloads'; Column = 'Protection'; Console = $true }
            @{ Title = 'Least ready'; Items = @($workloads | Sort-Object Confidence | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Resource; Value = $_.Confidence; Filter = $_.Resource } }); Table = 'workloads'; Column = 'Resource'; Tone = 'warn' }
        )
        Tables   = @(
            @{ Id = 'workloads'; Title = 'Workloads'; Section = 'Workloads'; Rows = $workloads; Noun = 'workloads'; GroupBy = @('Protection', 'Severity', 'Rpo', 'Subscription'); ConsoleLimit = 25
                Empty = 'No VMs or backed-up items in scope.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Workload'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Protection'; Label = 'Protection'; Type = 'badge'; Tones = @{ None = 'bad'; Backup = 'warn'; 'Site Recovery' = 'info'; 'Backup and Site Recovery' = 'good' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Confidence'; Label = 'Confidence'; Type = 'score'; Console = $true; Pdf = $true }
                    @{ Key = 'Rpo'; Label = 'RPO'; Type = 'badge'; Tones = @{ 'On track' = 'good'; 'At risk' = 'bad'; 'n/a' = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Findings'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'BackupAgeHours'; Label = 'Last backup (h)'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'LastBackupStatus'; Label = 'Backup status'; Facet = $true }
                    @{ Key = 'LastRestoreTest'; Label = 'Last restore'; Type = 'datetime' }
                    @{ Key = 'ReplicationHealth'; Label = 'Replication'; Facet = $true }
                    @{ Key = 'RpoMinutes'; Label = 'RPO (min)'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'LastTestFailover'; Label = 'Last test failover'; Type = 'datetime' }
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'mono'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide' }
                ) }
            @{ Id = 'findings'; Title = 'Vaults and recovery plans'; Section = 'Vaults and plans'; Rows = $result.Findings; Noun = 'findings'; ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Effort'; Label = 'Effort'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-RpoMinutes and -BackupRpoHours set the targets; -NoDisplay returns the workloads; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $workloads -Noun 'workload' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $workloads -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
