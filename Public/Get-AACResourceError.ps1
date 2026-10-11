function Get-AACResourceError {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Summarizes what failed in Azure - failed deployments and operations,
        access denied, Azure Policy denies, quota and capacity limits,
        throttling and locks - from the Activity Log, with who hit each
        error, the action and scope that were refused, and what to do.
    .DESCRIPTION
        Reads every subscription's Activity Log for the last -Hours (24; up
        to 90 days) in parallel, keeps the failed operations and Azure
        Policy denies - one per correlation ID - and reads the error out of
        each (ARM's error, the innermost detail of a failed deployment):

          Authorization  the caller lacks a role: the action and scope that
                         were refused
          Policy         an Azure Policy assignment denied it
          Quota          a quota (vCPUs, IPs, ...) would be exceeded
          Capacity       the size isn't available in the region or zone
          Throttling     too many requests
          Lock           a CanNotDelete or ReadOnly lock blocked it
          Conflict       another operation was running
          Validation     the template or request was invalid; a resource
                         provider isn't registered
          Not found      something it needs doesn't exist

        Each error (AAC.ResourceError) has the time, operation, resource,
        caller and client IP, the code and message, and the fix; the report
        adds the errors by code (how often, who, how many resources) and by
        caller - the place to start for a pipeline that keeps failing or
        an identity missing a role.

        Read-only; Reader (or Monitoring Reader) on the subscriptions. For
        what changed (successful operations), use Get-AACChangeHistory.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only errors on resources in these resource groups.
    .PARAMETER ResourceType
        Only errors on resources of these types (for example
        'microsoft.compute/virtualmachines'); wildcards work.
    .PARAMETER Category
        Only these kinds of error.
    .PARAMETER Caller
        Only errors of these callers (a UPN, an app ID or object ID);
        wildcards work.
    .PARAMETER Hours
        How far back to read. Default 24; up to 2160 (90 days, what the
        Activity Log keeps).
    .PARAMETER CsvPath
        Write the errors to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the errors.
    .PARAMETER NoDisplay
        Return the errors without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACResourceError
        What failed in the last 24 hours, newest first, with the fix for each.
    .EXAMPLE
        Get-AACResourceError -Category Authorization -Hours 168 -NoDisplay | Group-Object Caller, Action | Sort-Object Count -Descending
        This week's access denials, by who and what they couldn't do.
    .EXAMPLE
        Get-AACResourceError -Category Quota, Capacity -Hours 720 -HtmlPath .\out\Limits.html
        A month of quota and capacity failures, as an HTML report.
    .EXAMPLE
        Get-AACResourceError -Caller 'sp-pipeline*' -Hours 48
        Why the pipeline's deployments failed.
    .OUTPUTS
        AAC.ResourceError
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceError')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [ValidateSet('Authorization', 'Policy', 'Quota', 'Capacity', 'Throttling', 'Lock', 'Conflict', 'Validation', 'Not found', 'Other')]
        [string[]] $Category,

        [SupportsWildcards()]
        [string[]] $Caller,

        [ValidateRange(1, 2160)]
        [int] $Hours = 24,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure resource errors',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $to = [datetime]::UtcNow
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); From = $to.AddHours(-$Hours); To = $to }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Resource errors' -Color 'red3' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $iso = { param([datetime] $When) $When.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
        $select = 'caller,eventTimestamp,status,subStatus,operationName,resourceId,resourceGroupName,correlationId,category,authorization,httpRequest,eventDataId,resourceType,properties,subscriptionId,level'
        $uris = [ordered]@{}
        foreach ($id in $scope.Ids) {
            $filter = "eventTimestamp ge '$(& $iso $request.From)' and eventTimestamp le '$(& $iso $request.To)'"
            if ($request.ResourceGroupName.Count -eq 1) { $filter += " and resourceGroupName eq '$($request.ResourceGroupName[0])'" }
            $uris[$id] = "/subscriptions/$id/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$([System.Uri]::EscapeDataString($filter))&`$select=$select"
        }
        Update-AACProgress -Id 'activity' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading the Activity Log of $($uris.Count) subscription(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($LogDone, $LogTotal) Update-AACProgress -Id 'activity' -Increment 1 }
        $entries = [System.Collections.Generic.List[object]]::new()
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($id in $uris.Keys) {
            $answer = $answers[$uris[$id]]
            if (-not $answer -or $answer.Error) { $notices.Add("The Activity Log of $($scope.Names[$id.ToLowerInvariant()]) couldn't be read: $(if ($answer) { $answer.Error } else { 'no answer' })"); continue }
            foreach ($e in @($answer.Items)) { if ($e) { if (-not $e.Contains('subscriptionId') -or -not $e['subscriptionId']) { $e['subscriptionId'] = $id }; $entries.Add($e) } }
        }
        Update-AACProgress -Id 'activity' -Complete -Description ('Read {0:N0} Activity Log event(s)' -f $entries.Count)
        $result = ConvertTo-AACResourceError -Entry $entries.ToArray() -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $errors = @($outcome.Result.Errors)
    if ($request.ResourceGroupName.Count) { $groups = @($request.ResourceGroupName | ForEach-Object { $_.ToLowerInvariant() }); $errors = @($errors | Where-Object { $groups -contains ([string]$_.ResourceGroup).ToLowerInvariant() }) }
    if ($ResourceType) { $errors = @($errors | Where-Object { $t = $_.ResourceType; @($ResourceType | Where-Object { $t -like $_ }).Count }) }
    if ($Category) { $errors = @($errors | Where-Object { $Category -contains $_.Category }) }
    if ($Caller) { $errors = @($errors | Where-Object { $c = $_.Caller; @($Caller | Where-Object { $c -like $_ }).Count }) }
    $codes = @(@(foreach ($group in @($errors | Group-Object ErrorCode, Category)) {
            $first = $group.Group[0]
            [pscustomobject][ordered]@{
                ErrorCode   = $first.ErrorCode
                Category    = $first.Category
                Count       = $group.Count
                Callers     = (@($group.Group | ForEach-Object { $_.Caller } | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 5) -join ', ')
                Resources   = @($group.Group | ForEach-Object { $_.ResourceId } | Where-Object { $_ } | Select-Object -Unique).Count
                LastSeen    = @($group.Group | Sort-Object Time -Descending)[0].Time
                Example     = $first.Message
                Remediation = $first.Remediation
                Link        = $first.Link
            }
        }) | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, ErrorCode)

    $categoryTones = @{ Authorization = 'bad'; Policy = 'violet'; Quota = 'warn'; Capacity = 'warn'; Throttling = 'info'; Lock = 'neutral'; Conflict = 'info'; Validation = 'warn'; 'Not found' = 'neutral'; Other = 'neutral' }
    $denied = @($errors | Where-Object Category -EQ 'Authorization').Count
    $policy = @($errors | Where-Object Category -EQ 'Policy').Count
    $limits = @($errors | Where-Object { $_.Category -in 'Quota', 'Capacity' }).Count
    $deployments = @($errors | Where-Object { $_.OperationName -match '(?i)microsoft\.resources/deployments/' }).Count
    $callers = @($errors | ForEach-Object { $_.Caller } | Where-Object { $_ } | Select-Object -Unique).Count
    $report = @{
        Subtitle = 'Failed operations: access, policy, quota, capacity, throttling, locks and deployments'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Window = "the last $Hours hour(s)" }
        Status   = $(if ($errors.Count) { 'Warning' } else { 'Success' })
        Headline = $(if ($errors.Count) { "$($errors.Count) failed operation(s) by $callers caller(s): $denied access denied, $policy policy deny, $limits quota or capacity" } else { "Nothing failed in the last $Hours hour(s)." })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $errors.Count; Label = 'failed operations'; Tone = $(if ($errors.Count) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $denied; Label = 'access denied'; Tone = $(if ($denied) { 'bad' } else { 'good' }); Table = 'errors'; Filters = @{ Category = 'Authorization' } }
            @{ Value = '{0:N0}' -f $policy; Label = 'policy denies'; Tone = $(if ($policy) { 'violet' } else { 'good' }); Table = 'errors'; Filters = @{ Category = 'Policy' } }
            @{ Value = '{0:N0}' -f $limits; Label = 'quota or capacity'; Tone = $(if ($limits) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $deployments; Label = 'failed deployments'; Tone = $(if ($deployments) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $codes.Count; Label = 'error codes'; Tone = 'info'; Table = 'codes' }
        )
        Notices  = @($outcome.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By kind'; Kind = 'donut'; CenterLabel = 'errors'; Items = @($errors | Group-Object Category | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $categoryTones[$_.Name]; Filter = $_.Name } }); Table = 'errors'; Column = 'Category' }
            @{ Title = 'Top error codes'; Items = @($codes | Select-Object -First 10 | ForEach-Object { @{ Label = $_.ErrorCode; Value = $_.Count; Filter = $_.ErrorCode } }); Table = 'errors'; Column = 'ErrorCode'; Tone = 'bad'; Console = $true }
            @{ Title = 'Top callers'; Items = @($errors | Where-Object Caller | Group-Object Caller | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'errors'; Column = 'Caller'; Tone = 'warn'; Console = $true }
            @{ Title = 'By hour'; Items = @($errors | Where-Object Time | Group-Object { $_.Time.ToString('yyyy-MM-dd HH:00', [cultureinfo]::InvariantCulture) } | Sort-Object Name | Select-Object -Last 48 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }); Tone = 'info' }
        )
        Tables   = @(
            @{ Id = 'codes'; Title = 'By error code'; Section = 'Error codes'; Rows = $codes; Noun = 'codes'; ConsoleLimit = 10
                Empty = "Nothing failed in the last $Hours hour(s)."; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'ErrorCode'; Label = 'Code'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Kind'; Type = 'badge'; Tones = $categoryTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Callers'; Label = 'Callers'; Type = 'wide'; Console = $true }
                    @{ Key = 'Resources'; Label = 'Resources'; Type = 'number' }
                    @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime'; Pdf = $true }
                    @{ Key = 'Example'; Label = 'Example'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'errors'; Title = 'Failed operations'; Section = 'Failed operations'; Rows = $errors; Noun = 'errors'; GroupBy = @('Category', 'ErrorCode', 'Caller', 'Subscription'); ConsoleLimit = 25
                Empty = "Nothing failed in the last $Hours hour(s)."; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Time'; Label = 'Time'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Kind'; Type = 'badge'; Tones = $categoryTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ErrorCode'; Label = 'Code'; Type = 'mono'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Operation'; Label = 'Operation'; Console = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Caller'; Label = 'Caller'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Message'; Label = 'Message'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Action'; Label = 'Refused action'; Type = 'mono' }
                    @{ Key = 'Scope'; Label = 'Scope'; Type = 'mono' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide' }
                    @{ Key = 'ClientIp'; Label = 'Client IP'; Type = 'mono' }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'CorrelationId'; Label = 'Correlation ID'; Type = 'mono' }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-Category Authorization (or Policy, Quota...) narrows the list; -Caller finds an identity''s errors; -Hours goes further back; -NoDisplay returns the errors; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $errors -Noun 'error' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $errors -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
