<#
    Unit tests for Get-AACPolicyRemediation: made-up DeployIfNotExists and
    Modify policies with non-compliant resources, their assignments and
    remediation tasks - never run, failed, drifted, running, no identity -
    and the command with Resource Graph and Resource Manager faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $sub = '11111111-1111-1111-1111-111111111111'
    $mg = '/providers/microsoft.management/managementgroups/mg-platform'
    $now = [datetime]::UtcNow
    $assign = { param([string] $Name, [string] $Identity = 'SystemAssigned', [string] $Enforcement = 'Default') @{ id = "$mg/providers/microsoft.authorization/policyassignments/$Name"; displayName = $Name; scope = $mg; definitionId = "/providers/microsoft.authorization/policysetdefinitions/$Name"; identityType = $Identity; enforcement = $Enforcement } }
    $fix = { param([string] $Assignment, [string] $Reference, [string] $Policy, [int] $Count, [string] $Effect = 'deployifnotexists') @{ assignmentId = "$mg/providers/microsoft.authorization/policyassignments/$Assignment"; referenceId = $Reference; definitionId = "/providers/microsoft.authorization/policydefinitions/$Policy"; nonCompliant = $Count; subscriptions = 1; effect = $Effect } }
    $task = { param([string] $Assignment, [string] $Reference, [string] $State, [int] $Days, [int] $Ok, [int] $Failed) @{ name = "t-$Assignment-$Reference-$Days"; properties = @{ policyAssignmentId = "$mg/providers/Microsoft.Authorization/policyAssignments/$Assignment"; policyDefinitionReferenceId = $Reference; provisioningState = $State; createdOn = $now.AddDays(-$Days).ToString('o'); deploymentStatus = @{ totalDeployments = $Ok + $Failed; successfulDeployments = $Ok; failedDeployments = $Failed } } } }
    $script:sub = $sub
    $script:read = @{
        Errors = @{}
        Rows   = @{
            fixable     = @(
                (& $fix 'diag' 'logs-kv' 'deploy-diag-kv' 12)
                (& $fix 'diag' 'logs-sql' 'deploy-diag-sql' 3)
                (& $fix 'tags' 'inherit-env' 'inherit-tag' 40 'modify')
                (& $fix 'backup' 'vm-backup' 'deploy-backup' 7)
                (& $fix 'noid' 'deploy-x' 'deploy-x' 2)
                (& $fix 'audit' 'deploy-y' 'deploy-y' 5)
            )
            assignments = @((& $assign 'diag'), (& $assign 'tags' 'UserAssigned'), (& $assign 'backup'), (& $assign 'noid' 'None'), (& $assign 'audit' 'SystemAssigned' 'DoNotEnforce'))
        }
    }
    $script:tasks = @(
        (& $task 'diag' 'logs-kv' 'Succeeded' 10 5 0)
        (& $task 'diag' 'logs-kv' 'Failed' 2 1 4)
        (& $task 'tags' 'inherit-env' 'Succeeded' 5 40 0)
        (& $task 'backup' 'vm-backup' 'Running' 0 0 0)
    )
    $script:definitions = @{ '/providers/microsoft.authorization/policydefinitions/deploy-diag-kv' = @{ id = '/providers/microsoft.authorization/policydefinitions/deploy-diag-kv'; displayName = 'Deploy Key Vault diagnostics' } }
}

Describe 'Azure Admin Console - policy remediation' {
    BeforeAll { $script:r = InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:read; T = $script:tasks; D = $script:definitions } { param($R, $T, $D) ConvertTo-AACPolicyRemediation -Read $R -Task $T -Definition $D } }

    It 'puts failed and impossible remediation first, then what was never remediated' {
        @($script:r.Remediations | ForEach-Object { "$($_.Severity) | $($_.Assignment) | $($_.Policy) | $($_.NonCompliant) | $($_.LastTask)" }) | Should -Be @(
            'High | diag | Deploy Key Vault diagnostics | 12 | Failed'
            'High | noid | deploy-x | 2 | Never'
            'Medium | audit | deploy-y | 5 | Never'
            'Medium | diag | deploy-diag-sql | 3 | Never'
            'Low | tags | inherit-tag | 40 | Succeeded'
            'Info | backup | deploy-backup | 7 | Running'
        )
        $script:r.Remediations[0].PSObject.TypeNames | Should -Contain 'AAC.PolicyRemediation'
    }

    It 'says what happened and what to do' {
        $kv = $script:r.Remediations[0]
        "$($kv.Deployments) | $($kv.Failed) | $($kv.Effect)" | Should -Be '1 of 5 succeeded | 4 | DeployIfNotExists'
        $kv.Findings | Should -BeLike 'The latest remediation task failed*'
        ($script:r.Remediations | Where-Object Assignment -EQ 'noid').Findings | Should -BeLike 'The assignment has no managed identity*'
        ($script:r.Remediations | Where-Object Assignment -EQ 'tags').Findings | Should -BeLike 'Remediated on *, yet 40 resource(s) are non-compliant again*'
        ($script:r.Remediations | Where-Object Assignment -EQ 'audit').Findings | Should -BeLike '*Enforcement is off (DoNotEnforce)*'
        "$($script:r.Stats.Policies) $($script:r.Stats.Fixable) $($script:r.Stats.Never) $($script:r.Stats.Failed)" | Should -Be '6 69 3 1'
    }
}

Describe 'Azure Admin Console - Get-AACPolicyRemediation' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-platform' }) }) }; Errors = @{} } }
            if ($Query.Contains('fixable')) { return $script:read }
            @{ Rows = @{ definitions0 = @($script:definitions.Values) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) { $answers[$u] = @{ Status = 200; Error = $null; Body = $null; Items = $(if ($u -match 'managementGroups/mg-platform') { $script:tasks } else { @() }) } }
            $answers
        }
    }

    It 'reads the tasks of the subscriptions and the management groups above them, and filters by severity' {
        @(Get-AACPolicyRemediation -NoDisplay).Count | Should -Be 6
        @(Get-AACPolicyRemediation -Severity High -NoDisplay).Assignment | Should -Be @('diag', 'noid')
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -match 'managementGroups/mg-platform/providers/Microsoft.PolicyInsights' }).Count -eq 1 -and @($Uri | Where-Object { $_ -match '^/subscriptions/' }).Count -eq 1 }
    }

    It 'shows the policies at the prompt, and writes CSV' {
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        # The default enrichers detect CI (GitHub Actions) and turn colours back on, whatever Ansi says.
        $settings = [Spectre.Console.AnsiConsoleSettings]::new(); $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer); $settings.Ansi = [Spectre.Console.AnsiSupport]::No; $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings); $console.Profile.Width = 220; $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; Get-AACPolicyRemediation -NoPaging } finally { [Spectre.Console.AnsiConsole]::Console = $real }
        $text = $buffer.ToString()
        foreach ($expected in 'Azure Admin Console :: Policy remediation', '6 polic(ies) could fix 69 non-compliant resource(s): 3 never remediated, 1 with failed remediation') { $text | Should -Match ([regex]::Escape($expected)) }
        $csv = Join-Path $TestDrive 'remediation.csv'
        try { [Spectre.Console.AnsiConsole]::Console = $console; Get-AACPolicyRemediation -CsvPath $csv } finally { [Spectre.Console.AnsiConsole]::Console = $real }
        @(Import-Csv -LiteralPath $csv)[0].Assignment | Should -Be 'diag'
    }
}
