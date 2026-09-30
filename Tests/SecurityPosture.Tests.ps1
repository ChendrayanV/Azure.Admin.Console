<#
    Unit tests for Get-AACSecurityPosture: the posture built from made-up
    Defender for Cloud and Azure Policy rows (Fixtures\ContosoSecurity.ps1) -
    findings across sections, scores, compliance failures traced to
    resources, plans off, policy compliance, a resource group or tag
    selection - and the command with Resource Graph faked: the queries per
    section, the scope, the console view and the exports. Also: the query
    set and converters it shares with Get-AACInventory.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoSecurity.ps1')
    $script:security = Get-AACContosoSecurity
    $script:names = @{ '11111111-1111-1111-1111-111111111111' = 'sub-connectivity'; '22222222-2222-2222-2222-222222222222' = 'sub-corp-apps' }
    $script:build = {
        param([string[]] $Only, $ResourceId = $null)
        $rows = @{}
        foreach ($key in 'Scores', 'Controls', 'ControlAssessments', 'Recommendations', 'Alerts', 'Plans', 'Standards', 'ComplianceControls', 'ComplianceAssessments', 'PolicyStates', 'PolicyAssignments') {
            if (-not $Only -or $Only -contains $key) { $rows[$key] = $script:security[$key] }
        }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $rows; N = $script:names; I = $ResourceId } {
            param($R, $N, $I)
            if ($I) {
                $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($id in $I) { [void]$set.Add($id) }
                ConvertTo-AACSecurityPosture -Rows $R -SubscriptionName $N -ResourceId $set
            }
            else { ConvertTo-AACSecurityPosture -Rows $R -SubscriptionName $N }
        }
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

