<#
    Unit tests for Get-AACComplianceGap: made-up Contoso regulatory
    compliance - Defender for Cloud's PCI-DSS and MCSB controls in two
    subscriptions, Azure Policy's ISO 27001 and CIS initiatives - the gaps,
    their priority, effort and phase, frameworks not assessed, unscanned
    resources and progress against a baseline; and the command with
    Resource Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $s1 = '11111111-1111-1111-1111-111111111111'; $s2 = '22222222-2222-2222-2222-222222222222'
    $control = { param([string] $Sub, [string] $Standard, [string] $Id, [string] $State, [string] $Description = '') @{ id = "$Sub-$Standard-$Id"; subscriptionId = $Sub; standard = $Standard; control = $Id; description = $Description; state = $State } }
    $script:data = @{
        Names         = @{ $s1 = 'sub-prod'; $s2 = 'sub-dev' }
        Controls      = @(
            (& $control $s1 'PCI-DSS-4' '1.1' 'Failed' 'Network security controls'), (& $control $s2 'PCI-DSS-4' '1.1' 'Passed' 'Network security controls')
            (& $control $s1 'PCI-DSS-4' '1.2' 'Passed'), (& $control $s2 'PCI-DSS-4' '1.2' 'Passed')
            (& $control $s1 'PCI-DSS-4' '12.1' 'Skipped' 'Information security policy')
            (& $control $s1 'Microsoft-cloud-security-benchmark' 'NS-1' 'Failed' 'Establish network segmentation'), (& $control $s1 'Microsoft-cloud-security-benchmark' 'DP-3' 'Passed')
        )
        Assessments   = @(
            @{ id = 'as1'; subscriptionId = $s1; standard = 'PCI-DSS-4'; control = '1.1'; assessment = 'Management ports should be closed'; failedResources = 8; link = 'https://portal.azure.com/#a1' }
            @{ id = 'as2'; subscriptionId = $s1; standard = 'PCI-DSS-4'; control = '1.1'; assessment = 'Subnets should have an NSG'; failedResources = 5; link = 'https://portal.azure.com/#a2' }
            @{ id = 'as3'; subscriptionId = $s1; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS-1'; assessment = 'Subnets should have an NSG'; failedResources = 3; link = '' }
        )
        PolicyControl = @(
            @{ id = 'p1'; initiative = 'ISO 27001:2013'; groupName = 'ISO27001-2013_A.12.4.1'; nonCompliant = 4; compliant = 6; policies = 2; effects = @('auditifnotexists') }
            @{ id = 'p2'; initiative = 'ISO 27001:2013'; groupName = 'ISO27001-2013_A.9.2.3'; nonCompliant = 0; compliant = 10; policies = 1; effects = @('audit') }
            @{ id = 'p3'; initiative = 'ISO 27001:2013'; groupName = 'ISO27001-2013_A.10.1.1'; nonCompliant = 20; compliant = 1; policies = 1; effects = @('deployifnotexists') }
            @{ id = 'p4'; initiative = 'CIS Microsoft Azure Foundations Benchmark v2.0.0'; groupName = 'CISv2.0.0_1.1'; nonCompliant = 0; compliant = 0; policies = 1; effects = @('manual') }
        )
        Unscanned     = @(@{ type = 'microsoft.compute/virtualmachines/extensions'; resources = 40 }, @{ type = 'microsoft.network/networkwatchers'; resources = 3 })
    }
    $script:gap = {
        param([hashtable] $More = @{})
        $d = $script:data
        InModuleScope 'Azure.Admin.Console' -Parameters @{ D = $d; M = $More } { param($D, $M) ConvertTo-AACComplianceGap -Control $D.Controls -Assessment $D.Assessments -PolicyControl $D.PolicyControl -Unscanned $D.Unscanned -SubscriptionName $D.Names @M }
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

Describe 'Azure Admin Console - compliance gaps' {
    BeforeAll { $script:r = & $script:gap }

    It 'sums up each framework from Defender and Policy - a control fails when any subscription fails it' {
        @($script:r.Frameworks | ForEach-Object { "$($_.Framework) | $($_.Source) | $($_.Passed)/$($_.Failed)/$($_.Manual) | $($_.Compliance)" }) | Should -Be @(
            'CIS | Azure Policy | 0/0/1 | '
            'ISO 27001 | Azure Policy | 1/2/0 | 33.3'
            'Microsoft cloud security benchmark | Defender for Cloud | 1/1/0 | 50'
            'PCI-DSS | Defender for Cloud | 1/1/1 | 50'
        )
    }

    It 'lists the gaps by priority and effort, quick wins first, with what to do' {
        @($script:r.Gaps | ForEach-Object { "$($_.Severity) | $($_.Phase) | $($_.Framework) | $($_.ControlId) | $($_.FailingResources) | $($_.Effort)" }) | Should -Be @(
            'High | Quick win | ISO 27001 | ISO27001-2013_A.10.1.1 | 20 | Low'
            'High | Plan | PCI-DSS | 1.1 | 13 | Medium'
            'Medium | Backlog | ISO 27001 | ISO27001-2013_A.12.4.1 | 4 | Medium'
            'Medium | Backlog | Microsoft cloud security benchmark | NS-1 | 3 | Medium'
            'Low | Backlog | PCI-DSS | 12.1 | 0 | Low'
        )
        $pci = $script:r.Gaps | Where-Object ControlId -EQ '1.1'
        $pci.Detail | Should -Be 'Management ports should be closed; Subnets should have an NSG'
        $pci.FailingSubscriptions | Should -Be 'sub-prod'
        $pci.Link | Should -Be 'https://portal.azure.com/#a1'
        ($script:r.Gaps | Where-Object ControlId -EQ 'ISO27001-2013_A.10.1.1').Remediation | Should -BeLike 'Create remediation tasks*'
        ($script:r.Gaps | Where-Object ControlId -EQ '12.1').State | Should -Be 'Manual'
        $script:r.Gaps[0].PSObject.TypeNames | Should -Contain 'AAC.ComplianceGap'
        $script:r.Stats.UnscannedTotal | Should -Be 43
    }

    It 'keeps to the frameworks asked for, and flags the ones nothing assesses' {
        $r = & $script:gap @{ Framework = @('PCI-DSS', 'HIPAA', 'GDPR') }
        @($r.Frameworks.Framework | Select-Object -Unique) | Should -Be @('PCI-DSS')
        @($r.Gaps | Where-Object State -EQ 'Not assessed' | ForEach-Object { "$($_.Severity) $($_.Framework)" }) | Should -Be @('High GDPR', 'High HIPAA')
        ($r.Gaps | Where-Object Framework -EQ 'GDPR').Remediation | Should -BeLike 'Azure has no built-in GDPR initiative*'
        $r.Stats.NotAssessed | Should -Be 2
    }

    It 'marks each gap new, still open or closed against a baseline' {
        $baseline = @(
            [pscustomobject]@{ Source = 'Defender for Cloud'; Standard = 'PCI DSS 4'; ControlId = '1.1'; Control = '1.1 Network security controls'; Framework = 'PCI-DSS'; Status = '' }
            [pscustomobject]@{ Source = 'Defender for Cloud'; Standard = 'Microsoft cloud security benchmark'; ControlId = 'DP-3'; Control = 'DP-3'; Framework = 'Microsoft cloud security benchmark'; Status = '' }
        )
        $r = & $script:gap @{ Baseline = $baseline }
        ($r.Gaps | Where-Object ControlId -EQ '1.1').Progress | Should -Be 'Open'
        ($r.Gaps | Where-Object ControlId -EQ 'NS-1').Progress | Should -Be 'New'
        $closed = $r.Gaps | Where-Object Progress -EQ 'Closed'
        "$($closed.ControlId) $($closed.Severity) $($closed.Phase)" | Should -Be 'DP-3 Info Done'
        "$($r.Stats.New) $($r.Stats.Closed) $($r.Stats.Gaps)" | Should -Be '4 1 5'
    }
}

Describe 'Azure Admin Console - Get-AACComplianceGap' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled'; chain = @() }, @{ subscriptionId = '22222222-2222-2222-2222-222222222222'; name = 'sub-dev'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            $script:keys = @($Query.Keys)
            @{ Rows = @{ controls = $script:data.Controls; assessments = $script:data.Assessments; policy = $script:data.PolicyControl; unscanned = $script:data.Unscanned }; Errors = @{} }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'writes the gaps as a baseline, and reads them back as one' {
        $csv = Join-Path $TestDrive 'gaps.csv'
        $null = & $script:capture { Get-AACComplianceGap -CsvPath $csv }
        $script:keys | Should -Contain 'unscanned'
        $again = @(Get-AACComplianceGap -BaselinePath $csv -SkipUnscanned -NoDisplay)
        @($again.Progress | Select-Object -Unique) | Should -Be @('Open')
        $script:keys | Should -Not -Contain 'unscanned'
        { Get-AACComplianceGap -BaselinePath (Join-Path $TestDrive 'nope.csv') -NoDisplay } | Should -Throw '*doesn''t exist*'
    }

    It 'shows the frameworks and the roadmap at the prompt' {
        $text = (& $script:capture { Get-AACComplianceGap -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Compliance gaps', 'x 5 gap(s) across 4 framework(s): 2 high - 1 quick win(s)', 'Frameworks (4)', 'Gaps and roadmap (5)', 'Quick win', 'Resource types no policy evaluates (2)', 'Compliance by framework (%)') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}
