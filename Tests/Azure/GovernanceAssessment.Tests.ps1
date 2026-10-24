<#
    Unit tests for Show-AACManagementGroupMap, Export-AACDiagram -View
    Governance and Invoke-AACGovernanceAssessment (with its Markdown page):
    a made-up management group hierarchy, and the assessment with each
    area's command faked - one of them failing.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $prod = '11111111-1111-1111-1111-111111111111'; $dev = '22222222-2222-2222-2222-222222222222'
    $script:prod = $prod
    $mg = { param([string] $Name) "/providers/microsoft.management/managementgroups/$Name" }
    $script:subs = @(
        @{ subscriptionId = $prod; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'corp'; displayName = 'Corp' }, @{ name = 'landingzones'; displayName = 'Landing zones' }, @{ name = 't-1'; displayName = 'Tenant Root Group' }) }
        @{ subscriptionId = $dev; name = 'sub-dev'; state = 'Enabled'; chain = @(@{ name = 'sandbox'; displayName = 'Sandbox' }, @{ name = 't-1'; displayName = 'Tenant Root Group' }) }
    )
    $script:mapRows = @{
        groups    = @(@{ name = 't-1'; displayName = 'Tenant Root Group'; parent = '' }, @{ name = 'landingzones'; displayName = 'Landing zones'; parent = 't-1' }, @{ name = 'corp'; displayName = 'Corp'; parent = 'landingzones' }, @{ name = 'sandbox'; displayName = 'Sandbox'; parent = 't-1' }, @{ name = 'empty'; displayName = 'Empty'; parent = 't-1' })
        policies  = @(@{ scope = (& $mg 'landingzones'); used = 12 }, @{ scope = (& $mg 't-1'); used = 3 }, @{ scope = "/subscriptions/$prod"; used = 2 })
        roles     = @(@{ scope = (& $mg 't-1'); used = 4 }, @{ scope = '/'; used = 1 }, @{ scope = "/subscriptions/$prod"; used = 9 })
        resources = @(@{ subscriptionId = $prod; used = 140 })
    }
    $script:graph = {
        param($Query)
        if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = $script:subs }; Errors = @{} } }
        @{ Rows = $script:mapRows; Errors = @{} }
    }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        # The default enrichers detect CI (GitHub Actions) and turn colours back on, whatever Ansi says.
        $settings = [Spectre.Console.AnsiConsoleSettings]::new(); $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer); $settings.Ansi = [Spectre.Console.AnsiSupport]::No; $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings); $console.Profile.Width = 200; $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) } finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $typed = { param([string] $Type, [hashtable] $Properties) $o = [pscustomobject]([ordered]@{} + $Properties); $o.PSObject.TypeNames.Insert(0, $Type); $o }
    $script:typed = $typed
}

Describe 'Azure Admin Console - the management group map' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { & $script:graph $Query }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -MockWith { }
    }

    It 'builds the hierarchy with what sits at each level, empty groups too when unscoped' {
        $rows = @(Show-AACManagementGroupMap -NoBrowser -PassThru -HtmlPath (Join-Path $TestDrive 'mg.html') 6>$null | Select-Object -Skip 0)
        @($rows | ForEach-Object { "$($_.ManagementGroup) | $($_.Parent) | $($_.Depth) | $($_.SubscriptionsBelow) | $($_.PolicyAssignments) | $($_.RoleAssignments)" }) | Should -Be @(
            'Tenant Root Group |  | 0 | 2 | 3 | 5'
            'Empty | Tenant Root Group | 1 | 0 | 0 | 0'
            'Landing zones | Tenant Root Group | 1 | 1 | 12 | 0'
            'Sandbox | Tenant Root Group | 1 | 1 | 0 | 0'
            'Corp | Landing zones | 2 | 1 | 0 | 0'
        )
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.ManagementGroup'
        $page = Get-Content -LiteralPath (Join-Path $TestDrive 'mg.html') -Raw
        $page | Should -Match '"layout":"packed"'
        $page | Should -Match '2 policy assignment\(s\)'
    }

    It 'shows only the groups above the subscriptions in scope' {
        @(Show-AACManagementGroupMap -SubscriptionId $script:prod -NoBrowser -PassThru -HtmlPath (Join-Path $TestDrive 'mg2.html') 6>$null).ManagementGroup | Should -Be @('Tenant Root Group', 'Landing zones', 'Corp')
    }

    It 'draws the hierarchy as an editable diagram with -View Governance' {
        $path = Join-Path $TestDrive 'hierarchy.drawio'
        $d = Export-AACDiagram -View Governance -Path $path -SplitBy ManagementGroup -PassThru 6>$null
        $d.Shapes | Should -BeGreaterThan 5
        ([xml](Get-Content -LiteralPath $path -Raw)).mxfile.diagram.name | Should -Contain 'Landing zones (Tenant Root Group)'
        { Export-AACDiagram -View Governance -ResourceGroupName 'rg' -Path (Join-Path $TestDrive 'x.drawio') } | Should -Throw "*-ResourceGroupName doesn't apply to -View Governance*"
    }
}

