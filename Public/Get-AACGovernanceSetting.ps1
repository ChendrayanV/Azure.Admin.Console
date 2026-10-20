function Get-AACGovernanceSetting {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Checks the tenant-wide and per-subscription settings governance
        depends on - who can create management groups, where new
        subscriptions land, Defender security contacts, classic
        administrators, preview features, resource providers registered
        unevenly, and each subscription's offer and state.
    .DESCRIPTION
        Reads, read-only:
          Management groups  the tenant root group's hierarchy settings:
                             whether creating a management group needs
                             permission, and the default management group
                             for new subscriptions
          Resource Graph     each subscription's offer (quota ID), state and
                             spending limit
          Management group   each management group above the subscriptions:
          diagnostics        whether its activity log (administrative and
                             policy events) is exported anywhere
          Each subscription  Defender for Cloud security contacts and email
                             notifications, classic administrators, the
                             preview features registered, and the resource
                             providers registered
        Each setting (AAC.GovernanceSetting) has its area, scope, value,
        status - Warning (fix it), Info (worth knowing) or OK - and what to
        do. Warnings: anyone can create management groups, new
        subscriptions land in the root group, a subscription with no
        security contact or with alert notifications off, a management
        group whose activity log goes nowhere, classic co-administrators
        left, a subscription not Enabled.

        Reader is enough (Reader on the tenant root group for its settings;
        what can't be read is left out, and said).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Area
        Only these areas: ManagementGroups, Diagnostics, Subscription,
        DefenderContacts, ClassicAdministrators, PreviewFeatures,
        ResourceProviders.
    .PARAMETER Status
        Only these: Warning, Info, OK.
    .PARAMETER CsvPath
        Write the settings to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the settings.
    .PARAMETER NoDisplay
        Return the settings without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACGovernanceSetting
        Every governance setting, the warnings first.
    .EXAMPLE
        Get-AACGovernanceSetting -Status Warning -NoDisplay | Select-Object Area, Scope, Setting, Recommendation
        Only what needs fixing.
    .EXAMPLE
        Get-AACGovernanceSetting -Area PreviewFeatures, ResourceProviders -HtmlPath .\Settings.html
        The preview features and unevenly registered providers, as a report.
    .OUTPUTS
        AAC.GovernanceSetting
    #>
    [CmdletBinding()]
    [OutputType('AAC.GovernanceSetting')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('ManagementGroups', 'Diagnostics', 'Subscription', 'DefenderContacts', 'ClassicAdministrators', 'PreviewFeatures', 'ResourceProviders')]
        [string[]] $Area,

        [ValidateSet('Warning', 'Info', 'OK')]
        [string[]] $Status,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Governance settings',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); TenantId = [string]$(if ($script:AACSession) { $script:AACSession.TenantId }) }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Governance settings' -Color 'mediumpurple' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        # Each subscription's offer and spending limit.
        $details = Invoke-AACGraphBatch -Query ([ordered]@{ details = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId = tolower(subscriptionId), quotaId = tostring(properties.subscriptionPolicies.quotaId), spendingLimit = tostring(properties.subscriptionPolicies.spendingLimit)" }) -SubscriptionId $scope.GraphScope -AllowFailure @('details')
        $policy = @{}
        foreach ($row in @($details.Rows['details'] | Where-Object { $_ })) { $policy[[string]$row['subscriptionId']] = $row }
        $subscriptions = @(foreach ($s in $scope.Subscriptions) {
                $copy = @{}; foreach ($k in $s.Keys) { $copy[$k] = $s[$k] }
                $id = ([string]$s['subscriptionId']).ToLowerInvariant()
                if ($policy.Contains($id)) { $copy['quotaId'] = $policy[$id]['quotaId']; $copy['spendingLimit'] = $policy[$id]['spendingLimit'] }
                $copy
            })

        $uris = [ordered]@{}
        if ($request.TenantId) { $uris['hierarchy'] = "/providers/Microsoft.Management/managementGroups/$($request.TenantId)/settings/default?api-version=2021-04-01" }
        foreach ($id in $scope.Ids) {
            $uris["Contacts|$id"] = "/subscriptions/$id/providers/Microsoft.Security/securityContacts?api-version=2020-01-01-preview"
            $uris["Classic|$id"] = "/subscriptions/$id/providers/Microsoft.Authorization/classicAdministrators?api-version=2015-07-01"
            $uris["Features|$id"] = "/subscriptions/$id/providers/Microsoft.Features/features?api-version=2021-07-01"
            $uris["Providers|$id"] = "/subscriptions/$id/providers?api-version=2021-04-01"
        }
        $groups = @($scope.Subscriptions | ForEach-Object { @($_['chain']) | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { [string]$_['name'] } } | Select-Object -Unique)
        foreach ($g in $groups) { $uris["GroupDiag|$g"] = "/providers/Microsoft.Management/managementGroups/$g/providers/microsoft.insights/diagnosticSettings?api-version=2020-01-01-preview" }
        Update-AACProgress -Id 'arm' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading the settings of $($scope.Ids.Count) subscription(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($ArmDone, $ArmTotal) Update-AACProgress -Id 'arm' -Increment 1 }
        $hierarchy = $null
        $hierarchyError = ''
        $per = @{}
        $groupDiag = [ordered]@{}
        foreach ($key in $uris.Keys) {
            $answer = $answers[$uris[$key]]
            if ($key -eq 'hierarchy') {
                # No settings yet answers 404: the defaults (anyone may create; new subscriptions land in the root).
                if ($answer -and [int]$answer.Status -eq 404) { $hierarchy = @{ properties = @{ requireAuthorizationForGroupCreation = $false; defaultManagementGroup = '' } } }
                elseif ($answer -and -not $answer.Error) { $hierarchy = $answer.Body }
                else { $hierarchyError = $(if ($answer) { [string]$answer.Error } else { 'no answer' }) }
                continue
            }
            $kind, $id = $key.Split('|')
            if ($kind -eq 'GroupDiag') {
                $groupDiag[$id] = if ($answer -and -not $answer.Error) { @{ Items = @($answer.Items | Where-Object { $null -ne $_ }) } } else { @{ Error = $(if ($answer) { [string]$answer.Error } else { 'no answer' }) } }
                continue
            }
            $id = $id.ToLowerInvariant()
            if (-not $per.Contains($id)) { $per[$id] = @{ Errors = @{} } }
            if ($answer -and -not $answer.Error) { $per[$id][$kind] = @($answer.Items | Where-Object { $null -ne $_ }) }
            else { $per[$id][$kind] = $null; $per[$id].Errors[$kind] = $(if ($answer) { [string]$answer.Error } else { 'no answer' }) }
        }
        Update-AACProgress -Id 'arm' -Complete -Description "Read the settings of $($scope.Ids.Count) subscription(s)"
        @{ Result = (ConvertTo-AACGovernanceSetting -Hierarchy $hierarchy -HierarchyError $hierarchyError -TenantId $request.TenantId -Subscription $subscriptions -PerSubscription $per -GroupDiagnostics $groupDiag); Scope = $scope }
    }

    $settings = @($outcome.Result.Settings)
    if ($Area) { $areas = @{ ManagementGroups = 'Management groups'; Diagnostics = 'Diagnostics'; Subscription = 'Subscription'; DefenderContacts = 'Defender contacts'; ClassicAdministrators = 'Classic administrators'; PreviewFeatures = 'Preview features'; ResourceProviders = 'Resource providers' }; $wanted = @($Area | ForEach-Object { $areas[$_] }); $settings = @($settings | Where-Object { $wanted -contains $_.Area }) }
    if ($Status) { $settings = @($settings | Where-Object { $Status -contains $_.Status }) }
    $warnings = @($settings | Where-Object Status -EQ 'Warning').Count
    $tones = @{ Warning = 'warn'; Info = 'info'; OK = 'good' }
    $report = @{
        Subtitle = 'Governance settings: management group hierarchy, subscriptions, Defender contacts, classic administrators, preview features and resource providers'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Subscriptions = "$($outcome.Result.Stats.Subscriptions)" }
        Status   = $(if ($warnings) { 'Warning' } else { 'Success' })
        Headline = $(if ($warnings) { "$warnings setting(s) to fix: $((@($settings | Where-Object Status -EQ 'Warning' | Group-Object Area | ForEach-Object { "$($_.Count) $($_.Name.ToLowerInvariant())" })) -join ', ')" } else { 'No governance setting needs fixing.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $warnings; Label = 'to fix'; Tone = $(if ($warnings) { 'warn' } else { 'good' }); Table = 'settings'; Filters = @{ Status = 'Warning' } }
            @{ Value = '{0:N0}' -f @($settings | Where-Object { $_.Area -eq 'Defender contacts' -and $_.Status -eq 'Warning' }).Count; Label = 'contact gaps'; Tone = 'warn'; Table = 'settings'; Filters = @{ Area = 'Defender contacts' } }
            @{ Value = '{0:N0}' -f @($settings | Where-Object Area -EQ 'Preview features').Count; Label = 'preview features'; Tone = 'info'; Table = 'settings'; Filters = @{ Area = 'Preview features' } }
            @{ Value = '{0:N0}' -f @($settings | Where-Object Area -EQ 'Resource providers').Count; Label = 'uneven providers'; Tone = 'info'; Table = 'settings'; Filters = @{ Area = 'Resource providers' } }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By area'; Items = @($settings | Group-Object Area | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'settings'; Column = 'Area'; Tone = 'info'; Console = $true }
            @{ Title = 'By status'; Kind = 'donut'; CenterLabel = 'settings'; Items = @(foreach ($s in 'Warning', 'Info', 'OK') { $n = @($settings | Where-Object Status -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $tones[$s]; Filter = $s } } }); Table = 'settings'; Column = 'Status' }
        )
        Tables   = @(
            @{ Id = 'settings'; Title = 'Governance settings'; Section = 'Settings'; Rows = $settings; Noun = 'settings'; GroupBy = @('Area', 'Status'); ConsoleLimit = 30
                Empty = 'No setting matches.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $tones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Area'; Label = 'Area'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Scope'; Label = 'Scope'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Setting'; Label = 'Setting'; Console = $true; Pdf = $true }
                    @{ Key = 'Value'; Label = 'Value'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'ScopeId'; Label = 'Scope ID'; Type = 'mono' }
                ) }
        )
        Hint     = '-Area and -Status narrow it; -NoDisplay returns the settings; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $settings -Noun 'setting' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $settings -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
