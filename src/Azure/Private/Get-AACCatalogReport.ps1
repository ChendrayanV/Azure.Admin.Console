function Get-AACCatalogReport {
    <#
    .SYNOPSIS
        The report of an assessment run from a catalogue of queries, shared by
        Invoke-AACLandingZoneAssessment and Invoke-AACResiliencyAssessment.
    .DESCRIPTION
        -Assessment is the converter's result with -Review (Invoke-AACFindingReview's)
        applied. -Group is the column the checks are grouped by: Category or
        ResourceType. Returns the model Invoke-AACReportOutput takes. A check isn't
        scored: with this many that can't be judged by a query, a percentage would
        claim more than was measured.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [hashtable] $Review,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Fact,

        [Parameter(Mandatory)]
        [string] $Subtitle,

        [Parameter(Mandatory)]
        [string] $Group,

        [Parameter(Mandatory)]
        [string] $GroupLabel,

        [Parameter(Mandatory)]
        [string] $Hint
    )

    $checks = @($Assessment.Checks)
    $count = { param([string] $Status) @($checks | Where-Object Status -EQ $Status).Count }
    $tones = @{ Fail = 'bad'; Review = 'warn'; 'Not checked' = 'neutral'; 'No evidence' = 'neutral'; Present = 'info'; Pass = 'good'; Manual = 'neutral' }
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Info = 'neutral' }
    $fails = & $count 'Fail'
    $highFails = @($checks | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'High' }).Count
    $reviewCount = & $count 'Review'
    $found = @($checks | Where-Object { $_.Status -in 'Fail', 'Review' } | ForEach-Object { $_.$Group } | Group-Object | Sort-Object -Property Count -Descending | Select-Object -First 12)
    $tables = [System.Collections.Generic.List[object]]::new()
    $tables.Add(@{ Id = 'checks'; Title = 'Checks'; Section = 'Checks'; Rows = $checks; Noun = 'checks'; GroupBy = @('Status', $Group, 'Severity'); ConsoleLimit = 30
            Empty = 'Nothing in scope to check.'; EmptyStatus = 'Info'
            Columns = @(
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $tones; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = $Group; Label = $GroupLabel; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = 'Check'; Label = 'Check'; Type = 'wide'; Console = $true; Pdf = $true }
                @{ Key = 'Evidence'; Label = 'Evidence'; Facet = $true }
                @{ Key = 'Affected'; Label = 'Affected'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                @{ Key = 'Detail'; Label = 'What was found'; Type = 'wide'; Pdf = $true }
            ) })
    if (@($Assessment.Items).Count) {
        $tables.Add(@{ Id = 'affected'; Title = 'Affected resources'; Section = 'Checks'; Rows = @($Assessment.Items); Noun = 'resources'; GroupBy = @('Check', 'Severity')
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $tones; Facet = $true }
                    @{ Key = 'Check'; Label = 'Check'; Type = 'wide' }
                    @{ Key = 'Name'; Label = 'Name' }
                    @{ Key = 'ResourceId'; Label = 'Resource ID'; Type = 'mono' }
                ) })
    }
    if (@($Review.Suppressed).Count) {
        $tables.Add(@{ Id = 'suppressed'; Title = 'Suppressed findings'; Section = 'Review'; Rows = @($Review.Suppressed); Noun = 'findings'; Note = 'Accepted in the suppression file, and left out of the counts.'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                    @{ Key = 'Check'; Label = 'Check'; Type = 'wide' }
                    @{ Key = 'SuppressionReason'; Label = 'Reason'; Type = 'wide' }
                    @{ Key = 'SuppressedUntil'; Label = 'Until' }
                    @{ Key = 'FindingKey'; Label = 'Key'; Type = 'mono' }
                ) })
    }
    if (@($Review.Resolved).Count) {
        $tables.Add(@{ Id = 'resolved'; Title = 'Resolved since the earlier run'; Section = 'Review'; Rows = @($Review.Resolved); Noun = 'findings'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                    @{ Key = 'Finding'; Label = 'Check'; Type = 'wide' }
                    @{ Key = 'FindingKey'; Label = 'Key'; Type = 'mono' }
                ) })
    }
    @{
        Subtitle = $Subtitle
        Facts    = $Fact
        Status   = $(if ($highFails) { 'Failed' } elseif ($fails -or $reviewCount) { 'Warning' } else { 'Success' })
        Headline = "$fails check(s) failed ($highFails high) and $reviewCount to review, of $($checks.Count); $(& $count 'Manual') need a person, because no query can answer them."
        Tiles    = @(
            @{ Value = '{0:N0}' -f $fails; Label = 'failed'; Tone = $(if ($fails) { 'bad' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Fail' } }
            @{ Value = '{0:N0}' -f $reviewCount; Label = 'to review (judged by name)'; Tone = $(if ($reviewCount) { 'warn' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Review' } }
            @{ Value = '{0:N0}' -f (& $count 'Pass'); Label = 'passed'; Tone = 'good'; Table = 'checks'; Filters = @{ Status = 'Pass' } }
            @{ Value = '{0:N0}' -f (& $count 'Manual'); Label = 'need a person'; Tone = 'info'; Table = 'checks'; Filters = @{ Status = 'Manual' } }
        )
        Notices  = @(@($Assessment.Notices) + @($Review.Notices) | Where-Object { $_ } | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            if ($found.Count) { @{ Title = "Failed or to review, by $($GroupLabel.ToLowerInvariant())"; Items = @($found | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'checks'; Column = $Group; Tone = 'warn'; Console = $true } }
        )
        Tables   = $tables.ToArray()
        Hint     = $Hint
    }
}
