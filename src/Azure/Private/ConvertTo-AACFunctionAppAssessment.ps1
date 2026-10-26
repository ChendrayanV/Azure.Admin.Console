function ConvertTo-AACFunctionAppAssessment {
    <#
    .SYNOPSIS
        Assesses function apps from what Invoke-AACFunctionAppAssessment
        read: each app and its plan, functions and triggers, configuration,
        app settings (names only), slots, deployments, networking, backups,
        connections, Activity Log, usage, Well-Architected checks, PSRule
        results and Advisor / Defender recommendations - as findings.
    .DESCRIPTION
        -App, -Plan, -Slot, -PrivateEndpoint, -Advisor and -Defender are
        Resource Graph rows; -Detail is Read-AACFunctionAppDetail's answer;
        -Metric is Read-AACMetric's (calls Http, Exec, Latency, Memory per
        app, Plan per plan) over -Hours; -PSRule the PSRule for Azure results.

        Hosting is read from the plan: Consumption (Y1), Flex Consumption
        (FC1), Elastic Premium (EP1-3), Dedicated (an App Service plan) or
        App Service Environment (Isolated); a Container Apps environment if
        the app has one.

        Language runtimes are checked against their end of support (dates
        as Microsoft publishes them for Azure Functions; -Now is the date to
        judge by): out of support, ending within 180 days, or supported.
        The .NET in-process model's support ends on 10 November 2026.

        Consumption cost is estimated from execution units (GB-seconds at
        USD 0.000016) and executions (USD 0.20 a million), scaled to 30
        days, before the monthly free grant (400,000 GB-s and a million
        executions per subscription) - a guide, not a bill.

        Setting values never leave this function: app settings are
        returned as names with a kind (Key Vault reference, identity-based
        connection, key or connection string, plain value, platform).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $App = @(),
        [AllowEmptyCollection()] [object[]] $Plan = @(),
        [AllowEmptyCollection()] [object[]] $Slot = @(),
        [AllowEmptyCollection()] [object[]] $PrivateEndpoint = @(),
        [AllowEmptyCollection()] [object[]] $Advisor = @(),
        [AllowEmptyCollection()] [object[]] $Defender = @(),
        [AllowEmptyCollection()] [object[]] $PSRule = @(),
        [hashtable] $Detail = @{},
        [hashtable] $Metric = @{},
        [hashtable] $SubscriptionName = @{},
        [double] $Hours = 168,
        [int] $ActivityDays = 7,
        [datetime] $Now = [datetime]::UtcNow
    )

    $at = {
        param($Value, [string[]] $Keys)
        foreach ($key in $Keys) { if ($Value -is [System.Collections.IDictionary]) { $Value = $Value[$key] } else { return $null } }
        $Value
    }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $when = { param($Value) if ($Value -is [datetime]) { $Value.ToUniversalTime() } elseif ($Value) { try { [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) } catch { $null } } else { $null } }
    $round = { param($Number, [int] $Digits = 1) if ($null -eq $Number) { $null } else { [Math]::Round([double]$Number, $Digits) } }
    $subName = { param([string] $Id) $k = & $lower $Id; if ($SubscriptionName.ContainsKey($k)) { $SubscriptionName[$k] } else { $Id } }
    $bodyOf = { param($Answer) if ($Answer -is [System.Collections.IDictionary] -and -not $Answer['Error']) { $Answer['Body'] } else { $null } }
    $itemsOf = { param($Answer) @(if ($Answer -is [System.Collections.IDictionary] -and -not $Answer['Error']) { $Answer['Items'] | Where-Object { $_ } }) }
    $readOk = { param($Answer) [bool]($Answer -is [System.Collections.IDictionary] -and -not $Answer['Error']) }
    # Metric totals, averages and maxima across a call's series.
    $seriesOf = { param([string] $Id, [string] $Call, [string] $Name) $m = $Metric[$Id]; if (-not $m) { $m = $Metric[(& $lower $Id)] }; if (-not $m -or -not $m[$Call] -or $m[$Call].Error) { return $null }; @($m[$Call].Series | Where-Object { $_.Name -eq $Name }) }
    $total = { param([string] $Id, [string] $Call, [string] $Name) $s = & $seriesOf $Id $Call $Name; if ($null -eq $s) { return $null }; $t = 0.0; foreach ($x in $s) { foreach ($p in $x.Points) { if ($null -ne $p['total']) { $t += [double]$p['total'] } } }; $t }
    $average = { param([string] $Id, [string] $Call, [string] $Name) $s = & $seriesOf $Id $Call $Name; if ($null -eq $s) { return $null }; $v = @(foreach ($x in $s) { foreach ($p in $x.Points) { if ($null -ne $p['average']) { [double]$p['average'] } } }); if ($v.Count) { ($v | Measure-Object -Average).Average } else { $null } }
    $maximum = { param([string] $Id, [string] $Call, [string] $Name) $s = & $seriesOf $Id $Call $Name; if ($null -eq $s) { return $null }; $v = @(foreach ($x in $s) { foreach ($p in $x.Points) { if ($null -ne $p['maximum']) { [double]$p['maximum'] } } }); if ($v.Count) { ($v | Measure-Object -Maximum).Maximum } else { $null } }

    # --- Runtime support ----------------------------------------------------------------------------------------------
    $endOfSupport = @{
        'dotnet|6' = '2024-11-12'; 'dotnet|7' = '2024-05-14'; 'dotnet|8' = '2026-11-10'; 'dotnet|9' = '2026-11-10'; 'dotnet|10' = '2028-11-14'
        'node|14' = '2023-04-30'; 'node|16' = '2023-09-11'; 'node|18' = '2025-04-30'; 'node|20' = '2026-04-30'; 'node|22' = '2027-04-30'
        'python|3.7' = '2023-06-27'; 'python|3.8' = '2024-10-07'; 'python|3.9' = '2025-10-31'; 'python|3.10' = '2026-10-31'; 'python|3.11' = '2027-10-31'; 'python|3.12' = '2028-10-31'; 'python|3.13' = '2029-10-31'
        'powershell|7.0' = '2022-12-03'; 'powershell|7.2' = '2024-11-08'; 'powershell|7.4' = '2026-11-10'
        'java|11' = '2027-09-30'
    }
    $inProcessEnd = [datetime]'2026-11-10'
    $supportOf = {
        param([string] $Language, [string] $Version)
        if (-not $Language -or -not $Version) { return @{ Status = 'Unknown'; Ends = $null } }
        $major = if ($Language -eq 'python' -or $Language -eq 'powershell') { ($Version -replace '^v', '' -split '\.')[0..1] -join '.' } else { ($Version -replace '^[v~]', '' -split '\.')[0] }
        $key = "$Language|$major"
        if (-not $endOfSupport.ContainsKey($key)) { return @{ Status = 'Supported'; Ends = $null } }
        $ends = [datetime]$endOfSupport[$key]
        @{ Status = $(if ($ends -lt $Now) { 'Out of support' } elseif (($ends - $Now).TotalDays -le 180) { 'Ending soon' } else { 'Supported' }); Ends = $ends }
    }

    # --- Plans ------------------------------------------------------------------------------------------------------
    $hostingOf = {
        param($PlanRow)
        if (-not $PlanRow) { return 'Unknown' }
        $tier = [string](& $at $PlanRow 'sku', 'tier'); $sku = [string](& $at $PlanRow 'sku', 'name')
        if ($tier -eq 'Dynamic' -or $sku -eq 'Y1') { 'Consumption' }
        elseif ($tier -eq 'FlexConsumption' -or $sku -like 'FC*') { 'Flex Consumption' }
        elseif ($tier -eq 'ElasticPremium' -or $sku -like 'EP*') { 'Elastic Premium' }
        elseif ($tier -like 'Isolated*' -or $sku -like 'I*v2' -or $sku -like 'I[0-9]*') { 'App Service Environment' }
        else { 'Dedicated' }
    }
    $planById = @{}
    foreach ($p in $Plan) { if ($p) { $planById[(& $lower $p['id'])] = $p } }

    $findings = [System.Collections.Generic.List[object]]::new()
    $find = {
        param([string] $Severity, [string] $AppName, [string] $Pillar, [string] $Title, [string] $DetailText, [string] $Fix, [string] $Source = 'Check', [string] $ResourceId = '')
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppFinding'; Severity = $Severity; App = $AppName; Pillar = $Pillar; Finding = $Title; Detail = $DetailText; Recommendation = $Fix; Source = $Source; ResourceId = $ResourceId })
    }
    $apps = [System.Collections.Generic.List[object]]::new()
    $functions = [System.Collections.Generic.List[object]]::new()
    $settings = [System.Collections.Generic.List[object]]::new()
    $appSettings = [System.Collections.Generic.List[object]]::new()
    $slots = [System.Collections.Generic.List[object]]::new()
    $deployments = [System.Collections.Generic.List[object]]::new()
    $networks = [System.Collections.Generic.List[object]]::new()
    $backups = [System.Collections.Generic.List[object]]::new()
    $connections = [System.Collections.Generic.List[object]]::new()
    $activity = [System.Collections.Generic.List[object]]::new()
    $checks = [System.Collections.Generic.List[object]]::new()
    $recommendations = [System.Collections.Generic.List[object]]::new()
    $secretName = '(password|passwd|secret|token|apikey|api_key|connectionstring|accesskey|accountkey|privatekey|clientsecret|sas)'
    $storageByApp = @{}

    foreach ($a in $App) {
        if (-not $a) { continue }
        $id = [string]$a['id']; $key = & $lower $id; $name = [string]$a['name']
        $p = $a['properties']
        $d = if ($Detail.ContainsKey($key)) { $Detail[$key] } else { @{} }
        $web = & $at (& $bodyOf $d['Web']) 'properties'
        if (-not $web) { $web = & $at $p 'siteConfig' }
        $planRow = $planById[(& $lower (& $at $p 'serverFarmId'))]
        $hosting = if (& $at $p 'managedEnvironmentId') { 'Container Apps' } else { & $hostingOf $planRow }
        $linux = ([string]$a['kind']) -match 'linux'
        $values = $d['AppSettings']
        $settingsRead = $values -is [hashtable]
        $setting = { param([string] $Name) if ($settingsRead -and $values.ContainsKey($Name)) { $values[$Name] } else { $null } }

        # The language runtime and version: Flex reads functionAppConfig; Linux linuxFxVersion; Windows its settings.
        $worker = [string](& $setting 'FUNCTIONS_WORKER_RUNTIME')
        $flexRuntime = & $at $p 'functionAppConfig', 'runtime'
        $fx = [string](& $at $web 'linuxFxVersion')
        $language = ''; $version = ''
        if ($flexRuntime) { $language = [string]$flexRuntime['name']; $version = [string]$flexRuntime['version'] }
        elseif ($fx -match '^([A-Za-z-]+)\|(.+)$') { $language = $Matches[1]; $version = $Matches[2] }
        else {
            $language = $worker
            $version = switch -Regex ($worker) {
                '^dotnet' { [string](& $at $web 'netFrameworkVersion'); break }
                '^powershell$' { [string](& $at $web 'powerShellVersion'); break }
                '^node$' { [string](& $setting 'WEBSITE_NODE_DEFAULT_VERSION'); break }
                '^java$' { [string](& $at $web 'javaVersion'); break }
                default { '' }
            }
            if (-not $language -and (& $at $web 'powerShellVersion')) { $language = 'powershell'; $version = [string](& $at $web 'powerShellVersion') }
        }
        $language = $language.ToLowerInvariant()
        $inProcess = $worker -eq 'dotnet' -or $language -eq 'dotnet'
        $family = if ($language -like 'dotnet*') { 'dotnet' } else { $language }
        $support = & $supportOf $family $version
        $functionsVersion = [string](& $setting 'FUNCTIONS_EXTENSION_VERSION')
        if (-not $functionsVersion -and $hosting -eq 'Flex Consumption') { $functionsVersion = '~4' }

        # Functions and triggers.
        $functionsAnswer = $d['Functions']
        $fnList = @(& $itemsOf $functionsAnswer)
        $httpAnonymous = 0; $httpCount = 0
        $triggerCounts = @{}
        foreach ($f in $fnList) {
            $fp = $f['properties']
            $bindings = @(@(& $at $fp 'config', 'bindings') | Where-Object { $_ })
            $trigger = @($bindings | Where-Object { ([string]$_['type']) -like '*Trigger' }) | Select-Object -First 1
            $triggerType = if ($trigger) { ([string]$trigger['type']) -replace 'Trigger$', '' } else { 'Unknown' }
            $auth = if ($trigger -and $triggerType -eq 'http') { [string]$trigger['authLevel'] } else { '' }
            if ($triggerType -eq 'http') { $httpCount++; if ($auth -eq 'anonymous') { $httpAnonymous++ } }
            if (-not $triggerCounts.ContainsKey($triggerType)) { $triggerCounts[$triggerType] = 0 }
            $triggerCounts[$triggerType]++
            $functions.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.FunctionAppFunction'; App = $name; Function = (([string]$f['name']) -split '/')[-1]; Trigger = $triggerType
                    AuthLevel = $auth; Schedule = $(if ($trigger -and $triggerType -eq 'timer') { [string]$trigger['schedule'] } else { '' })
                    Inputs = (@($bindings | Where-Object { $_['direction'] -eq 'in' -and ([string]$_['type']) -notlike '*Trigger' } | ForEach-Object { [string]$_['type'] }) -join ', ')
                    Outputs = (@($bindings | Where-Object { $_['direction'] -eq 'out' } | ForEach-Object { [string]$_['type'] }) -join ', ')
                    Connection = (@($bindings | ForEach-Object { [string]$_['connection'] } | Where-Object { $_ } | Select-Object -Unique) -join ', ')
                    Disabled = [string](& $at $fp 'isDisabled') -eq 'True'; Language = [string](& $at $fp 'language'); InvokeUrl = [string](& $at $fp 'invoke_url_template')
                    ResourceId = [string]$f['id']
                })
        }
        $triggers = (@($triggerCounts.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', ')

        # App settings: names and kinds only.
        $plainSecrets = [System.Collections.Generic.List[string]]::new()
        $kvRefs = 0
        if ($settingsRead) {
            foreach ($n in @($values.Keys | Sort-Object)) {
                $v = [string]$values[$n]
                $kind = if ($v -match '^@Microsoft\.KeyVault\(') { 'Key Vault reference' }
                elseif ($n -match '__(accountName|serviceUri|fullyQualifiedNamespace|credential|clientId|blobServiceUri|queueServiceUri)$') { 'Identity-based connection' }
                elseif ($v -match '(?i)(AccountKey=|SharedAccessKey=|SharedAccessSignature=|Password=|sig=)') { 'Key or connection string' }
                elseif ($n -match '^(FUNCTIONS_|WEBSITE_|AzureWebJobs|APPINSIGHTS_|APPLICATIONINSIGHTS_|SCM_|ENABLE_ORYX|XDG_)') { 'Platform' }
                else { 'Plain value' }
                if ($kind -eq 'Key Vault reference') { $kvRefs++ }
                if (($kind -eq 'Key or connection string' -and $n -notmatch '^AzureWebJobsStorage$|^WEBSITE_CONTENTAZUREFILECONNECTIONSTRING$') -or ($kind -eq 'Plain value' -and $n -match $secretName -and $v)) { $plainSecrets.Add($n) }
                $appSettings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppAppSetting'; App = $name; Setting = $n; Kind = $kind; HasValue = [bool]$v })
                # Dependencies named in settings: the vault of a reference, the account of a connection - names only.
                if ($kind -eq 'Key Vault reference' -and $v -match 'https://([^.]+)\.vault\.azure\.net') { $connections.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppConnection'; App = $name; Source = 'App setting'; Name = $n; Target = $Matches[1]; TargetType = 'Key Vault'; Auth = 'Managed identity (Key Vault reference)'; ResourceId = '' }) }
                elseif ($v -match '(?i)AccountName=([a-z0-9]+);') { $connections.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppConnection'; App = $name; Source = 'App setting'; Name = $n; Target = $Matches[1]; TargetType = 'Storage account'; Auth = 'Account key'; ResourceId = '' }) }
                elseif ($n -match '__accountName$' -and $v) { $connections.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppConnection'; App = $name; Source = 'App setting'; Name = $n; Target = $v; TargetType = 'Storage account'; Auth = 'Managed identity'; ResourceId = '' }) }
                elseif ($n -match '__fullyQualifiedNamespace$' -and $v) { $connections.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppConnection'; App = $name; Source = 'App setting'; Name = $n; Target = ($v -split '\.')[0]; TargetType = 'Service Bus / Event Hubs'; Auth = 'Managed identity'; ResourceId = '' }) }
                elseif ($v -match '(?i)Endpoint=sb://([^.]+)\.') { $connections.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppConnection'; App = $name; Source = 'App setting'; Name = $n; Target = $Matches[1]; TargetType = 'Service Bus / Event Hubs'; Auth = 'Shared access key'; ResourceId = '' }) }
                elseif ($v -match '(?i)AccountEndpoint=https://([^.]+)\.documents') { $connections.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppConnection'; App = $name; Source = 'App setting'; Name = $n; Target = $Matches[1]; TargetType = 'Cosmos DB'; Auth = 'Account key'; ResourceId = '' }) }
            }
            $webJobs = [string](& $setting 'AzureWebJobsStorage')
            $account = if ($webJobs -match '(?i)AccountName=([a-z0-9]+)') { $Matches[1] } else { [string](& $setting 'AzureWebJobsStorage__accountName') }
            if ($account) { $storageByApp[$name] = $account.ToLowerInvariant() }
        }
        $identityStorage = if (-not $settingsRead) { $null } else { [bool](& $setting 'AzureWebJobsStorage__accountName') -or [bool](& $setting 'AzureWebJobsStorage__blobServiceUri') -or ([string](& $setting 'AzureWebJobsStorage') -and [string](& $setting 'AzureWebJobsStorage') -notmatch 'AccountKey=') }
        $appInsights = if ($settingsRead) { [bool](& $setting 'APPLICATIONINSIGHTS_CONNECTION_STRING') -or [bool](& $setting 'APPINSIGHTS_INSTRUMENTATIONKEY') } else { $null }
        $runFromPackage = if ($settingsRead) { [bool](& $setting 'WEBSITE_RUN_FROM_PACKAGE') -or $linux -or $hosting -eq 'Flex Consumption' } else { $null }

        # Service Connector connections.
        foreach ($l in @(& $itemsOf $d['Linkers'])) {
            $lp = $l['properties']
            $target = [string](& $at $lp 'targetService', 'id')
            $connections.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.FunctionAppConnection'; App = $name; Source = 'Service Connector'; Name = [string]$l['name']
                    Target = $(if ($target) { ($target -split '/')[-1] } else { [string](& $at $lp 'targetService', 'type') })
                    TargetType = $(if ($target -match '/providers/([^/]+/[^/]+)/') { $Matches[1] } else { [string](& $at $lp 'targetService', 'type') })
                    Auth = [string](& $at $lp 'authInfo', 'authType'); ResourceId = [string]$l['id']
                })
        }

        # Networking.
        $restrictions = @(@(& $at $web 'ipSecurityRestrictions') | Where-Object { $_ })
        $scmRestrictions = @(@(& $at $web 'scmIpSecurityRestrictions') | Where-Object { $_ })
        $allowRules = @($restrictions | Where-Object { [string]$_['action'] -eq 'Allow' -and [string]$_['ipAddress'] -ne 'Any' })
        $defaultAction = [string](& $at $web 'ipSecurityRestrictionsDefaultAction')
        $restricted = $allowRules.Count -gt 0 -or $defaultAction -eq 'Deny'
        $endpoints = @($PrivateEndpoint | Where-Object { $_ -and ([string]$_['target']) -eq $key })
        $public = [string](& $at $p 'publicNetworkAccess')
        $network = if ($public -eq 'Disabled') { 'Private' } elseif ($endpoints.Count -and $restricted) { 'Private + restricted' } elseif ($restricted) { 'Restricted' } elseif ($endpoints.Count) { 'Public + private endpoint' } else { 'Public' }
        $subnet = [string](& $at $p 'virtualNetworkSubnetId')
        $cors = @(@(& $at $web 'cors', 'allowedOrigins') | Where-Object { $_ })
        $networks.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.FunctionAppNetwork'; App = $name; Inbound = $network; PublicNetworkAccess = $(if ($public) { $public } else { 'Enabled' })
                AccessRules = $allowRules.Count; DefaultAction = $(if ($defaultAction) { $defaultAction } elseif ($restricted) { 'Deny' } else { 'Allow' })
                ScmRules = @($scmRestrictions | Where-Object { [string]$_['action'] -eq 'Allow' -and [string]$_['ipAddress'] -ne 'Any' }).Count; ScmUsesMainRules = [string](& $at $web 'scmIpSecurityRestrictionsUseMain') -eq 'True'
                PrivateEndpoints = $endpoints.Count; VnetIntegration = $(if ($subnet) { ($subnet -split '/')[-3] + '/' + ($subnet -split '/')[-1] } else { '' }); RouteAll = [string](& $at $web 'vnetRouteAllEnabled') -eq 'True' -or [string](& $at $p 'vnetRouteAllEnabled') -eq 'True'
                OutboundIps = @(([string](& $at $p 'possibleOutboundIpAddresses')) -split ',' | Where-Object { $_ }).Count; Cors = $cors -join ', '
                ClientCertificates = [string](& $at $p 'clientCertMode')
            })

        # Deployment center and deployments.
        $sc = & $at (& $bodyOf $d['SourceControl']) 'properties'
        $scmType = [string](& $at $web 'scmType')
        $deployList = @(& $itemsOf $d['Deployments'] | Sort-Object -Property { & $when (& $at $_ 'properties', 'end_time') } -Descending)
        foreach ($dep in @($deployList | Select-Object -First 10)) {
            $dp = $dep['properties']
            $deployments.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.FunctionAppDeployment'; App = $name; Time = (& $when $dp['end_time']); Status = $(switch ([string]$dp['status']) { '4' { 'Succeeded' } '3' { 'Failed' } '1' { 'Building' } '2' { 'Deploying' } default { [string]$dp['status'] } })
                    Author = [string]$dp['author']; Deployer = [string]$dp['deployer']; Message = (([string]$dp['message']) -split "`n")[0]; Active = [string]$dp['active'] -eq 'True'
                })
        }
        $lastDeploy = @($deployList | ForEach-Object { & $when (& $at $_ 'properties', 'end_time') } | Where-Object { $_ }) | Select-Object -First 1
        $source = if ($sc -and (& $at $sc 'isGitHubAction')) { 'GitHub Actions' } elseif ($sc -and (& $at $sc 'repoUrl')) { "$(if ($scmType -and $scmType -ne 'None') { $scmType } else { 'External Git' })" } elseif ($scmType -and $scmType -ne 'None') { $scmType } elseif ($deployList.Count) { 'Zip / package deploy' } else { 'None' }
        $scmBasic = [string](& $at (& $bodyOf $d['ScmBasic']) 'properties', 'allow')
        $ftpBasic = [string](& $at (& $bodyOf $d['FtpBasic']) 'properties', 'allow')

        # Slots.
        $mySlots = @($Slot | Where-Object { $_ -and (& $lower $_['id']).StartsWith("$key/slots/") })
        foreach ($s in $mySlots) {
            $sp = $s['properties']
            $slots.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.FunctionAppSlot'; App = $name; Slot = (([string]$s['name']) -split '/')[-1]; State = [string]$sp['state']; HostName = [string]$sp['defaultHostName']
                    HttpsOnly = [string]$sp['httpsOnly'] -eq 'True'; LastModified = (& $when $sp['lastModifiedTimeUtc']); ResourceId = [string]$s['id']
                })
        }

        # Backups.
        $backupSupported = $hosting -in 'Dedicated', 'App Service Environment' -and ([string](& $at $planRow 'sku', 'tier')) -notin 'Free', 'Shared', 'Basic'
        $backupList = @(& $itemsOf $d['Backups'] | Sort-Object -Property { & $when (& $at $_ 'properties', 'created') } -Descending)
        $lastBackup = $backupList | Select-Object -First 1
        $backups.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.FunctionAppBackup'; App = $name; Hosting = $hosting; Supported = $backupSupported; Backups = $(if (& $readOk $d['Backups']) { $backupList.Count } else { $null })
                LastBackup = $(if ($lastBackup) { & $when (& $at $lastBackup 'properties', 'created') } else { $null }); LastStatus = $(if ($lastBackup) { [string](& $at $lastBackup 'properties', 'status') } else { '' })
                Note = $(if (-not $backupSupported) { "Not available on $hosting - redeploy from source control, and keep state in storage you back up." } elseif (-not $backupList.Count) { 'No backup taken.' } else { '' })
            })

        # Activity Log: one row per operation (its last event), what kind of change it was.
        $events = @(& $itemsOf $d['Activity'])
        $byOperation = @($events | Group-Object -Property { [string](& $at $_ 'correlationId') + '|' + [string](& $at $_ 'operationName', 'value') })
        $kindCounts = @{}
        foreach ($group in $byOperation) {
            $last = @($group.Group | Sort-Object -Property { & $when (& $at $_ 'eventTimestamp') }) | Select-Object -Last 1
            $op = [string](& $at $last 'operationName', 'value')
            if ($op -match '/read$') { continue }
            $kind = switch -Regex ($op) {
                '/slotsswap/action|/slotsswap$' { 'Slot swap'; break }
                '/restart/action' { 'Restart'; break }
                '/stop/action' { 'Stop'; break }
                '/start/action' { 'Start'; break }
                '(config/(appsettings|connectionstrings|publishingcredentials)/list/action|listsecrets|listkeys|/publishxml/action)' { 'Secrets or keys read'; break }
                '/config/write' { 'Configuration change'; break }
                '(deployments/write|syncfunctiontriggers|/extensions/|/zipdeploy|/sourcecontrols/write)' { 'Deployment'; break }
                '/delete$' { 'Delete'; break }
                '/write$' { 'Change'; break }
                default { 'Other' }
            }
            if (-not $kindCounts.ContainsKey($kind)) { $kindCounts[$kind] = 0 }
            $kindCounts[$kind]++
            $activity.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.FunctionAppActivity'; App = $name; Time = (& $when (& $at $last 'eventTimestamp')); Kind = $kind
                    Operation = $(if (& $at $last 'operationName', 'localizedValue') { [string](& $at $last 'operationName', 'localizedValue') } else { $op })
                    Status = [string](& $at $last 'status', 'value'); Caller = [string](& $at $last 'caller'); Category = [string](& $at $last 'category', 'value')
                    CorrelationId = [string](& $at $last 'correlationId')
                })
        }
        $changes = @($activity | Where-Object { $_.App -eq $name }).Count
        $failedOps = @($activity | Where-Object { $_.App -eq $name -and $_.Status -eq 'Failed' }).Count

        # Usage over the period.
        $requests = & $total $id 'Http' 'Requests'
        $http5xx = & $total $id 'Http' 'Http5xx'
        $http4xx = & $total $id 'Http' 'Http4xx'
        $executions = & $total $id 'Exec' 'FunctionExecutionCount'
        $units = & $total $id 'Exec' 'FunctionExecutionUnits'
        $gbSeconds = if ($null -ne $units) { $units / 1024.0 / 1000.0 } else { $null }
        $latency = & $average $id 'Latency' 'HttpResponseTime'
        $memoryAvg = & $average $id 'Memory' 'MemoryWorkingSet'
        $memoryMax = & $maximum $id 'Memory' 'MemoryWorkingSet'
        $scale = 720.0 / [Math]::Max(1.0, $Hours)
        $cost = if ($hosting -eq 'Consumption' -and $null -ne $gbSeconds) { & $round (($gbSeconds * $scale * 0.000016) + ((& { if ($null -ne $executions) { $executions } else { 0 } }) * $scale / 1000000.0 * 0.20)) 2 } else { $null }
        $errorRate = if ($requests) { & $round (100.0 * $http5xx / $requests) 2 } else { $null }
        $health = [string](& $at (& $bodyOf $d['Health']) 'properties', 'availabilityState')
        $locks = @(& $itemsOf $d['Locks'])
        $diagnostics = @(& $itemsOf $d['Diagnostics'])
        $tags = $a['tags']
        $tagOf = { param([string[]] $Names) if ($tags -is [System.Collections.IDictionary]) { foreach ($k in $tags.Keys) { if ([string]$k -in $Names) { return [string]$tags[$k] } } }; '' }
        $environment = & $tagOf @('Environment', 'environment', 'env', 'Env')
        $production = $environment -match '^(prod|production|prd|live)$' -or $name -match '(^|-)(prod|prd)(-|$)'
        $state = [string](& $at $p 'state')
        $alwaysOn = [string](& $at $web 'alwaysOn') -eq 'True'
        $auth = & $at (& $bodyOf $d['Auth']) 'properties', 'platform', 'enabled'

        # --- Well-Architected checks: Pass, Fail or N/A, each failure a finding -----------------------------------
        $check = {
            param([string] $Pillar, [string] $Title, $Result, [string] $Severity, [string] $Why, [string] $Fix)
            $status = if ($null -eq $Result) { 'N/A' } elseif ($Result) { 'Pass' } else { 'Fail' }
            $checks.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppCheck'; App = $name; Pillar = $Pillar; Check = $Title; Status = $status; Severity = $(if ($status -eq 'Fail') { $Severity } else { '' }); Detail = $Why; Recommendation = $Fix })
            if ($status -eq 'Fail') { & $find $Severity $name $Pillar $Title $Why $Fix 'Well-Architected' $id }
        }
        $dedicated = $hosting -in 'Dedicated', 'App Service Environment'
        $premium = $hosting -eq 'Elastic Premium'
        $minTls = [string](& $at $web 'minTlsVersion')
        # Security
        & $check 'Security' 'HTTPS only' ([string](& $at $p 'httpsOnly') -eq 'True') 'High' 'HTTP requests are served without redirecting to HTTPS.' 'Turn on HTTPS Only (Configuration > General settings).'
        & $check 'Security' 'Minimum TLS 1.2' $(if ($minTls) { $minTls -in '1.2', '1.3' } else { $null }) 'High' "Minimum TLS version is $minTls." 'Set the minimum inbound TLS version to 1.2 (or 1.3).'
        & $check 'Security' 'FTP off (or FTPS only)' $(if (& $at $web 'ftpsState') { [string](& $at $web 'ftpsState') -in 'Disabled', 'FtpsOnly' } else { $null }) 'Medium' "FTP state is $([string](& $at $web 'ftpsState'))." 'Set FTP state to Disabled - deploy from CI/CD or with zip deploy.'
        & $check 'Security' 'Basic publishing credentials off' $(if ($scmBasic -or $ftpBasic) { $scmBasic -ne 'True' -and $ftpBasic -ne 'True' } else { $null }) 'Medium' "Basic authentication: SCM $(if ($scmBasic -eq 'True') { 'allowed' } else { 'off' }), FTP $(if ($ftpBasic -eq 'True') { 'allowed' } else { 'off' })." 'Turn off SCM and FTP basic authentication; deploy with Entra ID (OIDC from GitHub Actions or Azure Pipelines).'
        & $check 'Security' 'Managed identity' ([string](& $at $a 'identity', 'type') -and [string](& $at $a 'identity', 'type') -ne 'None') 'Medium' 'The app has no managed identity, so it signs in to other services with keys.' 'Turn on a system-assigned (or user-assigned) identity, and use it for storage, Key Vault and messaging.'
        & $check 'Security' 'No secrets in plain app settings' $(if ($settingsRead) { -not $plainSecrets.Count } else { $null }) 'High' "Settings holding keys or secret-looking values: $($plainSecrets -join ', ')." 'Move them to Key Vault (@Microsoft.KeyVault references) or use identity-based connections - then rotate them.'
        & $check 'Security' 'Identity-based storage connection' $identityStorage 'Medium' 'AzureWebJobsStorage uses the storage account key.' 'Use AzureWebJobsStorage__accountName with the app''s identity (Storage Blob Data Owner, Queue Data Contributor), and remove the key.'
        & $check 'Security' 'Inbound access restricted' $(if ($httpCount -or -not ($functionsAnswer -and (& $readOk $functionsAnswer))) { $network -ne 'Public' } else { $null }) 'Medium' 'The app accepts requests from any network.' 'Add access restrictions (or a private endpoint, and turn public access off); front public HTTP APIs with API Management or Front Door.'
        & $check 'Security' 'SCM site restricted' $(if ($network -ne 'Public') { [string](& $at $web 'scmIpSecurityRestrictionsUseMain') -eq 'True' -or @($scmRestrictions | Where-Object { [string]$_['action'] -eq 'Allow' -and [string]$_['ipAddress'] -ne 'Any' }).Count -gt 0 -or $public -eq 'Disabled' } else { $null }) 'Low' 'The deployment (SCM / Kudu) site is open while the app is restricted.' 'Apply the same rules to the SCM site, or add its own.'
        & $check 'Security' 'Remote debugging off' $(if ($web) { [string](& $at $web 'remoteDebuggingEnabled') -ne 'True' } else { $null }) 'Medium' 'Remote debugging is on.' 'Turn remote debugging off when you''re not debugging.'
        & $check 'Security' 'CORS not open to every origin' $(if ($cors.Count) { $cors -notcontains '*' } else { $null }) 'Medium' 'CORS allows every origin (*).' 'List the origins that need the API.'
        & $check 'Security' 'HTTP functions require a key or sign-in' $(if ($httpCount) { -not $httpAnonymous -or [string]$auth -eq 'True' } else { $null }) 'Medium' "$httpAnonymous HTTP function(s) are anonymous and the app has no authentication." 'Use function or admin keys, App Service authentication (Entra ID), or API Management in front.'
        # Reliability
        & $check 'Reliability' 'App running' ($state -ne 'Stopped') 'High' 'The app is stopped.' 'Start it, or delete it if it is no longer needed.'
        & $check 'Reliability' 'Functions runtime 4.x' $(if ($functionsVersion) { $functionsVersion -match '^~?4' } else { $null }) 'High' "FUNCTIONS_EXTENSION_VERSION is $functionsVersion - only 4.x is supported." 'Migrate to Functions runtime 4.x.'
        & $check 'Reliability' 'Language runtime supported' $(if ($support.Status -eq 'Unknown') { $null } else { $support.Status -eq 'Supported' }) $(if ($support.Status -eq 'Out of support') { 'High' } else { 'Medium' }) "$language $version - $($support.Status)$(if ($support.Ends) { " ($($support.Ends.ToString('yyyy-MM-dd')))" })." 'Upgrade to a supported version of the language (and test the app on it).'
        & $check 'Reliability' 'Zone redundant' $(if ($dedicated -or $premium -or $hosting -eq 'Flex Consumption') { [string](& $at $planRow 'properties', 'zoneRedundant') -eq 'True' } else { $null }) 'Medium' "The plan $([string](& $at $planRow 'name')) isn't zone redundant." 'Use a zone-redundant plan (Elastic Premium, Flex Consumption or Premium v3 with 3+ instances) for production.'
        & $check 'Reliability' 'Health check' $(if ($dedicated -or $premium) { [bool](& $at $web 'healthCheckPath') } else { $null }) 'Low' 'No health check path: unhealthy instances keep getting traffic.' 'Set a health check path (an HTTP function that checks dependencies).'
        & $check 'Reliability' 'Always On' $(if ($dedicated) { $alwaysOn } else { $null }) 'Medium' 'Always On is off on a dedicated plan: timer, queue and other triggers stop when the app idles.' 'Turn Always On on.'
        & $check 'Reliability' 'Deployment slots' $(if (($dedicated -or $premium) -and $production) { $mySlots.Count -gt 0 } else { $null }) 'Low' 'A production app with no staging slot deploys straight to production.' 'Deploy to a staging slot, warm it up, then swap.'
        & $check 'Reliability' 'Backups' $(if ($backupSupported) { $backupList.Count -gt 0 } else { $null }) 'Low' 'No backup of the app on a plan that supports them.' 'Configure backups - or make sure source control and infrastructure as code can rebuild it.'
        & $check 'Reliability' 'Error rate under 5%' $(if ($requests -ge 100) { $errorRate -lt 5 } else { $null }) 'High' "$errorRate% of $([long]$requests) requests failed (5xx) over the period." 'Find the failing functions in Application Insights (failures, exceptions) and fix the cause.'
        # Operational excellence
        & $check 'Operational Excellence' 'Application Insights' $appInsights 'Medium' 'No Application Insights connection: no traces, failures or live metrics.' 'Connect Application Insights (APPLICATIONINSIGHTS_CONNECTION_STRING), ideally with Entra ID authentication.'
        & $check 'Operational Excellence' 'Diagnostic settings' $(if (& $readOk $d['Diagnostics']) { $diagnostics.Count -gt 0 } else { $null }) 'Low' 'FunctionAppLogs aren''t sent to a Log Analytics workspace.' 'Add a diagnostic setting sending FunctionAppLogs to Log Analytics.'
        & $check 'Operational Excellence' 'Deployed by CI/CD' ($source -ne 'None') 'Low' 'No deployment source and no deployment record: changes may be made by hand.' 'Deploy from GitHub Actions or Azure Pipelines (Deployment Center).'
        & $check 'Operational Excellence' 'Run from package' $runFromPackage 'Low' 'The app isn''t run from a package: deployments can leave files half-updated.' 'Set WEBSITE_RUN_FROM_PACKAGE=1 (zip deploy does it).'
        & $check 'Operational Excellence' '.NET isolated worker model' $(if ($family -eq 'dotnet') { -not $inProcess } else { $null }) $(if ($Now -ge $inProcessEnd) { 'High' } else { 'Medium' }) "The app uses the .NET in-process model, whose support ends on $($inProcessEnd.ToString('yyyy-MM-dd'))." 'Migrate to the isolated worker model (dotnet-isolated).'
        & $check 'Operational Excellence' 'Resource lock' $(if ($production -and (& $readOk $d['Locks'])) { $locks.Count -gt 0 } else { $null }) 'Low' 'A production app with no delete lock.' 'Add a CanNotDelete lock (on the app or its resource group).'
        # Cost
        $idle = ($null -ne $executions -or $null -ne $requests) -and -not $executions -and -not $requests
        & $check 'Cost Optimization' 'In use' $(if ($null -eq $executions -and $null -eq $requests) { $null } else { -not $idle }) $(if ($dedicated -or $premium) { 'Medium' } else { 'Low' }) "No execution and no request in the last $([int]$Hours) hours$(if ($dedicated -or $premium) { ' - and the plan is paid for whether it runs or not' })." 'Delete the app if nothing needs it (check its triggers first), or move it to a consumption plan.'
        # Performance
        & $check 'Performance Efficiency' '64-bit worker' $(if (-not $linux -and $web -and ($dedicated -or $premium)) { [string](& $at $web 'use32BitWorkerProcess') -ne 'True' } else { $null }) 'Low' 'The app runs as a 32-bit process (2 GB memory ceiling).' 'Switch the platform to 64-bit.'
        & $check 'Performance Efficiency' 'HTTP/2' $(if ($web -and $httpCount) { [string](& $at $web 'http20Enabled') -eq 'True' } else { $null }) 'Low' 'HTTP/2 is off.' 'Turn HTTP/2 on (Configuration > General settings).'
        & $check 'Performance Efficiency' 'Response time under 1 second' $(if ($null -ne $latency -and $requests -ge 100) { $latency -lt 1 } else { $null }) 'Medium' "Average response time $(& $round ($latency * 1000) 0) ms." 'Profile the slow functions (Application Insights performance), cache, and check cold starts (Premium always-ready instances).'
        & $check 'Performance Efficiency' 'Memory headroom' $(if ($hosting -eq 'Consumption' -and $null -ne $memoryMax) { $memoryMax -lt 1.2GB } else { $null }) 'Medium' "Peak memory $(& $round ($memoryMax / 1MB) 0) MB of the 1.5 GB a Consumption instance has." 'Reduce memory use, or move to Flex Consumption or Elastic Premium with more memory.'

        if ($failedOps) { & $find 'Info' $name 'Operational Excellence' 'Failed management operations' "$failedOps operation(s) on the app failed in the last $ActivityDays days." 'Open the Activity Log tab to see who tried what.' 'Activity Log' $id }
        $restarts = if ($kindCounts.ContainsKey('Restart')) { $kindCounts['Restart'] } else { 0 }
        if ($restarts -ge 4) { & $find 'Low' $name 'Reliability' 'Frequent restarts' "$restarts restart(s) in $ActivityDays days." 'Find why it''s restarted (health, memory, deployments) rather than restarting it by hand.' 'Activity Log' $id }
        if ($kindCounts.ContainsKey('Secrets or keys read')) { & $find 'Info' $name 'Security' 'App settings or keys read' "Settings, keys or publishing profiles were read $($kindCounts['Secrets or keys read']) time(s) in $ActivityDays days." 'Check the callers in the Activity Log tab are expected.' 'Activity Log' $id }

        # The configuration, setting by setting.
        $add = { param([string] $Area, [string] $Label, $Value) if ($null -ne $Value -and "$Value" -ne '') { $settings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppSettingView'; App = $name; Area = $Area; Setting = $Label; Value = [string]$Value }) } }
        & $add 'General' 'State' $state; & $add 'General' 'Kind' $a['kind']; & $add 'General' 'Hosting' $hosting; & $add 'General' 'Plan' (& $at $planRow 'name'); & $add 'General' 'SKU' (& $at $planRow 'sku', 'name')
        & $add 'General' 'Default host name' (& $at $p 'defaultHostName'); & $add 'General' 'Last modified (UTC)' (& $at $p 'lastModifiedTimeUtc')
        & $add 'Runtime' 'Functions runtime' $functionsVersion; & $add 'Runtime' 'Worker runtime' $worker; & $add 'Runtime' 'Language' "$language $version"; & $add 'Runtime' 'Linux FX version' $fx
        & $add 'Runtime' '.NET version' (& $at $web 'netFrameworkVersion'); & $add 'Runtime' 'PowerShell version' (& $at $web 'powerShellVersion'); & $add 'Runtime' 'Java version' (& $at $web 'javaVersion'); & $add 'Runtime' '32-bit worker' (& $at $web 'use32BitWorkerProcess')
        & $add 'Security' 'HTTPS only' (& $at $p 'httpsOnly'); & $add 'Security' 'Minimum TLS' $minTls; & $add 'Security' 'Minimum TLS cipher suite' (& $at $web 'minTlsCipherSuite'); & $add 'Security' 'FTP state' (& $at $web 'ftpsState')
        & $add 'Security' 'SCM basic auth' $scmBasic; & $add 'Security' 'FTP basic auth' $ftpBasic; & $add 'Security' 'Managed identity' (& $at $a 'identity', 'type'); & $add 'Security' 'Remote debugging' (& $at $web 'remoteDebuggingEnabled')
        & $add 'Security' 'App Service authentication' $auth; & $add 'Security' 'Client certificates' (& $at $p 'clientCertMode'); & $add 'Security' 'Key Vault references' $(if ($settingsRead) { $kvRefs } else { $null })
        & $add 'Networking' 'Public network access' $(if ($public) { $public } else { 'Enabled' }); & $add 'Networking' 'Inbound' $network; & $add 'Networking' 'VNet integration' $subnet; & $add 'Networking' 'Route all traffic through the VNet' (& $at $web 'vnetRouteAllEnabled'); & $add 'Networking' 'CORS' ($cors -join ', ')
        & $add 'Scale' 'Always On' (& $at $web 'alwaysOn'); & $add 'Scale' 'Scale-out limit' (& $at $web 'functionAppScaleLimit'); & $add 'Scale' 'Always-ready instances' (& $at $web 'minimumElasticInstanceCount'); & $add 'Scale' 'Pre-warmed instances' (& $at $web 'preWarmedInstanceCount')
        & $add 'Scale' 'Plan maximum burst' (& $at $planRow 'properties', 'maximumElasticWorkerCount'); & $add 'Scale' 'Flex maximum instances' (& $at $p 'functionAppConfig', 'scaleAndConcurrency', 'maximumInstanceCount'); & $add 'Scale' 'Flex instance memory (MB)' (& $at $p 'functionAppConfig', 'scaleAndConcurrency', 'instanceMemoryMB')
        & $add 'Monitoring' 'Application Insights' $appInsights; & $add 'Monitoring' 'Diagnostic settings' $(if (& $readOk $d['Diagnostics']) { $diagnostics.Count } else { $null }); & $add 'Monitoring' 'HTTP logging' (& $at $web 'httpLoggingEnabled'); & $add 'Monitoring' 'Health check path' (& $at $web 'healthCheckPath')
        & $add 'Deployment' 'Source' $source; & $add 'Deployment' 'Repository' (& $at $sc 'repoUrl'); & $add 'Deployment' 'Branch' (& $at $sc 'branch'); & $add 'Deployment' 'Run from package' $runFromPackage; & $add 'Deployment' 'Last deployment (UTC)' $lastDeploy

        $mine = @($findings | Where-Object { $_.App -eq $name })
        $myChecks = @($checks | Where-Object { $_.App -eq $name -and $_.Status -ne 'N/A' })
        $passed = @($myChecks | Where-Object { $_.Status -eq 'Pass' }).Count
        $apps.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.FunctionApp'; App = $name; Score = $(if ($myChecks.Count) { [int][Math]::Round(100.0 * $passed / $myChecks.Count) } else { $null }); State = $state
                Health = $(if ($health) { $health } else { 'Unknown' }); Hosting = $hosting; Plan = [string](& $at $planRow 'name'); Sku = [string](& $at $planRow 'sku', 'name'); Os = $(if ($linux) { 'Linux' } else { 'Windows' })
                Runtime = "$language $version".Trim(); RuntimeSupport = $support.Status; RuntimeEnds = $support.Ends; FunctionsVersion = $functionsVersion; Model = $(if ($family -eq 'dotnet') { if ($inProcess) { 'In-process' } else { 'Isolated' } } else { '' })
                Functions = $(if (& $readOk $functionsAnswer) { $fnList.Count } else { $null }); Triggers = $triggers
                Executions = $(if ($null -ne $executions) { [long]$executions } else { $null }); GbSeconds = (& $round $gbSeconds 1); Requests = $(if ($null -ne $requests) { [long]$requests } else { $null })
                Http5xx = $(if ($null -ne $http5xx) { [long]$http5xx } else { $null }); Http4xx = $(if ($null -ne $http4xx) { [long]$http4xx } else { $null }); ErrorRate = $errorRate
                AvgResponseMs = $(if ($null -ne $latency) { & $round ($latency * 1000) 0 } else { $null }); MemoryAvgMB = $(if ($null -ne $memoryAvg) { & $round ($memoryAvg / 1MB) 0 } else { $null }); MemoryMaxMB = $(if ($null -ne $memoryMax) { & $round ($memoryMax / 1MB) 0 } else { $null })
                EstimatedMonthlyUsd = $cost; Idle = $idle
                Slots = $mySlots.Count; Deployment = $source; LastDeployment = $lastDeploy; Inbound = $network; PrivateEndpoints = $endpoints.Count; VnetIntegration = [bool]$subnet
                Identity = [string](& $at $a 'identity', 'type'); AppInsights = $appInsights; Backups = $(if ($backupSupported) { $backupList.Count } else { $null }); Connections = @($connections | Where-Object { $_.App -eq $name }).Count
                Changes = $changes; FailedOperations = $failedOps; SettingsRead = $settingsRead
                Findings = $mine.Count; High = @($mine | Where-Object { $_.Severity -eq 'High' }).Count
                Owner = (& $tagOf @('Owner', 'owner', 'CreatedBy', 'Contact')); Environment = $environment; CostCenter = (& $tagOf @('CostCenter', 'costcenter', 'Cost Center', 'BillingCode'))
                Subscription = (& $subName $a['subscriptionId']); ResourceGroup = [string]$a['resourceGroup']; Location = [string]$a['location']; ResourceId = $id
            })
    }

    # --- A storage account shared by several apps: their hosts compete for its leases and queues ---------------
    foreach ($group in @($storageByApp.GetEnumerator() | Group-Object -Property Value | Where-Object Count -GT 1)) {
        foreach ($entry in $group.Group) { & $find 'Low' $entry.Key 'Reliability' 'Storage account shared with other apps' "AzureWebJobsStorage ($($group.Name)) is shared with $(@($group.Group | Where-Object Key -NE $entry.Key | ForEach-Object Key) -join ', ')." 'Give each app its own storage account - shared ones mix host keys, leases and scaling.' 'App settings' }
    }

    # --- Plans ------------------------------------------------------------------------------------------------------
    $planRows = [System.Collections.Generic.List[object]]::new()
    $appPlanIds = @($App | Where-Object { $_ } | ForEach-Object { & $lower (& $at $_ 'properties', 'serverFarmId') } | Select-Object -Unique)
    foreach ($planId in $appPlanIds) {
        $pr = $planById[$planId]
        if (-not $pr) { continue }
        $hosting = & $hostingOf $pr
        $onPlan = @($apps | Where-Object { $_.Plan -eq [string]$pr['name'] -and $_.ResourceId -like "/subscriptions/$($pr['subscriptionId'])/*" })
        $cpuMax = & $maximum ([string]$pr['id']) 'Plan' 'CpuPercentage'; $cpuAvg = & $average ([string]$pr['id']) 'Plan' 'CpuPercentage'; $memMax = & $maximum ([string]$pr['id']) 'Plan' 'MemoryPercentage'
        $planRows.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.FunctionAppPlan'; Plan = [string]$pr['name']; Hosting = $hosting; Sku = [string](& $at $pr 'sku', 'name'); Tier = [string](& $at $pr 'sku', 'tier')
                Os = $(if ([string](& $at $pr 'properties', 'reserved') -eq 'True') { 'Linux' } else { 'Windows' }); Instances = (& $at $pr 'sku', 'capacity'); MaximumBurst = (& $at $pr 'properties', 'maximumElasticWorkerCount')
                ZoneRedundant = [string](& $at $pr 'properties', 'zoneRedundant') -eq 'True'; Apps = (& $at $pr 'properties', 'numberOfSites'); FunctionApps = ($onPlan.App -join ', ')
                CpuAvg = (& $round $cpuAvg 1); CpuMax = (& $round $cpuMax 1); MemoryMax = (& $round $memMax 1)
                Subscription = (& $subName $pr['subscriptionId']); ResourceGroup = [string]$pr['resourceGroup']; Location = [string]$pr['location']; ResourceId = [string]$pr['id']
            })
        if ($hosting -in 'Dedicated', 'Elastic Premium' -and $null -ne $cpuMax -and $cpuMax -lt 20) { & $find 'Low' ([string]$pr['name']) 'Cost Optimization' 'Plan over-provisioned' "CPU peaked at $(& $round $cpuMax 1)% over the period." 'Scale the plan down (fewer or smaller instances), or move light apps to Consumption / Flex Consumption.' 'Metrics' ([string]$pr['id']) }
        if ($hosting -in 'Dedicated', 'Elastic Premium' -and $null -ne $cpuMax -and $cpuMax -ge 90) { & $find 'Medium' ([string]$pr['name']) 'Performance Efficiency' 'Plan running hot' "CPU reached $(& $round $cpuMax 1)% over the period." 'Scale out (more instances or a larger burst), or up to a larger SKU.' 'Metrics' ([string]$pr['id']) }
    }

    # --- PSRule, Advisor, Defender -------------------------------------------------------------------------------
    $nameById = @{}; foreach ($x in $apps) { $nameById[(& $lower $x.ResourceId)] = $x.App }
    foreach ($x in $planRows) { $nameById[(& $lower $x.ResourceId)] = $x.Plan }
    $ruleResults = @($PSRule | Where-Object { $_ -and $nameById.ContainsKey((& $lower $_.ResourceId)) })
    foreach ($r in @($ruleResults | Where-Object { $_.Outcome -eq 'Fail' })) {
        & $find $(if ($r.Severity -match 'Critical|High|Important') { 'Medium' } else { 'Low' }) $nameById[(& $lower $r.ResourceId)] $r.Pillar "PSRule: $($r.RuleName)" $(if ($r.Reason) { $r.Reason } else { $r.Title }) $r.Recommendation 'PSRule' $r.ResourceId
    }
    foreach ($row in $Advisor) {
        if (-not $row -or -not $nameById.ContainsKey([string]$row['resourceId'])) { continue }
        $recommendations.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppRecommendation'; App = $nameById[[string]$row['resourceId']]; Source = 'Azure Advisor'; Category = [string]$row['category']; Impact = [string]$row['impact']; Recommendation = [string]$row['problem']; Action = [string]$row['solution'] })
        & $find $(if ([string]$row['impact'] -eq 'High') { 'Medium' } else { 'Low' }) $nameById[[string]$row['resourceId']] ([string]$row['category']) "Advisor: $($row['problem'])" ([string]$row['problem']) ([string]$row['solution']) 'Advisor' ([string]$row['resourceId'])
    }
    foreach ($row in $Defender) {
        if (-not $row -or -not $nameById.ContainsKey([string]$row['resourceId'])) { continue }
        $recommendations.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppRecommendation'; App = $nameById[[string]$row['resourceId']]; Source = 'Defender for Cloud'; Category = 'Security'; Impact = [string]$row['severity']; Recommendation = [string]$row['name']; Action = [string]$row['remediation'] })
        & $find $(if ([string]$row['severity'] -eq 'High') { 'High' } elseif ([string]$row['severity'] -eq 'Medium') { 'Medium' } else { 'Low' }) $nameById[[string]$row['resourceId']] 'Security' "Defender: $($row['name'])" ([string]$row['name']) ([string]$row['remediation']) 'Defender for Cloud' ([string]$row['resourceId'])
    }
    # Each app's findings count again, now PSRule, Advisor and Defender are in.
    foreach ($x in $apps) { $mine = @($findings | Where-Object { $_.App -eq $x.App }); $x.Findings = $mine.Count; $x.High = @($mine | Where-Object { $_.Severity -eq 'High' }).Count }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $pillars = @('Security', 'Reliability', 'Operational Excellence', 'Cost Optimization', 'Performance Efficiency')
    $pillarRows = @(foreach ($pl in $pillars) {
            $c = @($checks | Where-Object { $_.Pillar -eq $pl -and $_.Status -ne 'N/A' })
            $pass = @($c | Where-Object { $_.Status -eq 'Pass' }).Count
            [pscustomobject][ordered]@{ PSTypeName = 'AAC.FunctionAppPillar'; Pillar = $pl; Score = $(if ($c.Count) { [int][Math]::Round(100.0 * $pass / $c.Count) } else { $null }); Passed = $pass; Failed = $c.Count - $pass; Checks = $c.Count; Findings = @($findings | Where-Object { $_.Pillar -eq $pl }).Count }
        })
    $scored = @($checks | Where-Object { $_.Status -ne 'N/A' })
    @{
        Apps            = @($apps | Sort-Object -Property @{ Expression = { if ($null -eq $_.Score) { 101 } else { $_.Score } } }, App)
        Plans           = $planRows.ToArray()
        Functions       = $functions.ToArray()
        Settings        = $settings.ToArray()
        AppSettings     = $appSettings.ToArray()
        Slots           = $slots.ToArray()
        Deployments     = $deployments.ToArray()
        Networks        = $networks.ToArray()
        Backups         = $backups.ToArray()
        Connections     = $connections.ToArray()
        Activity        = @($activity | Sort-Object -Property Time -Descending)
        Checks          = $checks.ToArray()
        Pillars         = $pillarRows
        PSRule          = $ruleResults
        Recommendations = $recommendations.ToArray()
        Findings        = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, App, Finding)
        Stats           = @{
            Apps = $apps.Count; Plans = $planRows.Count; Functions = $functions.Count; Slots = $slots.Count
            WafScore = $(if ($scored.Count) { [int][Math]::Round(100.0 * @($scored | Where-Object { $_.Status -eq 'Pass' }).Count / $scored.Count) } else { $null })
            Executions = [long](@($apps | ForEach-Object { if ($null -ne $_.Executions) { $_.Executions } else { 0 } }) | Measure-Object -Sum).Sum
            Requests = [long](@($apps | ForEach-Object { if ($null -ne $_.Requests) { $_.Requests } else { 0 } }) | Measure-Object -Sum).Sum
            Http5xx = [long](@($apps | ForEach-Object { if ($null -ne $_.Http5xx) { $_.Http5xx } else { 0 } }) | Measure-Object -Sum).Sum
            EstimatedMonthlyUsd = [Math]::Round([double](@($apps | ForEach-Object { if ($null -ne $_.EstimatedMonthlyUsd) { $_.EstimatedMonthlyUsd } else { 0 } }) | Measure-Object -Sum).Sum, 2)
            Idle = @($apps | Where-Object { $_.Idle }).Count; OutOfSupport = @($apps | Where-Object { $_.RuntimeSupport -eq 'Out of support' }).Count; EndingSoon = @($apps | Where-Object { $_.RuntimeSupport -eq 'Ending soon' }).Count
            Public = @($apps | Where-Object { $_.Inbound -eq 'Public' }).Count; Changes = $activity.Count; SettingsUnread = @($apps | Where-Object { -not $_.SettingsRead }).Count
            High = @($findings | Where-Object { $_.Severity -eq 'High' }).Count; Medium = @($findings | Where-Object { $_.Severity -eq 'Medium' }).Count; Low = @($findings | Where-Object { $_.Severity -eq 'Low' }).Count
            PSRuleFailed = @($ruleResults | Where-Object { $_.Outcome -eq 'Fail' }).Count
        }
    }
}
