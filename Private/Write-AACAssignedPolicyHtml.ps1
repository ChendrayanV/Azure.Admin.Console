function Write-AACAssignedPolicyHtml {
    <#
    .SYNOPSIS
        Writes Get-AACAssignedPolicy's inventory as an interactive HTML
        report: tiles and charts that filter a table of the assignments and
        one of every parameter with its default, assigned and effective value.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Inventory,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Inventory.Stats
    $sourceTones = @{ Assigned = 'good'; Default = 'neutral'; 'Not set' = 'warn' }
    $enforcementTones = @{ Default = 'good'; DoNotEnforce = 'warn' }
    $kindTones = @{ Policy = 'info'; PolicySet = 'violet' }
    $scopeTones = @{ 'Management group' = 'violet'; Subscription = 'info'; 'Resource group' = 'good'; Resource = 'warn'; Other = 'neutral' }
    $memberSourceTones = @{ Assigned = 'good'; Initiative = 'violet'; 'Initiative default' = 'neutral'; 'Policy default' = 'neutral'; Expression = 'info'; 'Not set' = 'warn' }
    # Effects are written in any case ('Deny', 'deny'): a tone for each one used.
    $effectTones = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $toneOf = @{ deny = 'bad'; audit = 'info'; auditIfNotExists = 'info'; deployIfNotExists = 'violet'; modify = 'violet'; append = 'violet'; disabled = 'neutral' }
    foreach ($effect in @($Inventory.Members | ForEach-Object Effect | Where-Object { $_ } | Select-Object -Unique)) { if ($toneOf.ContainsKey($effect)) { $effectTones[$effect] = $toneOf[$effect] } }

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Assignments; Label = 'assignments'; Tone = 'info'; Table = 'assignments' }
        @{ Value = '{0:N0}' -f $stats.Initiatives; Label = 'initiatives'; Tone = 'violet'; Table = 'assignments'; Filters = @{ DefinitionType = 'PolicySet' } }
        @{ Value = '{0:N0}' -f $stats.MemberPolicies; Label = 'policies in initiatives'; Tone = 'violet'; Table = 'policies' }
        @{ Value = '{0:N0}' -f $stats.Policies; Label = 'single policies'; Tone = 'info'; Table = 'assignments'; Filters = @{ DefinitionType = 'Policy' } }
        @{ Value = '{0:N0}' -f $stats.Assigned; Label = 'parameters assigned'; Tone = 'good'; Table = 'parameters'; Filters = @{ ValueSource = 'Assigned' } }
        @{ Value = '{0:N0}' -f $stats.Default; Label = 'at their default'; Tone = 'neutral'; Table = 'parameters'; Filters = @{ ValueSource = 'Default' } }
        @{ Value = '{0:N0}' -f $stats.DoNotEnforce; Label = 'not enforced'; Tone = $(if ($stats.DoNotEnforce) { 'warn' } else { 'good' }); Table = 'assignments'; Filters = @{ EnforcementMode = 'DoNotEnforce' } }
    )
    $charts = @(
        @{ Title = 'Assignments by scope'; Kind = 'donut'; CenterLabel = 'assignments'; Table = 'assignments'; Column = 'ScopeType'; Items = @($Inventory.Assignments | Group-Object ScopeType | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $scopeTones[$_.Name] } }) }
        @{ Title = 'Parameter values'; Kind = 'donut'; CenterLabel = 'parameters'; Table = 'parameters'; Column = 'ValueSource'; Items = @($Inventory.Rows | Where-Object ParameterName | Group-Object ValueSource | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $sourceTones[$_.Name] } }) }
        @{ Title = 'Resource types with the most assignments'; Wide = $true; Tone = 'info'; Items = @($stats.ResourceTypes | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Label; Value = $_.Value } }) }
    )
    $tables = @(
        @{
            Id = 'assignments'; Title = 'Policy assignments'; Noun = 'assignments'; File = 'policy-assignments'; Rows = @($Inventory.Assignments); GroupBy = @('ScopeType', 'ScopeName', 'DefinitionType', 'Category')
            Columns = @(
                @{ Key = 'AssignmentDisplayName'; Label = 'Assignment' }
                @{ Key = 'ScopeType'; Label = 'Scope type'; Type = 'badge'; Tones = $scopeTones; Facet = $true }
                @{ Key = 'ScopeName'; Label = 'Assigned at'; Facet = $true }
                @{ Key = 'Inherited'; Label = 'Inherited'; Facet = $true }
                @{ Key = 'DefinitionDisplayName'; Label = 'Definition'; Type = 'wide' }
                @{ Key = 'DefinitionType'; Label = 'Type'; Type = 'badge'; Tones = $kindTones; Facet = $true }
                @{ Key = 'PolicyType'; Label = 'Built-in or custom'; Facet = $true }
                @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                @{ Key = 'EnforcementMode'; Label = 'Enforcement'; Type = 'badge'; Tones = $enforcementTones; Facet = $true }
                @{ Key = 'Members'; Label = 'Policies'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Parameters'; Label = 'Parameters'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'Assigned'; Label = 'Assigned'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'ResourceType'; Label = 'Resource types'; Type = 'wide' }
                @{ Key = 'NotScopes'; Label = 'Excluded scopes'; Type = 'wide'; Hidden = $true }
                @{ Key = 'AssignmentName'; Label = 'Name'; Type = 'mono'; Hidden = $true }
                @{ Key = 'AssignmentId'; Label = 'Assignment ID'; Type = 'mono'; Hidden = $true }
                @{ Key = 'DefinitionId'; Label = 'Definition ID'; Type = 'mono'; Hidden = $true }
            )
        }
        @{
            Id = 'parameters'; Title = 'Parameters'; Note = 'Effective: the assigned value, else the default. Resource types: what the policy (or, in an initiative, the policies using the parameter) applies to.'; Noun = 'parameters'; File = 'assigned-policy-parameters'
            Rows = @($Inventory.Rows); GroupBy = @('AssignmentDisplayName', 'ValueSource', 'ScopeName')
            Columns = @(
                @{ Key = 'AssignmentDisplayName'; Label = 'Assignment'; Facet = $true }
                @{ Key = 'ScopeName'; Label = 'Assigned at'; Facet = $true }
                @{ Key = 'DefinitionDisplayName'; Label = 'Definition'; Facet = $true; Hidden = $true }
                @{ Key = 'ParameterName'; Label = 'Parameter'; Type = 'mono' }
                @{ Key = 'ParameterDisplayName'; Label = 'Display name'; Hidden = $true }
                @{ Key = 'ParameterType'; Label = 'Type'; Facet = $true }
                @{ Key = 'ValueSource'; Label = 'Value from'; Type = 'badge'; Tones = $sourceTones; Facet = $true }
                @{ Key = 'EffectiveValue'; Label = 'Effective value'; Type = 'wide' }
                @{ Key = 'AssignedValue'; Label = 'Assigned'; Type = 'wide' }
                @{ Key = 'DefaultValue'; Label = 'Default'; Type = 'wide' }
                @{ Key = 'AllowedValues'; Label = 'Allowed values'; Type = 'wide'; Hidden = $true }
                @{ Key = 'ResourceType'; Label = 'Resource types'; Type = 'wide' }
                @{ Key = 'EnforcementMode'; Label = 'Enforcement'; Facet = $true; Hidden = $true }
                @{ Key = 'DefinitionType'; Label = 'Definition type'; Facet = $true; Hidden = $true }
                @{ Key = 'Category'; Label = 'Category'; Facet = $true; Hidden = $true }
                @{ Key = 'AssignmentName'; Label = 'Assignment name'; Type = 'mono'; Hidden = $true }
            )
        }
        @{
            Id = 'policies'; Title = 'Policies in force'; Note = 'Each initiative opened up: every member policy (and every policy assigned on its own) with its effect and the value each parameter ends up with - from the assignment, the initiative or the policy''s default.'; Noun = 'policy parameters'; File = 'assigned-policy-members'
            Rows = @($Inventory.Members); GroupBy = @('AssignmentDisplayName', 'PolicyDisplayName', 'Effect', 'ValueSource')
            Columns = @(
                @{ Key = 'AssignmentDisplayName'; Label = 'Assignment'; Facet = $true }
                @{ Key = 'PolicySetDisplayName'; Label = 'Initiative'; Facet = $true }
                @{ Key = 'PolicyDisplayName'; Label = 'Policy'; Type = 'wide'; Facet = $true }
                @{ Key = 'Effect'; Label = 'Effect'; Type = 'badge'; Tones = $effectTones; Facet = $true }
                @{ Key = 'ParameterName'; Label = 'Parameter'; Type = 'mono' }
                @{ Key = 'ValueSource'; Label = 'Value from'; Type = 'badge'; Tones = $memberSourceTones; Facet = $true }
                @{ Key = 'EffectiveValue'; Label = 'Effective value'; Type = 'wide' }
                @{ Key = 'InitiativeValue'; Label = 'In the initiative'; Type = 'wide' }
                @{ Key = 'DefaultValue'; Label = 'Policy default'; Type = 'wide'; Hidden = $true }
                @{ Key = 'AllowedValues'; Label = 'Allowed values'; Type = 'wide'; Hidden = $true }
                @{ Key = 'ResourceType'; Label = 'Resource types'; Type = 'wide' }
                @{ Key = 'ScopeName'; Label = 'Assigned at'; Facet = $true; Hidden = $true }
                @{ Key = 'PolicyType'; Label = 'Built-in or custom'; Facet = $true; Hidden = $true }
                @{ Key = 'Category'; Label = 'Category'; Facet = $true; Hidden = $true }
                @{ Key = 'Groups'; Label = 'Groups'; Type = 'wide'; Hidden = $true }
                @{ Key = 'ReferenceId'; Label = 'Reference ID'; Type = 'mono'; Hidden = $true }
                @{ Key = 'PolicyId'; Label = 'Policy ID'; Type = 'mono'; Hidden = $true }
            )
        }
    )
    $notices = @(@($Inventory.Notice | Where-Object { $_ }) | ForEach-Object { @{ Tone = 'warn'; Text = $_ } })
    $notices += @{ Tone = 'info'; Text = 'Read-only, from Azure Resource Graph (policyresources): the assignments, the definitions and initiatives they assign, and the initiatives'' member policies.' }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Every policy assignment, its parameters and the resource types it applies to' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
