<#
    Unit tests for Export-AACTerraform: the HCL splitter, the folder layout
    (azurerm and azapi exports merged), the rows, and the command with the
    Azure Export for Terraform API faked (Fixtures\ContosoTerraformExport.ps1)
    - submitted, answered 202, polled to Succeeded or Failed - with the
    resource provider registered or not, and terraform plan faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoTerraformExport.ps1')
    $script:f = Get-AACContosoTerraformExport
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
}

Describe 'Azure Admin Console - Terraform export layout' {
    It 'splits HCL into top-level blocks, ignoring braces in strings, comments and heredocs' {
        $blocks = InModuleScope 'Azure.Admin.Console' {
            Split-AACHclBlock -Text "# a { comment`nresource `"a`" `"b`" {`n  x = `"}`" // }`n  y = <<EOT`n}`nEOT`n}`n/* { */`nprovider `"azurerm`" {`n  features {}`n}`n"
        }
        @($blocks | ForEach-Object { "$($_.Type) $($_.Labels -join '.')" }) | Should -Be @('resource a.b', 'provider azurerm')
        $blocks[0].Text | Should -BeLike 'resource "a" "b" {*EOT*}'
    }

    It 'lays the azurerm and azapi exports out as one module: one terraform block, the providers, the resources, the imports' {
        $layout = InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $script:f } {
            param($F)
            ConvertTo-AACTerraformFile -Primary $F.AzureRm -Fallback $F.AzApi -PrimaryProvider azurerm -SubscriptionId $F.Sub
        }
        @($layout.Files.Keys) | Should -Be @('terraform.tf', 'providers.tf', 'main.tf', 'azapi.tf', 'import.tf')
        $layout.Files['terraform.tf'] | Should -Be "terraform {`n  required_providers {`n    azurerm = {`n      source  = `"azurerm`"`n      version = `"4.80.0`"`n    }`n    azapi = {`n      source  = `"Azure/azapi`"`n      version = `"2.5.0`"`n    }`n  }`n}`n"
        $layout.Files['providers.tf'] | Should -Match "provider `"azurerm`" \{\n  subscription_id = `"$($script:f.Sub)`"\n  features \{\}"
        $layout.Files['main.tf'] | Should -Not -Match 'terraform \{|provider '
        $layout.Files['azapi.tf'] | Should -BeLike '*azapi_resource*EOT*'
        @($layout.Imports | ForEach-Object { "$($_.Provider) $($_.File) $($_.Address)" }) | Should -Be @('azurerm main.tf azurerm_resource_group.res-0', 'azurerm main.tf azurerm_virtual_network.res-1', 'azapi azapi.tf azapi_resource.res-azapi-0')
    }
}

