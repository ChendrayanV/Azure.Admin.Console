function Write-AACPolicyAssessmentHtml {
    <#
    .SYNOPSIS
        Writes Invoke-AACPolicyAssessment's report as one interactive HTML page.
    .DESCRIPTION
        Tiles (overall compliance, assignments, non-compliant resources,
        exemptions to look at, findings by severity - each opening its
        table), charts (compliance by subscription and by category, findings
        by area), the management group hierarchy as a tree - each level's
        compliance as a pill, clicking it filters the tables - and the
        tables, under their section in the contents, each collapsible,
        searchable, filterable, groupable and downloadable as CSV:
          Overview     findings, subscriptions, management groups
          Compliance   assignments, by assignment and subscription, by
                       policy, the policies in the initiatives (effect and
                       parameter values), by category
          Exemptions   every exemption, its expiry and status
          Definitions  initiatives, definitions, the managed identities' roles
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Assessment.Stats
    $platform = $Assessment.Audience -ne 'Application'
    $severity = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Info = 'neutral' }
    $ratingTones = @{ Good = 'good'; Warning = 'warn'; Poor = 'bad'; 'No data' = 'neutral' }
    $yesNo = @{ Yes = 'good'; No = 'warn' }
    $flag = @{ Yes = 'warn'; No = 'neutral' }
    $status = @{ Expired = 'bad'; Expiring = 'warn'; 'No expiry' = 'info'; Active = 'good' }
    $col = { param([string] $Key, [string] $Label, [hashtable] $More = @{}) $c = @{ Key = $Key; Label = $Label }; foreach ($k in $More.Keys) { $c[$k] = $More[$k] }; $c }
    $num = @{ Type = 'number' }
    $facet = @{ Facet = $true }
    $tone = { param($Rating) $ratingTones[[string]$Rating] }
    $counts = {
        @((& $col 'CompliancePercent' 'Compliance' @{ Type = 'score' }), (& $col 'Rating' 'Rating' @{ Type = 'badge'; Tones = $ratingTones; Facet = $true }), (& $col 'NonCompliant' 'Non-compliant' @{ Type = 'number'; Tone = 'bad'; Sum = $true }), (& $col 'Compliant' 'Compliant' @{ Type = 'number'; Sum = $true }), (& $col 'Exempt' 'Exempt' @{ Type = 'number'; Sum = $true }), (& $col 'Conflict' 'Conflict' @{ Type = 'number'; Sum = $true }))
    }

    $tiles = @(
        @{ Value = $(if ($null -ne $stats.CompliancePercent) { "$($stats.CompliancePercent)%" } else { '-' }); Label = "resources compliant ($('{0:N0}' -f $stats.Resources) evaluated)"; Tone = (& $tone $stats.Rating); Table = 'policy-subscriptions' }
        @{ Value = '{0:N0}' -f $stats.Assignments; Label = "assignments ($($stats.Initiatives) initiatives, $($stats.Definitions) policies assigned)"; Tone = 'info'; Table = 'policy-assignments' }
        @{ Value = '{0:N0}' -f $stats.NotEnforced; Label = 'assignments not enforced (DoNotEnforce)'; Tone = $(if ($stats.NotEnforced) { 'warn' } else { 'good' }); Table = 'policy-assignments'; Filters = @{ Enforcement = 'DoNotEnforce' } }
        @{ Value = '{0:N0}' -f $stats.NonCompliant; Label = 'non-compliant resources'; Tone = $(if ($stats.NonCompliant) { 'warn' } else { 'good' }); Table = 'policy-policies' }
        @{ Value = '{0:N0}' -f $stats.ExpiringExemptions; Label = "exemptions expired or expiring ($($stats.Exemptions) in all)"; Tone = $(if ($stats.ExpiringExemptions) { 'warn' } else { 'good' }); Table = 'policy-exemptions' }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high-severity findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'policy-findings'; Filters = @{ Severity = 'High' } }
        @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium-severity findings'; Tone = $(if ($stats.Medium) { 'warn' } else { 'good' }); Table = 'policy-findings'; Filters = @{ Severity = 'Medium' } }
    )
    $charts = @(
        if (@($Assessment.Subscriptions | Where-Object { $null -ne $_.CompliancePercent }).Count) { @{ Title = 'Compliance by subscription (%)'; Items = @($Assessment.Subscriptions | Where-Object { $null -ne $_.CompliancePercent } | Select-Object -First 20 | ForEach-Object { @{ Label = $_.Subscription; Value = $_.CompliancePercent; Display = "$($_.CompliancePercent)% ($($_.NonCompliant) non-compliant)"; Tone = (& $tone $_.Rating); Filter = $_.Subscription } }); Table = 'policy-assignment-compliance'; Column = 'Subscription' } }
        if (@($Assessment.Categories | Where-Object { $null -ne $_.CompliancePercent }).Count) { @{ Title = 'Compliance by category (%)'; Items = @($Assessment.Categories | Where-Object { $null -ne $_.CompliancePercent } | Select-Object -First 20 | ForEach-Object { @{ Label = $_.Category; Value = $_.CompliancePercent; Display = "$($_.CompliancePercent)% ($($_.NonCompliant) non-compliant)"; Tone = (& $tone $_.Rating); Filter = $_.Category } }); Table = 'policy-policies'; Column = 'Category' } }
        if (@($Assessment.Findings).Count) { @{ Title = 'Findings by area'; Items = @($Assessment.Findings | Group-Object Area | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'policy-findings'; Column = 'Area'; Tone = 'warn' } }
    )

    $tables = [System.Collections.Generic.List[hashtable]]::new()
    $add = { param([hashtable] $Table) if (@($Table.Rows).Count) { $tables.Add($Table) } }
    & $add @{
        Id = 'policy-findings'; Section = 'Overview'; Title = 'Findings'; Note = 'What to improve: assignments, managed identities, exemptions, definitions and compliance. Most severe first.'; Noun = 'findings'; File = 'policy-findings'; Rows = @($Assessment.Findings); GroupBy = @('Area', 'Finding', 'Severity', 'Scope')
        Columns = @((& $col 'Severity' 'Severity' @{ Type = 'badge'; Tones = $severity; Facet = $true }), (& $col 'Area' 'Area' $facet), (& $col 'Finding' 'Finding' $facet), (& $col 'Item' 'Item'), (& $col 'Scope' 'Scope' $facet), (& $col 'Detail' 'What was found' @{ Type = 'wide' }), (& $col 'Recommendation' 'What to do' @{ Type = 'wide' }), (& $col 'Link' 'Docs' @{ Type = 'link' }), (& $col 'ResourceId' 'ID' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{ Id = 'policy-subscriptions'; Section = 'Overview'; Title = 'Subscriptions'; Noun = 'subscriptions'; File = 'policy-subscriptions'; Rows = @($Assessment.Subscriptions); Columns = @((& $col 'Subscription' 'Subscription' @{ Type = 'resource' }), (& $col 'ManagementGroups' 'Management groups')) + @(& $counts) + @((& $col 'Resources' 'Resources' @{ Type = 'number'; Sum = $true }), (& $col 'Assignments' 'Assignments' $num), (& $col 'Exemptions' 'Exemptions' $num), (& $col 'SubscriptionId' 'ID' @{ Type = 'mono'; Hidden = $true }), $(if ($platform) { & $col 'HiddenTags' 'Hidden tags' @{ Hidden = $true } })) | Where-Object { $_ } }
    & $add @{ Id = 'policy-management-groups'; Section = 'Overview'; Title = 'Management groups'; Note = 'Each management group''s compliance: the subscriptions under it, counted together.'; Noun = 'management groups'; File = 'policy-management-groups'; Rows = @($Assessment.ManagementGroups); Columns = @((& $col 'ManagementGroup' 'Management group'), (& $col 'Parent' 'Parent' $facet), (& $col 'Depth' 'Depth' $num)) + @(& $counts) + @((& $col 'Assignments' 'Assigned here' $num), (& $col 'Subscriptions' 'Subscriptions' $num), (& $col 'Name' 'ID' @{ Type = 'mono' })) }
    & $add @{
        Id = 'policy-assignments'; Section = 'Compliance'; Title = 'Assignments'; Note = 'Each resource counted once, at its worst state; compliance = (compliant + exempt) / all.'; Noun = 'assignments'; File = 'policy-assignments'; Rows = @($Assessment.Assignments | Select-Object -Property * -ExcludeProperty Compliance, PolicyStates, InitiativePolicies, Findings); GroupBy = @('Scope', 'ScopeType', 'Kind', 'Enforcement', 'Category', 'Rating')
        Columns = @((& $col 'Assignment' 'Assignment' @{ Type = 'resource' }), (& $col 'Scope' 'Scope' $facet), (& $col 'ScopeType' 'Scope type' $facet), (& $col 'Definition' 'Assigns' @{ Type = 'wide' }), (& $col 'Kind' 'Kind' $facet), (& $col 'PolicyType' 'Type' $facet), (& $col 'Policies' 'Policies' $num), (& $col 'Category' 'Category' $facet), (& $col 'Enforcement' 'Enforcement' @{ Type = 'badge'; Tones = @{ Default = 'good'; DoNotEnforce = 'warn' }; Facet = $true }), (& $col 'Effect' 'Effect' $facet)) + @(& $counts) + @(
            (& $col 'Resources' 'Resources' @{ Type = 'number'; Sum = $true }), (& $col 'Subscriptions' 'Subscriptions' $num), (& $col 'Exemptions' 'Exemptions' $num), (& $col 'ExcludedScopes' 'Excluded scopes' $num), (& $col 'Overrides' 'Overrides' $num), (& $col 'ResourceSelectors' 'Selectors' $num), (& $col 'NonComplianceMessage' 'Message' @{ Type = 'badge'; Tones = $yesNo; Facet = $true }), (& $col 'Identity' 'Identity' $facet), (& $col 'RolesNeeded' 'Roles needed'), (& $col 'RolesMissing' 'Roles missing' @{ Tone = 'bad' }), (& $col 'Parameters' 'Parameters' @{ Type = 'number'; Hidden = $true }), (& $col 'DefinitionVersion' 'Version' @{ Hidden = $true }), (& $col 'AssignedBy' 'Assigned by' @{ Hidden = $true }), (& $col 'Description' 'Description' @{ Type = 'wide'; Hidden = $true }), $(if ($platform) { & $col 'HiddenMetadata' 'Hidden metadata' @{ Hidden = $true } })) | Where-Object { $_ }
    }
    & $add @{ Id = 'policy-assignment-compliance'; Section = 'Compliance'; Title = 'By assignment and subscription'; Noun = 'rows'; File = 'policy-assignment-compliance'; Rows = @($Assessment.AssignmentCompliance); GroupBy = @('Assignment', 'Subscription', 'Rating'); Columns = @((& $col 'Assignment' 'Assignment' $facet), (& $col 'Subscription' 'Subscription' $facet)) + @(& $counts) + @(& $col 'Resources' 'Resources' @{ Type = 'number'; Sum = $true }) }
    & $add @{ Id = 'policy-policies'; Section = 'Compliance'; Title = 'By policy'; Note = 'Each policy in each assignment (an initiative''s by its reference ID), across the subscriptions in scope.'; Noun = 'policies'; File = 'policy-policies'; Rows = @($Assessment.Policies); GroupBy = @('Assignment', 'Category', 'Effect', 'Rating', 'Groups'); Columns = @((& $col 'Policy' 'Policy' @{ Type = 'wide' }), (& $col 'Assignment' 'Assignment' $facet), (& $col 'ReferenceId' 'Reference'), (& $col 'Effect' 'Effect' $facet), (& $col 'Category' 'Category' $facet), (& $col 'Groups' 'Groups')) + @(& $counts) + @((& $col 'Resources' 'Resources' @{ Type = 'number'; Sum = $true }), (& $col 'Subscriptions' 'Subscriptions' $num), (& $col 'PolicyType' 'Type' $facet)) }
    & $add @{
        Id = 'policy-initiative-policies'; Section = 'Compliance'; Title = 'Policies in the initiatives'; Note = 'Each assigned initiative opened up: its member policies, the effect and the value of each parameter (from the assignment, else the initiative or the policy''s default, as noted), and their compliance - policies with no compliance data too.'; Noun = 'policies'; File = 'policy-initiative-policies'; Rows = @($Assessment.InitiativePolicies); GroupBy = @('Assignment', 'Initiative', 'Effect', 'Category', 'Rating')
        Columns = @((& $col 'Policy' 'Policy' @{ Type = 'wide' }), (& $col 'Assignment' 'Assignment' $facet), (& $col 'Initiative' 'Initiative' $facet), (& $col 'Effect' 'Effect' $facet), (& $col 'Parameters' 'Parameters' @{ Type = 'wide' }), (& $col 'Category' 'Category' $facet)) + @(& $counts) + @((& $col 'Resources' 'Resources' @{ Type = 'number'; Sum = $true }), (& $col 'EffectSource' 'Effect from' @{ Facet = $true; Hidden = $true }), (& $col 'ReferenceId' 'Reference' @{ Hidden = $true }), (& $col 'Groups' 'Groups' @{ Hidden = $true }), (& $col 'PolicyType' 'Type' @{ Facet = $true; Hidden = $true }), (& $col 'Deprecated' 'Deprecated' @{ Type = 'badge'; Tones = $flag; Facet = $true; Hidden = $true }), (& $col 'DefinitionId' 'Definition ID' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{ Id = 'policy-categories'; Section = 'Compliance'; Title = 'By category'; Note = 'From each policy''s metadata.category.'; Noun = 'categories'; File = 'policy-categories'; Rows = @($Assessment.Categories); Columns = @((& $col 'Category' 'Category'), (& $col 'Policies' 'Policies' $num), (& $col 'Assignments' 'Assignments' $num)) + @(& $counts) }
    & $add @{
        Id = 'policy-exemptions'; Section = 'Exemptions'; Title = 'Exemptions'; Note = "Expired first, then expiring, then those with no expiry."; Noun = 'exemptions'; File = 'policy-exemptions'; Rows = @($Assessment.Exemptions); GroupBy = @('Status', 'Category', 'Assignment', 'Scope')
        Columns = @((& $col 'Exemption' 'Exemption' @{ Type = 'resource' }), (& $col 'Status' 'Status' @{ Type = 'badge'; Tones = $status; Facet = $true }), (& $col 'ExpiresOn' 'Expires' @{ Type = 'date' }), (& $col 'DaysLeft' 'Days left' $num), (& $col 'Category' 'Category' $facet), (& $col 'Assignment' 'Assignment' $facet), (& $col 'Policies' 'Policies'), (& $col 'Scope' 'Scope' $facet), (& $col 'ScopeType' 'Scope type' $facet), (& $col 'Description' 'Description' @{ Type = 'wide' }), $(if ($platform) { & $col 'HiddenMetadata' 'Hidden metadata' @{ Hidden = $true } })) | Where-Object { $_ }
    }
    & $add @{
        Id = 'policy-initiatives'; Section = 'Definitions'; Title = 'Initiatives'; Note = $(if ($platform) { 'The initiatives assigned, and every custom initiative.' } else { 'The initiatives assigned.' }); Noun = 'initiatives'; File = 'policy-initiatives'; Rows = @($Assessment.Initiatives); GroupBy = @('PolicyType', 'Category', 'Assigned')
        Columns = @((& $col 'Initiative' 'Initiative' @{ Type = 'resource' }), (& $col 'PolicyType' 'Type' $facet), (& $col 'Category' 'Category' $facet), (& $col 'Version' 'Version'), (& $col 'Policies' 'Policies' $num), (& $col 'Groups' 'Groups' $num), (& $col 'Assignments' 'Assignments' $num), (& $col 'Assigned' 'Assigned' @{ Type = 'badge'; Tones = $yesNo; Facet = $true }), (& $col 'Deprecated' 'Deprecated' @{ Type = 'badge'; Tones = $flag; Facet = $true }), (& $col 'Preview' 'Preview' @{ Type = 'badge'; Tones = $flag; Facet = $true }), (& $col 'DefinedAt' 'Defined at' $facet), (& $col 'Description' 'Description' @{ Type = 'wide'; Hidden = $true }), $(if ($platform) { & $col 'HiddenMetadata' 'Hidden metadata' @{ Hidden = $true } })) | Where-Object { $_ }
    }
    & $add @{
        Id = 'policy-definitions'; Section = 'Definitions'; Title = 'Policy definitions'; Note = $(if ($platform) { 'The policies assigned (directly or in an initiative), and every custom definition.' } else { 'The policies assigned, directly or in an initiative.' }); Noun = 'definitions'; File = 'policy-definitions'; Rows = @($Assessment.Definitions); GroupBy = @('PolicyType', 'Category', 'Effect', 'Mode', 'Assigned')
        Columns = @((& $col 'Definition' 'Definition' @{ Type = 'resource' }), (& $col 'PolicyType' 'Type' $facet), (& $col 'Category' 'Category' $facet), (& $col 'Mode' 'Mode' $facet), (& $col 'Effect' 'Effect' $facet), (& $col 'AllowedEffects' 'Allowed effects'), (& $col 'RolesNeeded' 'Roles needed'), (& $col 'Version' 'Version'), (& $col 'Initiatives' 'Initiatives' $num), (& $col 'DirectAssignments' 'Assigned directly' $num), (& $col 'Assigned' 'Assigned' @{ Type = 'badge'; Tones = $yesNo; Facet = $true }), (& $col 'Deprecated' 'Deprecated' @{ Type = 'badge'; Tones = $flag; Facet = $true }), (& $col 'Preview' 'Preview' @{ Type = 'badge'; Tones = $flag; Facet = $true }), (& $col 'DefinedAt' 'Defined at' $facet), (& $col 'Description' 'Description' @{ Type = 'wide'; Hidden = $true }), $(if ($platform) { & $col 'HiddenMetadata' 'Hidden metadata' @{ Hidden = $true } })) | Where-Object { $_ }
    }
    & $add @{ Id = 'policy-roles'; Section = 'Definitions'; Title = 'Managed identities'' role assignments'; Note = 'The roles held by the assignments'' managed identities; Required: a role the assignment''s policies list (roleDefinitionIds).'; Noun = 'role assignments'; File = 'policy-role-assignments'; Rows = @($Assessment.Roles); GroupBy = @('Assignment', 'Role', 'Required'); Columns = @((& $col 'Assignment' 'Assignment' $facet), (& $col 'Identity' 'Identity' $facet), (& $col 'Role' 'Role' $facet), (& $col 'Scope' 'Scope'), (& $col 'Required' 'Required' @{ Type = 'badge'; Tones = @{ Yes = 'good'; No = 'info' }; Facet = $true }), (& $col 'PrincipalId' 'Principal' @{ Type = 'mono' }), (& $col 'ScopeId' 'Scope ID' @{ Type = 'mono'; Hidden = $true })) }

    $tree = $null
    if (@($Assessment.ManagementGroups).Count -or @($Assessment.Subscriptions).Count) { $tree = @{ Title = 'Management groups and subscriptions, with their compliance'; OpenTo = 'm'; Root = $Assessment.Tree } }
    $notices = @(foreach ($line in @($Assessment['Notices'])) { @{ Tone = 'warn'; Text = $line } })
    $report = @{ Path = $Path; Title = $Title; Subtitle = 'Azure Policy: assignments, compliance, exemptions and definitions - and what to improve'; Fact = $Detail; Tile = $tiles; Chart = $charts; Table = $tables.ToArray(); Notice = $notices }
    if ($tree) { $report.Tree = $tree }
    Write-AACHtmlReport @report
}
