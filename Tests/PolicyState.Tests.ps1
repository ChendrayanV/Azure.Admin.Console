<#
    Unit tests for Get-AACPolicyState: the compliance built from made-up
    Azure Policy states (Fixtures\ContosoPolicy.ps1) - per resource,
    assignment, subscription, resource group and policy - and the command
    with Resource Graph faked: its KQL and scope, the console view and the
    exports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoPolicy.ps1')
    $script:policy = Get-AACContosoPolicy
    $script:names = @{ '11111111-1111-1111-1111-111111111111' = 'sub-connectivity'; '22222222-2222-2222-2222-222222222222' = 'sub-corp-apps' }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 150
        $console.Profile.Capabilities.Unicode = $false
        try {
            [Spectre.Console.AnsiConsole]::Console = $console
            $output = @(& $Render)
        }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - policy compliance' {
    BeforeAll {
        $script:c = InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $script:policy; N = $script:names } {
            param($P, $N)
            ConvertTo-AACPolicyState -Row $P.States -Assignment $P.Assignments -SubscriptionName $N -ManagementGroupName @{ 'mg-landingzones' = 'Landing Zones' }
        }
    }

    It 'flattens every state, non-compliant first, with names for the policy, initiative, assignment and scope' {
        $script:c.States.Count | Should -Be 6
        $script:c.States[0].ComplianceState | Should -Be 'NonCompliant'
        $script:c.States[0].PSObject.TypeNames | Should -Contain 'AAC.PolicyState'
        $row = $script:c.States | Where-Object { $_.Resource -eq 'stordersdata' -and $_.ComplianceState -eq 'NonCompliant' }
        $row.Policy | Should -Be 'Allowed locations'
        $row.PolicySet | Should -Be 'Contoso baseline'
        $row.Assignment | Should -Be 'Contoso: allowed locations'
        $row.AssignmentScope | Should -Be 'Management group Landing Zones'
        $row.SubscriptionName | Should -Be 'sub-corp-apps'
        $row.ResourceGroup | Should -Be 'rg-data'
        $row.EvaluatedAt | Should -BeOfType [datetime]
        ($script:c.States | Where-Object Assignment -EQ 'Contoso: require CostCenter')[0].AssignmentScope | Should -Be 'Subscription sub-corp-apps'
    }

    It 'judges each resource by all its policies, and counts compliance as the portal does' {
        ($script:c.Resources | Where-Object Resource -EQ 'vm-web-01').Compliance | Should -Be 'NonCompliant' -Because 'one policy finds it so'
        ($script:c.Resources | Where-Object Resource -EQ 'vm-web-01').NonCompliantWith | Should -Be 'Require a tag on resources'
        ($script:c.Resources | Where-Object Resource -EQ 'stordersdata').Compliance | Should -Be 'NonCompliant'
        ($script:c.Resources | Where-Object Resource -EQ 'kv-app').Compliance | Should -Be 'Compliant'
        $script:c.Stats.Resources | Should -Be 4
        "$($script:c.Stats.Compliant)/$($script:c.Stats.NonCompliant)" | Should -Be '2/2'
        $script:c.Stats.ComplianceRate | Should -Be 50
    }

    It 'summarises each assignment, subscription, resource group and policy' {
        $tags = $script:c.Assignments | Where-Object Assignment -EQ 'Contoso: require CostCenter'
        "$($tags.Compliant)/$($tags.NonCompliant)/$($tags.Exempt)" | Should -Be '1/1/1'
        $tags.ComplianceRate | Should -Be 67 -Because 'exempt counts as compliant, as in the portal: (1 + 1) of 3'
        $tags.Enforcement | Should -Be 'DoNotEnforce'
        ($script:c.Scopes | Where-Object { $_.Level -eq 'Subscription' -and $_.Name -eq 'sub-connectivity' }).ComplianceRate | Should -Be 100
        $data = $script:c.Scopes | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.Name -eq 'rg-data' }
        $data.ComplianceRate | Should -Be 0
        $script:c.Scopes[0].Level | Should -Be 'Subscription' -Because 'subscriptions first'
        @($script:c.Policies.Policy) | Should -Contain 'Allowed locations'
        $script:c.Stats.NonCompliantPolicies | Should -Be 2
    }

    It "gives the portal's tiles: compliant resources, initiatives and policies, each out of all" {
        "$($script:c.Stats.CompliantCounted) of $($script:c.Stats.Resources)" | Should -Be '2 of 4'
        "$($script:c.Stats.NonCompliantInitiatives) of $($script:c.Stats.Initiatives)" | Should -Be '1 of 1' -Because 'the baseline finds stordersdata non-compliant'
        "$($script:c.Stats.NonCompliantPolicies) of $($script:c.Stats.Policies)" | Should -Be '2 of 2'
    }

    It 'keeps the id column, so Resource Graph pages through every state, and names policies by their full ID' {
        $query = InModuleScope 'Azure.Admin.Console' { Get-AACPolicyStateQuery }
        $query | Should -Match '\| project id, '
        $query | Should -Match 'project definitionId = tolower\(id\).* on definitionId'
        $query | Should -Match 'project setId = tolower\(id\).* on setId'
    }
}

