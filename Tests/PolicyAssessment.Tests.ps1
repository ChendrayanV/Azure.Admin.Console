<#
    Unit tests for Invoke-AACPolicyAssessment: its Resource Graph queries, the
    assessment of a made-up Contoso tenant's Azure Policy
    (Fixtures\ContosoPolicyAssessment.ps1) - compliance counted at each resource's worst
    state, the findings, exemptions, definitions, audiences and scopes - and
    the command with Azure mocked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoPolicyAssessment.ps1')
    $script:f = Get-AACContosoPolicyAssessment
    $script:assess = {
        param([hashtable] $With = @{})
        $r = $script:f.Rows
        $p = @{
            Subscription = $r.subscriptions; ManagementGroup = $r.managementGroups; Assignment = $r.assignments; Exemption = $r.exemptions; Definition = $script:f.Definitions
            RoleAssignment = $r.roles0; RoleDefinition = $r.roleDefinitions; ComplianceBySubscription = $r.complianceBySubscription; ComplianceByAssignment = $r.complianceByAssignment; ComplianceByPolicy = $r.complianceByPolicy; Now = $script:f.Now
        }
        foreach ($k in $With.Keys) { $p[$k] = $With[$k] }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $p } { param($P) ConvertTo-AACPolicyAssessment @P }
    }
    $script:a = & $script:assess
    $script:assignment = { param([string] $Name, $From = $script:a) $From.Assignments | Where-Object Name -EQ $Name | Select-Object -First 1 }
    $script:findingsOf = { param([string] $Item, $From = $script:a) @($From.Findings | Where-Object Item -EQ $Item | ForEach-Object Finding) }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 180
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Azure Policy assessment queries' {
    It 'reads the hierarchy, assignments, exemptions and custom definitions tenant-wide, and every query keeps an id column' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACPolicyAssessmentQuery -Stage Discovery }
        @($q.Keys) | Should -Be @('subscriptions', 'managementGroups', 'assignments', 'exemptions', 'customDefinitions', 'customInitiatives', 'roleDefinitions')
        foreach ($key in $q.Keys) {
            $q[$key].Tenant | Should -BeTrue -Because "$key is read tenant-wide"
            $q[$key].Query | Should -Match '\bid\b' -Because 'Resource Graph pages only results with an id column'
        }
        $q.assignments.Query | Should -Match 'nonComplianceMessages'
        $q.exemptions.Query | Should -Match 'expiresOn'
    }

    It 'counts each resource once at its worst state, with an id per row' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACPolicyAssessmentQuery -Stage Compliance }
        @($q.Keys) | Should -Be @('complianceBySubscription', 'complianceByAssignment', 'complianceByPolicy')
        foreach ($key in $q.Keys) {
            $q[$key] | Should -Match "complianceState == 'NonCompliant', 300, complianceState == 'Compliant', 200, complianceState == 'Conflict', 100, complianceState == 'Exempt', 50"
            $q[$key] | Should -Match 'summarize worst = max\(stateWeight\)'
            $q[$key] | Should -Match '\| extend id = '
        }
    }

    It 'reads definitions and role assignments by ID, 100 to a query, quoted' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACPolicyAssessmentQuery -Stage Definitions -Id @(1..150 | ForEach-Object { "/providers/Microsoft.Authorization/policyDefinitions/D$_" }) }
        @($q.Keys) | Should -Be @('definitions0', 'definitions100')
        $q.definitions0.Query | Should -Match "'/providers/microsoft.authorization/policydefinitions/d1'"
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACPolicyAssessmentQuery -Stage Roles -Id "it's", 'B' }
        @($q.Keys) | Should -Be @('roles0')
        $q.roles0.Query | Should -Match "principalId in \('b', 'it\\'s'\)"
    }
}

