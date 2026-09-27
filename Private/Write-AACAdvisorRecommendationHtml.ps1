function Write-AACAdvisorRecommendationHtml {
    <#
    .SYNOPSIS
        Writes Get-AACAdvisorRecommendation's -HtmlPath report: tiles for
        recommendations, impact, resources and savings; charts by category,
        impact, subscription and recommendation; and every recommendation in
        one interactive table, grouped by recommendation.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Recommendation,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Azure Advisor recommendations',

        [System.Collections.IDictionary] $Detail
    )

    $count = { param($Items, [scriptblock] $Where) @($Items | Where-Object $Where).Count }
    $top = {
        param($Items, [string] $Property, [int] $First = 10)
        @($Items | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object {
                @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count; Filter = $(if ($_.Name) { $_.Name } else { '(none)' }) }
            })
    }
    $categoryTone = @{ Cost = 'good'; Security = 'bad'; Reliability = 'info'; OperationalExcellence = 'violet'; Performance = 'warn' }

    $resources = @($Recommendation | Where-Object ResourceId | ForEach-Object { $_.ResourceId.ToLowerInvariant() } | Select-Object -Unique).Count
    $tiles = [System.Collections.Generic.List[object]]::new()
    $tiles.Add(@{ Value = '{0:N0}' -f $Recommendation.Count; Label = 'recommendations'; Tone = 'info'; Table = 'recommendations' })
    $tiles.Add(@{ Value = '{0:N0}' -f (& $count $Recommendation { $_.Impact -eq 'High' }); Label = 'high impact'; Tone = 'bad'; Table = 'recommendations'; Filters = @{ Impact = 'High' } })
    $tiles.Add(@{ Value = '{0:N0}' -f (& $count $Recommendation { $_.Impact -eq 'Medium' }); Label = 'medium impact'; Tone = 'warn'; Table = 'recommendations'; Filters = @{ Impact = 'Medium' } })
    $tiles.Add(@{ Value = '{0:N0}' -f (& $count $Recommendation { $_.Impact -eq 'Low' }); Label = 'low impact'; Tone = 'neutral'; Table = 'recommendations'; Filters = @{ Impact = 'Low' } })
    $tiles.Add(@{ Value = '{0:N0}' -f $resources; Label = 'resources affected'; Tone = 'violet' })
    # Savings per currency, never converted.
    foreach ($currency in @($Recommendation | Where-Object { $_.MonthlySavings } | Group-Object SavingsCurrency | Sort-Object Count -Descending | Select-Object -First 2)) {
        $total = 0.0
        foreach ($item in $currency.Group) { $total += [double]$item.MonthlySavings }
        $tiles.Add(@{ Value = ('{0} {1:N0}' -f $currency.Name, $total).Trim(); Label = 'est. savings / month'; Tone = 'good'; Table = 'recommendations'; Filters = @{ Category = 'Cost' } })
    }
    $retiring = & $count $Recommendation { $_.RetirementDate }
    if ($retiring) {
        $tiles.Add(@{ Value = '{0:N0}' -f $retiring; Label = 'affected by retirements'; Tone = 'warn' })
    }

    $byCategory = @(& $top $Recommendation 'Category' 10 | ForEach-Object { $_.Tone = $categoryTone[$_.Label]; $_ })
    $byImpact = @(foreach ($impact in 'High', 'Medium', 'Low') {
            $n = & $count $Recommendation { $_.Impact -eq $impact }
            if ($n) { @{ Label = $impact; Value = $n; Tone = @{ High = 'bad'; Medium = 'warn'; Low = 'neutral' }[$impact] } }
        })
    $charts = @(
        @{ Title = 'By category'; Items = $byCategory; Table = 'recommendations'; Column = 'Category' }
        @{ Title = 'By impact'; Items = $byImpact; Table = 'recommendations'; Column = 'Impact' }
        @{ Title = 'By subscription'; Items = @(& $top $Recommendation 'SubscriptionName' 10); Table = 'recommendations'; Column = 'SubscriptionName'; Tone = 'violet' }
        @{ Title = 'Most common recommendations'; Items = @(& $top $Recommendation 'Problem' 10); Table = 'recommendations'; Column = 'Problem'; Wide = $true }
    )

    $table = @{
        Id       = 'recommendations'
        Title    = 'Recommendations'
        Note     = 'One row per recommendation per resource. Savings are Advisor''s estimates, per currency.'
        Noun     = 'recommendations'
        File     = 'AdvisorRecommendations'
        Rows     = $Recommendation
        Group    = 'Problem'
        GroupBy  = @('Problem', 'Category', 'Impact', 'SubscriptionName', 'ResourceGroup', 'ResourceType')
        Columns  = @(
            @{ Key = 'Category'; Label = 'Category'; Type = 'badge'; Facet = $true; Tones = $categoryTone }
            @{ Key = 'Impact'; Label = 'Impact'; Type = 'badge'; Facet = $true; Tones = @{ High = 'bad'; Medium = 'warn'; Low = 'neutral' } }
            @{ Key = 'Problem'; Label = 'Recommendation'; Type = 'wide' }
            @{ Key = 'ResourceName'; Label = 'Resource'; Type = 'resource' }
            @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true; Nowrap = $true }
            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Nowrap = $true }
            @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true; Nowrap = $true }
            @{ Key = 'MonthlySavings'; Label = 'Savings / month'; Type = 'money'; Sum = $true; CurrencyKey = 'SavingsCurrency'; Tone = 'good' }
            @{ Key = 'RetirementDate'; Label = 'Retirement'; Type = 'date'; Soon = $true }
            @{ Key = 'Solution'; Label = 'Solution'; Type = 'wide' }
            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Facet = $true; Tones = @{ Active = 'info'; Postponed = 'warn'; Dismissed = 'neutral' } }
            @{ Key = 'LearnMoreLink'; Label = 'Docs'; Type = 'link'; Text = 'Learn more' }
            @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Hidden = $true }
            @{ Key = 'AnnualSavings'; Label = 'Savings / year'; Type = 'money'; Hidden = $true }
            @{ Key = 'SavingsCurrency'; Label = 'Currency'; Hidden = $true }
            @{ Key = 'RetiringFeature'; Label = 'Retiring feature'; Hidden = $true }
            @{ Key = 'PotentialBenefits'; Label = 'Potential benefits'; Hidden = $true }
            @{ Key = 'LastUpdated'; Label = 'Last updated'; Type = 'date'; Hidden = $true }
            @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
        )
    }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle "$('{0:N0}' -f $Recommendation.Count) recommendations for $('{0:N0}' -f $resources) resources" -Fact $Detail -Tile $tiles.ToArray() -Chart $charts -Table @($table)
}
