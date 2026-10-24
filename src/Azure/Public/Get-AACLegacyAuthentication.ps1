function Get-AACLegacyAuthentication {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Finds legacy and high-risk authentication across Azure and Entra ID -
        resources that still accept keys, SAS, local accounts, passwords or
        old TLS, legacy-protocol sign-ins, legacy authentication left
        unblocked, implicit grant and password flows, client secrets and
        SMS - with the risk and what to move to.
    .DESCRIPTION
        Azure (Resource Graph, and Resource Manager for App Service):
          Keys and SAS      storage shared keys; local authentication on
                            Cosmos DB, Service Bus, Event Hubs, Relay, Event
                            Grid, SignalR, Web PubSub, App Configuration,
                            Azure AI services, AI Search, Automation, IoT
                            Hub, Batch, Log Analytics and Application
                            Insights; Redis access keys
          Passwords         SQL authentication, PostgreSQL passwords, the
                            container registry admin user, Linux password
                            login, App Service basic authentication (SCM and
                            FTP publishing credentials)
          Local accounts    AKS local accounts, AKS without Entra ID
          Old TLS           TLS 1.0/1.1 on storage, SQL and Redis; Redis's
                            non-TLS port
          Legacy authorization  Key Vault access policies
        Entra ID (Microsoft Graph, unless -SkipEntra):
          Legacy protocols  sign-ins over Exchange ActiveSync, IMAP, POP,
                            SMTP AUTH, EWS, MAPI, Outlook Anywhere,
                            Autodiscover and other clients in the last
                            -SignInDays - successful (High) or failed
                            (password spraying); whether Conditional Access
                            or security defaults block legacy authentication
          Legacy flows      app registrations with the implicit grant or
                            public client flows (ROPC, device code)
          Client secrets    app registrations with secrets and no
                            certificate
          Weak MFA          SMS and voice enabled

        Each finding (AAC.LegacyAuthentication) has its Area (Azure or Entra
        ID), severity, the resource or protocol, the detail and the fix.
        Read-only; Reader in Azure, and for Entra ID AuditLog.Read.All (with
        Entra ID P1 for sign-ins), Policy.Read.All and Application.Read.All.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only Azure resources in these resource groups.
    .PARAMETER ResourceType
        Only Azure resources of these types; wildcards work.
    .PARAMETER Area
        Only Azure or only EntraID.
    .PARAMETER Severity
        Only these severities (High, Medium, Low).
    .PARAMETER SignInDays
        How many days of sign-ins to read for legacy protocols. Default 7.
    .PARAMETER SkipEntra
        Don't read Entra ID (Microsoft Graph): Azure resources only.
    .PARAMETER SkipAppService
        Don't read the App Service publishing credential policies (one call
        per app).
    .PARAMETER CsvPath
        Write the findings to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the findings.
    .PARAMETER NoDisplay
        Return the findings without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACLegacyAuthentication
        Legacy authentication in Azure and Entra ID, the riskiest first.
    .EXAMPLE
        Get-AACLegacyAuthentication -Area EntraID -SignInDays 30 -HtmlPath .\out\LegacyAuth.html
        A month of legacy-protocol sign-ins and the tenant's settings, as an HTML report.
    .EXAMPLE
        Get-AACLegacyAuthentication -SkipEntra -NoDisplay | Group-Object Finding | Sort-Object Count -Descending
        Which key- and password-based patterns are most common in Azure.
    .OUTPUTS
        AAC.LegacyAuthentication
    #>
    [CmdletBinding()]
    [OutputType('AAC.LegacyAuthentication')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [ValidateSet('Azure', 'EntraID')]
        [string[]] $Area,

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Severity,

        [ValidateRange(1, 30)]
        [int] $SignInDays = 7,

        [switch] $SkipEntra,

        [switch] $SkipAppService,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Legacy authentication',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $readAzure = -not $Area -or $Area -contains 'Azure'
    $readEntra = -not $SkipEntra -and (-not $Area -or $Area -contains 'EntraID')
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); SignInDays = $SignInDays; Azure = $readAzure; Entra = $readEntra; AppService = $readAzure -and -not $SkipAppService }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Legacy authentication' -Color 'orange3' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $q = Get-AACLegacyAuthenticationQuery -ResourceGroupName $request.ResourceGroupName -SignInDays $request.SignInDays
        $read = @{ Rows = @{}; Errors = @{} }
        $publishing = @{}
        $notices = [System.Collections.Generic.List[string]]::new()
        if ($request.Azure) {
            Update-AACProgress -Id 'read' -Total $q.Graph.Count -Description 'Reading how Azure resources authenticate'
            $read = Invoke-AACGraphBatch -Query $q.Graph -SubscriptionId $scope.GraphScope -AllowFailure @($q.Graph.Keys) -OnProgress {
                param($QueryName, $Done, $Total)
                Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
            }
            Update-AACProgress -Id 'read' -Complete -Description "Read $($q.Graph.Count - $read.Errors.Count) of $($q.Graph.Count) kinds of resource"
            $sites = @($read.Rows['sites'] | Where-Object { $_ -and $scope.Names.Contains(([string]$_['subscriptionId']).ToLowerInvariant()) })
            if ($request.AppService -and $sites.Count) {
                if ($sites.Count -gt 500) { $notices.Add("$($sites.Count) apps: the publishing credentials of the first 500 were read."); $sites = @($sites | Select-Object -First 500) }
                $uris = [ordered]@{}
                foreach ($s in $sites) { $uris[[string]$s['id']] = "$($s['id'])/basicPublishingCredentialsPolicies?api-version=2023-12-01" }
                Update-AACProgress -Id 'sites' -Total $uris.Count -Description "Reading the publishing credentials of $($uris.Count) app(s)"
                $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($SiteDone, $SiteTotal) Update-AACProgress -Id 'sites' -Increment 1 }
                foreach ($id in $uris.Keys) {
                    $answer = $answers[$uris[$id]]
                    if (-not $answer -or $answer.Error) { $publishing[$id] = $null; continue }
                    $allow = @{}
                    foreach ($item in @($answer.Items | Where-Object { $_ })) { $allow[[string]$item['name']] = [string]$item['properties']['allow'] -eq 'True' }
                    $publishing[$id] = @{ Ftp = [bool]$allow['ftp']; Scm = [bool]$allow['scm'] }
                }
                Update-AACProgress -Id 'sites' -Complete -Description ('Read the publishing credentials of {0:N0} app(s)' -f @($publishing.Values | Where-Object { $null -ne $_ }).Count)
            }
        }
        $entra = $null
        if ($request.Entra) {
            Update-AACProgress -Id 'entra' -Total $q.Entra.Count -Description 'Reading sign-ins and policies from Entra ID'
            $entra = Read-AACGraphQuery -Query $q.Entra -OnDone { param($Key, $Failure, $GraphDone, $GraphTotal) Update-AACProgress -Id 'entra' -Increment 1 }
            Update-AACProgress -Id 'entra' -Complete -Description "Read $($q.Entra.Count - $entra.Errors.Count) of $($q.Entra.Count) Entra ID queries"
        }
        $result = ConvertTo-AACLegacyAuthentication -Read $read -Entra $entra -Publishing $publishing -Protocols $q.Protocols -SignInDays $request.SignInDays -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = @($result.Notices) + $notices.ToArray() }
    }

    $findings = @($outcome.Result.Findings)
    if ($ResourceType) { $findings = @($findings | Where-Object { $t = $_.ResourceType; $_.Area -ne 'Azure' -or @($ResourceType | Where-Object { $t -like $_ }).Count }) }
    if ($Severity) { $findings = @($findings | Where-Object { $Severity -contains $_.Severity }) }

    $rank = Get-AACSeverityRank
    $high = @($findings | Where-Object Severity -EQ 'High').Count
    $azureCount = @($findings | Where-Object Area -EQ 'Azure').Count
    $entraCount = @($findings | Where-Object Area -EQ 'Entra ID').Count
    $resources = @($findings | Where-Object Area -EQ 'Azure' | ForEach-Object { $_.ResourceId } | Select-Object -Unique).Count
    $successful = 0; foreach ($f in @($findings | Where-Object { $_.Category -eq 'Legacy protocols' -and $_.Finding -like 'Successful*' })) { $successful += [int]$f.Count }
    $report = @{
        Subtitle = 'Legacy and high-risk authentication: keys, passwords, old protocols and old TLS'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; 'Entra ID' = $(if ($readEntra) { "read (sign-ins: the last $SignInDays day(s))" } else { 'not read' }) }
        Status   = $(if ($high) { 'Failed' } elseif ($findings.Count) { 'Warning' } else { 'Success' })
        Headline = $(if ($findings.Count) { "$($findings.Count) finding(s): $high high; $resources Azure resource(s) accept keys, passwords or old TLS$(if ($readEntra) { "; $successful successful legacy sign-in(s)" })" } else { 'No legacy authentication found.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $high; Label = 'high'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $azureCount; Label = 'in Azure'; Tone = $(if ($azureCount) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Area = 'Azure' } }
            @{ Value = '{0:N0}' -f $resources; Label = 'resources'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $entraCount; Label = 'in Entra ID'; Tone = $(if ($entraCount) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Area = 'Entra ID' } }
            @{ Value = $(if ($readEntra) { '{0:N0}' -f $successful } else { '-' }); Label = 'legacy sign-ins (successful)'; Tone = $(if ($successful) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Category = 'Legacy protocols' } }
            @{ Value = '{0:N0}' -f @($findings | Where-Object Category -EQ 'Old TLS').Count; Label = 'old TLS'; Tone = 'warn'; Table = 'findings'; Filters = @{ Category = 'Old TLS' } }
        )
        Notices  = @($outcome.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By severity'; Kind = 'donut'; CenterLabel = 'findings'; Items = @(foreach ($s in 'High', 'Medium', 'Low') { $n = @($findings | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $rank.Tone[$s]; Filter = $s } } }); Table = 'findings'; Column = 'Severity' }
            @{ Title = 'By pattern'; Items = @($findings | Group-Object Finding | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Finding'; Tone = 'warn'; Console = $true }
            @{ Title = 'By kind'; Items = @($findings | Group-Object Category | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Category'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'findings'; Title = 'Legacy authentication'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; GroupBy = @('Severity', 'Area', 'Category', 'Finding', 'Subscription'); ConsoleLimit = 30
                Empty = 'No legacy authentication found.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Area'; Label = 'Area'; Facet = $true; Console = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Effort'; Label = 'Effort'; Type = 'badge'; Tones = @{ Low = 'good'; Medium = 'warn'; High = 'bad' }; Facet = $true }
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'type'; Facet = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-Area Azure or EntraID narrows it; -SignInDays reads more sign-ins; -SkipEntra skips Microsoft Graph; -NoDisplay returns the findings; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $findings -Noun 'finding' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $findings -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
