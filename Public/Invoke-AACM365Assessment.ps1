function Invoke-AACM365Assessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Microsoft 365 tenant discovery and security posture - Entra ID,
        Microsoft 365 and Intune - read from the Microsoft Graph REST API
        with one token, with zero-trust findings, as a Spectre.Console view,
        an object, CSV files and a tabbed, interactive HTML report.
    .DESCRIPTION
        Read-only, Microsoft Graph REST only: no AzureAD, MSOnline,
        AzureADPreview or Microsoft.Graph modules. Every call uses the one
        Graph token of the Connect-AAC sign-in; about 25 calls run in
        parallel, each followed through its pages.

        -Section picks what is read (everything by default):
          Entra         tenant details and directory sync, licences,
                        security defaults, user and guest settings
                        (authorization policy), cross-tenant access,
                        Conditional Access policies and named locations,
                        admin roles - active and eligible (PIM) - with each
                        admin's MFA registration, every user's MFA
                        registration, authentication methods, identity
                        providers - and:
                          MFA coverage           registered and phishing-
                                                 resistant MFA by members,
                                                 admins and guests; the MFA
                                                 policy's exclusions
                          emergency access       break-glass accounts (excluded
                                                 from every policy, or by
                                                 name): two, cloud-only,
                                                 Global Admin, passkey
                          dangling admins        privileged roles held by
                                                 deleted, disabled, guest,
                                                 idle, synced accounts or apps
                          role overlap           Global Admin plus more, three
                                                 or more roles, active and
                                                 eligible at once
                          legacy authentication  actual IMAP, POP, SMTP AUTH,
                                                 ActiveSync... sign-ins in
                                                 the last -SignInDays
                          user consent           who can consent to apps, and
                                                 the admin consent workflow
                          security defaults      off with no MFA, or on when
                                                 Conditional Access is
                                                 licensed
                          PIM role settings      MFA, approval, justification
                                                 and maximum duration on
                                                 activation; permanent
                                                 assignments
                          groups                 who is in the groups excluded
                                                 from Conditional Access and
                                                 the groups holding roles
                          access reviews         of admin roles and guests
                          directory sync         password hash sync,
                                                 accidental deletion
                                                 prevention
          Threat protection (with Entra and Microsoft365) risky users and
                        risk detections (Identity Protection), Microsoft
                        Defender XDR incidents
          Applications  (with Entra) app registrations and enterprise
                        apps: secrets and certificates expired, expiring or
                        long-lived; over-privileged permissions (application
                        permissions on Microsoft Graph and delegated
                        consents, rated Critical, High, Medium); redirect
                        URIs that are dangling (their host looked up in DNS),
                        wildcard or not HTTPS
          Microsoft365  domains, Microsoft Secure Score and its controls
                        (with the gap and how to fix each), SharePoint and
                        OneDrive sharing settings, audit logging (Purview
                        audit log search, from its Secure Score control, and
                        the Entra audit log)
          Intune        tenant settings, enrollment restrictions,
                        compliance policies, endpoint security policies
                        (antivirus, firewall, disk encryption, EDR, attack
                        surface reduction, account protection), managed
                        devices (compliance, encryption, stale), the
                        Entra ID devices no MDM manages, and app protection
                        (MAM) for personal iOS and Android devices
          Microsoft365  (also) licensed users with no activity in 30 days

        PERMISSIONS. A Graph token carries the permissions consented to the
        app you sign in with. Connect-AAC's default (the Azure CLI) can read
        the directory but not Conditional Access, Intune or Secure Score.
        For everything in one token, sign in with an app that has the
        delegated (or, for a service principal, application) permissions
        -ListPermission prints - for example Microsoft Graph Command Line
        Tools, once an admin has consented:

            Connect-AAC -ClientId 14d82eec-204b-4c2f-b7e8-296a70dab67e `
                -Scope ((Invoke-AACM365Assessment -ListPermission) + 'offline_access', 'openid', 'profile')

        Your account also needs a directory role that can read them (Global
        Reader, Security Reader plus Intune Administrator or reader roles).
        COVERAGE. The Coverage tab lists every lens - Assessed, Partly
        assessed, Not assessed (with Graph's reason, the permission and any
        licence it needs) or Not in this run - and what Microsoft Graph
        doesn't reach at all (Exchange Online, Defender for Office 365,
        Purview, Teams, Defender for Cloud Apps, Sentinel...), each with
        what would cover it. The rest of the report is made whatever is
        refused.

        What you get depends on where the command runs:
          at the prompt    tiles, the security settings, Conditional Access,
                           the privileged role assignments, what couldn't
                           be read and the findings, a page at a time
          piped onward     the AAC.M365Assessment object, with every table
                           as a property
          -PassThru        the view and the object
          -NoDisplay       the object only
        -CsvPath (a folder) writes a CSV per table. -HtmlPath writes a
        tabbed report - Overview, Findings, Entra ID, Microsoft 365,
        Applications, Threat protection, Intune, Coverage - where every
        table can be searched, filtered, grouped
        and downloaded, and a row opens all its details.
    .PARAMETER Section
        What to read: Entra, Microsoft365, Intune. All by default.
    .PARAMETER StaleDays
        A device that hasn't checked in (Intune) or signed in (Entra ID) for
        more than this many days is stale. 90 by default.
    .PARAMETER SignInDays
        Look for sign-ins with legacy authentication protocols in the last
        this many days (7 by default; Entra ID keeps sign-ins 30 days with
        P1 or P2).
    .PARAMETER ListPermission
        Return the Microsoft Graph permissions the report needs (as scopes
        for Connect-AAC -Scope), and read nothing.
    .PARAMETER CsvPath
        A folder to write a CSV per table to.
    .PARAMETER HtmlPath
        Write the tabbed, interactive HTML report to this file.
    .PARAMETER Title
        The HTML report's title.
    .PARAMETER PassThru
        Show the view and also return the object.
    .PARAMETER NoDisplay
        Return the object without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC -ClientId 14d82eec-204b-4c2f-b7e8-296a70dab67e -Scope ((Invoke-AACM365Assessment -ListPermission) + 'offline_access', 'openid', 'profile')
        Invoke-AACM365Assessment -HtmlPath .\out\M365.html -CsvPath .\out\m365
        Signs in once with every permission the report needs, then writes the HTML report and a CSV per table.
    .EXAMPLE
        Invoke-AACM365Assessment -Section Entra
        Only Entra ID: settings, Conditional Access, admin roles and MFA registration.
    .EXAMPLE
        (Invoke-AACM365Assessment -NoDisplay -Section Entra).Registration | Where-Object { $_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'No' }
        The administrators with no MFA method registered.
    .EXAMPLE
        (Invoke-AACM365Assessment -NoDisplay -Section Intune -StaleDays 30).ManagedDevices | Where-Object Stale -EQ 'Yes' | Export-Csv .\stale.csv
        The Intune devices that haven't checked in for 30 days.
    .OUTPUTS
        AAC.M365Assessment (piped onward, or with -PassThru or -NoDisplay)
        System.String (with -ListPermission)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Assess')]
    [OutputType('AAC.M365Assessment', ParameterSetName = 'Assess')]
    [OutputType([string], ParameterSetName = 'Permission')]
    param(
        [Parameter(ParameterSetName = 'Assess')]
        [Parameter(ParameterSetName = 'Permission')]
        [ValidateSet('Entra', 'Microsoft365', 'Intune')]
        [string[]] $Section = @('Entra', 'Microsoft365', 'Intune'),

        [Parameter(ParameterSetName = 'Assess')]
        [ValidateRange(1, 3650)]
        [int] $StaleDays = 90,

        [Parameter(ParameterSetName = 'Assess')]
        [ValidateRange(1, 30)]
        [int] $SignInDays = 7,

        [Parameter(Mandatory, ParameterSetName = 'Permission')]
        [switch] $ListPermission,

        [Parameter(ParameterSetName = 'Assess')]
        [string] $CsvPath,

        [Parameter(ParameterSetName = 'Assess')]
        [string] $HtmlPath,

        [Parameter(ParameterSetName = 'Assess')]
        [string] $Title = 'Microsoft 365 security posture',

        [Parameter(ParameterSetName = 'Assess')]
        [switch] $PassThru,

        [Parameter(ParameterSetName = 'Assess')]
        [switch] $NoDisplay,

        [Parameter(ParameterSetName = 'Assess')]
        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $queries = Get-AACM365AssessmentQuery -Section $Section
    if ($ListPermission) {
        return @($queries.Values | ForEach-Object { "https://graph.microsoft.com/$($_.Permission)" } | Sort-Object -Unique)
    }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Section = @($Section); StaleDays = $StaleDays; SignInDays = $SignInDays; CsvPath = & $resolve $CsvPath; HtmlPath = & $resolve $HtmlPath; Title = $Title; Queries = $queries }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Microsoft 365 security posture' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        # One Graph token for every call: the Connect-AAC sign-in's.
        $null = Get-AACAccessToken -Resource 'https://graph.microsoft.com'
        # A progress line per batch, one after another. The callback runs
        # inside Invoke-AACHttpBatch, whose -Request would hide $request: it
        # uses nothing but its arguments.
        $read = Read-AACM365Graph -Query $request.Queries -SignInDays $request.SignInDays -OnProgress {
            param($Batch, $What, $Done, $Total, $Waiting, $Finished)
            if ($Finished) { Update-AACProgress -Id "graph $Batch" -Complete -Description "$($Batch): read $Done of $Total" }
            elseif (-not $What) { Update-AACProgress -Id "graph $Batch" -Total $Total -Description "$($Batch): reading $Total$(if ($Waiting) { " ($Waiting)" })" }
            else { Update-AACProgress -Id "graph $Batch" -Total $Total -Increment 1 -Description "$($Batch): read $What ($Done of $Total)$(if ($Waiting) { "; still reading $Waiting" })" }
        }
        if (-not $read.Data.Count) {
            $problem = [System.InvalidOperationException]::new("Microsoft Graph refused every read: $(@($read.Errors.Values | Select-Object -First 1))")
            $problem.Data['AACHint'] = 'Sign in with an app that has the permissions -ListPermission prints: Connect-AAC -ClientId 14d82eec-204b-4c2f-b7e8-296a70dab67e -Scope ((Invoke-AACM365Assessment -ListPermission) + ''offline_access'', ''openid'', ''profile'')'
            throw $problem
        }

        Update-AACProgress -Id 'assess' -Indeterminate -Description 'Assessing identity, data and devices'
        $assessment = ConvertTo-AACM365Assessment -Data $read.Data -Errors $read.Errors -Query $request.Queries -StaleDays $request.StaleDays -SignInDays $request.SignInDays -Resolved $read.Resolved -Fallback $read.Fallbacks
        $stats = $assessment.Stats
        Update-AACProgress -Id 'assess' -Complete -Description ('{0}: Secure Score {1}; MFA registered {2}; {3} Conditional Access polic(ies) on; {4} critical/high, {5} medium finding(s)' -f $(if ($stats.Tenant) { $stats.Tenant } else { 'Tenant' }), $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { 'n/a' }), $(if ($null -ne $stats.MfaRegistered) { "$($stats.MfaRegistered)%" } else { 'n/a' }), $stats.ConditionalAccessOn, ($stats.Critical + $stats.High), $stats.Medium)

        $detail = [ordered]@{
            Tenant   = "$($stats.Tenant) ($($stats.TenantId))"
            Sections = $request.Section -join ', '
            Read     = "$($stats.Read) of $($stats.Read + $stats.NotRead + @($assessment.Permissions | Where-Object Status -EQ 'Not asked').Count) Graph endpoints$(if ($stats.NotRead) { " ($($stats.NotRead) refused: see Permissions)" })"
            Stale    = "no check-in or sign-in for $($request.StaleDays) days"
        }
        if ($request.CsvPath) {
            Update-AACProgress -Id 'csv' -Indeterminate -Description 'Writing the CSV files'
            $files = @(Write-AACM365AssessmentCsv -Assessment $assessment -Path $request.CsvPath)
            Update-AACProgress -Id 'csv' -Complete -Description "CSV: $($files.Count) file(s) in $($request.CsvPath)"
        }
        $null = Invoke-AACExport -HtmlPath $request.HtmlPath -WriteHtml {
            Write-AACM365AssessmentHtml -Assessment $assessment -Path $request.HtmlPath -Title $request.Title -Detail $detail
        }
        @{ Assessment = $assessment; Scope = $detail }
    }

    $assessment = $state.Assessment
    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACM365AssessmentView -Assessment $assessment -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($assessment.Notices)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $result = [ordered]@{ PSTypeName = 'AAC.M365Assessment'; Tenant = $assessment.Stats.Tenant; TenantId = $assessment.Stats.TenantId; SecureScore = $assessment.Stats.SecureScore }
        foreach ($key in 'Findings', 'Settings', 'ConditionalAccess', 'NamedLocations', 'RoleAssignments', 'Registration', 'AuthenticationMethods', 'Licenses', 'IdentityProviders', 'Domains', 'SecureScoreControls', 'EnrollmentRestrictions', 'CompliancePolicies', 'EndpointSecurity', 'ManagedDevices', 'EntraDevices', 'MfaCoverage', 'EmergencyAccess', 'PrivilegedAccounts', 'AppCredentials', 'AppPermissions', 'RedirectUris', 'LegacyAuthentication', 'PimRoleSettings', 'GroupExposure', 'AccessReviews', 'RiskyUsers', 'RiskDetections', 'Incidents', 'InactiveUsers', 'AppProtection', 'Coverage', 'Permissions', 'Notices') { $result[$key] = @($assessment[$key]) }
        $result['Stats'] = [pscustomobject]$assessment.Stats
        [pscustomobject]$result
    }
}