Describe 'Azure Admin Console - policy roll-up, as the Azure portal does it' {
    BeforeAll {
        $script:rollup = {
            param([object[]] $States)
            $rows = @(foreach ($s in $States) { @{ subscriptionId = 's1'; resourceId = "/subscriptions/s1/resourcegroups/rg/providers/x/y/$($s[0])"; resourceGroup = 'rg'; state = $s[1]; assignmentId = 'a1'; assignment = 'a1'; policy = $s[2] } })
            InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $rows } { param($R) ConvertTo-AACPolicyState -Row $R }
        }
    }

    It 'gives each resource the state that ranks first: Non-compliant, Compliant, Error, Conflicting, Protected, Exempt, Unknown' {
        $c = & $script:rollup @(
            @('r1', 'Compliant', 'p1'), @('r1', 'NonCompliant', 'p2')
            @('r2', 'Exempt', 'p1'), @('r2', 'Compliant', 'p2')
            @('r3', 'Exempt', 'p1'), @('r3', 'Error', 'p2')
            @('r4', 'Unknown', 'p1'), @('r4', 'Exempt', 'p2')
            @('r5', 'Conflicting', 'p1'), @('r5', 'Protected', 'p2')
        )
        $verdict = @{}
        foreach ($r in $c.Resources) { $verdict[$r.Resource] = $r.Compliance }
        "$($verdict.r1) $($verdict.r2) $($verdict.r3) $($verdict.r4) $($verdict.r5)" | Should -Be 'NonCompliant Compliant Error Exempt Conflict'
    }

    It 'counts compliant, exempt, unknown and protected as compliant, out of every resource evaluated - and leaves out Not started' {
        $c = & $script:rollup @(
            @('r1', 'Compliant', 'p1'), @('r2', 'Exempt', 'p1'), @('r3', 'Unknown', 'p1'), @('r4', 'Protected', 'p1')
            @('r5', 'NonCompliant', 'p1'), @('r6', 'Error', 'p1'), @('r7', 'Conflict', 'p1'), @('r8', 'NotStarted', 'p1')
        )
        $c.Stats.Resources | Should -Be 7
        $c.Stats.ComplianceRate | Should -Be 57 -Because '4 of 7, as the portal computes it'
        $c.Stats.NotCounted | Should -Be 1
    }
}

Describe 'Azure Admin Console - Get-AACPolicyState' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{
                states           = @($script:policy.States | Where-Object { $q = [string]$Query['states']; ($q -notmatch "resourceGroup in~" -or $q -match "'$($_.resourceGroup)'") -and ($q -notmatch "state in~" -or $q -match "'$($_.state)'") })
                assignments      = $script:policy.Assignments
                subscriptions    = $script:policy.Subscriptions
                managementGroups = $script:policy.ManagementGroups
            }
            @{ Rows = $rows; Errors = @{} }
        }
    }

    It 'reads the states with one KQL query in scope, and the names tenant-wide' {
        $rows = @(Get-AACPolicyState -NoDisplay)
        $rows.Count | Should -Be 6
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 1 -Exactly -ParameterFilter {
            ([string]$Query['states']).Contains('microsoft.policyinsights/policystates') -and $Query['assignments'].Tenant -and $Query['subscriptions'].Tenant -and $Query['managementGroups'].Tenant
        }
    }

    It 'scopes to management groups, subscriptions and resource groups, and filters states in the query' {
        $null = Get-AACPolicyState -ManagementGroupId 'mg-landingzones' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { @($ManagementGroupId) -contains 'mg-landingzones' } -Times 1 -Exactly
        $null = Get-AACPolicyState -SubscriptionId '22222222-2222-2222-2222-222222222222' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { @($SubscriptionId) -contains '22222222-2222-2222-2222-222222222222' } -Times 1 -Exactly
        $rows = @(Get-AACPolicyState -ResourceGroupName 'rg-app' -ComplianceState NonCompliant -NoDisplay)
        $rows.Count | Should -Be 1
        $rows[0].Resource | Should -Be 'vm-web-01'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { $q = [string]$Query['states']; $q.Contains("state in~ ('NonCompliant')") -and $q.Contains("resourceGroup in~ ('rg-app')") } -Times 1 -Exactly
    }

    It 'says so when a resource group has no policy states' {
        $null = Get-AACPolicyState -ResourceGroupName 'rg-typo' -NoDisplay
        $text = (& $script:capture { Get-AACPolicyState -ResourceGroupName 'rg-typo' -NoPaging }).Text
        $text | Should -BeLike "*No policy states for resource group 'rg-typo'*"
    }

    It 'draws the compliance at the console, in characters any console can show' {
        $text = (& $script:capture { Get-AACPolicyState -NoPaging }).Text
        foreach ($expected in 'resource compliance', '50%', 'Compliance by subscription', 'Compliance by resource group', 'Assignments', 'Contoso: require CostCenter', 'not enforced', 'Non-compliant resources by policy', 'Allowed locations', 'stordersdata') {
            $text | Should -BeLike "*$expected*"
        }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'writes every state to CSV, and an HTML report with a table per summary' {
        $csv = Join-Path $TestDrive 'policy.csv'
        $html = Join-Path $TestDrive 'policy.html'
        $null = & $script:capture { Get-AACPolicyState -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 6
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('resources', 'states', 'assignments', 'policies', 'subscriptions', 'groups')
        ($model.charts | Where-Object title -EQ 'Policy states').kind | Should -Be 'donut'
        ($model.tiles | Where-Object label -EQ 'resource compliance (2 of 4)').value | Should -Be '50%'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'policy.pdf'
        $null = & $script:capture { Get-AACPolicyState -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
