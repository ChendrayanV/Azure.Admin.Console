function Write-AACPolicyStateHtml {
    <#
    .SYNOPSIS
        Writes Get-AACPolicyState's result as an interactive HTML report:
        tiles and charts that filter tables of every policy state, the
        resources, assignments, policies, subscriptions and resource groups.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Compliance,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Compliance.Stats
    $tone = { param($Rate) if ($null -eq $Rate) { 'neutral' } elseif ($Rate -ge 90) { 'good' } elseif ($Rate -ge 70) { 'warn' } else { 'bad' } }
    $stateTones = @{ NonCompliant = 'bad'; Compliant = 'good'; Exempt = 'neutral'; Unknown = 'warn'; Conflict = 'warn'; Error = 'bad'; Protected = 'info' }
    $bad = @($Compliance.States | Where-Object ComplianceState -EQ 'NonCompliant')
    $top = {
        param([object[]] $Items, [string] $Property, [int] $First = 12)
        @($Items | Where-Object { $_.$Property } | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } })
    }

    $tiles = @(
        @{ Value = $(if ($null -ne $stats.ComplianceRate) { "$($stats.ComplianceRate)%" } else { '-' }); Label = ('resource compliance ({0:N0} of {1:N0})' -f $stats.CompliantCounted, $stats.Resources); Tone = (& $tone $stats.ComplianceRate); Table = 'resources' }
        @{ Value = '{0:N0}' -f $stats.NonCompliant; Label = 'non-compliant resources'; Tone = $(if ($stats.NonCompliant) { 'bad' } else { 'good' }); Table = 'resources'; Filters = @{ Compliance = 'NonCompliant' } }
        @{ Value = '{0:N0}' -f $stats.Compliant; Label = 'compliant resources'; Tone = 'good'; Table = 'resources'; Filters = @{ Compliance = 'Compliant' } }
        @{ Value = '{0:N0}' -f $stats.Exempt; Label = 'exempt resources'; Tone = 'neutral'; Table = 'resources'; Filters = @{ Compliance = 'Exempt' } }
        @{ Value = '{0:N0}' -f $stats.Assignments; Label = 'assignments'; Tone = 'violet'; Table = 'assignments' }
        @{ Value = '{0:N0} / {1:N0}' -f $stats.NonCompliantInitiatives, $stats.Initiatives; Label = 'non-compliant initiatives'; Tone = $(if ($stats.NonCompliantInitiatives) { 'warn' } else { 'good' }); Table = 'states' }
        @{ Value = '{0:N0} / {1:N0}' -f $stats.NonCompliantPolicies, $stats.Policies; Label = 'non-compliant policies'; Tone = $(if ($stats.NonCompliantPolicies) { 'warn' } else { 'good' }); Table = 'policies' }
        @{ Value = '{0:N0}' -f $stats.States; Label = 'policy states'; Tone = 'neutral'; Table = 'states' }
    )
    $charts = @(
        @{ Title = 'Policy states'; Kind = 'donut'; CenterLabel = 'states'; Table = 'states'; Column = 'ComplianceState'; Items = @($stats.ByState | ForEach-Object { @{ Label = $_.Label; Value = $_.Value; Filter = $_.Label; Tone = $(if ($stateTones.Contains($_.Label)) { $stateTones[$_.Label] } else { 'neutral' }) } }) }
        @{ Title = 'Non-compliant resources by policy'; Items = @(& $top $bad 'Policy'); Table = 'states'; Column = 'Policy'; BaseFilters = @{ ComplianceState = 'NonCompliant' }; Tone = 'bad'; Wide = $true }
        @{ Title = 'Compliance by subscription (%)'; Items = @($Compliance.Scopes | Where-Object Level -EQ 'Subscription' | ForEach-Object { @{ Label = $_.Name; Value = $(if ($null -ne $_.ComplianceRate) { $_.ComplianceRate } else { 0 }); Display = $(if ($null -ne $_.ComplianceRate) { "$($_.ComplianceRate)%" } else { '-' }); Tone = (& $tone $_.ComplianceRate); Filter = $_.Name } }); Table = 'resources'; Column = 'SubscriptionName' }
        @{ Title = 'Non-compliant by resource type'; Items = @(& $top $bad 'ResourceType'); Table = 'states'; Column = 'ResourceType'; BaseFilters = @{ ComplianceState = 'NonCompliant' }; Tone = 'warn' }
    )
    $scopeColumns = {
        param([string] $Name)
        @(
            @{ Key = 'Name'; Label = $Name }
            if ($Name -eq 'Resource group') { @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true } }
            @{ Key = 'ComplianceRate'; Label = 'Compliance'; Type = 'score' }
            @{ Key = 'NonCompliant'; Label = 'Non-compliant'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
            @{ Key = 'Compliant'; Label = 'Compliant'; Type = 'number'; Sum = $true; Format = 'N0' }
            @{ Key = 'Exempt'; Label = 'Exempt'; Type = 'number'; Sum = $true; Format = 'N0' }
            @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Sum = $true; Format = 'N0' }
        )
    }
    $tables = @(
        @{
            Id = 'resources'; Title = 'Resources'; Note = 'Non-compliant when any policy finds it so; compliant when every policy that evaluated it does.'
            Noun = 'resources'; File = 'policy-resources'; Rows = @($Compliance.Resources); GroupBy = @('Compliance', 'SubscriptionName', 'ResourceGroup', 'ResourceType')
            Columns = @(
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Compliance'; Label = 'Compliance'; Type = 'badge'; Tones = $stateTones; Facet = $true }
                @{ Key = 'NonCompliantPolicies'; Label = 'Policies failing'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'PoliciesEvaluated'; Label = 'Policies evaluated'; Type = 'number'; Format = 'N0' }
                @{ Key = 'NonCompliantWith'; Label = 'Non-compliant with'; Type = 'wide' }
                @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
            )
        }
        @{
            Id = 'states'; Title = 'Policy states'; Note = 'One row per resource and policy.'
            Noun = 'states'; File = 'policy-states'; Rows = @($Compliance.States); GroupBy = @('Policy', 'Assignment', 'ComplianceState', 'SubscriptionName', 'ResourceGroup')
            Columns = @(
                @{ Key = 'ComplianceState'; Label = 'State'; Type = 'badge'; Tones = $stateTones; Facet = $true }
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Policy'; Label = 'Policy'; Type = 'wide'; Facet = $true }
                @{ Key = 'PolicySet'; Label = 'Initiative'; Facet = $true }
                @{ Key = 'Assignment'; Label = 'Assignment'; Facet = $true }
                @{ Key = 'AssignmentScope'; Label = 'Assigned at'; Facet = $true }
                @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'EvaluatedAt'; Label = 'Evaluated'; Type = 'datetime' }
                @{ Key = 'Enforcement'; Label = 'Enforcement'; Facet = $true; Hidden = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true; Hidden = $true }
                @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
            )
        }
        @{
            Id = 'assignments'; Title = 'Assignments'; Noun = 'assignments'; File = 'policy-assignments'; Rows = @($Compliance.Assignments)
            Columns = @(
                @{ Key = 'Assignment'; Label = 'Assignment' }
                @{ Key = 'Scope'; Label = 'Assigned at'; Facet = $true }
                @{ Key = 'Enforcement'; Label = 'Enforcement'; Type = 'badge'; Tones = @{ Default = 'good'; DoNotEnforce = 'warn' }; Facet = $true }
                @{ Key = 'ComplianceRate'; Label = 'Compliance'; Type = 'score' }
                @{ Key = 'NonCompliant'; Label = 'Non-compliant'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Compliant'; Label = 'Compliant'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Exempt'; Label = 'Exempt'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'NonCompliantPolicies'; Label = 'Policies failing'; Type = 'number'; Format = 'N0' }
                @{ Key = 'AssignmentId'; Label = 'Assignment ID'; Type = 'mono'; Hidden = $true }
            )
        }
        @{
            Id = 'policies'; Title = 'Policies'; Noun = 'policies'; File = 'policies'; Rows = @($Compliance.Policies)
            Columns = @(
                @{ Key = 'Policy'; Label = 'Policy'; Type = 'wide' }
                @{ Key = 'PolicySet'; Label = 'Initiative'; Facet = $true }
                @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                @{ Key = 'ComplianceRate'; Label = 'Compliance'; Type = 'score' }
                @{ Key = 'NonCompliant'; Label = 'Non-compliant'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Compliant'; Label = 'Compliant'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Exempt'; Label = 'Exempt'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Assignments'; Label = 'Assignments'; Type = 'wide' }
            )
        }
        @{ Id = 'subscriptions'; Title = 'Subscriptions'; Noun = 'subscriptions'; File = 'policy-subscriptions'; Rows = @($Compliance.Scopes | Where-Object Level -EQ 'Subscription'); Columns = @(& $scopeColumns 'Subscription') }
        @{ Id = 'groups'; Title = 'Resource groups'; Noun = 'resource groups'; File = 'policy-resource-groups'; Rows = @($Compliance.Scopes | Where-Object Level -EQ 'ResourceGroup'); GroupBy = @('SubscriptionName'); Columns = @(& $scopeColumns 'Resource group') }
    )
    $notices = @(@($Compliance.Notice | Where-Object { $_ }) | ForEach-Object { @{ Tone = 'info'; Text = $_ } })
    $notices += @{ Tone = 'info'; Text = 'Azure Policy states from Azure Resource Graph. Compliance: (compliant + exempt + unknown + protected resources) / every resource evaluated, as the Azure portal counts it. 90% or more green, 70-89% amber, below red.' }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Azure Policy: every resource''s compliance, by assignment, policy, subscription and resource group' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
