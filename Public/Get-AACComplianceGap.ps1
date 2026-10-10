function Get-AACComplianceGap {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Maps your Azure estate to compliance frameworks - CIS, PCI-DSS,
        HIPAA, SOC 2, GDPR, ISO 27001, NIST and the Microsoft cloud security
        benchmark - and lists the gaps by priority and effort, as a
        remediation roadmap, with what changed since the last run.
    .DESCRIPTION
        Reads, from Azure Resource Graph:
          Defender for Cloud  each regulatory compliance standard's controls
                              and the failing assessments under them
          Azure Policy        the regulatory compliance initiatives assigned,
                              control by control (their policy definition
                              groups), and the non-compliant resources
          Coverage            the resource types no policy evaluates
        Gaps (AAC.ComplianceGap): failing controls (High with 10 or more
        failing resources, else Medium), controls waiting for a manual
        attestation (Low), and frameworks asked for with -Framework that
        nothing assesses (High). Each has an effort - Low when remediation
        tasks fix it - and a roadmap phase: Quick win, Plan or Backlog.

        Progress: -BaselinePath reads a previous run's CSV (-CsvPath) and
        marks each gap New, Open or Closed - so a run a month later shows what
        was fixed.

        The report: a summary per framework (controls passed, failed,
        manual; compliance %), the gaps, the roadmap and the unscanned
        resource types. Read-only; Reader (and Security Reader for
        Defender) is enough. Certifications themselves (audit reports,
        expiry dates) aren't in Azure: see the Service Trust Portal.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Framework
        Only these frameworks; a framework asked for that nothing assesses
        is a gap. CIS, PCI-DSS, HIPAA, SOC2, GDPR, ISO27001, NIST or MCSB.
    .PARAMETER BaselinePath
        A previous run's CSV (-CsvPath): each gap is then New, Open or
        Closed.
    .PARAMETER SkipUnscanned
        Don't look for resources no policy evaluates (one heavier query).
    .PARAMETER CsvPath
        Write the gaps to this CSV file - next time's -BaselinePath.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the gaps.
    .PARAMETER NoDisplay
        Return the gaps without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACComplianceGap -Framework PCI-DSS, ISO27001 -CsvPath .\out\gaps-2026-10.csv
        The PCI-DSS and ISO 27001 gaps, saved as next month's baseline.
    .EXAMPLE
        Get-AACComplianceGap -BaselinePath .\out\gaps-2026-10.csv -HtmlPath .\out\Compliance.html
        What's new, still open and closed since last month, as a report.
    .EXAMPLE
        Get-AACComplianceGap -NoDisplay | Where-Object Phase -EQ 'Quick win'
        The gaps to close first.
    .OUTPUTS
        AAC.ComplianceGap
    #>
    [CmdletBinding()]
    [OutputType('AAC.ComplianceGap')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('CIS', 'PCI-DSS', 'HIPAA', 'SOC2', 'GDPR', 'ISO27001', 'NIST', 'MCSB')]
        [string[]] $Framework,

        [string] $BaselinePath,

        [switch] $SkipUnscanned,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Compliance gaps',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $baselineRows = @()
    if ($BaselinePath) {
        $baselineFile = & $resolve $BaselinePath
        if (-not (Test-Path -LiteralPath $baselineFile)) { throw "The baseline $baselineFile doesn't exist. Write one with -CsvPath first." }
        $baselineRows = @(Import-Csv -LiteralPath $baselineFile)
        if ($baselineRows.Count -and -not $baselineRows[0].PSObject.Properties['ControlId']) { throw "$baselineFile isn't a Get-AACComplianceGap CSV (it has no ControlId column)." }
    }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); SkipUnscanned = [bool]$SkipUnscanned }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Compliance gaps' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $queries = [ordered]@{
            controls    = "securityresources | where type =~ 'microsoft.security/regulatorycompliancestandards/regulatorycompliancecontrols' | extend parts = split(id, '/') | project id, subscriptionId, standard = tostring(parts[6]), control = name, description = tostring(properties.description), state = tostring(properties.state)"
            assessments = "securityresources | where type =~ 'microsoft.security/regulatorycompliancestandards/regulatorycompliancecontrols/regulatorycomplianceassessments' | where tostring(properties.state) =~ 'Failed' | extend parts = split(id, '/') | project id, subscriptionId, standard = tostring(parts[6]), control = tostring(parts[8]), assessment = tostring(properties.description), failedResources = toint(properties.failedResources), link = tostring(properties.assessmentDetailsLink)"
            policy      = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | extend setId = tolower(tostring(properties.policySetDefinitionId)), groups = properties.policyDefinitionGroupNames, state = tostring(properties.complianceState), effect = tostring(properties.policyDefinitionAction), resourceId = tolower(tostring(properties.resourceId)), definitionId = tolower(tostring(properties.policyDefinitionId)) | where isnotempty(setId) and array_length(groups) > 0 | mv-expand groupName = groups to typeof(string) | summarize nonCompliant = dcountif(resourceId, state =~ 'NonCompliant'), compliant = dcountif(resourceId, state =~ 'Compliant'), policies = dcount(definitionId), effects = make_set(effect, 5) by setId, groupName | join kind=inner (policyresources | where type =~ 'microsoft.authorization/policysetdefinitions' | where tostring(properties.metadata.category) =~ 'Regulatory Compliance' | project setId = tolower(id), initiative = tostring(properties.displayName)) on setId | extend id = strcat(setId, '|', groupName) | project-away setId1"
        }
        if (-not $request.SkipUnscanned) {
            $queries['unscanned'] = "resources | project resourceId = tolower(id), type = tolower(type) | join kind=leftanti (policyresources | where type =~ 'microsoft.policyinsights/policystates' | distinct resourceId = tolower(tostring(properties.resourceId))) on resourceId | summarize resources = count() by type | extend id = type | order by resources desc"
        }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading Defender for Cloud''s regulatory compliance and Azure Policy''s initiatives'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @($queries.Keys) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total)" }
        $notices = [System.Collections.Generic.List[string]]::new()
        $labels = @{ controls = 'Defender for Cloud regulatory compliance'; assessments = 'Defender for Cloud regulatory assessments'; policy = 'Azure Policy regulatory initiatives'; unscanned = 'unscanned resources' }
        foreach ($key in $read.Errors.Keys) { if ($read.Errors[$key]) { $notices.Add("The $($labels[$key]) couldn't be read: $($read.Errors[$key])") } }
        if (-not @($read.Rows['controls']).Count -and -not $read.Errors['controls']) { $notices.Add('Defender for Cloud reports no regulatory compliance standards here: they need a Defender plan (Defender CSPM, or any Defender for Cloud plan) on the subscriptions.') }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} Defender control state(s) and {1:N0} Policy control(s)' -f @($read.Rows['controls']).Count, @($read.Rows['policy']).Count)
        @{ Read = $read; Scope = $scope; Notices = $notices.ToArray() }
    }

    $read = $state.Read
    $result = ConvertTo-AACComplianceGap -Control @($read.Rows['controls'] | Where-Object { $_ }) -Assessment @($read.Rows['assessments'] | Where-Object { $_ }) -PolicyControl @($read.Rows['policy'] | Where-Object { $_ }) `
        -Unscanned @($read.Rows['unscanned'] | Where-Object { $_ } | Select-Object -First 50) -Framework @($Framework | Where-Object { $_ }) -Baseline $baselineRows -SubscriptionName $state.Scope.Names
    $gaps = @($result.Gaps)
    $s = $result.Stats
    $rank = Get-AACSeverityRank
    $phaseTones = @{ 'Quick win' = 'good'; Plan = 'warn'; Backlog = 'neutral'; Done = 'good' }
    $report = @{
        Subtitle = 'Compliance gaps: Defender for Cloud regulatory compliance and Azure Policy initiatives'
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Frameworks = $(if ($Framework) { $Framework -join ', ' } else { 'every one found' }); Baseline = $(if ($BaselinePath) { (Split-Path -Leaf $BaselinePath) } else { 'none' }) }
        Status   = $(if ($s.High) { 'Failed' } elseif ($s.Gaps) { 'Warning' } else { 'Success' })
        Headline = $(if ($s.Gaps) { "$($s.Gaps) gap(s) across $($s.Frameworks) framework(s): $($s.High) high - $($s.QuickWins) quick win(s)$(if ($BaselinePath) { "; $($s.New) new, $($s.Closed) closed since the baseline" })" } else { 'No gaps: every control assessed passes.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Gaps; Label = 'open gaps'; Tone = $(if ($s.Gaps) { 'warn' } else { 'good' }); Table = 'gaps' }
            @{ Value = '{0:N0}' -f $s.High; Label = 'high priority'; Tone = $(if ($s.High) { 'bad' } else { 'good' }); Table = 'gaps'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $s.QuickWins; Label = 'quick wins'; Tone = 'good'; Table = 'gaps'; Filters = @{ Phase = 'Quick win' } }
            @{ Value = '{0:N0}' -f $s.Manual; Label = 'awaiting attestation'; Tone = 'info'; Table = 'gaps'; Filters = @{ State = 'Manual' } }
            @{ Value = '{0:N0}' -f $s.NotAssessed; Label = 'frameworks not assessed'; Tone = $(if ($s.NotAssessed) { 'bad' } else { 'good' }) }
            @{ Value = $(if ($BaselinePath) { '{0:N0}' -f $s.Closed } else { '-' }); Label = 'closed since the baseline'; Tone = 'good'; Table = 'gaps'; Filters = @{ Progress = 'Closed' } }
            @{ Value = '{0:N0}' -f $s.UnscannedTotal; Label = 'resources no policy evaluates'; Tone = $(if ($s.UnscannedTotal) { 'neutral' } else { 'good' }); Table = 'unscanned' }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Compliance by framework (%)'; Items = @($result.Frameworks | Where-Object { $null -ne $_.Compliance } | ForEach-Object { @{ Label = "$($_.Framework) ($($_.Source -replace 'Defender for Cloud', 'Defender' -replace 'Azure Policy', 'Policy'))"; Value = $_.Compliance; Filter = $_.Framework } }); Table = 'gaps'; Column = 'Framework'; Tone = 'good'; Console = $true; Format = 'N1' }
            @{ Title = 'Gaps by phase'; Kind = 'donut'; CenterLabel = 'gaps'; Items = @($gaps | Group-Object Phase | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $phaseTones[$_.Name]; Filter = $_.Name } }); Table = 'gaps'; Column = 'Phase' }
        )
        Tables   = @(
            @{ Id = 'frameworks'; Title = 'Frameworks'; Section = 'Summary'; Rows = $result.Frameworks; Noun = 'standards'
                Empty = 'No compliance framework is assessed: add standards in Defender for Cloud, or assign regulatory compliance initiatives in Azure Policy.'; EmptyStatus = 'Warning'
                Columns = @(
                    @{ Key = 'Framework'; Label = 'Framework'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Standard'; Label = 'Standard or initiative'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Compliance'; Label = 'Compliance (%)'; Type = 'score'; Console = $true; Pdf = $true }
                    @{ Key = 'Passed'; Label = 'Passed'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Manual'; Label = 'Manual'; Type = 'number'; Console = $true; Pdf = $true }
                ) }
            @{ Id = 'gaps'; Title = 'Gaps and roadmap'; Section = 'Gaps'; Rows = $gaps; Noun = 'gaps'; GroupBy = @('Framework', 'Phase', 'Severity', 'Source'); ConsoleLimit = 25
                Empty = 'No gaps: every control assessed passes.'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Priority'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Phase'; Label = 'Phase'; Type = 'badge'; Tones = $phaseTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Framework'; Label = 'Framework'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Control'; Label = 'Control'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'FailingResources'; Label = 'Failing resources'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Effort'; Label = 'Effort'; Type = 'badge'; Tones = @{ Low = 'good'; Medium = 'warn'; High = 'bad' }; Facet = $true; Console = $true }
                    @{ Key = 'Progress'; Label = 'Since the baseline'; Type = 'badge'; Tones = @{ New = 'warn'; Open = 'neutral'; Closed = 'good' }; Facet = $true }
                    @{ Key = 'State'; Label = 'State'; Facet = $true }
                    @{ Key = 'Standard'; Label = 'Standard'; Facet = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Failing checks'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'FailingSubscriptions'; Label = 'Subscriptions'; Type = 'wide' }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'unscanned'; Title = 'Resource types no policy evaluates'; Section = 'Coverage'; Rows = $result.Unscanned; Noun = 'types'; ConsoleLimit = 10
                Note = 'Resources with no policy compliance state at all: nothing assesses them against a framework (some types, such as extensions, can''t be).'
                Columns = @(@{ Key = 'ResourceType'; Label = 'Resource type'; Type = 'mono'; Console = $true }, @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Console = $true }) }
        )
        Hint     = '-Framework narrows it; -CsvPath saves the gaps as next run''s -BaselinePath; -NoDisplay returns the gaps.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $gaps -Noun 'gap' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $gaps -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
