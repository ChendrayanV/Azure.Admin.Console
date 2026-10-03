<#
    Unit tests for Get-AACTerraformPlan over a made-up Contoso plan
    (Fixtures\ContosoTerraformPlan.json, in terraform show -json's format):
    the actions and why, attributes flattened to paths, blocks paired by
    name, JSON-encoded strings, what forces a replacement, sensitive values
    kept out of every output, the filters, the files it refuses, the view
    and the exports. No Azure sign-in and no Terraform needed.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:planPath = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoTerraformPlan.json'
    # Values the plan holds in clear text but marks sensitive.
    $script:secrets = 'old-storage-key==', 'OldPa55w0rd!', 'NewPa55w0rd!', 'Pa55w0rd-in-variables'
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
    $script:attribute = {
        param([string] $Address, [string] $Attribute)
        Get-AACTerraformPlan -Path $script:planPath -ExpandAttribute -NoDisplay | Where-Object { $_.Address -eq $Address -and $_.Attribute -eq $Attribute }
    }
}

Describe 'Azure Admin Console - Get-AACTerraformPlan' {
    It 'returns one row per resource and output change, deletes and replacements first, no-ops left out' {
        $rows = @(Get-AACTerraformPlan -Path $script:planPath -NoDisplay)
        $rows[0].PSObject.TypeNames[0] | Should -Be 'AAC.TerraformChange'
        @($rows.Action | Select-Object -First 2) | Should -Be @('Delete', 'Replace')
        @($rows | ForEach-Object Address) | Should -Not -Contain 'azurerm_subnet.app' -Because 'a no-op is not a change'
        @($rows | ForEach-Object Address) | Should -Not -Contain 'output.rg_name'
        @($rows | ForEach-Object Address) | Should -Contain 'output.vault_uri'
        @($rows | Where-Object Source -EQ 'Drift').Count | Should -Be 0 -Because 'drift is returned only with -IncludeDrift'
    }

    It 'maps every action and says why' {
        $rows = @(Get-AACTerraformPlan -Path $script:planPath -Action Create, Update, Replace, Delete, Read, Import, Move, Forget, NoOp -NoDisplay)
        $byAddress = @{}; foreach ($row in $rows) { $byAddress[$row.Address] = $row }
        $byAddress['azurerm_storage_account.logs'].Action | Should -Be 'Replace'
        $byAddress['azurerm_storage_account.logs'].ReplaceOrder | Should -Be 'Destroy then create'
        $byAddress['azurerm_storage_account.logs'].Reason | Should -Be 'a changed attribute forces replacement'
        $byAddress['azurerm_storage_account.logs'].ReplacePaths | Should -Be 'location, network_rules[0].default_action'
        $byAddress['azurerm_log_analytics_workspace.old["weu"]'].Action | Should -Be 'Delete'
        $byAddress['azurerm_log_analytics_workspace.old["weu"]'].Reason | Should -Be 'its for_each key is gone'
        $byAddress['azurerm_log_analytics_workspace.old["weu"]'].Index | Should -Be 'weu'
        $byAddress['azurerm_virtual_network.hub'].Action | Should -Be 'Import'
        $byAddress['azurerm_virtual_network.hub'].Importing | Should -BeTrue
        $byAddress['data.azurerm_client_config.current'].Action | Should -Be 'Read'
        $byAddress['data.azurerm_client_config.current'].Mode | Should -Be 'data'
        $byAddress['azurerm_subnet.app'].Action | Should -Be 'NoOp'
        $byAddress['azurerm_key_vault.main'].Action | Should -Be 'Create'
        $byAddress['module.network.azurerm_network_security_group.web'].Module | Should -Be 'module.network'
    }

    It 'reads the Azure name, resource group, location, ID and provider' {
        $logs = Get-AACTerraformPlan -Path $script:planPath -Address 'azurerm_storage_account.logs' -NoDisplay
        $logs.ResourceName | Should -Be 'stcontosologs'
        $logs.ResourceGroup | Should -Be 'rg-contoso-app'
        $logs.Location | Should -Be 'ukwest' -Because 'the planned location, not the old one'
        $logs.ResourceId | Should -BeLike '*/storageAccounts/stcontosologs'
        $logs.Provider | Should -Be 'azurerm'
    }

    It 'flattens maps and lists of blocks to paths, a block named by its name' {
        $nsg = @(Get-AACTerraformPlan -Path $script:planPath -Address '*network_security_group*' -ExpandAttribute -NoDisplay)
        $nsg[0].PSObject.TypeNames[0] | Should -Be 'AAC.TerraformAttributeChange'
        ($nsg | Where-Object Attribute -EQ 'security_rule[name=allow-ssh].access').Before | Should -Be 'Allow'
        ($nsg | Where-Object Attribute -EQ 'security_rule[name=allow-ssh].access').After | Should -Be 'Deny'
        @($nsg | Where-Object Attribute -Like 'security_rule[[]name=allow-http].*').Change | Select-Object -Unique | Should -Be 'Added'
        $nsg.Attribute | Should -Not -Contain 'security_rule[name=allow-https].priority' -Because 'an unchanged rule is paired with itself, though its index moved'

        $tag = & $script:attribute 'azurerm_resource_group.app' 'tags["cost.centre"]'
        $tag.Change | Should -Be 'Added'
        $tag.After | Should -Be 'CC-42'
        (& $script:attribute 'azurerm_resource_group.app' 'tags.touched-by').Change | Should -Be 'Removed'
        (& $script:attribute 'azurerm_resource_group.app' 'tags.env') | Should -BeNullOrEmpty -Because 'an update lists only what changes'
    }

    It 'diffs inside a JSON-encoded string, ignoring its spacing' {
        $rows = @(Get-AACTerraformPlan -Path $script:planPath -Address 'azurerm_policy_definition.tags' -ExpandAttribute -NoDisplay)
        $rows.Count | Should -Be 1
        $rows[0].Attribute | Should -Be 'policy_rule{json}.then.effect'
        $rows[0].Before | Should -Be 'audit'
        $rows[0].After | Should -Be 'deny'
    }

    It 'marks the attributes that force a replacement, nested ones included' {
        $forced = @(Get-AACTerraformPlan -Path $script:planPath -ExpandAttribute -NoDisplay | Where-Object ForcesReplacement)
        @($forced.Attribute | Sort-Object) | Should -Be @('location', 'network_rules[0].default_action')
        (& $script:attribute 'azurerm_storage_account.logs' 'account_replication_type').ForcesReplacement | Should -BeFalse
    }

    It 'lists every attribute of a create and a delete, with values known after apply' {
        $vault = @(Get-AACTerraformPlan -Path $script:planPath -Address 'azurerm_key_vault.main' -ExpandAttribute -NoDisplay)
        $vault.Attribute | Should -Contain 'sku_name'
        ($vault | Where-Object Attribute -EQ 'purge_protection_enabled').After | Should -Be 'true'
        ($vault | Where-Object Attribute -EQ 'vault_uri').After | Should -Be '(known after apply)'
        $vault.Attribute | Should -Not -Contain 'tags' -Because 'empty maps and lists are left out'
        $workspace = @(Get-AACTerraformPlan -Path $script:planPath -Action Delete -ExpandAttribute -NoDisplay)
        ($workspace | Where-Object Attribute -EQ 'retention_in_days').Before | Should -Be '30'
        @($workspace.Change | Select-Object -Unique) | Should -Be @('Removed')
    }

    It 'reports a list in another order as reordered' {
        $soa = @(Get-AACTerraformPlan -Path $script:planPath -Address 'azurerm_dns_zone.main' -ExpandAttribute -NoDisplay)
        $soa.Count | Should -Be 1
        $soa[0].Change | Should -Be 'Reordered'
        $soa[0].Attribute | Should -Be 'soa_record'
    }

    It 'never returns, shows or writes a sensitive value' {
        $csv = Join-Path $TestDrive 'secrets.csv'
        $html = Join-Path $TestDrive 'secrets.html'
        $rows = @(Get-AACTerraformPlan -Path $script:planPath -ExpandAttribute -IncludeDrift -NoDisplay)
        $text = (& $script:capture { Get-AACTerraformPlan -Path $script:planPath -NoPaging }).Text
        $null = & $script:capture { Get-AACTerraformPlan -Path $script:planPath -ExpandAttribute -CsvPath $csv -HtmlPath $html }
        $everything = @(($rows | ConvertTo-Json -Depth 5), $text, (Get-Content -LiteralPath $csv -Raw), (Get-Content -LiteralPath $html -Raw)) -join "`n"
        foreach ($secret in $script:secrets) { $everything | Should -Not -Match ([regex]::Escape($secret)) }
        $password = & $script:attribute 'azurerm_mssql_server.main' 'administrator_login_password'
        $password.Before | Should -Be '(sensitive)'
        $password.After | Should -Be '(sensitive)'
        $password.Sensitive | Should -BeTrue
        (& $script:attribute 'azurerm_storage_account.logs' 'primary_access_key').After | Should -Be '(known after apply)'
        (& $script:attribute 'output.storage_key' 'value').Before | Should -Be '(sensitive)'
    }

    It 'returns the drift with -IncludeDrift' {
        $drift = @(Get-AACTerraformPlan -Path $script:planPath -IncludeDrift -NoDisplay | Where-Object Source -EQ 'Drift')
        $drift.Count | Should -Be 1
        $drift[0].ChangedAttributes | Should -Be 'tags.touched-by'
    }

    It 'filters by action, address and resource type, with wildcards' {
        @(Get-AACTerraformPlan -Path $script:planPath -Action Delete, Replace -NoDisplay | ForEach-Object Address) | Should -Be @('azurerm_log_analytics_workspace.old["weu"]', 'azurerm_storage_account.logs')
        @(Get-AACTerraformPlan -Path $script:planPath -Address 'module.network.*' -NoDisplay).Count | Should -Be 1
        @(Get-AACTerraformPlan -Path $script:planPath -ResourceType 'azurerm_*_server', 'azurerm_key_vault' -NoDisplay | ForEach-Object Address) | Should -Be @('azurerm_mssql_server.main', 'azurerm_key_vault.main')
    }

    It 'keeps the AAC type names of what it returns after drawing the view (-PassThru)' {
        $rows = (& $script:capture { Get-AACTerraformPlan -Path $script:planPath -NoPaging -PassThru }).Output
        @($rows | ForEach-Object { $_.Attributes } | ForEach-Object { $_.PSObject.TypeNames[0] } | Select-Object -Unique) | Should -Be @('AAC.TerraformAttributeChange')
    }

    It 'reads a UTF-16 file (Windows PowerShell''s > redirection)' {
        $utf16 = Join-Path $TestDrive 'utf16.json'
        [System.IO.File]::WriteAllText($utf16, [System.IO.File]::ReadAllText($script:planPath), [System.Text.Encoding]::Unicode)
        @(Get-AACTerraformPlan -Path $utf16 -NoDisplay).Count | Should -Be @(Get-AACTerraformPlan -Path $script:planPath -NoDisplay).Count
    }

    It 'refuses <Name>, and says what to run' -ForEach @(
        @{ Name = 'a binary plan'; Content = 'PK' + [char]3 + [char]4; Message = '*binary Terraform plan*' }
        @{ Name = 'Terraform state'; Content = '{"format_version":"1.0","terraform_version":"1.9.5","values":{}}'; Message = '*Terraform state, not a plan*' }
        @{ Name = 'other JSON'; Content = '{"name":"x"}'; Message = '*no format_version*' }
        @{ Name = 'text that is not JSON'; Content = 'Terraform will perform the following actions:'; Message = '*isn''t valid JSON*' }
    ) {
        $file = Join-Path $TestDrive 'bad.json'
        [System.IO.File]::WriteAllText($file, $Content)
        { $null = & $script:capture { Get-AACTerraformPlan -Path $file -NoDisplay } } | Should -Throw -ExpectedMessage $Message
        { $null = & $script:capture { Get-AACTerraformPlan -Path (Join-Path $TestDrive 'missing.json') -NoDisplay } } | Should -Throw -ExpectedMessage '*No file at*'
    }

    It 'says when the plan errored, and when there are no changes' {
        $plan = Get-Content -LiteralPath $script:planPath -Raw | ConvertFrom-Json -AsHashtable
        $plan['errored'] = $true
        $file = Join-Path $TestDrive 'errored.json'
        $plan | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $file
        (& $script:capture { Get-AACTerraformPlan -Path $file -NoPaging }).Text | Should -Match 'hit an error while planning'

        $quiet = @{ format_version = '1.2'; terraform_version = '1.9.5'; resource_changes = @(); output_changes = @{} }
        $file = Join-Path $TestDrive 'quiet.json'
        $quiet | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $file
        $text = (& $script:capture { Get-AACTerraformPlan -Path $file -NoPaging }).Text
        $text | Should -Match 'Plan: 0 to add, 0 to change, 0 to destroy'
        $text | Should -Match 'No changes'
        @(Get-AACTerraformPlan -Path $file -NoDisplay).Count | Should -Be 0
    }

    It 'shows Terraform''s summary, a table per action with the attribute changes, the outputs and the drift' {
        $text = (& $script:capture { Get-AACTerraformPlan -Path $script:planPath -NoPaging }).Text
        $text | Should -Match 'Plan: 2 to add, 5 to change, 2 to destroy'
        $text | Should -Match '-/\+ Replace'
        $text | Should -Match 'stcontosologs'
        $text | Should -Match 'location: uksouth → ukwest # forces replacement|location: uksouth -> ukwest # forces replacement'
        $text | Should -Match 'security_rule\[name=allow-ssh\]\.access: Allow (→|->) Deny'
        $text | Should -Match 'its for_each key is gone'
        $text | Should -Match 'Outputs'
        $text | Should -Match 'Changed outside Terraform'
        $text | Should -Match '\(sensitive\)'
    }

    It 'writes the rows to CSV - resources, or attributes with -ExpandAttribute - and an HTML report' {
        $csv = Join-Path $TestDrive 'plan.csv'
        $html = Join-Path $TestDrive 'plan.html'
        $null = & $script:capture { Get-AACTerraformPlan -Path $script:planPath -CsvPath $csv -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be @(Get-AACTerraformPlan -Path $script:planPath -NoDisplay).Count
        $rows[0].PSObject.Properties.Name | Should -Contain 'ChangedAttributes'
        $rows[0].PSObject.Properties.Name | Should -Not -Contain 'Attributes'
        Get-Content -LiteralPath $html -Raw | Should -Match 'Plan: 2 to add, 5 to change, 2 to destroy'

        $null = & $script:capture { Get-AACTerraformPlan -Path $script:planPath -ExpandAttribute -CsvPath $csv }
        $attributes = @(Import-Csv -LiteralPath $csv)
        $attributes[0].PSObject.Properties.Name | Should -Contain 'Before'
        $attributes.Attribute | Should -Contain 'policy_rule{json}.then.effect'
    }
}

Describe 'Azure Admin Console - Get-AACTerraformPlan over the sample plans' {
    BeforeAll {
        $script:samples = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/TerraformPlans'
        $script:sample = { param([string] $Name) Join-Path -Path $script:samples -ChildPath $Name }
        $script:all = 'Create', 'Update', 'Replace', 'Delete', 'Read', 'Import', 'Move', 'Forget', 'NoOp'
    }

    It '<File> reads as "Plan: <Add> to add, <Change> to change, <Destroy> to destroy"' -ForEach @(
        @{ File = '01-create-landing-zone.json'; Add = 3; Change = 0; Destroy = 0 }
        @{ File = '02-update-in-place.json'; Add = 0; Change = 2; Destroy = 0 }
        @{ File = '03-replace-every-reason.json'; Add = 5; Change = 0; Destroy = 5 }
        @{ File = '04-delete-every-reason.json'; Add = 0; Change = 0; Destroy = 6 }
        @{ File = '05-data-sources-read.json'; Add = 0; Change = 0; Destroy = 0 }
        @{ File = '06-import-and-move.json'; Add = 0; Change = 2; Destroy = 0 }
        @{ File = '07-drift-outside-terraform.json'; Add = 1; Change = 1; Destroy = 0 }
        @{ File = '08-sensitive-values.json'; Add = 1; Change = 2; Destroy = 0 }
        @{ File = '09-json-encoded-strings.json'; Add = 0; Change = 4; Destroy = 0 }
        @{ File = '10-no-changes.json'; Add = 0; Change = 0; Destroy = 0 }
        @{ File = '11-errored-plan.json'; Add = 1; Change = 0; Destroy = 0 }
        @{ File = '12-deposed-object.json'; Add = 0; Change = 0; Destroy = 1 }
        @{ File = '13-checks.json'; Add = 0; Change = 1; Destroy = 0 }
        @{ File = '14-forget-removed-block.json'; Add = 0; Change = 0; Destroy = 0 }
        @{ File = '15-nested-modules.json'; Add = 2; Change = 1; Destroy = 0 }
    ) {
        $text = (& $script:capture { Get-AACTerraformPlan -Path (& $script:sample $File) -NoPaging }).Text
        $text | Should -Match "Plan: $Add to add, $Change to change, $Destroy to destroy"
    }

    It 'refuses <File>' -ForEach @(
        @{ File = 'invalid-state-not-plan.json'; Message = '*Terraform state, not a plan*' }
        @{ File = 'invalid-not-terraform.json'; Message = '*no format_version*' }
    ) {
        { $null = & $script:capture { Get-AACTerraformPlan -Path (& $script:sample $File) -NoDisplay } } | Should -Throw -ExpectedMessage $Message
    }

    It 'gives every documented action_reason in words' {
        $rows = @('03-replace-every-reason.json', '04-delete-every-reason.json', '05-data-sources-read.json' | ForEach-Object { Get-AACTerraformPlan -Path (& $script:sample $_) -NoDisplay })
        @($rows | Where-Object { $_.Mode -ne 'output' -and -not $_.Reason }).Count | Should -Be 0
        @($rows | Where-Object { $_.Reason -match '_because_|^replace_by_' }).Count | Should -Be 0 -Because 'no reason is left as Terraform''s code'
        ($rows | Where-Object Address -EQ 'azurerm_container_group.worker').Reason | Should -Be 'something in its replace_triggered_by changed'
    }

    It 'tells a deposed object from the live one at the same address' {
        $rows = @(Get-AACTerraformPlan -Path (& $script:sample '12-deposed-object.json') -Action $script:all -NoDisplay)
        $old = $rows | Where-Object Deposed
        $old.Action | Should -Be 'Delete'
        $old.Deposed | Should -Be '00000001'
        $old.ResourceName | Should -Be 'pip-lb-v1'
        $old.Reason | Should -Match 'deposed object'
        (& $script:capture { Get-AACTerraformPlan -Path (& $script:sample '12-deposed-object.json') -NoPaging }).Text | Should -Match 'deposed object 00000001'
    }

    It 'lists the checks that fail, with their messages' {
        $text = (& $script:capture { Get-AACTerraformPlan -Path (& $script:sample '13-checks.json') -NoPaging }).Text
        $text | Should -Match 'Check azurerm_storage_account\.public fails \(fail\): Storage accounts must not allow public network access\.'
        $text | Should -Match "check\.api_health can't be checked until apply"
        $text | Should -Not -Match 'output\.endpoint' -Because 'a check that passes is not listed'
    }

    It 'calls JSON that is only spaced differently Reformatted' {
        $rows = @(Get-AACTerraformPlan -Path (& $script:sample '09-json-encoded-strings.json') -Address 'azurerm_policy_definition.require_tag' -ExpandAttribute -NoDisplay)
        ($rows | Where-Object Attribute -EQ 'policy_rule').Change | Should -Be 'Reformatted'
        $rows.Attribute | Should -Contain 'description'
    }

    It 'gives no "not applyable" warning for a plan with nothing to do' {
        $text = (& $script:capture { Get-AACTerraformPlan -Path (& $script:sample '10-no-changes.json') -NoPaging }).Text
        $text | Should -Match 'No changes'
        $text | Should -Not -Match 'not applyable'
    }

    It 'keeps every sensitive value of 08-sensitive-values.json out of the rows and reports' {
        $path = & $script:sample '08-sensitive-values.json'
        $html = Join-Path $TestDrive 'sensitive.html'
        $csv = Join-Path $TestDrive 'sensitive.csv'
        $null = & $script:capture { Get-AACTerraformPlan -Path $path -ExpandAttribute -CsvPath $csv -HtmlPath $html }
        $everything = @(
            (Get-AACTerraformPlan -Path $path -ExpandAttribute -IncludeDrift -NoDisplay | ConvertTo-Json -Depth 5)
            (& $script:capture { Get-AACTerraformPlan -Path $path -NoPaging }).Text
            (Get-Content -LiteralPath $csv -Raw)
            (Get-Content -LiteralPath $html -Raw)
        ) -join "`n"
        foreach ($secret in 'Var-Secret-0', 'Sql-Secret-1', 'Sql-Secret-2', 'Conn-Secret-3', 'Api-Secret-4', 'Conn-Secret-5', 'Token-Secret-6') {
            $everything | Should -Not -Match ([regex]::Escape($secret))
        }
    }
}

Describe 'Azure Admin Console - Get-AACTerraformPlan with the live progress display' {
    BeforeAll {
        # As at a real terminal: Invoke-AACProgress runs the command's work
        # inside a Spectre.Console live display, in its own scope.
        $script:live = {
            param([scriptblock] $Render)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            $settings.Interactive = [Spectre.Console.InteractionSupport]::Yes
            $settings.Enrichment.UseDefaultEnrichers = $false
            $console = [Spectre.Console.AnsiConsole]::Create($settings)
            $console.Profile.Width = 200
            try { [Spectre.Console.AnsiConsole]::Console = $console; $null = & $Render }
            finally { [Spectre.Console.AnsiConsole]::Console = $real }
            $buffer.ToString()
        }
        $script:drift = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/TerraformPlans/07-drift-outside-terraform.json'
    }

    It 'shows every change - the progress display''s own variables don''t hide the command''s -Action' {
        $text = & $script:live { Get-AACTerraformPlan -Path $script:drift -NoPaging }
        $text | Should -Not -Match 'System\.Action'
        $text | Should -Not -Match 'No changes match'
        $text | Should -Match 'Update in place'
        $text | Should -Match 'temp-rdp-from-anywhere'
        $text | Should -Match 'Changed outside Terraform'
    }

    It 'filters by -Action at a live display' {
        $text = & $script:live { Get-AACTerraformPlan -Path $script:drift -Action Create -NoPaging }
        $text | Should -Match 'Actions: Create'
        $text | Should -Match 'stcontosodiag'
        $text | Should -Not -MatchExactly 'Update in place' -Because 'only the Create table is drawn (the tile reads "update in place")'
    }
}
