function ConvertTo-AACStorageContainerRow {
    <#
    .SYNOPSIS
        One container's blob tally (Read-AACBlobContainer) as the
        AAC.StorageContainerSize row Get-AACStorageAccountContainerSize
        returns - its sizes per tier, status, and why it failed with what to
        do about it.
    .DESCRIPTION
        -Item is @{ Account (the storage account); Container (the name, or
        $null for an account whose containers couldn't be listed); Url;
        PublicAccess; AuthMode; Tally (New-AACBlobTally, or $null); Error }.

        Status: OK (every page read), Partial (it failed after some pages:
        the numbers are what was read), Failed (nothing read). Azure
        Storage's error codes get the reason in plain words:
          AuthorizationPermissionMismatch  no data role for Entra ID
          AuthorizationFailure             the account's network rules
          KeyBasedAuthenticationNotPermitted  shared key access is off
          AuthenticationFailed             the token or SAS was refused
    #>
    [CmdletBinding()]
    [OutputType('AAC.StorageContainerSize')]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Item
    )

    $account = $Item.Account
    $tally = $Item.Tally
    $failure = [string]$Item.Error
    $status = if (-not $failure) { 'OK' } elseif ($tally -and $tally.Pages -gt 0) { 'Partial' } else { 'Failed' }
    if ($failure) {
        $hint = switch -Regex ($failure) {
            '^AuthorizationPermissionMismatch' { 'Your sign-in has no data access: give it Storage Blob Data Reader on the account (or its resource group or subscription), or run with -AuthMode Auto or AccountSas.'; break }
            '^AuthorizationFailure' {
                if ($account.Firewall -eq 'All networks') { 'Azure Storage refused the request - often a private endpoint only setup or a resource instance rule: run from a network the account allows.' }
                else { "The account's firewall refused this network ($($account.Firewall)): run from a network it allows, or add this one to its rules." }
                break
            }
            '^KeyBasedAuthenticationNotPermitted' { 'Shared key access is off for this account: read it with Entra ID and the Storage Blob Data Reader role (-AuthMode EntraId).'; break }
            '^AuthenticationFailed' { 'The token or SAS was refused: run Connect-AAC again, or check the account''s clock skew and SAS policy.'; break }
            'listKeys|listAccountSas|AuthorizationFailed' { 'Making an account SAS needs permission to list the account''s keys (Contributor, Storage Account Contributor).'; break }
            default { '' }
        }
        if ($hint) { $failure = "$failure $hint" }
    }

    $bytes = [long]0; $blobs = [long]0
    $tiers = @{}
    if ($tally) {
        $bytes = $tally.Bytes
        $blobs = $tally.Blobs
        $tiers = $tally.Tiers
    }
    $tierBytes = { param([string] $Name) if ($tiers[$Name]) { [long]$tiers[$Name][1] } else { [long]0 } }
    $known = (& $tierBytes 'Hot') + (& $tierBytes 'Cool') + (& $tierBytes 'Cold') + (& $tierBytes 'Archive')
    $total = $bytes + $(if ($tally) { $tally.SnapshotBytes + $tally.VersionBytes + $tally.DeletedBytes } else { 0 })
    $largest = @(if ($tally) { $tally.Largest | Sort-Object -Property Size -Descending })

    [pscustomobject]@{
        PSTypeName            = 'AAC.StorageContainerSize'
        StorageAccount        = $account.Name
        Container             = $Item.Container
        Status                = $status
        BlobCount             = $blobs
        Size                  = $bytes
        SizeText              = Format-AACByteSize -Bytes $bytes
        SizeHot               = & $tierBytes 'Hot'
        SizeCool              = & $tierBytes 'Cool'
        SizeCold              = & $tierBytes 'Cold'
        SizeArchive           = & $tierBytes 'Archive'
        SizeNoTier            = $bytes - $known
        Snapshots             = $(if ($tally) { $tally.Snapshots } else { [long]0 })
        SnapshotSize          = $(if ($tally) { $tally.SnapshotBytes } else { [long]0 })
        Versions              = $(if ($tally) { $tally.Versions } else { [long]0 })
        VersionSize           = $(if ($tally) { $tally.VersionBytes } else { [long]0 })
        DeletedBlobs          = $(if ($tally) { $tally.Deleted } else { [long]0 })
        DeletedSize           = $(if ($tally) { $tally.DeletedBytes } else { [long]0 })
        TotalSize             = $total
        TotalSizeText         = Format-AACByteSize -Bytes $total
        Directories           = $(if ($tally) { $tally.Directories } else { [long]0 })
        LastModified          = $(if ($tally) { $tally.LastModified } else { $null })
        PublicAccess          = $Item.PublicAccess
        AuthMode              = $Item.AuthMode
        Error                 = $failure
        ResourceGroup         = $account.ResourceGroup
        SubscriptionName      = $account.SubscriptionName
        SubscriptionId        = $account.SubscriptionId
        Location              = $account.Location
        Kind                  = $account.Kind
        Sku                   = $account.Sku
        HierarchicalNamespace = [bool]$account.Hns
        NetworkAccess         = $account.Firewall
        Url                   = $Item.Url
        StorageAccountId      = $account.Id
        LargestBlobs          = $largest
        Blobs                 = @(if ($tally -and $null -ne $tally.Rows) { $tally.Rows })
    }
}