Describe 'Azure Admin Console - Terraform export batches merged' {
    It 'keeps a resource two batches both returned once, and points references to the other copy at it' {
        $vnet = $script:f.Vnet
        $one = @{ configuration = "resource `"azurerm_virtual_network`" `"res-b1-0`" {`n  name = `"vnet-app`"`n}`n"; import = "import {`n  id = `"$vnet`"`n  to = azurerm_virtual_network.res-b1-0`n}`n" }
        $two = @{
            configuration = "resource `"azurerm_virtual_network`" `"res-b2-0`" {`n  name = `"vnet-app`"`n}`nresource `"azurerm_subnet`" `"res-b2-1`" {`n  virtual_network_name = azurerm_virtual_network.res-b2-0.name`n  depends_on = [azurerm_virtual_network.res-b2-0]`n}`n"
            import        = "import {`n  id = `"$vnet`"`n  to = azurerm_virtual_network.res-b2-0`n}`nimport {`n  id = `"$vnet/subnets/snet-a`"`n  to = azurerm_subnet.res-b2-1`n}`n"
        }
        $layout = InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $one; B = $two } {
            param($A, $B)
            ConvertTo-AACTerraformFile -Source @(@{ Result = $A; Provider = 'azurerm'; File = 'main.tf' }, @{ Result = $B; Provider = 'azurerm'; File = 'main.tf' })
        }
        $layout.Duplicates | Should -Be 1
        @($layout.Imports | ForEach-Object { $_.Address }) | Should -Be @('azurerm_virtual_network.res-b1-0', 'azurerm_subnet.res-b2-1')
        $layout.Files['main.tf'] | Should -Not -Match 'res-b2-0'
        $layout.Files['main.tf'] | Should -Match 'virtual_network_name = azurerm_virtual_network\.res-b1-0\.name'
        $layout.Files['main.tf'] | Should -Match 'depends_on = \[azurerm_virtual_network\.res-b1-0\]'
    }
}

Describe 'Azure Admin Console - Export-AACTerraform' {
    BeforeEach {
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
        $script:other = '22222222-2222-2222-2222-222222222222'
        $script:http = @{ Posts = [System.Collections.Generic.List[hashtable]]::new(); Polls = @{}; Registered = $true; Registrations = 0; Fail = $false }
        $script:out = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('n'))
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith {
            $ids = if ($SubscriptionId) { @($SubscriptionId) } else { @($script:f.Sub) }
            @{ Ids = $ids; GraphScope = @(); Names = @{ $script:f.Sub = 'sub-prod'; $script:other = 'sub-dev' }; Label = "$($ids.Count) subscription(s)" }
        }
        # The resource IDs Resource Graph counts before an export (-BatchSize, the advice).
        $script:sized = @()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{ groups = @(@{ name = 'rg-app'; subscriptionId = $script:f.Sub }, @{ name = 'rg-data'; subscriptionId = $script:f.Sub }) }
            foreach ($key in @($Query.Keys | Where-Object { $_ -like 'j*' })) { $rows[$key] = @($script:sized | ForEach-Object { @{ id = $_ } }) }
            @{ Errors = @{}; Rows = $rows }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith {
            $answer = { param([int] $Status, $Body, [hashtable] $Headers = @{}) @{ Status = $Status; Content = $(if ($null -eq $Body) { '' } else { ConvertTo-Json -InputObject $Body -Depth 20 }); Headers = $Headers } }
            if ($Uri -match '/providers/Microsoft\.AzureTerraform\?api-version') { return (& $answer 200 @{ registrationState = $(if ($script:http.Registered) { 'Registered' } else { 'NotRegistered' }) }) }
            if ($Uri -match '/providers/Microsoft\.AzureTerraform/register') { $script:http.Registrations++; $script:http.Registered = $true; return (& $answer 200 @{ registrationState = 'Registering' }) }
            if ($Method -eq 'Post' -and $Uri -match '/exportTerraform\?api-version=2026-09-01-preview') {
                $script:http.Posts.Add((ConvertFrom-Json -InputObject $Body -AsHashtable))
                return (& $answer 202 $null @{ 'Azure-AsyncOperation' = "https://management.azure.com/subscriptions/x/providers/Microsoft.AzureTerraform/operationStatuses/op$($script:http.Posts.Count)?api-version=2026-09-01-preview"; 'Retry-After' = '1' })
            }
            $op = [regex]::Match($Uri, 'operationStatuses/op(\d+)')
            if ($op.Success) {
                $n = [int]$op.Groups[1].Value
                $script:http.Polls[$n] = 1 + [int]$script:http.Polls[$n]
                if ($script:http.Polls[$n] -eq 1) { return (& $answer 200 @{ status = 'InProgress'; percentComplete = 40 }) }
                if ($script:http.Fail) { return (& $answer 200 @{ status = 'Failed'; error = @{ code = 'NoResourceFound'; message = 'No resource matched.' } }) }
                $properties = if ($script:http.Posts[$n - 1].targetProvider -eq 'azapi') { $script:f.AzApi } else { $script:f.AzureRm }
                return (& $answer 200 @{ status = 'Succeeded'; name = "op$n"; properties = $properties })
            }
            throw "Unexpected call: $Method $Uri"
        }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'exports a resource group: submitted, polled to Succeeded, written as a folder, what was skipped listed' {
        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoDisplay
        $script:http.Posts.Count | Should -Be 1
        $body = $script:http.Posts[0]
        "$($body.type) $($body.resourceGroupName) $($body.targetProvider) $($body.maskSensitive) $($body.fullProperties) $($body.namePattern)" | Should -Be 'ExportResourceGroup rg-app azurerm True True res-'
        "$($result.Status) $($result.Exported) $($result.Skipped) $($result.Errors) $($result.OperationId)" | Should -Be 'Partial 2 1 1 op1'
        $result.PSObject.TypeNames | Should -Contain 'AAC.TerraformExport'
        @(Get-ChildItem -LiteralPath $script:out -File | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('export.json', 'import.tf', 'main.tf', 'providers.tf', 'terraform.tf')
        (Get-Content -LiteralPath (Join-Path $script:out 'export.json') -Raw | ConvertFrom-Json).skippedResources | Should -Be $script:f.Grafana
        @($result.Resources | ForEach-Object { "$($_.Status) | $($_.Address) | $($_.ResourceType) | $($_.Name)" }) | Should -Be @(
            'Exported | azurerm_resource_group.res-0 | Microsoft.Resources/resourceGroups | rg-app'
            'Exported | azurerm_virtual_network.res-1 | Microsoft.Network/virtualNetworks | vnet-app'
            'Skipped |  | Microsoft.Dashboard/grafana | amg-app'
            'Error |  | Microsoft.Network/virtualNetworks | vnet-app'
        )
        ($result.Resources | Where-Object Status -EQ 'Skipped').Note | Should -BeLike '*-FallbackToAzApi*'
    }

    It 'exports several resource groups in one query, with their child resources, and maps the switches to the request' {
        $null = Export-AACTerraform -ResourceGroupName rg-app, rg-data -Path $script:out -Include RoleAssignment, Lock, ManagedResource -Exclude 'microsoft.insights' -ExcludeType azurerm_network_watcher -NamePrefix 'app-' -Compact -IncludeSensitive -NoDisplay
        $body = $script:http.Posts[0]
        "$($body.type) | $($body.query) | $($body.recursive) | $($body.includeResourceGroup)" | Should -Be "ExportQuery | resourceGroup in~ ('rg-app', 'rg-data') | True | True"
        "$($body.includeExtensions -join ',') | $($body.includeManagedResource) | $($body.excludeAzureResource) | $($body.excludeTerraformResource) | $($body.namePattern) | $($body.fullProperties) | $($body.maskSensitive)" | Should -Be 'role-assignments,locks | True | microsoft.insights | azurerm_network_watcher | app- | False | False'
    }

    It 'exports what azurerm skipped again with azapi (-FallbackToAzApi), into azapi.tf' {
        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -FallbackToAzApi -NoDisplay
        $script:http.Posts.Count | Should -Be 2
        $again = $script:http.Posts[1]
        "$($again.type) $($again.targetProvider) $($again.namePattern) $($again.resourceIds)" | Should -Be "ExportResource azapi res-azapi- $($script:f.Grafana)"
        "$($result.Exported) $($result.Skipped)" | Should -Be '3 0'
        Test-Path -LiteralPath (Join-Path $script:out 'azapi.tf') | Should -BeTrue
        ($result.Resources | Where-Object Provider -EQ 'azapi').Address | Should -Be 'azapi_resource.res-azapi-0'
    }

    It 'takes resource IDs from the pipeline, a folder per subscription' {
        $results = @(@([pscustomobject]@{ ResourceId = $script:f.Vnet }, [pscustomobject]@{ Id = "/subscriptions/$($script:other)/resourceGroups/rg-dev" }, $script:f.Vnet) | Export-AACTerraform -Path $script:out -Recurse -NoDisplay)
        $script:http.Posts.Count | Should -Be 2
        "$($script:http.Posts[0].type) $($script:http.Posts[0].resourceIds -join ',') $($script:http.Posts[0].recursive)" | Should -Be "ExportResource $($script:f.Vnet) True"
        @($results | ForEach-Object { Split-Path -Path $_.Path -Leaf }) | Should -Be @('sub-prod', 'sub-dev')
    }

    It 'says when the resource provider isn''t registered - and registers it with -RegisterProvider, never under -WhatIf' {
        $script:http.Registered = $false
        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoDisplay
        "$($result.Status) | $($result.Message)" | Should -BeLike 'Failed | The Microsoft.AzureTerraform resource provider isn''t registered on sub-prod (NotRegistered). Run again with -RegisterProvider*'
        $script:http.Posts.Count | Should -Be 0

        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -RegisterProvider -WhatIf -NoDisplay
        "$($result.Status) $($script:http.Registrations)" | Should -Be 'Failed 0'

        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -RegisterProvider -Confirm:$false -NoDisplay
        "$($result.Status) $($script:http.Registrations)" | Should -Be 'Partial 1'
    }

    It 'reports a failed export with Azure''s reason, and won''t overwrite Terraform files without -Force' {
        $script:http.Fail = $true
        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoDisplay
        "$($result.Status) | $($result.Message)" | Should -Be "Failed | Azure couldn't finish the operation - NoResourceFound: No resource matched."

        $script:http.Fail = $false
        $null = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoDisplay
        { Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoDisplay } | Should -Throw "*won't overwrite the Terraform files*"
        { Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -Force -NoDisplay } | Should -Not -Throw
    }

    It 'says when a resource group isn''t found' {
        { Export-AACTerraform -ResourceGroupName rg-missing -Path $script:out -NoDisplay } | Should -Throw "*found no resource group named 'rg-missing'*"
    }

    It 'proves the export with terraform plan (-Plan): imports, and what Terraform would still change' {
        $fake = Join-Path -Path $TestDrive -ChildPath 'terraform.exe'
        Set-Content -LiteralPath $fake -Value ''
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACTerraformCli -MockWith {
            if ($Argument[0] -eq 'show') { return @{ ExitCode = 0; Output = $script:f.PlanJson; Error = '' } }
            @{ ExitCode = 0; Output = ''; Error = '' }
        }
        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -Plan -TerraformPath $fake -NoDisplay
        "$($result.Plan.Ran) $($result.Plan.Import) $(@($result.Plan.Changes).Count) $($result.Plan.Clean)" | Should -Be 'True 2 1 False'
        $result.Plan.Changes[0].Address | Should -Be 'azurerm_virtual_network.res-1'
        Test-Path -LiteralPath (Join-Path $script:out 'plan.json') | Should -BeTrue
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACTerraformCli -Times 4 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACTerraformCli -ParameterFilter { $Argument[0] -eq 'plan' -and $Environment['ARM_SUBSCRIPTION_ID'] -eq $script:f.Sub }

        { Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -Force -Plan -TerraformPath (Join-Path $TestDrive 'nowhere.exe') -NoDisplay } | Should -Throw '*found no terraform CLI*'
    }

    It 'stops at the terraform step that failed, with its reason' {
        $fake = Join-Path -Path $TestDrive -ChildPath 'terraform.exe'
        Set-Content -LiteralPath $fake -Value ''
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACTerraformCli -MockWith {
            if ($Argument[0] -eq 'plan') { return @{ ExitCode = 1; Output = ''; Error = "Error: building account: could not acquire access token`n" } }
            @{ ExitCode = 0; Output = ''; Error = '' }
        }
        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -Plan -TerraformPath $fake -NoDisplay
        "$($result.Plan.Ran) | $($result.Plan.Step) | $($result.Plan.Message)" | Should -Be 'False | plan | terraform plan failed: Error: building account: could not acquire access token'
    }

    It 'shows the export at the prompt, and writes the CSV and HTML report' {
        $text = (& $script:capture { Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoPaging }).Text
        $text | Should -Match 'Terraform export'
        $text | Should -Match '2 resource\(s\) exported to 1 folder\(s\) in \d+:\d\d; 1 skipped, 1 error\(s\)'
        $text | Should -Match 'Exporting resource group rg-app from sub-prod \(0 resources\) - done, \d+:\d\d'
        $text | Should -Match 'azurerm_virtual_network\.res-1'
        $text | Should -Match '-FallbackToAzApi exports them with the azapi provider'

        $csv = Join-Path -Path $TestDrive -ChildPath 'tf.csv'; $html = Join-Path -Path $TestDrive -ChildPath 'tf.html'
        $null = & $script:capture { Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -Force -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 4
        Get-Content -LiteralPath $html -Raw | Should -Match 'azurerm_resource_group\.res-0'
    }

    It 'splits a large export into batches (-BatchSize) that run at once, children left to their parents, and merges them' {
        $vnets = @(1..119 | ForEach-Object { "$($script:f.Rg)/providers/Microsoft.Network/virtualNetworks/vnet-$_" })
        # A child of a listed parent: exported with it (recursive), so not in a batch of its own.
        $script:sized = @($vnets) + "$($script:f.Rg)/providers/Microsoft.Network/virtualNetworks/vnet-1/subnets/snet-a"
        $result = Export-AACTerraform -ResourceGroupName rg-app -BatchSize 50 -ThrottleLimit 2 -Path $script:out -NoDisplay
        @($script:http.Posts | ForEach-Object { "$($_.type) $($_.namePattern) $(@($_.resourceIds).Count) $($_.recursive)" }) | Should -Be @(
            'ExportResource res-b1- 50 True'
            'ExportResource res-b2- 50 True'
            'ExportResource res-b3- 19 True'
            'ExportResource res-rg- 1 False'
        )
        $script:http.Posts[3].resourceIds | Should -Be $script:f.Rg
        # Every batch answers with the same two resources: kept once, the rest counted as duplicates.
        "$($result.Status) $($result.Exported) $($result.Batches) $($result.Duplicates) $($result.Planned)" | Should -Be 'Partial 2 4 6 120'
        (Get-Content -LiteralPath (Join-Path $script:out 'export.json') -Raw | ConvertFrom-Json).status | Should -Be 'Succeeded'
    }

    It 'advises on a large export: -BatchSize, and the types most often left out' {
        $script:sized = @(1..119 | ForEach-Object { "$($script:f.Rg)/providers/Microsoft.Compute/disks/disk-$_" }) + "$($script:f.Rg)/providers/Microsoft.Network/networkWatchers/nw-uksouth"
        $text = (& $script:capture { Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoPaging }).Text
        $text | Should -Match '120 resources: a large export takes several minutes'
        $text | Should -Match '-BatchSize 50 splits it'
        $text | Should -Match '-ExcludeType azurerm_network_watcher'
    }

    It 'leaves an export still running at -TimeoutMinutes for -Resume, which collects it without exporting again' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmOperationBatch -MockWith {
            $results = [ordered]@{}
            foreach ($r in $Request) {
                $url = 'https://management.azure.com/subscriptions/x/providers/Microsoft.AzureTerraform/operationStatuses/op7?api-version=2026-09-01-preview'
                & $OnSubmitted $r.Key $url
                $results[$r.Key] = @{ Succeeded = $false; TimedOut = $true; Error = "Azure didn't finish within 30 minute(s)."; OperationUrl = $url; Result = $null }
            }
            $results
        }
        $result = Export-AACTerraform -ResourceGroupName rg-app -Path $script:out -NoDisplay
        "$($result.Status) | $($result.Message)" | Should -BeLike "Running | Still running after 30 minute(s). Export-AACTerraform -Resume -Path '*' collects it*"
        $saved = Get-Content -LiteralPath (Join-Path $script:out 'export.json') -Raw | ConvertFrom-Json
        "$($saved.status) $($saved.operations[0].url -match 'op7')" | Should -Be 'InProgress True'
        @(Get-ChildItem -LiteralPath $script:out -Filter '*.tf').Count | Should -Be 0
    }

    It 'resumes from export.json: polls the saved operation, writes the folder' {
        $null = New-Item -ItemType Directory -Path $script:out
        # What a run stopped with Ctrl+C leaves: the operation Azure accepted (op1), and one never submitted.
        $script:http.Posts.Add(@{ targetProvider = 'azurerm' })
        $manifest = [ordered]@{ status = 'InProgress'; startedAt = [datetime]::UtcNow.AddMinutes(-7).ToString('o'); subscriptionId = $script:f.Sub; subscription = 'sub-prod'; label = 'resource group rg-app'; resources = 2
            options = [ordered]@{ provider = 'azurerm'; fallbackToAzApi = $false; compact = $false; includeSensitive = $false; namePrefix = 'res-'; batchSize = 0; apiVersion = '2026-09-01-preview' }
            operations = @([ordered]@{ key = '1/1'; phase = 'primary'; part = '1'; url = 'https://management.azure.com/subscriptions/x/providers/Microsoft.AzureTerraform/operationStatuses/op1?api-version=2026-09-01-preview'; request = @{ type = 'ExportResourceGroup'; resourceGroupName = 'rg-app' } }) }
        Set-Content -LiteralPath (Join-Path $script:out 'export.json') -Value (ConvertTo-Json -InputObject $manifest -Depth 10)
        $result = Export-AACTerraform -Resume -Path $script:out -NoDisplay
        $script:http.Posts.Count | Should -Be 1 -Because 'nothing is submitted again'
        "$($result.Status) $($result.Exported) $($result.Duration.TotalMinutes -ge 7)" | Should -Be 'Partial 2 True'
        Test-Path -LiteralPath (Join-Path $script:out 'main.tf') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $script:out 'export.json') -Raw | ConvertFrom-Json).status | Should -Be 'Succeeded'
        { Export-AACTerraform -Resume -Path $script:out -NoDisplay } | Should -Throw '*found no export in progress*'
    }
}

