<#
    Unit tests for Get-AACAccessReview: the review of made-up Contoso access
    (Fixtures\ContosoAccess.ps1) - standing and just-in-time access, guests,
    applications, disabled, dormant and deleted principals, unused access,
    custom roles, classic and Entra ID roles, Graph permissions - and the
    command with Resource Graph, Resource Manager and Microsoft Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoAccess.ps1')
    $script:f = Get-AACContosoAccess
    $script:review = { param([hashtable] $Change = @{}) $in = @{} + $script:f.Input; foreach ($k in $Change.Keys) { if ($null -eq $Change[$k]) { $in.Remove($k) } else { $in[$k] = $Change[$k] } }; InModuleScope 'Azure.Admin.Console' -Parameters @{ I = $in } { param($I) ConvertTo-AACAccessReview @I } }
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
    $script:row = { param($Result, [string] $Principal, [string] $Role, [string] $Assignment = '') @($Result.Rows | Where-Object { $_.Principal -eq $Principal -and $_.Role -eq $Role -and (-not $Assignment -or $_.Assignment -eq $Assignment) })[0] }
}

Describe 'Azure Admin Console - the access review' {
    BeforeAll { $script:r = & $script:review }

    It 'lists every assignment in scope once - RBAC, eligible, classic, Entra ID and Graph - worst first' {
        $script:r.Stats.Assignments | Should -Be 19
        @($script:r.Rows.Principal) | Should -Not -Contain 'zed' -Because 'its subscription is out of scope'
        @($script:r.Rows | Select-Object -First 2 | ForEach-Object { "$($_.Severity) $($_.Principal) $($_.Role)" }) | Should -Be @('Critical app-sync RoleManagement.ReadWrite.Directory', 'Critical Bob Builder Contributor')
        $script:r.Rows[0].PSObject.TypeNames | Should -Contain 'AAC.AccessAssignment'
        @($script:r.Rows | Where-Object Source -EQ 'Graph app permission').Count | Should -Be 3
    }

    It 'calls out standing privileged access - critical at a management group - and recommends just-in-time' {
        $bob = & $script:row $script:r 'Bob Builder' 'Contributor'
        "$($bob.Severity) | $($bob.ScopeLevel) | $($bob.Recommendation)" | Should -Be 'Critical | Management group | Make eligible (PIM)'
        $ivy = & $script:row $script:r 'Ivy Idle' 'Contributor'
        $ivy.Findings | Should -Be 'Standing privileged access to a subscription - should be just-in-time; No write operations in the last 30 day(s) (Activity Log)'
        $eve = & $script:row $script:r 'Eve Online' 'Contributor'
        "$($eve.Assignment) | $($eve.Severity) | $($eve.Recommendation)" | Should -Be 'Activated (PIM) | Info | Keep' -Because 'just-in-time is what we want'
        (& $script:row $script:r 'Ada Lovelace' 'Owner' 'Eligible (PIM)').Recommendation | Should -Be 'Keep'
    }

    It 'recommends removing the dormant, disabled, deleted and guest holders of privileged access' {
        $ada = & $script:row $script:r 'Ada Lovelace' 'Owner' 'Permanent'
        "$($ada.Severity) | $($ada.Recommendation)" | Should -Be 'High | Remove'
        $ada.Findings | Should -BeLike '*No sign-in for 200 days'
        (& $script:row $script:r 'Dan Dormant' 'Contributor').Findings | Should -Be 'The account is disabled but still holds privileged access'
        $gone = @($script:r.Rows | Where-Object Principal -Like '*(deleted)')[0]
        "$($gone.Severity) | $($gone.Recommendation)" | Should -Be 'Medium | Remove'
        (& $script:row $script:r 'Gus Guest' 'Owner').Findings | Should -Be 'A guest (external account) holds privileged access'
        (& $script:row $script:r 'old@contoso.example' 'CoAdministrator').Findings | Should -BeLike 'A classic co-administrator*'
    }

    It 'narrows applications that can grant access or take over the tenant, and wildcard custom roles' {
        (& $script:row $script:r 'sp-deploy' 'Owner').Findings | Should -Be 'An application can grant access to anyone (Owner)'
        (& $script:row $script:r 'app-mail' 'Mail.Read').Severity | Should -Be 'High'
        (& $script:row $script:r 'app-ok' 'User.ReadBasic.All').Severity | Should -Be 'Info'
        (& $script:row $script:r 'mi-app' 'Ops Admin').Findings | Should -Be "Custom role 'Ops Admin' allows '*' or changes to access"
        (& $script:row $script:r 'Ada Lovelace' 'Global Administrator').Findings | Should -BeLike 'A permanent privileged Entra ID role - should be eligible (PIM)*'
        (& $script:row $script:r 'Eve Online' 'Global Administrator').Assignment | Should -Be 'Activated (PIM)'
    }

    It 'never recommends PIM for an application or a managed identity - PIM needs a person to activate the role' {
        # Neither workload identity wrote anything in the window; mi-app also gets Contributor on the subscription.
        $idle = @{} + $script:f.Input.Activity
        $idle.Remove('app-mi-app'); $idle.Remove('app-sp-deploy')
        $contributor = "/subscriptions/$($script:f.Sub)/providers/microsoft.authorization/roledefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        $more = @($script:f.Input.Assignment) + @(@{ id = '/providers/microsoft.authorization/roleassignments/a20'; principalId = $script:f.Principal['mi-app']; principalType = 'ServicePrincipal'; roleId = $contributor; scope = "/subscriptions/$($script:f.Sub)"; createdOn = '2025-01-01T00:00:00Z' })
        $r = & $script:review @{ Activity = $idle; Assignment = $more }
        @($r.Rows | Where-Object { $_.PrincipalType -in 'Service principal', 'Managed identity' -and $_.Recommendation -eq 'Make eligible (PIM)' }).Count | Should -Be 0
        $mi = & $script:row $r 'mi-app' 'Contributor'
        "$($mi.PrincipalType) | $($mi.Severity) | $($mi.Recommendation)" | Should -Be 'Managed identity | Medium | Narrow the scope or role' -Because 'quiet for 30 days is no proof a workload is unused - narrow it, review its usage'
        $mi.Findings | Should -Be 'An application can change everything in the subscription; No write operations in the last 30 day(s) (Activity Log)'
        $mi.Action | Should -BeLike 'Scope it to the resource groups it deploys to*Check the application''s sign-in logs*An application can''t be made eligible in PIM*'
        $sp = & $script:row $r 'sp-deploy' 'Owner'
        "$($sp.Severity) | $($sp.Recommendation)" | Should -Be 'High | Narrow the scope or role' -Because 'an application with Owner is a real risk - but removing a pipeline''s role breaks it'
        $sp.Action | Should -BeLike 'Replace Owner with Contributor*Role Based Access Control Administrator with a condition*managed identity or a federated credential rather than a client secret*'
        # A person still gets just-in-time.
        $ivy = & $script:row $r 'Ivy Idle' 'Contributor'
        "$($ivy.Recommendation) | $($ivy.Action)" | Should -BeLike 'Make eligible (PIM) | Make it eligible in PIM*'
    }

    It 'asks to review an application''s usage before removing access it hasn''t used' {
        $web = 'de139f84-1756-47ae-9be6-808fbbe84772'
        $definitions = @($script:f.Input.Definition) + @(@{ id = "/providers/microsoft.authorization/roledefinitions/$web"; roleName = 'Website Contributor'; roleType = 'BuiltInRole'; permissions = @(@{ actions = @('Microsoft.Web/sites/*') }) })
        $more = @($script:f.Input.Assignment) + @(@{ id = '/providers/microsoft.authorization/roleassignments/a22'; principalId = $script:f.Principal['mi-app']; principalType = 'ServicePrincipal'; roleId = "/subscriptions/$($script:f.Sub)/providers/microsoft.authorization/roledefinitions/$web"; scope = "/subscriptions/$($script:f.Sub)/resourcegroups/rg-app"; createdOn = '2025-01-01T00:00:00Z' })
        $idle = @{} + $script:f.Input.Activity
        $idle.Remove('app-mi-app')
        $r = & $script:review @{ Activity = $idle; Assignment = $more; Definition = $definitions }
        $row = & $script:row $r 'mi-app' 'Website Contributor'
        "$($row.Severity) | $($row.Recommendation)" | Should -Be 'Medium | Review usage'
        $row.Action | Should -BeLike "Check the application's sign-in logs*If it isn't used, remove the role*"
    }

    It 'doesn''t call data-plane access unused - the Activity Log doesn''t record it' {
        $blob = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
        $definitions = @($script:f.Input.Definition) + @(@{ id = "/providers/microsoft.authorization/roledefinitions/$blob"; roleName = 'Storage Blob Data Contributor'; roleType = 'BuiltInRole'; permissions = @(@{ actions = @('Microsoft.Storage/storageAccounts/blobServices/containers/write'); dataActions = @('Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write') }) })
        $more = @($script:f.Input.Assignment) + @(@{ id = '/providers/microsoft.authorization/roleassignments/a21'; principalId = $script:f.Principal['mi-app']; principalType = 'ServicePrincipal'; roleId = "/subscriptions/$($script:f.Sub)/providers/microsoft.authorization/roledefinitions/$blob"; scope = "/subscriptions/$($script:f.Sub)/resourcegroups/rg-app"; createdOn = '2025-01-01T00:00:00Z' })
        $idle = @{} + $script:f.Input.Activity
        $idle.Remove('app-mi-app')
        $r = & $script:review @{ Activity = $idle; Assignment = $more; Definition = $definitions }
        $row = & $script:row $r 'mi-app' 'Storage Blob Data Contributor'
        "$($row.Severity) | $($row.Recommendation) | $($row.Findings)" | Should -Be 'Info | Keep | ' -Because 'an app writing blobs all day leaves nothing in the Activity Log'
    }

    It 'says what it couldn''t assess when Entra ID or the Activity Log weren''t read' {
        $blind = & $script:review @{ Directory = $null; Activity = $null }
        $blind.Notices | Should -Be @("Entra ID couldn't be read, so principals are shown by ID and deleted ones can't be told apart (Microsoft Graph: Directory.Read.All).", "The Activity Log wasn't read, so unused access isn't assessed (-ActivityDays).")
        @($blind.Rows | Where-Object { $_.Findings -like '*No write operations*' -or $_.Findings -like '*no longer exists*' }).Count | Should -Be 0
    }

    It 'flags more than four Global Administrators' {
        $many = @($script:f.Input.EntraAssignment) + @(1..3 | ForEach-Object { @{ id = "x$_"; principalId = $script:f.Principal['ivy']; roleDefinitionId = 'ga' } }) + @(@{ id = 'x9'; principalId = $script:f.Principal['dan']; roleDefinitionId = 'ga' })
        $r = & $script:review @{ EntraAssignment = $many }
        (& $script:row $r 'Dan Dormant' 'Global Administrator').Findings | Should -BeLike '*5 Global Administrators - Microsoft recommends fewer than 5'
    }
}

