function Get-AACEntraGroupMembership {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Who is in your Entra ID groups - direct members and everyone in the
        groups nested in them - flattened to one row per group and member,
        with a Spectre.Console view, objects, and CSV, PDF and interactive
        HTML reports.
    .DESCRIPTION
        Reads the groups and their members from Microsoft Graph, following
        nested groups to the end (a loop is followed once):
          -GroupName            these groups, by exact display name
          -GroupNameStartsWith  every group whose name starts with this
          neither               every group in the tenant
        Both can be given together.

        It uses the Connect-AAC sign-in - no second prompt: a Microsoft Graph
        token is taken from it silently, as other APIs' tokens are. Your
        account needs to be allowed to read groups in Entra ID, which members
        of the tenant are by default. With an App Registration of your own
        (Connect-AAC -ClientId), give it Microsoft Graph's delegated
        Group.Read.All and User.Read.All permissions. Nothing is written to
        Entra ID.

        One row per member of each group (AAC.EntraGroupMember): GroupName,
        GroupType (Microsoft 365, Security, Mail-enabled security,
        Distribution - dynamic, role-assignable), GroupSource (Cloud, or
        synced from on-premises AD), MemberName, MemberType (User, Group,
        Device, Service principal, Contact), UserPrincipalName, Mail,
        UserType (Member or Guest), AccountEnabled, JobTitle, Department,
        Membership (Direct, Nested, or Empty for a group with no members),
        Via (the nested path, 'Group > Nested group'), Depth, GroupId and
        MemberId. The same rows go to CSV, HTML and PDF.

        What you get depends on where the command runs:
          at the prompt    tiles, each group's type, source and counts, and
                           each group's members as a tree (nested groups
                           under their group) - a page at a time
          piped onward     the rows, with no view
          -PassThru        the view and the rows
          -NoDisplay       the rows only
        -CsvPath writes the rows. -HtmlPath writes an interactive report:
        tiles and charts that filter the tables, a table of groups and one of
        every membership - searchable, filterable by group, member type,
        guest or member, direct or nested, and downloadable as CSV. -PdfPath
        writes a PDF: the summary, the groups, and each group's members.
        With any of them, the console shows only the progress and the files
        written.
    .PARAMETER GroupName
        The display names of the groups to report on (exact matches). Alias:
        GroupNames.
    .PARAMETER GroupNameStartsWith
        Report on every group whose display name starts with this.
    .PARAMETER CsvPath
        Write every row to this CSV file. Alias: OutputPath.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-hr'
        Two groups, with everyone in them, direct or nested.
    .EXAMPLE
        Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-azure-' -HtmlPath .\out\Groups.html -CsvPath .\out\Groups.csv
        Every group whose name starts with 'grp-azure-', as an interactive HTML report and a CSV file.
    .EXAMPLE
        Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -NoDisplay | Where-Object { $_.UserType -eq 'Guest' }
        The guests in those groups, and through which group.
    .EXAMPLE
        Connect-AAC
        Get-AACEntraGroupMembership -PdfPath .\out\Groups.pdf
        Every group in the tenant you signed in to, as a PDF report.
    .OUTPUTS
        AAC.EntraGroupMember (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.EntraGroupMember')]
    param(
        [Alias('GroupNames')]
        [ValidateNotNullOrEmpty()]
        [string[]] $GroupName,

        [ValidateNotNullOrEmpty()]
        [string] $GroupNameStartsWith,

        [Alias('OutputPath')]
        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Entra ID group membership',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Entra ID group membership' -Color 'deepskyblue3_1'
    }
    # The Connect-AAC sign-in, for Microsoft Graph: fails here, clearly, when
    # there is none or it can't give a Graph token.
    $null = Get-AACAccessToken -Resource 'https://graph.microsoft.com'

    $state = Invoke-AACProgress -ScriptBlock {
        $read = Read-AACEntraGroup -GroupName @($GroupName | Where-Object { $_ }) -GroupNameStartsWith $GroupNameStartsWith
        foreach ($name in $read.Missing) { Write-Warning "No group named '$name' was found; it's left out." }
        if (-not $read.Groups.Count) {
            $asked = @(@($GroupName | Where-Object { $_ } | ForEach-Object { "'$_'" }) + @(if ($GroupNameStartsWith) { "starting with '$GroupNameStartsWith'" }))
            throw $(if ($asked.Count) { "No group $($asked -join ' or ') was found. Group names are matched exactly (-GroupName) or by their start (-GroupNameStartsWith)." } else { 'No groups were found in the tenant.' })
        }

        Update-AACProgress -Id 'flatten' -Indeterminate -Description 'Flattening the memberships'
        $membership = ConvertTo-AACGroupMembership -Group $read.Groups -Member $read.Members -MemberError $read.MemberErrors
        $stats = $membership.Stats
        Update-AACProgress -Id 'flatten' -Complete -Description ('{0:N0} group(s): {1:N0} membership row(s), {2:N0} unique user(s) - {3:N0} guest(s), {4:N0} disabled' -f $stats.Groups, $stats.Rows, $stats.Users, $stats.Guests, $stats.Disabled)

        $scope = [ordered]@{}
        if ($script:AACSession) { $scope['Signed in as'] = [string]$script:AACSession.Account; $scope['Tenant'] = [string]$script:AACSession.TenantId }
        $scope['Groups'] = @(
            if ($GroupName) { "named $(($GroupName | ForEach-Object { "'$_'" }) -join ', ')" }
            if ($GroupNameStartsWith) { "starting with '$GroupNameStartsWith'" }
        ) -join '; '
        if (-not $scope['Groups']) { $scope['Groups'] = 'every group in the tenant' }
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($membership.Rows) -Noun 'membership row' -PdfPath $pdfFullPath -WritePdf {
            Write-AACGroupMembershipPdf -Membership $membership -Path $pdfFullPath -Title $Title -Detail $scope
        } -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACGroupMembershipHtml -Membership $membership -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Membership = $membership; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACGroupMembershipView -Membership $state.Membership -Scope $state.Scope
        }
    }
    if ($returnObjects) {
        $state.Membership.Rows
    }
}
