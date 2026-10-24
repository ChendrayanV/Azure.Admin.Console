function Get-AACKeyVaultInsight {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Key Vault insights across subscriptions - what Azure Monitor's Key
        Vault workbook shows (availability, transactions, latency, failures by
        status, operations from the audit logs) plus saturation, posture,
        callers that are denied or throttled, and secrets, keys and
        certificates near expiry - as a heat map, findings, a
        Spectre.Console view, objects, and CSV, PDF and interactive HTML
        reports.
    .DESCRIPTION
        Read-only. Always (Reader is enough):
          Resource Graph   the vaults, their private endpoints, the Defender
                           for Key Vault plan and its alerts
          metrics          per vault over -TimeRange: Availability,
                           ServiceApiHit (transactions, and by request type),
                           ServiceApiLatency, ServiceApiResult by status code
                           (2xx, 401, 403, 429, other) and SaturationShoebox
                           (Overall Vault Saturation)
          settings         whether AuditEvent reaches a Log Analytics
                           workspace, and in which table
        -IncludeOperations (Log Analytics Reader): the audit logs - both
        AzureDiagnostics and AZKVAuditLogs - by vault, operation and caller,
        with failures, denials (401/403), throttling (429) and p99 duration;
        the SDK's normal Authentication challenge (401) is left out, as in the
        workbook.
        -IncludeObjects (Key Vault Reader, or a List access policy): secrets,
        keys and certificates - metadata only, never a value - with expired,
        expiring within -ExpiryDays and no-expiry. A vault whose firewall
        blocks this machine, or that denies the account, is reported as such.

        Findings (High, Medium, Low): soft delete or purge protection off,
        open to every network, access policies instead of RBAC, no audit logs,
        Defender off or alerting, availability under 99.9%, throttling,
        saturation at 50%+ (High at 75%), 403s, other failures, idle vaults,
        callers denied 10+ times, expired, expiring and never-expiring objects.

        The heat map scores each vault 0-100 for availability, failures,
        throttling, saturation, posture and objects - the 40 worst at the
        prompt and in the reports; clicking a cell in the HTML lists its
        findings.

        -View sets what is returned (piped onward, -PassThru, -NoDisplay) and
        written to -CsvPath: Vault (default), Operation, Object or Finding.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Name
        Only vaults with these names; wildcards work.
    .PARAMETER TimeRange
        How far back the metrics and logs go: 1h, 4h, 12h, 1d (default), 3d,
        7d, 14d or 30d.
    .PARAMETER IncludeOperations
        Read the audit logs: operations and callers.
    .PARAMETER IncludeObjects
        Read secrets, keys and certificates (metadata only) for their expiry.
    .PARAMETER ExpiryDays
        An object expiring within this many days is Expiring (30 by default).
    .PARAMETER View
        Vault, Operation, Object or Finding: what is returned and written to
        -CsvPath.
    .PARAMETER ThrottleLimit
        How many requests run at once (1 to 32; 12 by default).
    .PARAMETER CsvPath
        Write the -View rows to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Connect-AAC
        Get-AACKeyVaultInsight
        Every vault's health, posture and findings over the last day.
    .EXAMPLE
        Get-AACKeyVaultInsight -ResourceGroupName 'rg-app-prod' -TimeRange 7d -IncludeOperations -IncludeObjects -HtmlPath .\out\KeyVault.html -PdfPath .\out\KeyVault.pdf
        A week of a workload's vaults: operations, callers, objects near expiry, as reports.
    .EXAMPLE
        Get-AACKeyVaultInsight -IncludeObjects -View Object -NoDisplay | Where-Object Status -In 'Expired', 'Expiring'
        Secrets, keys and certificates to rotate.
    .EXAMPLE
        Get-AACKeyVaultInsight -IncludeOperations -View Operation -NoDisplay | Where-Object AuthDenied | Sort-Object AuthDenied -Descending | Select-Object -First 10
        The callers denied most often.
    .OUTPUTS
        AAC.KeyVaultInsight, AAC.KeyVaultOperation, AAC.KeyVaultObject or AAC.KeyVaultFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.KeyVaultInsight', 'AAC.KeyVaultOperation', 'AAC.KeyVaultObject', 'AAC.KeyVaultFinding')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateSet('1h', '4h', '12h', '1d', '3d', '7d', '14d', '30d')]
        [string] $TimeRange = '1d',

        [switch] $IncludeOperations,

        [switch] $IncludeObjects,

        [ValidateRange(1, 365)]
        [int] $ExpiryDays = 30,

        [ValidateSet('Vault', 'Operation', 'Object', 'Finding')]
        [string] $View = 'Vault',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Key Vault insights',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # TimeRange -> the span and the metric grain (an interval Azure Monitor accepts).
    $range = @{ '1h' = @(1, 'PT5M', 'PT1H'); '4h' = @(4, 'PT15M', 'PT4H'); '12h' = @(12, 'PT30M', 'PT12H'); '1d' = @(24, 'PT1H', 'P1D'); '3d' = @(72, 'PT6H', 'P3D'); '7d' = @(168, 'PT6H', 'P7D'); '14d' = @(336, 'PT12H', 'P14D'); '30d' = @(720, 'P1D', 'P30D') }[$TimeRange]
    $end = [datetime]::UtcNow
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ })
        Timespan = "$($end.AddHours(-$range[0]).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"; Interval = $range[1]; Duration = $range[2]
        IncludeOperations = [bool]$IncludeOperations; IncludeObjects = [bool]$IncludeObjects; ExpiryDays = $ExpiryDays; ThrottleLimit = $ThrottleLimit
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Key Vault insights' -Color 'gold1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the vaults, Defender and workspaces (Resource Graph)'
        $queries = Get-AACKeyVaultQuery -ResourceGroupName $request.ResourceGroupName
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('pricing', 'alerts', 'workspaces')
        $vaults = @($read.Rows['vaults'] | Where-Object { $n = [string]$_['name']; $null -ne $_ -and (-not $request.Name.Count -or @($request.Name | Where-Object { $n -like $_ }).Count) })
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} vault(s)' -f $vaults.Count)
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }

        Update-AACProgress -Id 'metrics' -Total ([Math]::Max(1, $vaults.Count * 4)) -Description 'Reading metrics and diagnostic settings'
        $telemetry = Read-AACKeyVaultTelemetry -VaultId @($vaults | ForEach-Object { [string]$_['id'] }) -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress { param($Done, $Total) Update-AACProgress -Id 'metrics' -Increment 1 }
        Update-AACProgress -Id 'metrics' -Complete -Description ('Read metrics and settings for {0:N0} vault(s)' -f $vaults.Count)

        $objects = $null
        if ($request.IncludeObjects) {
            Update-AACProgress -Id 'objects' -Indeterminate -Description 'Listing secrets, keys and certificates (metadata only)'
            $objects = Read-AACKeyVaultObject -Vault @($vaults | ForEach-Object { @{ Id = [string]$_['id']; Name = [string]$_['name']; Uri = $(if ($_['properties'] -and $_['properties']['vaultUri']) { [string]$_['properties']['vaultUri'] } else { "https://$($_['name']).vault.azure.net/" }) } }) -ThrottleLimit ([Math]::Min(8, $request.ThrottleLimit))
            $blocked = @($objects.Access.Values | Where-Object { $_ -ne 'Read' }).Count
            Update-AACProgress -Id 'objects' -Complete -Description ('Read {0:N0} object(s) from {1:N0} vault(s){2}' -f @($objects.Items).Count, ($vaults.Count - $blocked), $(if ($blocked) { "; $blocked not readable" }))
        }
        $workspaceName = @{}
        $customerId = @{}
        foreach ($w in @($read.Rows['workspaces'])) { if ($w) { $workspaceName[[string]$w['id']] = [string]$w['name']; $customerId[[string]$w['id']] = [string]$w['customerId'] } }
        $common = @{ Vault = $vaults; Telemetry = $telemetry; Pricing = @($read.Rows['pricing']); Alert = @($read.Rows['alerts']); WorkspaceName = $workspaceName; Object = $objects; SubscriptionName = $scope.Names; ExpiryDays = $request.ExpiryDays }
        $result = ConvertTo-AACKeyVaultInsight @common

        if ($request.IncludeOperations) {
            $targets = @{}
            foreach ($v in $result.Vaults) {
                if (-not $v.AuditWorkspaceId) { continue }
                $cid = $customerId[$v.AuditWorkspaceId]
                if (-not $cid) { $notices.Add("$($v.Vault) sends its audit logs to a workspace your account can't see ($(($v.AuditWorkspaceId -split '/')[-1])); its operations are left out."); continue }
                if (-not $targets.Contains($cid)) { $targets[$cid] = [System.Collections.Generic.List[string]]::new() }
                $targets[$cid].Add($v.ResourceId)
            }
            Update-AACProgress -Id 'logs' -Indeterminate -Description ('Reading audit logs from {0:N0} workspace(s)' -f $targets.Count)
            $logs = Read-AACKeyVaultLog -Workspace $targets -Duration $request.Duration
            foreach ($cid in @($logs.Errors.Keys)) { $notices.Add("Audit logs couldn't be read from workspace $($cid): $($logs.Errors[$cid] -replace '\s+', ' ')") }
            $result = ConvertTo-AACKeyVaultInsight @common -Log $logs.Rows
            Update-AACProgress -Id 'logs' -Complete -Description ('Read {0:N0} operation row(s)' -f @($result.Operations).Count)
        }
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $show = { param($Value, [string] $Format = 'N0') if ($null -eq $Value) { '-' } else { ([double]$Value).ToString($Format) } }
    $vaults = @($r.Vaults | Sort-Object -Property @{ Expression = { if ($null -eq $_.Score) { 101 } else { $_.Score } } }, Vault)
    $availabilities = @($r.Vaults | Where-Object { $null -ne $_.Availability -and $_.Transactions } | ForEach-Object { $_.Availability })
    $worstAvailability = if ($availabilities.Count) { ($availabilities | Measure-Object -Minimum).Minimum } else { $null }
    $deniedCallers = @($r.Operations | Where-Object AuthDenied | Group-Object -Property Caller | ForEach-Object { @{ Label = $(if ($_.Name) { $_.Name } else { '(unknown)' }); Value = ($_.Group | Measure-Object -Property AuthDenied -Sum).Sum; Filter = $_.Name } } | Sort-Object -Property { $_.Value } -Descending | Select-Object -First 10)
    $tones = @{ Expired = 'bad'; Expiring = 'warn'; 'No expiry' = 'neutral'; OK = 'good'; Disabled = 'neutral' }
    $report = @{
        Subtitle = "Key Vault insights - last $TimeRange"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'Time range' = $TimeRange; Operations = $(if ($IncludeOperations) { 'audit logs read' } else { 'not read (-IncludeOperations)' }); Objects = $(if ($IncludeObjects) { "read; expiring within $ExpiryDays days" } else { 'not read (-IncludeObjects)' }) }
        Status   = $(if ($stats.High) { 'Failed' } elseif (@($r.Findings).Count) { 'Warning' } else { 'Success' })
        Headline = $(if (-not $stats.Vaults) { 'No Key Vault in scope.' } else { "$($stats.Vaults) vault(s), $('{0:N0}' -f $stats.Transactions) transaction(s): $($stats.High) high finding(s); $('{0:N0}' -f $stats.Throttled) throttled, $('{0:N0}' -f $stats.Forbidden) denied (403)$(if ($IncludeObjects) { "; $($stats.Expired) expired, $($stats.Expiring) expiring" })" })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Vaults; Label = 'vaults'; Tone = 'info'; Table = 'vaults' }
            @{ Value = & $show $worstAvailability 'N2'; Label = 'lowest availability %'; Tone = $(if ($null -eq $worstAvailability) { 'neutral' } elseif ($worstAvailability -ge 99.9) { 'good' } else { 'bad' }) }
            @{ Value = '{0:N0}' -f $stats.Throttled; Label = 'throttled (429)'; Tone = $(if ($stats.Throttled) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Signal = 'Throttling' } }
            @{ Value = '{0:N0}' -f $stats.Saturated; Label = 'saturation 75%+'; Tone = $(if ($stats.Saturated) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Signal = 'Saturation' } }
            @{ Value = '{0:N0}' -f $stats.NoAuditLogs; Label = 'without audit logs'; Tone = $(if ($stats.NoAuditLogs) { 'warn' } else { 'good' }); Table = 'vaults'; Filters = @{ AuditLogsTo = '' } }
            if ($IncludeObjects) { @{ Value = '{0:N0}' -f ($stats.Expired + $stats.Expiring); Label = 'objects expired or expiring'; Tone = $(if ($stats.Expired) { 'bad' } elseif ($stats.Expiring) { 'warn' } else { 'good' }); Table = 'objects' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        HeatMaps = @($(if (@($r.HeatMap.Rows).Count) { $r.HeatMap }))
        Charts   = @(
            @{ Title = 'Requests by status'; Kind = 'donut'; CenterLabel = 'requests'; Items = @(foreach ($k in '2xx', '401', '403', '429', 'Other') { if ($r.StatusCodes[$k]) { @{ Label = $k; Value = $r.StatusCodes[$k]; Tone = @{ '2xx' = 'good'; '401' = 'neutral'; '403' = 'bad'; '429' = 'bad'; Other = 'warn' }[$k] } } }) }
            @{ Title = 'Request types'; Items = @($r.RequestTypes.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Key; Value = $_.Value } }); Tone = 'info' }
            @{ Title = 'Callers denied most (401/403)'; Items = $deniedCallers; Table = 'operations'; Column = 'Caller'; Tone = 'bad'; Console = [bool]$deniedCallers.Count }
        )
        Tabs     = @(
            @{ Name = 'Vaults'; Badge = $stats.Vaults; Tone = 'info'; Note = 'Each vault''s health over the period (the workbook''s Overview and Failures), saturation, posture and audit logs.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to fix, worst first.' }
            @{ Name = 'Operations'; Badge = @($r.Operations).Count; Tone = 'violet'; Note = 'The audit logs by vault, operation and caller (the workbook''s Operations tab), with denials and throttling.' }
            @{ Name = 'Objects'; Badge = @($r.Objects).Count; Tone = 'neutral'; Note = "Secrets, keys and certificates - metadata only - expired, expiring within $ExpiryDays days, or never expiring." }
        )
        Tables   = @(
            @{ Id = 'vaults'; Title = 'Vaults'; Section = 'Vaults'; Rows = $vaults; Noun = 'vaults'; GroupBy = @('Subscription', 'ResourceGroup', 'Network', 'PermissionModel'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Vault'; Label = 'Vault'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Availability'; Label = 'Availability %'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    @{ Key = 'Transactions'; Label = 'Transactions'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Forbidden'; Label = '403'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Throttled'; Label = '429'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'OtherFailures'; Label = 'Other failures'; Type = 'number'; Sum = $true }
                    @{ Key = 'Unauthorized'; Label = '401 (incl. SDK challenge)'; Type = 'number'; Sum = $true }
                    @{ Key = 'LatencyAvgMs'; Label = 'Latency ms'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'SaturationMax'; Label = 'Saturation max %'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Network'; Label = 'Network'; Type = 'badge'; Tones = @{ Private = 'good'; Firewall = 'info'; Public = 'warn' }; Facet = $true; Pdf = $true }
                    @{ Key = 'PermissionModel'; Label = 'Permissions'; Facet = $true }
                    @{ Key = 'PurgeProtection'; Label = 'Purge protection'; Facet = $true }
                    @{ Key = 'AuditLogsTo'; Label = 'Audit logs to'; Facet = $true }
                    @{ Key = 'Defender'; Label = 'Defender'; Type = 'badge'; Tones = @{ On = 'good'; Off = 'warn' }; Facet = $true }
                    @{ Key = 'RequestTypes'; Label = 'Top request types'; Type = 'wide' }
                    @{ Key = 'Expired'; Label = 'Expired'; Type = 'number'; Sum = $true }
                    @{ Key = 'Expiring'; Label = 'Expiring'; Type = 'number'; Sum = $true }
                    @{ Key = 'ObjectAccess'; Label = 'Objects'; Facet = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Signal', 'Finding', 'Severity', 'Vault'); ConsoleLimit = 20
                Empty = 'Nothing to fix.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Vault'; Label = 'Vault'; Type = 'resource'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Signal'; Label = 'Signal'; Facet = $true; Console = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'operations'; Title = 'Operations and callers'; Section = 'Operations'; Rows = @($r.Operations | Sort-Object -Property @{ Expression = 'Failed'; Descending = $true }, @{ Expression = 'Count'; Descending = $true }); Noun = 'rows'; GroupBy = @('Vault', 'Operation', 'Caller'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Vault'; Label = 'Vault'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Operation'; Label = 'Operation'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Caller'; Label = 'Caller (app or object ID)'; Type = 'mono'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'CallerIp'; Label = 'Caller IP'; Type = 'mono' }
                    @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'AuthDenied'; Label = '401/403'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Throttled'; Label = '429'; Type = 'number'; Sum = $true; Pdf = $true }
                    @{ Key = 'P99Ms'; Label = 'p99 ms'; Type = 'number'; Format = 'N0' }
                ) }
            @{ Id = 'objects'; Title = 'Secrets, keys and certificates'; Section = 'Objects'; Rows = @($r.Objects | Sort-Object -Property @{ Expression = { @{ Expired = 0; Expiring = 1; 'No expiry' = 2; OK = 3; Disabled = 4 }[$_.Status] } }, DaysLeft, Vault); Noun = 'objects'; GroupBy = @('Status', 'Kind', 'Vault'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $tones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Vault'; Label = 'Vault'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Name'; Console = $true; Pdf = $true }
                    @{ Key = 'Expires'; Label = 'Expires'; Type = 'date'; Soon = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DaysLeft'; Label = 'Days left'; Type = 'number'; Console = $true }
                ) }
        )
        Hint     = '-IncludeOperations reads the audit logs (callers, denials); -IncludeObjects reads expiry dates; -TimeRange 7d looks further back; -View Operation, Object or Finding returns those rows; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = switch ($View) { 'Operation' { @($r.Operations) } 'Object' { @($r.Objects) } 'Finding' { @($r.Findings) } default { $vaults } }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
