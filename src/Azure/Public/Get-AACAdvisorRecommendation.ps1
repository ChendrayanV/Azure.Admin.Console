function Get-AACAdvisorRecommendation {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Gets a consolidated, flattened view of Azure Advisor recommendations
        (Resource Graph's advisorresources table): a Spectre.Console summary
        at the prompt, PowerShell objects down a pipeline, and optional CSV
        PDF and interactive HTML exports.
    .DESCRIPTION
        Reads every Azure Advisor recommendation the signed-in account can
        see (or only those in -SubscriptionId) from the advisorresources table
        in Azure Resource Graph, over REST with the Connect-AAC sign-in - no
        Az modules needed. Every Advisor category is covered: Cost, Security,
        Reliability (HighAvailability in the API), Operational excellence and
        Performance.

        Each recommendation's nested JSON is flattened to one flat row:
        subscription name, resource group, impacted resource name and type,
        category, impact, problem and solution, estimated monthly and annual
        savings with currency, retirement date and feature (for service
        retirement recommendations), last updated time and links. Advisor's
        free-form extendedProperties bag, whose keys differ per recommendation
        type, is always included as one "key=value; key=value" column; with
        -ExpandExtendedProperty each key also gets its own Ext_<key> column.

        Every object carries exactly the same properties (including every
        Ext_ column found in the whole result), because Export-Csv takes its
        header row from the first object only - ragged objects would silently
        lose columns.

        Postponed and dismissed recommendations (Advisor suppressions) are
        left out, as in the Azure portal; -IncludeSuppressed brings them back
        with Status 'Postponed' or 'Dismissed'.

        What you get depends on where the command runs:
          at the prompt    a Spectre.Console view: the account and scope,
                           tiles with the number of recommendations, high /
                           medium / low impact, resources affected and
                           estimated monthly savings, then one colour-coded
                           table per category listing every affected
                           resource, shown a screen at a time
          piped onward     the AAC.AdvisorRecommendation objects, with no
                           summary (e.g. | Where-Object, | Export-Csv)
          -PassThru        the summary and the objects, e.g. to keep them
                           in a variable
          -NoDisplay       the objects only, never the summary (scripts,
                           scheduled tasks)

        PowerShell can't tell "$r = Get-AACAdvisorRecommendation" from a
        plain call, so to capture the objects in a variable add -PassThru
        or -NoDisplay.

        In the tables, rows are grouped by recommendation under an impact
        badge (HIGH red, MEDIUM orange, LOW grey), savings are green, and a
        retirement date is red within 90 days, orange within 180 and gold
        after that. When the view is longer than the terminal it is paged:
        press any key for the next page, or A to show the rest. -NoPaging
        turns that off; paging is also skipped automatically when output is
        redirected.

        Exports:
          -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
                      recommendation per resource)
          -PdfPath    a landscape A4 PDF: a summary (totals, category by
                      impact, subscriptions, estimated savings), every
                      recommendation type consolidated with its affected
                      resource count, then one section per category listing
                      the affected resources under each recommendation
          -HtmlPath   a self-contained, interactive HTML report: clickable
                      tiles and charts (by category, impact, subscription,
                      recommendation) that filter a table of every
                      recommendation, grouped by recommendation, with
                      search, filters, sorting, subtotals of savings, Azure
                      portal links and a CSV download of what is shown

        When any of -CsvPath, -PdfPath or -HtmlPath is given, the console
        shows only the progress and the files written - the report is in
        the files. Add -PassThru to get the objects as well.

        Savings are Advisor's own estimates. Two recommendations can overlap
        (e.g. a reservation and a right-size for the same VM), so a total is
        an upper bound; totals are kept per currency, never converted.

        PDF export needs Windows and PowerShell 7.4 or later; objects and
        CSV work everywhere.
    .PARAMETER SubscriptionId
        Only get recommendations in these subscriptions. Defaults to every
        subscription the signed-in account can see.
    .PARAMETER Category
        Only get these categories: Cost, Security, Reliability,
        OperationalExcellence, Performance.
    .PARAMETER Impact
        Only get recommendations with these impacts: High, Medium, Low.
    .PARAMETER IncludeSuppressed
        Also get recommendations that were postponed or dismissed in
        Advisor, with Status set to 'Postponed' or 'Dismissed'.
    .PARAMETER ExpandExtendedProperty
        Add one Ext_<key> column per key of Advisor's extendedProperties bag
        (the union of keys over every recommendation returned), next to the
        combined ExtendedProperties column.
    .PARAMETER CsvPath
        Also write the recommendations to this CSV file. An existing file is
        overwritten; missing folders are created.
    .PARAMETER PdfPath
        Also write the report to this PDF file. An existing file is
        overwritten; missing folders are created.
    .PARAMETER HtmlPath
        Also write an interactive HTML report to this file. An existing file
        is overwritten; missing folders are created.
    .PARAMETER Title
        The PDF and HTML report's title. Defaults to 'Azure Advisor
        recommendations'.
    .PARAMETER PassThru
        Show the summary and also return the recommendation objects.
    .PARAMETER NoDisplay
        Return the recommendation objects without showing the summary.
    .PARAMETER NoPaging
        Show the whole view at once instead of a screen at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACAdvisorRecommendation
        Shows the summary of every Advisor recommendation you can see.
    .EXAMPLE
        Get-AACAdvisorRecommendation -CsvPath .\out\Advisor.csv -PdfPath .\out\Advisor.pdf -HtmlPath .\out\Advisor.html
        Writes every recommendation to a CSV file, a PDF report and an interactive HTML report.
    .EXAMPLE
        Get-AACAdvisorRecommendation -Category Cost |
            Group-Object SavingsCurrency |
            ForEach-Object { '{0} {1:N2} per month' -f $_.Name, ($_.Group | Measure-Object MonthlySavings -Sum).Sum }
        Totals Advisor's estimated monthly savings, per currency.
    .EXAMPLE
        $high = Get-AACAdvisorRecommendation -Impact High -PassThru
        Shows the summary of high-impact recommendations and keeps the objects in $high.
    .EXAMPLE
        Get-AACAdvisorRecommendation -Category Reliability |
            Where-Object RetirementDate |
            Sort-Object RetirementDate |
            Format-Table RetirementDate, RetiringFeature, ResourceName, SubscriptionName
        Lists resources affected by upcoming Azure service retirements, soonest first.
    .EXAMPLE
        Get-AACAdvisorRecommendation -NoDisplay -ExpandExtendedProperty -CsvPath .\Advisor.csv
        In a scheduled script: writes the CSV, with every extendedProperties key as its own column, and shows nothing.
    .EXAMPLE
        Get-AACAdvisorRecommendation | Export-Csv -Path .\advisor.csv -NoTypeInformation -Delimiter ';'
        Uses Export-Csv directly, for control over its options.
    .OUTPUTS
        AAC.AdvisorRecommendation (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.AdvisorRecommendation')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateSet('Cost', 'Security', 'Reliability', 'OperationalExcellence', 'Performance')]
        [string[]] $Category,

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Impact,

        [switch] $IncludeSuppressed,

        [switch] $ExpandExtendedProperty,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Azure Advisor recommendations',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    # Piped onward (| Where-Object, | Export-Csv ...) the objects are the
    # point, so no summary is drawn over them.
    # An export means the report is in the files: the console shows only
    # the title, the progress and the files written.
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $exporting = [bool]($CsvPath -or $PdfPath -or $HtmlPath)
    $showSummary = $interactive -and -not $exporting
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward

    # Resolve paths now, relative to the caller's location, so a bad path
    # fails before any Azure call.
    $csvFullPath = if ($CsvPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath) }
    $pdfFullPath = if ($PdfPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PdfPath) }
    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) }

    # Signed in? (Get-AACAccessToken says what to do when not.)
    $null = Get-AACAccessToken

    # advisorresources also holds suppressions, configurations and scores,
    # so the type filter matters. Nested fields are flattened here; only the
    # extendedProperties bag (different keys per recommendation type) comes
    # back as an object.
    $recommendationQuery = @'
