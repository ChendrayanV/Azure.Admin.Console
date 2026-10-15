function ConvertTo-AACWafReport {
    <#
    .SYNOPSIS
        The report model (Show-AACReportView, Write-AACHtmlReport,
        Write-AACReportPdf) of a Well-Architected assessment: headline,
        tiles, heat maps, and the principles, checks and findings tables.
    .DESCRIPTION
        -State is Get-AACWafAssessment's result, -Request what it was asked.
        -History adds the trend: @{ Previous; Change; Path }. Returns the
        report hashtable; its 'Findings' key holds the failed results.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [hashtable] $Request,

        [hashtable] $History
    )

    $result = $state.Result
    $stats = $result.Stats
    $rank = Get-AACSeverityRank
    $tone = { param($Score) if ($null -eq $Score) { 'neutral' } elseif ($Score -ge 75) { 'good' } elseif ($Score -ge 50) { 'warn' } else { 'bad' } }
    $show = { param($Score) if ($null -eq $Score) { '-' } else { '{0:N0}' -f $Score } }
    $findings = @($result.Results | Where-Object Status -In 'Fail', 'Partly' | Sort-Object -Property @{ Expression = { $rank.Rank[$_.Severity] } }, Pillar, Principle, Check, Resource)
    $statusTones = @{ Pass = 'good'; Gaps = 'bad'; 'Not assessed' = 'neutral' }
    $report = @{
        Subtitle = "Well-Architected Framework: $($request.Pillar -join ', ')"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Pillars = $request.Pillar -join ', '; 'Heat maps by' = $request.HeatMapBy; Sources = (@('Resource Graph') + @(if (-not $request.NoAdvisor) { 'Advisor' }) + @(if (-not $request.NoDefender -and 'Security' -in $request.Pillar) { 'Defender for Cloud' })) -join ', ' }
        Status   = $(if ($null -eq $result.Overall) { 'Info' } elseif ($result.Overall -ge 75) { 'Success' } elseif ($result.Overall -ge 50) { 'Warning' } else { 'Failed' })
        Headline = $(if ($null -eq $result.Overall) { 'Nothing in scope to assess.' } else { "Overall $(& $show $result.Overall) / 100 - $(@($result.Pillars | ForEach-Object { "$($_.Pillar) $(& $show $_.Score) ($($_.Maturity))" }) -join ', '); $($stats.Failed) failed result(s), $($stats.High) high" })
        Tiles    = @(
            @{ Value = & $show $result.Overall; Label = 'overall score'; Tone = & $tone $result.Overall }
            foreach ($p in $result.Pillars) { @{ Value = & $show $p.Score; Label = "$($p.Pillar.ToLowerInvariant()) - $($p.Maturity.ToLowerInvariant())"; Tone = & $tone $p.Score; Table = 'principles'; Filters = @{ Pillar = $p.Pillar } } }
            @{ Value = '{0:N0}' -f $stats.Resources; Label = 'resources assessed'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $stats.WithGaps; Label = "checks with gaps (of $($stats.Assessed))"; Tone = $(if ($stats.WithGaps) { 'warn' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Gaps' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high-severity findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @(@($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }) + @(if ($stats.Duplicates) { @{ Status = 'Info'; Text = "$($stats.Duplicates) Advisor and Defender item(s) were the same finding as a catalogue check on the same resource, and are counted once (-KeepDuplicates counts them twice)." } }))
        HeatMaps = @($result.HeatMaps)
        Tabs     = @(
            @{ Name = 'Principles'; Badge = @($result.Principles).Count; Tone = 'violet'; Note = 'Each design principle''s score, from its checks weighted by severity; a principle no check covers needs a review.' }
            @{ Name = 'Checks'; Badge = $stats.Assessed; Tone = 'info'; Note = 'Every check: how many resources it tested, passed and failed.' }
            @{ Name = 'Findings'; Badge = $findings.Count; Tone = $(if ($findings.Count) { 'bad' } else { 'good' }); Note = 'Each resource that failed a check, worst first, with what to do.' }
        )
        Tables   = @(
            @{ Id = 'principles'; Title = 'Design principles'; Section = 'Principles'; Rows = @($result.Principles); Noun = 'principles'; GroupBy = @('Pillar', 'Coverage'); ConsoleLimit = 12
                Columns = @(
                    @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Principle'; Label = 'Design principle'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Checks'; Label = 'Checks'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Evaluated'; Label = 'Results'; Type = 'number'; Pdf = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Coverage'; Label = 'Coverage'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Link'; Label = 'Principle'; Type = 'link'; Text = 'Learn' }
                ) }
            @{ Id = 'checks'; Title = 'Checks'; Section = 'Checks'; Rows = @($result.Checks | Sort-Object -Property @{ Expression = { if ($null -eq $_.Score) { 101 } else { $_.Score } } }, CheckId); Noun = 'checks'; GroupBy = @('Pillar', 'Principle', 'Source', 'Severity', 'Status'); NoConsole = $true
                Columns = @(
                    @{ Key = 'CheckId'; Label = 'ID'; Type = 'mono'; Pdf = $true }
                    @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true }
                    @{ Key = 'Principle'; Label = 'Design principle'; Facet = $true; Pdf = $true }
                    @{ Key = 'Check'; Label = 'Check'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'Evaluated'; Label = 'Tested'; Type = 'number'; Sum = $true; Pdf = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Sum = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide' }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; GroupBy = @('Pillar', 'Principle', 'Check', 'Severity', 'Subscription', 'ResourceGroup'); ConsoleLimit = 20
                Empty = 'Every check passed.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true; Console = $true }
                    @{ Key = 'Principle'; Label = 'Design principle'; Facet = $true }
                    @{ Key = 'Check'; Label = 'Check'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Console = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true; Pdf = $true }
                    @{ Key = 'HeatColumn'; Label = "Heat map ($request.HeatMapBy)"; Facet = $true; Hidden = $true }
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'type'; Facet = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-HeatMapBy ResourceGroup or ResourceType changes the heat maps'' columns; -Pillar, -ResourceGroupName and -ExcludeCheck narrow it; -NoDisplay returns the results; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    if ($History -and $null -ne $History.Previous) {
        $report.Headline = "$($report.Headline) - $(if ($History.Change -ge 0) { '+' })$('{0:N1}' -f $History.Change) since $($History.Previous)"
    }
    $report['Findings'] = $findings
    $report
}
