function Invoke-AACLandingZoneAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Checks the estate against the Azure Landing Zone checklist, with Resource
        Graph: what fails, what only a person can judge, and what no query can
        answer - with a console view, objects, and CSV, HTML and PDF reports.
    .DESCRIPTION
        Read-only (Reader is enough). Runs the Resource Graph queries of the Azure
        Landing Zone checklist (github.com/martinopedal/alz-graph-queries, at a
        pinned commit shipped with the module): about 130 of its 206 items can be
        queried, and the rest are listed as Manual, with why.

        These are community queries, and they don't all measure the same thing. So
        a check's status says what its evidence can bear:

          Fail         found something that doesn't comply
          Review       as Fail, but judged by a name, which proves little
          Pass         found things, and all comply
          Present      can only say the resource is there
          No evidence  nothing came back: not used, or not needed. Not a pass
          Manual       Resource Graph can't answer this one
          Not checked  the query failed

        A failed check isn't always a fault: many items depend on your design, such
        as those that apply only if you run ExpressRoute. Read it as a list to go
        through, not a score, which is why there is no score. Findings are the Fail
        and Review checks; Review counts as Info. Test-AACAlzPolicy compares your
        policy assignments with the landing zone's, which this doesn't.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups. Queries about
        management groups themselves always read the whole tenant.
    .PARAMETER Category
        Only these checklist categories, such as Security or 'Network Topology and
        Connectivity'. Wildcards work.
    .PARAMETER Severity
        Only these severities: High, Medium, Low.
    .PARAMETER Status
        Show only checks with these statuses.
    .PARAMETER SuppressionFile
        A JSON file of findings you have reviewed and accepted. Each entry names a
        finding by its FindingKey, or by source (LandingZone) and rule (and a subject,
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
        Invoke-AACLandingZoneAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\LandingZone.html
        The landing zones against the checklist, as a report.
    .EXAMPLE
        Invoke-AACLandingZoneAssessment -Category 'Network*' -Status Fail, Review -NoDisplay
        The network checks to look at, as objects.
    .EXAMPLE
        Invoke-AACLandingZoneAssessment -CsvPath .\lz-new.csv -PreviousPath .\lz-last.csv -SuppressionFile .\accepted.json
        What changed since last time, leaving out what has been accepted.
    .OUTPUTS
        AAC.LandingZoneCheck
    #>
    [CmdletBinding()]
    [OutputType('AAC.LandingZoneCheck')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [SupportsWildcards()]
        [string[]] $Category,

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Severity,

        [ValidateSet('Fail', 'Review', 'Pass', 'Present', 'No evidence', 'Manual', 'Not checked')]
        [string[]] $Status,

        [string] $SuppressionFile,

        [string] $PreviousPath,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure Landing Zone assessment',

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
    $catalogue = Get-AACServiceBaseline -Set LandingZone
    $wanted = @($catalogue.Rows | Where-Object {
            $row = $_
            (-not $Category -or @($Category | Where-Object { $row.Category -like $_ }).Count) -and (-not $Severity -or $Severity -contains $row.Severity)
        })
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); Wanted = $wanted }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Azure Landing Zone assessment' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $queries = [ordered]@{}
        foreach ($entry in @($request.Wanted | Where-Object { $_.Queryable -and $_.Query })) {
            $queries[$entry.Guid] = if ($entry.Query -match 'managementgroups') { @{ Tenant = $true; Query = $entry.Query } } else { @{ Query = $entry.Query } }
        }
        Update-AACProgress -Id 'run' -Total $queries.Count -Description "Running $($queries.Count) checklist queries"
        $read = if ($queries.Count) { Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @($queries.Keys) -OnProgress { param($QueryName, $Done, $Total) Update-AACProgress -Id 'run' -Increment 1 } } else { @{ Rows = @{}; Errors = @{} } }
        Update-AACProgress -Id 'run' -Complete -Description "Ran $($queries.Count - @($read.Errors.Keys).Count) of $($queries.Count) checklist queries"
        @{ Read = $read; Scope = $scope }
    }

    $assessment = ConvertTo-AACLandingZoneAssessment -Item $wanted -Read $outcome.Read
    $review = Invoke-AACFindingReview -Finding $assessment.Findings -Suppression $suppression -PreviousPath $previous
    $shown = @(if ($Status) { $assessment.Checks | Where-Object { $Status -contains $_.Status } } else { $assessment.Checks })
    $source = $catalogue.Source
    $model = @{ Checks = $shown; Items = $assessment.Items; Notices = $assessment.Notices }
    $report = Get-AACCatalogReport -Assessment $model -Review $review -Group 'Category' -GroupLabel 'Category' `
        -Subtitle 'The Azure Landing Zone checklist, checked with Azure Resource Graph' `
        -Fact ([ordered]@{ Scope = $outcome.Scope.Label; Source = "$($source.Name), commit $($source.Commit.Substring(0, 12)) ($($source.License))"; Note = 'Community queries. A failed check is a question to answer, not always a fault: many items depend on your design.' }) `
        -Hint '-Category and -Severity narrow it; -Status Fail, Review for what to look at; -SuppressionFile sets aside what was accepted; -PreviousPath shows what changed; -HtmlPath, -PdfPath or -CsvPath for a report.'
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $review.Findings -Noun 'finding' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $shown -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
