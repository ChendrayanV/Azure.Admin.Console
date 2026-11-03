function Get-AACResiliencyRecommendation {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        The Azure Proactive Resiliency Library's (APRL) recommendations for a
        resource type: what to do, its impact and why it helps.
    .DESCRIPTION
        Read from a copy of APRL that ships with the module: no sign-in, nothing
        in Azure is read or changed. These are recommendations to review, not
        results: nothing here says whether a resource follows them. Recommendations
        APRL has disabled are left out.
    .PARAMETER ResourceType
        The resource types, wildcards allowed: Microsoft.Web/sites, Microsoft.Web/*.
        Tab completes them. Every type by default.
    .PARAMETER Impact
        Only this impact: High, Medium or Low.
    .PARAMETER CsvPath
        Write the recommendations to this CSV file.
    .PARAMETER HtmlPath
        Write the report to this HTML file.
    .PARAMETER PdfPath
        Write the report to this PDF file.
    .PARAMETER Title
        The report's title.
    .PARAMETER PassThru
        Show the view and also return the recommendations.
    .PARAMETER NoDisplay
        Return the recommendations without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACResiliencyRecommendation -ResourceType Microsoft.Storage/storageAccounts
        What APRL recommends for a storage account.
    .EXAMPLE
        Get-AACResiliencyRecommendation -ResourceType 'Microsoft.Web/*' -Impact High -PdfPath .\resiliency.pdf
        The high impact recommendations for App Service, as a report.
    .OUTPUTS
        AAC.ResiliencyRecommendation (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResiliencyRecommendation')]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({ param($Command, $Parameter, $Word) & (Get-Module -Name 'Azure.Admin.Console') { param($Typed) (Get-AACServiceBaseline -Set Resiliency -ResourceType @()).Types | Where-Object { $_ -like "*$Typed*" } } $Word })]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceType = @('*'),

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Impact,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure resiliency recommendations',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Resiliency recommendations' -Color 'deepskyblue3_1' }

    $baseline = Get-AACServiceBaseline -Set Resiliency -ResourceType $ResourceType
    $rows = @($baseline.Rows | Where-Object { -not $Impact -or $Impact -contains $_.Impact })
    $count = { param([string] $Value) @($rows | Where-Object Impact -EQ $Value).Count }
    $impactTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }
    $report = @{
        Facts    = [ordered]@{ 'Resource types' = $ResourceType -join ', '; Source = "$($baseline.Source.Name), commit $($baseline.Source.Commit.Substring(0, 12)) ($($baseline.Source.License))" }
        Status   = 'Info'
        Headline = "$($rows.Count) recommendation(s) for $(@($rows | ForEach-Object { $_.ResourceType } | Select-Object -Unique).Count) resource type(s): to review, not results. Nothing here says whether a resource follows them."
        Tiles    = @(
            @{ Value = '{0:N0}' -f $rows.Count; Label = 'recommendations'; Tone = 'info'; Table = 'resiliency' }
            @{ Value = '{0:N0}' -f (& $count 'High'); Label = 'high impact'; Tone = 'bad'; Table = 'resiliency'; Filters = @{ Impact = 'High' } }
            @{ Value = '{0:N0}' -f (& $count 'Medium'); Label = 'medium impact'; Tone = 'warn'; Table = 'resiliency'; Filters = @{ Impact = 'Medium' } }
            @{ Value = '{0:N0}' -f (& $count 'Low'); Label = 'low impact'; Tone = 'info'; Table = 'resiliency'; Filters = @{ Impact = 'Low' } }
        )
        Tables   = @(
            @{ Id = 'resiliency'; Title = 'Resiliency recommendations'; Section = 'Recommendations'; Rows = $rows; Noun = 'recommendations'; File = 'resiliency-recommendations'; GroupBy = @('ResourceType', 'Impact', 'Control'); ConsoleLimit = 30
                Empty = 'APRL has no recommendation for this. It covers some resource types, not all.'; EmptyStatus = 'Info'; Hover = @('Description'); HoverTitle = 'Name'
                Columns = @(
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'mono'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Recommendation'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'badge'; Tones = $impactTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Control'; Label = 'Area'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Benefit'; Label = 'Benefit'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Link'; Label = 'Learn more'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-ResourceType narrows it, wildcards allowed; -Impact High for what matters most; -HtmlPath for the full list.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'resiliency recommendation' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
