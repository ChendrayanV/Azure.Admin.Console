<#
    Unit tests for New-AACServiceBlueprint: the names against Azure's rules, the
    policies and guardrails with Get-AACAssignedPolicy and checkPolicyRestrictions
    faked over a made-up Contoso tenant (Fixtures\ContosoBlueprint.ps1), PSRule
    faked and once for real, the view and the draw.io, HTML and PDF files.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
    $script:hasPSRule = [bool](Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable)
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoBlueprint.ps1')
    $script:f = Get-AACContosoBlueprint
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
    $script:name = {
        param([string] $Pattern, [hashtable] $Rule, [string] $Workload = 'orders', [string] $Abbreviation = 'func')
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $Pattern; R = $Rule; W = $Workload; A = $Abbreviation } {
            param($P, $R, $W, $A)
            ConvertTo-AACServiceBlueprintName -Pattern $P -Abbreviation $A -Workload $W -Environment 'prod' -Region 'westeurope' -Instance '01' -Rule $R
        }
    }
}

Describe 'Azure Admin Console - a blueprint''s names' {
    BeforeAll {
        $script:site = @{ Min = 2; Max = 60; Pattern = '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; Strip = $false; Text = 'letters' }
        $script:storage = @{ Min = 3; Max = 24; Pattern = '^[a-z0-9]+$'; Strip = $true; Text = '3-24 lowercase letters and numbers' }
    }

    It 'fills in the convention, in lower case, with a short region' {
        $result = & $script:name '{type}-{workload}-{env}-{region}-{instance}' $script:site 'Orders'
        $result.Name | Should -Be 'func-orders-prod-weu-01'
        $result.Problem | Should -BeNullOrEmpty
        $result.Adjusted | Should -BeFalse
    }

    It 'takes the hyphens out of a name that can''t have them, and says so' {
        $result = & $script:name '{type}-{workload}-{env}-{region}-{instance}' $script:storage 'orders' 'st'
        $result.Name | Should -Be 'stordersprodweu01'
        $result.Adjusted | Should -BeTrue
        $result.Problem | Should -BeNullOrEmpty
    }

    It 'reports a name that is too long instead of shortening it' {
        $result = & $script:name '{type}-{workload}-{env}-{region}-{instance}' $script:storage 'averyverylongworkloadname' 'st'
        $result.Name | Should -Be 'staveryverylongworkloadnameprodweu01' -Because 'shortening could collide with another name'
        $result.Problem | Should -BeLike '*Azure needs 3-24 lowercase letters and numbers*'
    }

    It 'stops at a token it doesn''t know' {
        { & $script:name '{type}-{team}' $script:site } | Should -Throw '*doesn''t know the token {team}*'
    }
}

Describe 'Azure Admin Console - New-AACServiceBlueprint' {
    BeforeEach {
        $script:checks = [System.Collections.Generic.List[object]]::new()
        $script:engineInput = $null
        $script:engineFails = $false
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAssignedPolicy -MockWith { $script:f.Rows }
        # checkPolicyRestrictions: public access to storage is denied, an Event Hubs namespace is audited, the region is limited.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            $request = ConvertFrom-Json -InputObject $Body -AsHashtable -Depth 50
            $script:checks.Add(@{ Uri = $Uri; Request = $request })
            $content = $request.resourceDetails.resourceContent
            $info = { param([string] $Name) @{ policyAssignmentId = "$($script:f.Group)/providers/Microsoft.Authorization/policyAssignments/$Name"; policyDefinitionId = "/providers/Microsoft.Authorization/policyDefinitions/$Name" } }
            $evaluations = @(
                if ($content.type -eq 'Microsoft.Storage/storageAccounts' -and $content.properties.publicNetworkAccess -eq 'Enabled') { @{ policyInfo = (& $info 'storage-public'); evaluationResult = 'NonCompliant'; effectDetails = @{ policyEffect = 'Deny' }; evaluationDetails = @{ reason = 'Public access'; evaluatedExpressions = @() } } }
                if ($content.type -eq 'Microsoft.EventHub/namespaces') { @{ policyInfo = (& $info 'hub-audit'); evaluationResult = 'NonCompliant'; effectDetails = @{ policyEffect = 'Audit' }; evaluationDetails = @{ reason = 'Needs a private link'; evaluatedExpressions = @() } } }
            )
            @{
                contentEvaluationResult = @{ policyEvaluations = $evaluations }
                fieldRestrictions       = @(if ($request.pendingFields) { @{ field = 'location'; restrictions = @(@{ policy = (& $info 'locations'); result = 'Required'; values = @('westeurope', 'northeurope'); policyEffect = 'Deny' }) } })
            }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -MockWith {
            if ($script:engineFails) { throw 'PSRule for Azure is not installed.' }
            $script:engineInput = $InputObject
            @{ Results = @(foreach ($item in $InputObject) {
                        [pscustomobject]@{ Outcome = 'Pass'; RuleName = 'Azure.Fake.Pass'; ResourceName = $item.name; Title = 'Passes'; Severity = 'Important'; Reason = ''; Recommendation = ''; Link = '' }
                        if ($item.type -eq 'Microsoft.Web/sites') { [pscustomobject]@{ Outcome = 'Fail'; RuleName = 'Azure.Fake.Critical'; ResourceName = $item.name; Title = 'A critical rule'; Severity = 'Critical'; Reason = 'Not set'; Recommendation = 'Set it'; Link = 'https://contoso.example/rule' } }
                    }) }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { @{ $Uri[0] = @{ Status = 200; Items = $script:f.Services } } }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) }; $script:AACServiceCatalog = $null }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null; $script:AACServiceCatalog = $null } }

    It 'plans each service''s resources, with its secure configuration, and takes a service as you''d type it' {
        $rows = @(New-AACServiceBlueprint -Service 'Function App', 'storage-account', EventHub, eventgrid -Workload orders -Environment prod -NoDisplay)
        @($rows.Name) | Should -Be @('asp-orders-prod-weu-01', 'func-orders-prod-weu-01', 'stordersprodweu01', 'evhns-orders-prod-weu-01', 'evgt-orders-prod-weu-01')
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.ServiceBlueprintComponent'
        $bodies = @{}
        foreach ($item in $script:engineInput) { $bodies[$item.type] = $item }
        $bodies['Microsoft.Storage/storageAccounts'].properties.publicNetworkAccess | Should -Be 'Disabled'
        $bodies['Microsoft.Storage/storageAccounts'].properties.allowSharedKeyAccess | Should -BeFalse
        @($bodies['Microsoft.Storage/storageAccounts'].resources)[0].type | Should -Be 'Microsoft.Storage/storageAccounts/blobServices'
        $bodies['Microsoft.EventHub/namespaces'].properties.disableLocalAuth | Should -BeTrue
        $bodies['Microsoft.EventGrid/topics'].properties.minimumTlsVersionAllowed | Should -Be '1.2'
        $bodies['Microsoft.Web/sites'].properties.serverFarmId | Should -BeLike '*/providers/Microsoft.Web/serverfarms/asp-orders-prod-weu-01' -Because 'the app runs on the plan the blueprint names'
    }

    It 'refuses a service it can''t plan, and two scopes' {
        { New-AACServiceBlueprint -Service 'Cosmos DB' -NoDisplay } | Should -Throw '*doesn''t know the service ''Cosmos DB''*Press Tab*'
        { New-AACServiceBlueprint -Service EventHub -SubscriptionId $script:f.Subscription -ManagementGroupId 'mg' -NoDisplay } | Should -Throw '*not both*'
        { New-AACServiceBlueprint -Service EventHub -OutputFormat Html -NoDisplay } | Should -Throw '*needs -Path*'
    }

    It 'reads Azure''s list once a session, only when a template doesn''t answer the name, without classic types' {
        $null = @(New-AACServiceBlueprint -Service FunctionApp, EventHub -SkipPSRule -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmParallel -Times 0 -Exactly
        $null = @(New-AACServiceBlueprint -Service 'Virtual Network' -SkipPSRule -NoDisplay)
        $null = @(New-AACServiceBlueprint -Service 'Contoso Widgets' -SkipPSRule -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmParallel -Times 1 -Exactly -ParameterFilter { $Uri[0] -eq '/providers/Microsoft.Support/services?api-version=2024-04-01' }
        $network = InModuleScope 'Azure.Admin.Console' { Get-AACServiceCatalog | Where-Object { $_.Name -eq 'Virtual Network' } }
        @($network.ResourceTypes) | Should -Be @('MICROSOFT.NETWORK/VIRTUALNETWORKS')
    }

    It 'plans a service without a template as its types: no body, no verdict, no PSRule, never ready' {
        $rows = @(New-AACServiceBlueprint -Service 'Virtual Network', EventHub -SubscriptionId $script:f.Subscription -Workload orders -NoDisplay)
        $network = $rows | Where-Object ResourceType -EQ 'Microsoft.Network/virtualNetworks'
        $network.Planned | Should -BeFalse
        $network.Status | Should -Be 'Not fully checked' -Because 'nothing was asked about it, so it can''t be ready'
        $network.PolicyChecked | Should -BeFalse
        $network.PSRuleChecked | Should -BeFalse
        $network.Name | Should -Be 'virtualnetwork-orders-dev-weu-01'
        $network.BaselineAlerts | Should -BeGreaterThan 0 -Because 'AMBA covers it, spelled in its own case'
        @($script:checks | Where-Object { $_.Request.resourceDetails.resourceContent.type -like '*virtualNetworks' }).Count | Should -Be 0
        @($script:engineInput.type) | Should -Be @('Microsoft.EventHub/namespaces')
        ($rows | Where-Object Id -EQ 'eventhub').PSRuleChecked | Should -BeTrue
    }

    It 'doesn''t run PSRule at all when nothing has a body, and says what wasn''t checked' {
        $result = & $script:capture { New-AACServiceBlueprint -Service 'Contoso Widgets' -NoPaging -PassThru }
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACPSRuleEngine -Times 0 -Exactly
        $result.Output[0].ResourceType | Should -Be 'MICROSOFT.CONTOSO/WIDGETS' -Because 'neither AMBA nor APRL has it, so Azure''s spelling stays'
        $result.Output[0].BaselineAlerts | Should -Be 0
        $result.Text | Should -Match 'No secure configuration is planned'
    }

    It 'uses a template when Azure''s service has its type, but not for a web app sharing a Function App''s' {
        @(New-AACServiceBlueprint -Service 'Blob Storage' -SkipPSRule -NoDisplay).Id | Should -Be 'storage'
        @(New-AACServiceBlueprint -Service 'Function App' -SkipPSRule -NoDisplay).Id | Should -Be @('plan', 'functionapp')
        $web = @(New-AACServiceBlueprint -Service 'Web App (Linux)' -SkipPSRule -NoDisplay)
        $web.Count | Should -Be 1
        $web[0].Planned | Should -BeFalse
    }

    It 'takes a resource type or part of a name, and plans a type once' {
        @(New-AACServiceBlueprint -Service 'microsoft.network/virtualnetworks' -SkipPSRule -NoDisplay).ResourceType | Should -Be 'Microsoft.Network/virtualNetworks'
        @(New-AACServiceBlueprint -Service 'widgets' -SkipPSRule -NoDisplay).ResourceType | Should -Be 'MICROSOFT.CONTOSO/WIDGETS'
        @(New-AACServiceBlueprint -Service 'Virtual Machine running Linux', 'Virtual Machine running Windows' -SkipPSRule -NoDisplay).Count | Should -Be 1 -Because 'they are the same resource type'
    }

    It 'says when a name fits several services, or one with nothing to deploy' {
        { New-AACServiceBlueprint -Service 'Virtual Machine' -NoDisplay } | Should -Throw '*found 2 services*running Linux*running Windows*'
        { New-AACServiceBlueprint -Service 'Billing' -NoDisplay } | Should -Throw '*can''t plan ''Billing''*no resource type*'
    }

    It 'says what to do when the list can''t be read' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { @{ $Uri[0] = @{ Status = 403; Error = 'Forbidden.' } } }
        { New-AACServiceBlueprint -Service 'Virtual Network' -NoDisplay } | Should -Throw '*couldn''t read Azure''s list of services: Forbidden.*'
    }

    It 'without a sign-in: the templates still work, and any other name says to sign in' {
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null }
        @(New-AACServiceBlueprint -Service StorageAccount -SkipPSRule -NoDisplay).Id | Should -Be 'storage'
        { New-AACServiceBlueprint -Service 'Virtual Network' -NoDisplay } | Should -Throw '*Run Connect-AAC to read it*'
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmParallel -Times 0 -Exactly
    }

    It 'tab completes Azure''s names, quoted, and never asks for a sign-in' {
        $complete = { param([string] $Line) @((TabExpansion2 -inputScript $Line -cursorColumn $Line.Length).CompletionMatches.CompletionText) }
        $signedIn = & $complete 'New-AACServiceBlueprint -Service virt'
        $signedIn | Should -Contain '''Virtual Network'''
        $signedIn | Should -Not -Contain 'Billing'
        & $complete 'New-AACServiceBlueprint -Service bill' | Should -BeNullOrEmpty -Because 'it has no resource type to plan'
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null; $script:AACServiceCatalog = $null }
        & $complete 'New-AACServiceBlueprint -Service ""' | Should -Contain '''Event Hubs'''
        & $complete 'New-AACServiceBlueprint -Service virt' | Should -BeNullOrEmpty
    }

    It 'adds each type''s AMBA alerts, for its kind, and APRL recommendations, without changing a status' {
        $rows = @(New-AACServiceBlueprint -Service FunctionApp, EventHub -SubscriptionId $script:f.Subscription -Workload orders -NoDisplay)
        $site = $rows | Where-Object Id -EQ 'functionapp'
        $forFunctions = InModuleScope 'Azure.Admin.Console' { (Get-AACServiceBaseline -Set Alerts -ResourceType 'Microsoft.Web/sites' -Kind 'functionapp,linux').Rows.Count }
        $everyKind = InModuleScope 'Azure.Admin.Console' { (Get-AACServiceBaseline -Set Alerts -ResourceType 'Microsoft.Web/sites').Rows.Count }
        $site.BaselineAlerts | Should -Be $forFunctions
        $forFunctions | Should -BeLessThan $everyKind -Because 'some of AMBA''s alerts for sites are for web apps only'
        $site.ResiliencyTotal | Should -BeGreaterThan 0
        ($rows | Where-Object Id -EQ 'plan').Status | Should -Be 'Ready' -Because 'alerts and recommendations are suggestions, not findings'
    }

    It 'needs no sign-in without a scope, and never calls an unchecked resource ready' {
        $rows = @(New-AACServiceBlueprint -Service EventHub -Workload orders -NoDisplay)
        $rows[0].Status | Should -Be 'Not fully checked' -Because 'policy wasn''t read, so it can''t be ready'
        $rows[0].PolicyChecked | Should -BeFalse
        Should -Invoke -ModuleName 'Azure.Admin.Console' Get-AACAccessToken -Times 0 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' Get-AACAssignedPolicy -Times 0 -Exactly
    }

    It 'in a subscription: asks Azure about each planned body, and about it open to the internet' {
        $null = @(New-AACServiceBlueprint -Service StorageAccount -SubscriptionId $script:f.Subscription -Workload orders -NoDisplay)
        $script:checks.Count | Should -Be 2
        $script:checks[0].Uri | Should -BeLike "$($script:f.Scope)/providers/Microsoft.PolicyInsights/checkPolicyRestrictions*"
        $script:checks[0].Request.resourceDetails.resourceContent.properties.publicNetworkAccess | Should -Be 'Disabled'
        $script:checks[0].Request.resourceDetails.resourceContent.location | Should -Be 'westeurope'
        $script:checks[1].Request.resourceDetails.resourceContent.properties.publicNetworkAccess | Should -Be 'Enabled'
        $script:checks[1].Request.resourceDetails.resourceContent.properties.networkAcls.defaultAction | Should -Be 'Allow'
    }

    It 'reads the guardrails: Azure''s answer on public access, and a type a policy refuses' {
        $policy = InModuleScope 'Azure.Admin.Console' -Parameters @{ S = $script:f.Subscription } {
            param($S)
            $catalog = Get-AACServiceTemplate
            $items = @(foreach ($key in 'StorageAccount', 'EventGrid') {
                    $part = $catalog[$key].Components[0]
                    @{ Id = $part.Id; Name = "x$($part.Id)"; Type = $part.Type; ApiVersion = $part.ApiVersion; Public = $part.Public; Resource = (& $part.Body @{}) }
                })
            Invoke-AACProgress -ScriptBlock { Read-AACServiceBlueprintPolicy -Component $items -SubscriptionId $S -Region 'westeurope' }
        }
        $guard = { param([string] $Name, [string] $Applies) @($policy.Guardrails | Where-Object { $_.Guardrail -eq $Name -and $_.AppliesTo -eq $Applies })[0] }
        (& $guard 'Allowed region' 'westeurope').Outcome | Should -Be 'Allowed'
        (& $guard 'Allowed region' 'westeurope').Detail | Should -Be 'Allowed: westeurope, northeurope'
        (& $guard 'Allowed region' 'westeurope').Source | Should -Be 'Azure Policy (checked)'
        (& $guard 'Public network access' 'Microsoft.Storage/storageAccounts').Outcome | Should -Be 'Refused'
        (& $guard 'Public network access' 'Microsoft.Storage/storageAccounts').Assignment | Should -Be 'storage-public'
        (& $guard 'Public network access' 'Microsoft.EventGrid/topics').Outcome | Should -Be 'Not refused'
        (& $guard 'Allowed resource type' 'Microsoft.EventGrid/topics').Outcome | Should -Be 'Blocks'
        (& $guard 'Allowed resource type' 'Microsoft.Storage/storageAccounts').Outcome | Should -Be 'Allowed'
    }

    It 'counts only the policies that reach a new resource here, for the type' {
        $policy = InModuleScope 'Azure.Admin.Console' -Parameters @{ S = $script:f.Subscription } {
            param($S)
            $catalog = Get-AACServiceTemplate
            $part = $catalog['StorageAccount'].Components[0]
            $items = @(@{ Id = $part.Id; Name = 'x'; Type = $part.Type; ApiVersion = $part.ApiVersion; Public = $part.Public; Resource = (& $part.Body @{}) })
            Invoke-AACProgress -ScriptBlock { Read-AACServiceBlueprintPolicy -Component $items -SubscriptionId $S -Region 'westeurope' }
        }
        @($policy.Policies.Policy | Sort-Object) | Should -Be @('Allowed locations', 'Not allowed resource types', 'Storage accounts should disable public network access') -Because 'not the disabled, excluded or below-the-scope ones, nor the Event Hubs one'
        ($policy.Policies | Where-Object Policy -Like 'Storage*').Impact | Should -Be 'Blocks'
    }

    It 'blocks a type or region policy refuses, an invalid name, and rates PSRule by severity' {
        $rows = @(New-AACServiceBlueprint -Service FunctionApp, EventGrid, EventHub -SubscriptionId $script:f.Subscription -Workload orders -NoDisplay)
        ($rows | Where-Object Id -EQ 'eventgrid').Status | Should -Be 'Blocked' -Because 'an assignment doesn''t allow the type'
        ($rows | Where-Object Id -EQ 'functionapp').Status | Should -Be 'Needs attention' -Because 'PSRule''s critical rule is high'
        ($rows | Where-Object Id -EQ 'functionapp').PSRuleFailed | Should -Be 1
        ($rows | Where-Object Id -EQ 'eventhub').Audits | Should -Be 1
        ($rows | Where-Object Id -EQ 'plan').Status | Should -Be 'Ready' -Because 'it was checked, and nothing was found'

        @(New-AACServiceBlueprint -Service FunctionApp, StorageAccount -SubscriptionId $script:f.Subscription -Region 'eastus' -NoDisplay).Status | Sort-Object -Unique | Should -Contain 'Ready' -Because 'a blocked region is reported for the whole blueprint below'
        $blocked = @(New-AACServiceBlueprint -Service StorageAccount -Workload 'averyverylongworkloadname' -NoDisplay)
        $blocked[0].Status | Should -Be 'Blocked'
        $blocked[0].NameProblem | Should -BeLike '*Azure needs*'
    }

    It 'reports a region outside the allowed ones, and that a Function App has no storage' {
        $text = (& $script:capture { New-AACServiceBlueprint -Service FunctionApp -SubscriptionId $script:f.Subscription -Region 'eastus' -NoPaging }).Text
        $text | Should -Match 'Allowed region'
        $text | Should -Match 'Blocks'
        $text | Should -Match 'needs a storage account at run time'
    }

    It 'under a management group: what is assigned, and no verdicts it can''t have' {
        $rows = @(New-AACServiceBlueprint -Service StorageAccount -ManagementGroupId 'mg-contoso' -NoDisplay)
        $script:checks.Count | Should -Be 0 -Because 'checkPolicyRestrictions works on a subscription'
        $rows[0].PoliciesAssigned | Should -BeGreaterThan 0
        $rows[0].PolicyChecked | Should -BeFalse
        $rows[0].Status | Should -Be 'Not fully checked'
        $policy = InModuleScope 'Azure.Admin.Console' {
            $part = (Get-AACServiceTemplate)['StorageAccount'].Components[0]
            Read-AACServiceBlueprintPolicy -Component @(@{ Id = $part.Id; Name = 'x'; Type = $part.Type; ApiVersion = $part.ApiVersion; Public = $part.Public; Resource = (& $part.Body @{}) }) -ManagementGroupId 'mg-contoso' -Region 'westeurope'
        }
        $public = @($policy.Guardrails | Where-Object Guardrail -EQ 'Public network access')[0]
        "$($public.Outcome) $($public.Source)" | Should -Be 'Probably refused Policy names' -Because 'it is a guess from a name, and says so'
    }

    It 'says when a verdict or PSRule couldn''t be had, and doesn''t call it ready' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith { throw 'Forbidden.' }
        $script:engineFails = $true
        $result = & $script:capture { New-AACServiceBlueprint -Service EventGrid -SubscriptionId $script:f.Subscription -NoPaging -PassThru }
        $result.Output[0].PolicyChecked | Should -BeFalse
        $result.Output[0].PSRuleChecked | Should -BeFalse
        $result.Text | Should -Match "couldn't be asked about"
        $result.Text | Should -Match "PSRule for Azure couldn't run"
    }

    It 'leaves out the module''s own naming rule: the convention decides the names' {
        $null = @(New-AACServiceBlueprint -Service EventHub -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACPSRuleEngine -ParameterFilter { $ExcludeRule -contains 'AAC.Resource.Naming' }
    }

    It 'shows the view at the prompt, in the order that matters' {
        $text = (& $script:capture { New-AACServiceBlueprint -Service FunctionApp, EventHub -SubscriptionId $script:f.Subscription -Workload orders -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Service blueprint', 'func-orders-dev-weu-01', 'Needs attention', 'Azure.Fake.Critical', 'Guardrails', 'Allowed region') { $text | Should -Match ([regex]::Escape($expected)) }
    }

    It 'writes nothing with -WhatIf' {
        $folder = Join-Path $TestDrive 'whatif'
        $null = & $script:capture { New-AACServiceBlueprint -Service EventHub -OutputFormat DrawIo, Html -Path $folder -WhatIf }
        Test-Path -LiteralPath $folder | Should -BeFalse
    }

    It 'writes an editable draw.io file: valid XML, unique IDs, a legend, nothing linked to the portal' {
        $folder = Join-Path $TestDrive 'drawio'
        $null = & $script:capture { New-AACServiceBlueprint -Service FunctionApp, StorageAccount -SubscriptionId $script:f.Subscription -Workload orders -Environment prod -Path $folder }
        $file = Join-Path $folder 'orders-prod-blueprint.drawio'
        [xml]$xml = Get-Content -LiteralPath $file -Raw
        @($xml.mxfile.diagram.name)[-1] | Should -Be 'Legend'
        foreach ($page in $xml.mxfile.diagram) {
            $ids = @($page.SelectNodes('.//*[@id]') | ForEach-Object { $_.GetAttribute('id') })
            @($ids | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0 -Because "draw.io needs unique IDs on '$($page.name)'"
        }
        $raw = Get-Content -LiteralPath $file -Raw
        $raw | Should -Match 'func-orders-prod-weu-01'
        $raw | Should -Match 'Needs attention'
        $raw | Should -Match 'runs on'
        $raw | Should -Match 'runtime state'
        $raw | Should -Match 'Planned, not deployed'
        $raw | Should -Match 'AMBA alerts'
        $raw | Should -Match 'Azure Proactive Resiliency Library'
        $raw | Should -Not -Match 'portal\.azure\.com' -Because 'nothing here exists yet'
    }

    It 'won''t overwrite a diagram that may hold your edits, without -Force' {
        $folder = Join-Path $TestDrive 'overwrite'
        $null = & $script:capture { New-AACServiceBlueprint -Service EventHub -Path $folder }
        { New-AACServiceBlueprint -Service EventHub -Path $folder -NoDisplay } | Should -Throw '*won''t overwrite*'
        { $null = & $script:capture { New-AACServiceBlueprint -Service EventHub -Path $folder -Force } } | Should -Not -Throw
    }

    It 'writes the diagram page and the tabbed report as HTML, and opens the diagram page with -Show' {
        $folder = Join-Path $TestDrive 'html'
        $null = & $script:capture { New-AACServiceBlueprint -Service FunctionApp, StorageAccount -SubscriptionId $script:f.Subscription -Workload orders -Environment prod -OutputFormat Html -Path $folder -Show }
        Test-Path -LiteralPath (Join-Path $folder 'orders-prod-blueprint.drawio') | Should -BeFalse -Because 'only what was asked for'
        Get-Content -LiteralPath (Join-Path $folder 'orders-prod-blueprint.html') -Raw | Should -Match 'func-orders-prod-weu-01'
        $model = [regex]::Match((Get-Content -LiteralPath (Join-Path $folder 'orders-prod-blueprint-report.html') -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json -AsHashtable
        @($model.tabs | ForEach-Object { $_.name }) | Should -Be @('Resources', 'Findings', 'Guardrails', 'Policies', 'Alerts', 'Resiliency')
        @($model.tables | ForEach-Object { $_.id }) | Should -Be @('components', 'findings', 'guardrails', 'policies', 'alerts', 'resiliency')
        @(($model.tables | Where-Object { $_.id -eq 'alerts' }).rows).Count | Should -BeGreaterThan 0
        @(($model.tables | Where-Object { $_.id -eq 'resiliency' }).rows | ForEach-Object { $_.Component } | Select-Object -Unique) | Should -Contain 'stordersprodweu01'
        Should -Invoke -ModuleName 'Azure.Admin.Console' Open-AACFile -Exactly -Times 1 -ParameterFilter { $Path -like '*orders-prod-blueprint.html' }
    }

    It 'writes the diagram and the report as PDF' -Skip:(-not $script:canWritePdf) {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Write-AACResourceMapPdf -MockWith { [System.IO.File]::WriteAllText($Path, '%PDF') }
        $folder = Join-Path $TestDrive 'pdf'
        $null = & $script:capture { New-AACServiceBlueprint -Service EventHub -Workload orders -Environment prod -OutputFormat Pdf -Path $folder }
        Should -Invoke -ModuleName 'Azure.Admin.Console' Write-AACResourceMapPdf -Exactly -Times 1
        (Get-Item -LiteralPath (Join-Path $folder 'orders-prod-blueprint-report.pdf')).Length | Should -BeGreaterThan 1000
    }
}

Describe 'Azure Admin Console - a blueprint''s bodies against the real PSRule for Azure rules' -Skip:(-not $script:hasPSRule) {
    It 'evaluates every planned resource without a rule erroring, and storage passes its soft delete rules' {
        $rows = @(New-AACServiceBlueprint -Service FunctionApp, StorageAccount, EventHub, EventGrid -Workload orders -Environment prod -Tag @{ CostCenter = 'cc-123' } -NoDisplay 3>$null)
        @($rows | Where-Object { $_.PSRulePassed -eq 0 }).Count | Should -Be 0 -Because 'each body is the shape PSRule reads'
        $results = InModuleScope 'Azure.Admin.Console' {
            $part = (Get-AACServiceTemplate)['StorageAccount'].Components[0]
            $body = & $part.Body @{}
            $child = Merge-AACObject -Base $part.Children[0] -Overlay ([ordered]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stcontoso/blobServices/default' })
            $object = [ordered]@{ id = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stcontoso'; name = 'stcontoso'; type = $part.Type; apiVersion = $part.ApiVersion; location = 'westeurope'; resourceGroupName = 'rg'; subscriptionId = '00000000-0000-0000-0000-000000000000'; resources = @($child) }
            foreach ($key in $body.Keys) { $object[$key] = $body[$key] }
            (Invoke-AACProgress -ScriptBlock { Invoke-AACPSRuleEngine -InputObject @($object) -ExcludeRule 'AAC.Resource.Naming' }).Results
        }
        @($results | Where-Object Outcome -EQ 'Error').RuleName | Should -BeNullOrEmpty
        @($results | Where-Object { $_.RuleName -like 'Azure.Storage.*SoftDelete' -and $_.Outcome -ne 'Pass' }).RuleName | Should -BeNullOrEmpty
    }
}
