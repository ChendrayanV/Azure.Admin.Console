function Invoke-AACSecurityPostureReport {
    <#
    .SYNOPSIS
        Reads the Defender for Cloud posture - secure score, recommendations,
        alerts, plans, regulatory compliance and Azure Policy compliance,
        optionally narrowed to resource groups or tags - and shows, exports or
        returns it as AAC.SecurityFinding rows: for Invoke-AACDefenderAssessment
        -View Posture (and the deprecated Get-AACSecurityPosture).
    #>
    [CmdletBinding()]
    [OutputType('AAC.SecurityFinding')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [hashtable] $Tag,

        [ValidateSet('Score', 'Recommendations', 'Alerts', 'Plans', 'Compliance', 'Policy')]
        [string[]] $Section = @('Score', 'Recommendations', 'Alerts', 'Plans', 'Compliance', 'Policy'),

        [SupportsWildcards()]
        [string[]] $Standard,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Security posture',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging,

        # Whether the public command's output is piped onward (its own
        # pipeline position, which this helper can't see).
        [switch] $OutputPiped
    )

    $pipedOnward = [bool]$OutputPiped
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath
    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }

    # The Defender queries each section needs (Get-AACDefenderQuery, shared with Get-AACInventory).
    $needs = @{
        Score           = @('Scores', 'Controls')
        Recommendations = @('Recommendations', 'ControlAssessments')
        Alerts          = @('Alerts')
        Plans           = @('Plans')
        Compliance      = @('Standards', 'ComplianceControls', 'ComplianceAssessments', 'Recommendations')
        Policy          = @('PolicyStates', 'PolicyAssignments')
    }
    # Scores for the subscriptions table, whatever the sections.
    $names = @(@('Scores') + @($Section | ForEach-Object { $needs[$_] }) | Select-Object -Unique)

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Security posture' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $queries = Get-AACDefenderQuery -Name $names
        $queries.Insert(0, 'subscriptions', "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name")
        # Assignments are often at management group scope: read them tenant-wide.
        if ($queries.Contains('PolicyAssignments')) { $queries['PolicyAssignments'] = @{ Tenant = $true; Query = $queries['PolicyAssignments'] } }
        # A resource group or tag selection: the resources it covers.
        $narrowed = $ResourceGroupName -or ($Tag -and $Tag.Count)
        if ($narrowed) {
            $where = @(
                if ($ResourceGroupName) { "resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" }
                if ($Tag) { foreach ($key in $Tag.Keys) { "tostring(tags[$(& $quote ([string]$key))]) =~ $(& $quote ([string]$Tag[$key]))" } }
            )
            $queries['scope'] = "resources | where $($where -join ' and ') | project id = tolower(id)"
            if ($ResourceGroupName -and -not $Tag) { $queries['scopeGroups'] = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' and name in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', ')) | project id = tolower(id)" }
        }
        $labels = @{ subscriptions = 'subscriptions'; Scores = 'secure scores'; Controls = 'secure score controls'; ControlAssessments = 'control membership'; Recommendations = 'recommendations'; Alerts = 'alerts'; Plans = 'Defender plans'; Standards = 'compliance standards'; ComplianceControls = 'compliance controls'; ComplianceAssessments = 'compliance assessments'; PolicyStates = 'Azure Policy states'; PolicyAssignments = 'policy assignments'; scope = 'the resources in scope'; scopeGroups = 'the resource groups in scope' }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading Microsoft Defender for Cloud from Azure Resource Graph'
        $batch = Invoke-AACGraphBatch -Query $queries -SubscriptionId $SubscriptionId -AllowFailure @($names) -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total queries)"
        }
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($name in @($batch.Errors.Keys | Sort-Object)) { $notices.Add("The $($labels[$name]) couldn't be read: $($batch.Errors[$name] -replace '\s+', ' ')") }

        $subscriptionNames = @{}
        foreach ($row in @($batch.Rows['subscriptions'])) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
        if ($SubscriptionId) {
            foreach ($id in $SubscriptionId) { if (-not $subscriptionNames.Contains($id.ToLowerInvariant())) { $subscriptionNames[$id.ToLowerInvariant()] = $id } }
        }
        $rows = @{}
        foreach ($name in $names) { $rows[$name] = @($batch.Rows[$name]) }
        if ($Standard) {
            foreach ($name in 'Standards', 'ComplianceControls', 'ComplianceAssessments') {
                if ($rows.Contains($name)) { $rows[$name] = @($rows[$name] | Where-Object { $standardName = [string]$_['standard']; @($Standard | Where-Object { $standardName -like $_ }).Count }) }
            }
        }
        # What the sections didn't ask for isn't shown, even when read for another.
        if ($Section -notcontains 'Recommendations') { $rows.Remove('Recommendations'); if ($Section -contains 'Compliance') { $rows['ComplianceRecommendations'] = @($batch.Rows['Recommendations']) } }
        $scopeIds = $null
        if ($narrowed) {
            $scopeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($row in @($batch.Rows['scope']) + @($batch.Rows['scopeGroups'])) { if ($row) { [void]$scopeIds.Add([string]$row['id']) } }
        }
        $posture = ConvertTo-AACSecurityPosture -Rows $rows -SubscriptionName $subscriptionNames -ResourceId $scopeIds
        if ($Section -notcontains 'Score') { $posture.Controls = @() }
        $stats = $posture.Stats
        if ($Section -contains 'Plans' -and -not $posture.Plans.Count -and -not $batch.Errors.Contains('Plans')) { $notices.Add('No Defender plans were found: Defender for Cloud may not be set up on these subscriptions.') }
        if ($Section -contains 'Alerts' -and $stats.PlansOn -eq 0 -and $Section -contains 'Plans') { $notices.Add('No Defender plan is on, so there can be no security alerts - an empty alert list is not a clean bill of health.') }
        if ($Section -contains 'Compliance' -and -not $posture.Standards.Count -and -not $batch.Errors.Contains('Standards')) { $notices.Add("No regulatory compliance standards were found$(if ($Standard) { " matching $($Standard -join ', ')" }): assign one in Defender for Cloud > Regulatory compliance.") }
        if ($Section -contains 'Policy' -and -not $posture.PolicyAssignments.Count -and -not $batch.Errors.Contains('PolicyStates')) { $notices.Add('No Azure Policy compliance data was found: no policies are assigned to these subscriptions, or they have not been evaluated yet.') }
        if ($narrowed) { $notices.Add('Secure scores, Defender plans and compliance standards are per subscription, so they cover whole subscriptions; the findings are narrowed to the resources selected.') }
        Update-AACProgress -Id 'read' -Complete -Description ('Secure score {0}; {1:N0} recommendation(s) on {2:N0} resource(s), {3:N0} alert(s), {4:N0} plan(s) off, {5:N0} failed compliance control(s)' -f $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { 'not available' }), $stats.Recommendations, $stats.Resources, $stats.Alerts, $stats.PlansOff, $stats.FailedControls)

        $scope = [ordered]@{
            Subscriptions = if ($SubscriptionId) { $SubscriptionId -join ', ' } else { 'every subscription the account can see' }
        }
        if ($ResourceGroupName) { $scope['Resource groups'] = $ResourceGroupName -join ', ' }
        if ($Tag -and $Tag.Count) { $scope['Tags'] = (@($Tag.Keys | Sort-Object | ForEach-Object { "$_ = $($Tag[$_])" })) -join '; ' }
        if ($Standard) { $scope['Standards'] = $Standard -join ', ' }
        $scope['Sections'] = $Section -join ', '
        $posture.Notice = $notices.ToArray()
        $posture.Sections = @($Section)
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($posture.Findings) -Noun 'finding' -PdfPath $pdfFullPath -WritePdf {
            Write-AACSecurityPosturePdf -Posture $posture -Path $pdfFullPath -Title $Title -Detail $scope
        } -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACSecurityPostureHtml -Posture $posture -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Posture = $posture; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACSecurityPostureView -Posture $state.Posture -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Posture.Notice)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $state.Posture.Findings
    }
}
