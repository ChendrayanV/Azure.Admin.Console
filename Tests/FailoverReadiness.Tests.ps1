<#
    Unit tests for Get-AACFailoverReadiness: made-up Contoso recovery
    (Fixtures\ContosoRecovery.ps1) - backups fresh, failed and stale,
    restores, Site Recovery health, RPO and test failovers, vault settings,
    recovery plans and their runbooks, the confidence score - and the
    command with Resource Graph and Resource Manager faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoRecovery.ps1')
    $script:f = Get-AACContosoRecovery
    $script:ready = {
        param([hashtable] $More = @{})
        $f = $script:f
        InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $f; M = $More } { param($F, $M) ConvertTo-AACFailoverReadiness -Vm $F.Vm -Vault $F.Vault -BackupItem $F.Items -RestoreJob $F.Restores -ReplicatedItem $F.Replicas -RecoveryPlan $F.Plans -Runbook $F.Runbooks -SubscriptionName $F.Names -Now $F.Now @M }
    }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 220
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - failover readiness' {
    BeforeAll { $script:r = & $script:ready }

    It 'rates every workload - least ready first - with its protection, confidence and RPO' {
        @($script:r.Workloads | ForEach-Object { "$($_.Resource) | $($_.Protection) | $($_.Confidence) | $($_.Rpo) | $($_.Severity)" }) | Should -Be @(
            'vm-c | None | 0 | n/a | High'
            'vm-b | Backup | 15 | At risk | High'
            'vm-d | Site Recovery | 40 | At risk | High'
            'share-docs | Backup | 45 | At risk | High'
            'vm-a | Backup and Site Recovery | 100 | On track | Info'
        )
        $script:r.Workloads[0].PSObject.TypeNames | Should -Contain 'AAC.FailoverReadiness'
        @($script:r.Workloads.Resource) | Should -Not -Contain 'vm-z' -Because 'its VM is out of scope'
        $script:r.Stats.Confidence | Should -Be 40
    }

    It 'says why: failed or stale backups, untested restores, replication health, RPO and test failovers' {
        ($script:r.Workloads | Where-Object Resource -EQ 'vm-b').Finding | Should -Be 'The last backup failed; No successful restore in 180 days - the backup is untested; Backed up but not replicated: it can''t fail over to another region' -Because 'a failed restore is no restore'
        ($script:r.Workloads | Where-Object Resource -EQ 'share-docs').Finding | Should -BeLike 'The last backup is 30 hours old (target 24)*'
        ($script:r.Workloads | Where-Object Resource -EQ 'vm-d').Finding | Should -Be 'Replication has warnings; The RPO is 40 minutes (target 15); Never test-failed over'
        $a = $script:r.Workloads | Where-Object Resource -EQ 'vm-a'
        "$($a.Finding) | $($a.BackupAgeHours) | $($a.RpoMinutes)" | Should -Be 'Ready: backed up, replicated and tested | 3 | 2'
        (& $script:ready @{ RpoMinutes = 60 }).Workloads | Where-Object Resource -EQ 'vm-d' | ForEach-Object { $_.Rpo } | Should -Be 'On track'
    }

    It 'checks the vaults, and the recovery plans'' runbooks - missing and unpublished ones would stop a failover' {
        @($script:r.Findings | ForEach-Object { "$($_.Severity) | $($_.Finding)" }) | Should -Be @(
            "High | plan-erp: the runbook rb-draft (action 'Fix DNS') isn't published (Edit)"
            "High | plan-erp: the runbook rb-gone (action 'Notify') can't be found: ResourceNotFound: The Resource was not found."
            'High | vault-lrs: soft delete is off - deleted backups are gone at once'
            'Medium | plan-erp: never test-failed over'
            'Medium | vault-lrs: backups are locally redundant - lost with the region'
            'Low | vault-lrs: no immutability - backups can be shortened or deleted early'
        )
    }
}

Describe 'Azure Admin Console - Get-AACFailoverReadiness' {
    BeforeEach {
        $script:armUris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Sub; name = 'sub-prod'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            @{ Rows = @{ vms = $script:f.Vm; vaults = $script:f.Vault; items = $script:f.Items; restores = $script:f.Restores }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) {
                $script:armUris.Add($u)
                $answers[$u] = switch -Wildcard ($u) {
                    '*vault-geo/replicationProtectedItems*' { @{ Status = 200; Error = ''; Items = @($script:f.Replicas | ForEach-Object { $c = @{} + $_; $c.Remove('vault'); $c }) }; break }
                    '*vault-geo/replicationRecoveryPlans*' { @{ Status = 200; Error = ''; Items = @($script:f.Plans | ForEach-Object { $c = @{} + $_; $c.Remove('vault'); $c }) }; break }
                    '*vault-lrs/*' { @{ Status = 200; Error = ''; Items = @() }; break }
                    '*runbooks/rb-ok*' { @{ Status = 200; Error = ''; Body = @{ properties = @{ state = 'Published' } } }; break }
                    '*runbooks/rb-draft*' { @{ Status = 200; Error = ''; Body = @{ properties = @{ state = 'Edit' } } }; break }
                    default { @{ Status = 404; Error = 'ResourceNotFound: The Resource was not found.' } }
                }
            }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads each vault''s Site Recovery, then the runbooks its plans run' {
        $workloads = @(Get-AACFailoverReadiness -NoDisplay)
        @($script:armUris | Where-Object { $_ -like '*replicationProtectedItems*' }).Count | Should -Be 2
        @($script:armUris | Where-Object { $_ -like '*/runbooks/*' }).Count | Should -Be 3
        ($workloads | Where-Object Resource -EQ 'vm-d').Protection | Should -Be 'Site Recovery'
    }

    It 'shows the readiness at the prompt' {
        $text = (& $script:capture { Get-AACFailoverReadiness -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Failover readiness', 'Recovery confidence', 'recovery confidence (of 100)', 'Workloads (5)', 'Vaults and recovery plans (6)', 'Workloads by protection', 'rb-gone') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}
