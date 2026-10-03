function ConvertTo-AACStorageConfiguration {
    <#
    .SYNOPSIS
        Reads a storage account's configuration - from a file, parameters, or
        both - into one case-insensitive hashtable with the Azure Verified
        Module (avm/res/storage/storage-account) parameter names, and refuses
        what isn't supported.
    .DESCRIPTION
        -Path is a .psd1 file, or a .json file: either the configuration
        itself, or an AVM / ARM parameters file ({ "parameters": { "name":
        { "value": ... } } }), whose values are unwrapped - so a team's
        existing AVM parameters can be used as they are. -Override (the
        command's own parameters) wins over the file.

        Every key, at every level, becomes case-insensitive. Keys AVM has that
        this command doesn't implement yet are refused by name (rather than
        quietly ignored, which would deploy something other than asked);
        enableTelemetry, AVM's own, is ignored.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string] $Path,

        [System.Collections.IDictionary] $Override = @{}
    )

    # Hashtables at every level, keys case-insensitive ([ordered] is).
    $normalize = {
        param($Value)
        if ($Value -is [System.Collections.IDictionary]) {
            $out = [ordered]@{}
            foreach ($key in $Value.Keys) { $out[[string]$key] = & $normalize $Value[$key] }
            return , $out
        }
        if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) { return , @(foreach ($item in $Value) { & $normalize $item }) }
        if ($Value -is [psobject] -and $Value.PSObject.BaseObject -is [System.Management.Automation.PSCustomObject]) {
            $out = [ordered]@{}
            foreach ($property in $Value.PSObject.Properties) { $out[$property.Name] = & $normalize $property.Value }
            return , $out
        }
        $Value
    }

    $config = [ordered]@{}
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "No configuration file at '$Path'." }
        $raw = switch -Regex ([System.IO.Path]::GetExtension($Path)) {
            '^\.psd1$' { Import-PowerShellDataFile -LiteralPath $Path }
            '^\.json[c]?$' { ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($Path)) -AsHashtable -Depth 100 }
            default { throw "'$Path' isn't a .psd1 or .json configuration file." }
        }
        $raw = & $normalize $raw
        # An AVM / ARM parameters file: { parameters: { name: { value } } }.
        if ($raw.Contains('parameters') -and $raw['parameters'] -is [System.Collections.IDictionary] -and -not $raw.Contains('name')) {
            foreach ($key in $raw['parameters'].Keys) {
                $entry = $raw['parameters'][$key]
                # Not '= if (...)': that would unroll a one-item list.
                $config[$key] = $entry
                if ($entry -is [System.Collections.IDictionary] -and $entry.Contains('value')) { $config[$key] = $entry['value'] }
            }
        }
        else {
            foreach ($key in $raw.Keys) { if ($key -notin '$schema', 'contentVersion') { $config[$key] = $raw[$key] } }
        }
    }
    foreach ($key in $Override.Keys) { $config[[string]$key] = & $normalize $Override[$key] }
    $config.Remove('enableTelemetry')

    $supported = @(
        'name', 'location', 'kind', 'skuName', 'accessTier', 'tags'
        'allowBlobPublicAccess', 'allowSharedKeyAccess', 'allowCrossTenantReplication', 'defaultToOAuthAuthentication', 'minimumTlsVersion', 'supportsHttpsTrafficOnly'
        'publicNetworkAccess', 'networkAcls', 'requireInfrastructureEncryption', 'largeFileSharesState', 'enableHierarchicalNamespace', 'enableNfsV3', 'enableSftp', 'isLocalUserEnabled'
        'allowedCopyScope', 'dnsEndpointType'
        'blobServices', 'fileServices', 'queueServices', 'tableServices', 'managementPolicyRules', 'privateEndpoints', 'diagnosticSettings', 'roleAssignments', 'lock'
        # Not AVM's: the files to upload into containers (data plane).
        'blobs'
    )
    $unsupported = @($config.Keys | Where-Object { $_ -notin $supported })
    if ($unsupported.Count) {
        $problem = [System.InvalidOperationException]::new("These storage account settings aren't supported yet: $($unsupported -join ', '). Nothing was changed.")
        $problem.Data['AACHint'] = "Supported: $($supported -join ', '). Remove the others from the configuration, or set them another way after this deployment."
        throw $problem
    }
    if (-not $config['name']) { throw 'The storage account needs a name: -Name, or name in the configuration.' }
    $config
}
