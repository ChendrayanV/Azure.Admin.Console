function ConvertTo-AACAssignedPolicyReport {
    <#
    .SYNOPSIS
        Turns Get-AACAssignedPolicy's inventory (ConvertTo-AACAssignedPolicy)
        into the report model Invoke-AACReportOutput writes as HTML and PDF.
    .DESCRIPTION
        One report, read from the top down: a Summary, then a tab each for
        the assignments, the policies in force, what is assigned per resource
        type and every parameter. In the PDF, each tab is a bookmarked chapter.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Inventory,

        [System.Collections.IDictionary] $Detail = [ordered]@{},

        [string] $Source = 'REST'
    )

    $stats = $Inventory.Stats
    $sourceTones = @{ Assigned = 'good'; Default = 'neutral'; 'Not set' = 'warn' }
    $enforcementTones = @{ Default = 'good'; DoNotEnforce = 'warn' }
    $kindTones = @{ Policy = 'info'; PolicySet = 'violet' }
    $scopeTones = @{ 'Management group' = 'violet'; Subscription = 'info'; 'Resource group' = 'good'; Resource = 'warn'; Other = 'neutral' }
    $memberSourceTones = @{ Assigned = 'good'; Initiative = 'violet'; 'Initiative default' = 'neutral'; 'Policy default' = 'neutral'; Expression = 'info'; 'Not set' = 'warn' }
    $impactTones = @{ Blocks = 'bad'; 'Blocks delete' = 'bad'; Audits = 'warn'; Changes = 'info'; Deploys = 'info'; 'Reports only' = 'neutral'; Manual = 'neutral'; Disabled = 'neutral'; Unknown = 'neutral' }
    $coverageTones = @{ Named = 'info'; 'All types' = 'violet'; 'All except some' = 'violet' }
    # Effects are written in any case ('Deny', 'deny'): a tone for each one used.
    $effectTones = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $toneOf = @{ deny = 'bad'; audit = 'info'; auditIfNotExists = 'info'; deployIfNotExists = 'violet'; modify = 'violet'; append = 'violet'; disabled = 'neutral' }
    foreach ($effect in @($Inventory.Members | ForEach-Object Effect | Where-Object { $_ } | Select-Object -Unique)) { if ($toneOf.ContainsKey($effect)) { $effectTones[$effect] = $toneOf[$effect] } }

    $assignments = @($Inventory.Assignments)
    $summaries = @($Inventory.ResourceTypeSummaries)
    $typeRows = @($Inventory.ResourceTypeRows)
    $named = @($summaries | Where-Object Coverage -EQ 'Named')
    $blocking = @($typeRows | Where-Object Impact -In 'Blocks', 'Blocks delete')
    $facts = [ordered]@{}
    foreach ($key in $Detail.Keys) { $facts[$key] = $Detail[$key] }
    $facts['Read from'] = $(if ($Source -eq 'REST') { 'Azure Resource Manager REST APIs' } else { 'Azure Resource Manager REST APIs, with Azure Resource Graph filling the gaps' })

    @{
        Subtitle = 'What Azure Policy is assigned, what each policy does, its parameter values and the resource types it covers'
        Facts    = $facts
        Status   = $(if ($stats.Missing) { 'Warning' } elseif ($stats.Assignments) { 'Success' } else { 'Info' })
        Headline = $(if ($stats.Assignments) { "$($stats.Assignments) assignment(s) put $(@($Inventory.Members | ForEach-Object { "$($_.AssignmentId)|$($_.ReferenceId)|$($_.PolicyId)" } | Select-Object -Unique).Count) polic(ies) in force, naming $($named.Count) resource type(s); $($stats.DoNotEnforce) assignment(s) not enforced" } else { 'No policy assignments were found in this scope.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Assignments; Label = 'assignments'; Tone = 'info'; Table = 'assignments' }
            @{ Value = '{0:N0}' -f $stats.Initiatives; Label = 'initiatives'; Tone = 'violet'; Table = 'assignments'; Filters = @{ DefinitionType = 'PolicySet' } }
            @{ Value = '{0:N0}' -f $stats.Policies; Label = 'single policies'; Tone = 'info'; Table = 'assignments'; Filters = @{ DefinitionType = 'Policy' } }
            @{ Value = '{0:N0}' -f $stats.MemberPolicies; Label = 'policies in initiatives'; Tone = 'violet'; Table = 'policies' }
            @{ Value = '{0:N0}' -f $named.Count; Label = 'resource types named'; Tone = 'info'; Table = 'resourcetypes' }
            @{ Value = '{0:N0}' -f $blocking.Count; Label = 'type and policy pairs that block'; Tone = $(if ($blocking.Count) { 'bad' } else { 'neutral' }); Table = 'typepolicies'; Filters = @{ Impact = 'Blocks' } }
            @{ Value = '{0:N0}' -f $stats.Assigned; Label = 'parameters assigned'; Tone = 'good'; Table = 'parameters'; Filters = @{ ValueSource = 'Assigned' } }
            @{ Value = '{0:N0}' -f $stats.Default; Label = 'at their default'; Tone = 'neutral'; Table = 'parameters'; Filters = @{ ValueSource = 'Default' } }
            @{ Value = '{0:N0}' -f $stats.DoNotEnforce; Label = 'not enforced'; Tone = $(if ($stats.DoNotEnforce) { 'warn' } else { 'good' }); Table = 'assignments'; Filters = @{ EnforcementMode = 'DoNotEnforce' } }
        )
        Notices  = @(@($Inventory.Notice | Where-Object { $_ }) | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Assignments by scope'; Kind = 'donut'; CenterLabel = 'assignments'; Table = 'assignments'; Column = 'ScopeType'; Items = @($assignments | Group-Object ScopeType | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $scopeTones[$_.Name] } }) }
            @{ Title = 'What the policies do'; Kind = 'donut'; CenterLabel = 'policies'; Table = 'typepolicies'; Column = 'Impact'; Items = @($typeRows | Group-Object Impact | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $impactTones[$_.Name] } }) }
            @{ Title = 'Parameter values'; Kind = 'donut'; CenterLabel = 'parameters'; Table = 'parameters'; Column = 'ValueSource'; Items = @($Inventory.Rows | Where-Object ParameterName | Group-Object ValueSource | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $sourceTones[$_.Name] } }) }
            @{ Title = 'Resource types with the most policies'; Wide = $true; Tone = 'info'; Table = 'typepolicies'; Column = 'ResourceType'; Items = @($named | Select-Object -First 15 | ForEach-Object { @{ Label = $_.ResourceType; Value = $_.Policies } }) }
        )
        Tabs     = @(
            @{ Name = 'Assignments'; Badge = $assignments.Count; Tone = 'info'; Note = 'Each assignment: where it is assigned, what it assigns, what that does and whether it is enforced. DoNotEnforce reports but doesn''t deny, change or deploy.' }
            @{ Name = 'Policies in force'; Badge = $stats.Policies + $stats.MemberPolicies; Tone = 'violet'; Note = 'Each initiative opened up: every member policy (and every policy assigned on its own) with its effect and the value each parameter ends up with - from the assignment, the initiative or the policy''s default.' }
            @{ Name = 'Resource types'; Badge = $named.Count; Tone = 'info'; Note = 'What is assigned for each resource type, read from each policy''s rule with its parameters resolved. A policy that names no type applies to every type, so it is listed once under its own heading. This is what the rule targets, not whether such resources exist.' }
            @{ Name = 'Parameters'; Badge = $stats.Parameters; Tone = 'good'; Note = 'One row per assignment and parameter. Effective is the assigned value, else the default. For an initiative, the resource types are those of the member policies using the parameter.' }
        )
        Tables   = @(
            @{
                Id = 'assignments'; Title = 'Policy assignments'; Section = 'Assignments'; Noun = 'assignments'; File = 'policy-assignments'; Rows = $assignments; GroupBy = @('ScopeType', 'ScopeName', 'DefinitionType', 'Category'); NoConsole = $true
                Columns = @(
                    @{ Key = 'AssignmentDisplayName'; Label = 'Assignment'; Pdf = $true }
                    @{ Key = 'ScopeType'; Label = 'Scope type'; Type = 'badge'; Tones = $scopeTones; Facet = $true; Pdf = $true }
                    @{ Key = 'ScopeName'; Label = 'Assigned at'; Facet = $true; Pdf = $true }
                    @{ Key = 'Inherited'; Label = 'Inherited'; Facet = $true }
                    @{ Key = 'DefinitionDisplayName'; Label = 'Definition'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'DefinitionType'; Label = 'Type'; Type = 'badge'; Tones = $kindTones; Facet = $true; Pdf = $true }
                    @{ Key = 'DefinitionDescription'; Label = 'What it does'; Type = 'wide' }
                    @{ Key = 'PolicyType'; Label = 'Built-in or custom'; Facet = $true }
                    @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                    @{ Key = 'EnforcementMode'; Label = 'Enforcement'; Type = 'badge'; Tones = $enforcementTones; Facet = $true; Pdf = $true }
                    @{ Key = 'Members'; Label = 'Policies'; Type = 'number'; Format = 'N0'; Pdf = $true }
                    @{ Key = 'Parameters'; Label = 'Parameters'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Assigned'; Label = 'Assigned'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'ResourceType'; Label = 'Resource types'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Description'; Label = 'Assignment description'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'NotScopes'; Label = 'Excluded scopes'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'AssignmentName'; Label = 'Name'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'AssignmentId'; Label = 'Assignment ID'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'DefinitionId'; Label = 'Definition ID'; Type = 'mono'; Hidden = $true }
                )
            }
            @{
                Id = 'policies'; Title = 'Policies in force'; Section = 'Policies in force'; Noun = 'policy parameters'; File = 'assigned-policy-members'; Rows = @($Inventory.Members); GroupBy = @('AssignmentDisplayName', 'PolicyDisplayName', 'Effect', 'ValueSource'); NoConsole = $true
                Columns = @(
                    @{ Key = 'AssignmentDisplayName'; Label = 'Assignment'; Facet = $true; Pdf = $true }
                    @{ Key = 'PolicySetDisplayName'; Label = 'Initiative'; Facet = $true }
                    @{ Key = 'PolicyDisplayName'; Label = 'Policy'; Type = 'wide'; Facet = $true; Pdf = $true }
                    @{ Key = 'Effect'; Label = 'Effect'; Type = 'badge'; Tones = $effectTones; Facet = $true; Pdf = $true }
                    @{ Key = 'ParameterName'; Label = 'Parameter'; Type = 'mono'; Pdf = $true }
                    @{ Key = 'ValueSource'; Label = 'Value from'; Type = 'badge'; Tones = $memberSourceTones; Facet = $true; Pdf = $true }
                    @{ Key = 'EffectiveValue'; Label = 'Effective value'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'InitiativeValue'; Label = 'In the initiative'; Type = 'wide' }
                    @{ Key = 'PolicyDescription'; Label = 'What it does'; Type = 'wide'; Hidden = $true }
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
            @{
                Id = 'resourcetypes'; Title = 'Resource types'; Section = 'Resource types'; Noun = 'resource types'; File = 'policy-resource-types'; Rows = $summaries; GroupBy = @('Provider', 'Coverage'); NoConsole = $true
                Columns = @(
                    @{ Key = 'ResourceType'; Label = 'Resource type'; Type = 'mono'; Pdf = $true }
                    @{ Key = 'Coverage'; Label = 'Coverage'; Type = 'badge'; Tones = $coverageTones; Facet = $true; Pdf = $true }
                    @{ Key = 'Provider'; Label = 'Provider'; Facet = $true }
                    @{ Key = 'Assignments'; Label = 'Assignments'; Type = 'number'; Format = 'N0'; Pdf = $true }
                    @{ Key = 'Policies'; Label = 'Policies'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'Blocks'; Label = 'Block'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'Audits'; Label = 'Audit'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'Changes'; Label = 'Change or deploy'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'ReportsOnly'; Label = 'Reports only'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'Disabled'; Label = 'Disabled'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'Other'; Label = 'Other'; Type = 'number'; Format = 'N0'; Sum = $true }
                )
            }
            @{
                Id = 'typepolicies'; Title = 'Policies by resource type'; Section = 'Resource types'; Noun = 'policies'; File = 'policies-by-resource-type'; Rows = $typeRows; GroupBy = @('ResourceType', 'Impact', 'AssignmentDisplayName'); NoConsole = $true
                Columns = @(
                    @{ Key = 'ResourceType'; Label = 'Resource type'; Type = 'mono'; Facet = $true; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'What it does'; Type = 'badge'; Tones = $impactTones; Facet = $true; Pdf = $true }
                    @{ Key = 'PolicyDisplayName'; Label = 'Policy'; Type = 'wide'; Facet = $true; Pdf = $true }
                    @{ Key = 'AssignmentDisplayName'; Label = 'Assignment'; Facet = $true; Pdf = $true }
                    @{ Key = 'ScopeName'; Label = 'Assigned at'; Facet = $true; Pdf = $true }
                    @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                    @{ Key = 'EnforcementMode'; Label = 'Enforcement'; Type = 'badge'; Tones = $enforcementTones; Facet = $true }
                    @{ Key = 'Excludes'; Label = 'Except'; Type = 'wide' }
                    @{ Key = 'PolicySetDisplayName'; Label = 'Initiative'; Facet = $true; Hidden = $true }
                    @{ Key = 'PolicyType'; Label = 'Built-in or custom'; Facet = $true; Hidden = $true }
                    @{ Key = 'Category'; Label = 'Category'; Facet = $true; Hidden = $true }
                    @{ Key = 'NotScopes'; Label = 'Excluded scopes'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Provider'; Label = 'Provider'; Facet = $true; Hidden = $true }
                )
            }
            @{
                Id = 'parameters'; Title = 'Parameters'; Section = 'Parameters'; Noun = 'parameters'; File = 'assigned-policy-parameters'; Rows = @($Inventory.Rows); GroupBy = @('AssignmentDisplayName', 'ValueSource', 'ScopeName'); NoConsole = $true
                Columns = @(
                    @{ Key = 'AssignmentDisplayName'; Label = 'Assignment'; Facet = $true; Pdf = $true }
                    @{ Key = 'ScopeName'; Label = 'Assigned at'; Facet = $true; Pdf = $true }
                    @{ Key = 'DefinitionDisplayName'; Label = 'Definition'; Facet = $true; Hidden = $true }
                    @{ Key = 'ParameterName'; Label = 'Parameter'; Type = 'mono'; Pdf = $true }
                    @{ Key = 'ParameterDisplayName'; Label = 'Display name'; Hidden = $true }
                    @{ Key = 'ParameterType'; Label = 'Type'; Facet = $true }
                    @{ Key = 'ValueSource'; Label = 'Value from'; Type = 'badge'; Tones = $sourceTones; Facet = $true; Pdf = $true }
                    @{ Key = 'EffectiveValue'; Label = 'Effective value'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'AssignedValue'; Label = 'Assigned'; Type = 'wide' }
                    @{ Key = 'DefaultValue'; Label = 'Default'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'AllowedValues'; Label = 'Allowed values'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'ResourceType'; Label = 'Resource types'; Type = 'wide' }
                    @{ Key = 'EnforcementMode'; Label = 'Enforcement'; Facet = $true; Hidden = $true }
                    @{ Key = 'DefinitionType'; Label = 'Definition type'; Facet = $true; Hidden = $true }
                    @{ Key = 'Category'; Label = 'Category'; Facet = $true; Hidden = $true }
                    @{ Key = 'AssignmentName'; Label = 'Assignment name'; Type = 'mono'; Hidden = $true }
                )
            }
        )
    }
}
