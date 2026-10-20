function Get-AACTagUsage {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows how tags are really used across resources, resource groups
        and subscriptions - each tag name, its coverage and values - and
        what is inconsistent: names that differ only in casing,
        near-duplicates, values in mixed casing, required tags missing.
    .DESCRIPTION
        Counts, read-only and in Azure Resource Graph, every tag name on
        resources, resource groups and subscriptions, with its distinct
        values, and how many of each carry any tag at all. Azure's own
        hidden tags are left out.

        Each tag name as spelled (AAC.TagUsage): uses per kind of scope,
        Coverage (the share of resources that carry it), the number of
        distinct values and a sample, and findings:
          Medium  the same name in other casing - Azure treats tag names
                  case-insensitively, so 'Environment' and 'environment'
                  collide in cost reports and policies; a -RequiredTag on
                  fewer than -CoverageTarget percent of resources
          Low     near-duplicates ('cost-center', 'CostCenter',
                  'cost_center'); the same value in different casing
          Info    a tag used once
        Reader is enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER RequiredTag
        Tags every resource should carry: each gets a row, used or not, with
        its coverage.
    .PARAMETER CoverageTarget
        A required tag on fewer than this percentage of resources is a
        finding. Default 90.
    .PARAMETER WithFinding
        Only tags with a finding.
    .PARAMETER CsvPath
        Write the tags to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the tags.
    .PARAMETER NoDisplay
        Return the tags without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACTagUsage
        Every tag name, the inconsistent ones first.
    .EXAMPLE
        Get-AACTagUsage -RequiredTag 'env', 'owner', 'costcenter' -HtmlPath .\Tags.html
        How far the required tags reach, as a report.
    .EXAMPLE
        Get-AACTagUsage -WithFinding -NoDisplay | Select-Object Tag, Findings
        Only the tags to tidy up.
    .OUTPUTS
        AAC.TagUsage
    #>
    [CmdletBinding()]
    [OutputType('AAC.TagUsage')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $RequiredTag,

        [ValidateRange(1, 100)]
        [int] $CoverageTarget = 90,

        [switch] $WithFinding,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Tag usage',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); RequiredTag = @($RequiredTag | Where-Object { $_ }); CoverageTarget = $CoverageTarget }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Tag usage' -Color 'gold1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $query = Get-AACTagUsageQuery
        Update-AACProgress -Id 'read' -Total $query.Count -Description 'Counting the tags'
        $read = Invoke-AACGraphBatch -Query $query -SubscriptionId $scope.GraphScope -AllowFailure @($query.Keys) -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Counted the $QueryName ($Done of $Total)"
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Counted {0:N0} tag name(s)' -f (@($read.Rows['resourceTags']).Count + @($read.Rows['groupTags']).Count))
        @{ Result = (ConvertTo-AACTagUsage -Read $read -RequiredTag $request.RequiredTag -CoverageTarget $request.CoverageTarget); Scope = $scope }
    }

    $tags = @($outcome.Result.Tags)
    if ($WithFinding) { $tags = @($tags | Where-Object Findings) }
    $t = $outcome.Result.Totals
    $stats = $outcome.Result.Stats
    $rank = Get-AACSeverityRank
    $findingCount = @($tags | Where-Object Findings).Count
    $report = @{
        Subtitle = 'Tag usage: every tag name on resources, resource groups and subscriptions, its coverage and values, and what is inconsistent'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Resources = ('{0:N0} ({1:N0} tagged)' -f $t.Resources, $t.TaggedResources); 'Resource groups' = ('{0:N0} ({1:N0} tagged)' -f $t.ResourceGroups, $t.TaggedResourceGroups); Required = $(if ($RequiredTag) { $RequiredTag -join ', ' } else { 'none given (-RequiredTag)' }) }
        Status   = $(if (@($tags | Where-Object Severity -EQ 'Medium').Count) { 'Warning' } else { 'Success' })
        Headline = "$($stats.Tags) tag name(s); $($stats.Coverage)% of resources carry a tag; $findingCount with a finding$(if ($stats.CaseClashes) { ", $($stats.CaseClashes) clashing in casing" })"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Tags; Label = 'tag names'; Tone = 'info' }
            @{ Value = "$($stats.Coverage)%"; Label = 'resources tagged'; Tone = $(if ($stats.Coverage -ge $CoverageTarget) { 'good' } else { 'warn' }) }
            @{ Value = '{0:N0}' -f $stats.CaseClashes; Label = 'casing clashes'; Tone = $(if ($stats.CaseClashes) { 'warn' } else { 'good' }); Table = 'tags'; Filters = @{ Severity = 'Medium' } }
            @{ Value = '{0:N0}' -f $findingCount; Label = 'with a finding'; Tone = $(if ($findingCount) { 'warn' } else { 'good' }) }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Most used tags'; Items = @($tags | Sort-Object { $_.Resources + $_.ResourceGroups + $_.Subscriptions } -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Tag; Value = $_.Resources + $_.ResourceGroups + $_.Subscriptions; Filter = $_.Tag } }); Table = 'tags'; Column = 'Tag'; Tone = 'info'; Console = $true }
            @{ Title = 'Coverage of resources (%)'; Items = @($tags | Where-Object { $_.Required -or $_.Coverage -gt 0 } | Sort-Object Coverage -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Tag; Value = $_.Coverage } }); Tone = 'good' }
        )
        Tables   = @(
            @{ Id = 'tags'; Title = 'Tags'; Section = 'Tags'; Rows = $tags; Noun = 'tags'; ConsoleLimit = 30
                Empty = 'No tags found.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Tag'; Label = 'Tag'; Console = $true; Pdf = $true }
                    @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'ResourceGroups'; Label = 'Groups'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Subscriptions'; Label = 'Subs'; Type = 'number'; Console = $true }
                    @{ Key = 'Coverage'; Label = 'Coverage'; Type = 'score'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Values'; Label = 'Values'; Type = 'number'; Console = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'SampleValues'; Label = 'Sample values'; Type = 'wide' }
                    @{ Key = 'Required'; Label = 'Required'; Facet = $true }
                ) }
        )
        Hint     = '-RequiredTag checks coverage of the tags you need; -WithFinding shows only what to tidy; -NoDisplay returns the tags; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $tags -Noun 'tag' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $tags -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
