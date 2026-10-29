<#
    Unit tests for Show-AACEffectivePolicy and Test-AACPolicyDeployment,
    with Azure Resource Graph, Resource Manager and Policy Insights faked
    over a made-up Contoso tenant (Fixtures/ContosoEffectivePolicy.ps1):
    what applies to a resource and why, exemptions, notScopes, resource
    selectors, data-plane policies, overrides, enforcement, compliance and
    its reasons, a planned resource, a template - and the template
    expander (Get-AACTemplateResource) on its own.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoEffectivePolicy.ps1')
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
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:expand = {
        param([hashtable] $Template, [hashtable] $Parameter = @{}, [string] $Group = 'rg-x', [string] $Location = 'uksouth')
        InModuleScope 'Azure.Admin.Console' -Parameters @{ T = $Template; P = $Parameter; G = $Group; L = $Location } {
            param($T, $P, $G, $L)
            Get-AACTemplateResource -Template $T -Parameter $P -SubscriptionId '22222222-2222-2222-2222-222222222222' -ResourceGroupName $G -Location $L
        }
    }
}

Describe 'Azure Admin Console - effective Azure Policy' {
    BeforeEach {
        $script:tenant = Get-AACContosoEffectivePolicy
        $script:checks = [System.Collections.Generic.List[object]]::new()
        # checkPolicyRestrictions: Allowed locations - UK refuses anything else.
        $script:check = {
            param([string] $Uri, $Request)
            $content = $Request.resourceDetails.resourceContent
            $policy = @{ policyAssignmentId = $script:tenant.Ids.Locations; policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/allowed-locations' }
            $evaluations = @()
            if ($content.Contains('location') -and $content.location -notin 'uksouth', 'ukwest', 'global') {
                $evaluations += @{ evaluationResult = 'NonCompliant'; policyInfo = $policy; effectDetails = @{ policyEffect = 'Deny' }
                    evaluationDetails = @{ evaluatedExpressions = @(@{ path = 'location'; operator = 'NotIn'; targetValue = @('uksouth', 'ukwest'); expressionValue = $content.location; result = 'True' }) }
                }
            }
            @{ contentEvaluationResult = @{ policyEvaluations = $evaluations }
                fieldRestrictions = @(@{ field = 'location'; restrictions = @(@{ result = 'Required'; values = @('uksouth', 'ukwest'); policyEffect = 'Deny'; policy = $policy }) })
            }
        }
        $script:groups = @{ 'rg-orders' = 'uksouth' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($name in @($Query.Keys)) {
                $text = [string]$Query[$name]['Query']
                $quoted = @([regex]::Matches($text, "'(/[^']+)'") | ForEach-Object { $_.Groups[1].Value })
                $rows[$name] = switch -Wildcard ($name) {
                    'assignments' { @($script:tenant.Assignments) }
                    'subscriptions' { @($script:tenant.Subscriptions) }
                    'managementGroups' { @($script:tenant.ManagementGroups) }
                    'definitions*' { @($script:tenant.Definitions | Where-Object { $quoted -contains $_.id.ToLowerInvariant() }) }
                    'exemptions' { @($script:tenant.Exemptions) }
                    'resources-*' { @($script:tenant.Resources | Where-Object { $quoted -contains $_.id.ToLowerInvariant() }) }
                    'containers-*' { @() }
                    'resources' { @($script:tenant.Resources | Where-Object { $text -notmatch "resourceGroup in~" -or $text -match "'$($_.resourceGroup)'" }) }
                    'states-*' { @($script:tenant.States | Where-Object { $quoted -contains $_.resourceId }) }
                }
                if ($OnProgress) { & $OnProgress $name 1 1 }
            }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $id = ($u -split '/providers/Microsoft.PolicyInsights/')[0].ToLowerInvariant()
                $out[$u] = if ($u -match 'queryResults' -and $script:tenant.Reasons.Contains($id)) { @{ Status = 200; Body = @{}; Items = @($script:tenant.Reasons[$id]); Error = '' } }
                elseif ($u -match 'queryResults') { @{ Status = 200; Body = @{}; Items = @(); Error = '' } }
                else { @{ Status = 404; Body = $null; Items = $null; Error = 'Not found.' } }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            if ($Method -eq 'Post' -and $Uri -match 'checkPolicyRestrictions') {
                $request = ConvertFrom-Json -InputObject $Body -AsHashtable
                $script:checks.Add(@{ Uri = $Uri; Request = $request })
                if ($script:missingGroup -and $Uri -match "/resourceGroups/$($script:missingGroup)/") { $e = [System.Exception]::new("Resource group '$($script:missingGroup)' could not be found."); $e.Data['StatusCode'] = 404; throw $e }
                return (& $script:check $Uri $request)
            }
            if ($Uri -match '/resourceGroups/([^/?]+)\?') {
                if ($script:groups.Contains($Matches[1])) { return @{ name = $Matches[1]; location = $script:groups[$Matches[1]] } }
                $e = [System.Exception]::new('ResourceGroupNotFound'); $e.Data['StatusCode'] = 404; throw $e
            }
            throw "Unexpected request: $Method $Uri"
        }
        $script:missingGroup = ''
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }

    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    Describe 'Azure Admin Console - Show-AACEffectivePolicy, an existing resource' {
        It 'lists what applies to a key vault, where it is assigned, its compliance and why' {
            $rows = @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -NoDisplay)
            $rows[0].PSObject.TypeNames[0] | Should -Be 'AAC.EffectivePolicy'
            $locations = $rows | Where-Object Assignment -EQ 'Allowed locations - UK'
            $locations.Applicability | Should -Be 'Applies'
            $locations.Impact | Should -Be 'Blocks'
            $locations.State | Should -Be 'NonCompliant'
            $locations.AssignedAt | Should -Be 'Management group: Landing zones' -Because 'inherited from the management group above the subscription'
            $locations.Detail | Should -Be "location NotIn [""uksouth"",""ukwest""] (is 'westeurope')" -Because 'Policy Insights says which field, what was expected and what was found - and the type check is left out'
            $locations.Message | Should -Be 'Deploy to UK South or UK West only.'
            $locations.Version | Should -Be '1.*.*'

            $diagnostics = $rows | Where-Object Policy -EQ 'Deploy Key Vault diagnostics'
            $diagnostics.Impact | Should -Be 'Deploys'
            $diagnostics.Initiative | Should -Be 'Contoso baseline'
            $diagnostics.Identity | Should -Be 'None'
            $diagnostics.Controls | Should -Be 'Azure_Security_Benchmark_v3.0_LT-3'
            ($rows | Where-Object Assignment -EQ 'EU vault RBAC').Applicability | Should -Be 'Applies' -Because 'the vault is in westeurope, which the resource selector selects'
            @($rows | Where-Object Policy -EQ 'Storage accounts use TLS 1.2').Count | Should -Be 0 -Because 'a storage policy doesn''t target a vault, and those are left out by default'
        }

        It 'turns a non-compliant deny and a remediation that cannot run into high findings' {
            $findings = @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -View Finding -NoDisplay)
            $findings[0].PSObject.TypeNames[0] | Should -Be 'AAC.EffectivePolicyFinding'
            @($findings | Where-Object Severity -EQ 'High' | ForEach-Object Policy) | Should -Be @('Allowed locations', 'Deploy Key Vault diagnostics')
            ($findings | Where-Object Policy -EQ 'Allowed locations').Finding | Should -Match 'next deployment .* refused'
            ($findings | Where-Object Policy -EQ 'Deploy Key Vault diagnostics').Finding | Should -Match 'no managed identity'
        }

        It 'shows exemptions, notScopes and resource selectors for a storage account - with the reasons' {
            $rows = @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Storage -NoDisplay)
            $tls = $rows | Where-Object { $_.Policy -eq 'Storage accounts use TLS 1.2' -and $_.Assignment -eq 'Contoso baseline' }
            $tls.Applicability | Should -Be 'Exempt'
            $tls.Impact | Should -Be 'Exempt'
            $tls.Exemption | Should -Be 'Legacy client needs TLS 1.0 (Waiver)'
            $tls.Effect | Should -Be 'Deny' -Because 'the initiative passes its default, Deny, to the member'
            $tls.Message | Should -Be 'Storage must use TLS 1.2.' -Because 'the message for that member, not the assignment''s default'
            ($rows | Where-Object Assignment -EQ 'Storage TLS audit').Applicability | Should -Be 'Excluded'
            ($rows | Where-Object Assignment -EQ 'Storage TLS audit').Reason | Should -Match 'notScopes \(rg-data\)'
            ($rows | Where-Object Assignment -EQ 'EU vault RBAC').Applicability | Should -Be 'Not selected'
            ($rows | Where-Object Assignment -EQ 'Require CostCenter').Impact | Should -Be 'Reports only' -Because 'a deny assigned with DoNotEnforce only reports'

            $exemptions = @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Storage -View Exemption -NoDisplay)
            $exemptions.Status | Should -Be 'Ending soon'
            $exemptions.Policies | Should -Be 'storagetls'
            @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Storage -View Finding -NoDisplay | Where-Object Finding -Match "Exemption 'Legacy client").Severity | Should -Be 'Medium'
        }

        It 'notes an expired exemption without applying it' {
            $rows = @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -NoDisplay)
            $cost = $rows | Where-Object Assignment -EQ 'Require CostCenter'
            $cost.Applicability | Should -Be 'Applies'
            $cost.Exemption | Should -Be 'Tagged by the pipeline (Mitigated, expired)'
            (@(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -View Exemption -NoDisplay)).Status | Should -Be 'Expired'
        }

        It 'applies a Kubernetes data-plane policy to the cluster only, and lists what doesn''t target a resource with -IncludeNotApplicable' {
            (@(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Aks -NoDisplay) | Where-Object Policy -Match 'Kubernetes').State | Should -Be 'Compliant'
            $rows = @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Storage -IncludeNotApplicable -NoDisplay)
            ($rows | Where-Object Policy -Match 'Kubernetes').Applicability | Should -Be 'Not targeted'
            $vm = $rows | Where-Object Policy -EQ 'VM OS check'
            $vm.Applicability | Should -Be 'Not targeted'
            $vm.Reason | Should -Match 'only properties of Microsoft.Compute/virtualMachines'
            $vm.Effect | Should -Be 'Disabled'
            $vm.EffectSource | Should -Be 'Override' -Because 'the assignment overrides that member''s effect'
        }

        It 'filters by -Impact and returns the chain root first' {
            @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -Impact Blocks -NoDisplay | ForEach-Object Impact | Select-Object -Unique) | Should -Be @('Blocks')
            $chain = @(Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -View Assignment -NoDisplay)
            $chain[0].Level | Should -Be 'Management group'
            $chain[0].Scope | Should -Be 'Tenant Root Group'
            $chain[-1].Level | Should -Be 'Subscription'
        }

        It 'takes resources from the pipeline, or every resource in a subscription' {
            $piped = @([pscustomobject]@{ ResourceId = $script:tenant.Ids.Vault }, [pscustomobject]@{ Id = $script:tenant.Ids.Aks } | Show-AACEffectivePolicy -View Resource -NoDisplay)
            @($piped | ForEach-Object Resource | Sort-Object) | Should -Be @('aks-orders', 'kv-app')
            $all = @(Show-AACEffectivePolicy -SubscriptionId $script:tenant.SubscriptionId -View Resource -NoDisplay)
            $all.Count | Should -Be 3
            ($all | Where-Object Resource -EQ 'kv-app').State | Should -Be 'NonCompliant'
            ($all | Where-Object Resource -EQ 'kv-app').Blocks | Should -Be 1
        }

        It 'shows the view with the policies in force, and writes an HTML report' {
            $html = Join-Path -Path $TestDrive -ChildPath 'effective.html'
            $result = & $script:capture { Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -NoPaging }
            $result.Text | Should -Match 'Effective Azure Policy'
            $result.Text | Should -Match 'Allowed locations'
            $result.Text | Should -Match 'no managed identity'
            $null = Show-AACEffectivePolicy -ResourceId $script:tenant.Ids.Vault -HtmlPath $html -NoDisplay
            Test-Path -LiteralPath $html | Should -BeTrue
            Get-Content -LiteralPath $html -Raw | Should -Match 'Assignment chain'
        }

        It 'says what to do when a resource ID is not one' {
            { Show-AACEffectivePolicy -ResourceId 'not-an-id' -NoDisplay -WarningAction SilentlyContinue } | Should -Throw '*no resource ID*'
        }
    }

    Describe 'Azure Admin Console - Show-AACEffectivePolicy, a planned resource' {
        It 'asks Azure Policy what it would do, and lists the allowed values' {
            $rows = @(Show-AACEffectivePolicy -Scope "/subscriptions/$($script:tenant.SubscriptionId)/resourceGroups/rg-orders" -ResourceType 'Microsoft.Storage/storageAccounts' -Location 'westus' -Sku 'Standard_LRS' -Tag @{ CostCenter = 'cc-9' } -NoDisplay)
            $locations = $rows | Where-Object Assignment -EQ 'Allowed locations - UK'
            $locations.State | Should -Be 'Would fail'
            $locations.Detail | Should -Match "location NotIn .* \(is 'westus'\)"
            ($rows | Where-Object { $_.Policy -eq 'Storage accounts use TLS 1.2' -and $_.Assignment -eq 'Contoso baseline' }).State | Should -Be 'Passes'
            $sent = $script:checks[0].Request
            $sent.resourceDetails.resourceContent.sku.name | Should -Be 'Standard_LRS'
            $sent.resourceDetails.resourceContent.tags.CostCenter | Should -Be 'cc-9'
            $sent.includeAuditEffect | Should -BeTrue
            @($sent.pendingFields.field) | Should -Contain 'location'

            $allowed = @(Show-AACEffectivePolicy -Scope "/subscriptions/$($script:tenant.SubscriptionId)/resourceGroups/rg-orders" -ResourceType 'Microsoft.Storage/storageAccounts' -Location 'westus' -View Restriction -NoDisplay)
            $allowed[0].PSObject.TypeNames[0] | Should -Be 'AAC.EffectivePolicyRestriction'
            $allowed.Rule | Should -Be 'Must be one of'
            $allowed.Values | Should -Be 'uksouth, ukwest'
            $finding = @(Show-AACEffectivePolicy -Scope "/subscriptions/$($script:tenant.SubscriptionId)/resourceGroups/rg-orders" -ResourceType 'Microsoft.Storage/storageAccounts' -Location 'westus' -View Finding -NoDisplay) | Where-Object Severity -EQ 'High'
            $finding.Finding | Should -Be 'Azure Policy would refuse the deployment'
            $finding.Recommendation | Should -Match 'location must be one of: uksouth, ukwest'
        }

        It 'lists a deployIfNotExists as acting after the deployment, and asks at the subscription when the group is new' {
            $script:missingGroup = 'rg-new'
            $result = & $script:capture { Show-AACEffectivePolicy -Scope "/subscriptions/$($script:tenant.SubscriptionId)/resourceGroups/rg-new" -ResourceType 'Microsoft.KeyVault/vaults' -Location 'uksouth' -PassThru -NoPaging }
            ($result.Output | Where-Object Policy -EQ 'Deploy Key Vault diagnostics').State | Should -Be 'After deployment'
            $script:checks[-1].Uri | Should -Match "^/subscriptions/$($script:tenant.SubscriptionId)/providers/Microsoft.PolicyInsights/checkPolicyRestrictions"
            $result.Text | Should -Match "doesn't exist yet"
        }
    }

    Describe 'Azure Admin Console - the template expander' {
        It 'works out parameters, variables, format, concat and resource group functions, and leaves out what is only known at deployment' {
            $template = @{
                parameters = @{ env = @{ type = 'string' }; location = @{ type = 'string'; defaultValue = '[resourceGroup().location]' } }
                variables  = @{ store = "[format('st{0}{1}', parameters('env'), uniqueString(resourceGroup().id))]"; vault = "[toLower(concat('KV-', parameters('env')))]" }
                resources  = @(
                    @{ type = 'Microsoft.Storage/storageAccounts'; apiVersion = '2023-05-01'; name = "[variables('store')]"; location = "[parameters('location')]"; sku = @{ name = 'Standard_LRS' }; zones = @('1')
                        properties = @{ allowBlobPublicAccess = "[equals(parameters('env'), 'dev')]"; minimumTlsVersion = 'TLS1_2' }
                        resources = @(@{ type = 'blobServices'; apiVersion = '2023-05-01'; name = 'default'; properties = @{} }) }
                    @{ type = 'Microsoft.KeyVault/vaults'; apiVersion = '2023-07-01'; name = "[variables('vault')]"; location = "[parameters('location')]"; properties = @{ tenantId = '[subscription().tenantId]'; enableRbacAuthorization = $true } }
                )
            }
            $result = & $script:expand $template @{ env = 'Dev' }
            $store = $result.Resources | Where-Object Type -EQ 'Microsoft.Storage/storageAccounts'
            $store.Name | Should -Be 'unresolved-name'
            $store.Unresolved | Should -Be @('name')
            $store.Content.Contains('name') | Should -BeFalse -Because 'a naming policy would judge the placeholder'
            $store.Content.location | Should -Be 'uksouth'
            $store.Content.properties.allowBlobPublicAccess | Should -BeFalse
            , $store.Content.zones | Should -BeOfType [object[]] -Because 'a one-item list stays a list'
            $child = $result.Resources | Where-Object Type -EQ 'Microsoft.Storage/storageAccounts/blobServices'
            $child.Name | Should -Be 'unresolved-name/default'
            $child.ParentId | Should -BeLike '*/providers/Microsoft.Storage/storageAccounts/unresolved-name'
            $child.Content.name | Should -Be 'default'
            $vault = $result.Resources | Where-Object Type -EQ 'Microsoft.KeyVault/vaults'
            $vault.Name | Should -Be 'kv-dev'
            $vault.Id | Should -Be '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-x/providers/Microsoft.KeyVault/vaults/kv-dev'
            $vault.Unresolved | Should -Be @('properties.tenantId')
            $vault.Content.properties.Contains('tenantId') | Should -BeFalse
        }

        It 'follows modules, skips existing resources and false conditions, checks a copy loop once, and names a parameter with no value' {
            $template = @{
                parameters = @{ count = @{ type = 'int'; defaultValue = 3 }; deployCache = @{ type = 'bool'; defaultValue = $false }; secretName = @{ type = 'string' } }
                resources  = [ordered]@{
                    nics  = @{ type = 'Microsoft.Network/networkInterfaces'; apiVersion = '2023-09-01'; name = "[format('nic-{0}', copyIndex(1))]"; location = 'uksouth'; copy = @{ name = 'nics'; count = "[parameters('count')]" } }
                    cache = @{ type = 'Microsoft.Cache/redis'; apiVersion = '2023-08-01'; name = 'redis-1'; condition = "[parameters('deployCache')]" }
                    old   = @{ type = 'Microsoft.KeyVault/vaults'; apiVersion = '2023-07-01'; name = 'kv-old'; existing = $true }
                    app   = @{ type = 'Microsoft.Resources/deployments'; apiVersion = '2022-09-01'; name = 'app'; resourceGroup = 'rg-app'
                        properties = @{ expressionEvaluationOptions = @{ scope = 'inner' }; parameters = @{ siteName = @{ value = "[concat('app-', 'orders')]" } }
                            template = @{ parameters = @{ siteName = @{ type = 'string' } }; resources = @(@{ type = 'Microsoft.Web/sites'; apiVersion = '2023-01-01'; name = "[parameters('siteName')]"; location = 'ukwest'; tags = @{ owner = 'apps' } }) } } }
                    link  = @{ type = 'Microsoft.Resources/deployments'; apiVersion = '2022-09-01'; name = 'linked'; properties = @{ templateLink = @{ uri = 'https://example.org/t.json' } } }
                }
            }
            $result = & $script:expand $template
            @($result.Resources | ForEach-Object Name) | Should -Be @('nic-1', 'app-orders')
            ($result.Resources | Where-Object Name -EQ 'nic-1').Copy | Should -BeTrue
            $site = $result.Resources | Where-Object Name -EQ 'app-orders'
            $site.Source | Should -Be 'module app'
            $site.ResourceGroup | Should -Be 'rg-app' -Because 'the module deploys to another resource group'
            $site.Id | Should -BeLike '/subscriptions/*/resourceGroups/rg-app/providers/Microsoft.Web/sites/app-orders'
            $result.Notices | Should -Contain "Module 'linked' links its template by URI - it isn't fetched, so its resources aren't checked."
            @($result.Notices | Where-Object { $_ -match "Parameter 'secretName' has no value" }).Count | Should -Be 1
        }
    }

    Describe 'Azure Admin Console - Test-AACPolicyDeployment' {
        BeforeAll {
            $script:writeTemplate = {
                param([string] $StoreLocation)
                $path = Join-Path -Path $TestDrive -ChildPath 'main.json'
                $template = @{
                    '$schema'  = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
                    parameters = @{ storeLocation = @{ type = 'string'; defaultValue = $StoreLocation }; env = @{ type = 'string'; defaultValue = 'prod' } }
                    resources  = @(
                        @{ type = 'Microsoft.Storage/storageAccounts'; apiVersion = '2023-05-01'; name = "[format('st{0}', uniqueString(resourceGroup().id))]"; location = "[parameters('storeLocation')]"; sku = @{ name = 'Standard_LRS' }; kind = 'StorageV2'; properties = @{ minimumTlsVersion = 'TLS1_2' } }
                        @{ type = 'Microsoft.KeyVault/vaults'; apiVersion = '2023-07-01'; name = "[concat('kv-orders-', parameters('env'))]"; location = '[resourceGroup().location]'; properties = @{ enableRbacAuthorization = $true } }
                    )
                }
                Set-Content -LiteralPath $path -Value (ConvertTo-Json -InputObject $template -Depth 20)
                $path
            }
        }

        It 'checks each resource the template deploys, and says what Azure Policy would refuse and why' {
            $path = & $script:writeTemplate 'westus'
            $resources = @(Test-AACPolicyDeployment -TemplatePath $path -SubscriptionId $script:tenant.SubscriptionId -ResourceGroupName 'rg-orders' -NoDisplay)
            $resources[0].PSObject.TypeNames[0] | Should -Be 'AAC.PolicyDeploymentResource'
            $store = $resources | Where-Object ResourceType -EQ 'Microsoft.Storage/storageAccounts'
            $store.Outcome | Should -Be 'Blocked'
            $store.Unresolved | Should -Be 'name'
            $vault = $resources | Where-Object ResourceType -EQ 'Microsoft.KeyVault/vaults'
            $vault.Resource | Should -Be 'kv-orders-prod'
            $vault.Outcome | Should -Be 'Passes' -Because 'resourceGroup().location is the group''s, uksouth'
            $vault.AfterDeployment | Should -Be 1 -Because 'Deploy Key Vault diagnostics acts after the deployment'
            @($script:checks | ForEach-Object { $_.Request.resourceDetails.resourceContent.Contains('name') }) | Should -Be @($false, $true) -Because 'a name only known at deployment isn''t sent'
            $script:checks[0].Uri | Should -Match '/resourceGroups/rg-orders/providers/Microsoft.PolicyInsights/checkPolicyRestrictions'

            $failing = @(Test-AACPolicyDeployment -TemplatePath $path -SubscriptionId $script:tenant.SubscriptionId -ResourceGroupName 'rg-orders' -View Policy -NoDisplay | Where-Object State -EQ 'Would fail')
            $failing.Policy | Should -Be 'Allowed locations'
            $failing.Detail | Should -Match "is 'westus'"
        }

        It 'passes a template policy allows, and fails a pipeline with -FailOn Deny when it would be refused' {
            @(Test-AACPolicyDeployment -TemplatePath (& $script:writeTemplate 'ukwest') -SubscriptionId $script:tenant.SubscriptionId -ResourceGroupName 'rg-orders' -FailOn Deny -NoDisplay | ForEach-Object Outcome) | Should -Be @('Passes', 'Passes')
            { Test-AACPolicyDeployment -TemplatePath (& $script:writeTemplate 'westus') -SubscriptionId $script:tenant.SubscriptionId -ResourceGroupName 'rg-orders' -FailOn Deny -NoDisplay } | Should -Throw '*would refuse 1 resource(s)*'
        }

        It 'asks at the subscription for a resource group that does not exist yet, and uses -Location for it' {
            $script:missingGroup = 'rg-new'
            $result = & $script:capture { Test-AACPolicyDeployment -TemplatePath (& $script:writeTemplate 'uksouth') -SubscriptionId $script:tenant.SubscriptionId -ResourceGroupName 'rg-new' -Location 'uksouth' -PassThru -NoPaging }
            @($result.Output | ForEach-Object Outcome) | Should -Be @('Passes', 'Passes')
            @($script:checks | Where-Object { $_.Uri -match '/resourceGroups/' }).Count | Should -Be 0
            $result.Text | Should -Match "doesn't exist yet"
        }

        It 'reads a parameters file, and says what to do with a file that is not a template' {
            $path = & $script:writeTemplate 'uksouth'
            $parameters = Join-Path -Path $TestDrive -ChildPath 'prod.parameters.json'
            Set-Content -LiteralPath $parameters -Value '{ "parameters": { "storeLocation": { "value": "westus" } } }'
            (@(Test-AACPolicyDeployment -TemplatePath $path -ParameterPath $parameters -SubscriptionId $script:tenant.SubscriptionId -ResourceGroupName 'rg-orders' -NoDisplay) | Where-Object ResourceType -EQ 'Microsoft.Storage/storageAccounts').Outcome | Should -Be 'Blocked'
            $bad = Join-Path -Path $TestDrive -ChildPath 'bad.json'
            Set-Content -LiteralPath $bad -Value '{ "name": "x" }'
            { Test-AACPolicyDeployment -TemplatePath $bad -SubscriptionId $script:tenant.SubscriptionId -ResourceGroupName 'rg-orders' -NoDisplay } | Should -Throw "*no 'resources'*"
        }
    }
}