Describe 'Azure Admin Console - Get-AACAccessReview' {
    BeforeEach {
        $i = $script:f.Input
        $script:armUris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Sub; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-prod' }, @{ name = 'contoso' }) }) }; Errors = @{} } }
            @{ Rows = @{ roleAssignments = $script:f.Input.Assignment; roleDefinitions = $script:f.Input.Definition }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            $now = [datetime]::UtcNow
            foreach ($u in $Uri) {
                $script:armUris.Add($u)
                $items = switch -Wildcard ($u) {
                    '*roleEligibilityScheduleInstances*' { $script:f.Input.Eligibility; break }
                    '*roleAssignmentScheduleInstances*' { $script:f.Input.ScheduleInstance; break }
                    '*classicAdministrators*' { @($script:f.Input.ClassicAdmin[0].Items); break }
                    '*eventtypes/management*' {
                        @(foreach ($caller in 'ada@contoso.example', 'app-sp-deploy', 'eve@contoso.example', 'dan@contoso.example', 'gus@contoso.example', 'app-mi-app') { @{ caller = $caller; eventTimestamp = $now.AddDays(-2).ToString('o'); status = @{ value = 'Succeeded' }; authorization = @{ action = 'Microsoft.Compute/virtualMachines/write' } } }
                            @{ caller = 'ivy@contoso.example'; eventTimestamp = $now.AddDays(-1).ToString('o'); status = @{ value = 'Succeeded' }; authorization = @{ action = 'Microsoft.Compute/virtualMachines/read' } })
                        break
                    }
                }
                $answers[$u] = @{ Status = 200; Items = @($items); Error = '' }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -MockWith { @{ Objects = $script:f.Input.Directory; Error = '' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith {
            $data = @{}
            $map = @{ entraAssignments = $script:f.Input.EntraAssignment; entraEligibility = $script:f.Input.EntraEligibility; entraDefinitions = $script:f.Input.EntraDefinition; graphGrants = $script:f.Input.AppGrant
                entraActive = @(@{ principalId = $script:f.Principal['eve']; roleDefinitionId = 'ga'; assignmentType = 'Activated' }); graphApp = @{ appRoles = @(@{ id = 'role-rm'; value = 'RoleManagement.ReadWrite.Directory' }, @{ id = 'role-mail'; value = 'Mail.Read' }, @{ id = 'role-basic'; value = 'User.ReadBasic.All' }) } }
            foreach ($key in $Query.Keys) {
                if ($map.Contains($key)) { $data[$key] = $map[$key] }
                elseif ($key -eq $script:f.Principal['ada']) { $data[$key] = @{ signInActivity = @{ lastSignInDateTime = [datetime]::UtcNow.AddDays(-200).ToString('o') } } }
                else { $data[$key] = @{ signInActivity = @{ lastSignInDateTime = [datetime]::UtcNow.AddDays(-1).ToString('o') } } }
            }
            @{ Data = $data; Errors = @{} }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads RBAC, PIM, classic admins, the Activity Log, Entra ID and Graph - and reviews it all' {
        $rows = @(Get-AACAccessReview -NoDisplay)
        $rows.Count | Should -Be 19
        @($script:armUris | Where-Object { $_ -like '*eventtypes/management*' }).Count | Should -Be 1
        $script:armUris | Should -Contain "/subscriptions/$($script:f.Sub)/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01"
        (& $script:row @{ Rows = $rows } 'Ivy Idle' 'Contributor').Findings | Should -BeLike '*No write operations in the last 30 day(s)*' -Because 'reading is not changing'
        (& $script:row @{ Rows = $rows } 'Ada Lovelace' 'Owner' 'Permanent').Findings | Should -BeLike '*No sign-in for 200 days'
        (& $script:row @{ Rows = $rows } 'Eve Online' 'Global Administrator').Assignment | Should -Be 'Activated (PIM)'
    }

    It 'skips the Activity Log with -ActivityDays 0 and Entra ID roles with -SkipEntra, and filters' {
        $rows = @(Get-AACAccessReview -ActivityDays 0 -SkipEntra -NoDisplay)
        @($script:armUris | Where-Object { $_ -like '*eventtypes*' }).Count | Should -Be 0
        @($rows | Where-Object Source -In 'Entra ID role', 'Graph app permission').Count | Should -Be 0
        @(Get-AACAccessReview -PrivilegedOnly -Severity Critical -NoDisplay).Principal | Should -Be @('app-sync', 'Bob Builder')
    }

    It 'shows the review at the prompt, and writes the attestation CSV with Decision and Reviewer columns' {
        $text = (& $script:capture { Get-AACAccessReview -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Access review', 'x 19 assignment(s) for 14 principal(s): 2 critical, 8 high', 'standing privileged (users)', 'Recommendations', 'Access (top 25 of 19)'.Replace('top 25 of 19', '19'), 'Make eligible (PIM)') { $text | Should -Match ([regex]::Escape($expected)) }
        $csv = Join-Path $TestDrive 'access.csv'
        $null = & $script:capture { Get-AACAccessReview -CsvPath $csv }
        $header = (Get-Content -LiteralPath $csv -TotalCount 1)
        $header | Should -BeLike '*"Recommendation","Action","Decision","Reviewer"*'
    }
}
