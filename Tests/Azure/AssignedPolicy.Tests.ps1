<#
    Unit tests for Get-AACAssignedPolicy: the resource types a policy rule
    targets (Get-AACPolicyResourceType), and the command with Azure Resource
    Graph and Resource Manager faked over a made-up Contoso tenant -
    parameters with their default, assigned and effective values,
    initiatives, assignments inherited from management groups, a missing
    definition, the filters, the view and the exports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:types = {
        param($Rule, [hashtable] $Parameter = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $Rule; P = $Parameter } { param($R, $P) Get-AACPolicyResourceType -Rule $R -Parameter $P }
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
        $console.Profile.Width = 200
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - the resource types a policy targets' {
    It 'reads "field": "type" conditions, resolving parameters' {
        $rule = @{ if = @{ allOf = @(@{ field = 'type'; in = "[parameters('types')]" }, @{ field = 'location'; notIn = "[parameters('locations')]" }) }; then = @{ effect = 'deny' } }
        (& $script:types $rule @{ types = @('Microsoft.Sql/servers', 'Microsoft.Web/sites') }).Text | Should -Be 'Microsoft.Sql/servers, Microsoft.Web/sites'
    }

    It "turns a negated type condition into 'All except' - as Allowed resource types does" {
        $rule = @{ if = @{ allOf = @(@{ not = @{ field = 'type'; in = "[parameters('listOfResourceTypesAllowed')]" } }) }; then = @{ effect = 'deny' } }
        (& $script:types $rule @{ listOfResourceTypesAllowed = @('Microsoft.Storage/storageAccounts') }).Text | Should -Be 'All except Microsoft.Storage/storageAccounts'
        (& $script:types @{ if = @{ field = 'type'; notEquals = 'Microsoft.Compute/disks' } }).Text | Should -Be 'All except Microsoft.Compute/disks'
    }

    It 'takes the types of the aliases a rule reads when it names none, and ignores the then block' {
        $rule = @{ If = @{ AnyOf = @(
                        @{ Field = 'Microsoft.Compute/virtualMachines/storageProfile.osDisk.osType'; equals = 'Linux' }
                        @{ count = @{ field = 'Microsoft.Network/networkSecurityGroups/securityRules[*]'; where = @{ field = 'Microsoft.Network/networkSecurityGroups/securityRules[*].access'; equals = 'Allow' } }; greater = 0 }
                    ) }; then = @{ effect = 'deployIfNotExists'; details = @{ type = 'Microsoft.Insights/diagnosticSettings' } }
        }
        $result = & $script:types $rule
        $result.Aliased | Should -Be @('Microsoft.Compute/virtualMachines', 'Microsoft.Network/networkSecurityGroups')
        $result.Text | Should -Be 'Microsoft.Compute/virtualMachines, Microsoft.Network/networkSecurityGroups'
    }

    It "is 'All' for a rule about no type" {
        (& $script:types @{ if = @{ field = 'location'; notIn = @('uksouth') } }).Text | Should -Be 'All'
        (& $script:types $null).Text | Should -Be 'All'
    }
}

