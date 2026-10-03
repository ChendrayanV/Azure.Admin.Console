<#
    Unit tests for Deploy-AACStorageAccount against an in-memory fake of
    Azure: Resource Manager reads and writes, checkNameAvailability,
    checkPolicyRestrictions, the policy assignments, PSRule and blob uploads
    all go to one store, which answers the way Azure does where it matters
    (false properties left out, a rule's state, a category's retention
    policy, a service's CORS added, PATCH merged in). Proves the plan, the
    gates, apply, verify - and idempotency: the second run writes nothing.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:sub = '11111111-1111-1111-1111-111111111111'
    $script:group = "/subscriptions/$script:sub/resourceGroups/rg-data"
    $script:account = "$script:group/providers/Microsoft.Storage/storageAccounts/stcontosodata"
    $script:base = @{ SubscriptionId = $script:sub; ResourceGroupName = 'rg-data'; Name = 'stcontosodata' }
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
    $script:deploy = { param([hashtable] $Extra = @{}) $p = @{} + $script:base; foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }; Deploy-AACStorageAccount @p -NoDisplay }
    $script:change = { param($Result, [string] $Resource) @($Result.Changes | Where-Object Resource -EQ $Resource)[0] }
}

Describe 'Azure Admin Console - Deploy-AACStorageAccount against a fake Azure' {
    BeforeEach {
        # The fake lives in the test's scope: Pester runs mock bodies there.
        $script:fake = @{
            Store = @{}; Writes = [System.Collections.Generic.List[object]]::new(); Blobs = @{}
            Groups = @{ 'rg-data' = 'uksouth' }; Taken = @('sttaken'); Policy = $null; FailWrite = ''; PSRuleInput = $null
        }
        $script:merge = { param($Base, $Overlay) & (Get-Module 'Azure.Admin.Console') { param($B, $O) Merge-AACObject -Base $B -Overlay $O } $Base $Overlay }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $path = ($u -split '\?')[0].TrimEnd('/').ToLowerInvariant()
                $store = $script:fake.Store
                if ($u -match '/providers/Microsoft\.Authorization/roleAssignments\?') {
                    $items = @($store.Keys | Where-Object { $_.StartsWith("$path/") } | ForEach-Object { $store[$_] })
                    $out[$u] = @{ Status = 200; Body = @{ value = $items }; Items = $items; Error = '' }
                }
                elseif ($path -match '/(containers|shares|queues|tables)$') {
                    $items = @($store.Keys | Where-Object { $_.StartsWith("$path/") -and $_.Substring($path.Length + 1) -notmatch '/' } | ForEach-Object { $store[$_] })
                    $out[$u] = @{ Status = 200; Body = @{ value = $items }; Items = $items; Error = '' }
                }
                elseif ($store.Contains($path)) { $out[$u] = @{ Status = 200; Body = $store[$path]; Items = $null; Error = '' } }
                else { $out[$u] = @{ Status = 404; Body = $null; Items = $null; Error = 'The Resource was not found.' } }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            $notFound = { $e = [System.Exception]::new('The Resource was not found.'); $e.Data['StatusCode'] = 404; throw $e }
            $path = ($Uri -split '\?')[0].TrimEnd('/').ToLowerInvariant()
            if ($Method -eq 'Post' -and $Uri -match 'checkNameAvailability') {
                $name = (ConvertFrom-Json $Body).name
                if ($script:fake.Taken -contains $name) { return @{ nameAvailable = $false; reason = 'AlreadyExists'; message = "The storage account named $name is already taken." } }
                return @{ nameAvailable = $true }
            }
            if ($Method -eq 'Post' -and $Uri -match 'checkPolicyRestrictions') {
                $request = ConvertFrom-Json $Body -AsHashtable
                if ($script:fake.Policy) { return (& $script:fake.Policy $request) }
                return @{ fieldRestrictions = @(); contentEvaluationResult = @{ policyEvaluations = @() } }
            }
            if ($Uri -match 'roleDefinitions\?') {
                if ($Uri -match 'Storage%20Blob%20Data%20Contributor') { return @{ value = @(@{ name = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' }) } }
                return @{ value = @() }
            }
            if ($path -match '/resourcegroups/([^/]+)$') { if ($script:fake.Groups.Contains($Matches[1])) { return @{ name = $Matches[1]; location = $script:fake.Groups[$Matches[1]] } }; & $notFound }
            if ($script:fake.Store.Contains($path)) { return $script:fake.Store[$path] }
            & $notFound
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmWrite -MockWith {
            $path = ($Uri -split '\?')[0].TrimEnd('/')
            $key = $path.ToLowerInvariant()
            # As JSON, as Azure receives it: a copy - so nothing the command
            # holds is changed - and a list sent as an object shows.
            if ($Body) { $Body = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Body -Depth 50) -AsHashtable -Depth 50 }
            $script:fake.Writes.Add([pscustomobject]@{ Method = $Method; Path = $path; Body = $Body })
            if ($script:fake.FailWrite -and $path -match $script:fake.FailWrite) {
                $e = [System.Exception]::new("Resource '$($path -split '/' | Select-Object -Last 1)' was disallowed by policy. Policy identifiers: 'Storage containers must not ...'.")
                $e.Data['Code'] = 'RequestDisallowedByPolicy'; $e.Data['StatusCode'] = 403; throw $e
            }
            if ($Method -eq 'Delete') { foreach ($k in @($script:fake.Store.Keys | Where-Object { $_ -eq $key -or $_.StartsWith("$key/") })) { $script:fake.Store.Remove($k) }; return }
            $stored = if ($Method -eq 'Patch' -and $script:fake.Store.Contains($key)) { & $script:merge $script:fake.Store[$key] $Body } else { & $script:merge @{} $Body }
            $stored['id'] = $path; $stored['name'] = ($path -split '/')[-1]
            if (-not $stored.Contains('properties')) { $stored['properties'] = [ordered]@{} }
            # Azure, as it answers: false left out, its own fields added.
            if ($key -match '/storageaccounts/[^/]+$') {
                foreach ($flag in 'isLocalUserEnabled', 'isSftpEnabled') { if ($false -eq $stored['properties'][$flag]) { $stored['properties'].Remove($flag) } }
                if ($stored['properties']['encryption'] -and $false -eq $stored['properties']['encryption']['requireInfrastructureEncryption']) { $stored['properties']['encryption'].Remove('requireInfrastructureEncryption') }
                $stored['properties']['provisioningState'] = 'Succeeded'
                $stored['properties']['primaryEndpoints'] = @{ blob = "https://$($stored['name']).blob.core.windows.net/" }
                $acl = $stored['properties']['networkAcls']
                if ($acl) { $acl['virtualNetworkRules'] = @(@($acl['virtualNetworkRules']) | Where-Object { $_ } | ForEach-Object { $r = & $script:merge @{} $_; $r['state'] = 'Succeeded'; $r }) }
            }
            if ($key -match '/providers/microsoft\.authorization/roleassignments/') { $stored['properties']['scope'] = ($path -split '/providers/Microsoft\.Authorization/')[0] }
            if ($key -match '/blobservices/default$' -and -not $stored['properties'].Contains('cors')) { $stored['properties']['cors'] = @{ corsRules = @() } }
            if ($key -match '/diagnosticsettings/') { $stored['properties']['logs'] = @(@($stored['properties']['logs']) | ForEach-Object { $l = & $script:merge @{ category = $null; retentionPolicy = @{ enabled = $false; days = 0 } } $_; $l }) }
            $script:fake.Store[$key] = $stored
            $stored
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -ParameterFilter { $Resource -eq 'https://storage.azure.com' } -MockWith {
            if ($Method -eq 'Head') {
                if ($script:fake.Blobs.Contains($Uri)) { $h = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase); $h['Content-MD5'] = $script:fake.Blobs[$Uri]; return @{ Status = 200; Content = ''; Headers = $h } }
                $e = [System.Exception]::new('The specified blob does not exist.'); $e.Data['StatusCode'] = 404; throw $e
            }
            $script:fake.Writes.Add([pscustomobject]@{ Method = 'Upload'; Path = $Uri; Body = $null })
            $script:fake.Blobs[$Uri] = [Convert]::ToBase64String([System.Security.Cryptography.MD5]::HashData($BodyBytes))
            @{ Status = 201; Content = ''; Headers = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAssignedPolicy -MockWith {
            @(
                [pscustomobject]@{ AssignmentId = "/subscriptions/$script:sub/providers/Microsoft.Authorization/policyAssignments/st-tls"; AssignmentDisplayName = 'Storage accounts use TLS 1.2'; DefinitionDisplayName = 'Storage TLS'; DefinitionType = 'Policy'; EnforcementMode = 'Default'; ScopeName = 'sub-data'; AssignmentScope = "/subscriptions/$script:sub"; NotScopes = ''; ResourceType = 'Microsoft.Storage/storageAccounts'; ParameterName = 'effect'; EffectiveValue = 'Deny' }
                [pscustomobject]@{ AssignmentId = "/subscriptions/$script:sub/providers/Microsoft.Authorization/policyAssignments/vm-sku"; AssignmentDisplayName = 'Allowed VM sizes'; DefinitionDisplayName = 'VM SKUs'; DefinitionType = 'Policy'; EnforcementMode = 'Default'; ScopeName = 'sub-data'; AssignmentScope = "/subscriptions/$script:sub"; NotScopes = ''; ResourceType = 'Microsoft.Compute/virtualMachines'; ParameterName = 'listOfAllowedSKUs'; EffectiveValue = 'Standard_D2s_v5' }
            )
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -MockWith {
            $script:fake.PSRuleInput = $InputObject
            $object = $InputObject[0]
            $acl = $object['properties']['networkAcls']
            $results = @([pscustomobject]@{ Outcome = 'Pass'; RuleName = 'Azure.Storage.MinTLS'; Title = 'Minimum TLS'; ResourceName = $object['name']; Severity = 'Important'; Reason = ''; Link = '' })
            if ([string]$acl['defaultAction'] -ne 'Deny') { $results += [pscustomobject]@{ Outcome = 'Fail'; RuleName = 'Azure.Storage.Firewall'; Title = 'Storage firewall'; ResourceName = $object['name']; Severity = 'Important'; Reason = 'The default network action is Allow.'; Link = 'https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.Storage.Firewall/' } }
            @{ Results = $results; Warnings = @(); Rules = 2; Objects = 1; Version = '1.47.0' }
        }
    }

    It 'plans a new account with -WhatIf - AVM''s defaults, every child - and writes nothing' {
        $result = & $script:deploy @{ Container = 'logs', 'exports'; WhatIf = $true }
        $result.PSObject.TypeNames[0] | Should -Be 'AAC.StorageDeployment'
        $result.Status | Should -Be 'Planned'
        @($result.Changes | Where-Object Action -EQ 'Create' | ForEach-Object Resource) | Should -Be @('Storage account stcontosodata', 'Blob service of stcontosodata', 'Container logs', 'Container exports')
        $account = & $script:change $result 'Storage account stcontosodata'
        $account.Body.sku.name | Should -Be 'Standard_GRS'
        $account.Body.kind | Should -Be 'StorageV2'
        $account.Body.location | Should -Be 'uksouth' -Because "the resource group's region"
        $account.Body.properties.minimumTlsVersion | Should -Be 'TLS1_2'
        $account.Body.properties.allowBlobPublicAccess | Should -BeFalse
        $account.Body.properties.networkAcls.defaultAction | Should -Be 'Deny'
        $account.Body.properties.networkAcls.bypass | Should -Be 'AzureServices'
        $account.Body.properties.encryption.requireInfrastructureEncryption | Should -BeTrue
        (& $script:change $result 'Blob service of stcontosodata').Body.properties.deleteRetentionPolicy.days | Should -Be 6
        (& $script:change $result 'Container logs').Body.properties.publicAccess | Should -Be 'None'
        & { $script:fake.Writes.Count } | Should -Be 0
    }

    It 'applies, verifies - and the second run plans no changes and writes nothing (idempotent)' {
        $first = & $script:deploy @{ Container = 'logs'; Force = $true }
        $first.Status | Should -Be 'Applied'
        @($first.Applied | ForEach-Object Status | Select-Object -Unique) | Should -Be @('Applied')
        @($first.Verification).Count | Should -Be 0 -Because 'read again, everything matches'
        $written = & { @($script:fake.Writes | ForEach-Object { "$($_.Method) $(($_.Path -split '/providers/Microsoft.Storage/')[-1])" }) }
        $written | Should -Be @('Put storageAccounts/stcontosodata', 'Put storageAccounts/stcontosodata/blobServices/default', 'Put storageAccounts/stcontosodata/blobServices/default/containers/logs')
        & { $script:fake.Writes.Clear() }
        $second = & $script:deploy @{ Container = 'logs'; Force = $true }
        $second.Status | Should -Be 'NoChanges'
        @($second.Changes | Where-Object Action -NE 'NoChange').Count | Should -Be 0
        & { $script:fake.Writes.Count } | Should -Be 0
    }

    It 'updates with PATCH and only what changed - Azure''s own fields and omitted false values aren''t changes' {
        $null = & $script:deploy @{ Force = $true; Setting = @{ networkAcls = @{ virtualNetworkRules = @("$script:group/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet") } } }
        & { $script:fake.Writes.Clear() }
        $result = & $script:deploy @{ Force = $true; SkuName = 'Standard_LRS'; Tag = @{ env = 'prod' }; Setting = @{ networkAcls = @{ virtualNetworkRules = @("$script:group/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet") } } }
        $account = & $script:change $result 'Storage account stcontosodata'
        $account.Action | Should -Be 'Update'
        $account.Method | Should -Be 'Patch'
        @($account.Differences | ForEach-Object Property | Sort-Object) | Should -Be @('sku.name', 'tags') -Because 'largeFileSharesState is absent, which Azure means as Disabled - as desired; nothing else differs'
        $patch = & { @($script:fake.Writes)[0] }
        $patch.Method | Should -Be 'Patch'
        @($patch.Body.Keys | Sort-Object) | Should -Be @('sku', 'tags') -Because 'no property changed, so none is sent'
        $result.Status | Should -Be 'Applied'
        @($result.Verification).Count | Should -Be 0
    }

    It 'keeps a service''s settings it doesn''t manage when it updates it (PUT merged)' {
        $null = & $script:deploy @{ Force = $true }
        & { $script:fake.Store["$($args[0].ToLowerInvariant())/blobservices/default"]['properties']['cors'] = @{ corsRules = @(@{ allowedOrigins = @('https://contoso.com') }) } } $script:account
        $null = & $script:deploy @{ Force = $true; Setting = @{ blobServices = @{ isVersioningEnabled = $true } } }
        $sent = & { @($script:fake.Writes | Where-Object { $_.Path -like '*/blobServices/default' })[-1].Body }
        $sent.properties.isVersioningEnabled | Should -BeTrue
        $sent.properties.cors.corsRules[0].allowedOrigins | Should -Be 'https://contoso.com'
    }

    It 'stops at a property Azure can''t change in place' {
        $null = & $script:deploy @{ Force = $true }
        $plan = & $script:deploy @{ WhatIf = $true; Setting = @{ enableHierarchicalNamespace = $true; requireInfrastructureEncryption = $false } }
        $plan.Status | Should -Be 'Blocked'
        $account = & $script:change $plan 'Storage account stcontosodata'
        $account.Action | Should -Be 'Replace'
        @($plan.Gates | Where-Object { $_.Gate -eq 'Immutable' } | ForEach-Object Item | Sort-Object) | Should -Be @('properties.encryption.requireInfrastructureEncryption', 'properties.isHnsEnabled')
        { $null = & $script:capture { & $script:deploy @{ Force = $true; Setting = @{ enableHierarchicalNamespace = $true } } } } | Should -Throw -ExpectedMessage '*is blocked - nothing was changed*'
    }

    It 'reads the same under -WhatIf (ForEach-Object <Name> on a hashtable returns nothing under -WhatIf)' {
        $roles = @{ roleAssignments = @(@{ roleDefinitionIdOrName = 'Storage Blob Data Contributor'; principalId = '22222222-2222-2222-2222-222222222222' }) }
        $null = & $script:deploy @{ Force = $true; Setting = $roles }
        (& $script:change (& $script:deploy @{ WhatIf = $true; Setting = $roles }) 'Role Storage Blob Data Contributor on stcontosodata').Action | Should -Be 'NoChange'
        @((& $script:deploy @{ WhatIf = $true; Setting = $roles }).Policies | ForEach-Object { $_.Assignment }) | Should -Be @('Storage accounts use TLS 1.2') -Because 'the policy assignments are read under -WhatIf too'
    }

    It 'changes redundancy in place within its kind, and stops for zonal or Premium' {
        $null = & $script:deploy @{ Force = $true }
        (& $script:change (& $script:deploy @{ WhatIf = $true; SkuName = 'Standard_RAGRS' }) 'Storage account stcontosodata').Action | Should -Be 'Update'
        foreach ($sku in 'Standard_ZRS', 'Premium_LRS') {
            $plan = & $script:deploy @{ WhatIf = $true; SkuName = $sku }
            (& $script:change $plan 'Storage account stcontosodata').Action | Should -Be 'Replace' -Because "Standard_GRS -> $sku needs a conversion or a new account"
        }
    }

    It 'stops when the name is taken' {
        $plan = & $script:deploy @{ Name = 'sttaken'; WhatIf = $true }
        $plan.Status | Should -Be 'Blocked'
        ($plan.Gates | Where-Object Gate -EQ 'Name').Detail | Should -Match 'already taken'
    }

    It 'asks Azure Policy about the exact body of each write: a Deny blocks, a Modify is shown' {
        & {
            $script:fake.Policy = {
                param($Request)
                $content = $Request.resourceDetails.resourceContent
                $evaluations = @()
                if ($content.type -eq 'Microsoft.Storage/storageAccounts' -and $content.properties.allowSharedKeyAccess) {
                    $evaluations += @{ evaluationResult = 'NonCompliant'; effectDetails = @{ policyEffect = 'Deny' }; policyInfo = @{ policyAssignmentId = "/subscriptions/$script:sub/providers/Microsoft.Authorization/policyAssignments/st-tls"; policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/no-shared-key' }; evaluationDetails = @{ evaluatedExpressions = @(@{ path = 'properties.allowSharedKeyAccess'; operator = 'notEquals'; targetValue = $false; result = 'True' }) } }
                }
                @{ contentEvaluationResult = @{ policyEvaluations = $evaluations }; fieldRestrictions = @(@{ field = 'tags.costcentre'; restrictions = @(@{ result = 'Required'; defaultValue = 'CC-0'; policyEffect = 'Modify'; policy = @{ policyAssignmentId = 'x/inherit-tag' } }) }) }
            }
        }
        $plan = & $script:deploy @{ WhatIf = $true }
        $deny = @($plan.Gates | Where-Object { $_.Gate -eq 'Policy' -and $_.Outcome -eq 'Blocks' })
        $deny.Count | Should -Be 1
        $deny[0].Item | Should -Be 'Storage accounts use TLS 1.2' -Because 'the assignment is named, not just its ID'
        $deny[0].Detail | Should -Match 'allowSharedKeyAccess'
        @($plan.Gates | Where-Object { $_.Gate -eq 'Policy' -and $_.Outcome -eq 'Changes' }).Detail | Should -Contain "Sets tags.costcentre to 'CC-0' when it isn't given (Modify)."
        @($plan.Policies | ForEach-Object Assignment) | Should -Be @('Storage accounts use TLS 1.2') -Because 'only the assignments that target storage'
        $null = & $script:deploy @{ WhatIf = $true; Setting = @{ allowSharedKeyAccess = $false } }
        @((& $script:deploy @{ WhatIf = $true; Setting = @{ allowSharedKeyAccess = $false } }).Gates | Where-Object Outcome -EQ 'Blocks').Count | Should -Be 0
    }

    It 'runs PSRule on the account as it will be, with its children - and a failing rule blocks, with its fix' {
        $plan = & $script:deploy @{ WhatIf = $true; Container = 'logs'; Setting = @{ networkAcls = @{ defaultAction = 'Allow' } } }
        $breaks = @($plan.Gates | Where-Object Outcome -EQ 'Breaks')
        @($breaks | ForEach-Object Item) | Should -Be @('Azure.Storage.Firewall')
        $plan.Status | Should -Be 'Blocked' -Because 'a failing PSRule rule stops the deployment'
        $breaks[0].Fix | Should -Match '^Set networkAcls\.defaultAction = "Deny"\.'
        @($plan.Fixes | ForEach-Object Setting) | Should -Be @('networkAcls.defaultAction')
        $object = & { $script:fake.PSRuleInput[0] }
        $object['type'] | Should -Be 'Microsoft.Storage/storageAccounts'
        $object['apiVersion'] | Should -Be '2023-05-01' -Because 'PSRule reads defaults by it'
        $object['resourceGroupName'] | Should -Be 'rg-data'
        @($object['resources'] | ForEach-Object { $_['type'] }) | Should -Contain 'Microsoft.Storage/storageAccounts/blobServices/containers'
        { $null = & $script:capture { & $script:deploy @{ Force = $true; Setting = @{ networkAcls = @{ defaultAction = 'Allow' } } } } } | Should -Throw -ExpectedMessage '*blocked - nothing was changed: PSRule: stcontosodata (Azure.Storage.Firewall)*'
        & { $script:fake.Writes.Count } | Should -Be 0
    }

    It 'deploys with the suggested fixes on -UseSuggestedFix - checked again, and shown to put in the configuration' {
        $plan = & $script:deploy @{ WhatIf = $true; UseSuggestedFix = $true; Setting = @{ networkAcls = @{ defaultAction = 'Allow'; ipRules = @('203.0.113.10') } } }
        $plan.Status | Should -Be 'Planned'
        @($plan.FixesApplied | ForEach-Object Setting) | Should -Be @('networkAcls.defaultAction')
        @($plan.Gates | Where-Object Outcome -EQ 'Breaks').Count | Should -Be 0 -Because 'the gates ran again on the fixed configuration'
        (& $script:change $plan 'Storage account stcontosodata').Body.properties.networkAcls.defaultAction | Should -Be 'Deny'
        @((& $script:change $plan 'Storage account stcontosodata').Body.properties.networkAcls.ipRules | ForEach-Object { $_['value'] }) | Should -Be @('203.0.113.10') -Because 'the rest of the configuration stays'
        $text = (& $script:capture { Deploy-AACStorageAccount @script:base -UseSuggestedFix -WhatIf -Setting @{ networkAcls = @{ defaultAction = 'Allow' } } }).Text
        $text | Should -Match 'Suggested fixes applied to this run'
        $text | Should -Match "defaultAction = 'Deny'"
        $applied = & $script:deploy @{ Force = $true; UseSuggestedFix = $true; Setting = @{ networkAcls = @{ defaultAction = 'Allow' } } }
        $applied.Status | Should -Be 'Applied'
        @($applied.Verification).Count | Should -Be 0
    }

    It 'shows how to fix a block: the settings as a configuration snippet, and -UseSuggestedFix' {
        $text = (& $script:capture { Deploy-AACStorageAccount @script:base -WhatIf -Setting @{ networkAcls = @{ defaultAction = 'Allow' } } }).Text
        $text | Should -Match 'How to fix the failing PSRule rules'
        $text | Should -Match 'networkAcls = @\{'
        $text | Should -Match "defaultAction = 'Deny'"
        $text | Should -Match '-UseSuggestedFix'
        $text | Should -Match 'Fix: Set networkAcls\.defaultAction'
    }

    It 'blocks when PSRule can''t run - not checked is not passed - unless -SkipPSRule' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -MockWith { throw 'PSRule for Azure 1.47.0 failed: boom' }
        $plan = & $script:deploy @{ WhatIf = $true }
        $plan.Status | Should -Be 'Blocked'
        ($plan.Gates | Where-Object Gate -EQ 'PSRule').Detail | Should -Match "couldn't run"
        (& $script:deploy @{ WhatIf = $true; SkipPSRule = $true }).Status | Should -Be 'Planned'
    }

    It 'reports containers that aren''t configured as drift, deletes them with -Prune - unless locked' {
        $null = & $script:deploy @{ Force = $true; Container = 'logs', 'old' }
        $plan = & $script:deploy @{ WhatIf = $true; Container = 'logs' }
        (& $script:change $plan 'Container old').Action | Should -Be 'Drift'
        $pruned = & $script:deploy @{ Force = $true; Container = 'logs'; Prune = $true }
        @($pruned.Applied | Where-Object Action -EQ 'Delete').Resource | Should -Be 'Container old'
        & { $script:fake.Store.Contains("$($args[0].ToLowerInvariant())/blobservices/default/containers/old") } $script:account | Should -BeFalse
        $null = & $script:deploy @{ Force = $true; Container = 'logs', 'old2'; Setting = @{ lock = @{ kind = 'CanNotDelete' } } }
        $locked = & $script:deploy @{ WhatIf = $true; Container = 'logs'; Prune = $true; Setting = @{ lock = @{ kind = 'CanNotDelete' } } }
        $locked.Status | Should -Be 'Blocked'
        ($locked.Gates | Where-Object Gate -EQ 'Lock').Detail | Should -Match 'locked'
    }

    It 'names a role assignment from scope, principal and role - found again, and an existing one adopted' {
        $roles = @{ roleAssignments = @(@{ roleDefinitionIdOrName = 'Storage Blob Data Contributor'; principalId = '22222222-2222-2222-2222-222222222222'; principalType = 'Group' }) }
        $first = & $script:deploy @{ Force = $true; Setting = $roles }
        $put = & { @($script:fake.Writes | Where-Object { $_.Path -match 'roleAssignments' })[0] }
        $put.Body.properties.roleDefinitionId | Should -Match '/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe$'
        $put.Body.properties.principalType | Should -Be 'Group'
        $again = & $script:deploy @{ WhatIf = $true; Setting = $roles }
        (& $script:change $again 'Role Storage Blob Data Contributor on stcontosodata').Action | Should -Be 'NoChange'
        # Made another way (the portal): a random name - still the same assignment.
        & {
            $key = @($script:fake.Store.Keys | Where-Object { $_ -match 'roleassignments' })[0]
            $item = $script:fake.Store[$key]; $script:fake.Store.Remove($key)
            $item['id'] = $item['id'] -replace '[0-9a-f-]{36}$', '99999999-9999-9999-9999-999999999999'
            $script:fake.Store[$item['id'].ToLowerInvariant()] = $item
        }
        (& $script:change (& $script:deploy @{ WhatIf = $true; Setting = $roles }) 'Role Storage Blob Data Contributor on stcontosodata').Action | Should -Be 'NoChange'
    }

    It 'uploads a blob only when it is new or changed (MD5)' {
        $file = Join-Path $TestDrive 'index.html'
        Set-Content -LiteralPath $file -Value '<h1>v1</h1>' -NoNewline
        $blob = @{ container = 'web'; path = $file; contentType = 'text/html' }
        $null = & $script:deploy @{ Force = $true; Container = 'web'; Blob = $blob; Setting = @{ networkAcls = @{ ipRules = @('203.0.113.10') } } }
        & { @($script:fake.Writes | Where-Object Method -EQ 'Upload').Count } | Should -Be 1
        (& $script:change (& $script:deploy @{ WhatIf = $true; Container = 'web'; Blob = $blob; Setting = @{ networkAcls = @{ ipRules = @('203.0.113.10') } } }) 'Blob web/index.html').Action | Should -Be 'NoChange'
        Set-Content -LiteralPath $file -Value '<h1>v2</h1>' -NoNewline
        (& $script:change (& $script:deploy @{ WhatIf = $true; Container = 'web'; Blob = $blob; Setting = @{ networkAcls = @{ ipRules = @('203.0.113.10') } } }) 'Blob web/index.html').Action | Should -Be 'Update'
    }

    It 'warns that blob uploads need network access when the account denies by default' {
        $file = Join-Path $TestDrive 'a.txt'; Set-Content -LiteralPath $file -Value 'a'
        $plan = & $script:deploy @{ WhatIf = $true; Container = 'web'; Blob = @{ container = 'web'; path = $file } }
        ($plan.Gates | Where-Object Gate -EQ 'Network').Detail | Should -Match 'ipRules'
    }

    It 'brings diagnostic settings, services and children to the same state on the second run' {
        $setting = @{
            diagnosticSettings = @(@{ workspaceResourceId = "$script:group/providers/Microsoft.OperationalInsights/workspaces/law" })
            blobServices       = @{ deleteRetentionPolicyEnabled = $true; deleteRetentionPolicyDays = 14; isVersioningEnabled = $true; containers = @(@{ name = 'data'; metadata = @{ owner = 'team-a' } }); diagnosticSettings = @(@{ workspaceResourceId = "$script:group/providers/Microsoft.OperationalInsights/workspaces/law" }) }
            fileServices       = @{ shares = @(@{ name = 'share1'; shareQuota = 100 }) }
            queueServices      = @{ queues = @('jobs') }
            tableServices      = @{ tables = @('events') }
            managementPolicyRules = @(@{ name = 'cool-after-30'; enabled = $true; type = 'Lifecycle'; definition = @{ actions = @{ baseBlob = @{ tierToCool = @{ daysAfterModificationGreaterThan = 30 } } }; filters = @{ blobTypes = @('blockBlob') } } })
            lock               = @{ kind = 'CanNotDelete' }
        }
        $first = & $script:deploy @{ Force = $true; Setting = $setting }
        $first.Status | Should -Be 'Applied'
        @($first.Verification | ForEach-Object { "$($_.Resource): $(@($_.Differences | ForEach-Object { "$($_.Property) [$($_.Current)] -> [$($_.Desired)]" }) -join '; ')" }) | Should -BeNullOrEmpty -Because 'logs Azure echoes back with retention policies, and the service''s CORS, are not changes'
        & { $script:fake.Writes.Clear() }
        $second = & $script:deploy @{ Force = $true; Setting = $setting }
        @($second.Changes | Where-Object Action -NE 'NoChange' | ForEach-Object { "$($_.Action) $($_.Resource): $(@($_.Differences | ForEach-Object { "$($_.Property) [$($_.Current)] -> [$($_.Desired)]" }) -join '; ') $($_.Reason)" }) | Should -BeNullOrEmpty
        $second.Status | Should -Be 'NoChanges'
        & { $script:fake.Writes.Count } | Should -Be 0
        $order = @($first.Applied | ForEach-Object Resource)
        $order[0] | Should -Be 'Storage account stcontosodata'
        $order[-1] | Should -Match 'lock' -Because 'the lock goes on last'
    }

    It 'stops at the first failure: what came before stays, the rest is skipped, and running again carries on' {
        & { $script:fake.FailWrite = '/containers/bbb$' }
        { $null = & $script:capture { & $script:deploy @{ Force = $true; Container = 'aaa', 'bbb', 'ccc' } } } | Should -Throw -ExpectedMessage '*Container bbb couldn''t be created: Denied by Azure Policy*'
        & { @($script:fake.Store.Keys | Where-Object { $_ -match '/containers/' } | ForEach-Object { ($_ -split '/')[-1] } | Sort-Object) } | Should -Be @('aaa')
        & { $script:fake.FailWrite = '' }
        $retry = & $script:deploy @{ Force = $true; Container = 'aaa', 'bbb', 'ccc' }
        @($retry.Applied | ForEach-Object Resource) | Should -Be @('Container bbb', 'Container ccc') -Because 'only what is left'
    }

    It 'reads an AVM parameters file, and refuses settings it doesn''t support' {
        $avm = Join-Path $TestDrive 'avm.json'
        @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = @{ name = @{ value = 'stcontosodata' }; skuName = @{ value = 'Standard_ZRS' }; blobServices = @{ value = @{ containers = @(@{ name = 'raw'; publicAccess = 'None' }) } }; enableTelemetry = @{ value = $true } } } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $avm
        $plan = Deploy-AACStorageAccount -SubscriptionId $script:sub -ResourceGroupName 'rg-data' -ConfigurationPath $avm -WhatIf -NoDisplay
        (& $script:change $plan 'Storage account stcontosodata').Body.sku.name | Should -Be 'Standard_ZRS'
        (& $script:change $plan 'Container raw').Action | Should -Be 'Create'
        $bad = Join-Path $TestDrive 'bad.psd1'
        "@{ name = 'stcontosodata'; customerManagedKey = @{ keyName = 'k' } }" | Set-Content -LiteralPath $bad
        { $null = & $script:capture { Deploy-AACStorageAccount -SubscriptionId $script:sub -ResourceGroupName 'rg-data' -ConfigurationPath $bad -WhatIf -NoDisplay } } | Should -Throw -ExpectedMessage "*aren't supported yet: customerManagedKey*"
    }

    It 'says so when the resource group doesn''t exist' {
        { $null = & $script:capture { Deploy-AACStorageAccount -SubscriptionId $script:sub -ResourceGroupName 'rg-missing' -Name 'stcontosodata' -WhatIf -NoDisplay } } | Should -Throw -ExpectedMessage "*rg-missing doesn't exist*"
    }

    It 'writes the plan to -PlanPath, and shows the plan, the policies and the gates' {
        $planFile = Join-Path $TestDrive 'plan.json'
        $text = (& $script:capture { Deploy-AACStorageAccount @script:base -Container logs -WhatIf -PlanPath $planFile }).Text
        $saved = Get-Content -LiteralPath $planFile -Raw | ConvertFrom-Json
        $saved.account | Should -Be 'stcontosodata'
        @($saved.changes | Where-Object action -EQ 'Create').Count | Should -Be 3
        foreach ($expected in 'Plan: 3 to create', 'Storage account stcontosodata', 'minimumTlsVersion', 'Azure Policy assigned here for storage', 'Storage accounts use TLS 1.2', 'Gates', 'Ready to apply') { $text | Should -Match ([regex]::Escape($expected)) }
    }

    It 'sends lists as lists: diagnostic categories, IP rules and lifecycle rules of one item' {
        $one = @{
            diagnosticSettings = @(@{ workspaceResourceId = "$script:group/providers/Microsoft.OperationalInsights/workspaces/law" })
            blobServices = @{ containers = @('ccc'); diagnosticSettings = @(@{ workspaceResourceId = "$script:group/providers/Microsoft.OperationalInsights/workspaces/law" }) }
            networkAcls = @{ ipRules = @('203.0.113.10') }
            managementPolicyRules = @(@{ name = 'r1'; enabled = $true; type = 'Lifecycle'; definition = @{ actions = @{ baseBlob = @{ delete = @{ daysAfterModificationGreaterThan = 365 } } }; filters = @{ blobTypes = @('blockBlob') } } })
        }
        $null = & $script:deploy @{ Force = $true; Setting = $one }
        $bodies = @($script:fake.Writes | Where-Object Body)
        $diag = @($bodies | Where-Object { $_.Path -match '/blobServices/default/providers/Microsoft.Insights/diagnosticSettings/' })[0].Body
        ,$diag.properties.logs | Should -BeOfType [System.Collections.IList]
        $account = @($bodies | Where-Object { $_.Path -match 'storageAccounts/stcontosodata$' })[0].Body
        ,$account.properties.networkAcls.ipRules | Should -BeOfType [System.Collections.IList]
        $policy = @($bodies | Where-Object { $_.Path -match '/managementPolicies/default$' })[0].Body
        ,$policy.properties.policy.rules | Should -BeOfType [System.Collections.IList]
        ,$policy.properties.policy.rules[0].definition.filters.blobTypes | Should -BeOfType [System.Collections.IList]
    }

    It 'compares every property it sets: the create body holds nothing that is never checked again' {
        $nodes = InModuleScope 'Azure.Admin.Console' {
            $config = ConvertTo-AACStorageConfiguration -Override @{ name = 'stcontosodata'; tags = @{ a = 'b' }; blobServices = @{ deleteRetentionPolicyEnabled = $true; deleteRetentionPolicyDays = 7; isVersioningEnabled = $true; changeFeedEnabled = $true; changeFeedRetentionInDays = 7; containers = @('ccc') }; fileServices = @{ shares = @(@{ name = 's'; accessTier = 'Hot' }) } }
            Get-AACStorageDesiredState -Configuration $config -SubscriptionId '11111111-1111-1111-1111-111111111111' -ResourceGroupName 'rg' -Location 'uksouth'
        }
        $leaves = {
            param($Value, [string] $Prefix)
            if ($Value -is [System.Collections.IDictionary]) { foreach ($k in $Value.Keys) { & $leaves $Value[$k] $(if ($Prefix) { "$Prefix.$k" } else { $k }) } }
            else { $Prefix }
        }
        $unchecked = foreach ($node in $nodes | Where-Object Kind -In 'account', 'blobService', 'container', 'fileService', 'share') {
            $managed = @($node.Managed | ForEach-Object Path)
            foreach ($path in @(& $leaves $node.Desired '')) {
                if (-not @($managed | Where-Object { $path -eq $_ -or $path.StartsWith("$_.") }).Count -and $path -notmatch '^properties\.encryption\.(keySource|services)') { "$($node.Kind): $path" }
            }
        }
        @($unchecked) | Should -BeNullOrEmpty -Because 'a property sent on create but never compared would drift silently'
    }
}


Describe 'Azure Admin Console - the fixes for failing PSRule rules' {
    BeforeAll {
        $script:fix = {
            param([object[]] $Result, [hashtable] $Configuration = @{ name = 'stcontosodata' }, [switch] $Exists)
            InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $Result; C = $Configuration; E = [bool]$Exists } { param($R, $C, $E) Get-AACStorageRuleFix -Result $R -Configuration $C -AccountExists:$E }
        }
        $script:result = { param([string] $Rule, [string] $Reason = '') [pscustomobject]@{ Outcome = 'Fail'; RuleName = $Rule; ResourceName = 'stcontosodata'; Reason = $Reason; Link = '' } }
    }

    It 'turns <Rule> into <Setting> = <Value>' -ForEach @(
        @{ Rule = 'Azure.Storage.LocalAuth'; Setting = 'allowSharedKeyAccess'; Value = $false }
        @{ Rule = 'Azure.Storage.BlobPublicAccess'; Setting = 'allowBlobPublicAccess'; Value = $false }
        @{ Rule = 'Azure.Storage.MinTLS'; Setting = 'minimumTlsVersion'; Value = 'TLS1_2' }
        @{ Rule = 'Azure.Storage.SecureTransfer'; Setting = 'supportsHttpsTrafficOnly'; Value = $true }
        @{ Rule = 'Azure.Storage.Firewall'; Setting = 'networkAcls.defaultAction'; Value = 'Deny' }
        @{ Rule = 'Azure.Storage.SoftDelete'; Setting = 'blobServices.deleteRetentionPolicyEnabled'; Value = $true }
        @{ Rule = 'Azure.Storage.ContainerSoftDelete'; Setting = 'blobServices.containerDeleteRetentionPolicyEnabled'; Value = $true }
        @{ Rule = 'Azure.Storage.FileShareSoftDelete'; Setting = 'fileServices.shareDeleteRetentionPolicy.enabled'; Value = $true }
    ) {
        $fixes = @(& $script:fix @(& $script:result $Rule))
        $match = @($fixes | Where-Object Setting -EQ $Setting)
        $match.Count | Should -Be 1
        $match[0].Kind | Should -Be 'Auto'
        $match[0].Value | Should -Be $Value
    }

    It 'makes each public container private, by the name in the rule''s reason' {
        $fixes = @(& $script:fix @(& $script:result 'Azure.Storage.BlobAccessType' "The container 'pub' is configured with access type 'Blob'."))
        $fixes[0].Setting | Should -Be 'blobServices.containers[name=pub].publicAccess'
        $fixes[0].Value | Should -Be 'None'
    }

    It 'suggests a redundancy Azure can apply: GRS in place for an existing account, GZRS for a new one' {
        (& $script:fix @(& $script:result 'Azure.Storage.UseReplication') @{ name = 'st1'; skuName = 'Standard_LRS' } -Exists)[0].Value | Should -Be 'Standard_GRS'
        (& $script:fix @(& $script:result 'Azure.Storage.UseReplication') @{ name = 'st1'; skuName = 'Standard_LRS' })[0].Value | Should -Be 'Standard_GZRS'
        (& $script:fix @(& $script:result 'Azure.Storage.UseReplication') @{ name = 'st1'; skuName = 'Premium_LRS' } -Exists)[0].Kind | Should -Be 'Manual'
    }

    It 'says what to do when no setting fixes it: <Rule>' -ForEach @(
        @{ Rule = 'Azure.Storage.DefenderCloud'; Advice = 'Defender for Storage' }
        @{ Rule = 'Azure.Storage.Naming'; Advice = "can't be renamed" }
        @{ Rule = 'Contoso.Storage.Custom'; Advice = '-ExcludeRule Contoso.Storage.Custom' }
    ) {
        $fixes = @(& $script:fix @(& $script:result $Rule))
        $fixes[0].Kind | Should -Be 'Manual'
        $fixes[0].Advice | Should -Match ([regex]::Escape($Advice))
    }

    It 'applies fixes to a copy of the configuration: a named container becomes a hashtable, blobServices starts from AVM''s defaults' {
        $result = InModuleScope 'Azure.Admin.Console' {
            $config = [ordered]@{ name = 'st1'; blobServices = [ordered]@{ containers = @('pub', 'raw') } }
            $fixes = @(
                [pscustomobject]@{ Kind = 'Auto'; Setting = 'blobServices.containers[name=pub].publicAccess'; Value = 'None' }
                [pscustomobject]@{ Kind = 'Auto'; Setting = 'networkAcls.defaultAction'; Value = 'Deny' }
            )
            $fixed = Set-AACStorageConfigurationFix -Configuration $config -Fix $fixes
            $fresh = Set-AACStorageConfigurationFix -Configuration ([ordered]@{ name = 'st2' }) -Fix @([pscustomobject]@{ Kind = 'Auto'; Setting = 'blobServices.isVersioningEnabled'; Value = $true })
            @{ Fixed = $fixed; Original = $config; Fresh = $fresh }
        }
        $result.Fixed.blobServices.containers[0].name | Should -Be 'pub'
        $result.Fixed.blobServices.containers[0].publicAccess | Should -Be 'None'
        $result.Fixed.blobServices.containers[1] | Should -Be 'raw'
        $result.Fixed.networkAcls.defaultAction | Should -Be 'Deny'
        $result.Original.blobServices.containers[0] | Should -Be 'pub' -Because 'the input is not changed'
        $result.Original.Contains('networkAcls') | Should -BeFalse
        $result.Fresh.blobServices.deleteRetentionPolicyDays | Should -Be 6 -Because 'AVM''s default blob settings stay'
        $result.Fresh.blobServices.isVersioningEnabled | Should -BeTrue
    }
}

Describe 'Azure Admin Console - the suggested fixes against the real PSRule for Azure rules' -Skip:(-not (Get-Module PSRule.Rules.Azure -ListAvailable)) {
    BeforeEach {
        # Nothing exists yet: the account is planned from scratch. PSRule runs for real.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { $out = @{}; foreach ($u in $Uri) { $out[$u] = @{ Status = 404; Body = $null; Items = $null; Error = 'Not found' } }; $out }
        # No request may leave the machine: the name check too.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith { @{ nameAvailable = $true } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith { throw "A test tried to call Azure: $Method $Uri" }
    }

    It 'fixes every rule a setting can fix: an account that fails them all passes once the fixes are applied' {
        $outcome = InModuleScope 'Azure.Admin.Console' {
            $script:AACProgressPlain = $true
            $sub = '11111111-1111-1111-1111-111111111111'
            $broken = ConvertTo-AACStorageConfiguration -Override @{
                name = 'stcontosodata'; skuName = 'Standard_LRS'; minimumTlsVersion = 'TLS1_0'; supportsHttpsTrafficOnly = $false; allowBlobPublicAccess = $true; allowSharedKeyAccess = $true
                networkAcls = @{ defaultAction = 'Allow' }
                blobServices = @{ deleteRetentionPolicyEnabled = $false; containerDeleteRetentionPolicyEnabled = $false; containers = @(@{ name = 'pub'; publicAccess = 'Blob' }, 'raw') }
            }
            $check = {
                param($Configuration)
                $nodes = Get-AACStorageDesiredState -Configuration $Configuration -SubscriptionId $sub -ResourceGroupName 'rg-data' -Location 'uksouth'
                $changes = Get-AACStoragePlan -Node $nodes -SubscriptionId $sub
                Test-AACStoragePlan -Change $changes -SubscriptionId $sub -ResourceGroupName 'rg-data' -SkipPolicy -Configuration $Configuration
            }
            $before = & $check $broken
            $fixed = Set-AACStorageConfigurationFix -Configuration $broken -Fix @($before.Fixes | Where-Object Kind -EQ 'Auto')
            $after = & $check $fixed
            # What only you can give: the tags.
            $fixed['tags'] = [ordered]@{ env = 'prod'; owner = 'data-platform' }
            $tagged = & $check $fixed
            @{
                Before = @($before.Gates | Where-Object Outcome -EQ 'Breaks' | ForEach-Object { $_.Item } | Sort-Object)
                Manual = @($before.Fixes | Where-Object Kind -EQ 'Manual' | ForEach-Object { $_.Rule })
                After  = @($after.Gates | Where-Object Outcome -In 'Breaks', 'Blocks' | ForEach-Object { $_.Item })
                Tagged = @($tagged.Gates | Where-Object Outcome -In 'Breaks', 'Blocks' | ForEach-Object { "$($_.Item): $($_.Detail)" })
            }
        }
        $outcome.Before | Should -Be @('Azure.Resource.UseTags', 'Azure.Storage.BlobAccessType', 'Azure.Storage.BlobPublicAccess', 'Azure.Storage.ContainerSoftDelete', 'Azure.Storage.Firewall', 'Azure.Storage.LocalAuth', 'Azure.Storage.MinTLS', 'Azure.Storage.SecureTransfer', 'Azure.Storage.SoftDelete', 'Azure.Storage.UseReplication')
        $outcome.Manual | Should -Be @('Azure.Resource.UseTags') -Because 'tag values are yours to give'
        $outcome.After | Should -Be @('Azure.Resource.UseTags') -Because 'every automatic fix satisfies the real rule'
        $outcome.Tagged | Should -BeNullOrEmpty -Because 'with the tags given too, nothing fails'
    }
}
