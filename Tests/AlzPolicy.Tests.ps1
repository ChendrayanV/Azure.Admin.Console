<#
    Unit tests for Test-AACAlzPolicy: a tiny Azure Landing Zones Library
    written to the test drive (an architecture of four management groups,
    three archetypes, five assignments) compared with made-up deployed
    assignments - missing, different definition, not enforced, renamed,
    present, a management group mapped and one not found - and the command
    with Resource Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    # The library: platform\alz with architecture, archetype and assignment files.
    $script:library = Join-Path $TestDrive 'alz-library'
    $alz = Join-Path $script:library 'platform/alz'
    foreach ($folder in 'architecture_definitions', 'archetype_definitions', 'policy_assignments') { $null = New-Item -ItemType Directory -Path (Join-Path $alz $folder) -Force }
    $json = { param([string] $Path, $Object) [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 10)) }
    & $json (Join-Path $alz 'alz_library_metadata.json') @{ name = 'ALZ'; display_name = 'Azure Landing Zones'; path = 'platform/alz' }
    & $json (Join-Path $alz 'architecture_definitions/alz.alz_architecture_definition.json') @{ name = 'alz'; management_groups = @(
            @{ id = 'alz'; display_name = 'Azure Landing Zones'; parent_id = $null; archetypes = @('root') }
            @{ id = 'landingzones'; display_name = 'Landing zones'; parent_id = 'alz'; archetypes = @('landing_zones') }
            @{ id = 'corp'; display_name = 'Corp'; parent_id = 'landingzones'; archetypes = @('corp') }
            @{ id = 'sandbox'; display_name = 'Sandbox'; parent_id = 'alz'; archetypes = @('corp') }
        ) }
    & $json (Join-Path $alz 'archetype_definitions/root.alz_archetype_definition.json') @{ name = 'root'; policy_assignments = @('Deploy-ASC-Monitoring', 'Deny-Classic-Resources') }
    & $json (Join-Path $alz 'archetype_definitions/landing_zones.alz_archetype_definition.json') @{ name = 'landing_zones'; policy_assignments = @('Deny-IP-forwarding', 'Enable-DDoS-VNET') }
    & $json (Join-Path $alz 'archetype_definitions/corp.alz_archetype_definition.json') @{ name = 'corp'; policy_assignments = @('Deny-Public-Endpoints') }
    $assignment = { param([string] $Name, [string] $Definition, [string] $Display, [string] $Mode = 'Default') & $json (Join-Path $alz "policy_assignments/$Name.alz_policy_assignment.json") @{ type = 'Microsoft.Authorization/policyAssignments'; name = $Name; properties = @{ displayName = $Display; policyDefinitionId = "/providers/Microsoft.Authorization/policySetDefinitions/$Definition"; enforcementMode = $Mode } } }
    & $assignment 'Deploy-ASC-Monitoring' 'asc-monitoring-v2' 'Microsoft Cloud Security Benchmark'
    & $assignment 'Deny-Classic-Resources' 'deny-classic' 'Deny classic resources'
    & $assignment 'Deny-IP-forwarding' 'deny-ipfwd' 'Network interfaces should disable IP forwarding'
    & $assignment 'Enable-DDoS-VNET' 'ddos-vnet' 'Virtual networks should be protected by DDoS'
    & $assignment 'Deny-Public-Endpoints' 'deny-public-endpoints' 'Public network access should be disabled'

    $mg = { param([string] $Name) "/providers/microsoft.management/managementgroups/$Name" }
    $deployed = { param([string] $Group, [string] $Name, [string] $Definition, [string] $Mode = 'Default') @{ id = "$(& $mg $Group)/providers/microsoft.authorization/policyassignments/$Name"; name = $Name; displayName = $Name; scope = (& $mg $Group); definitionId = "/providers/microsoft.authorization/policysetdefinitions/$Definition"; enforcement = $Mode } }
    $script:groups = @(@{ name = 'contoso' }, @{ name = 'landingzones' }, @{ name = 'corp' })
    $script:assignments = @(
        (& $deployed 'contoso' 'Deploy-ASC-Monitoring' 'asc-monitoring-v1')
        (& $deployed 'contoso' 'Deny-Classic-Resources' 'deny-classic')
        (& $deployed 'landingzones' 'Deny-IP-forwarding' 'deny-ipfwd' 'DoNotEnforce')
        (& $deployed 'corp' 'my-public-endpoints' 'deny-public-endpoints')
    )
}

