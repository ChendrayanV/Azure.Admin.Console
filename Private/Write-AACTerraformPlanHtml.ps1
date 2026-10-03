function Write-AACTerraformPlanHtml {
    <#
    .SYNOPSIS
        Writes Get-AACTerraformPlan's result as an interactive HTML report:
        tiles and charts that filter a table of the resource changes, one of
        every attribute change, the outputs and what changed outside
        Terraform.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Plan,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Plan.Stats
    $actionTones = @{ Create = 'good'; Update = 'warn'; Replace = 'violet'; Delete = 'bad'; Read = 'info'; Import = 'info'; Move = 'info'; Forget = 'neutral'; NoOp = 'neutral' }
    $changeTones = @{ Added = 'good'; Removed = 'bad'; Modified = 'warn'; 'Known after apply' = 'neutral'; Reordered = 'info'; Reformatted = 'info' }
    $resources = @($Plan.Selected | Where-Object { $_.Source -eq 'Plan' -and $_.Mode -ne 'output' })
    $outputs = @($Plan.Selected | Where-Object { $_.Mode -eq 'output' })
    $drift = @($Plan.Selected | Where-Object { $_.Source -eq 'Drift' })
    $attributes = [System.Collections.Generic.List[object]]::new()
    foreach ($change in $resources) { $attributes.AddRange([object[]]$change.Attributes) }

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Create; Label = 'to create'; Tone = 'good'; Table = 'resources'; Filters = @{ Action = 'Create' } }
        @{ Value = '{0:N0}' -f $stats.Update; Label = 'to update in place'; Tone = 'warn'; Table = 'resources'; Filters = @{ Action = 'Update' } }
        @{ Value = '{0:N0}' -f $stats.Replace; Label = 'to replace'; Tone = 'violet'; Table = 'resources'; Filters = @{ Action = 'Replace' } }
        @{ Value = '{0:N0}' -f $stats.Delete; Label = 'to delete'; Tone = $(if ($stats.Delete) { 'bad' } else { 'good' }); Table = 'resources'; Filters = @{ Action = 'Delete' } }
        @{ Value = '{0:N0}' -f ($stats.Import + $stats.Move); Label = 'to import or move'; Tone = 'info'; Table = 'resources' }
        @{ Value = '{0:N0}' -f $stats.Forced; Label = 'attributes forcing replacement'; Tone = $(if ($stats.Forced) { 'bad' } else { 'neutral' }); Table = 'attributes'; Filters = @{ ForcesReplacement = 'true' } }
        @{ Value = '{0:N0}' -f $stats.Drift; Label = 'changed outside Terraform'; Tone = $(if ($stats.Drift) { 'warn' } else { 'neutral' }); Table = 'drift' }
    )
    $charts = @(
        @{ Title = 'Resources by action'; Kind = 'donut'; CenterLabel = 'resources'; Table = 'resources'; Column = 'Action'; Items = @($resources | Group-Object Action | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $actionTones[$_.Name] } }) }
        @{ Title = 'Attribute changes'; Kind = 'donut'; CenterLabel = 'attributes'; Table = 'attributes'; Column = 'Change'; Items = @($attributes | Group-Object Change | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $changeTones[$_.Name] } }) }
        @{ Title = 'Resource types changing most'; Wide = $true; Tone = 'info'; Table = 'resources'; Column = 'Type'; Items = @($resources | Group-Object Type | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-AACFirst 15 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }) }
    )
    $resourceColumns = @(
        @{ Key = 'Action'; Label = 'Action'; Type = 'badge'; Tones = $actionTones; Facet = $true }
        @{ Key = 'Address'; Label = 'Address'; Type = 'mono' }
        @{ Key = 'Type'; Label = 'Type'; Facet = $true }
        @{ Key = 'ResourceName'; Label = 'Azure name' }
        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
        @{ Key = 'Location'; Label = 'Location'; Facet = $true }
        @{ Key = 'Module'; Label = 'Module'; Facet = $true }
        @{ Key = 'Reason'; Label = 'Why'; Type = 'wide' }
        @{ Key = 'ReplacePaths'; Label = 'Forces replacement'; Type = 'wide' }
        @{ Key = 'AttributeCount'; Label = 'Attributes'; Type = 'number'; Format = 'N0'; Sum = $true }
        @{ Key = 'ChangedAttributes'; Label = 'Changed attributes'; Type = 'wide' }
        @{ Key = 'PreviousAddress'; Label = 'Moved from'; Type = 'mono'; Hidden = $true }
        @{ Key = 'Deposed'; Label = 'Deposed object'; Type = 'mono'; Hidden = $true }
        @{ Key = 'ReplaceOrder'; Label = 'Replace order'; Hidden = $true }
        @{ Key = 'Provider'; Label = 'Provider'; Facet = $true; Hidden = $true }
        @{ Key = 'ResourceId'; Label = 'Resource ID'; Type = 'mono'; Hidden = $true }
    )
    $tables = @(
        @{
            Id = 'resources'; Title = 'Resource changes'; Note = 'Deletes and replacements first. A replacement destroys the resource and creates it again.'; Noun = 'resources'; File = 'terraform-plan-resources'
            Rows = $resources; GroupBy = @('Action', 'Type', 'Module', 'ResourceGroup'); Columns = $resourceColumns
        }
        @{
            Id = 'attributes'; Title = 'Attribute changes'; Note = "Each changed attribute, flattened to a path: tags[`"key`"], a block's [0] or [name=...], {json} inside a JSON string. Sensitive values read '(sensitive)'."; Noun = 'attribute changes'; File = 'terraform-plan-attributes'
            Rows = $attributes.ToArray(); GroupBy = @('Address', 'Action', 'Change', 'Type')
            Columns = @(
                @{ Key = 'Action'; Label = 'Action'; Type = 'badge'; Tones = $actionTones; Facet = $true }
                @{ Key = 'Address'; Label = 'Address'; Type = 'mono'; Facet = $true }
                @{ Key = 'Type'; Label = 'Type'; Facet = $true; Hidden = $true }
                @{ Key = 'ResourceName'; Label = 'Azure name'; Hidden = $true }
                @{ Key = 'Attribute'; Label = 'Attribute'; Type = 'mono' }
                @{ Key = 'Change'; Label = 'Change'; Type = 'badge'; Tones = $changeTones; Facet = $true }
                @{ Key = 'Before'; Label = 'Before'; Type = 'wide' }
                @{ Key = 'After'; Label = 'After'; Type = 'wide' }
                @{ Key = 'ForcesReplacement'; Label = 'Forces replacement'; Type = 'badge'; Tones = @{ 'true' = 'bad'; 'false' = 'neutral' }; Facet = $true }
                @{ Key = 'Sensitive'; Label = 'Sensitive'; Facet = $true; Hidden = $true }
            )
        }
    )
    if ($outputs.Count) {
        $tables += @{
            Id = 'outputs'; Title = 'Outputs'; Noun = 'outputs'; File = 'terraform-plan-outputs'
            Rows = @($outputs | ForEach-Object { $_.Attributes }); GroupBy = @('Action')
            Columns = @(
                @{ Key = 'Action'; Label = 'Action'; Type = 'badge'; Tones = $actionTones; Facet = $true }
                @{ Key = 'Address'; Label = 'Output'; Type = 'mono' }
                @{ Key = 'Attribute'; Label = 'Value path'; Type = 'mono'; Hidden = $true }
                @{ Key = 'Before'; Label = 'Before'; Type = 'wide' }
                @{ Key = 'After'; Label = 'After'; Type = 'wide' }
            )
        }
    }
    $tables += @{
        Id = 'drift'; Title = 'Changed outside Terraform'; Note = 'What changed since the last terraform apply (resource_drift). The plan above already accounts for it.'; Noun = 'resources'; File = 'terraform-plan-drift'
        Rows = $drift; GroupBy = @('Action', 'Type'); Columns = $resourceColumns
    }

    $notices = @(foreach ($text in @($Plan.Notice | Where-Object { $_ })) { @{ Tone = $(if ($text -match 'error|not applyable|incomplete|^Check .* fails') { 'bad' } else { 'info' }); Text = $text } })
    $summary = "Plan: $($stats.ToAdd) to add, $($stats.ToChange) to change, $($stats.ToDestroy) to destroy$(if ($stats.Import) { ", $($stats.Import) to import" })."
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle $summary -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