Describe 'Azure Admin Console - Azure Policy assessment' {
    It 'counts compliance as (compliant + exempt) / all - overall, by subscription and by management group' {
        "$($script:a.Stats.CompliancePercent) $($script:a.Stats.NonCompliant) $($script:a.Stats.Resources)" | Should -Be '85.4 35 240'
        $app1 = $script:a.Subscriptions | Where-Object Subscription -EQ 'sub-app1'
        "$($app1.CompliancePercent) $($app1.Rating) $($app1.ManagementGroups)" | Should -Be '70 Warning Tenant Root Group > Landing zones > Corp'
        $script:a.Subscriptions[0].Subscription | Should -Be 'sub-app1' -Because 'the least compliant come first'
        ($script:a.ManagementGroups | Where-Object Name -EQ 'mg-corp').CompliancePercent | Should -Be 82.5
    }

    It 'rates each assignment against the threshold: Poor under half of it' {
        $diag = & $script:assignment 'a-diag'
        "$($diag.CompliancePercent) $($diag.Rating) $($diag.Kind) $($diag.Effect)" | Should -Be '0 Poor Policy DeployIfNotExists'
        "$((& $script:assignment 'a-tags').Rating) $((& $script:assignment 'a-mcsb').Rating)" | Should -Be 'Warning Good'
        (& $script:assignment 'a-mcsb').Subscriptions | Should -Be 3
        (& $script:assignment 'a-mcsb').Policies | Should -Be 2
        $strict = & $script:assess @{ ComplianceWarningPercent = 96 }
        (& $script:assignment 'a-mcsb' $strict).Rating | Should -Be 'Warning'
    }

    It 'rolls compliance up by policy (the definition''s name) and by category' {
        $https = $script:a.Policies | Where-Object ReferenceId -EQ 'storageHttps'
        "$($https.Policy) | $($https.Category) | $($https.Groups) | $($https.CompliancePercent)" | Should -Be 'Secure transfer to storage accounts should be enabled | Storage | NS-1 | 89.1'
        @($script:a.Categories | ForEach-Object Category) | Should -Be @('Tags', 'Monitoring', 'Storage', 'General', 'Key Vault')
        ($script:a.Categories | Where-Object Category -EQ 'Tags').Rating | Should -Be 'Warning'
    }

    It 'opens up each assigned initiative: its member policies, their effect, parameters and compliance' {
        $members = @($script:a.InitiativePolicies | Where-Object { $_.AssignmentId -like '*/a-mcsb' })
        $members.Count | Should -Be 2
        $members[0].PSObject.TypeNames[0] | Should -Be 'AAC.PolicyInitiativeMember'
        $https = $members | Where-Object ReferenceId -EQ 'storageHttps'
        "$($https.Policy) | $($https.Initiative) | $($https.Effect) | $($https.EffectSource) | $($https.Groups)" | Should -Be 'Secure transfer to storage accounts should be enabled | Microsoft cloud security benchmark | Audit | Policy default | NS-1'
        "$($https.NonCompliant) $($https.Resources)" | Should -Be '12 110' -Because 'its compliance across the subscriptions in scope'
        @($script:a.InitiativePolicies | Where-Object { $_.AssignmentId -like '*/a-locations' }).Count | Should -Be 0 -Because 'a policy assigned on its own is no initiative'
    }

    It 'flags the assignment findings' {
        & $script:findingsOf 'Allowed locations' | Should -Be @('Deny without a non-compliance message', 'Policy definition assigned directly')
        & $script:findingsOf 'Allowed locations (platform)' | Should -Be @('Policy definition assigned directly') -Because 'it has a message'
        & $script:findingsOf 'Tagging' | Should -Be @('Not enforced (DoNotEnforce)', 'Assignment below the compliance threshold')
        & $script:findingsOf 'Security benchmark' | Should -Be @('Deprecated policy assigned', 'Excluded scope that doesn''t exist')
        & $script:findingsOf 'Diagnostics (app1) / Diagnostics' | Should -Be @('Assigned twice on the same scope path')
        @($script:a.Findings | Where-Object Finding -EQ 'Assigned twice on the same scope path').Count | Should -Be 1 -Because 'mg-platform and mg-landingzones are not on one path'
    }

    It 'flags remediation with no managed identity, or one missing the roles its policies list' {
        & $script:findingsOf 'Diagnostics (app1)' | Should -Contain 'Remediation without a managed identity'
        & $script:findingsOf 'Diagnostics' | Should -Not -Contain 'Managed identity missing roles'
        $script:a.Roles[0].Required | Should -Be 'Yes'
        $without = & $script:assess @{ RoleAssignment = @() }
        & $script:findingsOf 'Diagnostics' $without | Should -Contain 'Managed identity missing roles'
        (& $script:assignment 'a-diag-mg' $without).RolesMissing | Should -Be 'Log Analytics Contributor'
    }

    It 'reads each exemption''s expiry: expired, expiring, never, and for an assignment that is gone' {
        @($script:a.Exemptions | ForEach-Object { "$($_.Exemption)=$($_.Status)" }) | Should -Be @('ex-expired=Expired', 'ex-expiring=Expiring', 'ex-forever=No expiry', 'ex-orphan=Active')
        (& $script:findingsOf 'ex-expired') | Should -Be @('Exemption expired')
        (& $script:findingsOf 'ex-orphan') | Should -Be @('Exemption for an assignment that doesn''t exist')
        (& $script:findingsOf 'ex-forever') | Should -Be @('Exemption with no expiry')
        $soon = & $script:assess @{ ExemptionWarningDays = 7 }
        ($soon.Exemptions | Where-Object Exemption -EQ 'ex-expiring').Status | Should -Be 'Active'
    }

    It 'lists the definitions assigned and every custom one, with the hygiene findings' {
        @($script:a.Initiatives | ForEach-Object { "$($_.Initiative)=$($_.Assigned)" }) | Should -Be @('Microsoft cloud security benchmark=Yes', 'Contoso Tagging=Yes', 'Contoso Security=No')
        ($script:a.Definitions | Where-Object Definition -EQ 'Deploy diagnostic settings to Log Analytics').RolesNeeded | Should -Be 'Log Analytics Contributor'
        & $script:findingsOf 'Contoso Tagging' | Should -Be @('Unused policy definition groups')
        & $script:findingsOf 'Contoso Security' | Should -Be @('Unassigned custom initiative', 'No category in the metadata')
        & $script:findingsOf 'Old test policy' | Should -Be @('Unassigned custom policy definition', 'No category in the metadata')
        @($script:a.Findings | Where-Object Finding -EQ 'Same control, different group names').Detail | Should -BeLike '*Sec-1, Tagging-1*'
        ($script:a.Definitions | Where-Object Definition -EQ 'Require a cost center tag').HiddenMetadata | Should -Be 'hidden-owner=platform-team'
    }

    It 'leaves the platform team''s items out for an application team' {
        $app = & $script:assess @{ Audience = 'Application' }
        @($app.Initiatives | ForEach-Object Initiative) | Should -Not -Contain 'Contoso Security'
        @($app.Definitions | ForEach-Object Definition) | Should -Not -Contain 'Old test policy'
        @($app.Findings | Where-Object { $_.Finding -match 'Unassigned|category|group' }).Count | Should -Be 0
        (& $script:assignment 'a-tags' $app).HiddenMetadata | Should -Be ''
        ($app.Subscriptions | Where-Object Subscription -EQ 'sub-app1').HiddenTags | Should -Be ''
        @($app.Findings | Where-Object Severity -EQ 'High').Count | Should -Be 2 -Because 'what needs doing is the same'
    }

    It 'scopes to a management group and what is under it' {
        $corp = & $script:assess @{ ManagementGroupId = 'mg-corp' }
        @($corp.Assignments | ForEach-Object Name | Sort-Object) | Should -Be @('a-diag', 'a-tags')
        @($corp.Subscriptions | ForEach-Object Subscription | Sort-Object) | Should -Be @('sub-app1', 'sub-app2')
        @($corp.ManagementGroups | ForEach-Object Name) | Should -Be @('mg-corp')
        @($corp.Exemptions | ForEach-Object Exemption) | Should -Be @('ex-forever') -Because 'only the exemptions of its assignments'
        $corp.Tree.k[0].n | Should -Be 'Corp'
    }

    It 'scopes to subscriptions, with every assignment that reaches them' {
        $app2 = & $script:assess @{ SubscriptionId = @($script:f.App2) }
        @($app2.Assignments | ForEach-Object Name | Sort-Object) | Should -Be @('a-diag-mg', 'a-locations', 'a-mcsb', 'a-tags')
        @($app2.Subscriptions | ForEach-Object Subscription) | Should -Be @('sub-app2')
        (& $script:assignment 'a-mcsb' $app2).Resources | Should -Be 100 -Because 'only sub-app2''s resources count'
        @($app2.AssignmentCompliance | ForEach-Object Subscription | Sort-Object -Unique) | Should -Be @('sub-app2')
    }

    It 'leaves out a subscription an assignment excludes' {
        $excluded = @($script:f.Rows.assignments | ForEach-Object { $c = $_.Clone(); if ($c.name -eq 'a-mcsb') { $c.notScopes = @("/subscriptions/$($script:f.App2)") }; $c })
        (& $script:assignment 'a-mcsb' (& $script:assess @{ Assignment = $excluded })).Subscriptions | Should -Be 2
    }

    It 'builds the hierarchy tree with each level''s compliance' {
        $root = $script:a.Tree.k[0]
        "$($root.n) $($root.p)" | Should -Be 'Tenant Root Group 85'
        @($root.k | ForEach-Object n) | Should -Be @('Landing zones', 'Platform')
        $root.k[0].k[0].k[0].n | Should -Be 'sub-app1'
        $root.k[0].k[0].k[0].f.table | Should -Be 'policy-subscriptions'
    }
}

