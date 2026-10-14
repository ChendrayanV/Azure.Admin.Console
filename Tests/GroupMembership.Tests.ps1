<#
    Unit tests for Get-AACEntraGroupMembership: the flattened rows built from
    made-up Contoso groups (Fixtures\ContosoGroups.ps1) - direct and nested
    members, a loop, an empty group, the counts - the Microsoft Graph reads
    through a fake Graph (paging, filters, a group that can't be read), the
    command's output and exports, with the Connect-AAC sign-in's Graph token.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoGroups.ps1')
    $script:contosoGroups = Get-AACContosoGroups
    $script:graphDeny = @()
    $script:build = {
        param([string[]] $Ids, [hashtable] $Errors = @{})
        $data = $script:contosoGroups
        InModuleScope 'Azure.Admin.Console' -Parameters @{ G = @($Ids | ForEach-Object { $data.Groups[$_] }); M = $data.Members; E = $Errors; O = $data.Owners } {
            param($G, $M, $E, $O)
            ConvertTo-AACGroupMembership -Group $G -Member $M -MemberError $E -Owner $O
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
        $console.Profile.Width = 140
        $console.Profile.Capabilities.Unicode = $false
        try {
            [Spectre.Console.AnsiConsole]::Console = $console
            $output = @(& $Render)
        }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - group membership rows' {
    BeforeAll { $script:m = & $script:build @('g-fin', 'g-all', 'g-loopa', 'g-empty') }

    It 'lists direct members, then everyone in nested groups with the path they came through' {
        $fin = @($script:m.Rows | Where-Object GroupName -EQ 'grp-finance')
        @($fin | Where-Object Membership -EQ 'Direct').MemberName | Should -Be @('Ada Lovelace', 'Gus Guest', 'grp-finance-emea')
        $nested = @($fin | Where-Object Membership -EQ 'Nested')
        $nested.MemberName | Should -Be @('Grace Hopper', 'Ada Lovelace', 'app-payroll')
        $nested[0].Via | Should -Be 'grp-finance > grp-finance-emea'
        $nested[0].Depth | Should -Be 1
        $nested[2].MemberType | Should -Be 'Service principal'
        $fin[0].PSObject.TypeNames | Should -Contain 'AAC.EntraGroupMember'
    }

    It 'describes each group, and counts unique users through every nested group' {
        $fin = $script:m.Groups | Where-Object GroupName -EQ 'grp-finance'
        $fin.GroupType | Should -Be 'Security'
        $fin.GroupSource | Should -Be 'Cloud'
        $fin.DirectMembers | Should -Be 3
        $fin.NestedGroups | Should -Be 1
        $fin.Users | Should -Be 3 -Because 'Ada is in it twice but counts once'
        $fin.Guests | Should -Be 1
        $fin.DisabledUsers | Should -Be 1
        ($script:m.Groups | Where-Object GroupName -EQ 'grp-all-staff').GroupType | Should -Be 'Microsoft 365 (dynamic)'
        ($script:m.Rows | Where-Object { $_.GroupName -eq 'grp-finance' -and $_.MemberName -eq 'Grace Hopper' }).AccountEnabled | Should -BeFalse
        (& $script:build @('g-emea')).Groups[0].GroupSource | Should -Be 'Synced from on-premises AD'
    }

    It 'follows a loop of nested groups once, and keeps an empty group as a row' {
        $loop = @($script:m.Rows | Where-Object GroupName -EQ 'grp-loop-a')
        $loop.MemberName | Should -Be @('grp-loop-b', 'Linus Torvalds', 'grp-loop-a')
        ($loop | Select-Object -Last 1).Via | Should -Be 'grp-loop-a > grp-loop-b'
        $empty = @($script:m.Rows | Where-Object GroupName -EQ 'grp-empty')
        $empty.Count | Should -Be 1
        $empty[0].Membership | Should -Be 'Empty'
        ($script:m.Groups | Where-Object GroupName -EQ 'grp-loop-a').NestedGroups | Should -Be 1 -Because 'the group itself, met again, is not a nested group'
        $script:m.Stats.EmptyGroups | Should -Be 1
        $script:m.Stats.Users | Should -Be 4
    }

    It 'splits each group into its direct members and each nested group''s, and lists everyone once with how they''re in it' {
        $sections = @($script:m.Sections[($script:m.Groups | Where-Object GroupName -EQ 'grp-finance').GroupId])
        @($sections | ForEach-Object { "[$($_.Path)] $(@($_.Members.MemberName) -join ', ')" }) | Should -Be @('[] Ada Lovelace, Gus Guest, grp-finance-emea', '[grp-finance-emea] Grace Hopper, Ada Lovelace, app-payroll')
        $loop = @($script:m.Sections['g-loopa'])
        $loop[1].Path | Should -Be 'grp-loop-b'
        $loop[1].Loops.Contains('g-loopa') | Should -BeTrue -Because 'grp-loop-a is met again inside grp-loop-b'
        @($script:m.Sections['g-empty'])[0].Members.Count | Should -Be 0
        $people = @($script:m.People | Where-Object GroupName -EQ 'grp-finance')
        @($people | ForEach-Object { "$($_.MemberName)|$($_.MemberType)|$($_.Membership)|$($_.Through)" }) | Should -Be @(
            'Ada Lovelace|User|Direct and nested|grp-finance-emea'
            'app-payroll|Service principal|Nested|grp-finance-emea'
            'Grace Hopper|User|Nested|grp-finance-emea'
            'Gus Guest|User|Direct|'
        )
        $people[0].PSObject.TypeNames | Should -Contain 'AAC.EntraGroupPerson'
    }

    It 'gives each group and row its owners, when it was created and its membership type' {
        $fin = $script:m.Groups | Where-Object GroupName -EQ 'grp-finance'
        $fin.Owners | Should -Be 'Ada Lovelace (ada@contoso.example); app-payroll (Service principal)'
        $fin.OwnerCount | Should -Be 2
        $fin.Created | Should -Be ([datetime]::new(2024, 1, 15, 9, 30, 0, [System.DateTimeKind]::Utc))
        $fin.MembershipType | Should -Be 'Assigned'
        ($script:m.Groups | Where-Object GroupName -EQ 'grp-all-staff').MembershipType | Should -Be 'Dynamic'
        ($script:m.Groups | Where-Object GroupName -EQ 'grp-empty').Owners | Should -Be '(No owners)'
        $row = $script:m.Rows | Where-Object GroupName -EQ 'grp-finance' | Select-Object -First 1
        "$($row.MembershipType) | $($row.GroupCreated.ToString('yyyy-MM-dd')) | $($row.GroupOwners)" | Should -Be 'Assigned | 2024-01-15 | Ada Lovelace (ada@contoso.example); app-payroll (Service principal)'
        $sum = $script:m.Summary | Where-Object GroupName -EQ 'grp-finance'
        "$($sum.Owners) | $($sum.CreatedDateTime) | $($sum.MembershipType)" | Should -Be 'Ada Lovelace (ada@contoso.example); app-payroll (Service principal) | 2024-01-15 09:30 UTC | Assigned'
        $paused = $script:contosoGroups.Groups['g-all'].Clone(); $paused.membershipRuleProcessingState = 'Paused'
        $p = InModuleScope 'Azure.Admin.Console' -Parameters @{ G = $paused } { param($G) ConvertTo-AACGroupMembership -Group @($G) -OwnerError @{ 'g-all' = 'Insufficient privileges.' } }
        $p.Groups[0].MembershipType | Should -Be 'Dynamic (paused)'
        $p.Groups[0].Owners | Should -Be '(Not read: Insufficient privileges.)'
    }

    It 'says which group''s members couldn''t be read' {
        $m = & $script:build @('g-fin') @{ 'g-emea' = 'Insufficient privileges.' }
        $m.Groups[0].Error | Should -BeLike '*grp-finance-emea*Insufficient privileges*'
    }
}

Describe 'Azure Admin Console - Get-AACEntraGroupMembership' {
    BeforeEach {
        $script:graphDeny = @()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { if ($Resource -eq 'https://graph.microsoft.com') { 'graph-token' } else { 'arm-token' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -MockWith { & $script:graphFake $Uri $Header }
    }

    It 'reads the groups by name, pages through their members, follows nested groups, and returns the rows' {
        $rows = @(Get-AACEntraGroupMembership -GroupName 'grp-finance' -NoDisplay)
        $rows.Count | Should -Be 6
        @($rows | Where-Object Membership -EQ 'Nested').Count | Should -Be 3
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -ParameterFilter { [System.Uri]::UnescapeDataString($Uri) -like "*/groups?*`$filter=displayName eq 'grp-finance'*" -and $Token -eq 'graph-token' } -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -ParameterFilter { $Uri -like '*/groups/g-fin/members*' } -Times 2 -Exactly -Because 'three members come in two pages'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -ParameterFilter { $Uri -like '*/groups/g-emea/members*' } -Times 2 -Exactly
    }

    It 'lists service principals among the members: Graph v1.0 leaves them out unless asked with an advanced query' {
        $rows = @(Get-AACEntraGroupMembership -GroupName 'grp-finance-emea' -NoDisplay)
        @($rows.MemberName) | Should -Be @('Grace Hopper', 'Ada Lovelace', 'app-payroll')
        ($rows | Where-Object MemberName -EQ 'app-payroll').MemberType | Should -Be 'Service principal'
        (Get-AACEntraGroupMembership -GroupName 'grp-finance' -NoDisplay)[0].GroupOwners | Should -BeLike '*app-payroll (Service principal)*' -Because 'service principals can own a group too'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -ParameterFilter { $Uri -like '*/members?*' -and -not ($Uri -like '*$count=true*' -and $Header['ConsistencyLevel'] -eq 'eventual') } -Times 0 -Exactly
        $csv = Join-Path $TestDrive 'spn.csv'
        $null = & $script:capture { Get-AACEntraGroupMembership -GroupName 'grp-finance' -CsvPath $csv }
        (Import-Csv -LiteralPath $csv).NestedGroupMembers | Should -Be 'grp-finance-emea: Grace Hopper, Ada Lovelace, app-payroll'
    }

    It 'uses the Connect-AAC sign-in for Microsoft Graph - no second sign-in' {
        $null = Get-AACEntraGroupMembership -GroupName 'grp-empty' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -ParameterFilter { $Resource -eq 'https://graph.microsoft.com' }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -ParameterFilter { $Resource -ne 'https://graph.microsoft.com' } -Times 0 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -ParameterFilter { $Token -ne 'graph-token' } -Times 0 -Exactly
    }

    It 'finds groups by the start of their name, quoting it for OData' {
        $rows = @(Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-loop' -NoDisplay)
        @($rows.GroupName | Select-Object -Unique) | Should -Be @('grp-loop-a', 'grp-loop-b')
        { Get-AACEntraGroupMembership -GroupNameStartsWith "grp-o'brien" -NoDisplay } | Should -Throw "*No group starting with 'grp-o'brien' was found*"
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -ParameterFilter { [System.Uri]::UnescapeDataString($Uri) -like "*startswith(displayName,'grp-o''brien')*" } -Times 1 -Exactly
    }

    It 'warns about a name it can''t find, and stops when it finds none' {
        $rows = @(Get-AACEntraGroupMembership -GroupNames 'grp-empty', 'grp-typo' -NoDisplay -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows[0].Membership | Should -Be 'Empty'
        "$warnings" | Should -BeLike "*No group named 'grp-typo'*"
        { Get-AACEntraGroupMembership -GroupName 'grp-nope' -NoDisplay } | Should -Throw "*No group 'grp-nope' was found*"
    }

    It 'keeps going when a group''s members can''t be read, and says why' {
        $script:graphDeny = @('g-emea')
        $rows = @(Get-AACEntraGroupMembership -GroupName 'grp-finance' -NoDisplay)
        @($rows | Where-Object Membership -EQ 'Direct').Count | Should -Be 3
        $html = Join-Path $TestDrive 'denied.html'
        $null = & $script:capture { Get-AACEntraGroupMembership -GroupName 'grp-finance' -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        ($model.tables | Where-Object id -EQ 'groups').rows[0].Error | Should -BeLike '*Insufficient privileges*'
        # The CSV: grp-finance stays, its nested group's members shown as none; a group of its own that can't be read is left out, and said.
        $csv = Join-Path $TestDrive 'denied.csv'
        $warned = (& $script:capture { $null = Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-finance-emea' -CsvPath $csv -WarningVariable seen -WarningAction SilentlyContinue; $seen }).Output
        @(Import-Csv -LiteralPath $csv | ForEach-Object { "$($_.GroupName)|$($_.NestedGroupMembers)" }) | Should -Be @('grp-finance|grp-finance-emea: (No members)')
        @($warned | ForEach-Object { "$_" }) | Should -Be @("The members of group 'grp-finance-emea' couldn't be read, so it's left out of the CSV: Insufficient privileges to complete the operation.")
    }

    It 'summarises each group in Export-EntraGroupMemberShip.ps1''s columns: its labels, everyone in it flattened, and nested groups'' own members' {
        $m = & $script:build @('g-fin', 'g-all', 'g-loopa', 'g-empty', 'g-emea')
        @($m.Summary | ForEach-Object { "$($_.GroupName) | $($_.GroupSource) | $($_.GroupType) | $($_.Members) | $($_.NestedGroupMembers)" }) | Should -Be @(
            'grp-all-staff | Cloud | Microsoft 365 / Dynamic | Ada Lovelace, Linus Torvalds | '
            'grp-empty | Cloud | Security | (No members) | '
            'grp-finance | Cloud | Security | Ada Lovelace, Gus Guest, Grace Hopper, app-payroll | grp-finance-emea: Grace Hopper, Ada Lovelace, app-payroll'
            'grp-finance-emea | Windows Server AD | Security | Grace Hopper, Ada Lovelace, app-payroll | '
            'grp-loop-a | Cloud | Security | Linus Torvalds | grp-loop-b: Linus Torvalds, grp-loop-a (Group)'
        )
        @($m.Summary[0].PSObject.Properties.Name) | Should -Be @('GroupName', 'GroupSource', 'GroupType', 'Members', 'NestedGroupMembers', 'Owners', 'CreatedDateTime', 'MembershipType')
        $m.Summary[0].PSObject.TypeNames | Should -Contain 'AAC.EntraGroupMembershipSummary'
    }

    It 'expands groups nested at every depth in the summary, each group once' {
        $data = $script:contosoGroups
        $members = @{}
        foreach ($key in $data.Members.Keys) { $members[$key] = $data.Members[$key] }
        # grp-finance > grp-finance-emea > grp-loop-a > grp-loop-b (> grp-loop-a again), and grp-loop-b straight under grp-finance too.
        $members['g-emea'] = @($data.Members['g-emea']) + $data.Groups['g-loopa']
        $members['g-fin'] = @($data.Members['g-fin']) + $data.Groups['g-loopb']
        $m = InModuleScope 'Azure.Admin.Console' -Parameters @{ G = @($data.Groups['g-fin']); M = $members } {
            param($G, $M)
            ConvertTo-AACGroupMembership -Group $G -Member $M
        }
        $m.Summary[0].NestedGroupMembers | Should -Be ('grp-finance-emea: Grace Hopper, Ada Lovelace, app-payroll, grp-loop-a (Group); ' +
            'grp-finance-emea > grp-loop-a: grp-loop-b (Group); ' +
            'grp-finance-emea > grp-loop-a > grp-loop-b: Linus Torvalds, grp-loop-a (Group)')
    }

    It 'names a member by its UPN or ID when it has no display name, and leaves out a group whose members couldn''t be read' {
        $data = $script:contosoGroups
        $members = @{}
        foreach ($key in $data.Members.Keys) { $members[$key] = $data.Members[$key] }
        $members['g-all'] = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-x'; displayName = $null; userPrincipalName = 'x@contoso.example' }, @{ '@odata.type' = '#microsoft.graph.device'; id = 'd-1' })
        $role = $data.Groups['g-loopa'].Clone(); $role.isAssignableToRole = $true; $role.mailEnabled = $true
        $m = InModuleScope 'Azure.Admin.Console' -Parameters @{ G = @($data.Groups['g-all'], $data.Groups['g-fin'], $data.Groups['g-emea'], $role); M = $members } {
            param($G, $M)
            ConvertTo-AACGroupMembership -Group $G -Member $M -MemberError @{ 'g-emea' = 'Insufficient privileges.' }
        }
        ($m.Summary | Where-Object GroupName -EQ 'grp-all-staff').Members | Should -Be 'x@contoso.example, d-1'
        ($m.Summary | Where-Object GroupName -EQ 'grp-finance').NestedGroupMembers | Should -Be 'grp-finance-emea: (No members)'
        ($m.Summary | Where-Object GroupName -EQ 'grp-loop-a').GroupType | Should -Be 'Mail-Enabled Security / Role-Assignable'
        @($m.Summary.GroupName) | Should -Not -Contain 'grp-finance-emea'
    }

    It 'draws the groups and each group''s members flattened at the console, in characters any console can show' {
        $text = (& $script:capture { Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -NoPaging }).Text
        foreach ($expected in 'unique users', 'grp-finance', 'Security', 'Synced from on-premises AD', 'Microsoft 365 (dynamic)', 'Ada Lovelace (ada@contoso.example); app-payroll (Service principal)', 'Assigned', '2024-01-15 09:30 UTC', 'Dynamic', 'DIRECT MEMBERS (3)', 'NESTED GROUP grp-finance-emea (3 members)', 'its members are listed below', 'already listed above (a loop)', '3 direct', '4 in all (1 guest, 1 disabled)', 'app-payroll', 'Service principal', 'Grace Hopper', 'DISABLED', 'GUEST', 'no members') {
            $text | Should -BeLike "*$expected*"
        }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            $lost = @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ })
            $lost | Should -BeNullOrEmpty -Because "code page $codePage would print these as ?"
        }
    }

    It 'writes the CSV a row per group as Export-EntraGroupMemberShip.ps1 does (-OutputPath too), or per member, and an HTML report with a groups and a memberships table' {
        $csv = Join-Path $TestDrive 'groups.csv'
        $html = Join-Path $TestDrive 'groups.html'
        $null = & $script:capture { Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-empty' -OutputPath $csv -HtmlPath $html }
        $groupRows = @(Import-Csv -LiteralPath $csv)
        (Get-Content -LiteralPath $csv -TotalCount 1) | Should -Be '"GroupName","GroupSource","GroupType","Members","NestedGroupMembers","Owners","CreatedDateTime","MembershipType"'
        @($groupRows | ForEach-Object { "$($_.GroupName)|$($_.Members)" }) | Should -Be @('grp-empty|(No members)', 'grp-finance|Ada Lovelace, Gus Guest, Grace Hopper, app-payroll')
        $null = & $script:capture { Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-empty' -CsvPath $csv -CsvLayout Member }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 7
        $rows[0].PSObject.Properties.Name | Should -Contain 'Via'
        $null = & $script:capture { Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-empty' -OutputPath $csv -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('groups', 'people', 'members')
        @(($model.tables | Where-Object id -EQ 'members').rows).Count | Should -Be 7
        @(($model.tables | Where-Object id -EQ 'people').rows | ForEach-Object { "$($_.MemberName)|$($_.Membership)|$($_.Through)" }) | Should -Be @('Ada Lovelace|Direct and nested|grp-finance-emea', 'app-payroll|Nested|grp-finance-emea', 'Grace Hopper|Nested|grp-finance-emea', 'Gus Guest|Direct|')
        # The tree: each group, its owners first, then its members - a nested group opening to its own.
        $fin = $model.tree.root.k | Where-Object n -EQ 'grp-finance'
        @($fin.k | ForEach-Object { "$($_.l):$($_.n)" }) | Should -Be @('O:Owners', 'U:Ada Lovelace', 'U:Gus Guest', 'N:grp-finance-emea')
        @($fin.k[0].k.n) | Should -Be @('Ada Lovelace (ada@contoso.example)', 'app-payroll (Service principal)')
        @(($fin.k | Where-Object n -EQ 'grp-finance-emea').k | ForEach-Object { "$($_.l):$($_.n)" }) | Should -Be @('U:Ada Lovelace', 'P:app-payroll', 'U:Grace Hopper')
        $fin.d | Should -Be 'Security · Cloud · Assigned · created 2024-01-15'
        $model.tree.levels.G[0] | Should -Be 'GROUP'
        ($model.tiles | Where-Object label -EQ 'guests').value | Should -Be '1'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'groups.pdf'
        $null = & $script:capture { Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
