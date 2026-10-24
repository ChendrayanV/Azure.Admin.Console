function Get-AACRetailPrice {
    <#
    .SYNOPSIS
        A VM size's pay-as-you-go price an hour, in USD, from the public
        Azure Retail Prices API - for the region and OS (Linux or Windows),
        not Spot or Low Priority.
    .DESCRIPTION
        https://prices.azure.com/api/retail/prices is public: nothing is
        signed in and no credential is sent. Returns the price, or $null
        when there's none (or the API couldn't be reached).
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)]
        [string] $Location,

        [Parameter(Mandatory)]
        [string] $Size,

        [string] $Os = 'linux'
    )

    $filter = "serviceName eq 'Virtual Machines' and armRegionName eq '$($Location.ToLowerInvariant())' and armSkuName eq '$Size' and priceType eq 'Consumption'"
    try {
        $answer = Invoke-RestMethod -Method Get -Uri "https://prices.azure.com/api/retail/prices?`$filter=$([System.Uri]::EscapeDataString($filter))" -TimeoutSec 30 -ErrorAction Stop
    }
    catch { return $null }
    $windows = $Os -eq 'windows'
    $item = @($answer.Items | Where-Object {
            $_.skuName -notmatch 'Spot|Low Priority' -and $_.unitOfMeasure -eq '1 Hour' -and (($_.productName -match 'Windows') -eq $windows)
        }) | Select-Object -First 1
    if ($item) { [double]$item.retailPrice } else { $null }
}
