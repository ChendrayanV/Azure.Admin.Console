function Get-AACStorageRuleFix {
    <#
    .SYNOPSIS
        For each PSRule rule a planned storage account fails, the change to
        its configuration that fixes it - in the AVM parameter names
        Deploy-AACStorageAccount reads - or what to do when no setting can.
    .DESCRIPTION
        -Result is PSRule results (Outcome Fail or Error); -Configuration the
        configuration they were run on; -AccountExists whether the account
        is already there (a redundancy fix must then be one Azure can make in
        place).

        Returns AAC.StorageRuleFix rows: Rule, Resource, Kind, Setting,
        Value, Advice, Link:
          Auto     a setting fixes it: Setting is its path in the
                   configuration (networkAcls.defaultAction,
                   blobServices.containers[name=raw].publicAccess), Value
                   the value - -UseSuggestedFix applies it
          Manual   it can't be fixed by a setting here (the name, Defender
                   for Storage on the subscription, a rule this command
                   doesn't know): Advice says what to do

        Built from PSRule for Azure's storage rules as they report (1.47):
        LocalAuth, BlobPublicAccess, MinTLS, SecureTransfer, Firewall,
        UseReplication, SoftDelete, ContainerSoftDelete, FileShareSoftDelete,
        BlobAccessType, Name, Naming, DefenderCloud, Defender.MalwareScan,
        Azure.Resource.UseTags - and the module's own naming and tag rules.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Result,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Configuration,

        [switch] $AccountExists
    )

    $fixes = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($Item, [string] $Kind, [string] $Setting, $Value, [string] $Advice)
        $fixes.Add([pscustomobject]@{ PSTypeName = 'AAC.StorageRuleFix'; Rule = (& $field $Item 'RuleName'); Resource = (& $field $Item 'ResourceName'); Kind = $Kind; Setting = $Setting; Value = $Value; Advice = $Advice; Link = (& $field $Item 'Link') })
    }
    $sku = [string]$(if ($Configuration['skuName']) { $Configuration['skuName'] } else { 'Standard_GRS' })
    # A result's property, or '' - results from elsewhere may not have them all.
    $field = { param($Item, [string] $Name) $property = $Item.PSObject.Properties[$Name]; if ($property) { [string]$property.Value } else { '' } }

    foreach ($item in @($Result | Where-Object { $_.Outcome -in 'Fail', 'Error' })) {
        $rule = [string]$item.RuleName
        switch -Regex ($rule) {
            '^Azure\.Storage\.LocalAuth$' { & $add $item 'Auto' 'allowSharedKeyAccess' $false 'Disable shared key (account key and SAS) access: use Microsoft Entra ID. Apps and tools that use the account key stop working - move them to Entra ID first.' }
            '^Azure\.Storage\.BlobPublicAccess$' { & $add $item 'Auto' 'allowBlobPublicAccess' $false 'Disallow anonymous (public) access to blobs.' }
            '^Azure\.Storage\.MinTLS$' { & $add $item 'Auto' 'minimumTlsVersion' 'TLS1_2' 'Accept TLS 1.2 or later only.' }
            '^Azure\.Storage\.SecureTransfer$' { & $add $item 'Auto' 'supportsHttpsTrafficOnly' $true 'Accept HTTPS only.' }
            '^Azure\.Storage\.Firewall$' { & $add $item 'Auto' 'networkAcls.defaultAction' 'Deny' 'Deny network access by default; allow the clients that need it with networkAcls.ipRules or networkAcls.virtualNetworkRules, or use private endpoints.' }
            '^Azure\.Storage\.UseReplication$' {
                # In place from LRS is GRS (zonal needs a conversion); a new account can be zone-redundant.
                $better = if ($sku -like 'Premium_*') { 'Premium_ZRS' } elseif ($AccountExists) { 'Standard_GRS' } else { 'Standard_GZRS' }
                if ($sku -like 'Premium_*' -and $AccountExists) { & $add $item 'Manual' 'skuName' $null "A Premium account can't change to zone-redundant in place: create a new Premium_ZRS account and move the data." }
                else { & $add $item 'Auto' 'skuName' $better $(if ($AccountExists) { 'Replicate to a second region (GRS) - a change Azure makes in place. For zone redundancy (GZRS), Azure needs a conversion request.' } else { 'Replicate across zones and a second region.' }) }
            }
            '^Azure\.Storage\.SoftDelete$' {
                & $add $item 'Auto' 'blobServices.deleteRetentionPolicyEnabled' $true 'Keep deleted blobs recoverable.'
                if (-not $Configuration['blobServices'] -or -not $Configuration['blobServices']['deleteRetentionPolicyDays']) { & $add $item 'Auto' 'blobServices.deleteRetentionPolicyDays' 7 'For 7 days.' }
            }
            '^Azure\.Storage\.ContainerSoftDelete$' {
                & $add $item 'Auto' 'blobServices.containerDeleteRetentionPolicyEnabled' $true 'Keep deleted containers recoverable.'
                if (-not $Configuration['blobServices'] -or -not $Configuration['blobServices']['containerDeleteRetentionPolicyDays']) { & $add $item 'Auto' 'blobServices.containerDeleteRetentionPolicyDays' 7 'For 7 days.' }
            }
            '^Azure\.Storage\.FileShareSoftDelete$' {
                & $add $item 'Auto' 'fileServices.shareDeleteRetentionPolicy.enabled' $true 'Keep deleted file shares recoverable.'
                & $add $item 'Auto' 'fileServices.shareDeleteRetentionPolicy.days' 7 'For 7 days.'
            }
            '^Azure\.Storage\.BlobAccessType$' {
                $containers = @([regex]::Matches((& $field $item 'Reason'), "container '([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                if (-not $containers.Count) { & $add $item 'Manual' 'blobServices.containers' $null 'Set publicAccess to None on every container.' }
                foreach ($container in $containers) { & $add $item 'Auto' "blobServices.containers[name=$container].publicAccess" 'None' "Make container $container private." }
            }
            '^(Azure\.Storage\.(Name|Naming)|AAC\.Resource\.Naming)$' { & $add $item 'Manual' 'name' $null "The name doesn't follow the naming rules ($(& $field $item 'Reason')). A storage account can't be renamed: choose a name that does (Cloud Adoption Framework: st<workload><env>, e.g. stcontosoprod) for a new account - or exclude the rule (-ExcludeRule $rule) if this name is intended." }
            '^Azure\.Storage\.(DefenderCloud|Defender\.MalwareScan)$' { & $add $item 'Manual' '' $null "Turn on Microsoft Defender for Storage$(if ($rule -like '*MalwareScan') { ' with malware scanning' }) - for the subscription (Defender for Cloud > Environment settings) or this account. It isn't a storage account setting, so it can't be fixed here; once it's on, run again." }
            '^Azure\.Resource\.UseTags$' { & $add $item 'Manual' 'tags' $null "Tag the account - tags are your values, so they can't be suggested: tags in the configuration, or -Tag @{ env = 'prod'; owner = 'team' }." }
            '^AAC\.(Resource|ResourceGroup)\.(RequiredTags|AllowedTagValues)$' { & $add $item 'Manual' 'tags' $null "Fix the tags: $(& $field $item 'Reason'). Add them to tags in the configuration (-Tag)." }
            default { & $add $item 'Manual' '' $null "$(if (& $field $item 'Recommendation') { & $field $item 'Recommendation' } else { & $field $item 'Title' }) - see the rule's documentation, or exclude it with -ExcludeRule $rule if it doesn't apply." }
        }
    }
    $fixes.ToArray()
}
