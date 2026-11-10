function Get-AACRegionCode {
    <#
    .SYNOPSIS
        A region's short code for resource names: westeurope is weu. A region
        without one keeps its name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Region
    )

    $regionCode = @{
        westeurope = 'weu'; northeurope = 'neu'; uksouth = 'uks'; ukwest = 'ukw'; francecentral = 'frc'; germanywestcentral = 'gwc'; swedencentral = 'swc'; switzerlandnorth = 'chn'; norwayeast = 'noe'
        eastus = 'eus'; eastus2 = 'eus2'; centralus = 'cus'; westus = 'wus'; westus2 = 'wus2'; westus3 = 'wus3'; canadacentral = 'cac'; brazilsouth = 'brs'
        southeastasia = 'sea'; eastasia = 'ea'; japaneast = 'jpe'; australiaeast = 'aue'; centralindia = 'cin'; southafricanorth = 'san'; uaenorth = 'uan'
    }
    $key = $Region.ToLowerInvariant()
    if ($regionCode.ContainsKey($key)) { $regionCode[$key] } else { $key }
}
