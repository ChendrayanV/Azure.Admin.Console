function Get-AACApplicationPermission {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists every permission an enterprise application or managed identity
        holds - API permissions, delegated consents, Entra directory roles
        (and their scope), Azure roles, owned objects and groups - with
        findings for the privileged ones, as a Spectre.Console view,
        objects, and CSV, HTML and PDF reports.
    .DESCRIPTION
        Read-only. For each -Identity it finds the service principal - by
        object ID, application (client) ID, app registration object ID,
        display name, or an Azure resource ID of a user-assigned identity
        (or of a resource with a system-assigned one) - and reads, with
        Microsoft Graph and Azure Resource Graph:
          Application permission    each API's app roles granted to it
                                    (Microsoft Graph User.Read.All...) -
                                    tenant-wide, no user signed in
          Delegated permission      scopes consented for all users, or for
                                    one user
          Directory role            Entra roles: at tenant scope, on an
                                    administrative unit (with what the unit
                                    holds - New-AACApplicationPermission's
                                    scoped roles show here) or on one object;
                                    direct, or through a role-assignable group
          Directory role (eligible) the same through PIM
          Azure role                Azure RBAC, direct or through a group,
                                    with the scope in words (-SkipAzure
                                    leaves it out)
          Owner                     applications, service principals and
                                    groups it owns
          Group membership          the groups it is in
          Requested (not granted)   API permissions its app registration
                                    asks for without consent

        Findings: privileged application permissions (Directory.ReadWrite.All,
        RoleManagement.ReadWrite.Directory, AppRoleAssignment.ReadWrite.All,
        Mail.Send, Sites.FullControl.All...); privileged directory roles at
        tenant scope (Global Administrator, Privileged Role Administrator,
        Application Administrator...), any other role at tenant scope;
        Azure Owner and User Access Administrator, Contributor on a
        subscription or above; privileged delegated scopes consented for
        everyone; owning another application.

        The Entra admin center shows these in different places - API
        permissions only under the application's Permissions; directory
        roles under Roles & admins (and the administrative unit); Azure
        roles under each scope's Access control - this lists them together.

        Needs the Connect-AAC sign-in with read access to the directory
        (Directory Readers is enough). A part that can't be read is a
        notice, not an error. PIM-eligible roles need a Microsoft Graph
        token with RoleManagement.Read.Directory, which the client
        Connect-AAC uses by default can't get: sign in with
        Connect-AAC -ClientId <your app registration> (that delegated
        permission, admin-consented) to include them; everything else is
        listed either way.
    .PARAMETER Identity
        One or more: service principal object ID, application (client) ID,
        app registration object ID, display name, or the Azure resource ID
        of a managed identity (or of a resource with a system-assigned one).
    .PARAMETER SkipAzure
        Leave out Azure role assignments (no Resource Graph query).
    .PARAMETER View
        Permission (default), Finding or Summary: what is returned and
        written to -CsvPath.
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
        Get-AACApplicationPermission -Identity 'My-Enterprise-App'
        Everything the enterprise application can do, and what is privileged.
    .EXAMPLE
        Get-AACApplicationPermission -Identity 11111111-2222-3333-4444-555555555555 -NoDisplay | Where-Object Kind -EQ 'Directory role'
        By application (client) ID or object ID: its directory roles and their scope.
    .EXAMPLE
        Get-AACApplicationPermission -Identity '/subscriptions/<id>/resourceGroups/rg-app/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app'
        A user-assigned managed identity, by its Azure resource ID.
    .EXAMPLE
        'app-one', 'app-two', 'func-myapp-prod' | Get-AACApplicationPermission -HtmlPath .\AppPermissions.html -CsvPath .\AppPermissions.csv
        Several at once, as reports.
    .OUTPUTS
        AAC.ApplicationPermissionEntry, AAC.ApplicationPermissionFinding or AAC.ApplicationPermissionSummary, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ApplicationPermissionEntry', 'AAC.ApplicationPermissionFinding', 'AAC.ApplicationPermissionSummary')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ServicePrincipal', 'AppId', 'ObjectId', 'ServicePrincipalId', 'PrincipalId', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Identity,

        [switch] $SkipAzure,

        [ValidateSet('Permission', 'Finding', 'Summary')]
        [string] $View = 'Permission',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Application permissions',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $wanted = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($entry in $Identity) { if ($entry -and -not $wanted.Contains($entry)) { $wanted.Add($entry) } }
    }
    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }

        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Application permissions' -Color 'mediumpurple' }
        $state = Invoke-AACProgress -ScriptBlock {
            $rows = [System.Collections.Generic.List[object]]::new()
            $findings = [System.Collections.Generic.List[object]]::new()
            $summaries = [System.Collections.Generic.List[object]]::new()
            $notices = [System.Collections.Generic.List[string]]::new()
            Update-AACProgress -Id 'read' -Total $wanted.Count -Description "Reading $($wanted.Count) application(s)"
            foreach ($one in $wanted) {
                Update-AACProgress -Id 'read' -Description "Reading $one"
                try { $read = Read-AACApplicationPermission -Identity $one -SkipAzure:$SkipAzure }
                catch {
                    # One that can't be found doesn't stop the others.
                    if ($wanted.Count -eq 1) { throw }
                    $notices.Add("$one was left out: $($_.Exception.Message)")
                    Update-AACProgress -Id 'read' -Increment 1
                    continue
                }
                $result = ConvertTo-AACApplicationPermission -Read $read
                $rows.AddRange([object[]]@($result.Rows))
                $findings.AddRange([object[]]@($result.Findings))
                $summaries.Add($result.Summary)
                foreach ($problem in $read.Errors) { $notices.Add("$($result.Summary.Principal): $problem") }
                Update-AACProgress -Id 'read' -Increment 1
            }
            if (-not $summaries.Count) { throw "Azure Admin Console couldn't read any of the applications. $($notices -join ' ')" }
            Update-AACProgress -Id 'read' -Complete -Description "Read $($summaries.Count) application(s): $($rows.Count) permission(s), $($findings.Count) finding(s)"
            @{ Rows = $rows.ToArray(); Findings = $findings.ToArray(); Summaries = $summaries.ToArray(); Notices = $notices.ToArray() }
        }

        # --- Report ----------------------------------------------------------------------------------------------------
        $rows = @($state.Rows)
        $multi = @($state.Summaries).Count -gt 1
        $rank = Get-AACSeverityRank
        $high = @($state.Findings | Where-Object Severity -EQ 'High').Count
        $count = { param([string] $Kind) @($rows | Where-Object { $_.Kind -like $Kind }).Count }
        $kindTones = @{ 'Application permission' = 'warn'; 'Delegated permission' = 'info'; 'Directory role' = 'violet'; 'Directory role (eligible)' = 'violet'; 'Azure role' = 'info'; Owner = 'warn'; 'Group membership' = 'neutral'; 'Requested (not granted)' = 'neutral' }
        $first = @($state.Summaries)[0]
        $report = @{
            Subtitle = $(if ($multi) { "$(@($state.Summaries).Count) applications" } else { "$($first.Principal) ($($first.Type))" })
            Facts    = [ordered]@{
                Applications = (@($state.Summaries | ForEach-Object { "$($_.Principal) ($($_.Type); object $($_.PrincipalId); app $($_.AppId))" }) -join '; ')
                Azure        = $(if ($SkipAzure) { 'left out (-SkipAzure)' } else { 'Azure role assignments included' })
                Generated    = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
            }
            Status   = $(if ($high) { 'Failed' } elseif (@($state.Findings).Count) { 'Warning' } else { 'Success' })
            Headline = "$($rows.Count) permission(s): $(& $count 'Application permission') application, $(& $count 'Delegated permission') delegated, $(& $count 'Directory role*') directory role(s), $(& $count 'Azure role') Azure role(s), $(& $count 'Owner') owned object(s); $high high finding(s)"
            Tiles    = @(
                @{ Value = '{0:N0}' -f (& $count 'Application permission'); Label = 'application permissions'; Tone = 'warn'; Table = 'permissions'; Filters = @{ Kind = 'Application permission' } }
                @{ Value = '{0:N0}' -f (& $count 'Delegated permission'); Label = 'delegated permissions'; Tone = 'info'; Table = 'permissions'; Filters = @{ Kind = 'Delegated permission' } }
                @{ Value = '{0:N0}' -f (& $count 'Directory role*'); Label = 'directory roles'; Tone = 'violet'; Table = 'permissions'; Filters = @{ Kind = 'Directory role' } }
                @{ Value = '{0:N0}' -f (& $count 'Azure role'); Label = 'Azure roles'; Tone = 'info'; Table = 'permissions'; Filters = @{ Kind = 'Azure role' } }
                @{ Value = '{0:N0}' -f $high; Label = 'high findings'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
            )
            Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
            Charts   = @(
                @{ Title = 'Permissions by kind'; Kind = 'donut'; CenterLabel = 'permissions'; Items = @($rows | Group-Object -Property Kind | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $kindTones[$_.Name]; Filter = $_.Name } }); Table = 'permissions'; Column = 'Kind'; Console = $true }
            )
            Tabs     = @(
                @{ Name = 'Permissions'; Badge = $rows.Count; Tone = 'info'; Note = 'Every permission: API permissions, consents, directory roles with their scope, Azure roles, owned objects and groups.' }
                @{ Name = 'Findings'; Badge = @($state.Findings).Count; Tone = $(if ($high) { 'bad' } else { 'warn' }); Note = 'The privileged ones, worst first, and what to do.' }
                @{ Name = 'Applications'; Badge = @($state.Summaries).Count; Tone = 'violet'; Note = 'Each application or managed identity, with its counts.' }
            )
            Tables   = @(
                @{ Id = 'permissions'; Title = 'Permissions'; Section = 'Permissions'; Rows = $rows; Noun = 'permissions'; GroupBy = @('Kind', 'Api', 'Principal'); ConsoleLimit = 40
                    Empty = 'No permissions.'; EmptyStatus = 'Info'
                    Columns = @(
                        @{ Key = 'Principal'; Label = 'Application'; Facet = $true; Console = $multi; Pdf = $multi }
                        @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Api'; Label = 'API or service'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Permission'; Label = 'Permission or role'; Console = $true; Pdf = $true }
                        @{ Key = 'Scope'; Label = 'Scope'; Console = $true; Pdf = $true }
                        @{ Key = 'Via'; Label = 'Via'; Facet = $true; Console = $true }
                        @{ Key = 'Privileged'; Label = 'Privileged'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'Since'; Label = 'Since'; Type = 'datetime' }
                        @{ Key = 'Id'; Label = 'ID'; Type = 'mono' }
                    ) }
                @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($state.Findings); Noun = 'findings'; GroupBy = @('Finding', 'Severity'); ConsoleLimit = 25
                    Empty = 'Nothing privileged.'; EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Principal'; Label = 'Application'; Facet = $true; Console = $multi; Pdf = $multi }
                        @{ Key = 'Item'; Label = 'Permission'; Console = $true; Pdf = $true }
                        @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Console = $true; Pdf = $true }
                    ) }
                @{ Id = 'applications'; Title = 'Applications'; Section = 'Applications'; Rows = @($state.Summaries); Noun = 'applications'; ConsoleLimit = 20
                    Columns = @(
                        @{ Key = 'Principal'; Label = 'Application'; Type = 'resource'; Console = $true; Pdf = $true }
                        @{ Key = 'Type'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'ApplicationPermissions'; Label = 'Application'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'DelegatedPermissions'; Label = 'Delegated'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'DirectoryRoles'; Label = 'Directory roles'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'AzureRoles'; Label = 'Azure roles'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Owned'; Label = 'Owns'; Type = 'number' }
                        @{ Key = 'NotGranted'; Label = 'Not granted'; Type = 'number' }
                        @{ Key = 'High'; Label = 'High'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'AppId'; Label = 'App ID'; Type = 'mono' }
                        @{ Key = 'PrincipalId'; Label = 'Object ID'; Type = 'mono' }
                    ) }
            )
            Hint     = '-View Finding or Summary returns those rows; -SkipAzure leaves out Azure roles; New-AACApplicationPermission scopes group rights to an administrative unit.'
        }
        $out = @(switch ($View) { 'Finding' { $state.Findings } 'Summary' { $state.Summaries } default { $rows } })
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $out -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $out -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