advisorresources
| where type =~ 'microsoft.advisor/recommendations'
| project id, name, subscriptionId, resourceGroup,
    category = tostring(properties.category),
    impact = tostring(properties.impact),
    impactedField = tostring(properties.impactedField),
    impactedValue = tostring(properties.impactedValue),
    resourceId = tostring(properties.resourceMetadata.resourceId),
    resourceType = tostring(properties.resourceMetadata.resourceType),
    problem = tostring(properties.shortDescription.problem),
    solution = tostring(properties.shortDescription.solution),
    potentialBenefits = tostring(properties.potentialBenefits),
    recommendationTypeId = tostring(properties.recommendationTypeId),
    learnMoreLink = tostring(properties.learnMoreLink),
    lastUpdated = tostring(properties.lastUpdated),
    extendedProperties = properties.extendedProperties
'@
    # A suppression's ID is its recommendation's ID + /suppressions/<name>.
    # ttl '-1' means dismissed; any other ttl is a postponement.
    $suppressionQuery = @'
advisorresources
| where type =~ 'microsoft.advisor/suppressions'
| project recommendationId = tolower(substring(id, 0, indexof(tolower(id), '/suppressions/'))),
    ttl = tostring(properties.ttl),
    expires = tostring(properties.expirationTimeStamp)
