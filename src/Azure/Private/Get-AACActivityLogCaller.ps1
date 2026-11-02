function Get-AACActivityLogCaller {
    <#
    .SYNOPSIS
        Who called, from an Activity Log event's caller and token claims:
        a user, a guest, a service principal, a managed identity or Azure
        itself. Shared by Invoke-AACActivityLogAssessment and
        Show-AACActivityLogEvent.
    .DESCRIPTION
          Managed identity   the token names its resource (xms_mirid); Name
                             is that resource's name
          Service principal  an app token (idtyp app), or a GUID caller (the
                             service principal's object ID)
          Guest user         a UPN holding #EXT#
          User               any other UPN
          Azure platform     no caller (Azure's own operations)
          Other              a name that is none of these
        Returns @{ Kind; Name; Person ($true for users and guests) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()]
        [string] $Caller = '',

        [AllowEmptyString()]
        [string] $ManagedIdentity = '',

        [AllowEmptyString()]
        [string] $TokenType = '',

        [AllowEmptyString()]
        [string] $Upn = ''
    )

    $kind = if ($ManagedIdentity) { 'Managed identity' }
    elseif ($TokenType -eq 'app' -or $Caller -match '^[0-9a-fA-F-]{36}$') { 'Service principal' }
    elseif ($Caller -match '@') { if ("$Upn$Caller" -match '#EXT#') { 'Guest user' } else { 'User' } }
    elseif (-not $Caller) { 'Azure platform' }
    else { 'Other' }
    @{
        Kind   = $kind
        Name   = $(if ($ManagedIdentity) { ($ManagedIdentity.TrimEnd('/') -split '/')[-1] } elseif (-not $Caller) { 'Azure' } else { $Caller })
        Person = $kind -in 'User', 'Guest user'
    }
}
