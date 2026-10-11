function Export-AACDiagnosticBundle {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Packages everything needed to troubleshoot Azure resources into one
        zip for a support case or a colleague - each resource's
        configuration, health and its history, Activity Log, diagnostic
        settings, locks, recommendations, compliance, alerts, recent changes
        and role assignments - with secrets redacted and a summary on top.
    .DESCRIPTION
        For each resource (-ResourceId, piped in, or every resource of
        -ResourceGroupName, up to -MaxResources):

          config.json               the resource as Resource Graph has it
          health.json               Resource Health now, its history and the
                                    latest health event
          activity-log.json         the Activity Log for the resource, the
                                    last -Hours
          diagnostic-settings.json  where its logs and metrics go
          locks.json                management locks on it
          advisor.json              Azure Advisor recommendations
          defender.json             unhealthy Defender for Cloud assessments
          policy.json               non-compliant Azure Policy states
          alerts.json               alerts fired in the last -Hours
          changes.json              property changes (Resource Graph keeps
                                    14 days)
          role-assignments.json     role assignments scoped to it

        and at the top of the zip: README.md (what is where, when, the
        window), summary.json (the manifest: resources, files, what couldn't
        be read) and summary.html (the summary as an interactive report).

        Secrets are redacted before anything is written: values whose name
        says password, secret, token, connection string, SAS, credentials
        or an access, account or shared access key - and values that look
        like a connection string, a SAS signature, a JWT or a private key.
        Read the bundle before you send it anyway: the account and tenant ID
        it was made with, names, IPs and tags stay in.

        Read-only in Azure; Reader is enough. Writes one zip file (-Force to
        overwrite it); -WhatIf shows where.
    .PARAMETER ResourceId
        The resources to bundle. Takes ResourceId or Id from the pipeline.
    .PARAMETER ResourceGroupName
        Bundle every resource in this resource group (up to -MaxResources).
    .PARAMETER SubscriptionId
        The subscription of -ResourceGroupName (otherwise every subscription
        with a resource group of that name).
    .PARAMETER Path
        The zip file to write.
    .PARAMETER Hours
        How far back the Activity Log and alerts go. Default 24; up to 720.
    .PARAMETER MaxResources
        The most resources to bundle. Default 50.
    .PARAMETER Force
        Overwrite the zip file if it exists.
    .PARAMETER PassThru
        Show the summary and also return the bundle.
    .PARAMETER NoDisplay
        Return the bundle without showing the summary.
    .PARAMETER NoPaging
        Show the whole summary at once.
    .EXAMPLE
        Export-AACDiagnosticBundle -ResourceId $vm.Id -Path .\out\vm-case.zip
        One VM's configuration, health, activity and more, for a support case.
    .EXAMPLE
        Export-AACDiagnosticBundle -ResourceGroupName rg-app -SubscriptionId $sub -Hours 72 -Path .\out\rg-app.zip
        Every resource in rg-app with three days of activity.
    .EXAMPLE
        Get-AACResourceHealth -State Unavailable -NoDisplay | Export-AACDiagnosticBundle -Path .\out\down.zip
        A bundle of everything that is down right now.
    .OUTPUTS
        AAC.DiagnosticBundle
    #>
    [CmdletBinding(DefaultParameterSetName = 'Resource', SupportsShouldProcess)]
    [OutputType('AAC.DiagnosticBundle')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Resource', ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]] $ResourceId,

        [Parameter(Mandatory, ParameterSetName = 'ResourceGroup')]
        [string] $ResourceGroupName,

        [Parameter(ParameterSetName = 'ResourceGroup')]
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateRange(1, 720)]
        [int] $Hours = 24,

        [ValidateRange(1, 200)]
        [int] $MaxResources = 50,

        [switch] $Force,

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $wanted = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($id in @($ResourceId | Where-Object { $_ })) { if ($id -match '^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/') { $wanted.Add($id.TrimEnd('/')) } else { Write-Warning "Not a resource ID, skipped: $id" } }
    }

    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $zip = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if ($zip -notmatch '\.zip$') { $zip += '.zip' }
        if ((Test-Path -LiteralPath $zip) -and -not $Force) { throw [System.IO.IOException]::new("$zip already exists. Use -Force to overwrite it, or choose another -Path.") }
        if (-not $PSCmdlet.ShouldProcess($zip, 'Write a diagnostic bundle')) { return }
        $request = @{ Ids = $wanted.ToArray(); ResourceGroupName = $ResourceGroupName; SubscriptionId = $SubscriptionId; Hours = $Hours; Max = $MaxResources; Version = [string]$MyInvocation.MyCommand.Module.Version }

        $null = Get-AACAccessToken
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Diagnostic bundle' -Color 'deepskyblue3_1' }
        $outcome = Invoke-AACProgress -ScriptBlock {
            $warnings = [System.Collections.Generic.List[string]]::new()
            $ids = @($request.Ids | Select-Object -Unique)
            if ($request.ResourceGroupName) {
                Update-AACProgress -Id 'list' -Indeterminate -Description "Listing the resources of $($request.ResourceGroupName)"
                $listed = Invoke-AACGraphBatch -Query ([ordered]@{ resources = "resources | where resourceGroup =~ '$($request.ResourceGroupName -replace "'", "\'")' | project id, name, type | order by type asc, name asc" }) -SubscriptionId @($request.SubscriptionId | Where-Object { $_ })
                $ids = @($listed.Rows['resources'] | Where-Object { $_ } | ForEach-Object { [string]$_['id'] })
                Update-AACProgress -Id 'list' -Complete -Description ('{0:N0} resource(s) in {1}' -f $ids.Count, $request.ResourceGroupName)
                if (-not $ids.Count) { throw [System.InvalidOperationException]::new("No resources found in resource group '$($request.ResourceGroupName)'$(if ($request.SubscriptionId) { " of subscription $($request.SubscriptionId)" }).") }
            }
            if (-not $ids.Count) { throw [System.ArgumentException]::new('No resource to bundle: give -ResourceId (or pipe resources in) or -ResourceGroupName.') }
            if ($ids.Count -gt $request.Max) { $warnings.Add("$($ids.Count) resources: the first $($request.Max) were bundled (-MaxResources)."); $ids = @($ids | Select-Object -First $request.Max) }
            $lower = @($ids | ForEach-Object { $_.ToLowerInvariant() })
            $subscriptions = @($lower | ForEach-Object { ($_ -split '/')[2] } | Select-Object -Unique)

            # --- Resource Graph ----------------------------------------------------------------------------------------
            $queries = Get-AACDiagnosticBundleQuery -ResourceId $lower -Hours $request.Hours
            Update-AACProgress -Id 'graph' -Total $queries.Count -Description "Reading $($ids.Count) resource(s) from Resource Graph"
            $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $subscriptions -AllowFailure @($queries.Keys) -OnProgress { param($QueryName, $Done, $Total) Update-AACProgress -Id 'graph' -Increment 1 -Description "Read the $QueryName ($Done of $Total)" }
            Update-AACProgress -Id 'graph' -Complete -Description "Read $($queries.Count - $read.Errors.Count) of $($queries.Count) Resource Graph sections"

            # --- Resource Manager, per resource ------------------------------------------------------------------------
            $to = [datetime]::UtcNow
            $iso = { param([datetime] $When) $When.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
            $uris = [ordered]@{}
            foreach ($id in $lower) {
                $sub = ($id -split '/')[2]
                $filter = "eventTimestamp ge '$(& $iso $to.AddHours(-$request.Hours))' and eventTimestamp le '$(& $iso $to)' and resourceUri eq '$id'"
                $uris["$id|Activity"] = "/subscriptions/$sub/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$([System.Uri]::EscapeDataString($filter))"
                $uris["$id|Diagnostics"] = "$id/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
                $uris["$id|Locks"] = "$id/providers/Microsoft.Authorization/locks?api-version=2020-05-01"
                $uris["$id|History"] = "$id/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2022-10-01"
            }
            Update-AACProgress -Id 'arm' -Total $uris.Count -Description 'Reading activity, diagnostic settings, locks and health history'
            $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($ArmDone, $ArmTotal) Update-AACProgress -Id 'arm' -Increment 1 }
            $arm = @{}
            foreach ($key in $uris.Keys) {
                $id, $part = $key.Split('|')
                if (-not $arm.Contains($id)) { $arm[$id] = @{} }
                $a = $answers[$uris[$key]]
                # A resource type without diagnostic settings or Resource Health answers 400/404: not an error, just nothing.
                $arm[$id][$part] = if ($a -and $a.Error -and $part -in 'Diagnostics', 'History' -and [int]$a.Status -in 400, 404, 405) { $null } else { $a }
            }
            Update-AACProgress -Id 'arm' -Complete -Description ('Read {0:N0} Resource Manager section(s)' -f $uris.Count)
            $scopeNames = @{}
            $result = ConvertTo-AACDiagnosticBundle -ResourceId $lower -Read $read -Arm $arm -SubscriptionName $scopeNames

            # --- Write, redacted, and zip -----------------------------------------------------------------------------------
            Update-AACProgress -Id 'write' -Indeterminate -Description 'Writing the bundle (secrets redacted)'
            $work = Join-Path ([System.IO.Path]::GetTempPath()) "aac-bundle-$([guid]::NewGuid().ToString('N'))"
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            $redacted = 0
            $files = [System.Collections.Generic.List[string]]::new()
            $write = {
                param([string] $Relative, $Data)
                $full = Join-Path $work $Relative
                $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full)
                $clean = ConvertTo-AACRedactedObject -InputObject $Data -Count ([ref]$redacted)
                [System.IO.File]::WriteAllText($full, ($(if ($null -eq $clean) { 'null' } else { ConvertTo-Json -InputObject $clean -Depth 64 })), $utf8)
                $files.Add($Relative.Replace('\', '/'))
            }
            try {
                foreach ($r in $result.Resources) { foreach ($file in $r.Sections.Keys) { & $write "resources/$($r.Folder)/$file" $r.Sections[$file] } }
                $session = $script:AACSession
                $manifest = [ordered]@{
                    generated   = $to.ToString('o', [cultureinfo]::InvariantCulture)
                    module      = "Azure.Admin.Console $($request.Version)"
                    account     = $(if ($session) { [string]$session.Account } else { '' })
                    tenantId    = $(if ($session) { [string]$session.TenantId } else { '' })
                    windowHours = $request.Hours
                    resources   = @($result.Resources | ForEach-Object { $_.Summary })
                    warnings    = @($warnings) + @($result.Warnings)
                }
                & $write 'summary.json' $manifest
                $readme = @(
                    '# Azure diagnostic bundle'
                    ''
                    "Generated $($manifest.generated) by $($manifest.module)$(if ($manifest.account) { " ($($manifest.account), tenant $($manifest.tenantId))" }); Activity Log and alerts cover the last $($request.Hours) hour(s)."
                    ''
                    'Secrets (keys, passwords, tokens, connection strings, SAS) were replaced by [REDACTED]. Check the files before sharing them anyway.'
                    ''
                    '| Resource | Type | Health | Failed operations | Alerts | Issues | Folder |'
                    '| --- | --- | --- | --- | --- | --- | --- |'
                    @($result.Resources | ForEach-Object { $s = $_.Summary; "| $($s.Resource) | $($s.ResourceType) | $($s.Health) | $($s.FailedOperations) | $($s.Alerts) | $($s.Issues) | $($s.Folder) |" })
                    ''
                    'Each folder holds: config.json, health.json, activity-log.json, diagnostic-settings.json, locks.json, advisor.json, defender.json, policy.json, alerts.json, changes.json, role-assignments.json.'
                    $(if ($manifest.warnings.Count) { "`n## What couldn't be read`n`n$(@($manifest.warnings | ForEach-Object { "- $_" }) -join "`n")" })
                ) -join "`n"
                [System.IO.File]::WriteAllText((Join-Path $work 'README.md'), $readme + "`n", $utf8); $files.Add('README.md')
                @{ Result = $result; Work = $work; Files = $files; Redacted = $redacted; Warnings = @($warnings) + @($result.Warnings) }
            }
            catch { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue; throw }
        }

        $rows = @($outcome.Result.Resources | ForEach-Object { $_.Summary })
        $report = @{
            Subtitle = 'Diagnostic bundle: configuration, health, activity, settings, recommendations and changes per resource'
            Facts    = [ordered]@{ Bundle = $zip; Window = "the last $Hours hour(s)"; Redacted = "$($outcome.Redacted) value(s)" }
            Status   = $(if (@($rows | Where-Object Status -EQ 'Failed').Count) { 'Warning' } else { 'Success' })
            Headline = "Bundled $($rows.Count) resource(s) into $zip ($($outcome.Files.Count + 1) file(s), $($outcome.Redacted) secret value(s) redacted)"
            Tiles    = @(
                @{ Value = '{0:N0}' -f $rows.Count; Label = 'resources'; Tone = 'info' }
                @{ Value = '{0:N0}' -f @($rows | Where-Object { $_.Health -in 'Unavailable', 'Degraded' }).Count; Label = 'not healthy'; Tone = $(if (@($rows | Where-Object { $_.Health -in 'Unavailable', 'Degraded' }).Count) { 'bad' } else { 'good' }) }
                @{ Value = '{0:N0}' -f @($rows | ForEach-Object { $_.FailedOperations } | Measure-Object -Sum).Sum; Label = 'failed operations'; Tone = 'warn' }
                @{ Value = '{0:N0}' -f @($rows | ForEach-Object { $_.Alerts } | Measure-Object -Sum).Sum; Label = 'alerts'; Tone = 'warn' }
                @{ Value = '{0:N0}' -f $outcome.Redacted; Label = 'values redacted'; Tone = 'violet' }
            )
            Notices  = @($outcome.Warnings | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
            Tables   = @(
                @{ Id = 'resources'; Title = 'Resources in the bundle'; Section = 'Resources'; Rows = $rows; Noun = 'resources'; ConsoleLimit = 50
                    Columns = @(
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Success = 'good'; Warning = 'warn'; Failed = 'bad' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                        @{ Key = 'ResourceType'; Label = 'Type'; Type = 'type'; Facet = $true; Console = $true }
                        @{ Key = 'Health'; Label = 'Health'; Type = 'badge'; Tones = @{ Available = 'good'; Unavailable = 'bad'; Degraded = 'warn'; Unknown = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'FailedOperations'; Label = 'Failed ops'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Alerts'; Label = 'Alerts'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Issues'; Label = 'Issues'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'ActivityEvents'; Label = 'Activity events'; Type = 'number' }
                        @{ Key = 'Advisor'; Label = 'Advisor'; Type = 'number' }
                        @{ Key = 'Defender'; Label = 'Defender'; Type = 'number' }
                        @{ Key = 'PolicyNonCompliant'; Label = 'Policy non-compliant'; Type = 'number' }
                        @{ Key = 'Changes'; Label = 'Changes'; Type = 'number' }
                        @{ Key = 'Locks'; Label = 'Locks'; Type = 'number' }
                        @{ Key = 'DiagnosticSettings'; Label = 'Diagnostic settings'; Type = 'number' }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'Folder'; Label = 'Folder'; Type = 'mono' }
                    ) }
            )
            Hint     = 'Open README.md in the zip first; summary.html is the same summary, interactive.'
        }
        try {
            $null = Invoke-AACReportOutput -Report $report -Title 'Azure diagnostic bundle' -HtmlPath (Join-Path $outcome.Work 'summary.html') -Object @()
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zip)
            Compress-Archive -Path (Join-Path $outcome.Work '*') -DestinationPath $zip -Force
        }
        finally { Remove-Item -LiteralPath $outcome.Work -Recurse -Force -ErrorAction SilentlyContinue }

        $bundle = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.DiagnosticBundle'
            Path       = $zip
            Resources  = $rows.Count
            Files      = $outcome.Files.Count + 1
            SizeKB     = [Math]::Round((Get-Item -LiteralPath $zip).Length / 1KB, 1)
            Redacted   = $outcome.Redacted
            Hours      = $Hours
            Warnings   = @($outcome.Warnings)
            Summary    = $rows
            Created    = [datetime]::UtcNow
        }
        if ($interactive) { Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock { Show-AACReportView -Report $report } }
        if ($PassThru -or $NoDisplay -or $pipedOnward -or -not $interactive) { $bundle }
    }
}
