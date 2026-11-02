function ConvertTo-AACSentinelAssessment {
    <#
    .SYNOPSIS
        Turns what Invoke-AACSentinelAssessment read - the workspace, its
        Microsoft Sentinel resources and KQL results - into the assessment.
    .DESCRIPTION
        No Azure calls: everything comes in as it was read, so the rules can
        be tested with made-up data.

          -Workspace      the workspace (GET .../workspaces/{name}), hashtables
          -Arm            Invoke-AACArmParallel results by name: onboarding,
                          alertRules, alertRuleTemplates, dataConnectors,
                          tables, incidents, automationRules
          -Kql            Invoke-AACLogQueryBatch's @{ Rows; Errors }: tables,
                          health, incidentTimes
          -NotOnboarded   Microsoft Sentinel isn't enabled on the workspace

        Returns a hashtable:
          Workspace         the summary (name, IDs, whether Sentinel is on)
          AnalyticsRules    AAC.SentinelAnalyticsRule, failing rules first
          TacticCoverage    AAC.SentinelTacticCoverage, one per MITRE ATT&CK
                            tactic, when the rules could be read
          RuleTemplates     AAC.SentinelRuleTemplate, the ones worth enabling
                            first
          Incidents         AAC.SentinelIncident, newest first
          AutomationRules   AAC.SentinelAutomationRule, in the order they run
          DataConnectors    AAC.SentinelDataConnector
          Tables            AAC.SentinelTable, one per table with data, largest
                            first (custom tables always, the rest with
                            -IncludeEmptyTable)
          HealthFailures    AAC.SentinelHealthFailure, most failures first
          HealthState       On, NoRecords, Off or Unknown
          Recommendations   AAC.SentinelRecommendation, by severity
          Errors, Stats
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Workspace,

        [System.Collections.IDictionary] $Arm = @{},

        [System.Collections.IDictionary] $Kql = @{ Rows = @{}; Errors = @{} },

        [switch] $NotOnboarded,

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [switch] $IncludeEmptyTable,

        # "Now", for how long ago a table last received data (tests).
        [datetime] $Now = [datetime]::UtcNow
    )

    $inv = [cultureinfo]::InvariantCulture
    # A table that had data in the period is silent after this long without any.
    # Long enough that a daily feed isn't reported between two of its runs.
    $silentAfterHours = 48
    # An open incident can wait a day for an owner before it is worth raising:
    # a new one is normally still in the queue.
    $unassignedAfterHours = 24
    # Half of a rule's incidents being false positives is only a pattern once
    # the rule has closed a few: one or two say nothing.
    $noisyRuleMinimumClosed = 5
    $noisyRulePercent = 50
    # A starting point, not a standard: what is too slow depends on the team's targets.
    $slowCloseHours = 72
    # The MITRE ATT&CK Enterprise tactics, as Sentinel names them. Sentinel also
    # knows the ICS ones (ImpairProcessControl, InhibitResponseFunction), left
    # out here because most workspaces have no industrial systems to cover.
    $attackTactics = 'Reconnaissance', 'ResourceDevelopment', 'InitialAccess', 'Execution', 'Persistence', 'PrivilegeEscalation', 'DefenseEvasion', 'CredentialAccess', 'Discovery', 'LateralMovement', 'Collection', 'Exfiltration', 'CommandAndControl', 'Impact'
    $docs = 'https://learn.microsoft.com/azure/sentinel'
    # A value deep in hashtables: & $get $object 'properties', 'sku', 'name'.
    $get = {
        param($Object, [string[]] $Path)
        $value = $Object
        foreach ($key in $Path) {
            if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($key)) { return $null }
            $value = $value[$key]
        }
        $value
    }
    $number = { param($Value) if ($null -eq $Value -or "$Value" -eq '') { 0.0 } else { [double]$Value } }
    $round = { param([double] $Value, [int] $Digits = 3) [Math]::Round($Value, $Digits) }
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    $object = {
        param([string] $TypeName, [System.Collections.IDictionary] $Property)
        $item = [pscustomobject]$Property
        $item.PSObject.TypeNames.Insert(0, $TypeName)
        $item
    }
    $sum = { param($Items, [string] $Name) $total = 0.0; foreach ($item in @($Items)) { if ($null -ne $item) { $total += & $number $item.$Name } }; $total }
    $leaf = { param([string] $Id) if ($Id) { ($Id.TrimEnd('/') -split '/')[-1] } }
    $join = { param($Items) @($Items | Where-Object { $_ }) -join ', ' }
    $kqlRows = { param([string] $Name) @($Kql.Rows[$Name] | Where-Object { $null -ne $_ }) }
    $armItems = {
        param([string] $Name)
        $read = $Arm[$Name]
        if (-not $read -or $read.Error) { return @() }
        if ($null -ne $read.Items) { return @($read.Items) }
        @(& $get $read.Body 'value')
    }
    $errors = [ordered]@{}
    # What couldn't be read is reported and the rest carries on: a reader of the
    # workspace who lacks a Sentinel role still gets the tables and health.
    $noteArmError = {
        param([string] $Name, [string] $Label)
        $read = $Arm[$Name]
        if (-not $read -or -not $read.Error) { return }
        $errors[$Label] = "$($read.Error)$(if ($read.Status -in 401, 403) { ' (needs the Microsoft Sentinel Reader role on the workspace)' })"
    }
    # A 404 from the onboarding list is the answer "not enabled", not a failure.
    if (-not $NotOnboarded) { & $noteArmError 'onboarding' 'Onboarding state' }
    & $noteArmError 'alertRules' 'Analytics rules'
    & $noteArmError 'dataConnectors' 'Data connectors'
    & $noteArmError 'tables' 'Table properties'
    & $noteArmError 'alertRuleTemplates' 'Rule templates'
    & $noteArmError 'incidents' 'Incidents'
    & $noteArmError 'automationRules' 'Automation rules'
    $wasRead = { param([string] $Name) $Arm.Contains($Name) -and -not $Arm[$Name].Error }

    # --- The workspace -----------------------------------------------------------------------------------------
    $workspaceResourceId = [string]$Workspace['id']
    $segments = $workspaceResourceId -split '/'
    $summary = [ordered]@{
        Name            = [string]$Workspace['name']
        ResourceId      = $workspaceResourceId
        WorkspaceId     = [string](& $get $Workspace 'properties', 'customerId')
        SubscriptionId  = $(if ($segments.Count -gt 2) { $segments[2] } else { '' })
        ResourceGroup   = $(if ($segments.Count -gt 4) { $segments[4] } else { '' })
        Location        = [string]$Workspace['location']
        SentinelEnabled = -not $NotOnboarded
        Days            = $Days
    }

    # --- Health: _SentinelHealth, a row per resource and operation ---------------------------------------------
    # A workspace with health monitoring off has no such function or table, so
    # the query fails - that is a finding about the workspace, not a read error.
    $healthRead = $Kql.Rows.Contains('health') -or $Kql.Errors.Contains('health')
    $healthRows = @(& $kqlRows 'health')
    $healthState = 'Unknown'
    if ($Kql.Errors.Contains('health')) {
        if ([string]$Kql.Errors['health'] -match '(?i)(failed to resolve|unknown function).*SentinelHealth') { $healthState = 'Off' }
        else { $errors['Health (_SentinelHealth)'] = [string]$Kql.Errors['health'] }
    }
    elseif ($healthRead) {
        $healthState = if ($healthRows.Count) { 'On' } else { 'NoRecords' }
    }
    $healthFailures = @(foreach ($row in $healthRows) {
            if ((& $number $row['Failures']) -le 0) { continue }
            & $object 'AAC.SentinelHealthFailure' ([ordered]@{
                    ResourceType = [string]$row['SentinelResourceType']
                    Resource     = [string]$row['SentinelResourceName']
                    ResourceId   = [string]$row['SentinelResourceId']
                    Operation    = [string]$row['OperationName']
                    Failures     = [int](& $number $row['Failures'])
                    Records      = [int](& $number $row['Records'])
                    LastFailure  = & $date $row['LastFailure']
                    Reason       = [string]$row['Reason']
                })
        })
    $healthFailures = @($healthFailures | Sort-Object -Property Failures -Descending)

    # --- Incidents, with the close times SecurityIncident has ---------------------------------------------------
    # No SecurityIncident table just means no incident was written to it, so the
    # times are left blank. Any other failure is reported.
    if ($Kql.Errors.Contains('incidentTimes') -and [string]$Kql.Errors['incidentTimes'] -notmatch '(?i)failed to resolve.*SecurityIncident') {
        $errors['Incident times (SecurityIncident)'] = [string]$Kql.Errors['incidentTimes']
    }
    $timesByNumber = @{}
    foreach ($row in & $kqlRows 'incidentTimes') { $timesByNumber[[string]$row['IncidentNumber']] = $row }
    $incidentsByRule = @{}
    $incidents = @(foreach ($item in & $armItems 'incidents') {
            $properties = & $get $item 'properties'
            $incidentNumber = & $get $properties 'incidentNumber'
            $status = [string](& $get $properties 'status')
            $classification = [string](& $get $properties 'classification')
            $created = & $date (& $get $properties 'createdTimeUtc')
            $times = $timesByNumber[[string]$incidentNumber]
            $closed = if ($times -and $status -eq 'Closed') { & $date $times['ClosedTime'] }
            $owner = @((& $get $properties 'owner', 'assignedTo'), (& $get $properties 'owner', 'userPrincipalName'), (& $get $properties 'owner', 'email') | Where-Object { $_ } | Select-AACFirst 1)
            $ruleIds = @(& $get $properties 'relatedAnalyticRuleIds' | Where-Object { $_ } | ForEach-Object { ([string](& $leaf $_)).ToLowerInvariant() })
            foreach ($ruleKey in $ruleIds) {
                if (-not $incidentsByRule.Contains($ruleKey)) { $incidentsByRule[$ruleKey] = @{ Total = 0; Closed = 0; FalsePositive = 0 } }
                $incidentsByRule[$ruleKey].Total++
                if ($status -eq 'Closed') { $incidentsByRule[$ruleKey].Closed++ }
                if ($classification -eq 'FalsePositive') { $incidentsByRule[$ruleKey].FalsePositive++ }
            }
            & $object 'AAC.SentinelIncident' ([ordered]@{
                    Number               = $incidentNumber
                    Title                = [string](& $get $properties 'title')
                    Severity             = [string](& $get $properties 'severity')
                    Status               = $status
                    Owner                = $(if ($owner.Count) { [string]$owner[0] } else { '' })
                    Classification       = $classification
                    ClassificationReason = [string](& $get $properties 'classificationReason')
                    Created              = $created
                    LastModified         = & $date (& $get $properties 'lastModifiedTimeUtc')
                    Closed               = $closed
                    HoursToClose         = $(if ($closed -and $created -and $closed -ge $created) { & $round ($closed - $created).TotalHours 1 })
                    HoursOpen            = $(if ($status -ne 'Closed' -and $created) { & $round ($Now - $created).TotalHours 1 })
                    Alerts               = [int](& $number $(& $get $properties 'additionalData', 'alertsCount'))
                    Provider             = [string](& $get $properties 'providerName')
                    Tactics              = & $join (& $get $properties 'additionalData', 'tactics')
                    Url                  = [string](& $get $properties 'incidentUrl')
                })
        })
    $incidents = @($incidents | Sort-Object -Property @{ Expression = { $_.Created }; Descending = $true })

    # --- Analytics rules, with the failures health reported for each ------------------------------------------
    # The newest version of each template, to tell a rule when its template moved on.
    $templateVersions = @{}
    foreach ($item in & $armItems 'alertRuleTemplates') {
        $version = [string](& $get $item 'properties', 'version')
        if ($version) { $templateVersions[([string]$item['name']).ToLowerInvariant()] = $version }
    }
    $isNewer = {
        param([string] $Latest, [string] $Current)
        $latestVersion = $null; $currentVersion = $null
        [version]::TryParse($Latest, [ref]$latestVersion) -and [version]::TryParse($Current, [ref]$currentVersion) -and $latestVersion -gt $currentVersion
    }
    $failuresByRule = @{}
    foreach ($failure in @($healthFailures | Where-Object ResourceType -Match '(?i)analytics')) {
        # Health names a rule by its resource ID; the display name is the fallback.
        $key = ([string]$(if ($failure.ResourceId) { & $leaf $failure.ResourceId } else { $failure.Resource })).ToLowerInvariant()
        if (-not $failuresByRule.Contains($key)) { $failuresByRule[$key] = [System.Collections.Generic.List[object]]::new() }
        $failuresByRule[$key].Add($failure)
    }
    $analyticsRules = @(foreach ($item in & $armItems 'alertRules') {
            $properties = & $get $item 'properties'
            $ruleId = [string]$item['name']
            $displayName = [string](& $get $properties 'displayName')
            $found = @($ruleId, $displayName | Where-Object { $_ } | ForEach-Object { $failuresByRule[$_.ToLowerInvariant()] } | Where-Object { $null -ne $_ } | ForEach-Object { $_ })
            $ruleIncidents = $incidentsByRule[$ruleId.ToLowerInvariant()]
            $templateId = [string](& $get $properties 'alertRuleTemplateName')
            $templateVersion = [string](& $get $properties 'templateVersion')
            $latestTemplate = if ($templateId) { [string]$templateVersions[$templateId.ToLowerInvariant()] } else { '' }
            & $object 'AAC.SentinelAnalyticsRule' ([ordered]@{
                    Name            = $(if ($displayName) { $displayName } else { $ruleId })
                    RuleId          = $ruleId
                    Kind            = [string]$item['kind']
                    Enabled         = [bool](& $get $properties 'enabled')
                    Severity        = [string](& $get $properties 'severity')
                    Tactics         = & $join (& $get $properties 'tactics')
                    Techniques      = & $join (& $get $properties 'techniques')
                    Frequency       = [string](& $get $properties 'queryFrequency')
                    Period          = [string](& $get $properties 'queryPeriod')
                    CreatesIncident = & $get $properties 'incidentConfiguration', 'createIncident'
                    TemplateId      = $templateId
                    TemplateVersion = $templateVersion
                    LatestTemplate  = $latestTemplate
                    TemplateUpdate  = [bool](& $isNewer $latestTemplate $templateVersion)
                    LastModified    = & $date (& $get $properties 'lastModifiedUtc')
                    Failures        = [int](& $sum $found 'Failures')
                    LastFailure     = $(if ($found.Count) { ($found | Sort-Object -Property LastFailure -Descending | Select-AACFirst 1).LastFailure })
                    Incidents       = $(if ($ruleIncidents) { $ruleIncidents.Total } else { 0 })
                    ClosedIncidents = $(if ($ruleIncidents) { $ruleIncidents.Closed } else { 0 })
                    FalsePositives  = $(if ($ruleIncidents) { $ruleIncidents.FalsePositive } else { 0 })
                    Query           = [string](& $get $properties 'query')
                })
        })
    $severityOrder = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
    $analyticsRules = @($analyticsRules | Sort-Object -Property @{ Expression = 'Failures'; Descending = $true }, @{ Expression = 'Enabled'; Descending = $true }, @{ Expression = { $severityOrder[$_.Severity] ?? 4 } }, 'Name')

    # --- Data connectors ----------------------------------------------------------------------------------------
    # Older connectors list their data types, each with a state. Codeless ones
    # have an isActive flag or a single data type instead, so some have no state.
    $dataConnectors = @(foreach ($item in & $armItems 'dataConnectors') {
            $properties = & $get $item 'properties'
            $dataTypes = & $get $properties 'dataTypes'
            $typeNames = @()
            $state = 'Unknown'
            if ($dataTypes -is [System.Collections.IDictionary] -and $dataTypes.Count) {
                $typeNames = @($dataTypes.Keys | ForEach-Object { [string]$_ } | Sort-Object)
                $on = @($typeNames | Where-Object { [string](& $get $dataTypes $_, 'state') -eq 'Enabled' })
                $state = if ($on.Count) { 'Connected' } else { 'Disconnected' }
            }
            else {
                $single = & $get $properties 'dataType'
                if ($single) { $typeNames = @([string]$single) }
                $active = & $get $properties 'isActive'
                if ($null -ne $active) { $state = if ($active) { 'Connected' } else { 'Disconnected' } }
            }
            $title = & $get $properties 'connectorUiConfig', 'title'
            if (-not $title) { $title = & $get $properties 'connectorDefinitionName' }
            if (-not $title) { $title = $item['kind'] }
            & $object 'AAC.SentinelDataConnector' ([ordered]@{
                    Name        = [string]$title
                    ConnectorId = [string]$item['name']
                    Kind        = [string]$item['kind']
                    State       = $state
                    DataTypes   = $typeNames -join ', '
                })
        })
    $dataConnectors = @($dataConnectors | Sort-Object -Property Name)

    # --- Tables: Usage per table, merged with the table list (plan, retention) ---------------------------------
    if ($Kql.Errors.Contains('tables')) { $errors['Ingestion (Usage)'] = [string]$Kql.Errors['tables'] }
    $tableTypes = @{ Microsoft = 'Azure'; CustomLog = 'Custom'; RestoredLogs = 'Restored'; SearchResults = 'Search job' }
    $byName = [ordered]@{}
    foreach ($item in & $armItems 'tables') {
        $name = [string]$item['name']
        if ($name) { $byName[$name.ToLowerInvariant()] = @{ Name = $name; Arm = $item; Usage = $null } }
    }
    foreach ($row in & $kqlRows 'tables') {
        $name = [string]$row['Table']
        if (-not $name) { continue }
        $key = $name.ToLowerInvariant()
        if ($byName.Contains($key)) { $byName[$key].Usage = $row }
        else { $byName[$key] = @{ Name = $name; Arm = $null; Usage = $row } }
    }
    $totalBillable = 0.0
    foreach ($entry in $byName.Values) { if ($entry.Usage) { $totalBillable += & $number $entry.Usage['BillableGB'] } }
    $silentBefore = $Now.AddHours(-$silentAfterHours)
    $rulesRead = & $wasRead 'alertRules'
    $ruleQueries = @($analyticsRules | Where-Object { $_.Enabled -and $_.Query } | ForEach-Object Query)
    $tables = @(foreach ($entry in $byName.Values) {
            $rawType = [string](& $get $entry.Arm 'properties', 'schema', 'tableType')
            $type = if ($tableTypes.Contains($rawType)) { $tableTypes[$rawType] } elseif ($rawType) { $rawType } elseif ($entry.Name -like '*_CL') { 'Custom' } else { 'Azure' }
            if (-not $entry.Usage -and -not $IncludeEmptyTable -and $type -ne 'Custom') { continue }
            $billableGB = if ($entry.Usage) { & $number $entry.Usage['BillableGB'] } else { 0.0 }
            $freeGB = if ($entry.Usage) { & $number $entry.Usage['NonBillableGB'] } else { 0.0 }
            $lastRecord = if ($entry.Usage) { & $date $entry.Usage['LastRecord'] }
            & $object 'AAC.SentinelTable' ([ordered]@{
                    Table              = $entry.Name
                    Type               = $type
                    Plan               = [string](& $get $entry.Arm 'properties', 'plan')
                    RetentionDays      = & $get $entry.Arm 'properties', 'retentionInDays'
                    TotalRetentionDays = & $get $entry.Arm 'properties', 'totalRetentionInDays'
                    BillableGB         = & $round $billableGB
                    NonBillableGB      = & $round $freeGB
                    SharePercent       = $(if ($totalBillable -gt 0) { & $round (100 * $billableGB / $totalBillable) 1 } else { 0 })
                    DailyAverageGB     = & $round ($billableGB / $Days)
                    LastRecord         = $lastRecord
                    Solution           = $(if ($entry.Usage) { [string]$entry.Usage['Solution'] } else { '' })
                    # Billable only: free tables such as Operation are written now and then by design.
                    Silent             = [bool]($billableGB -gt 0 -and $lastRecord -and $lastRecord -lt $silentBefore)
                    # Blank when the rules couldn't be read: unknown isn't the same as no rules.
                    UsedByRules        = $(if ($rulesRead) { $pattern = "(?i)\b$([regex]::Escape($entry.Name))\b"; @($ruleQueries | Where-Object { $_ -match $pattern }).Count })
                })
        })
    $tables = @($tables | Sort-Object -Property @{ Expression = { $_.BillableGB + $_.NonBillableGB }; Descending = $true }, 'Table')

    # --- MITRE ATT&CK coverage of the enabled rules ------------------------------------------------------------
    $tacticCoverage = @(if ($rulesRead) {
            foreach ($tactic in $attackTactics) {
                $withTactic = @($analyticsRules | Where-Object { ([string]$_.Tactics -split ', ') -contains $tactic })
                & $object 'AAC.SentinelTacticCoverage' ([ordered]@{
                        Tactic        = $tactic
                        EnabledRules  = @($withTactic | Where-Object Enabled).Count
                        DisabledRules = @($withTactic | Where-Object { -not $_.Enabled }).Count
                    })
            }
        })

    # --- Rule templates: which have their data in the workspace and no rule yet --------------------------------
    $tablesWithData = @{}
    foreach ($item in $tables) { if ($item.BillableGB -gt 0 -or $item.NonBillableGB -gt 0) { $tablesWithData[$item.Table.ToLowerInvariant()] = $true } }
    $usageRead = $Kql.Rows.Contains('tables') -and -not $Kql.Errors.Contains('tables')
    $rulesFromTemplate = @{}
    foreach ($item in $analyticsRules) { if ($item.TemplateId) { $rulesFromTemplate[$item.TemplateId.ToLowerInvariant()] = $true } }
    $ruleTemplates = @(foreach ($item in & $armItems 'alertRuleTemplates') {
            $properties = & $get $item 'properties'
            $templateName = [string]$item['name']
            # A data type can carry a note: "CommonSecurityLog (Fortinet)" is the table CommonSecurityLog.
            $required = @(foreach ($connector in @(& $get $properties 'requiredDataConnectors' | Where-Object { $_ })) {
                    foreach ($dataType in @($connector['dataTypes'] | Where-Object { $_ })) { (([string]$dataType).Trim() -split '[\s(]')[0] }
                })
            $required = @($required | Where-Object { $_ } | Select-Object -Unique)
            $missing = @($required | Where-Object { -not $tablesWithData.Contains($_.ToLowerInvariant()) })
            $templateStatus = [string](& $get $properties 'status')
            $inUse = $rulesFromTemplate.Contains($templateName.ToLowerInvariant()) -or (& $number (& $get $properties 'alertRulesCreatedByTemplateCount')) -gt 0
            $dataAvailable = $usageRead -and $required.Count -gt 0 -and -not $missing.Count
            & $object 'AAC.SentinelRuleTemplate' ([ordered]@{
                    Name          = [string](& $get $properties 'displayName')
                    TemplateId    = $templateName
                    Kind          = [string]$item['kind']
                    Severity      = [string](& $get $properties 'severity')
                    Status        = $templateStatus
                    Version       = [string](& $get $properties 'version')
                    Tactics       = & $join (& $get $properties 'tactics')
                    DataTypes     = $required -join ', '
                    MissingData   = $missing -join ', '
                    DataAvailable = [bool]$dataAvailable
                    InUse         = [bool]$inUse
                    # Worth enabling: what it needs is arriving and nothing uses it. Without
                    # the rules there is no telling what is in use, so nothing is suggested.
                    Candidate     = [bool]($dataAvailable -and -not $inUse -and $rulesRead -and $templateStatus -ne 'NotAvailable')
                })
        })
    $ruleTemplates = @($ruleTemplates | Sort-Object -Property @{ Expression = 'Candidate'; Descending = $true }, @{ Expression = { $severityOrder[$_.Severity] ?? 4 } }, 'Name')

    # --- Automation rules ---------------------------------------------------------------------------------------
    $automationRules = @(foreach ($item in & $armItems 'automationRules') {
            $properties = & $get $item 'properties'
            $expires = & $date (& $get $properties 'triggeringLogic', 'expirationTimeUtc')
            $isEnabled = [bool](& $get $properties 'triggeringLogic', 'isEnabled')
            $expired = [bool]($expires -and $expires -lt $Now)
            & $object 'AAC.SentinelAutomationRule' ([ordered]@{
                    Name         = [string](& $get $properties 'displayName')
                    RuleId       = [string]$item['name']
                    Order        = [int](& $number (& $get $properties 'order'))
                    State        = $(if ($expired) { 'Expired' } elseif ($isEnabled) { 'Enabled' } else { 'Disabled' })
                    Expires      = $expires
                    TriggersOn   = [string](& $get $properties 'triggeringLogic', 'triggersOn')
                    TriggersWhen = [string](& $get $properties 'triggeringLogic', 'triggersWhen')
                    Conditions   = @(& $get $properties 'triggeringLogic', 'conditions' | Where-Object { $_ }).Count
                    Actions      = & $join (@(& $get $properties 'actions' | Where-Object { $_ }) | ForEach-Object { [string]$_['actionType'] })
                    LastModified = & $date (& $get $properties 'lastModifiedTimeUtc')
                    ModifiedBy   = [string](& $get $properties 'lastModifiedBy', 'email')
                })
        })
    $automationRules = @($automationRules | Sort-Object -Property Order, Name)

    # --- Recommendations ----------------------------------------------------------------------------------------
    $recommendations = [System.Collections.Generic.List[object]]::new()
    $recommend = {
        param([string] $Severity, [string] $Category, [string] $Title, [string] $Detail, [string] $Action, [string] $LearnMore)
        $recommendations.Add((& $object 'AAC.SentinelRecommendation' ([ordered]@{ Severity = $Severity; Category = $Category; Recommendation = $Title; Detail = $Detail; Action = $Action; LearnMore = $LearnMore })))
    }
    $preview = { param([string[]] $Names) "$(@($Names | Select-AACFirst 5) -join ', ')$(if ($Names.Count -gt 5) { ", and $($Names.Count - 5) more" })" }
    if ($NotOnboarded) {
        & $recommend 'High' 'Coverage' 'Microsoft Sentinel is not enabled on this workspace' 'The workspace has no Sentinel onboarding state, so it has no analytics rules, incidents or automation.' 'Enable Microsoft Sentinel on the workspace, or point this command at the workspace that has it.' "$docs/quickstart-onboard"
    }
    $failingRules = @($analyticsRules | Where-Object { $_.Enabled -and $_.Failures -gt 0 })
    if ($failingRules.Count) {
        & $recommend 'High' 'Reliability' "$($failingRules.Count) enabled analytics rule(s) are failing" "Failures in the last $Days day(s): $(& $preview @($failingRules.Name)). A failed run can miss detections." 'See the reason for each in the Health section, then fix the rule''s query or the permissions it needs.' "$docs/monitor-analytics-rule-integrity"
    }
    $silentTables = @($tables | Where-Object Silent)
    if ($silentTables.Count) {
        & $recommend 'High' 'Reliability' "$($silentTables.Count) table(s) stopped receiving data" "No data for over $silentAfterHours hours, after having data in the last $Days day(s): $(& $preview @($silentTables.Table)). Rules reading them can't detect anything new." 'Check the connector, agent or data collection rule that feeds each table. A source that only sends now and then can be ignored.' "$docs/monitor-data-connector-health"
    }
    if ($healthState -in 'Off', 'NoRecords') {
        & $recommend 'Medium' 'Reliability' 'Sentinel health monitoring appears to be off' "_SentinelHealth has no records for the last $Days day(s), so failing rules and connectors go unreported." 'Turn on auditing and health monitoring under Sentinel''s Settings, in the Azure or Defender portal.' "$docs/enable-monitoring"
    }
    $otherFailures = @($healthFailures | Where-Object ResourceType -NotMatch '(?i)analytics')
    if ($otherFailures.Count) {
        & $recommend 'Medium' 'Reliability' "$($otherFailures.Count) connector or automation operation(s) reported failures" "In the last $Days day(s): $(& $preview @($otherFailures.Resource | Select-Object -Unique))." 'See the reason for each in the Health section. Connector health is logged only for some connectors, so no failures here doesn''t prove every connector is healthy.' "$docs/health-audit"
    }
    $notRead = @($tables | Where-Object { $_.BillableGB -gt 0 -and $_.SharePercent -ge 1 -and $_.UsedByRules -eq 0 })
    if ($ruleQueries.Count -and $notRead.Count) {
        & $recommend 'Medium' 'Coverage' "$($notRead.Count) billable table(s) aren't read by any enabled rule" "No enabled rule names $(& $preview @($notRead.Table)): $(& $round (& $sum $notRead 'SharePercent') 1)% of billable data. A rule that reads a table through a function isn't counted, so check before acting." 'Enable or write detections for this data, or if nothing needs it, stop collecting it or move it to a cheaper plan.' "$docs/threat-detection"
    }
    $candidates = @($ruleTemplates | Where-Object Candidate)
    if ($candidates.Count) {
        & $recommend 'Medium' 'Coverage' "$($candidates.Count) rule template(s) could be enabled" "Their data is arriving and no rule uses them: $(& $preview @($candidates.Name))." 'Review them in the RuleTemplates section and create rules from the ones that fit. The list covers built-in templates and installed solutions.' "$docs/create-analytics-rule-from-template"
    }
    $gaps = @($tacticCoverage | Where-Object EnabledRules -EQ 0)
    if ($gaps.Count) {
        & $recommend 'Medium' 'Coverage' "No enabled rule covers $($gaps.Count) of $($attackTactics.Count) MITRE ATT&CK tactics" "Not covered: $($gaps.Tactic -join ', '). Only the tactics each rule declares are counted." 'Look for templates or write rules for these tactics, if they matter to your threat model.' "$docs/mitre-coverage"
    }
    $unassigned = @($incidents | Where-Object { $_.Status -ne 'Closed' -and -not $_.Owner -and $_.HoursOpen -gt $unassignedAfterHours })
    if ($unassigned.Count) {
        & $recommend 'Medium' 'Operations' "$($unassigned.Count) open incident(s) have no owner" "Open for over $unassignedAfterHours hours with nobody assigned, including: $(& $preview @($unassigned | Sort-Object -Property HoursOpen -Descending | ForEach-Object { "#$($_.Number) $($_.Title)" }))." 'Assign an owner, or add an automation rule that assigns new incidents.' "$docs/investigate-incidents"
    }
    $closeTimes = @($incidents | Where-Object { $null -ne $_.HoursToClose } | ForEach-Object HoursToClose | Sort-Object)
    $medianHours = if ($closeTimes.Count) {
        $middle = [Math]::Floor($closeTimes.Count / 2)
        if ($closeTimes.Count % 2) { $closeTimes[$middle] } else { & $round (($closeTimes[$middle - 1] + $closeTimes[$middle]) / 2) 1 }
    }
    if ($null -ne $medianHours -and $medianHours -gt $slowCloseHours) {
        & $recommend 'Medium' 'Operations' 'Incidents are slow to close' "The median incident closed in the last $Days day(s) took $medianHours hours, over $($closeTimes.Count) incident(s)." "Look for where incidents wait, and automate triage of the common ones. $slowCloseHours hours is this assessment's starting point: compare with your own targets." "$docs/manage-soc-with-incident-metrics"
    }
    $noisy = @($analyticsRules | Where-Object { $_.ClosedIncidents -ge $noisyRuleMinimumClosed -and 100 * $_.FalsePositives / $_.ClosedIncidents -ge $noisyRulePercent })
    if ($noisy.Count) {
        & $recommend 'Low' 'Operations' "$($noisy.Count) analytics rule(s) are noisy" "At least $noisyRulePercent% of the closed incidents were false positives: $(& $preview @($noisy | ForEach-Object { "$($_.Name) ($($_.FalsePositives) of $($_.ClosedIncidents))" }))." 'Tune the rule''s query or threshold, or add an automation rule that closes the known cases.' "$docs/false-positives"
    }
    $expiredAutomation = @($automationRules | Where-Object State -EQ 'Expired')
    if ($expiredAutomation.Count) {
        & $recommend 'Low' 'Operations' "$($expiredAutomation.Count) automation rule(s) have expired" "No longer running: $(& $preview @($expiredAutomation.Name))." 'Remove them, or extend them if the need is still there.' "$docs/automate-incident-handling-with-automation-rules"
    }
    $disabledAutomation = @($automationRules | Where-Object State -EQ 'Disabled')
    if ($disabledAutomation.Count) {
        & $recommend 'Low' 'Operations' "$($disabledAutomation.Count) automation rule(s) are disabled" "Not running: $(& $preview @($disabledAutomation.Name))." 'Turn them back on, or remove the ones no longer needed.' "$docs/automate-incident-handling-with-automation-rules"
    }
    $outdated = @($analyticsRules | Where-Object { $_.Enabled -and $_.TemplateUpdate })
    if ($outdated.Count) {
        & $recommend 'Low' 'Coverage' "$($outdated.Count) enabled rule(s) have a newer template" "$(& $preview @($outdated | ForEach-Object { "$($_.Name) ($($_.TemplateVersion) to $($_.LatestTemplate))" }))." 'Compare each rule with its new template version, then update it. Updating replaces changes you made to the rule.' "$docs/manage-analytics-rule-templates"
    }
    $order = @{ High = 0; Medium = 1; Low = 2 }
    $sorted = @($recommendations | Sort-Object -Stable -Property { $order[$_.Severity] })
    $closedIncidents = @($incidents | Where-Object Status -EQ 'Closed')

    $billableTotal = & $round $totalBillable
    @{
        Workspace       = $summary
        AnalyticsRules  = $analyticsRules
        TacticCoverage  = $tacticCoverage
        RuleTemplates   = $ruleTemplates
        Incidents       = $incidents
        AutomationRules = $automationRules
        DataConnectors  = $dataConnectors
        Tables          = $tables
        HealthFailures  = $healthFailures
        HealthState     = $healthState
        Recommendations = $sorted
        Errors          = $errors
        Stats           = [ordered]@{
            AnalyticsRules      = $analyticsRules.Count
            EnabledRules        = @($analyticsRules | Where-Object Enabled).Count
            FailingRules        = $failingRules.Count
            DataConnectors      = $dataConnectors.Count
            ConnectedConnectors = @($dataConnectors | Where-Object State -EQ 'Connected').Count
            TablesWithData      = @($tables | Where-Object { $_.BillableGB -gt 0 -or $_.NonBillableGB -gt 0 }).Count
            SilentTables        = $silentTables.Count
            BillableGB          = $billableTotal
            AverageDailyGB      = & $round ($totalBillable / $Days)
            HealthFailures      = [int](& $sum $healthFailures 'Failures')
            TacticsCovered      = @($tacticCoverage | Where-Object EnabledRules -GT 0).Count
            TacticsTotal        = $tacticCoverage.Count
            RuleTemplates       = $ruleTemplates.Count
            TemplateCandidates  = $candidates.Count
            Incidents           = $incidents.Count
            OpenIncidents       = $incidents.Count - $closedIncidents.Count
            UnassignedIncidents = $unassigned.Count
            MedianHoursToClose  = $medianHours
            FalsePositivePercent = $(if ($closedIncidents.Count) { & $round (100 * @($closedIncidents | Where-Object Classification -EQ 'FalsePositive').Count / $closedIncidents.Count) 1 } else { 0 })
            AutomationRules     = $automationRules.Count
            EnabledAutomation   = @($automationRules | Where-Object State -EQ 'Enabled').Count
            High                = @($sorted | Where-Object Severity -EQ 'High').Count
            Medium              = @($sorted | Where-Object Severity -EQ 'Medium').Count
            Low                 = @($sorted | Where-Object Severity -EQ 'Low').Count
        }
    }
}
