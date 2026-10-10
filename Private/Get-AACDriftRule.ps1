function Get-AACDriftRule {
    <#
    .SYNOPSIS
        The desired-state rules Get-AACConfigurationDrift checks: the
        built-in security baseline (-UseDefaultRules), and/or the rules in a
        file (-Path, .psd1 or .json).
    .DESCRIPTION
        A rule: @{ Name; ResourceType ('microsoft.storage/storageaccounts',
        wildcards work); Property ('properties.minimumTlsVersion', as a
        snapshot path); Operator (Equals, NotEquals, In, Match, Exists);
        Expected (a value, or values for In); Severity (High, Medium, Low);
        Remediation }. A .psd1 file holds @{ Rules = @( @{ ... } ) }; a
        .json file an array of them (or { "Rules": [...] }).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $Path,

        [switch] $Default
    )

    $rules = [System.Collections.Generic.List[hashtable]]::new()
    $rule = { param([string] $Type, [string] $Property, [string] $Operator, $Expected, [string] $Severity, [string] $Fix) @{ Name = "$($Type -replace '^microsoft\.', '') $($Property -replace '^properties\.', '')"; ResourceType = $Type; Property = $Property; Operator = $Operator; Expected = $Expected; Severity = $Severity; Remediation = $Fix } }
    if ($Default) {
        foreach ($r in @(
                (& $rule 'microsoft.storage/storageaccounts' 'properties.minimumTlsVersion' 'In' @('TLS1_2', 'TLS1_3') 'High' 'Set the minimum TLS version to 1.2.')
                (& $rule 'microsoft.storage/storageaccounts' 'properties.supportsHttpsTrafficOnly' 'Equals' 'true' 'High' 'Allow HTTPS traffic only.')
                (& $rule 'microsoft.storage/storageaccounts' 'properties.allowBlobPublicAccess' 'Equals' 'false' 'High' 'Disallow anonymous blob access.')
                (& $rule 'microsoft.storage/storageaccounts' 'properties.allowSharedKeyAccess' 'Equals' 'false' 'Medium' 'Disable shared key access: use Entra ID.')
                (& $rule 'microsoft.keyvault/vaults' 'properties.enableSoftDelete' 'Equals' 'true' 'High' 'Enable soft delete.')
                (& $rule 'microsoft.keyvault/vaults' 'properties.enablePurgeProtection' 'Equals' 'true' 'Medium' 'Enable purge protection.')
                (& $rule 'microsoft.keyvault/vaults' 'properties.enableRbacAuthorization' 'Equals' 'true' 'Low' 'Use Azure RBAC for data access rather than access policies.')
                (& $rule 'microsoft.web/sites' 'properties.httpsOnly' 'Equals' 'true' 'High' 'Turn on HTTPS only.')
                (& $rule 'microsoft.sql/servers' 'properties.minimalTlsVersion' 'In' @('1.2', '1.3') 'High' 'Set the minimal TLS version to 1.2.')
                (& $rule 'microsoft.sql/servers' 'properties.publicNetworkAccess' 'Equals' 'Disabled' 'Medium' 'Disable public network access: use private endpoints.')
                (& $rule 'microsoft.containerservice/managedclusters' 'properties.enableRBAC' 'Equals' 'true' 'High' 'Enable Kubernetes RBAC.')
                (& $rule 'microsoft.containerservice/managedclusters' 'properties.disableLocalAccounts' 'Equals' 'true' 'Medium' 'Disable local accounts: sign in with Entra ID.')
                (& $rule 'microsoft.documentdb/databaseaccounts' 'properties.disableLocalAuth' 'Equals' 'true' 'Medium' 'Disable key-based authentication: use Entra ID.')
                (& $rule 'microsoft.cache/redis' 'properties.enableNonSslPort' 'Equals' 'false' 'High' 'Disable the non-TLS port.')
                (& $rule 'microsoft.cache/redis' 'properties.minimumTlsVersion' 'In' @('1.2') 'High' 'Set the minimum TLS version to 1.2.')
                (& $rule 'microsoft.containerregistry/registries' 'properties.adminUserEnabled' 'Equals' 'false' 'Medium' 'Disable the admin user: use Entra ID or tokens.')
            )) { $rules.Add($r) }
    }
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) { throw "The desired-state file $Path doesn't exist." }
        $loaded = if ($Path -like '*.psd1') { Import-PowerShellDataFile -LiteralPath $Path } else { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
        $list = if ($loaded -is [System.Collections.IDictionary] -and $loaded.Contains('Rules')) { @($loaded['Rules']) } else { @($loaded) }
        $n = 0
        foreach ($item in $list) {
            $n++
            if ($item -isnot [System.Collections.IDictionary] -or -not $item.Contains('ResourceType') -or -not $item.Contains('Property')) { throw "Rule $n in $Path needs ResourceType and Property." }
            $operator = if ($item.Contains('Operator')) { [string]$item['Operator'] } else { 'Equals' }
            if ($operator -notin 'Equals', 'NotEquals', 'In', 'Match', 'Exists') { throw "Rule $n in $Path has an unknown Operator '$operator': Equals, NotEquals, In, Match or Exists." }
            $rules.Add(@{
                    Name = $(if ($item.Contains('Name')) { [string]$item['Name'] } else { "$($item['ResourceType'] -replace '^microsoft\.', '') $($item['Property'] -replace '^properties\.', '')" })
                    ResourceType = ([string]$item['ResourceType']).ToLowerInvariant(); Property = [string]$item['Property']; Operator = $operator
                    Expected = $(if ($item.Contains('Expected')) { $item['Expected'] } else { $null }); Severity = $(if ($item.Contains('Severity')) { [string]$item['Severity'] } else { 'Medium' })
                    Remediation = $(if ($item.Contains('Remediation')) { [string]$item['Remediation'] } else { "Set $($item['Property']) as the rule expects." })
                })
        }
    }
    $rules.ToArray()
}