Describe 'Azure Admin Console - Invoke-AACGovernanceAssessment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { & $script:graph $Query }
        $t = $script:typed
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACRoleAssignment -MockWith {
            & $t 'AAC.RoleAssignment' @{ Severity = 'High'; Principal = 'Carol'; PrincipalType = 'Guest'; Role = 'Contributor'; ScopeType = 'Subscription'; Scope = 'sub-prod'; Assignment = 'Permanent'; Findings = 'A guest holds Contributor.'; Id = 'ra1' }
            & $t 'AAC.RoleAssignment' @{ Severity = 'Info'; Principal = 'Admins'; PrincipalType = 'Group'; Role = 'Owner'; ScopeType = 'Root'; Scope = 'Root (/)'; Assignment = 'Permanent'; Findings = ''; Id = 'ra2' }
            & $t 'AAC.CustomRole' @{ Role = 'Super'; Assignments = 1; Unused = $false; OwnerEquivalent = $true; CanWriteRoleAssignments = $true; Id = 'c1' }
        }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACServicePrincipalInsight -MockWith { throw 'Graph refused: Forbidden' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACPolicyRemediation -MockWith { & $t 'AAC.PolicyRemediation' @{ Severity = 'Medium'; Assignment = 'diag'; Policy = 'Deploy diagnostics'; NonCompliant = 12; LastTask = 'Never'; Findings = 'Never remediated.' } }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Test-AACAzureLimit -MockWith { & $t 'AAC.AzureLimit' @{ Status = 'Critical'; Limit = 'Role assignments'; ScopeType = 'Subscription'; Scope = 'sub-prod'; Used = 3900; Maximum = 4000; Percent = 97.5; Advice = 'Use groups.' } }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACGovernanceSetting -MockWith { & $t 'AAC.GovernanceSetting' @{ Status = 'Warning'; Area = 'Management groups'; Scope = 'Tenant root group'; Setting = 'Who can create management groups'; Value = 'Any user in the tenant'; Recommendation = 'Require authorization.' } }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACTagUsage -MockWith { & $t 'AAC.TagUsage' @{ Severity = 'Low'; Tag = 'env'; Resources = 4; Coverage = 40; Findings = 'Near-duplicate.' } }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACResourceLock -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACGovernanceChange -MockWith { & $t 'AAC.GovernanceChange' @{ Severity = 'Medium'; When = [datetime]'2026-10-17'; Change = 'Created'; Kind = 'Role assignment'; Name = 'ra1'; By = 'alice@contoso.example'; Note = 'Privileged access granted: Contributor.' } }.GetNewClosure()
    }

    It 'brings the areas together, notes the one that failed, and keeps the findings that matter' {
        $a = Invoke-AACGovernanceAssessment -NoDisplay 6>$null 3>$null
        $a.PSObject.TypeNames | Should -Contain 'AAC.GovernanceAssessment'
        @($a.Findings | ForEach-Object { "$($_.Severity) | $($_.Area) | $($_.Item)" }) | Should -Be @(
            'High | Access | Contributor for Carol on sub-prod'
            'High | Access | Custom role Super'
            'High | Limits | Role assignments on sub-prod'
            'Medium | Changes | Role assignment ra1 (Created by alice@contoso.example)'
            'Medium | Policy | Deploy diagnostics (diag)'
            'Medium | Settings | Who can create management groups (Tenant root group)'
        )
        "$(@($a.Hierarchy).Count) $(@($a.RoleAssignments).Count) $(@($a.CustomRoles).Count) $(@($a.ServicePrincipals).Count)" | Should -Be '5 2 1 0'
        $a.Notices | Should -Contain "The identities area couldn't be assessed: Graph refused: Forbidden"
    }

    It 'runs only the areas asked for' {
        $a = Invoke-AACGovernanceAssessment -Area Limits, Settings -NoDisplay 6>$null
        @($a.Findings).Count | Should -Be 2
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACRoleAssignment -Times 0
    }

    It 'writes the workbook with a tab per area, and a Markdown page with the hierarchy' {
        $html = Join-Path $TestDrive 'gov.html'; $md = Join-Path $TestDrive 'wiki/gov.md'
        $null = & $script:capture { Invoke-AACGovernanceAssessment -HtmlPath $html -MarkdownPath $md -MarkdownFlavor AzureDevOps 3>$null }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tabs.name) | Should -Be @('Findings', 'Hierarchy', 'Access', 'Identities', 'Policy', 'Limits', 'Settings', 'Tags', 'Locks', 'Changes')
        @($model.tables.id) | Should -Contain 'customRoles'
        $page = Get-Content -LiteralPath $md -Raw
        foreach ($expected in '# Azure governance assessment', '::: mermaid', 'mg1["Tenant Root Group<br/>2 sub(s) - 3 polic(ies) - 5 role(s)"]', 'mg1 --> mg3', '## Findings (6)', '| High | Access | Contributor for Carol on sub-prod |', '## Limits (1)') { $page | Should -Match ([regex]::Escape($expected)) }
    }

    It 'shows the totals and the findings at the prompt' {
        $text = (& $script:capture { Invoke-AACGovernanceAssessment -NoPaging 3>$null }).Text
        foreach ($expected in 'Azure Admin Console :: Governance assessment', '6 finding(s) across', 'Findings (6)') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}