Describe 'Azure Admin Console - security posture' {
    BeforeAll { $script:p = & $script:build }

    It 'puts every section''s findings in one list, most severe first' {
        $script:p.Findings[0].PSObject.TypeNames | Should -Contain 'AAC.SecurityFinding'
        @($script:p.Findings | Group-Object Section | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) | Should -Be @('Alert 2', 'Compliance 3', 'Plan 2', 'Policy 3', 'Recommendation 5')
        $script:p.Findings[0].Severity | Should -Be 'High'
        $script:p.Findings[0].Section | Should -Be 'Alert' -Because 'at the same severity, alerts come first'
        ($script:p.Findings | Select-Object -Last 1).Section | Should -Be 'Policy' -Because 'Azure Policy has no severity'
    }

    It 'names each recommendation''s secure score control and links to its portal page' {
        $jit = $script:p.Recommendations | Where-Object AssessmentKey -EQ 'a-jit'
        $jit.Control | Should -Be 'Secure management ports'
        $jit.RemediationUrl | Should -BeLike 'https://portal.azure.com/*a-jit'
        $jit.Resource | Should -Be 'vm-web-01'
        $jit.Type | Should -Be 'microsoft.compute/virtualmachines'
        $jit.ResourceGroup | Should -Be 'rg-app'
        $jit.SubscriptionName | Should -Be 'sub-corp-apps'
        $jit.Since | Should -BeOfType [datetime]
    }

    It 'adds the secure scores up as Defender does, and summarises each subscription' {
        $script:p.Stats.SecureScore | Should -Be 56 -Because '(38 + 18) of (50 + 50) points'
        $corp = $script:p.Subscriptions | Where-Object SubscriptionName -EQ 'sub-corp-apps'
        $corp.SecureScore | Should -Be 36
        $corp.High | Should -Be 2
        $corp.Alerts | Should -Be 1
        "$($corp.PlansOn)/$($corp.PlansOff)" | Should -Be '2/1'
        $corp.FailedControls | Should -Be 10
        $corp.PolicyCompliance | Should -Be 60 -Because '3 of its 5 evaluated resources comply'
        ($script:p.Controls | Where-Object Control -EQ 'Secure management ports').PotentialIncrease | Should -Be 16
    }

    It 'traces a failed compliance control to the resources failing the recommendation behind it' {
        $ns1 = @($script:p.Findings | Where-Object { $_.Section -eq 'Compliance' -and $_.Control -eq 'NS.1' })
        $ns1.Count | Should -Be 2
        ($ns1 | Where-Object Resource -EQ 'vm-web-01').Severity | Should -Be 'High'
        ($ns1 | Where-Object Resource -EQ 'vm-web-01').Link | Should -BeLike 'https://*'
        ($ns1 | Where-Object Title -Like '*manual*').Resource | Should -Be 'sub-corp-apps' -Because 'a check with no resource is on the subscription'
        ($script:p.ComplianceControls | Where-Object Control -EQ 'NS.1').FailingChecks | Should -BeLike '*just-in-time*manual*'
        $script:p.ComplianceControls[0].State | Should -Be 'Failed' -Because 'failed controls first'
        ($script:p.Standards | Where-Object Standard -EQ 'Microsoft-cloud-security-benchmark').PassRate | Should -Be 80
    }

    It 'makes a finding of each Defender plan that is off, with friendly names' {
        @($script:p.Findings | Where-Object Section -EQ 'Plan').Title | Sort-Object | Should -Be @('Microsoft Defender for Servers is off', 'Microsoft Defender for Storage is off')
        ($script:p.Plans | Where-Object { $_.Name -eq 'VirtualMachines' -and $_.SubscriptionName -eq 'sub-corp-apps' }).Enabled | Should -BeTrue
    }

    It 'reports Azure Policy compliance per assignment, with display names, and each non-compliant resource' {
        $script:p.Stats.PolicyCompliance | Should -Be 67 -Because '6 of the 9 evaluated resources comply, counted as the portal does'
        $script:p.PolicyAssignments[0].Assignment | Should -Be 'Contoso allowed locations' -Because 'least compliant first (60%)'
        $script:p.PolicyAssignments[0].Scope | Should -Be 'Management group mg-corp'
        ($script:p.PolicyAssignments | Where-Object Assignment -EQ 'Contoso required tags').Enforcement | Should -Be 'DoNotEnforce'
        $locations = @($script:p.Findings | Where-Object { $_.Section -eq 'Policy' -and $_.Title -eq 'Allowed locations' })
        $locations.Count | Should -Be 2
        $locations[0].Category | Should -Be 'Contoso allowed locations'
        $locations[0].Detail | Should -Be 'Effect: deny'
        $script:p.Stats.NonCompliantResources | Should -Be 3
    }

    It 'narrows the findings to a resource selection, leaving the subscription-wide parts whole' {
        $narrow = & $script:build -ResourceId @($script:security.Ids.Vm1)
        @($narrow.Recommendations).Count | Should -Be 2
        @($narrow.Alerts).Count | Should -Be 1
        @($narrow.Findings | Where-Object Section -EQ 'Compliance').Resource | Should -Be @('vm-web-01')
        @($narrow.Findings | Where-Object Section -EQ 'Policy').Count | Should -Be 0
        $narrow.Stats.SecureScore | Should -Be 56
        @($narrow.Plans).Count | Should -Be 4
    }

    It 'uses the recommendations only for compliance when the Recommendations section wasn''t asked for' {
        $rows = @{ Standards = $script:security.Standards; ComplianceControls = $script:security.ComplianceControls; ComplianceAssessments = $script:security.ComplianceAssessments; ComplianceRecommendations = $script:security.Recommendations }
        $only = InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $rows; N = $script:names } { param($R, $N) ConvertTo-AACSecurityPosture -Rows $R -SubscriptionName $N }
        @($only.Findings | Where-Object Section -EQ 'Recommendation').Count | Should -Be 0
        @($only.Findings | Where-Object { $_.Section -eq 'Compliance' -and $_.Resource -eq 'vm-web-01' }).Count | Should -Be 1
    }
}