Describe 'Azure Admin Console - Get-AACAssignedPolicy' {
    BeforeAll {
        $mg = { param([string] $Name) "/providers/Microsoft.Management/managementGroups/$Name" }
        $script:subA = '11111111-1111-1111-1111-111111111111'
        $script:subB = '22222222-2222-2222-2222-222222222222'
        $chain = { param([string[]] $NearestFirst) @($NearestFirst | ForEach-Object { @{ name = $_; displayName = "MG $_" } }) }
        $script:subscriptions = @(
            @{ id = "/subscriptions/$script:subA"; subscriptionId = $script:subA; name = 'sub-apps'; chain = (& $chain 'mg-landingzones', 'mg-platform', 'tenant-root') }
            @{ id = "/subscriptions/$script:subB"; subscriptionId = $script:subB; name = 'sub-shared'; chain = (& $chain 'mg-platform', 'tenant-root') }
        )
        $script:groups = @(
            @{ id = (& $mg 'tenant-root'); name = 'tenant-root'; displayName = 'Tenant Root Group'; chain = @() }
            @{ id = (& $mg 'mg-platform'); name = 'mg-platform'; displayName = 'Platform'; chain = (& $chain 'tenant-root') }
            @{ id = (& $mg 'mg-landingzones'); name = 'mg-landingzones'; displayName = 'Landing zones'; chain = (& $chain 'mg-platform', 'tenant-root') }
        )
        $builtin = { param([string] $Name) "/providers/Microsoft.Authorization/policyDefinitions/$Name" }
        $custom = "/providers/Microsoft.Management/managementGroups/tenant-root/providers/Microsoft.Authorization/policyDefinitions/storage-tls"
        $set = "/providers/Microsoft.Management/managementGroups/tenant-root/providers/Microsoft.Authorization/policySetDefinitions/security-baseline"
        $script:definitionRows = @(
            @{ id = (& $builtin 'allowed-locations'); name = 'allowed-locations'; displayName = 'Allowed locations'; policyType = 'BuiltIn'; category = 'General'
                parameters = @{ listOfAllowedLocations = @{ type = 'Array'; metadata = @{ displayName = 'Allowed locations' } } }
                rule = @{ if = @{ field = 'location'; notIn = "[parameters('listOfAllowedLocations')]" }; then = @{ effect = 'deny' } }; members = $null }
            @{ id = $custom; name = 'storage-tls'; displayName = 'Storage accounts use TLS 1.2'; policyType = 'Custom'; category = 'Storage'
                parameters = [ordered]@{ minimumTlsVersion = @{ type = 'String'; defaultValue = 'TLS1_2'; allowedValues = @('TLS1_0', 'TLS1_1', 'TLS1_2') }; effect = @{ type = 'String'; defaultValue = 'Audit' } }
                rule = @{ if = @{ allOf = @(@{ field = 'type'; equals = 'Microsoft.Storage/storageAccounts' }, @{ field = 'Microsoft.Storage/storageAccounts/minimumTlsVersion'; notEquals = "[parameters('minimumTlsVersion')]" }) }; then = @{ effect = "[parameters('effect')]" } }; members = $null }
            @{ id = $set; name = 'security-baseline'; displayName = 'Contoso security baseline'; policyType = 'Custom'; category = 'Security'
                parameters = [ordered]@{ tlsVersion = @{ type = 'String'; defaultValue = 'TLS1_2' }; tags = @{ type = 'Object'; defaultValue = @{ owner = 'it' } } }
                rule = $null
                members = @(
                    @{ policyDefinitionId = $custom; parameters = @{ minimumTlsVersion = @{ value = "[parameters('tlsVersion')]" }; effect = @{ value = 'Deny' } } }
                    @{ policyDefinitionId = (& $builtin 'vm-os'); parameters = @{} }
                ) }
        )
        # Not in Resource Graph: read from Resource Manager.
        $script:armDefinition = @{ id = (& $builtin 'vm-os'); name = 'vm-os'; properties = @{ displayName = 'VM OS check'; policyType = 'BuiltIn'; metadata = @{ category = 'Compute' }; parameters = @{}
                policyRule = @{ if = @{ field = 'Microsoft.Compute/virtualMachines/storageProfile.osDisk.osType'; equals = 'Linux' }; then = @{ effect = 'audit' } } } }
        $script:assignmentRows = @(
            @{ id = "$(& $mg 'mg-platform')/providers/Microsoft.Authorization/policyAssignments/locations"; name = 'locations'; displayName = 'Allowed locations - UK'; scope = (& $mg 'mg-platform'); definitionId = (& $builtin 'allowed-locations')
                parameters = @{ listOfAllowedLocations = @{ value = @('uksouth', 'ukwest') } }; enforcement = 'Default'; notScopes = @(); description = '' }
            @{ id = "/subscriptions/$script:subA/providers/Microsoft.Authorization/policyAssignments/baseline"; name = 'baseline'; displayName = 'Security baseline'; scope = "/subscriptions/$script:subA"; definitionId = $set
                parameters = @{ tlsVersion = @{ value = 'TLS1_1' } }; enforcement = 'Default'; notScopes = @("/subscriptions/$script:subA/resourceGroups/rg-sandbox"); description = '' }
            @{ id = "/subscriptions/$script:subB/resourceGroups/rg-data/providers/Microsoft.Authorization/policyAssignments/tls"; name = 'tls'; displayName = ''; scope = "/subscriptions/$script:subB/resourceGroups/rg-data"; definitionId = $custom
                parameters = $null; enforcement = 'DoNotEnforce'; notScopes = $null; description = '' }
            @{ id = "$(& $mg 'mg-landingzones')/providers/Microsoft.Authorization/policyAssignments/gone"; name = 'gone'; displayName = 'Deleted definition'; scope = (& $mg 'mg-landingzones'); definitionId = (& $builtin 'deleted-one')
                parameters = @{ x = @{ value = 1 } }; enforcement = 'Default'; notScopes = @(); description = '' }
        )
    }

    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        $script:graphCalls = 0
        $script:failUri = ''
        # The fill-in for what REST couldn't read: only ever reached when something failed.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:graphCalls++
            $rows = @{}
            foreach ($name in @($Query.Keys)) {
                $text = [string]$Query[$name]['Query']
                $rows[$name] = switch -Wildcard ($name) {
                    'assignments' { @($script:assignmentRows) + @($script:graphOnlyAssignment) }
                    'subscriptions' { @($script:subscriptions) }
                    'managementGroups' { @($script:groups) }
                    'definitions*' {
                        $ids = @([regex]::Matches($text, "'(/[^']+)'") | ForEach-Object { $_.Groups[1].Value })
                        @($script:definitionRows | Where-Object { $ids -contains $_.id.ToLowerInvariant() })
                    }
                }
                if ($OnProgress) { & $OnProgress $name 1 1 }
            }
            @{ Rows = $rows; Errors = @{} }
        }
        # Azure Resource Manager, answering as its REST APIs do: the assignments
        # a scope lists follow its documented filter.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $list = { param($Items) @{ Status = 200; Body = @{ value = @($Items) }; Items = [System.Collections.Generic.List[object]]@($Items); Error = '' } }
            $asRest = {
                param($Row)
                @{ id = $Row.id; name = $Row.name; properties = @{ displayName = $Row.displayName; scope = $Row.scope; policyDefinitionId = $Row.definitionId; parameters = $Row.parameters; enforcementMode = $Row.enforcement; notScopes = $Row.notScopes; description = $Row.description } }
            }
            $out = @{}
            foreach ($u in $Uri) {
                $lower = $u.ToLowerInvariant()
                $path = ($lower -split '\?')[0]
                $out[$u] = if ($script:failUri -and $lower -like $script:failUri) { @{ Status = 403; Body = $null; Items = $null; Error = 'Forbidden.' } }
                elseif ($path -like '*/getentities') {
                    # The fixture's chains are nearest first; getEntities' are root first.
                    $rootFirst = { param($Chain) $names = @($Chain | ForEach-Object { $_.name }); [array]::Reverse($names); , $names }
                    & $list @(
                        foreach ($g in $script:groups) { @{ id = $g.id; name = $g.name; type = 'Microsoft.Management/managementGroups'; properties = @{ displayName = $g.displayName; parentNameChain = (& $rootFirst $g.chain) } } }
                        foreach ($s in $script:subscriptions) { @{ id = $s.id; name = $s.subscriptionId; type = '/subscriptions'; properties = @{ displayName = $s.name; parentNameChain = (& $rootFirst $s.chain) } } }
                    )
                }
                elseif ($path -eq '/subscriptions') { & $list @($script:subscriptions | ForEach-Object { @{ subscriptionId = $_.subscriptionId; displayName = $_.name; state = 'Enabled' } }) }
                elseif ($path -match '^/subscriptions/([^/]+)/providers/microsoft\.authorization/policyassignments$') {
                    # At the subscription, inside it, and from the management groups above it.
                    $sub = $Matches[1]
                    $above = @(@($script:subscriptions | Where-Object subscriptionId -EQ $sub).chain.name)
                    & $list @($script:assignmentRows | Where-Object { $_.scope.ToLowerInvariant().StartsWith("/subscriptions/$sub") -or ($_.scope -split '/')[-1] -in $above } | ForEach-Object { & $asRest $_ })
                }
                elseif ($path -match '/managementgroups/([^/]+)/providers/microsoft\.authorization/policyassignments$') {
                    # At the management group and its ancestors (atScope()).
                    $name = $Matches[1]
                    $self = @($script:groups | Where-Object name -EQ $name)
                    & $list @($script:assignmentRows | Where-Object { $_.scope -like '/providers/*' -and ($_.scope -split '/')[-1] -in (@($name) + @($self.chain.name)) } | ForEach-Object { & $asRest $_ })
                }
                else {
                    $row = @($script:definitionRows | Where-Object { $_.id.ToLowerInvariant() -eq $path })[0]
                    if ($path -like '*/vm-os') { @{ Status = 200; Body = $script:armDefinition; Items = $null; Error = '' } }
                    elseif ($row) { @{ Status = 200; Items = $null; Error = ''; Body = @{ id = $row.id; name = $row.name; properties = @{ displayName = $row.displayName; policyType = $row.policyType; metadata = @{ category = $row.category }; description = "What $($row.name) does"; parameters = $row.parameters; policyRule = $row.rule; policyDefinitions = $row.members } } } }
                    else { @{ Status = 404; Body = $null; Items = $null; Error = 'The policy definition was not found.' } }
                }
            }
            $out
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'lists one row per assignment and parameter, with the default, assigned and effective value' {
        $rows = @(Get-AACAssignedPolicy -NoDisplay)
        $rows[0].PSObject.TypeNames[0] | Should -Be 'AAC.AssignedPolicy'
        $locations = $rows | Where-Object AssignmentName -EQ 'locations'
        $locations.AssignedValue | Should -Be 'uksouth, ukwest'
        $locations.EffectiveValue | Should -Be 'uksouth, ukwest'
        $locations.ValueSource | Should -Be 'Assigned'
        $locations.ScopeType | Should -Be 'Management group'
        $locations.ScopeName | Should -Be 'Platform'
        $locations.DefinitionType | Should -Be 'Policy'
        $locations.PolicyType | Should -Be 'BuiltIn'
        $locations.ParameterDisplayName | Should -Be 'Allowed locations'

        $tls = @($rows | Where-Object AssignmentName -EQ 'tls')
        $tls.ParameterName | Should -Be @('effect', 'minimumTlsVersion')
        ($tls | Where-Object ParameterName -EQ 'minimumTlsVersion').ValueSource | Should -Be 'Default'
        ($tls | Where-Object ParameterName -EQ 'minimumTlsVersion').EffectiveValue | Should -Be 'TLS1_2'
        ($tls | Where-Object ParameterName -EQ 'minimumTlsVersion').AllowedValues | Should -Be 'TLS1_0, TLS1_1, TLS1_2'
        $tls[0].EnforcementMode | Should -Be 'DoNotEnforce'
        $tls[0].ScopeName | Should -Be "rg-data (sub-shared)"

        $baseline = @($rows | Where-Object AssignmentName -EQ 'baseline')
        $baseline[0].DefinitionType | Should -Be 'PolicySet'
        ($baseline | Where-Object ParameterName -EQ 'tlsVersion').EffectiveValue | Should -Be 'TLS1_1'
        ($baseline | Where-Object ParameterName -EQ 'tags').EffectiveValue | Should -Be '{"owner":"it"}' -Because 'an object is written as compact JSON'
        $baseline[0].NotScopes | Should -BeLike '*rg-sandbox'
    }

    It 'adds the resource types: per policy, and per initiative parameter from the member policies using it' {
        $rows = @(Get-AACAssignedPolicy -NoDisplay)
        ($rows | Where-Object AssignmentName -EQ 'locations').ResourceType | Should -Be 'All'
        @($rows | Where-Object AssignmentName -EQ 'tls' | ForEach-Object ResourceType | Select-Object -Unique) | Should -Be @('Microsoft.Storage/storageAccounts')
        ($rows | Where-Object { $_.AssignmentName -eq 'baseline' -and $_.ParameterName -eq 'tlsVersion' }).ResourceType | Should -Be 'Microsoft.Storage/storageAccounts'
        ($rows | Where-Object { $_.AssignmentName -eq 'baseline' -and $_.ParameterName -eq 'tags' }).ResourceType | Should -Be 'Microsoft.Compute/virtualMachines, Microsoft.Storage/storageAccounts' -Because 'a parameter no member uses gets every member''s types'
    }

    It 'reads everything from REST, without Resource Graph, when REST can read it all' {
        $rows = @(Get-AACAssignedPolicy -NoDisplay)
        @($rows.AssignmentName | Select-Object -Unique | Sort-Object) | Should -Be @('baseline', 'gone', 'locations', 'tls')
        $script:graphCalls | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -like '*/vm-os?*' }).Count -eq 1 } -Because 'each initiative''s member policies are read by ID'
    }

    It 'lists each assignment once, though several scopes return it' {
        @(Get-AACAssignedPolicy -ExpandPolicySet -NoDisplay | Where-Object AssignmentName -EQ 'locations').Count | Should -Be 1
    }

    It 'reads only the scopes that can hold what applies to the subscription asked about' {
        $null = @(Get-AACAssignedPolicy -SubscriptionId $script:subA -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -like "/subscriptions/$script:subB/*" }).Count -gt 0 } -Times 0 -Exactly
    }

    It 'fills in from Resource Graph only what REST couldn''t read, and says so' {
        $script:failUri = "/subscriptions/$script:subB/providers/*"
        $script:graphOnlyAssignment = @{ id = "/subscriptions/$script:subB/providers/Microsoft.Authorization/policyAssignments/only-in-graph"; name = 'only-in-graph'; displayName = 'Only in Graph'; scope = "/subscriptions/$script:subB"; definitionId = '/providers/Microsoft.Authorization/policyDefinitions/allowed-locations'; parameters = @{}; enforcement = 'Default'; notScopes = @(); description = '' }
        try {
            $names = @(Get-AACAssignedPolicy -NoDisplay | ForEach-Object AssignmentName | Select-Object -Unique)
            $names | Should -Contain 'only-in-graph'
            $names | Should -Contain 'tls' -Because 'its subscription failed in REST and Resource Graph has it'
            $script:graphCalls | Should -BeGreaterThan 0
            $text = (& $script:capture { Get-AACAssignedPolicy -NoPaging }).Text
            $text | Should -Match 'Resource Graph filled'
        }
        finally { $script:graphOnlyAssignment = $null }
    }

    It 'stops with Resource Graph''s error when neither source can read anything' {
        $script:failUri = '*'
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { throw 'Azure Admin Console could not query Resource Graph.' }
        { Get-AACAssignedPolicy -NoDisplay } | Should -Throw '*could not query Resource Graph*'
    }

    It 'lists what is assigned per resource type: a row per type and policy, and one heading for the policies naming none' {
        $result = InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $script:assignmentRows; R = $script:definitionRows; V = $script:armDefinition } {
            param($A, $R, $V)
            $definitions = @{}
            foreach ($row in $R) { $definitions[$row.id.ToLowerInvariant()] = @{ Id = $row.id; Name = $row.name; Kind = $(if ($row.id -match 'policySetDefinitions') { 'PolicySet' } else { 'Policy' }); DisplayName = $row.displayName; PolicyType = $row.policyType; Category = $row.category; Description = ''; Parameters = $row.parameters; Rule = $row.rule; Members = @($row.members) } }
            $definitions[$V.id.ToLowerInvariant()] = @{ Id = $V.id; Name = $V.name; Kind = 'Policy'; DisplayName = $V.properties.displayName; PolicyType = 'BuiltIn'; Category = 'Compute'; Description = ''; Parameters = $V.properties.parameters; Rule = $V.properties.policyRule; Members = @() }
            ConvertTo-AACAssignedPolicy -Assignment $A -Definition $definitions
        }
        $storage = $result.ResourceTypeSummaries | Where-Object ResourceType -EQ 'Microsoft.Storage/storageAccounts'
        "$($storage.Coverage) $($storage.Assignments) $($storage.Policies) $($storage.Blocks) $($storage.ReportsOnly) $($storage.Audits)" | Should -Be 'Named 2 2 1 0 1' -Because 'the baseline fixes Deny; the tls assignment is Audit by default, and an audit still audits when not enforced'
        $result.ResourceTypeRows[0].PSObject.TypeNames | Should -Contain 'AAC.PolicyResourceTypeAssignment'
        (@($result.ResourceTypeRows | Where-Object { $_.AssignmentDisplayName -eq 'Allowed locations - UK' }).ResourceType) | Should -Be '(all resource types)'
        $result.ResourceTypeSummaries[-1].Coverage | Should -Not -Be 'Named' -Because 'the types a policy names come first'
        @($result.ResourceTypeRows | Where-Object PolicyDisplayName -EQ '(definition not found)').Count | Should -Be 0 -Because 'a missing definition''s types aren''t known'
    }

    It 'reports a deny on an assignment that isn''t enforced as Reports only' {
        $result = InModuleScope 'Azure.Admin.Console' {
            $id = '/providers/Microsoft.Authorization/policyDefinitions/deny-sql'
            $definitions = @{ $id = @{ Id = $id; Name = 'deny-sql'; Kind = 'Policy'; DisplayName = 'Deny SQL'; PolicyType = 'Custom'; Category = ''; Description = ''; Parameters = @{}; Members = @(); Rule = @{ if = @{ field = 'type'; equals = 'Microsoft.Sql/servers' }; then = @{ effect = 'deny' } } } }
            ConvertTo-AACAssignedPolicy -Assignment @(@{ id = '/subscriptions/s/providers/Microsoft.Authorization/policyAssignments/x'; name = 'x'; displayName = 'x'; scope = '/subscriptions/s'; definitionId = $id; parameters = @{}; enforcement = 'DoNotEnforce' }) -Definition $definitions
        }
        $result.ResourceTypeRows[0].Impact | Should -Be 'Reports only'
        $result.ResourceTypeSummaries[0].ReportsOnly | Should -Be 1
    }

    It 'writes one tabbed report as HTML and PDF, with the resource types and what each definition does' {
        $html = Join-Path $TestDrive 'tabbed.html'
        $pdf = Join-Path $TestDrive 'tabbed.pdf'
        $canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
        $null = & $script:capture { Get-AACAssignedPolicy -HtmlPath $html -PdfPath $(if ($canWritePdf) { $pdf }) }
        # -AsHashtable: an effect's tones hold 'Deny' and 'deny', which plain ConvertFrom-Json refuses.
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json -AsHashtable
        @($model.tabs | ForEach-Object { $_.name }) | Should -Be @('Assignments', 'Policies in force', 'Resource types', 'Parameters')
        $model.overviewTab | Should -Be 'Summary'
        @($model.tables | ForEach-Object { $_.id }) | Should -Be @('assignments', 'policies', 'resourcetypes', 'typepolicies', 'parameters')
        $tabNames = @($model.tabs | ForEach-Object { $_.name })
        @($model.tables | Where-Object { $_.section -in $tabNames }).Count | Should -Be 5 -Because 'every table belongs to a tab'
        @(@($model.tables | Where-Object { $_.id -eq 'resourcetypes' })[0].rows | ForEach-Object { $_.ResourceType }) | Should -Contain 'Microsoft.Storage/storageAccounts'
        @(@($model.tables | Where-Object { $_.id -eq 'assignments' })[0].rows | ForEach-Object { $_.DefinitionDescription }) | Should -Contain 'What security-baseline does'
        @($model.facts | Where-Object { $_.k -eq 'Read from' })[0].v | Should -Be 'Azure Resource Manager REST APIs'
        if ($canWritePdf) { (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000 }
    }

    It "shows 'All' for an initiative parameter that a policy for every type uses" {
        $result = InModuleScope 'Azure.Admin.Console' {
            $all = '/providers/Microsoft.Authorization/policyDefinitions/allowed-locations'
            $groups = '/providers/Microsoft.Authorization/policyDefinitions/allowed-locations-rg'
            $set = '/providers/Microsoft.Authorization/policySetDefinitions/baseline'
            $parameter = @{ listOfAllowedLocations = @{ type = 'Array' } }
            $definitions = @{
                $all    = @{ Id = $all; Name = 'a'; Kind = 'Policy'; DisplayName = 'Allowed locations'; PolicyType = 'BuiltIn'; Category = ''; Parameters = $parameter; Members = @()
                    Rule = @{ if = @{ allOf = @(@{ field = 'location'; notIn = "[parameters('listOfAllowedLocations')]" }, @{ field = 'type'; notEquals = 'Microsoft.AzureActiveDirectory/b2cDirectories' }) } } }
                $groups = @{ Id = $groups; Name = 'b'; Kind = 'Policy'; DisplayName = 'Allowed locations for resource groups'; PolicyType = 'BuiltIn'; Category = ''; Parameters = $parameter; Members = @()
                    Rule = @{ if = @{ allOf = @(@{ field = 'type'; equals = 'Microsoft.Resources/subscriptions/resourceGroups' }, @{ field = 'location'; notIn = "[parameters('listOfAllowedLocations')]" }) } } }
                $set    = @{ Id = $set; Name = 'baseline'; Kind = 'PolicySet'; DisplayName = 'Baseline'; PolicyType = 'Custom'; Category = ''; Rule = $null
                    Parameters = @{ locations = @{ type = 'Array'; defaultValue = @('uksouth') }; groupsOnly = @{ type = 'Array'; defaultValue = @('uksouth') } }
                    Members = @(
                        @{ policyDefinitionId = $all; parameters = @{ listOfAllowedLocations = @{ value = "[parameters('locations')]" } } }
                        @{ policyDefinitionId = $groups; parameters = @{ listOfAllowedLocations = @{ value = "[parameters('locations')]" } } }
                        @{ policyDefinitionId = $groups; parameters = @{ listOfAllowedLocations = @{ value = "[parameters('groupsOnly')]" } } }
                    ) }
            }
            ConvertTo-AACAssignedPolicy -Assignment @(@{ id = '/subscriptions/s/providers/Microsoft.Authorization/policyAssignments/x'; name = 'x'; displayName = 'x'; scope = '/subscriptions/s'; definitionId = $set; parameters = @{} }) -Definition $definitions
        }
        ($result.Rows | Where-Object ParameterName -EQ 'locations').ResourceType | Should -Be 'All' -Because 'Allowed locations applies to every type, not only resource groups'
        ($result.Rows | Where-Object ParameterName -EQ 'groupsOnly').ResourceType | Should -Be 'Microsoft.Resources/subscriptions/resourceGroups'
        $result.Assignments[0].ResourceType | Should -Be 'All'
    }

    It 'opens up the initiatives with -ExpandPolicySet: each member policy, its effect and every parameter''s value' {
        $rows = @(Get-AACAssignedPolicy -ExpandPolicySet -NoDisplay)
        $rows[0].PSObject.TypeNames[0] | Should -Be 'AAC.AssignedPolicyMember'
        $baseline = @($rows | Where-Object AssignmentName -EQ 'baseline')
        @($baseline.PolicyDisplayName | Select-Object -Unique | Sort-Object) | Should -Be @('Storage accounts use TLS 1.2', 'VM OS check')
        $tls = $baseline | Where-Object ParameterName -EQ 'minimumTlsVersion'
        "$($tls.EffectiveValue) $($tls.ValueSource) $($tls.InitiativeParameter) $($tls.InitiativeValue) $($tls.DefaultValue)" | Should -Be "TLS1_1 Assigned tlsVersion [parameters('tlsVersion')] TLS1_2"
        $tls.PolicySetDisplayName | Should -Be 'Contoso security baseline'
        $tls.ResourceType | Should -Be 'Microsoft.Storage/storageAccounts'
        $effect = $baseline | Where-Object { $_.PolicyName -eq 'storage-tls' -and $_.ParameterName -eq 'effect' }
        "$($effect.EffectiveValue) $($effect.ValueSource) $($effect.Effect) $($effect.EffectSource)" | Should -Be 'Deny Initiative Deny Initiative' -Because 'the initiative fixes the effect'
        $vm = @($baseline | Where-Object PolicyName -EQ 'vm-os')
        $vm.Count | Should -Be 1 -Because 'a member with no parameters is one row'
        "$($vm[0].Effect) $($vm[0].EffectSource) $($vm[0].ResourceType)" | Should -Be 'audit Policy Microsoft.Compute/virtualMachines'

        $single = @($rows | Where-Object AssignmentName -EQ 'tls')
        ($single | Where-Object ParameterName -EQ 'effect').ValueSource | Should -Be 'Policy default'
        $single[0].Effect | Should -Be 'Audit'
        $single[0].PolicySetName | Should -Be '' -Because 'a policy assigned on its own is in no initiative'
        ($rows | Where-Object AssignmentName -EQ 'locations').ValueSource | Should -Be 'Assigned'
        ($rows | Where-Object AssignmentName -EQ 'gone').PolicyDisplayName | Should -Be '(definition not found)'
    }

    It 'resolves a member''s parameters through the initiative, and the assignment''s effect overrides' {
        $members = InModuleScope 'Azure.Admin.Console' {
            $policy = '/providers/Microsoft.Authorization/policyDefinitions/p'
            $definitions = @{ $policy = @{ parameters = @{ effect = @{ type = 'String'; defaultValue = 'Audit' }; sku = @{ type = 'String' }; tier = @{ type = 'String'; defaultValue = 'Basic' }; zone = @{ type = 'String' } }; rule = @{ then = @{ effect = "[parameters('effect')]" } } } }
            $member = @(
                @{ policyDefinitionId = $policy; policyDefinitionReferenceId = 'one'; parameters = @{ sku = @{ value = "[parameters('skuName')]" }; zone = @{ value = "[concat('a', 'b')]" } } }
                @{ policyDefinitionId = $policy; policyDefinitionReferenceId = 'two'; parameters = @{ effect = @{ value = "[parameters('effect')]" }; sku = @{ value = 'Standard' } } }
            )
            $override = @(@{ kind = 'policyEffect'; value = 'Disabled'; selectors = @(@{ kind = 'policyDefinitionReferenceId'; in = @('two') }) })
            Resolve-AACPolicySetMember -Member $member -SetParameter @{ skuName = @{ defaultValue = 'Premium' }; effect = @{ defaultValue = 'Deny' } } -Assigned @{} -Override $override -Definition $definitions
        }
        $one = $members | Where-Object ReferenceId -EQ 'one'
        $source = { param($M, $Name) $p = $M.Parameters | Where-Object Name -EQ $Name; "$($p.Value)|$($p.Source)" }
        & $source $one 'sku' | Should -Be 'Premium|Initiative default'
        & $source $one 'zone' | Should -Be "[concat('a', 'b')]|Expression"
        & $source $one 'tier' | Should -Be 'Basic|Policy default'
        "$($one.Effect) $($one.EffectSource)" | Should -Be 'Audit Policy default'
        $two = $members | Where-Object ReferenceId -EQ 'two'
        & $source $two 'sku' | Should -Be 'Standard|Initiative'
        & $source $two 'tier' | Should -Be 'Basic|Policy default'
        "$($two.Effect) $($two.EffectSource)" | Should -Be 'Disabled Override' -Because 'the override selects reference two'
    }

    It 'lists each initiative''s member policies in the view with -ExpandPolicySet' {
        $text = (& $script:capture { Get-AACAssignedPolicy -NoPaging }).Text
        $text | Should -Match '2 member policies \(-ExpandPolicySet lists them\)'
        $text = (& $script:capture { Get-AACAssignedPolicy -ExpandPolicySet -NoPaging }).Text
        $text | Should -Match 'Storage accounts use TLS 1.2 Deny'
        $text | Should -Match 'minimumTlsVersion\s+TLS1_1 assigned'
        $text | Should -Match 'VM OS check audit'
    }

    It 'lists an assignment whose definition is gone, and says so' {
        $text = (& $script:capture { Get-AACAssignedPolicy -AssignmentName 'gone' -NoPaging }).Text
        $text | Should -Match "couldn't be read"
        $gone = @(Get-AACAssignedPolicy -AssignmentName 'gone' -NoDisplay)
        $gone.Count | Should -Be 1
        $gone[0].DefinitionDisplayName | Should -Be '(definition not found)'
        $gone[0].ParameterName | Should -Be 'x' -Because 'its assigned parameters are still listed'
        $gone[0].AssignedValue | Should -Be '1'
    }

    It 'lists what applies to a subscription, inherited assignments marked' {
        $rows = @(Get-AACAssignedPolicy -SubscriptionId $script:subA -NoDisplay)
        @($rows.AssignmentName | Select-Object -Unique | Sort-Object) | Should -Be @('baseline', 'gone', 'locations')
        ($rows | Where-Object AssignmentName -EQ 'locations').Inherited | Should -BeTrue
        @($rows | Where-Object AssignmentName -EQ 'baseline')[0].Inherited | Should -BeFalse
    }

    It 'lists what applies to a management group: at it, above it and below it' {
        $names = @(Get-AACAssignedPolicy -ManagementGroupId 'mg-landingzones' -NoDisplay | ForEach-Object AssignmentName | Select-Object -Unique | Sort-Object)
        $names | Should -Be @('baseline', 'gone', 'locations') -Because 'sub-shared (and its rg-data assignment) is not under mg-landingzones'
        @(Get-AACAssignedPolicy -ManagementGroupId 'mg-platform' -NoDisplay | ForEach-Object AssignmentName | Select-Object -Unique).Count | Should -Be 4
    }

    It 'filters by assignment name or display name, with wildcards' {
        @(Get-AACAssignedPolicy -AssignmentName '*baseline*' -NoDisplay | ForEach-Object AssignmentName | Select-Object -Unique) | Should -Be @('baseline')
        @(Get-AACAssignedPolicy -AssignmentName 'Allowed locations*' -NoDisplay | ForEach-Object AssignmentName | Select-Object -Unique) | Should -Be @('locations')
    }

    It 'shows tiles, the assignments, the resource types and each assignment''s parameters' {
        $text = (& $script:capture { Get-AACAssignedPolicy -NoPaging }).Text
        $text | Should -Match 'Policy assignments'
        $text | Should -Match 'Security baseline'
        $text | Should -Match 'Not enforced'
        $text | Should -Match 'inherited|Management group'
        $text | Should -Match 'Storage/storageAccounts'
        $text | Should -Match 'minimumTlsVersion\s+TLS1_2'
        $text | Should -Match 'uksouth, ukwest'
    }

    It 'writes every row to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'assigned.csv'
        $html = Join-Path $TestDrive 'assigned.html'
        $null = & $script:capture { Get-AACAssignedPolicy -CsvPath $csv -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 6 -Because 'locations 1, baseline 2, tls 2, gone 1'
        $rows[0].PSObject.Properties.Name | Should -Contain 'ResourceType'
        $rows[0].PSObject.Properties.Name | Should -Contain 'EffectiveValue'
        Get-Content -LiteralPath $html -Raw | Should -Match 'Contoso security baseline'
        Get-Content -LiteralPath $html -Raw | Should -Match 'Policies in force'

        $members = Join-Path $TestDrive 'members.csv'
        $null = & $script:capture { Get-AACAssignedPolicy -ExpandPolicySet -CsvPath $members }
        $rows = @(Import-Csv -LiteralPath $members)
        $rows.Count | Should -Be 7 -Because 'locations 1, baseline 3 (storage-tls 2, vm-os 1), tls 2, gone 1'
        $rows[0].PSObject.Properties.Name | Should -Contain 'InitiativeValue'
    }
}