Describe 'Azure Admin Console - Azure Landing Zones policy check' {
    BeforeAll {
        $script:r = InModuleScope 'Azure.Admin.Console' -Parameters @{ L = $script:library; A = $script:assignments; G = @($script:groups | ForEach-Object { $_.name }) } {
            param($L, $A, $G)
            ConvertTo-AACAlzPolicy -Library (Read-AACAlzLibrary -Path $L) -Assignment $A -ManagementGroup $G -Map @{ alz = 'contoso' }
        }
    }

    It 'reads the library from the repository root or its platform folder, and says how to get it' {
        InModuleScope 'Azure.Admin.Console' -Parameters @{ L = $script:library } { param($L) (Read-AACAlzLibrary -Path (Join-Path $L 'platform/alz')).Assignments.Count } | Should -Be 5
        { InModuleScope 'Azure.Admin.Console' -Parameters @{ L = $TestDrive } { param($L) Read-AACAlzLibrary -Path $L } } | Should -Throw '*found no Azure Landing Zones Library*'
        { InModuleScope 'Azure.Admin.Console' -Parameters @{ L = $script:library } { param($L) Read-AACAlzLibrary -Path $L -Architecture 'slz' } } | Should -Throw "*no architecture 'slz'*It has: alz*"
    }

    It 'compares each management group with its archetypes' {
        @($script:r.Checks | ForEach-Object { "$($_.Status) | $($_.ManagementGroup) | $($_.Assignment)" }) | Should -Be @(
            'Missing | landingzones | Enable-DDoS-VNET'
            'Different | contoso | Deploy-ASC-Monitoring'
            'Different | landingzones | Deny-IP-forwarding'
            'Not found | sandbox | '
            'Present | contoso | Deny-Classic-Resources'
            'Present | corp | Deny-Public-Endpoints'
        )
        $script:r.Checks[0].PSObject.TypeNames | Should -Contain 'AAC.AlzPolicyCheck'
    }

    It 'says what differs, and where to deploy the missing ones from' {
        ($script:r.Checks | Where-Object Status -EQ 'Missing').Finding | Should -BeLike '*Enable-DDoS-VNET.alz_policy_assignment.json in the library*'
        ($script:r.Checks | Where-Object Assignment -EQ 'Deploy-ASC-Monitoring').Finding | Should -BeLike "Present, but assigned with definition 'asc-monitoring-v1', the library uses 'asc-monitoring-v2'*"
        ($script:r.Checks | Where-Object Assignment -EQ 'Deny-IP-forwarding').Finding | Should -BeLike '*not enforced (DoNotEnforce)*'
        ($script:r.Checks | Where-Object Assignment -EQ 'Deny-Public-Endpoints').Finding | Should -Be "Present, assigned as 'my-public-endpoints'."
        ($script:r.Checks | Where-Object Status -EQ 'Not found').Finding | Should -BeLike "No management group 'sandbox'*-ManagementGroupMap*"
        "$($script:r.Stats.Expected) $($script:r.Stats.Missing) $($script:r.Stats.Coverage)" | Should -Be '5 1 80'
    }
}

Describe 'Azure Admin Console - Test-AACAlzPolicy' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ groups = $script:groups; assignments = $script:assignments }; Errors = @{} } }
    }

    It 'maps the reference''s management groups to yours, and filters by status' {
        @(Test-AACAlzPolicy -LibraryPath $script:library -ManagementGroupMap @{ alz = 'contoso' } -NoDisplay).Count | Should -Be 6
        @(Test-AACAlzPolicy -LibraryPath $script:library -ManagementGroupMap @{ alz = 'contoso' } -Status Missing -NoDisplay).Assignment | Should -Be 'Enable-DDoS-VNET'
        @(Test-AACAlzPolicy -LibraryPath $script:library -Status NotFound -NoDisplay).ManagementGroup | Should -Be @('alz', 'sandbox')
    }
}