Describe 'Azure Admin Console - Get-AACSecurityPosture' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($key in @($Query.Keys)) {
                $rows[$key] = switch ($key) {
                    'scope' { @(@{ id = $script:security.Ids.Vm1 }) }
                    'scopeGroups' { @() }
                    default { @($script:security[$key]) }
                }
            }
            @{ Rows = $rows; Errors = @{} }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'returns the findings, and reads every section at once by default' {
        $findings = @(Get-AACSecurityPosture -NoDisplay)
        $findings.Count | Should -Be 15
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 1 -Exactly -ParameterFilter {
            $keys = @($Query.Keys)
            @('subscriptions', 'Scores', 'Controls', 'Recommendations', 'ControlAssessments', 'Alerts', 'Plans', 'Standards', 'ComplianceControls', 'ComplianceAssessments', 'PolicyStates', 'PolicyAssignments' | Where-Object { $keys -notcontains $_ }).Count -eq 0 -and
            $Query['PolicyAssignments'].Tenant -eq $true
        }
    }

    It 'reads only what the sections asked for need' {
        $findings = @(Get-AACSecurityPosture -Section Alerts, Plans -NoDisplay)
        @($findings.Section | Select-Object -Unique | Sort-Object) | Should -Be @('Alert', 'Plan')
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -Times 1 -Exactly -ParameterFilter {
            @($Query.Keys | Sort-Object) -join ',' -eq 'Alerts,Plans,Scores,subscriptions'
        }
    }

    It 'narrows to a tag or resource group with a scope query - exact tag values' {
        $findings = @(Get-AACSecurityPosture -Tag @{ Environment = 'Prod' } -NoDisplay -WarningAction SilentlyContinue)
        @($findings | Where-Object Section -EQ 'Recommendation').Resource | Select-Object -Unique | Should -Be 'vm-web-01'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { ([string]$Query['scope']).Contains("tostring(tags['Environment']) =~ 'Prod'") } -Times 1 -Exactly
        $null = Get-AACSecurityPosture -ResourceGroupName 'rg-app' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { $Query['scope'] -like "*resourceGroup in~ ('rg-app')*" -and $Query.Contains('scopeGroups') } -Times 1 -Exactly
    }

    It 'picks compliance standards by name' {
        $findings = @(Get-AACSecurityPosture -Section Compliance -Standard '*ISO*' -NoDisplay)
        @($findings.Category | Select-Object -Unique) | Should -Be @('ISO-27001-2013')
        @($findings | Where-Object Section -EQ 'Recommendation').Count | Should -Be 0
    }

    It 'draws every section at the console, in characters any console can show' {
        $text = (& $script:capture { Get-AACSecurityPosture -NoPaging }).Text
        foreach ($expected in '56%', 'secure score (fair)', 'Subscriptions', 'Secure score controls with the most to gain', 'Recommendations', 'Management ports should be protected', 'Active security alerts', 'Suspicious login to a VM', 'Regulatory compliance', 'NS.1', 'Azure Policy assignments', 'Contoso required tags', 'not enforced', 'Defender plans that are off', 'Servers') {
            $text | Should -BeLike "*$expected*"
        }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'writes the findings to CSV, and an HTML report with a table per part and portal links' {
        $csv = Join-Path $TestDrive 'security.csv'
        $html = Join-Path $TestDrive 'security.html'
        $null = & $script:capture { Get-AACSecurityPosture -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 15
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('findings', 'subscriptions', 'controls', 'standards', 'complianceControls', 'policy', 'plans')
        (($model.tables | Where-Object id -EQ 'findings').columns | Where-Object key -EQ 'Link').type | Should -Be 'link'
        ($model.tiles | Where-Object label -Like 'secure score*').value | Should -Be '56%'
        ($model.tiles | Where-Object label -EQ 'Azure Policy compliance').value | Should -Be '67%'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'security.pdf'
        $null = & $script:capture { Get-AACSecurityPosture -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}

Describe 'Azure Admin Console - shared Defender queries' {
    It 'gives Get-AACInventory and Get-AACSecurityPosture the same queries' {
        $queries = InModuleScope 'Azure.Admin.Console' { Get-AACDefenderQuery -Name 'Scores', 'Recommendations' }
        @($queries.Keys) | Should -Be @('Scores', 'Recommendations')
        $queries['Recommendations'] | Should -BeLike '*properties.links.azurePortal*'
        $queries['Recommendations'] | Should -BeLike "*status == 'Unhealthy'*"
    }
}