Describe 'Azure Admin Console - long-running operations side by side' {
    BeforeEach {
        $script:log = [System.Collections.Generic.List[string]]::new()
        $script:polls = @{}
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith {
            if ($Method -eq 'Post') {
                $n = ($Body | ConvertFrom-Json).n
                $script:log.Add("submit $n")
                if ($n -eq 4) { $script:log.Add('done 4'); return @{ Status = 200; Content = '{"status":"Succeeded","name":"now"}'; Headers = @{} } }
                return @{ Status = 202; Content = ''; Headers = @{ 'Azure-AsyncOperation' = "https://x/op$n"; 'Retry-After' = "$n" } }
            }
            $n = [int]([regex]::Match($Uri, 'op(\d+)').Groups[1].Value)
            $script:polls[$n] = 1 + [int]$script:polls[$n]
            if ($n -eq 5) { $script:log.Add('done 5'); $e = [System.Exception]::new('Not found'); $e.Data['StatusCode'] = 404; throw $e }
            if ($script:polls[$n] -lt 2) { return @{ Status = 200; Content = '{"status":"Running"}'; Headers = @{ 'Retry-After' = '1' } } }
            $script:log.Add("done $n")
            if ($n -eq 3) { return @{ Status = 200; Content = '{"status":"Failed","error":{"code":"Boom","message":"It broke."}}'; Headers = @{} } }
            @{ Status = 200; Content = "{`"status`":`"Succeeded`",`"name`":`"op$n`"}"; Headers = @{} }
        }
    }

    It 'runs at most -ThrottleLimit at once, and gives each its own outcome' {
        $answers = InModuleScope 'Azure.Admin.Console' {
            Invoke-AACArmOperationBatch -Request @(1..5 | ForEach-Object { @{ Key = "k$_"; Uri = '/x'; Body = @{ n = $_ } } }) -ThrottleLimit 2
        }
        # Never more than two submitted and not yet done.
        $open = 0; $most = 0
        foreach ($line in $script:log) { if ($line -like 'submit*') { $open++ } else { $open-- }; $most = [Math]::Max($most, $open) }
        $most | Should -BeLessOrEqual 2
        @($answers.Keys | ForEach-Object { "$_ $($answers[$_].Succeeded)" }) | Sort-Object | Should -Be @('k1 True', 'k2 True', 'k3 False', 'k4 True', 'k5 False')
        $answers['k3'].Error | Should -Be "Azure couldn't finish the operation - Boom: It broke."
        $answers['k4'].Result.name | Should -Be 'now' -Because 'a 200 at once needs no polling'
        $answers['k5'].Error | Should -BeLike 'Azure no longer has this operation*'
    }

    It 'polls an operation submitted earlier instead of submitting it again' {
        $answers = InModuleScope 'Azure.Admin.Console' { Invoke-AACArmOperationBatch -Request @(@{ Key = 'k'; OperationUrl = 'https://x/op9' }) }
        "$($answers['k'].Succeeded) $($answers['k'].Result.name)" | Should -Be 'True op9'
        @($script:log | Where-Object { $_ -like 'submit*' }).Count | Should -Be 0
    }
}
