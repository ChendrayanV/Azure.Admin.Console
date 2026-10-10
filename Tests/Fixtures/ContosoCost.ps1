<#
    Made-up Contoso daily costs for CostAnomaly.Tests.ps1, as Cost
    Management returns them (Cost, UsageDate as yyyyMMdd, the dimension,
    Currency) - 60 days to 8 Oct 2026:

      sub-prod  Virtual Machines   ~100 a day; 400 on 6 Oct           -> Spike
                Storage            20 a day; 40 the last 3 days      -> Spike (3 days)
                Microsoft Defender none; 15 a day the last 3 days    -> New
                SQL Database       50 a day; nothing the last 2 days -> Drop
      sub-dev   Log Analytics      rising steadily 5 -> 50           -> Trend
                Bandwidth          ~3 a day                          -> nothing (under -MinimumImpact)

    Returns @{ End; Cost (scope -> @{ Rows; Status }); Names; Resources
    (the root-cause rows for the VM spike) }.
#>
function Get-AACContosoCost {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $end = [datetime]'2026-10-08'
    $days = 60
    $start = $end.AddDays( - ($days - 1))
    $row = { param([datetime] $Day, [string] $Service, [double] $Cost) [pscustomobject]@{ Cost = $Cost; UsageDate = [int]$Day.ToString('yyyyMMdd'); ServiceName = $Service; Currency = 'EUR' } }
    $prodRows = [System.Collections.Generic.List[object]]::new()
    $devRows = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $days; $i++) {
        $day = $start.AddDays($i)
        $left = $days - 1 - $i   # days before the end
        $prodRows.Add((& $row $day 'Virtual Machines' $(if ($day -eq [datetime]'2026-10-06') { 400 } else { 98 + ($i % 5) })))
        $prodRows.Add((& $row $day 'Storage' $(if ($left -lt 3) { 40 } else { 20 })))
        if ($left -lt 3) { $prodRows.Add((& $row $day 'Microsoft Defender for Cloud' 15)) }
        if ($left -ge 2) { $prodRows.Add((& $row $day 'SQL Database' 50)) }
        $devRows.Add((& $row $day 'Log Analytics' ([Math]::Round(5 + 45 * $i / ($days - 1), 2))))
        $devRows.Add((& $row $day 'Bandwidth' (2.5 + ($i % 3) * 0.5)))
    }
    $vm = { param([string] $Name) "/subscriptions/$prod/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/$Name" }
    $resources = @(
        foreach ($d in 0..9) {
            $day = [datetime]'2026-09-29'
            $day = $day.AddDays($d)
            [pscustomobject]@{ Cost = $(if ($day -eq [datetime]'2026-10-06') { 320 } else { 20 }); UsageDate = [int]$day.ToString('yyyyMMdd'); ResourceId = (& $vm 'vm-batch-01'); Currency = 'EUR' }
            [pscustomobject]@{ Cost = 80; UsageDate = [int]$day.ToString('yyyyMMdd'); ResourceId = (& $vm 'vm-web-01'); Currency = 'EUR' }
        }
    )
    @{
        End       = $end
        Prod      = $prod
        Dev       = $dev
        Names     = @{ $prod = 'sub-prod'; $dev = 'sub-dev' }
        Cost      = @{ "/subscriptions/$prod" = @{ Rows = $prodRows.ToArray(); Status = 'OK' }; "/subscriptions/$dev" = @{ Rows = $devRows.ToArray(); Status = 'OK' } }
        Resources = $resources
    }
}
