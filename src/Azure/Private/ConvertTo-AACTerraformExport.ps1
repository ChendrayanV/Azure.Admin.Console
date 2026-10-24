function ConvertTo-AACTerraformExport {
    <#
    .SYNOPSIS
        Shapes what Export-AACTerraform exported - folder by folder - into
        one row per Azure resource (AAC.TerraformExportResource) and one
        object per folder (AAC.TerraformExport), with the totals.
    .DESCRIPTION
        -Folder takes, for each folder written: Path, Label, SubscriptionId,
        Subscription, Provider, Imports (from ConvertTo-AACTerraformFile),
        Skipped (the IDs no export could do), FallbackTried, Errors (the
        export's ErrorDetail list), Files, OperationId, Duration, Plan,
        Batches (how many exports it was split into), Duplicates (resources
        two batches both returned, kept once), Planned (the resources
        Resource Graph counted beforehand), Pending (still running: collect
        it later with -Resume) and Failure (why the folder has nothing).

        Rows:
          Exported  a Terraform address for an Azure resource
          Skipped   no Terraform support in the provider - with what to try
          Error     an error the export reported for a resource
          Failed    the whole export of a scope failed (provider not
                    registered, no resources, access denied...)
          Running   the export was still running when the command stopped
                    waiting
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Folder
    )

    # The Azure type from a resource ID: Microsoft.Network/virtualNetworks/subnets.
    $typeOf = {
        param([string] $Id)
        $parts = @((($Id -split '\?')[0]).Trim('/') -split '/')
        $at = [Array]::FindLastIndex([string[]]$parts, [Predicate[string]] { param($p) $p -ieq 'providers' })
        if ($at -ge 0 -and $at + 2 -lt $parts.Count) {
            $types = for ($k = $at + 2; $k -lt $parts.Count; $k += 2) { $parts[$k] }
            return "$($parts[$at + 1])/$($types -join '/')"
        }
        if ($parts.Count -eq 4 -and $parts[2] -ieq 'resourceGroups') { return 'Microsoft.Resources/resourceGroups' }
        if ($parts.Count -eq 2 -and $parts[0] -ieq 'subscriptions') { return 'Microsoft.Resources/subscriptions' }
        ''
    }
    $groupOf = { param([string] $Id) $m = [regex]::Match($Id, '/resourceGroups/([^/?]+)', 'IgnoreCase'); if ($m.Success) { $m.Groups[1].Value } else { '' } }
    $nameOf = { param([string] $Id) @((($Id -split '\?')[0]).TrimEnd('/') -split '/')[-1] }

    $rows = [System.Collections.Generic.List[object]]::new()
    $folders = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $Folder) {
        $mine = [System.Collections.Generic.List[object]]::new()
        $row = {
            param([string] $Status, [string] $Id, [string] $Address, [string] $Provider, [string] $File, [string] $Note)
            $mine.Add([pscustomobject][ordered]@{
                    PSTypeName    = 'AAC.TerraformExportResource'
                    Status        = $Status
                    Address       = $Address
                    TerraformType = $(if ($Address) { ($Address -split '\.')[0] } else { '' })
                    ResourceType  = $(if ($Id) { & $typeOf $Id } else { '' })
                    Name          = $(if ($Id) { & $nameOf $Id } else { '' })
                    ResourceGroup = $(if ($Id) { & $groupOf $Id } else { '' })
                    Subscription  = [string]$f.Subscription
                    Provider      = $Provider
                    File          = $File
                    Folder        = [string]$f.Path
                    Note          = $Note
                    ResourceId    = (($Id -split '\?')[0])
                })
        }
        if ($f.Pending) {
            & $row 'Running' ([string]$f.Label) '' ([string]$f.Provider) '' ([string]$f.Failure)
        }
        elseif ($f.Failure) {
            & $row 'Failed' ([string]$f.Label) '' ([string]$f.Provider) '' ([string]$f.Failure)
        }
        else {
            foreach ($import in @($f.Imports)) { & $row 'Exported' ([string]$import.Id) ([string]$import.Address) ([string]$import.Provider) ([string]$import.File) '' }
            $hint = if ($f.FallbackTried) { 'Not supported by the azapi provider either.' } elseif ($f.Provider -eq 'azurerm') { 'No azurerm support for this type - -FallbackToAzApi exports it with the azapi provider.' } else { 'The provider has no support for this type.' }
            foreach ($id in @($f.Skipped | Where-Object { $_ })) { & $row 'Skipped' ([string]$id) '' ([string]$f.Provider) '' $hint }
            foreach ($e in @($f.Errors | Where-Object { $_ })) {
                $message = if ($e -is [System.Collections.IDictionary]) { "$($e['code']): $($e['message'])".Trim(': ') } else { [string]$e }
                $target = if ($e -is [System.Collections.IDictionary]) { [string]$e['target'] } else { '' }
                & $row 'Error' $target '' ([string]$f.Provider) '' $message
            }
        }
        $rows.AddRange([object[]]$mine.ToArray())

        $count = { param([string] $Status) @($mine | Where-Object { $_.Status -eq $Status }).Count }
        $exported = & $count 'Exported'
        $folders.Add([pscustomobject][ordered]@{
                PSTypeName     = 'AAC.TerraformExport'
                Status         = $(if ($f.Pending) { 'Running' } elseif ($f.Failure) { 'Failed' } elseif ((& $count 'Skipped') -or (& $count 'Error')) { 'Partial' } else { 'Exported' })
                Path           = [string]$f.Path
                Scope          = [string]$f.Label
                Subscription   = [string]$f.Subscription
                SubscriptionId = [string]$f.SubscriptionId
                Provider       = [string]$f.Provider
                Exported       = $exported
                Skipped        = & $count 'Skipped'
                Errors         = & $count 'Error'
                Files          = @($f.Files)
                Plan           = $f.Plan
                Duration       = $f.Duration
                Planned        = $f.Planned
                Batches        = [int]$f.Batches
                Duplicates     = [int]$f.Duplicates
                OperationId    = [string]$f.OperationId
                Message        = [string]$f.Failure
                Resources      = $mine.ToArray()
            })
    }

    $all = $rows.ToArray()
    @{
        Rows    = $all
        Folders = $folders.ToArray()
        Stats   = [ordered]@{
            Exported = @($all | Where-Object { $_.Status -eq 'Exported' }).Count
            Skipped  = @($all | Where-Object { $_.Status -eq 'Skipped' }).Count
            Errors   = @($all | Where-Object { $_.Status -eq 'Error' }).Count
            Failed   = @($folders | Where-Object { $_.Status -eq 'Failed' }).Count
            Running  = @($folders | Where-Object { $_.Status -eq 'Running' }).Count
            Folders  = $folders.Count
            AzApi    = @($all | Where-Object { $_.Status -eq 'Exported' -and $_.Provider -eq 'azapi' }).Count
        }
    }
}
