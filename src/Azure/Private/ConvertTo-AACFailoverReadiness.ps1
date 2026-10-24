function ConvertTo-AACFailoverReadiness {
    <#
    .SYNOPSIS
        Rates how ready each workload is to recover - its backups (fresh,
        succeeding, ever restored), its Site Recovery replication (healthy,
        within the RPO target, failover tested and allowed) - and checks the
        vaults and recovery plans (their runbooks exist and are published),
        with a recovery confidence score for each.
    .DESCRIPTION
        Workloads: every VM in scope, and every other backed-up item (Azure
        Files, SQL in VMs, SAP HANA...). Findings:
          High    not protected at all; the last backup failed, or is older
                  than -BackupRpoHours; protection stopped or in error;
                  replication critical or over -RpoMinutes; failover not
                  allowed now
          Medium  no successful restore in -RestoreTestDays; no test
                  failover in -TestFailoverDays (or ever); replication with
                  warnings
          Low     backed up but not replicated (no regional disaster
                  recovery)
        Confidence (0-100) starts at 100 and loses: unprotected 100; backup
        failed or stale 40; failover not allowed 40; RPO over target 30;
        replication critical 30; no test failover 20; no restore test 15;
        not replicated 10; its vault locally redundant 10 or without soft
        delete 10.
        RPO: the replication's RPO, or the age of the last backup, against
        the target - On track or At risk.
        Vaults: locally redundant (Medium), soft delete off (High),
        cross-region restore off on a geo-redundant vault (Low), no
        immutability (Low). Recovery plans: no test failover (Medium); a
        runbook action whose runbook is missing or not published (High).
        Returns @{ Workloads (AAC.FailoverReadiness); Findings (vaults and
        plans, AAC.FailoverFinding); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $Vm = @(),
        [AllowEmptyCollection()] [object[]] $Vault = @(),
        [AllowEmptyCollection()] [object[]] $BackupItem = @(),
        [AllowEmptyCollection()] [object[]] $RestoreJob = @(),
        # Site Recovery replicated items (Resource Manager), each with a 'vault' (its ID).
        [AllowEmptyCollection()] [object[]] $ReplicatedItem = @(),
        # Recovery plans (Resource Manager), each with a 'vault'.
        [AllowEmptyCollection()] [object[]] $RecoveryPlan = @(),
        # Runbook ID (lower case) -> @{ State; Error }.
        [System.Collections.IDictionary] $Runbook = @{},
        [System.Collections.IDictionary] $SubscriptionName = @{},
        [int] $BackupRpoHours = 24,
        [int] $RpoMinutes = 15,
        [int] $TestFailoverDays = 180,
        [int] $RestoreTestDays = 180,
        [datetime] $Now = [datetime]::UtcNow
    )

    $Now = $Now.ToUniversalTime()
    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $props = { param($Row) $p = & $get $Row 'properties'; if ($p) { $p } else { @{} } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) ([string]$Id).TrimEnd('/') -replace '^.*/', '' }
    $time = { param($Raw) if ($Raw -is [datetime]) { $Raw.ToUniversalTime() } else { $d = [datetime]::MinValue; if ($Raw -and [datetime]::TryParse([string]$Raw, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$d) -and $d.Year -gt 1900) { $d } else { $null } } }
    $subOf = { param($Id) if ([string]$Id -match '(?i)^/subscriptions/([^/]+)') { $s = $Matches[1].ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { [string]$SubscriptionName[$s] } else { $s } } else { '' } }
    $severity = Get-AACSeverityRank

    # --- Vaults ------------------------------------------------------------------------------------------------
    $vaults = @{}
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($v in $Vault) {
        $id = & $lower (& $get $v 'id')
        $redundancy = [string](& $get $v 'redundancy')
        $soft = [string](& $get $v 'softDelete')
        $vaults[$id] = @{ Name = [string](& $get $v 'name'); Lrs = $redundancy -eq 'LocallyRedundant'; SoftOff = $soft -eq 'Disabled' }
        $add = { param([string] $Severity, [string] $Text, [string] $Fix, [string] $Effort) $findings.Add((New-AACFinding -TypeName 'AAC.FailoverFinding' -Severity $Severity -Category 'Recovery Services vault' -Finding "$(& $get $v 'name'): $Text" -ResourceId $id -Subscription (& $subOf $id) -Remediation $Fix -Effort $Effort -Link 'https://learn.microsoft.com/azure/backup/backup-azure-security-feature')) }
        if ($soft -eq 'Disabled') { & $add 'High' 'soft delete is off - deleted backups are gone at once' 'Turn on soft delete (always-on, ideally) so deleted backup data is kept 14 days or more.' 'Low' }
        if ($redundancy -eq 'LocallyRedundant') { & $add 'Medium' 'backups are locally redundant - lost with the region' 'Use geo-redundant storage (set before the first backup; otherwise a new vault) and turn on cross-region restore.' 'High' }
        elseif ($redundancy -eq 'GeoRedundant' -and [string](& $get $v 'crossRegionRestore') -ne 'Enabled') { & $add 'Low' 'cross-region restore is off - the copy in the paired region can''t be restored from there' 'Turn on cross-region restore on the vault.' 'Low' }
        if ([string](& $get $v 'immutability') -notin 'Locked', 'Unlocked') { & $add 'Low' 'no immutability - backups can be shortened or deleted early' 'Enable immutability (and lock it) so recovery points can''t be removed before they expire.' 'Low' }
    }

    # --- Backups and restores, by the protected resource -----------------------------------------------------------
    $backups = @{}
    foreach ($b in $BackupItem) {
        $source = & $lower (& $get $b 'sourceId')
        $key = if ($source) { $source } else { & $lower (& $get $b 'id') }
        $backups[$key] = $b
    }
    $restores = @{}
    foreach ($j in $RestoreJob) {
        if ([string](& $get $j 'status') -notin 'Completed', 'CompletedWithWarnings') { continue }
        $name = & $lower (& $get $j 'entity'); $when = & $time (& $get $j 'start')
        if ($when -and (-not $restores.Contains($name) -or $restores[$name] -lt $when)) { $restores[$name] = $when }
    }
    $replicas = @{}
    foreach ($r in $ReplicatedItem) {
        $p = & $props $r
        $details = & $get $p 'providerSpecificDetails'
        $source = & $lower (& $get $details 'fabricObjectId')
        $key = if ($source) { $source } else { & $lower (& $get $p 'friendlyName') }
        $replicas[$key] = $r
    }

    # --- Each workload -------------------------------------------------------------------------------------------
    $workloads = [System.Collections.Generic.List[object]]::new()
    $assess = {
        param([string] $Name, [string] $Type, [string] $ResourceId, $Backup, $Replica)
        $issues = [System.Collections.Generic.List[object]]::new()
        $score = 100
        $issue = { param([string] $Sev, [string] $Text, [string] $Fix, [int] $Cost) $issues.Add(@{ Severity = $Sev; Text = $Text; Fix = $Fix }); Set-Variable -Name score -Scope 1 -Value ($score - $Cost) }
        $backupAge = $null; $lastStatus = ''; $restore = $null; $rpo = $null; $health = ''; $lastTest = $null
        if (-not $Backup -and -not $Replica) { & $issue 'High' 'Not protected: no backup and no replication' 'Back it up (Azure Backup) - and replicate it with Site Recovery if it must survive a regional outage.' 100 }
        if ($Backup) {
            $bp = $Backup
            $last = & $time (& $get $bp 'lastBackupTime')
            $lastStatus = [string](& $get $bp 'lastBackupStatus')
            $state = [string](& $get $bp 'protectionState')
            if ($last) { $backupAge = [Math]::Round(($Now - $last).TotalHours, 1) }
            if ($state -match 'Stopped|Error') { & $issue 'High' "Backup protection is $state" 'Resume protection, or fix the error the vault reports for this item.' 40 }
            elseif ($lastStatus -eq 'Failed') { & $issue 'High' 'The last backup failed' 'Look at the failed job in the vault (Backup jobs) and fix its cause; then run a backup now.' 40 }
            elseif ($null -eq $backupAge -or $backupAge -gt $BackupRpoHours) { & $issue 'High' $(if ($null -eq $backupAge) { 'Never backed up' } else { "The last backup is $([int]$backupAge) hours old (target $BackupRpoHours)" }) 'Check the backup policy runs as scheduled, and run a backup now.' 40 }
            $restore = if ($restores.Contains((& $lower $Name))) { $restores[(& $lower $Name)] } else { $null }
            if (-not $restore -or ($Now - $restore).TotalDays -gt $RestoreTestDays) { & $issue 'Medium' "No successful restore in $RestoreTestDays days - the backup is untested" 'Test a restore (to a new VM, or files) on a schedule - a backup only counts once it has been restored.' 15 }
            $vaultId = & $lower ((& $get $bp 'vault'))
            if ($vaults.Contains($vaultId)) { if ($vaults[$vaultId].Lrs) { $score -= 10 }; if ($vaults[$vaultId].SoftOff) { $score -= 10 } }
        }
        if ($Replica) {
            $p = & $props $Replica
            $details = & $get $p 'providerSpecificDetails'
            $health = [string](& $get $p 'replicationHealth')
            $seconds = & $get $details 'rpoInSeconds'
            if ($null -ne $seconds) { $rpo = [Math]::Round([double]$seconds / 60, 1) }
            $lastTest = & $time (& $get $p 'lastSuccessfulTestFailoverTime')
            $allowed = @(& $get $p 'allowedOperations')
            if ($health -eq 'Critical') { & $issue 'High' "Replication is critical: $(@(& $get $p 'healthErrors' | ForEach-Object { [string](& $get $_ 'errorMessage') } | Select-Object -First 2) -join '; ')" 'Fix the replication errors in the vault (Replicated items) before you need it.' 30 }
            elseif ($health -eq 'Warning') { & $issue 'Medium' 'Replication has warnings' 'Look at the replicated item''s health in the vault.' 10 }
            if ($null -ne $rpo -and $rpo -gt $RpoMinutes) { & $issue 'High' "The RPO is $rpo minutes (target $RpoMinutes)" 'Check the source''s data change rate against the replication''s limits, and the network to the target region.' 30 }
            if (-not $lastTest -or ($Now - $lastTest).TotalDays -gt $TestFailoverDays) { & $issue 'Medium' $(if ($lastTest) { "The last test failover was $([int]($Now - $lastTest).TotalDays) days ago" } else { 'Never test-failed over' }) 'Run a test failover (it doesn''t touch production) and clean it up - it''s the only proof the recovery works.' 20 }
            if ($allowed.Count -and -not @($allowed | Where-Object { $_ -in 'UnplannedFailover', 'PlannedFailover', 'Failover' }).Count) { & $issue 'High' 'Failover isn''t possible right now' 'Look at the replicated item: it may be resynchronising, or in a state that blocks failover.' 40 }
        }
        elseif ($Backup -and $Type -eq 'microsoft.compute/virtualmachines') { & $issue 'Low' 'Backed up but not replicated: it can''t fail over to another region' 'If it must survive a regional outage, replicate it with Site Recovery (or rebuild it elsewhere from infrastructure as code and its backup).' 10 }
        $score = [Math]::Max(0, [Math]::Min(100, $score))
        $rpoActual = if ($null -ne $rpo) { $rpo } elseif ($null -ne $backupAge) { $backupAge * 60 } else { $null }
        $rpoTarget = if ($Replica) { $RpoMinutes } else { $BackupRpoHours * 60 }
        $worst = @($issues | Sort-Object -Property { $severity.Rank[$_.Severity] } | Select-Object -First 1)
        $workloads.Add((New-AACFinding -TypeName 'AAC.FailoverReadiness' -Severity $(if ($worst.Count) { $worst[0].Severity } else { 'Info' }) -Category 'Workload' -Finding $(if ($issues.Count) { ($issues | ForEach-Object { $_.Text }) -join '; ' } else { 'Ready: backed up, replicated and tested' }) `
                    -Resource $Name -ResourceType $Type -ResourceId $ResourceId -Subscription (& $subOf $ResourceId) -Detail ((@($(if ($Backup) { "Backup: $(if ($null -ne $backupAge) { "$backupAge h ago" } else { 'none yet' }), $lastStatus" }), $(if ($Replica) { "Replication: $health, RPO $(if ($null -ne $rpo) { "$rpo min" } else { 'n/a' })" })) | Where-Object { $_ }) -join '; ') `
                    -Remediation (@($issues | ForEach-Object { $_.Fix } | Select-Object -Unique) -join ' ') -Effort $(if ($issues | Where-Object { $_.Text -like 'Not protected*' }) { 'Medium' } elseif ($issues.Count) { 'Low' } else { '' }) -Link 'https://learn.microsoft.com/azure/reliability/business-continuity-management-program' -Property ([ordered]@{
                        Protection = $(if ($Backup -and $Replica) { 'Backup and Site Recovery' } elseif ($Backup) { 'Backup' } elseif ($Replica) { 'Site Recovery' } else { 'None' })
                        Confidence = $score; BackupAgeHours = $backupAge; LastBackupStatus = $lastStatus; LastRestoreTest = $restore; ReplicationHealth = $health; RpoMinutes = $rpo; LastTestFailover = $lastTest
                        Rpo = $(if ($null -eq $rpoActual) { 'n/a' } elseif ($rpoActual -le $rpoTarget) { 'On track' } else { 'At risk' }); Issues = $issues.Count
                    })))
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($v in $Vm) {
        $id = & $lower (& $get $v 'id')
        [void]$seen.Add($id)
        $name = [string](& $get $v 'name')
        $replica = if ($replicas.Contains($id)) { $replicas[$id] } elseif ($replicas.Contains((& $lower $name))) { $replicas[(& $lower $name)] } else { $null }
        & $assess $name 'microsoft.compute/virtualmachines' $id $(if ($backups.Contains($id)) { $backups[$id] }) $replica
    }
    foreach ($key in $backups.Keys) {
        if ($seen.Contains($key)) { continue }
        $b = $backups[$key]
        if ([string](& $get $b 'workloadType') -eq 'VM') { continue }   # a VM out of scope
        & $assess ([string](& $get $b 'item')) ([string](& $get $b 'workloadType')) $key $b $null
    }

    # --- Recovery plans ----------------------------------------------------------------------------------------------
    foreach ($plan in $RecoveryPlan) {
        $p = & $props $plan
        $name = [string]$(if (& $get $p 'friendlyName') { & $get $p 'friendlyName' } else { & $get $plan 'name' })
        $id = [string](& $get $plan 'id')
        $add = { param([string] $Severity, [string] $Text, [string] $Fix) $findings.Add((New-AACFinding -TypeName 'AAC.FailoverFinding' -Severity $Severity -Category 'Recovery plan' -Finding "$($name): $Text" -ResourceId $id -Subscription (& $subOf $id) -Remediation $Fix -Effort 'Low' -Link 'https://learn.microsoft.com/azure/site-recovery/site-recovery-test-failover-to-azure')) }
        $lastTest = & $time (& $get $p 'lastTestFailoverTime')
        if (-not $lastTest -or ($Now - $lastTest).TotalDays -gt $TestFailoverDays) { & $add 'Medium' $(if ($lastTest) { "last test failover $([int]($Now - $lastTest).TotalDays) days ago" } else { 'never test-failed over' }) 'Run a test failover of the whole plan - the order, the scripts and the runbooks - and record how long it took (the measured RTO).' }
        $actions = @(foreach ($g in @(& $get $p 'groups')) { @(& $get $g 'startGroupActions') + @(& $get $g 'endGroupActions') })
        foreach ($a in @($actions | Where-Object { $_ })) {
            $custom = & $get $a 'customDetails'
            if ([string](& $get $custom 'instanceType') -ne 'AutomationRunbookActionDetails') { continue }
            $runbookId = & $lower (& $get $custom 'runbookId')
            $known = if ($Runbook.Contains($runbookId)) { $Runbook[$runbookId] } else { @{ State = ''; Error = 'not checked' } }
            if ($known.Error) { & $add 'High' "the runbook $(& $leaf $runbookId) (action '$(& $get $a 'actionName')') can't be found: $($known.Error)" 'Point the action at a runbook that exists, or restore the runbook - a failover would stop at this step.' }
            elseif ($known.State -ne 'Published') { & $add 'High' "the runbook $(& $leaf $runbookId) (action '$(& $get $a 'actionName')') isn't published ($($known.State))" 'Publish the runbook: only the published version runs during a failover.' }
        }
    }

    $wl = @($workloads | Sort-Object -Property @{ Expression = { $severity.Rank[$_.Severity] } }, Confidence, Resource)
    $vf = @($findings | Sort-Object -Property @{ Expression = { $severity.Rank[$_.Severity] } }, Category, Finding)
    @{
        Workloads = $wl
        Findings  = $vf
        Stats     = @{
            Workloads    = $wl.Count
            Unprotected  = @($wl | Where-Object Protection -EQ 'None').Count
            AtRisk       = @($wl | Where-Object Rpo -EQ 'At risk').Count
            Ready        = @($wl | Where-Object Issues -EQ 0).Count
            High         = @(@($wl) + @($vf) | Where-Object { $_.Severity -in 'Critical', 'High' }).Count
            Replicated   = @($wl | Where-Object Protection -Like '*Site Recovery').Count
            Confidence   = $(if ($wl.Count) { [int][Math]::Round((@($wl | ForEach-Object { $_.Confidence }) | Measure-Object -Average).Average) } else { $null })
            Plans        = @($RecoveryPlan).Count
        }
    }
}
