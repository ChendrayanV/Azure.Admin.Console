<#
    Made-up Contoso metrics for ResourceUtilization.Tests.ps1 - 14 days,
    hourly - as Azure Monitor returns them:

      vm-idle    D2s_v5, CPU 1-2%, little network                 -> Idle
      vm-big     D8s_v5 (32 GB), CPU 10-20%, 8 GB used            -> Under-used, D4s_v5
      vm-hot     D4s_v5, CPU 70% rising to 92%                    -> Hot, growing
      plan-shop  CPU 40-60%, memory 50%                           -> Right sized
      st-old     no transactions                                  -> Idle
      sqldb      no metrics                                       -> No data
#>
function Get-AACContosoUtilization {
    $sub = '11111111-1111-1111-1111-111111111111'
    $res = { param([string] $Type, [string] $Name) "/subscriptions/$sub/resourcegroups/rg-app/providers/$Type/$Name" }
    $hours = 14 * 24
    $start = [datetime]'2026-09-25T00:00:00Z'
    $metric = {
        param([string] $Name, [scriptblock] $Value, [string] $Field = 'average')
        @{ name = @{ value = $Name }; timeseries = @(@{ data = @(for ($h = 0; $h -lt $hours; $h++) { $v = & $Value $h; $point = @{ timeStamp = $start.AddHours($h).ToString('o') }; $point[$Field] = $v; if ($Field -eq 'average') { $point.maximum = $v + 2; $point.minimum = $v } ; $point }) }) }
    }
    $gb = [double]1GB
    $row = { param([string] $Type, [string] $Name, [string] $Size = '', [string] $Os = '') @{ id = (& $res $Type $Name); name = $Name; type = $Type; resourceGroup = 'rg-app'; subscriptionId = $sub; location = 'westeurope'; size = $Size; os = $Os; sku = ''; power = $(if ($Type -eq 'microsoft.compute/virtualmachines') { 'PowerState/running' } else { '' }) } }
    $resources = @(
        (& $row 'microsoft.compute/virtualmachines' 'vm-idle' 'Standard_D2s_v5' 'linux')
        (& $row 'microsoft.compute/virtualmachines' 'vm-big' 'Standard_D8s_v5' 'linux')
        (& $row 'microsoft.compute/virtualmachines' 'vm-hot' 'Standard_D4s_v5' 'windows')
        (& $row 'microsoft.web/serverfarms' 'plan-shop')
        (& $row 'microsoft.storage/storageaccounts' 'st-old')
        (& $row 'microsoft.sql/servers/databases' 'sqldb')
        (@{ id = (& $res 'microsoft.compute/virtualmachines' 'vm-off'); name = 'vm-off'; type = 'microsoft.compute/virtualmachines'; resourceGroup = 'rg-app'; subscriptionId = $sub; location = 'westeurope'; size = 'Standard_D2s_v5'; os = 'linux'; sku = ''; power = 'PowerState/deallocated' })
    )
    $metrics = @{
        (& $res 'microsoft.compute/virtualmachines' 'vm-idle').ToLowerInvariant()  = @((& $metric 'Percentage CPU' { param($h) 1 + ($h % 2) }), (& $metric 'Available Memory Bytes' { param($h) 6 * $gb }), (& $metric 'Network In Total' { param($h) 1000 } 'total'))
        (& $res 'microsoft.compute/virtualmachines' 'vm-big').ToLowerInvariant()   = @((& $metric 'Percentage CPU' { param($h) 10 + ($h % 11) }), (& $metric 'Available Memory Bytes' { param($h) 24 * $gb }), (& $metric 'Network In Total' { param($h) 5MB } 'total'))
        (& $res 'microsoft.compute/virtualmachines' 'vm-hot').ToLowerInvariant()   = @((& $metric 'Percentage CPU' { param($h) if ($h -lt 168) { 70 } else { 92 } }), (& $metric 'Network In Total' { param($h) 50MB } 'total'))
        (& $res 'microsoft.web/serverfarms' 'plan-shop').ToLowerInvariant()         = @((& $metric 'CpuPercentage' { param($h) 40 + ($h % 21) }), (& $metric 'MemoryPercentage' { param($h) 50 }))
        (& $res 'microsoft.storage/storageaccounts' 'st-old').ToLowerInvariant()   = @((& $metric 'Transactions' { param($h) 0 } 'total'))
    }
    @{
        Sub       = $sub
        Names     = @{ $sub = 'sub-prod' }
        Resources = $resources
        Metrics   = $metrics
        Sizes     = @{ 'westeurope|standard_d2s_v5' = @{ Cores = 2; MemoryMB = 8192 }; 'westeurope|standard_d4s_v5' = @{ Cores = 4; MemoryMB = 16384 }; 'westeurope|standard_d8s_v5' = @{ Cores = 8; MemoryMB = 32768 } }
        Prices    = @{ 'westeurope|standard_d8s_v5|linux' = 0.4; 'westeurope|standard_d4s_v5|linux' = 0.2 }
        Cost      = @{ (& $res 'microsoft.compute/virtualmachines' 'vm-idle').ToLowerInvariant() = @{ Cost = 100; Currency = 'EUR' }; (& $res 'microsoft.web/serverfarms' 'plan-shop').ToLowerInvariant() = @{ Cost = 200; Currency = 'EUR' } }
    }
}
