function ConvertTo-AACServiceBlueprintName {
    <#
    .SYNOPSIS
        Fills in a naming convention for one resource and checks the name
        against what Azure accepts for that type.
    .DESCRIPTION
        -Pattern holds {type}, {workload}, {env}, {region} and {instance};
        any other token is a mistake and stops the command. A name is lower
        case. A type that can't have hyphens (a storage account) loses them,
        which is reported as Adjusted. A name that is too long or has
        characters Azure refuses is never shortened or repaired: it is
        returned with Problem set, for the caller to report.

        Returns @{ Name; Adjusted; Problem }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Pattern,

        [Parameter(Mandatory)]
        [string] $Abbreviation,

        [Parameter(Mandatory)]
        [string] $Workload,

        [Parameter(Mandatory)]
        [string] $Environment,

        [Parameter(Mandatory)]
        [string] $Region,

        [Parameter(Mandatory)]
        [string] $Instance,

        # @{ Min; Max; Pattern; Strip; Text }: Get-AACServiceTemplate's Naming.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Rule
    )

    $regionCode = @{
        westeurope = 'weu'; northeurope = 'neu'; uksouth = 'uks'; ukwest = 'ukw'; francecentral = 'frc'; germanywestcentral = 'gwc'; swedencentral = 'swc'; switzerlandnorth = 'chn'; norwayeast = 'noe'
        eastus = 'eus'; eastus2 = 'eus2'; centralus = 'cus'; westus = 'wus'; westus2 = 'wus2'; westus3 = 'wus3'; canadacentral = 'cac'; brazilsouth = 'brs'
        southeastasia = 'sea'; eastasia = 'ea'; japaneast = 'jpe'; australiaeast = 'aue'; centralindia = 'cin'; southafricanorth = 'san'; uaenorth = 'uan'
    }
    $key = $Region.ToLowerInvariant()
    $tokens = @{ type = $Abbreviation; workload = $Workload; env = $Environment; region = $(if ($regionCode.ContainsKey($key)) { $regionCode[$key] } else { $key }); instance = $Instance }
    foreach ($match in [regex]::Matches($Pattern, '\{([^{}]*)\}')) {
        if (-not $tokens.ContainsKey($match.Groups[1].Value)) {
            throw "Azure Admin Console doesn't know the token {$($match.Groups[1].Value)} in the naming convention. Use {type}, {workload}, {env}, {region} and {instance}."
        }
    }
    $name = [regex]::Replace($Pattern, '\{([^{}]*)\}', { param($Found) $tokens[$Found.Groups[1].Value] }).ToLowerInvariant()
    $adjusted = $false
    if ($Rule.Strip -and $name.Contains('-')) {
        $name = $name.Replace('-', '')
        $adjusted = $true
    }
    $problem = if ($name.Length -lt $Rule.Min -or $name.Length -gt $Rule.Max -or $name -notmatch $Rule.Pattern) { "'$name' ($($name.Length) characters) isn't a valid name here: Azure needs $($Rule.Text)." } else { '' }
    @{ Name = $name; Adjusted = $adjusted; Problem = $problem }
}
