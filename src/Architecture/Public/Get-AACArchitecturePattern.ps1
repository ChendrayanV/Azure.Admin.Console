function Get-AACArchitecturePattern {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Step 2 (optional): shows which cloud design patterns fit the brief,
        why, and their Well-Architected trade-offs.
    .DESCRIPTION
        Fifteen patterns from the Azure Architecture Center, best first.
        Recommended means it fits the answers; New-AACArchitectureDesign uses
        the recommended ones unless you pipe in others. Offline.
    .PARAMETER Brief
        The brief, or the path of a saved one.
    .PARAMETER Top
        Only the best this many.
    .PARAMETER RecommendedOnly
        Only the recommended patterns (a fit of 3 or more).
    .PARAMETER CsvPath
        Write the patterns to this CSV file.
    .PARAMETER HtmlPath
        Write an HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the patterns.
    .PARAMETER NoDisplay
        Return the patterns without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACArchitecturePattern -Brief $brief
        Every pattern, best first.
    .EXAMPLE
        Get-AACArchitecturePattern -Brief $brief -NoDisplay | Where-Object Id -In 'cache-aside', 'retry' | New-AACArchitectureDesign -Brief $brief -Offline
        Design with the patterns you pick.
    .OUTPUTS
        AAC.ArchitecturePattern (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ArchitecturePattern')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object] $Brief,

        [ValidateRange(1, 50)]
        [int] $Top,

        [switch] $RecommendedOnly,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Architecture patterns',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    process {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }
        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
        $source = if ($Brief -is [string]) { & $resolve $Brief } else { $Brief }
        $resolved = Resolve-AACArchitectureInput -InputObject $source -Kind Brief
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Architecture patterns' -Color 'mediumpurple2' }
        $catalog = Get-AACArchitectureCatalog
        # Answers not given take their defaults, as in the brief itself.
        $full = ConvertTo-AACArchitectureBrief -Catalog $catalog -Answer $resolved.Answers -Name $resolved.Name
        $rows = @(ConvertTo-AACArchitecturePattern -Catalog $catalog -Answers $full.Answers)
        if ($RecommendedOnly) { $rows = @($rows | Where-Object Recommended -EQ 'Yes') }
        if ($Top) { $rows = @($rows | Select-Object -First $Top) }
        $rank = 0
        foreach ($row in $rows) { $rank++; $row | Add-Member -NotePropertyName Rank -NotePropertyValue $rank -Force; $row | Add-Member -NotePropertyName Workload -NotePropertyValue $full.Name -Force }

        $report = @{
            Subtitle = "Cloud design patterns for $($full.Name)"
            Facts    = [ordered]@{ Workload = $full.Name; Catalog = $catalog.Version; 'Patterns from' = 'Azure Architecture Center' }
            Status   = 'Success'
            Headline = "$(@($rows | Where-Object Recommended -EQ 'Yes').Count) recommended of $($rows.Count): $((@($rows | Where-Object Recommended -EQ 'Yes' | Select-Object -First 4 | ForEach-Object Name)) -join ', ')"
            Tiles    = @(
                @{ Value = '{0:N0}' -f @($rows | Where-Object Recommended -EQ 'Yes').Count; Label = 'recommended'; Tone = 'good'; Table = 'patterns'; Filters = @{ Recommended = 'Yes' } }
                @{ Value = '{0:N0}' -f $rows.Count; Label = 'patterns ranked'; Tone = 'info'; Table = 'patterns' }
            )
            Charts   = @(@{ Title = 'Score'; Items = @($rows | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Score } }); Table = 'patterns'; Column = 'Name'; Tone = 'violet'; Console = $true })
            Tables   = @(@{ Id = 'patterns'; Title = 'Patterns, best first'; Rows = $rows; Noun = 'patterns'; ConsoleLimit = 15
                    Hover = @('Problem', 'Why', 'TradeOffs', 'Adds'); HoverTitle = 'Name'
                    Columns = @(
                        @{ Key = 'Rank'; Label = '#'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Name'; Label = 'Pattern'; Console = $true; Pdf = $true }
                        @{ Key = 'Recommended'; Label = 'Recommended'; Type = 'badge'; Tones = @{ Yes = 'good'; No = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Score'; Label = 'Score'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Why'; Label = 'Why'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'TradeOffs'; Label = 'Trade-offs'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Problem'; Label = 'Problem it solves'; Type = 'wide' }
                        @{ Key = 'Link'; Label = 'Architecture Center'; Type = 'link'; Text = 'Docs' }
                    ) })
            Hint     = 'Pipe the patterns you choose into New-AACArchitectureDesign -Brief <brief>; -RecommendedOnly keeps the ones that fit.'
        }
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'pattern' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