'@
    $subscriptionQuery = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"

    # The title first, then a line per step - as every command shows them.
    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Azure Advisor' -Color 'deepskyblue3_1'
    }
    $data = Invoke-AACProgress -ScriptBlock {
        # The three queries at once (Invoke-AACGraphBatch); subscription
        # names tenant-wide.
        Update-AACProgress -Id 'read' -Total 3 -Description 'Reading Advisor recommendations, postponed and dismissed ones, and subscription names'
        $batch = Invoke-AACGraphBatch -AsObject -SubscriptionId $SubscriptionId -Query ([ordered]@{
                recommendations = $recommendationQuery
                suppressions    = $suppressionQuery
                subscriptions   = @{ Tenant = $true; Query = $subscriptionQuery }
            }) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total queries)" }
        $recommendationRows = @($batch.Rows['recommendations'])
        $suppressionRows = @($batch.Rows['suppressions'])
        $subscriptionRows = @($batch.Rows['subscriptions'])
        $subscriptionCount = @($recommendationRows | ForEach-Object { $_.subscriptionId } | Select-Object -Unique).Count
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} Advisor recommendation(s) in {1:N0} subscription(s)' -f $recommendationRows.Count, $subscriptionCount)
        @{ Recommendations = $recommendationRows; Suppressions = $suppressionRows; Subscriptions = $subscriptionRows }
    }

    $lastSegment = { param([string] $Id) if ($Id) { $Id.TrimEnd('/').Split('/')[-1] } }
    $toNumber = {
        param($Value)
        $number = 0.0
        if ($null -ne $Value -and [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$number)) { $number }
    }
    $toDate = {
        param($Value)
        $date = [datetimeoffset]::MinValue
        if ($Value -and [datetimeoffset]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) { $date.UtcDateTime }
    }
    $toText = {
        param($Value)
        if ($null -eq $Value) { '' }
        elseif ($Value -is [string] -or $Value -is [ValueType]) { [string]$Value }
        else { $Value | ConvertTo-Json -Depth 10 -Compress }
    }

    $subscriptionNames = @{}
    foreach ($subscription in $data.Subscriptions) {
        $subscriptionNames[$subscription.subscriptionId] = $subscription.name
    }
    $suppressions = @{}
    foreach ($suppression in $data.Suppressions) {
        if ($suppression.recommendationId) {
            $suppressions[$suppression.recommendationId] = $suppression
        }
    }

    # The portal's names; the API still says HighAvailability for Reliability.
    $categoryNames = @{ HighAvailability = 'Reliability' }
    $categoryOrder = @{ Cost = 0; Security = 1; Reliability = 2; OperationalExcellence = 3; Performance = 4 }
    $impactOrder = @{ High = 0; Medium = 1; Low = 2 }

    $recommendations = foreach ($row in $data.Recommendations) {
        $categoryName = if ($categoryNames.ContainsKey([string]$row.category)) { $categoryNames[[string]$row.category] } else { [string]$row.category }
        if ($Category -and $categoryName -notin $Category) { continue }
        if ($Impact -and [string]$row.impact -notin $Impact) { continue }

        $suppression = $suppressions[([string]$row.id).ToLowerInvariant()]
        $status = if (-not $suppression) { 'Active' } elseif ($suppression.ttl -eq '-1') { 'Dismissed' } else { 'Postponed' }
        if ($status -ne 'Active' -and -not $IncludeSuppressed) { continue }

        $extended = [ordered]@{}
        if ($row.extendedProperties -is [System.Management.Automation.PSCustomObject]) {
            foreach ($property in @($row.extendedProperties.PSObject.Properties | Sort-Object -Property Name)) {
                $extended[$property.Name] = & $toText $property.Value
            }
        }
        $ext = { param([string] $Name) if ($extended.Contains($Name)) { $extended[$Name] } }

        # A subscription-level recommendation has no resource group and its
        # resource ID is the subscription itself.
        $resourceId = if ($row.resourceId) { [string]$row.resourceId } else { '' }
        $retiringFeature = & $ext 'retirementFeatureName'
        if (-not $retiringFeature) { $retiringFeature = & $ext 'retiringFeature' }

        [pscustomobject]@{
            PSTypeName           = 'AAC.AdvisorRecommendation'
            Category             = $categoryName
            Impact               = [string]$row.impact
            Status               = $status
            SubscriptionName     = $subscriptionNames[$row.subscriptionId]
            SubscriptionId       = $row.subscriptionId
            ResourceGroup        = [string]$row.resourceGroup
            ResourceName         = if ($row.impactedValue) { [string]$row.impactedValue } else { & $lastSegment $resourceId }
            ResourceType         = if ($row.resourceType) { [string]$row.resourceType } else { [string]$row.impactedField }
            Problem              = [string]$row.problem
            Solution             = [string]$row.solution
            PotentialBenefits    = [string]$row.potentialBenefits
            SubCategory          = [string](& $ext 'recommendationSubCategory')
            MonthlySavings       = & $toNumber (& $ext 'savingsAmount')
            AnnualSavings        = & $toNumber (& $ext 'annualSavingsAmount')
            SavingsCurrency      = [string](& $ext 'savingsCurrency')
            RetirementDate       = & $toDate (& $ext 'retirementDate')
            RetiringFeature      = [string]$retiringFeature
            LastUpdated          = & $toDate $row.lastUpdated
            SuppressionExpires   = if ($suppression) { & $toDate $suppression.expires } else { $null }
            RecommendationTypeId = [string]$row.recommendationTypeId
            LearnMoreLink        = [string]$row.learnMoreLink
            ResourceId           = $resourceId
            RecommendationId     = [string]$row.id
            ExtendedProperties   = ($extended.Keys | ForEach-Object { "$_=$($extended[$_])" }) -join '; '
            _Extended            = $extended
        }
    }

    $recommendations = @($recommendations | Sort-Object -Property @(
            @{ Expression = { $o = $categoryOrder[$_.Category]; if ($null -eq $o) { 9 } else { $o } } }
            @{ Expression = { $o = $impactOrder[$_.Impact]; if ($null -eq $o) { 9 } else { $o } } }
            'Problem', 'SubscriptionName', 'ResourceGroup', 'ResourceName'
        ))

    # Give every object the same Ext_ columns (the union over the whole
    # result, sorted), then drop the working copy of the bag.
    $extendedKeys = if ($ExpandExtendedProperty) {
        @($recommendations | ForEach-Object { $_._Extended.Keys } | Sort-Object -Unique)
    }
    foreach ($recommendation in $recommendations) {
        foreach ($key in $extendedKeys) {
            $value = if ($recommendation._Extended.Contains($key)) { $recommendation._Extended[$key] } else { '' }
            $recommendation.PSObject.Properties.Add([psnoteproperty]::new("Ext_$key", $value))
        }
        $recommendation.PSObject.Properties.Remove('_Extended')
    }

    # Where the recommendations came from, for the summary and the PDF.
    $scope = [ordered]@{
        Subscriptions = if ($SubscriptionId) { $SubscriptionId -join ', ' } else { 'every subscription the account can see' }
    }
    if ($Category) { $scope['Categories'] = $Category -join ', ' }
    if ($Impact) { $scope['Impact'] = $Impact -join ', ' }
    $scope['Postponed / dismissed'] = if ($IncludeSuppressed) { 'included' } else { 'not included' }

    if ($recommendations.Count -eq 0 -and -not $showSummary) {
        Write-Warning 'No Azure Advisor recommendations were found for the signed-in account and the given filters.'
    }

    $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $recommendations -Noun 'recommendation' -PdfPath $pdfFullPath -WritePdf {
        Write-AACAdvisorRecommendationPdf -Recommendation $recommendations -Path $pdfFullPath -Title $Title -Detail $scope
    } -HtmlPath $htmlFullPath -WriteHtml {
        Write-AACAdvisorRecommendationHtml -Recommendation $recommendations -Path $htmlFullPath -Title $Title -Detail $scope
    }

    if ($showSummary) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACAdvisorSummary -Recommendation $recommendations -Scope $scope -NoTitle
            Show-AACAdvisorTable -Recommendation $recommendations
            [Spectre.Console.AnsiConsole]::WriteLine()
            if ($recommendations.Count -gt 0) {
                Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath, -PdfPath or -HtmlPath for a report.[/]'
            }
        }
    }

    if ($returnObjects) {
        $recommendations
    }
}
