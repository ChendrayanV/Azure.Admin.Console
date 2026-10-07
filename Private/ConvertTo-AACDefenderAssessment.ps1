function ConvertTo-AACDefenderAssessment {
    <#
    .SYNOPSIS
        Builds Invoke-AACDefenderAssessment's model from what Defender for
        Cloud returned (Get-AACDefenderAssessmentQuery): recommendations,
        attack paths, alerts, inventory, vulnerabilities, secure score,
        plans, regulatory compliance and environment settings - and the
        findings: what to improve in how Defender for Cloud is set up.
    .DESCRIPTION
        No Azure calls. -Rows maps a Resource Graph query's name to its rows;
        -Rest maps a REST call's name (Contacts, Settings, Connectors, Jit,
        Suppression) to subscription ID -> Invoke-AACArmParallel's result
        (Status, Items, Error). -SubscriptionName names the subscriptions in
        scope (lower-case ID -> name); rows of others are left out. A name
        missing from -Rows or -Rest was not read: its tables are empty.

        Findings (AAC.DefenderFinding), each with its severity, what was
        found and what to do:
          Plans         a plan off for resources the subscription has, Defender
                        CSPM or Resource Manager off, Servers on Plan 1
          Notifications no security contact, alert e-mails off or only for
                        High alerts, the owners not notified
          Integrations  Defender for Endpoint (MDE) or Defender for Cloud Apps
                        off
          Secure score  a subscription under -ScoreWarningPercent
          Attack paths  Critical and High attack paths
          Alerts        High alerts still active, Medium ones active for
                        over a week
          Suppression   rules with no expiry, or expired but still on
          Just-in-time  a port opened to any source

        Returns a hashtable: Subscriptions, Recommendations,
        UnhealthyResources, Controls, AttackPaths, Alerts, Inventory,
        Vulnerabilities, Plans, Standards, ComplianceControls,
        ComplianceAssessments, Settings, Connectors, JitPolicies,
        SuppressionRules, Findings, Notices and Stats.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable] $Rows = @{},

        [hashtable] $Rest = @{},

        [hashtable] $SubscriptionName = @{},

        [ValidateRange(1, 99)]
        [int] $ScoreWarningPercent = 70,

        [datetime] $Now = [datetime]::UtcNow
    )

    # --- Helpers ---------------------------------------------------------------------------------------------
    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Key)) { $Object[$Key] } }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    # REST bodies and attack paths: their keys' case isn't fixed.
    $get = {
        param($Object, [string] $Path)
        foreach ($part in $Path.Split('.')) {
            if ($Object -isnot [System.Collections.IDictionary]) { return $null }
            $found = $null
            foreach ($k in $Object.Keys) { if ($k -eq $part) { $found = $Object[$k]; break } }
            $Object = $found
        }
        $Object
    }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Rows.Contains($Name)) { $Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $inScope = { param([string] $Subscription) $Subscription -and $SubscriptionName.Contains($Subscription.ToLowerInvariant()) }
    $subscriptionLabel = { param([string] $Id) $key = ([string]$Id).ToLowerInvariant(); if ($SubscriptionName.Contains($key)) { $SubscriptionName[$key] } else { $Id } }
    $object = { param([string] $TypeName, [System.Collections.IDictionary] $Property) $item = [pscustomobject]$Property; $item.PSObject.TypeNames.Insert(0, $TypeName); $item }
    $date = {
        param([string] $Text)
        $d = [datetime]::MinValue
        if ($Text -and [datetime]::TryParse($Text, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    # Defender's texts carry HTML (<br>, links, &nbsp;): as plain text, one step a line.
    $plain = {
        param([string] $Html)
        if (-not $Html) { return '' }
        $t = $Html -replace '(?i)<br\s*/?>|</p>|</li>', "`n" -replace '(?i)<li[^>]*>', '- ' -replace '<[^>]+>', ''
        ([System.Net.WebUtility]::HtmlDecode($t).Replace([char]0x00A0, ' ') -replace '[ \t]+\n', "`n" -replace '\n{3,}', "`n`n").Trim()
    }
    $rank = @{ Critical = 0; High = 1; Medium = 2; Low = 3; Informational = 4; Info = 4 }
    $rankOf = { param([string] $Severity) if ($Severity -and $rank.Contains($Severity)) { $rank[$Severity] } else { 5 } }
    # /subscriptions/s/resourceGroups/g/providers/Microsoft.Compute/virtualMachines/vm -> its parts.
    $parse = {
        param([string] $Id)
        $r = @{ Name = ''; Type = ''; Group = ''; Subscription = '' }
        if (-not $Id) { return $r }
        if ($Id -notmatch '^/') { $r.Name = $Id; return $r }
        $parts = $Id.Trim('/').Split('/')
        $lower = @($parts | ForEach-Object { $_.ToLowerInvariant() })
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            if ($lower[$i] -eq 'subscriptions' -and -not $r.Subscription) { $r.Subscription = $lower[$i + 1] }
            if ($lower[$i] -eq 'resourcegroups' -and -not $r.Group) { $r.Group = $parts[$i + 1] }
        }
        $p = [array]::LastIndexOf($lower, 'providers')
        if ($p -ge 0 -and $p + 2 -lt $parts.Count) { $r.Type = ($lower[$p + 1] + '/' + (@(for ($j = $p + 2; $j -lt $parts.Count; $j += 2) { $lower[$j] }) -join '/')) }
        elseif ($r.Group) { $r.Type = 'microsoft.resources/resourcegroups' }
        elseif ($r.Subscription) { $r.Type = 'microsoft.resources/subscriptions' }
        $r.Name = $parts[-1]
        $r
    }
    $docs = 'https://learn.microsoft.com/azure/defender-for-cloud'
    $notices = [System.Collections.Generic.List[string]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $Area, [string] $Title, [string] $Item, [string] $Subscription, [string] $Detail, [string] $Action, [string] $Link, [string] $Id)
        $findings.Add((& $object 'AAC.DefenderFinding' ([ordered]@{
                        Severity = $Severity; Area = $Area; Finding = $Title; Item = $Item; SubscriptionName = $(if ($Subscription) { & $subscriptionLabel $Subscription } else { '' })
                        Detail = $Detail; Recommendation = $Action; Link = $Link; SubscriptionId = ([string]$Subscription).ToLowerInvariant(); ResourceId = $Id
                    })))
    }

    # --- Defender plans: which plan covers which resource type -----------------------------------------------
    $planNames = [ordered]@{
        CloudPosture = 'Defender CSPM'; VirtualMachines = 'Servers'; SqlServers = 'Azure SQL databases'; SqlServerVirtualMachines = 'SQL servers on machines'
        OpenSourceRelationalDatabases = 'Open-source relational databases'; CosmosDbs = 'Azure Cosmos DB'; AppServices = 'App Service'; StorageAccounts = 'Storage'
        KeyVaults = 'Key Vault'; Containers = 'Containers'; Api = 'APIs'; AI = 'AI services'; Arm = 'Resource Manager'; Dns = 'DNS'
    }
    $planOfType = @{
        'microsoft.compute/virtualmachines' = 'VirtualMachines'; 'microsoft.compute/virtualmachinescalesets' = 'VirtualMachines'; 'microsoft.hybridcompute/machines' = 'VirtualMachines'
        'microsoft.sql/servers' = 'SqlServers'; 'microsoft.sql/servers/databases' = 'SqlServers'; 'microsoft.sql/managedinstances' = 'SqlServers'; 'microsoft.synapse/workspaces' = 'SqlServers'
        'microsoft.sqlvirtualmachine/sqlvirtualmachines' = 'SqlServerVirtualMachines'
        'microsoft.dbforpostgresql/servers' = 'OpenSourceRelationalDatabases'; 'microsoft.dbforpostgresql/flexibleservers' = 'OpenSourceRelationalDatabases'
        'microsoft.dbformysql/servers' = 'OpenSourceRelationalDatabases'; 'microsoft.dbformysql/flexibleservers' = 'OpenSourceRelationalDatabases'; 'microsoft.dbformariadb/servers' = 'OpenSourceRelationalDatabases'
        'microsoft.documentdb/databaseaccounts' = 'CosmosDbs'; 'microsoft.web/sites' = 'AppServices'; 'microsoft.storage/storageaccounts' = 'StorageAccounts'; 'microsoft.keyvault/vaults' = 'KeyVaults'
        'microsoft.containerservice/managedclusters' = 'Containers'; 'microsoft.containerregistry/registries' = 'Containers'; 'microsoft.kubernetes/connectedclusters' = 'Containers'
        'microsoft.apimanagement/service' = 'Api'; 'microsoft.cognitiveservices/accounts' = 'AI'
    }
    $planState = @{}   # "sub|plan" -> plan row
    foreach ($row in (& $rowsOf 'Plans')) {
        $sub = (& $text $row 'subscriptionId').ToLowerInvariant()
        if (-not (& $inScope $sub)) { continue }
        $planState["$sub|$(& $text $row 'plan')"] = $row
    }
    $planFor = {
        param([string] $Subscription, [string] $Type)
        if (-not $planOfType.Contains($Type)) { return @{ Plan = ''; State = '' } }
        $name = $planOfType[$Type]; $row = $planState["$Subscription|$name"]
        @{ Plan = $planNames[$name]; State = $(if (-not $row) { '' } elseif ((& $text $row 'tier') -eq 'Standard') { 'On' } else { 'Off' }) }
    }

    # --- Secure score and its controls ------------------------------------------------------------------------
    $scores = @{}
    foreach ($row in (& $rowsOf 'Scores')) {
        $sub = (& $text $row 'subscriptionId').ToLowerInvariant()
        if (& $inScope $sub) { $scores[$sub] = @{ Current = [double](& $value $row 'current'); Max = [double](& $value $row 'max') } }
    }
    $maxima = @{}; foreach ($key in $scores.Keys) { $maxima[$key] = $scores[$key].Max }
    $controls = @(ConvertTo-AACSecurityControl -Row (& $rowsOf 'Controls') -ScoreMax $maxima -SubscriptionName $SubscriptionName | Sort-Object -Property @{ Expression = 'PotentialIncrease'; Descending = $true }, Control)
    $controlOf = @{}
    foreach ($row in (& $rowsOf 'ControlAssessments')) { $controlOf[(& $text $row 'key').ToLowerInvariant()] = & $text $row 'control' }

    # --- Recommendations: per resource, then per recommendation --------------------------------------------------
    $unhealthy = @(foreach ($row in (& $rowsOf 'Unhealthy')) {
            $sub = & $text $row 'subscriptionId'
            if (-not (& $inScope $sub)) { continue }
            $id = & $text $row 'resourceId'; $where = & $parse $id; $key = & $text $row 'key'
            & $object 'AAC.DefenderUnhealthyResource' ([ordered]@{
                    Recommendation = & $text $row 'name'; Severity = & $text $row 'severity'; RiskLevel = & $text $row 'riskLevel'
                    RiskFactors = (@(& $list (& $value $row 'riskFactors')) -join ', '); AttackPaths = [int](& $value $row 'attackPaths')
                    Control = $(if ($controlOf.Contains($key)) { $controlOf[$key] } else { '' })
                    Resource = $where.Name; Type = $where.Type; ResourceGroup = $where.Group; SubscriptionName = & $subscriptionLabel $sub
                    Cause = $(if (& $text $row 'statusDescription') { & $text $row 'statusDescription' } else { & $text $row 'cause' })
                    Since = & $date (& $text $row 'since'); Source = $(if (& $text $row 'source') { & $text $row 'source' } else { 'Azure' })
                    Link = & $text $row 'link'; Key = $key; SubscriptionId = $sub.ToLowerInvariant(); ResourceId = $id
                })
        })
    $unhealthy = @($unhealthy | Sort-Object -Property @{ Expression = { & $rankOf $_.RiskLevel } }, @{ Expression = { & $rankOf $_.Severity } }, Recommendation, Resource)
    $byRecommendation = @{}
    foreach ($item in $unhealthy) { if (-not $byRecommendation.Contains($item.Key)) { $byRecommendation[$item.Key] = [System.Collections.Generic.List[object]]::new() }; $byRecommendation[$item.Key].Add($item) }
    $recommendationName = @{}
    $recommendations = @(foreach ($row in (& $rowsOf 'RecommendationSummary')) {
            $key = & $text $row 'key'
            $u = [int](& $value $row 'unhealthy'); $h = [int](& $value $row 'healthy'); $na = [int](& $value $row 'notApplicable')
            if (-not ($u + $h + $na)) { continue }
            $recommendationName[$key] = & $text $row 'name'
            $resources = @(if ($byRecommendation.Contains($key)) { $byRecommendation[$key] })
            $risk = @($resources | Where-Object RiskLevel | Sort-Object -Property @{ Expression = { & $rankOf $_.RiskLevel } } | Select-Object -First 1 -ExpandProperty RiskLevel)
            & $object 'AAC.DefenderRecommendation' ([ordered]@{
                    Recommendation = & $text $row 'name'; Severity = & $text $row 'severity'; RiskLevel = [string]($risk | Select-Object -First 1)
                    Status = $(if ($u) { 'Unhealthy' } elseif ($h) { 'Healthy' } else { 'Not applicable' })
                    Control = $(if ($controlOf.Contains($key)) { $controlOf[$key] } else { '' }); Categories = & $text $row 'categories'
                    UnhealthyResources = $u; HealthyResources = $h; NotApplicableResources = $na
                    HealthyPercent = $(if ($u + $h) { [Math]::Round(100 * $h / ($u + $h)) } else { $null })
                    Subscriptions = [int](& $value $row 'subscriptions'); AttackPaths = $($n = 0; foreach ($x in $resources) { $n += [int]$x.AttackPaths }; $n)
                    Impact = & $text $row 'impact'; Effort = & $text $row 'effort'; Threats = & $text $row 'threats'
                    Type = $(if (& $text $row 'assessmentType') { & $text $row 'assessmentType' } else { 'BuiltIn' }); Preview = $(if ((& $text $row 'preview') -eq 'True') { 'Yes' } else { 'No' })
                    Description = & $plain (& $text $row 'description'); Remediation = & $plain (& $text $row 'remediation')
                    Link = [string](@($resources | Where-Object Link | Select-Object -First 1 -ExpandProperty Link) | Select-Object -First 1)
                    Key = $key; PolicyDefinitionId = & $text $row 'policyDefinitionId'
                })
        })
    $recommendations = @($recommendations | Sort-Object -Property @{ Expression = { if ($_.UnhealthyResources) { 0 } else { 1 } } }, @{ Expression = { & $rankOf $_.RiskLevel } }, @{ Expression = { & $rankOf $_.Severity } }, @{ Expression = 'UnhealthyResources'; Descending = $true }, Recommendation)
    foreach ($item in $unhealthy) { if (-not $recommendationName.Contains($item.Key)) { $recommendationName[$item.Key] = $item.Recommendation } }

    # --- Attack paths ------------------------------------------------------------------------------------------
    $pathResources = @{}   # resource ID -> attack paths it is on
    $attackPaths = @(foreach ($row in (& $rowsOf 'AttackPaths')) {
            $sub = & $text $row 'subscriptionId'
            if (-not (& $inScope $sub)) { continue }
            $p = & $value $row 'properties'
            $entities = @(& $list (& $get $p 'graphComponent.entities'))
            $connections = @(& $list (& $get $p 'graphComponent.connections'))
            $nodeName = {
                param($Entity)
                $azure = [string](& $get $Entity 'entityIdentifiers.azureResourceId')
                $name = [string](& $get $Entity 'entityName'); if (-not $name) { $name = [string](& $get $Entity 'displayName') }
                if (-not $name -and $azure) { $name = ($azure -split '/')[-1] }
                $type = [string](& $get $Entity 'entityType')
                if (-not $name) { $name = $type }
                if ($type -and $name -ne $type) { "$name ($type)" } else { $name }
            }
            # The path: follow the connections from the entity nothing leads to.
            $byId = [ordered]@{}
            foreach ($e in $entities) { $eid = [string](& $get $e 'entityInternalId'); if (-not $eid) { $eid = [string]$byId.Count }; $byId[$eid] = $e }
            $next = @{}; $incoming = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($c in $connections) {
                $from = [string](& $get $c 'sourceEntityInternalId'); $to = [string](& $get $c 'targetEntityInternalId')
                if ($from -and $to) { if (-not $next.Contains($from)) { $next[$from] = $to }; [void]$incoming.Add($to) }
            }
            $chain = [System.Collections.Generic.List[object]]::new()
            $start = @($byId.Keys | Where-Object { $next.Contains($_) -and -not $incoming.Contains($_) }) | Select-Object -First 1
            if ($start) {
                $seen = [System.Collections.Generic.HashSet[string]]::new(); $at = $start
                while ($at -and $byId.Contains($at) -and $seen.Add($at) -and $chain.Count -lt 15) { $chain.Add($byId[$at]); $at = $next[$at] }
            }
            if ($chain.Count -lt 2) { $chain = [System.Collections.Generic.List[object]]::new(); foreach ($e in $byId.Values) { $chain.Add($e) } }
            $steps = @($chain | ForEach-Object { & $nodeName $_ })
            $ids = @($entities | ForEach-Object { [string](& $get $_ 'entityIdentifiers.azureResourceId') } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
            $risk = [string](& $get $p 'riskLevel'); if (-not $risk) { $risk = [string](@(& $list (& $get $p 'riskCategories')) | Select-Object -First 1) }
            $remediation = & $get $p 'remediationSteps'; if ($null -eq $remediation) { $remediation = & $get $p 'remediation' }
            $item = & $object 'AAC.DefenderAttackPath' ([ordered]@{
                    AttackPath = [string](& $get $p 'displayName'); RiskLevel = $risk; RiskFactors = (@(& $list (& $get $p 'riskFactors')) -join ', ')
                    EntryPoint = $(if ($steps.Count) { $steps[0] } else { '' }); Target = $(if ($steps.Count) { $steps[-1] } else { '' }); Path = $steps -join ' → '; Steps = $steps.Count
                    Tactics = (@(& $list (& $get $p 'mitreTactics')) -join ', '); Techniques = (@(& $list (& $get $p 'mitreTechniques')) -join ', ')
                    Description = & $plain ([string](& $get $p 'description')); Story = & $plain ([string](& $get $p 'attackStory'))
                    Remediation = & $plain ((@(& $list $remediation) | ForEach-Object { if ($_ -is [System.Collections.IDictionary]) { ConvertTo-Json -InputObject $_ -Compress -Depth 5 } else { [string]$_ } }) -join "`n")
                    Resources = $ids.Count; SubscriptionName = & $subscriptionLabel $sub; SubscriptionId = $sub.ToLowerInvariant()
                    ResourceId = $(if ($ids.Count) { $ids[-1] } else { '' }); Id = & $text $row 'id'
                })
            foreach ($rid in $ids) { $pathResources[$rid] = 1 + [int]$pathResources[$rid] }
            $item
        })
    $attackPaths = @($attackPaths | Sort-Object -Property @{ Expression = { & $rankOf $_.RiskLevel } }, AttackPath)

    # --- Security alerts ---------------------------------------------------------------------------------------
    $alertResources = @{}   # resource ID -> active alerts
    $alerts = @(foreach ($row in (& $rowsOf 'Alerts')) {
            $sub = & $text $row 'subscriptionId'
            if (-not (& $inScope $sub)) { continue }
            $target = @(@(& $list (& $value $row 'resources')) | ForEach-Object { [string](& $get $_ 'azureResourceId') } | Where-Object { $_ }) | Select-Object -First 1
            $where = & $parse $target
            $when = & $date (& $text $row 'time')
            $status = & $text $row 'status'
            $active = $status -in 'Active', 'InProgress'
            if ($active -and $target) { $alertResources[$target.ToLowerInvariant()] = 1 + [int]$alertResources[$target.ToLowerInvariant()] }
            & $object 'AAC.DefenderAlert' ([ordered]@{
                    Alert = & $text $row 'name'; Severity = & $text $row 'severity'; Status = $status; Active = $(if ($active) { 'Yes' } else { 'No' })
                    Tactics = & $text $row 'intent'; Techniques = (@(& $list (& $value $row 'techniques')) + @(& $list (& $value $row 'subTechniques')) | Select-Object -Unique) -join ', '
                    Resource = $(if ($where.Name) { $where.Name } else { & $text $row 'entity' }); Type = $where.Type; ResourceGroup = $where.Group; Entity = & $text $row 'entity'
                    SubscriptionName = & $subscriptionLabel $sub; TimeGenerated = $when; StartTime = & $date (& $text $row 'start'); EndTime = & $date (& $text $row 'end')
                    AgeDays = $(if ($when) { [int][Math]::Floor(($Now - $when).TotalDays) } else { $null })
                    Product = & $text $row 'product'; Incident = $(if ((& $text $row 'isIncident') -eq 'True') { 'Yes' } else { 'No' }); AlertType = & $text $row 'alertType'
                    Description = & $plain (& $text $row 'description'); Remediation = & $plain ((@(& $list (& $value $row 'remediation')) | ForEach-Object { [string]$_ }) -join "`n")
                    Link = & $text $row 'link'; SubscriptionId = $sub.ToLowerInvariant(); ResourceId = [string]$target
                })
        })
    $alerts = @($alerts | Sort-Object -Property @{ Expression = { if ($_.Active -eq 'Yes') { 0 } else { 1 } } }, @{ Expression = { & $rankOf $_.Severity } }, @{ Expression = 'TimeGenerated'; Descending = $true })

    # --- Vulnerabilities (sub-assessments) ----------------------------------------------------------------------
    $vulnerabilityResources = @{}
    $vulnerabilities = @(foreach ($row in (& $rowsOf 'Vulnerabilities')) {
            $sub = & $text $row 'subscriptionId'
            if (-not (& $inScope $sub)) { continue }
            $id = & $text $row 'resourceId'; $where = & $parse $id
            if ($id) { $vulnerabilityResources[$id.ToLowerInvariant()] = 1 + [int]$vulnerabilityResources[$id.ToLowerInvariant()] }
            $cves = @(@(& $list (& $value $row 'cve')) | ForEach-Object { if ($_ -is [System.Collections.IDictionary]) { [string](& $get $_ 'title') } else { [string]$_ } } | Where-Object { $_ })
            if (-not $cves.Count -and (& $text $row 'cveId')) { $cves = @(& $text $row 'cveId') }
            $parent = & $text $row 'assessmentKey'
            & $object 'AAC.DefenderVulnerability' ([ordered]@{
                    Vulnerability = & $text $row 'name'; Severity = & $text $row 'severity'; CVEs = ($cves | Select-Object -Unique) -join ', '
                    Patchable = $(switch (& $text $row 'patchable') { 'True' { 'Yes' } 'False' { 'No' } default { '' } }); Category = & $text $row 'category'
                    Resource = $where.Name; Type = $where.Type; ResourceGroup = $where.Group; Image = & $text $row 'image'; SubscriptionName = & $subscriptionLabel $sub
                    Recommendation = $(if ($recommendationName.Contains($parent)) { $recommendationName[$parent] } else { '' })
                    Impact = & $plain (& $text $row 'impact'); Remediation = & $plain (& $text $row 'remediation'); Generated = & $date (& $text $row 'generated')
                    VulnerabilityId = & $text $row 'vulnerabilityId'; SubscriptionId = $sub.ToLowerInvariant(); ResourceId = $id
                })
        })
    $vulnerabilities = @($vulnerabilities | Sort-Object -Property @{ Expression = { & $rankOf $_.Severity } }, Vulnerability, Resource)

    # --- Inventory ------------------------------------------------------------------------------------------------
    $inventory = @(foreach ($row in (& $rowsOf 'InventorySummary')) {
            $sub = (& $text $row 'subscriptionId').ToLowerInvariant()
            if (-not (& $inScope $sub)) { continue }
            $id = & $text $row 'resourceId'; $where = & $parse $id; $key = $id.ToLowerInvariant()
            $plan = & $planFor $sub $where.Type
            $u = [int](& $value $row 'unhealthy'); $h = [int](& $value $row 'healthy')
            & $object 'AAC.DefenderResource' ([ordered]@{
                    Resource = $where.Name; Type = $where.Type; ResourceGroup = $where.Group; SubscriptionName = & $subscriptionLabel $sub
                    Source = $(if (& $text $row 'source') { & $text $row 'source' } else { 'Azure' }); Plan = $plan.Plan; PlanState = $plan.State
                    Status = $(if ($u) { 'Unhealthy' } elseif ($h) { 'Healthy' } else { 'Not applicable' })
                    Unhealthy = $u; High = [int](& $value $row 'high'); Medium = [int](& $value $row 'medium'); Low = [int](& $value $row 'low')
                    Healthy = $h; NotApplicable = [int](& $value $row 'notApplicable')
                    Vulnerabilities = [int]$vulnerabilityResources[$key]; Alerts = [int]$alertResources[$key]; AttackPaths = [int]$pathResources[$key]
                    SubscriptionId = $sub; ResourceId = $id
                })
        })
    $inventory = @($inventory | Sort-Object -Property @{ Expression = 'AttackPaths'; Descending = $true }, @{ Expression = 'High'; Descending = $true }, @{ Expression = 'Unhealthy'; Descending = $true }, Resource)

    # --- Plans ------------------------------------------------------------------------------------------------------
    $typeCount = @{}   # "sub|plan" -> resources in inventory the plan covers
    foreach ($r in $inventory) { if ($planOfType.Contains($r.Type)) { $k = "$($r.SubscriptionId)|$($planOfType[$r.Type])"; $typeCount[$k] = 1 + [int]$typeCount[$k] } }
    $plans = @(foreach ($key in $planState.Keys) {
            $row = $planState[$key]; $sub = $key.Split('|')[0]; $name = & $text $row 'plan'
            $on = (& $text $row 'tier') -eq 'Standard'
            $extensions = @(@(& $list (& $value $row 'extensions')) | Where-Object { [string](& $get $_ 'isEnabled') -eq 'True' } | ForEach-Object { [string](& $get $_ 'name') })
            & $object 'AAC.DefenderPlanReport' ([ordered]@{
                    SubscriptionName = & $subscriptionLabel $sub; Plan = $(if ($planNames.Contains($name)) { $planNames[$name] } else { $name }); State = $(if ($on) { 'On' } else { 'Off' })
                    Tier = & $text $row 'tier'; SubPlan = & $text $row 'subPlan'; Extensions = $extensions -join ', '; Since = & $date (& $text $row 'since')
                    Resources = [int]$typeCount[$key]; Name = $name; SubscriptionId = $sub
                })
        })
    $plans = @($plans | Sort-Object -Property SubscriptionName, @{ Expression = { if ($_.State -eq 'On') { 0 } else { 1 } } }, Plan)
    foreach ($plan in $plans) {
        $where = "/subscriptions/$($plan.SubscriptionId)"
        if ($plan.State -eq 'Off' -and $plan.Resources) {
            & $finding 'High' 'Plans' "Defender for $($plan.Plan) is off" $plan.Plan $plan.SubscriptionId "$($plan.Resources) $($plan.Plan) resource(s) in this subscription get no threat detection, alerts or (for some plans) vulnerability scanning." "Turn the plan on in Defender for Cloud > Environment settings > $($plan.SubscriptionName) > Defender plans." "$docs/defender-for-cloud-introduction" $where
        }
        elseif ($plan.State -eq 'Off' -and $plan.Name -eq 'CloudPosture') {
            & $finding 'Medium' 'Plans' 'Defender CSPM is off' $plan.Plan $plan.SubscriptionId 'Without it there is no attack path analysis, risk-based prioritisation, cloud security explorer, agentless scanning or data security posture: only the free foundational CSPM.' 'Turn on Defender CSPM to see attack paths and prioritise recommendations by risk.' "$docs/concept-cloud-security-posture-management" $where
        }
        elseif ($plan.State -eq 'Off' -and $plan.Name -eq 'Arm') {
            & $finding 'Medium' 'Plans' 'Defender for Resource Manager is off' $plan.Plan $plan.SubscriptionId 'Suspicious management operations (from unusual IPs, by compromised identities, mass deletions) are not detected.' 'Turn on Defender for Resource Manager.' "$docs/defender-for-resource-manager-introduction" $where
        }
        elseif ($plan.State -eq 'On' -and $plan.Name -eq 'VirtualMachines' -and $plan.SubPlan -eq 'P1') {
            & $finding 'Low' 'Plans' 'Defender for Servers on Plan 1' $plan.Plan $plan.SubscriptionId 'Plan 1 has Defender for Endpoint only: no agentless scanning, vulnerability assessment, just-in-time access, file integrity monitoring or the free 500 MB of security data a day.' 'Consider Plan 2 for servers that need those.' "$docs/plan-defender-for-servers-select-plan" $where
        }
    }

    # --- Subscriptions' scores --------------------------------------------------------------------------------------------
    foreach ($sub in $scores.Keys) {
        $s = $scores[$sub]
        $pct = if ($s.Max -gt 0) { [Math]::Round(100 * $s.Current / $s.Max) } else { $null }
        if ($null -ne $pct -and $pct -lt $ScoreWarningPercent) {
            & $finding $(if ($pct -lt $ScoreWarningPercent / 2) { 'High' } else { 'Medium' }) 'Secure score' "Secure score $pct%" (& $subscriptionLabel $sub) $sub "Under $ScoreWarningPercent%: $([Math]::Round($s.Current, 1)) of $([Math]::Round($s.Max, 1)) points." 'Start with the secure score controls with the largest potential increase (Security posture tab).' "$docs/secure-score-security-controls" "/subscriptions/$sub"
        }
    }
    foreach ($path in @($attackPaths | Where-Object { $_.RiskLevel -in 'Critical', 'High' })) {
        & $finding $(if ($path.RiskLevel -eq 'Critical') { 'Critical' } else { 'High' }) 'Attack paths' "$($path.RiskLevel) attack path" $path.AttackPath $path.SubscriptionId "$($path.Path)$(if ($path.RiskFactors) { " - risk factors: $($path.RiskFactors)" })" 'Break the path at its entry point (the Attack path analysis tab has the remediation steps).' "$docs/concept-attack-path" $path.ResourceId
    }
    foreach ($group in @($alerts | Where-Object { $_.Active -eq 'Yes' -and $_.Severity -eq 'High' } | Group-Object SubscriptionId)) {
        $oldest = ($group.Group | Measure-Object AgeDays -Maximum).Maximum
        & $finding 'High' 'Alerts' 'High-severity alerts still active' "$($group.Count) alert(s)" $group.Name "$($group.Count) High alert(s) active or in progress; the oldest is $oldest day(s) old: $(@($group.Group | Select-Object -ExpandProperty Alert -Unique | Select-Object -First 3) -join '; ')." 'Investigate and resolve them (or dismiss false positives, with a suppression rule if they recur).' "$docs/managing-and-responding-alerts" "/subscriptions/$($group.Name)"
    }
    foreach ($group in @($alerts | Where-Object { $_.Active -eq 'Yes' -and $_.Severity -eq 'Medium' -and $_.AgeDays -gt 7 } | Group-Object SubscriptionId)) {
        & $finding 'Medium' 'Alerts' 'Medium-severity alerts active for over a week' "$($group.Count) alert(s)" $group.Name "$($group.Count) Medium alert(s) have been open for more than 7 days." 'Triage them: an alert left open stops being looked at.' "$docs/managing-and-responding-alerts" "/subscriptions/$($group.Name)"
    }

    # --- Environment settings (REST) ---------------------------------------------------------------------------------------
    $restOf = {
        # A REST result for a subscription: its items, or $null with a notice when it couldn't be read.
        param([string] $Name, [string] $Subscription)
        if (-not $Rest.Contains($Name)) { return $null }
        $result = $Rest[$Name][$Subscription]
        if (-not $result) { return $null }
        if (& $value $result 'Error') { return @{ Failed = [string](& $value $result 'Error'); Items = @() } }
        @{ Failed = ''; Items = @(& $list (& $value $result 'Items')) }
    }
    $settingRows = [System.Collections.Generic.List[object]]::new()
    $setting = {
        param([string] $Subscription, [string] $Area, [string] $Name, [string] $Value, [string] $Status, [string] $Detail)
        $settingRows.Add((& $object 'AAC.DefenderSetting' ([ordered]@{ SubscriptionName = & $subscriptionLabel $Subscription; Area = $Area; Setting = $Name; Value = $Value; Status = $Status; Detail = $Detail; SubscriptionId = $Subscription })))
    }
    $failedRest = @{}
    $connectors = [System.Collections.Generic.List[object]]::new()
    $jit = [System.Collections.Generic.List[object]]::new()
    $suppression = [System.Collections.Generic.List[object]]::new()
    $serversOn = { param([string] $Sub) $row = $planState["$Sub|VirtualMachines"]; $row -and (& $text $row 'tier') -eq 'Standard' }
    foreach ($sub in @($SubscriptionName.Keys | Sort-Object)) {
        $where = "/subscriptions/$sub"
        # Security contacts: 2023-12-01-preview (notificationsSources), or the older shape (alertNotifications).
        $contacts = & $restOf 'Contacts' $sub
        if ($contacts -and $contacts.Failed) { $failedRest['security contacts'] = $contacts.Failed; & $setting $sub 'Notifications' 'Security contacts' '' 'Unknown' $contacts.Failed }
        elseif ($contacts) {
            $props = @($contacts.Items | ForEach-Object { & $get $_ 'properties' })
            $emails = @($props | ForEach-Object { ([string](& $get $_ 'emails')) -split '[;,]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
            $sources = @($props | ForEach-Object { & $list (& $get $_ 'notificationsSources') })
            $alertSource = @($sources | Where-Object { [string](& $get $_ 'sourceType') -eq 'Alert' }) | Select-Object -First 1
            $pathSource = @($sources | Where-Object { [string](& $get $_ 'sourceType') -eq 'AttackPath' }) | Select-Object -First 1
            $enabled = @($props | Where-Object { [string](& $get $_ 'isEnabled') -eq 'True' -or [string](& $get $_ 'alertNotifications.state') -eq 'On' }).Count -gt 0
            $minimum = if ($alertSource) { [string](& $get $alertSource 'minimalSeverity') } else { [string](@($props | ForEach-Object { & $get $_ 'alertNotifications.minimalSeverity' } | Where-Object { $_ }) | Select-Object -First 1) }
            $alertsOn = $enabled -and ($alertSource -or -not $sources.Count)
            $roles = @($props | Where-Object { [string](& $get $_ 'notificationsByRole.state') -eq 'On' } | ForEach-Object { & $list (& $get $_ 'notificationsByRole.roles') } | Select-Object -Unique)
            & $setting $sub 'Notifications' 'Security contact e-mails' $(if ($emails.Count) { $emails -join '; ' } else { '(none)' }) $(if ($emails.Count) { 'Good' } else { 'Warning' }) 'Who Defender for Cloud e-mails about alerts and attack paths.'
            & $setting $sub 'Notifications' 'Alert e-mails' $(if ($alertsOn) { "On, $(if ($minimum) { $minimum } else { 'High' }) and above" } else { 'Off' }) $(if (-not $alertsOn) { 'Warning' } elseif ($minimum -eq 'High') { 'Review' } else { 'Good' }) 'The lowest alert severity e-mailed.'
            & $setting $sub 'Notifications' 'Attack path e-mails' $(if ($enabled -and $pathSource) { "On, $([string](& $get $pathSource 'minimalRiskLevel')) and above" } else { 'Off' }) $(if ($enabled -and $pathSource) { 'Good' } else { 'Review' }) 'E-mails about new attack paths (Defender CSPM).'
            & $setting $sub 'Notifications' 'Notify roles' $(if ($roles.Count) { $roles -join ', ' } else { 'Off' }) $(if ($roles.Count) { 'Good' } else { 'Review' }) 'Subscription roles e-mailed as well as the contacts.'
            if (-not $emails.Count) { & $finding 'Medium' 'Notifications' 'No security contact e-mail' (& $subscriptionLabel $sub) $sub 'Nobody is e-mailed about alerts or attack paths in this subscription.' 'Add a security contact (a monitored mailbox or distribution list) in Environment settings > Email notifications.' "$docs/configure-email-notifications" $where }
            elseif (-not $alertsOn) { & $finding 'Medium' 'Notifications' 'Alert e-mails are off' (& $subscriptionLabel $sub) $sub 'Security contacts are set, but not e-mailed about alerts.' 'Turn on alert notifications, for Medium severity and above.' "$docs/configure-email-notifications" $where }
            elseif ($minimum -eq 'High') { & $finding 'Low' 'Notifications' 'Only High alerts are e-mailed' (& $subscriptionLabel $sub) $sub 'Medium alerts (most real attacks start there) are not e-mailed.' 'Lower the notification severity to Medium.' "$docs/configure-email-notifications" $where }
            if ($emails.Count -and -not $roles.Count) { & $finding 'Low' 'Notifications' 'Subscription owners are not notified' (& $subscriptionLabel $sub) $sub 'Only the listed contacts get alert e-mails.' 'Notify the Owner role too, so alerts reach someone accountable.' "$docs/configure-email-notifications" $where }
        }
        # Integrations: Defender for Endpoint (WDATP), Defender for Cloud Apps (MCAS), Sentinel.
        $settings = & $restOf 'Settings' $sub
        if ($settings -and $settings.Failed) { $failedRest['integration settings'] = $settings.Failed; & $setting $sub 'Integrations' 'Integrations' '' 'Unknown' $settings.Failed }
        elseif ($settings) {
            $named = @{ WDATP = 'Microsoft Defender for Endpoint'; MCAS = 'Microsoft Defender for Cloud Apps'; Sentinel = 'Microsoft Sentinel bi-directional sync' }
            foreach ($item in $settings.Items) {
                $name = [string](& $get $item 'name')
                if (-not $named.Contains($name)) { continue }
                $on = [string](& $get $item 'properties.enabled') -eq 'True'
                & $setting $sub 'Integrations' $named[$name] $(if ($on) { 'On' } else { 'Off' }) $(if ($on) { 'Good' } elseif ($name -eq 'WDATP') { 'Warning' } else { 'Review' }) ''
                if (-not $on -and $name -eq 'WDATP' -and (& $serversOn $sub)) { & $finding 'High' 'Integrations' 'Defender for Endpoint integration is off' (& $subscriptionLabel $sub) $sub 'Defender for Servers is on, but its EDR (Defender for Endpoint) is not deployed to the machines.' 'Turn on the Endpoint protection integration in the Servers plan settings.' "$docs/integration-defender-for-endpoint" $where }
                if (-not $on -and $name -eq 'MCAS') { & $finding 'Low' 'Integrations' 'Defender for Cloud Apps integration is off' (& $subscriptionLabel $sub) $sub 'Defender for Cloud Apps alerts are not shown in Defender for Cloud.' 'Turn on the integration if you use Defender for Cloud Apps.' "$docs/defender-for-cloud-introduction" $where }
            }
        }
        $items = & $restOf 'Connectors' $sub
        if ($items -and $items.Failed) { $failedRest['multicloud connectors'] = $items.Failed }
        elseif ($items) {
            foreach ($item in $items.Items) {
                $connectors.Add((& $object 'AAC.DefenderConnector' ([ordered]@{
                                Connector = [string](& $get $item 'name'); Environment = [string](& $get $item 'properties.environmentName'); Account = [string](& $get $item 'properties.hierarchyIdentifier')
                                Offerings = (@(& $list (& $get $item 'properties.offerings') | ForEach-Object { [string](& $get $_ 'offeringType') }) -join ', '); Location = [string](& $get $item 'location')
                                SubscriptionName = & $subscriptionLabel $sub; SubscriptionId = $sub; ResourceId = [string](& $get $item 'id')
                            })))
            }
        }
        $items = & $restOf 'Jit' $sub
        if ($items -and $items.Failed) { $failedRest['just-in-time policies'] = $items.Failed }
        elseif ($items) {
            foreach ($policy in $items.Items) {
                foreach ($vm in @(& $list (& $get $policy 'properties.virtualMachines'))) {
                    $vmId = [string](& $get $vm 'id')
                    foreach ($port in @(& $list (& $get $vm 'ports'))) {
                        $sources = @(@([string](& $get $port 'allowedSourceAddressPrefix')) + @(& $list (& $get $port 'allowedSourceAddressPrefixes')) | Where-Object { $_ })
                        $jit.Add((& $object 'AAC.DefenderJitPolicy' ([ordered]@{
                                        Policy = [string](& $get $policy 'name'); VirtualMachine = ($vmId -split '/')[-1]; Port = [string](& $get $port 'number'); Protocol = [string](& $get $port 'protocol')
                                        AllowedSource = $sources -join ', '; MaxDuration = [string](& $get $port 'maxRequestAccessDuration'); SubscriptionName = & $subscriptionLabel $sub; SubscriptionId = $sub; ResourceId = $vmId
                                    })))
                        if ($sources -contains '*') { & $finding 'Medium' 'Just-in-time' 'Just-in-time port open to any source' "$(($vmId -split '/')[-1]):$([string](& $get $port 'number'))" $sub 'An access request can open the port to the whole internet.' 'Limit the allowed source to your IP ranges (or "My IP" per request).' "$docs/just-in-time-access-usage" $vmId }
                    }
                }
            }
        }
        $items = & $restOf 'Suppression' $sub
        if ($items -and $items.Failed) { $failedRest['alert suppression rules'] = $items.Failed }
        elseif ($items) {
            foreach ($rule in $items.Items) {
                $expires = & $date ([string](& $get $rule 'properties.expirationDateUtc'))
                $state = [string](& $get $rule 'properties.state')
                $status = if ($state -ne 'Enabled') { 'Disabled' } elseif (-not $expires) { 'No expiry' } elseif ($expires -lt $Now) { 'Expired' } else { 'Active' }
                $suppression.Add((& $object 'AAC.DefenderSuppressionRule' ([ordered]@{
                                Rule = [string](& $get $rule 'name'); AlertType = [string](& $get $rule 'properties.alertType'); State = $state; Status = $status; Expires = $expires
                                Reason = [string](& $get $rule 'properties.reason'); Comment = [string](& $get $rule 'properties.comment'); SubscriptionName = & $subscriptionLabel $sub; SubscriptionId = $sub
                            })))
                if ($status -eq 'No expiry') { & $finding 'Low' 'Suppression' 'Alert suppression rule with no expiry' ([string](& $get $rule 'name')) $sub "Alerts of type $([string](& $get $rule 'properties.alertType')) are dismissed for good." 'Give the rule an expiry date, and review it then.' "$docs/alerts-suppression-rules" $where }
            }
        }
    }
    foreach ($key in $failedRest.Keys | Sort-Object) { $notices.Add("The $key couldn't be read in every subscription: $($failedRest[$key])") }

    # --- Regulatory compliance -----------------------------------------------------------------------------------------
    $standards = @(foreach ($row in (& $rowsOf 'Standards')) {
            $sub = & $text $row 'subscriptionId'
            if (-not (& $inScope $sub)) { continue }
            $passed = [int](& $value $row 'passed'); $failed = [int](& $value $row 'failed')
            & $object 'AAC.DefenderComplianceStandard' ([ordered]@{
                    Standard = & $text $row 'standard'; SubscriptionName = & $subscriptionLabel $sub; State = & $text $row 'state'
                    PassedControls = $passed; FailedControls = $failed; SkippedControls = [int](& $value $row 'skipped'); UnsupportedControls = [int](& $value $row 'unsupported')
                    PassRate = $(if ($passed + $failed) { [Math]::Round(100 * $passed / ($passed + $failed)) } else { $null }); SubscriptionId = $sub.ToLowerInvariant()
                })
        })
    $standards = @($standards | Sort-Object -Property @{ Expression = { if ($null -eq $_.PassRate) { 101 } else { $_.PassRate } } }, Standard, SubscriptionName)
    $complianceControls = @(foreach ($row in (& $rowsOf 'ComplianceControls')) {
            $sub = & $text $row 'subscriptionId'
            if (-not (& $inScope $sub)) { continue }
            & $object 'AAC.DefenderComplianceControl' ([ordered]@{
                    Standard = & $text $row 'standard'; Control = & $text $row 'control'; Description = & $text $row 'description'; State = & $text $row 'state'
                    PassedAssessments = [int](& $value $row 'passed'); FailedAssessments = [int](& $value $row 'failed'); SkippedAssessments = [int](& $value $row 'skipped')
                    SubscriptionName = & $subscriptionLabel $sub; SubscriptionId = $sub.ToLowerInvariant()
                })
        })
    $complianceControls = @($complianceControls | Sort-Object -Property @{ Expression = { if ($_.State -eq 'Failed') { 0 } elseif ($_.State -eq 'Passed') { 2 } else { 1 } } }, Standard, Control)
    $severityOf = @{}; foreach ($r in $recommendations) { $severityOf[$r.Key] = $r.Severity }
    $complianceAssessments = @(foreach ($row in (& $rowsOf 'ComplianceAssessments')) {
            $sub = & $text $row 'subscriptionId'
            if (-not (& $inScope $sub) -or (& $text $row 'state') -ne 'Failed') { continue }
            $key = & $text $row 'key'
            & $object 'AAC.DefenderComplianceAssessment' ([ordered]@{
                    Standard = & $text $row 'standard'; Control = & $text $row 'control'; Assessment = & $text $row 'description'; State = & $text $row 'state'
                    FailedResources = [int](& $value $row 'failedResources'); Recommendation = $(if ($recommendationName.Contains($key)) { $recommendationName[$key] } else { '' })
                    Severity = $(if ($severityOf.Contains($key)) { $severityOf[$key] } else { '' }); SubscriptionName = & $subscriptionLabel $sub; Key = $key; SubscriptionId = $sub.ToLowerInvariant()
                })
        })
    $complianceAssessments = @($complianceAssessments | Sort-Object -Property Standard, Control, @{ Expression = 'FailedResources'; Descending = $true })

    # --- Subscriptions ----------------------------------------------------------------------------------------------------
    $subscriptions = @(foreach ($sub in @($SubscriptionName.Keys)) {
            $s = $scores[$sub]
            $mine = @($plans | Where-Object SubscriptionId -EQ $sub)
            & $object 'AAC.DefenderSubscription' ([ordered]@{
                    Subscription = $SubscriptionName[$sub]
                    SecureScore = $(if ($s -and $s.Max -gt 0) { [Math]::Round(100 * $s.Current / $s.Max) } else { $null })
                    PlansOn = @($mine | Where-Object State -EQ 'On').Count; Plans = $mine.Count
                    UnhealthyResources = @($unhealthy | Where-Object SubscriptionId -EQ $sub | Select-Object -ExpandProperty ResourceId -Unique).Count
                    HighRecommendations = @($unhealthy | Where-Object { $_.SubscriptionId -eq $sub -and $_.Severity -eq 'High' }).Count
                    AttackPaths = @($attackPaths | Where-Object SubscriptionId -EQ $sub).Count
                    ActiveAlerts = @($alerts | Where-Object { $_.SubscriptionId -eq $sub -and $_.Active -eq 'Yes' }).Count
                    Vulnerabilities = @($vulnerabilities | Where-Object SubscriptionId -EQ $sub).Count
                    Findings = @($findings | Where-Object SubscriptionId -EQ $sub).Count
                    SubscriptionId = $sub; ResourceId = "/subscriptions/$sub"
                })
        })
    $subscriptions = @($subscriptions | Sort-Object -Property @{ Expression = { if ($null -eq $_.SecureScore) { 101 } else { $_.SecureScore } } }, Subscription)

    $sorted = @($findings | Sort-Object -Property @{ Expression = { & $rankOf $_.Severity } }, Area, Finding, Item)
    $totalCurrent = 0.0; $totalMax = 0.0
    foreach ($s in $scores.Values) { $totalCurrent += $s.Current; $totalMax += $s.Max }
    @{
        Subscriptions         = $subscriptions
        Recommendations       = $recommendations
        UnhealthyResources    = $unhealthy
        Controls              = $controls
        AttackPaths           = $attackPaths
        Alerts                = $alerts
        Inventory             = $inventory
        Vulnerabilities       = $vulnerabilities
        Plans                 = $plans
        Standards             = $standards
        ComplianceControls    = $complianceControls
        ComplianceAssessments = $complianceAssessments
        Settings              = $settingRows.ToArray()
        Connectors            = $connectors.ToArray()
        JitPolicies           = $jit.ToArray()
        SuppressionRules      = $suppression.ToArray()
        Findings              = $sorted
        Notices               = $notices.ToArray()
        Stats                 = [ordered]@{
            Subscriptions          = $subscriptions.Count
            SecureScore            = $(if ($totalMax -gt 0) { [Math]::Round(100 * $totalCurrent / $totalMax) } else { $null })
            Recommendations        = @($recommendations | Where-Object UnhealthyResources).Count
            UnhealthyResources     = @($unhealthy | Select-Object -ExpandProperty ResourceId -Unique).Count
            HighRecommendations    = @($recommendations | Where-Object { $_.UnhealthyResources -and $_.Severity -eq 'High' }).Count
            AttackPaths            = $attackPaths.Count
            CriticalAttackPaths    = @($attackPaths | Where-Object { $_.RiskLevel -in 'Critical', 'High' }).Count
            Alerts                 = $alerts.Count
            ActiveAlerts           = @($alerts | Where-Object Active -EQ 'Yes').Count
            HighAlerts             = @($alerts | Where-Object { $_.Active -eq 'Yes' -and $_.Severity -eq 'High' }).Count
            Resources              = $inventory.Count
            Vulnerabilities        = $vulnerabilities.Count
            HighVulnerabilities    = @($vulnerabilities | Where-Object { $_.Severity -in 'Critical', 'High' }).Count
            PlansOn                = @($plans | Where-Object State -EQ 'On').Count
            PlansOff               = @($plans | Where-Object State -EQ 'Off').Count
            Standards              = $standards.Count
            FailedControls         = @($complianceControls | Where-Object State -EQ 'Failed').Count
            Findings               = $sorted.Count
            Critical               = @($sorted | Where-Object Severity -EQ 'Critical').Count
            High                   = @($sorted | Where-Object Severity -EQ 'High').Count
            Medium                 = @($sorted | Where-Object Severity -EQ 'Medium').Count
            Low                    = @($sorted | Where-Object Severity -EQ 'Low').Count
        }
    }
}
