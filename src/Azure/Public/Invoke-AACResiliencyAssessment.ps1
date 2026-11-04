function Invoke-AACResiliencyAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Checks your resources against the Azure Proactive Resiliency Library, with
        Resource Graph: which recommendations they miss, and which only a person can
        check - with a console view, objects, and CSV, HTML and PDF reports.
    .DESCRIPTION
        Read-only (Reader is enough). Get-AACResiliencyRecommendation lists what the
        Azure Proactive Resiliency Library (APRL) recommends; this runs APRL's own
        queries, at the pinned commit shipped with the module, to say which resources
        don't follow it.

        About half of APRL's recommendations have a query. The rest are listed as
        Manual when you use that resource type, because they need a person: a report
        with no failures doesn't mean they are met.

          Fail         the query listed resources
          Pass         you have resources of this type, and it listed none
          Manual       APRL has no query for it
          Not checked  the query failed

        Recommendations for types you don't use aren't shown. Queries are only run for
        types you have. Findings are the failed recommendations, with their impact as
        severity; every affected resource is in the report.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceType
        Only these resource types; wildcards work, e.g. 'Microsoft.Storage/*'.
    .PARAMETER Impact
        Only these impacts: High, Medium, Low.
    .PARAMETER Status
        Show only checks with these statuses.
    .PARAMETER SuppressionFile
        A JSON file of findings you have reviewed and accepted. Each entry names a
        finding by its FindingKey, or by source (Resiliency) and rule (and a subject,
        wildcards allowed), with the reason and, if you like, an expiry date:
        [{ "key": "a1b2c3d4e5f60718", "reason": "Accepted risk", "expires": "2027-01-01" }].
        They leave the counts, and the report lists them with their reasons.
    .PARAMETER PreviousPath
        A findings CSV from an earlier run (-CsvPath): each finding is then marked New
        or Open, and the report lists what has been resolved.
    .PARAMETER CsvPath
        Write the findings to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the checks.
    .PARAMETER NoDisplay
        Return the checks without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Connect-AAC
        Invoke-AACResiliencyAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -HtmlPath .\Resiliency.html
        A subscription against APRL, as a report.
    .EXAMPLE
        Invoke-AACResiliencyAssessment -ResourceType 'Microsoft.Storage/*' -Impact High -Status Fail -NoDisplay
        The storage recommendations of high impact that fail, as objects.
    .EXAMPLE
        Invoke-AACResiliencyAssessment -CsvPath .\new.csv -PreviousPath .\last.csv
        What has changed since the last run.
    .OUTPUTS
        AAC.ResiliencyCheck
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResiliencyCheck')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [SupportsWildcards()]
        [string[]] $ResourceType = @('*'),

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Impact,

        [ValidateSet('Fail', 'Pass', 'Manual', 'Not checked')]
        [string[]] $Status,

        [string] $SuppressionFile,

        [string] $PreviousPath,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure resiliency assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    # Before any Azure call: a bad file should stop the run now, not after minutes of reading.
    $suppression = if ($SuppressionFile) { Read-AACSuppressionFile -Path (& $resolve $SuppressionFile) } else { $null }
    $previous = & $resolve $PreviousPath
    if ($previous) { $null = Invoke-AACFindingReview -PreviousPath $previous }
    $catalogue = Get-AACServiceBaseline -Set Resiliency -ResourceType $ResourceType
    $wanted = @($catalogue.Rows | Where-Object { -not $Impact -or $Impact -contains $_.Impact })
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); Wanted = $wanted }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Azure resiliency assessment' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        Update-AACProgress -Id 'types' -Indeterminate -Description 'Finding the resource types in use'
        $inUse = Invoke-AACGraphBatch -Query ([ordered]@{ types = @{ Query = 'resources | summarize used = count() by type = tolower(type)' } }) -SubscriptionId $scope.GraphScope
        $present = @{}
        foreach ($row in @(if ($inUse.Rows.Contains('types')) { $inUse.Rows['types'] | Where-Object { $null -ne $_ } })) { $present[[string]$row['type']] = [int64]$row['used'] }
        Update-AACProgress -Id 'types' -Complete -Description "$($present.Count) resource type(s) in use"
        $queries = [ordered]@{}
        foreach ($entry in $request.Wanted) {
            if ($entry.Query -and $present.Contains($entry.ResourceType.ToLowerInvariant())) { $queries[$entry.Guid] = @{ Query = $entry.Query } }
        }
        Update-AACProgress -Id 'run' -Total $queries.Count -Description "Running $($queries.Count) APRL queries"
        $read = if ($queries.Count) { Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @($queries.Keys) -OnProgress { param($QueryName, $Done, $Total) Update-AACProgress -Id 'run' -Increment 1 } } else { @{ Rows = @{}; Errors = @{} } }
        Update-AACProgress -Id 'run' -Complete -Description "Ran $($queries.Count - @($read.Errors.Keys).Count) of $($queries.Count) APRL queries"
        @{ Read = $read; Scope = $scope; Present = $present }
    }

    $assessment = ConvertTo-AACResiliencyAssessment -Recommendation $wanted -Present $outcome.Present -Read $outcome.Read
    $review = Invoke-AACFindingReview -Finding $assessment.Findings -Suppression $suppression -PreviousPath $previous
    $shown = @(if ($Status) { $assessment.Checks | Where-Object { $Status -contains $_.Status } } else { $assessment.Checks })
    $source = $catalogue.Source
    $model = @{ Checks = $shown; Items = $assessment.Items; Notices = $assessment.Notices }
    $report = Get-AACCatalogReport -Assessment $model -Review $review -Group 'ResourceType' -GroupLabel 'Resource type' `
        -Subtitle 'Your resources against the Azure Proactive Resiliency Library' `
        -Fact ([ordered]@{ Scope = $outcome.Scope.Label; Source = "$($source.Name), commit $($source.Commit.Substring(0, 12)) ($($source.License))"; Note = 'About half of the recommendations have a query. The rest show as Manual: a report with no failures does not mean they are met.' }) `
        -Hint '-ResourceType and -Impact narrow it; -Status Fail for what to fix; -SuppressionFile sets aside what was accepted; -PreviousPath shows what changed; -HtmlPath, -PdfPath or -CsvPath for a report.'
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $review.Findings -Noun 'finding' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $shown -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
