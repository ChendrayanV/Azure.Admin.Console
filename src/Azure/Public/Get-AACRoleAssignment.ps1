function Get-AACRoleAssignment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Deprecated: use Get-AACAccessReview -View Assignment. Lists every Azure role assignment - root, management groups,
        subscriptions, resource groups and resources - with who holds it and
        what they are, what the role can do, how far it reaches, whether it
        is standing or PIM, the groups' members, who created it - and flags
        orphaned assignments, risky grants and custom roles that are unused
        or as powerful as Owner.
    .DESCRIPTION
        Deprecated, and to be removed in a later release: Get-AACAccessReview
        -View Assignment lists the same, with the same parameters (-Privileged
        there is -PrivilegedOnly). This command still works, and warns.

        The inventory under the access review: where Get-AACAccessReview
        says what to fix, this lists everything as it is. Reads, read-only:
          Resource Graph   every role assignment and definition (tenant-
                           wide, so management group and root assignments
                           that reach the scope count), the management
                           groups, the user-assigned identities and the
                           roles policies use
          PIM              each subscription's eligible assignments and
                           which active ones were activated just in time
          Microsoft Graph  the principals and the assignments' creators;
                           with -ExpandGroup, each group's members
                           (transitive)

        Each assignment (AAC.RoleAssignment):
          Principal        name, sign-in name, and its type: User, Guest,
                           Group, Application, Application (external - another
                           tenant's), Managed identity (system- or
                           user-assigned), or Deleted
          Role             name; Built-in or Custom; Privileged (Owner,
                           Contributor, User Access Administrator, RBAC
                           Administrator, or a custom role with every action
                           or able to grant access); CanWriteRoleAssignments
          Scope            type (Root, Management group, Subscription,
                           Resource group, Resource), name, and Reach - Direct,
                           or "Inherited by N subscription(s)"
          Assignment       Permanent, Activated (PIM) or Eligible (PIM)
          More             Members and MemberNames (groups, with
                           -ExpandGroup), Condition (ABAC), CreatedOn,
                           CreatedBy, EndsOn (eligible)
          Findings         and the worst one's Severity: High for a deleted
                           principal with a privileged role, a guest with
                           one, an application as Owner on a subscription or
                           above, a custom role equivalent to Owner; Medium for
                           orphaned assignments and Owner or User Access
                           Administrator given to a user directly; Low for
                           standing privileged access a person could hold
                           eligible
        The report also lists the custom roles (AAC.CustomRole): their
        assignments, whether a policy uses them, unused, equivalent to
        Owner, able to grant access.

        Reader on the scope; for Entra ID Directory.Read.All (GroupMember.
        Read.All for -ExpandGroup). What Graph or PIM refuses is left out,
        and said. -SkipEntra reads Azure only.
    .PARAMETER SubscriptionId
        Only these subscriptions (and the management group and root
        assignments that reach them).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER PrincipalType
        Only these principals: User, Guest, Group, Application,
        ManagedIdentity, Deleted.
    .PARAMETER RoleName
        Only these roles; wildcards work ('*Owner*').
    .PARAMETER ScopeType
        Only assignments at these scopes: Root, ManagementGroup,
        Subscription, ResourceGroup, Resource.
    .PARAMETER Privileged
        Only privileged roles.
    .PARAMETER WithFinding
        Only assignments with a finding.
    .PARAMETER ExpandGroup
        Read each group's members (transitive, up to 200 groups).
    .PARAMETER IncludeCustomRole
        Also return the custom roles (AAC.CustomRole), after the
        assignments.
    .PARAMETER SkipPim
        Don't read PIM (eligible and activated assignments).
    .PARAMETER SkipEntra
        Don't read Entra ID: principals are shown by ID and type.
    .PARAMETER CsvPath
        Write the assignments to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report (assignments and custom roles).
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the assignments.
    .PARAMETER NoDisplay
        Return the assignments without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACRoleAssignment
        Every role assignment the account can see, those with findings first.
    .EXAMPLE
        Get-AACRoleAssignment -SubscriptionId $sub -ExpandGroup -HtmlPath .\Rbac.html
        One subscription's assignments - including those inherited from management groups - with each group's members.
    .EXAMPLE
        Get-AACRoleAssignment -PrincipalType Guest, Deleted -Privileged -NoDisplay | Select-Object Principal, Role, Scope
        Privileged guests and orphaned privileged assignments.
    .EXAMPLE
        Get-AACRoleAssignment -RoleName 'Owner' -ScopeType ManagementGroup, Subscription -CsvPath .\Owners.csv
        Who is Owner at the top of the hierarchy, for review.
    .OUTPUTS
        AAC.RoleAssignment (and AAC.CustomRole, with -IncludeCustomRole)
    #>
    [CmdletBinding()]
    [OutputType('AAC.RoleAssignment')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('User', 'Guest', 'Group', 'Application', 'ManagedIdentity', 'Deleted')]
        [string[]] $PrincipalType,

        [SupportsWildcards()]
        [string[]] $RoleName,

        [ValidateSet('Root', 'ManagementGroup', 'Subscription', 'ResourceGroup', 'Resource')]
        [string[]] $ScopeType,

        [switch] $Privileged,

        [switch] $WithFinding,

        [switch] $ExpandGroup,

        [switch] $IncludeCustomRole,

        [switch] $SkipPim,

        [switch] $SkipEntra,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure role assignments',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    Write-Warning 'Get-AACRoleAssignment is deprecated and will be removed in a later release. Use Get-AACAccessReview -View Assignment, with the same parameters (-PrivilegedOnly for -Privileged).'
    Invoke-AACRoleAssignmentReport @PSBoundParameters -OutputPiped:$pipedOnward
}