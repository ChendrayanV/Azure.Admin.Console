function Write-AACPSRuleHtml {
    <#
    .SYNOPSIS
        Writes Invoke-AACPSRule's -HtmlPath report: tiles for the outcome,
        charts of the failures by pillar, rule, resource and severity, and
        every result in one interactive table - opening on the failures,
        grouped by rule - with Azure portal and rule documentation links.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'PSRule for Azure',

        [System.Collections.IDictionary] $Detail,

        [int] $Rules,

        [int] $Objects,

        [string[]] $Warning = @(),

        # List only failures (and rules that couldn't evaluate) in the
        # table; the tiles still count every result.
        [switch] $FailedOnly
    )

    $passed = @($Result | Where-Object Outcome -EQ 'Pass').Count
    $failed = @($Result | Where-Object Outcome -EQ 'Fail')
    $errors = @($Result | Where-Object Outcome -EQ 'Error').Count
    $problems = @($Result | Where-Object Outcome -NE 'Pass')
    $decided = $passed + $failed.Count
    $pillarTone = @{ Security = 'bad'; Reliability = 'info'; 'Cost Optimization' = 'good'; 'Operational Excellence' = 'violet'; 'Performance Efficiency' = 'warn' }
    $severityTone = @{ Critical = 'bad'; Error = 'bad'; Important = 'warn'; Warning = 'warn'; Awareness = 'neutral' }

    $tiles = @(
        @{ Value = '{0:N0}' -f $Objects; Label = 'objects checked'; Tone = 'info' }
        @{ Value = '{0:N0}' -f $Rules; Label = 'rules'; Tone = 'violet' }
        @{ Value = '{0:N0}' -f $passed; Label = 'passed'; Tone = 'good'; Table = 'results'; Filters = @{ Outcome = 'Pass' } }
        @{ Value = '{0:N0}' -f $failed.Count; Label = 'failed'; Tone = $(if ($failed.Count) { 'bad' } else { 'neutral' }); Table = 'results'; Filters = @{ Outcome = 'Fail' } }
        @{ Value = '{0:N0}' -f $errors; Label = 'could not evaluate'; Tone = $(if ($errors) { 'warn' } else { 'neutral' }); Table = 'results'; Filters = @{ Outcome = 'Error' } }
        @{ Value = $(if ($decided) { '{0:N1}%' -f (100 * $passed / $decided) } else { '-' }); Label = 'pass rate'; Tone = 'info' }
    )
    $top = {
        param([string] $Property, [int] $First = 10)
        @($failed | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object {
                @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count; Tone = $pillarTone[$_.Name] }
            })
    }
    $bySeverity = @(foreach ($severity in 'Critical', 'Important', 'Awareness', 'Error', 'Warning') {
            $n = @($failed | Where-Object Severity -EQ $severity).Count
            if ($n) { @{ Label = $severity; Value = $n; Tone = $severityTone[$severity] } }
        })
    $onlyFailed = @{ Outcome = 'Fail' }
    $charts = @(
        @{ Title = 'Failed by Well-Architected pillar'; Items = @(& $top 'Pillar'); Table = 'results'; Column = 'Pillar'; BaseFilters = $onlyFailed }
        @{ Title = 'Failed by severity'; Items = $bySeverity; Table = 'results'; Column = 'Severity'; BaseFilters = $onlyFailed }
        @{ Title = 'Resources with most failures'; Items = @(& $top 'ResourceName'); Table = 'results'; Column = 'ResourceName'; BaseFilters = $onlyFailed; Tone = 'violet' }
        @{ Title = 'Rules that fail most'; Items = @(& $top 'RuleName'); Table = 'results'; Column = 'RuleName'; BaseFilters = $onlyFailed; Wide = $true }
    )
    $notices = @(foreach ($line in $Warning | Select-Object -First 8) { @{ Tone = 'warn'; Text = $line } })

    $table = @{
        Id      = 'results'
        Title   = 'Results'
        Note    = $(if ($FailedOnly) { 'One row per rule and resource that failed (passed results are counted above, not listed).' } else { 'One row per rule and resource. It opens on the failures - Reset shows every result.' })
        Noun    = 'results'
        File    = 'PSRuleResults'
        Rows    = $(if ($FailedOnly) { $problems } else { $Result })
        Group   = 'RuleName'
        Filters = $(if ($problems.Count) { $onlyFailed } else { @{} })
        GroupBy = @('RuleName', 'ResourceName', 'Pillar', 'ResourceGroup', 'SubscriptionName')
        Columns = @(
            @{ Key = 'Outcome'; Label = 'Outcome'; Type = 'badge'; Facet = $true; Tones = @{ Pass = 'good'; Fail = 'bad'; Error = 'warn' } }
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Facet = $true; Tones = $severityTone }
            @{ Key = 'RuleName'; Label = 'Rule'; Facet = $true; Nowrap = $true }
            @{ Key = 'Title'; Label = 'Title'; Type = 'wide' }
            @{ Key = 'ResourceName'; Label = 'Resource'; Type = 'resource' }
            @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true; Nowrap = $true }
            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Nowrap = $true }
            @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true; Nowrap = $true }
            @{ Key = 'Reason'; Label = 'Why'; Type = 'wide' }
            @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Rule docs' }
            @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true; Nowrap = $true }
            @{ Key = 'Source'; Label = 'Source'; Facet = $true; Nowrap = $true }
            @{ Key = 'Recommendation'; Label = 'Recommendation'; Hidden = $true }
            @{ Key = 'Ref'; Label = 'Reference'; Hidden = $true }
            @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Hidden = $true }
            @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
        )
    }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle "$('{0:N0}' -f $Rules) rules on $('{0:N0}' -f $Objects) objects - $('{0:N0}' -f $failed.Count) failed" -Fact $Detail -Tile $tiles -Chart $charts -Table @($table) -Notice $notices
}