Describe 'Azure Admin Console - Invoke-AACPolicyAssessment' {
    BeforeEach {
        $script:graphCalls = [System.Collections.Generic.List[object]]::new()
        $script:builtIn = @($script:f.Definitions.Values | Where-Object { $_.policyType -eq 'BuiltIn' -and $_.name -ne 'kv-soft-delete' })
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:graphCalls.Add(@{ Keys = @($Query.Keys); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }) })
            $rows = @{}
            foreach ($key in @($Query.Keys)) {
                $rows[$key] = @(if ($key -like 'definitions*') { $script:builtIn | Where-Object { $Query[$key].Query -match [regex]::Escape("'$($_.id.ToLowerInvariant())'") } } elseif ($script:f.Rows.Contains($key)) { $script:f.Rows[$key] })
            }
            @{ Rows = $rows; Errors = @{} }
        }
        # Resource Graph doesn't have one built-in: Resource Manager does.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $script:armUris = @($Uri)
            $answers = @{}
            foreach ($target in $Uri) {
                $row = $script:f.Definitions[($target -split '\?')[0]]
                $answers[$target] = @{ Status = 200; Body = @{ id = $row.id; name = $row.name; type = $row.type; properties = @{ displayName = $row.displayName; policyType = 'BuiltIn'; metadata = $row.metadata; policyRule = $row.rule; parameters = @{} } }; Items = $null; Error = '' }
            }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 'tenant-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'assesses every assignment and returns them with their compliance, policies and findings' {
        $rows = @((& $script:capture { Invoke-AACPolicyAssessment -NoDisplay }).Output)
        $rows.Count | Should -Be 6
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.PolicyAssignmentReport'
        $mcsb = $rows | Where-Object Name -EQ 'a-mcsb'
        "$(@($mcsb.Compliance).Count) $(@($mcsb.PolicyStates).Count) $(@($mcsb.Findings).Count)" | Should -Be '3 2 2'
        $script:armUris | Should -Be @('/providers/microsoft.authorization/policydefinitions/kv-soft-delete?api-version=2023-04-01') -Because 'what Resource Graph lacks is read from Resource Manager'
        ($mcsb.Findings | ForEach-Object Finding) | Should -Contain 'Deprecated policy assigned'
        @($script:graphCalls | Where-Object { $_.Keys -contains 'roles0' }).Count | Should -Be 1
    }

    It 'reads compliance only in the subscriptions or management group asked for' {
        $null = & $script:capture { Invoke-AACPolicyAssessment -SubscriptionId $script:f.App2 -NoDisplay }
        ($script:graphCalls | Where-Object { $_.Keys -contains 'complianceByPolicy' }).SubscriptionId | Should -Be @($script:f.App2)
        $script:graphCalls.Clear()
        $rows = @((& $script:capture { Invoke-AACPolicyAssessment -ManagementGroupId 'mg-corp' -NoDisplay }).Output)
        ($script:graphCalls | Where-Object { $_.Keys -contains 'complianceByPolicy' }).ManagementGroupId | Should -Be @('mg-corp')
        @($rows | ForEach-Object Name | Sort-Object) | Should -Be @('a-diag', 'a-tags')
    }

    It 'says when the management group or subscriptions can''t be found' {
        { & $script:capture { Invoke-AACPolicyAssessment -ManagementGroupId 'mg-nope' -NoDisplay } } | Should -Throw "*No management group named 'mg-nope'*"
        { & $script:capture { Invoke-AACPolicyAssessment -SubscriptionId '99999999-9999-9999-9999-999999999999' -NoDisplay -WarningAction SilentlyContinue } } | Should -Throw '*None of those subscriptions*'
    }

    It 'shows the view at the prompt' {
        $text = (& $script:capture { Invoke-AACPolicyAssessment -NoPaging }).Text
        $text | Should -Match 'resources compliant'
        $text | Should -Match 'Security benchmark'
        $text | Should -Match 'Exemptions to look at'
        $text | Should -Match 'Remediation without a managed identity'
    }

    It 'writes the CSV files, the HTML report with the tree, and the PDF' {
        $csv = Join-Path $TestDrive 'policy'
        $html = Join-Path $TestDrive 'policy.html'
        $pdf = Join-Path $TestDrive 'policy.pdf'
        $null = & $script:capture { Invoke-AACPolicyAssessment -CsvPath $csv -HtmlPath $html -PdfPath $(if ($script:canWritePdf) { $pdf } else { $null }) }
        foreach ($name in 'assignments', 'assignment-compliance', 'policies', 'categories', 'subscriptions', 'management-groups', 'initiatives', 'definitions', 'exemptions', 'role-assignments', 'findings') { Join-Path $csv "$name.csv" | Should -Exist }
        @(Import-Csv -LiteralPath (Join-Path $csv 'assignments.csv')).Count | Should -Be 6
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables | ForEach-Object id) | Should -Contain 'policy-assignments'
        @($model.tables | ForEach-Object section | Select-Object -Unique) | Should -Be @('Overview', 'Compliance', 'Exemptions', 'Definitions')
        $model.tree.root.k[0].n | Should -Be 'Tenant Root Group'
        if ($script:canWritePdf) { $pdf | Should -Exist }
    }
}
