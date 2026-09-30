function ConvertTo-AACSecurityControl {
    <#
    .SYNOPSIS
        Turns Defender for Cloud's secure score controls (the Controls query
        of Get-AACDefenderQuery) into AAC.SecurityControl objects, with the
        potential increase of the subscription's secure score if the control
        were fully healthy. Shared by Get-AACInventory and
        Get-AACSecurityPosture.
    .DESCRIPTION
        -ScoreMax is each subscription's maximum secure score (subscription
        ID -> points) and -SubscriptionName its name; controls of a
        subscription not in -SubscriptionName are left out.
    #>
    [CmdletBinding()]
    [OutputType('AAC.SecurityControl')]
    param(
        [AllowEmptyCollection()]
        [object[]] $Row = @(),

        [hashtable] $ScoreMax = @{},

        [hashtable] $SubscriptionName = @{}
    )

    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Key)) { $Object[$Key] } } else { Get-AACPropertyValue -InputObject $Object -Name $Key } }
    foreach ($entry in $Row) {
        $subscriptionId = ([string](& $value $entry 'subscriptionId')).ToLowerInvariant()
        if (-not $SubscriptionName.Contains($subscriptionId)) { continue }
        $current = [double](& $value $entry 'current'); $max = [double](& $value $entry 'max')
        $subscriptionMax = if ($ScoreMax.Contains($subscriptionId)) { [double]$ScoreMax[$subscriptionId] } else { 0.0 }
        [pscustomobject][ordered]@{
            PSTypeName         = 'AAC.SecurityControl'
            Control            = [string](& $value $entry 'control')
            SubscriptionName   = $SubscriptionName[$subscriptionId]
            SubscriptionId     = $subscriptionId
            Current            = [Math]::Round($current, 2)
            Max                = [Math]::Round($max, 2)
            Score              = $(if ($max -gt 0) { [Math]::Round(100 * $current / $max) } else { $null })
            PotentialIncrease  = $(if ($subscriptionMax -gt 0) { [Math]::Round(100 * ($max - $current) / $subscriptionMax, 1) } else { 0 })
            HealthyResources   = [int](& $value $entry 'healthy')
            UnhealthyResources = [int](& $value $entry 'unhealthy')
        }
    }
}
