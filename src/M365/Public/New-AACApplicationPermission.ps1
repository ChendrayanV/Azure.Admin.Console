function New-AACApplicationPermission {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lets an enterprise application or managed identity manage specific
        Entra groups only - not every group in the tenant - with an
        administrative unit, a custom (or built-in) directory role and a
        role assignment scoped to the unit. Plan, confirm, apply, verify.
    .DESCRIPTION
        Microsoft Graph application permissions are tenant-wide:
        GroupMember.ReadWrite.All lets an application add and remove
        members in every group, and there is no "selected groups" version
        of it (as Sites.Selected is for SharePoint). The same rights, over
        chosen groups only:
          1. Administrative unit   holds exactly the groups
                                   (-AdministrativeUnitName; created when
                                   missing, -RestrictedManagement on creation)
          2. Directory role        only the group actions (-Access, or your
                                   own -AllowedResourceAction); a custom role
                                   (-RoleName) is created, or updated when its
                                   actions differ; a built-in role is used as
                                   it is
          3. Role assignment       the role to the application, scoped to the
                                   administrative unit - not '/'
        The application's code doesn't change: it still asks for a
        https://graph.microsoft.com/.default token and calls
        POST /groups/{id}/members/$ref. Any other group answers 403.

        Like Deploy-AACStorageAccount, it plans first - what exists is read
        and only what is missing is written - and shows the plan. Findings
        say what would undo the scope: a tenant-wide Graph permission
        (GroupMember.ReadWrite.All, Group.ReadWrite.All,
        Directory.ReadWrite.All - removed with -RemoveTenantWidePermission),
        the same role at tenant scope, other objects in the unit, dynamic or
        role-assignable groups. You are asked before anything is written
        (-Force, or -Confirm:$false, for pipelines); -WhatIf stops after the
        plan. After the apply everything is read again: running the same
        command again plans no changes.

        Needs the Connect-AAC sign-in with Privileged Role Administrator
        (or Global Administrator) - a service principal needs the Graph
        permissions RoleManagement.ReadWrite.Directory,
        AdministrativeUnit.ReadWrite.All, Application.Read.All and
        Group.Read.All, and AppRoleAssignment.ReadWrite.All for
        -RemoveTenantWidePermission. Custom roles and administrative units
        need Microsoft Entra ID P1. An application may cache its token for
        up to an hour (a managed identity up to 24 hours) before the change
        takes effect.
    .PARAMETER ServicePrincipal
        The enterprise application or managed identity: its object ID, its
        application (client) ID, or its display name.
    .PARAMETER Group
        The groups the application may manage, by display name or object ID.
    .PARAMETER Access
        What the application may do in the groups:
          MemberReadWrite          read the groups and their members, add
                                   and remove members (default - the same
                                   rights as GroupMember.ReadWrite.All)
          MemberRead               read the groups and their members
          MemberAndOwnerReadWrite  members and owners
    .PARAMETER AllowedResourceAction
        A custom role's actions instead of -Access, e.g.
        microsoft.directory/groups/members/update. Only group actions
        (microsoft.directory/groups...) can be given.
    .PARAMETER RoleName
        The directory role: a custom role's name (created when missing), or
        a built-in role's (Groups Administrator...). By default
        'Group access (scoped) - <application>'.
    .PARAMETER AdministrativeUnitName
        The administrative unit (created when missing). By default
        'AU-<application>-Managed-Groups'.
    .PARAMETER RestrictedManagement
        Create the administrative unit with restricted management, so that
        tenant-wide group administrators can't change its groups either.
        Can only be chosen when the unit is created.
    .PARAMETER RemoveTenantWidePermission
        Remove the application's tenant-wide Graph permissions that would
        override the scope (GroupMember.ReadWrite.All, Group.ReadWrite.All,
        Directory.ReadWrite.All).
    .PARAMETER Force
        Apply without asking.
    .PARAMETER PassThru
        Show the plan and also return the result.
    .PARAMETER NoDisplay
        Return the result without showing the plan.
    .EXAMPLE
        New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -WhatIf
        The plan: what would be created, and what would undo the scope.
    .EXAMPLE
        New-AACApplicationPermission -ServicePrincipal 'func-myapp-prod' -Group 'SG-Group-One' -RemoveTenantWidePermission
        A managed identity (its Function App's name) gets member read/write on one group, and loses GroupMember.ReadWrite.All.
    .EXAMPLE
        New-AACApplicationPermission -ServicePrincipal 11111111-2222-3333-4444-555555555555 -Group 'SG-Group-One' -AllowedResourceAction 'microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read' -RoleName 'Group Member Reader (Scoped)'
        A custom role of your own, for an application found by its ID.
    .EXAMPLE
        New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -RoleName 'Groups Administrator' -Force -NoDisplay
        A built-in role, scoped to the unit, in a pipeline.
    .OUTPUTS
        AAC.ApplicationPermission (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Access')]
    [OutputType('AAC.ApplicationPermission')]
    param(
        [Parameter(Mandatory)]
        [Alias('ServicePrincipalName', 'ServicePrincipalId', 'AppId')]
        [ValidateNotNullOrEmpty()]
        [string] $ServicePrincipal,

        [Parameter(Mandatory)]
        [Alias('GroupName', 'GroupId')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Group,

        [Parameter(ParameterSetName = 'Access')]
        [ValidateSet('MemberReadWrite', 'MemberRead', 'MemberAndOwnerReadWrite')]
        [string] $Access = 'MemberReadWrite',

        [Parameter(Mandatory, ParameterSetName = 'Custom')]
        [ValidateNotNullOrEmpty()]
        [string[]] $AllowedResourceAction,

        [string] $RoleName,

        [string] $AdministrativeUnitName,

        [switch] $RestrictedManagement,

        [switch] $RemoveTenantWidePermission,

        [switch] $Force,

        [switch] $PassThru,

        [switch] $NoDisplay
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward

    # The actions of each -Access: the directory's own names, as the Entra admin center lists them.
    $presets = @{
        MemberReadWrite         = @('microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read', 'microsoft.directory/groups/members/update')
        MemberRead              = @('microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read')
        MemberAndOwnerReadWrite = @('microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read', 'microsoft.directory/groups/members/update', 'microsoft.directory/groups/owners/read', 'microsoft.directory/groups/owners/update')
    }
    $actions = if ($PSCmdlet.ParameterSetName -eq 'Custom') { @($AllowedResourceAction | Where-Object { $_ } | ForEach-Object { $_.Trim() }) } else { $presets[$Access] }
    foreach ($action in $actions) {
        if ($action -notmatch '^microsoft\.directory/groups(\.[A-Za-z]+)?/[A-Za-z./]+$') {
            throw "Azure Admin Console can't scope the action '$action' to the groups: give group actions only, e.g. microsoft.directory/groups/members/update."
        }
    }
    $request = @{
        ServicePrincipal = $ServicePrincipal; Group = $Group; AllowedResourceAction = $actions; RoleName = $RoleName; AdministrativeUnitName = $AdministrativeUnitName
        RestrictedManagement = [bool]$RestrictedManagement; RemoveTenantWidePermission = [bool]$RemoveTenantWidePermission
    }
    # The report model of a plan, or of an apply.
    $view = {
        param([hashtable] $Plan, [object[]] $Applied, [string] $Status)
        $actionTones = @{ Create = 'good'; Add = 'good'; Assign = 'good'; Update = 'warn'; Remove = 'bad'; NoChange = 'neutral' }
        $statusTones = @{ Applied = 'good'; Failed = 'bad'; Skipped = 'neutral' }
        $high = @($Plan.Findings | Where-Object Severity -EQ 'High').Count
        @{
            Subtitle = "Microsoft Entra ID - $($Plan.Principal.DisplayName)"
            Facts    = [ordered]@{ Application = "$($Plan.Principal.DisplayName) ($($Plan.Principal.Type), $($Plan.Principal.Id))"; Groups = (@($Plan.Groups | ForEach-Object { $_.DisplayName }) -join ', '); 'Administrative unit' = $Plan.AdministrativeUnit.DisplayName; Role = "$($Plan.Role.DisplayName)$(if ($Plan.Role.BuiltIn) { ' (built-in)' })"; Actions = ($Plan.Actions -join ', ') }
            Status   = $(if ($Status -eq 'Failed' -or $high) { 'Failed' } elseif ($Plan.Findings.Count) { 'Warning' } else { 'Success' })
            Headline = $(switch ($Status) {
                    'Applied' { "Applied $(@($Applied | Where-Object Status -EQ 'Applied').Count) change(s): $($Plan.Principal.DisplayName) can manage $(@($Plan.Groups).Count) group(s) only" }
                    'Failed' { "A change failed - $(@($Applied | Where-Object Status -EQ 'Applied').Count) applied before it" }
                    'NoChanges' { "No changes: $($Plan.Principal.DisplayName) already holds $($Plan.Role.DisplayName) on $($Plan.AdministrativeUnit.DisplayName)" }
                    default { "Plan: $($Plan.Writes) change(s) so that $($Plan.Principal.DisplayName) can manage $(@($Plan.Groups).Count) group(s) only" }
                })
            Tiles    = @(
                @{ Value = '{0:N0}' -f $Plan.Writes; Label = 'changes'; Tone = 'info'; Table = 'changes' }
                @{ Value = '{0:N0}' -f @($Plan.Groups).Count; Label = 'groups in scope'; Tone = 'good' }
                @{ Value = '{0:N0}' -f $high; Label = 'high findings'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'findings' }
            )
            Tables   = @(
                @{ Id = 'changes'; Title = 'Plan'; Rows = @($Plan.Changes); Noun = 'changes'; ConsoleLimit = 30
                    Columns = @(
                        @{ Key = 'Order'; Label = '#'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Action'; Label = 'Action'; Type = 'badge'; Tones = $actionTones; Console = $true; Pdf = $true }
                        @{ Key = 'Resource'; Label = 'Resource'; Console = $true; Pdf = $true }
                        @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Console = $true; Pdf = $true }
                    ) }
                if ($Applied) {
                    @{ Id = 'applied'; Title = 'Applied'; Rows = @($Applied); Noun = 'changes'; ConsoleLimit = 30
                        Columns = @(
                            @{ Key = 'Order'; Label = '#'; Type = 'number'; Console = $true; Pdf = $true }
                            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Console = $true; Pdf = $true }
                            @{ Key = 'Resource'; Label = 'Resource'; Console = $true; Pdf = $true }
                            @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Console = $true; Pdf = $true }
                        ) }
                }
                @{ Id = 'findings'; Title = 'Findings'; Rows = @($Plan.Findings); Noun = 'findings'; ConsoleLimit = 20; Empty = 'Nothing undoes the scope.'; EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = (Get-AACSeverityRank).Tone; Console = $true; Pdf = $true }
                        @{ Key = 'Item'; Label = 'Item'; Console = $true; Pdf = $true }
                        @{ Key = 'Finding'; Label = 'Finding'; Console = $true; Pdf = $true }
                        @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Console = $true; Pdf = $true }
                    ) }
            )
            Hint     = '-WhatIf shows the plan only; -RemoveTenantWidePermission removes the Graph permissions that override the scope; -Force applies without asking.'
        }
    }
    $show = { param([hashtable] $Plan, [object[]] $Applied, [string] $Status) if ($interactive) { $WhatIfPreference = $false; Invoke-AACReportOutput -Report (& $view $Plan $Applied $Status) -Title 'Application permission' -ShowView -NoPaging } }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Application permission' -Color 'mediumpurple' }

    # --- Plan ------------------------------------------------------------------------------------------------------
    $plan = Invoke-AACProgress -ScriptBlock {
        # The plan only reads: -WhatIf is for the apply below.
        $WhatIfPreference = $false
        Update-AACProgress -Id 'plan' -Indeterminate -Description 'Reading the application, the groups, the unit, the role and its assignments'
        $result = Get-AACApplicationPermissionPlan @request
        Update-AACProgress -Id 'plan' -Complete -Description "Plan: $($result.Writes) change(s), $(@($result.Findings).Count) finding(s)"
        $result
    }

    # --- Decide, apply, verify -------------------------------------------------------------------------------------
    $applied = @()
    $verification = @()
    $target = "$($plan.Principal.DisplayName): $($plan.Role.DisplayName) on $($plan.AdministrativeUnit.DisplayName)"
    if (-not $plan.Writes) {
        $status = 'NoChanges'
        & $show $plan @() $status
    }
    elseif ($WhatIfPreference) {
        & $show $plan @() 'Planned'
        $null = $PSCmdlet.ShouldProcess($target, "Apply $($plan.Writes) change(s)")
        $status = 'Planned'
    }
    else {
        & $show $plan @() 'Planned'
        if ($Force -or $PSCmdlet.ShouldProcess($target, "Apply $($plan.Writes) change(s)")) {
            $outcome = Invoke-AACProgress -ScriptBlock {
                $rows = Invoke-AACApplicationPermissionPlan -Change $plan.Changes
                $again = @()
                if (-not @($rows | Where-Object Status -EQ 'Failed').Count) {
                    Update-AACProgress -Id 'verify' -Indeterminate -Description 'Verifying: reading everything again'
                    $again = @((Get-AACApplicationPermissionPlan @request).Changes | Where-Object { $_.Action -ne 'NoChange' })
                    Update-AACProgress -Id 'verify' -Complete -Description $(if ($again.Count) { "Verified: $($again.Count) change(s) still to make - Entra may still be replicating; run again in a minute" } else { 'Verified: nothing left to change' })
                }
                @{ Rows = $rows; Again = $again }
            }
            $applied = @($outcome.Rows)
            $verification = @($outcome.Again)
            $status = if (@($applied | Where-Object Status -EQ 'Failed').Count) { 'Failed' } else { 'Applied' }
            & $show $plan $applied $status
            if ($status -eq 'Failed') {
                $failure = @($applied | Where-Object Status -EQ 'Failed')[0]
                $problem = [System.InvalidOperationException]::new("$($failure.Resource) couldn't be changed: $($failure.Detail)")
                $problem.Data['AACHint'] = "$(@($applied | Where-Object Status -EQ 'Applied').Count) change(s) before it were applied and stay; fix the cause (a 403 means the sign-in lacks Privileged Role Administrator) and run again - it carries on from there."
                throw $problem
            }
        }
        else { $status = 'Declined' }
    }

    if ($returnObjects) {
        [pscustomobject]@{
            PSTypeName           = 'AAC.ApplicationPermission'
            Status               = $status
            ServicePrincipal     = $plan.Principal.DisplayName
            ServicePrincipalId   = $plan.Principal.Id
            AppId                = $plan.Principal.AppId
            Groups               = @($plan.Groups | ForEach-Object { $_.DisplayName })
            AdministrativeUnit   = $plan.AdministrativeUnit.DisplayName
            AdministrativeUnitId = $(if ($plan.AdministrativeUnit.Id) { $plan.AdministrativeUnit.Id } else { [string](@($applied | Where-Object { $_.Resource -like 'Administrative unit *' -and $_.Status -eq 'Applied' }) | ForEach-Object { $_.Detail -replace '^ID ', '' } | Select-Object -First 1) })
            Role                 = $plan.Role.DisplayName
            Actions              = $plan.Actions
            Writes               = $plan.Writes
            Changes              = $plan.Changes
            Findings             = $plan.Findings
            Applied              = $applied
            Verification         = $verification
        }
    }
}
