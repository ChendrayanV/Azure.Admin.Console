function Read-AACKeyVaultTelemetry {
    <#
    .SYNOPSIS
        Reads each Key Vault's platform metrics - what the Key Vault insights
        workbook's Overview and Failures tabs show, plus saturation - and its
        diagnostic settings, several vaults at once.
    .DESCRIPTION
        Per vault, through Invoke-AACArmParallel (Reader is enough):
          core     Availability, ServiceApiHit, ServiceApiLatency and
                   SaturationShoebox (Overall Vault Saturation): average,
                   total and maximum per -Interval
          results  ServiceApiResult by StatusCode
          types    ServiceApiHit by ActivityType (the request types)
          settings {id}/providers/Microsoft.Insights/diagnosticSettings
        Returns @{ vault id = @{ Core; Results; Types; Settings (each
        Invoke-AACArmParallel's result) } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $VaultId,

        # 'start/end', UTC, ISO 8601.
        [Parameter(Mandatory)]
        [string] $Timespan,

        [Parameter(Mandatory)]
        [string] $Interval,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress
    )

    $metrics = "providers/Microsoft.Insights/metrics?api-version=2023-10-01&timespan=$Timespan&interval=$Interval"
    $uris = [ordered]@{}
    foreach ($id in $VaultId) {
        $uris["$id|Core"] = "$id/$metrics&metricnames=Availability,ServiceApiHit,ServiceApiLatency,SaturationShoebox&aggregation=Average,Total,Maximum"
        $uris["$id|Results"] = "$id/$metrics&metricnames=ServiceApiResult&aggregation=Total&`$filter=$([System.Uri]::EscapeDataString("StatusCode eq '*'"))"
        $uris["$id|Types"] = "$id/$metrics&metricnames=ServiceApiHit&aggregation=Total&`$filter=$([System.Uri]::EscapeDataString("ActivityType eq '*'"))"
        $uris["$id|Settings"] = "$id/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
    }
    $answers = if ($uris.Count) { Invoke-AACArmParallel -Uri @($uris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} }
    $out = @{}
    foreach ($key in $uris.Keys) {
        $id, $part = $key -split '\|'
        if (-not $out.Contains($id)) { $out[$id] = @{ Core = $null; Results = $null; Types = $null; Settings = $null } }
        $out[$id][$part] = $answers[$uris[$key]]
    }
    $out
}
