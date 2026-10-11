<#
    Made-up Defender for Cloud security alerts for SecurityAlert.Tests.ps1,
    as Azure Resource Graph returns them (Get-AACSecurityAlertQuery):

      sub-prod (plans on)
        Suspicious sign-in     High    Active      vm-web, 1 day ago; host,
                               IP and account entities (and a bare $ref),
                               two MITRE tactics, extended properties
        Port scan x3           Medium  Active (2), Resolved (1)   vm-web:
                               recurring
        Lateral movement       High    InProgress  kv-app (rg-data); an
                               incident; resource ID key in camelCase
        On-premises malware    Low     Active      no Azure resource, the
                               compromised entity only
        Old storage access     Low     Dismissed   stdata, 40 days ago
      sub-dev (no plan on)     nothing
      sub-other (not in scope) one alert, left out
#>
function Get-AACContosoAlert {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $other = '33333333-3333-3333-3333-333333333333'
    $now = [datetime]::UtcNow
    $ago = { param([double] $Days) $now.AddDays(-$Days).ToString('o', [cultureinfo]::InvariantCulture) }
    $res = { param([string] $Sub, [string] $Group, [string] $Type, [string] $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name" }
    $vmWeb = & $res $prod 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web'
    $kv = & $res $prod 'rg-data' 'Microsoft.KeyVault/vaults' 'kv-app'
    $st = & $res $prod 'rg-data' 'Microsoft.Storage/storageAccounts' 'stdata'
    $alert = {
        param([string] $Sub, [string] $AlertName, [string] $Name, [string] $Severity, [string] $Status, [double] $Days, [string] $Target, [hashtable] $Extra = @{})
        $row = @{
            id = "/subscriptions/$Sub/resourceGroups/rg-app/providers/Microsoft.Security/locations/westeurope/alerts/$AlertName"; alertName = $AlertName; subscriptionId = $Sub; location = 'westeurope'
            status = $Status; severity = $Severity; time = (& $ago $Days); name = $Name; alertType = "VM_$($Name -replace '\W', '')"; intent = 'Discovery'; techniques = @(); subTechniques = @()
            start = (& $ago $Days); end = (& $ago $Days); description = "<p>$Name detected.</p>"; remediation = @('Investigate.'); link = "https://portal.azure.com/#alert/$AlertName"; entity = ($Target -split '/')[-1]
            resources = @(if ($Target) { @{ AzureResourceId = $Target; Type = 'AzureResource' } }); entities = @(); extended = @{}; product = 'Microsoft Defender for Servers'; vendor = 'Microsoft'; isIncident = 'False'
        }
        foreach ($k in $Extra.Keys) { $row[$k] = $Extra[$k] }
        $row
    }

    $rows = @(
        & $alert $prod '2517001_a' 'Suspicious sign-in' 'High' 'Active' 1 $vmWeb @{
            intent = 'InitialAccess, CredentialAccess'; techniques = @('T1078', 'T1110'); subTechniques = @('T1078.004')
            description = 'A sign-in from <b>203.0.113.7</b>&nbsp;was seen.<br>Check it.'; remediation = @('Check the sign-in.', 'Reset the password.')
            entities = @(
                @{ '$id' = '1'; Type = 'host'; HostName = 'vm-web'; DnsDomain = 'contoso.local' }
                @{ '$id' = '2'; Type = 'ip'; Address = '203.0.113.7' }
                @{ '$id' = '3'; Type = 'account'; Name = 'alice'; NTDomain = 'CONTOSO' }
                @{ '$ref' = '2' }
                @{ '$id' = '4'; Type = 'ip'; Address = '203.0.113.7' }
            )
            extended = @{ 'Client IP' = '203.0.113.7'; 'Attempts' = '42' }
        }
        & $alert $prod '2517002_a' 'Port scan' 'Medium' 'Active' 2 $vmWeb @{ intent = 'Reconnaissance' }
        & $alert $prod '2517002_b' 'Port scan' 'Medium' 'Active' 5 $vmWeb @{ intent = 'Reconnaissance' }
        & $alert $prod '2517002_c' 'Port scan' 'Medium' 'Resolved' 9 $vmWeb @{ intent = 'Reconnaissance' }
        & $alert $prod '2517003_a' 'Lateral movement' 'High' 'InProgress' 3 '' @{
            intent = 'LateralMovement'; isIncident = 'True'; product = 'Microsoft Defender for Key Vault'
            resources = @(@{ azureResourceId = $kv; type = 'AzureResource' })
            entities = @(@{ type = 'azure-resource'; ResourceId = $kv }, @{ type = 'account'; Name = 'bob'; UPNSuffix = 'contoso.com' })
        }
        & $alert $prod '2517004_a' 'On-premises malware' 'Low' 'Active' 4 '' @{ entity = 'contoso-onprem-01'; entities = @(@{ Type = 'file'; Name = 'evil.exe'; Directory = 'C:\Temp\' }, @{ Type = 'process'; CommandLine = 'evil.exe -run' }) }
        & $alert $prod '2517005_a' 'Old storage access' 'Low' 'Dismissed' 40 $st @{ intent = 'Exfiltration'; product = 'Microsoft Defender for Storage' }
        & $alert $other '2517099_a' 'Elsewhere' 'High' 'Active' 1 (& $res $other 'rg-x' 'Microsoft.Compute/virtualMachines' 'vm-x')
    )

    @{
        Prod  = $prod
        Dev   = $dev
        VmWeb = $vmWeb
        Kv    = $kv
        Names = @{ $prod = 'sub-prod'; $dev = 'sub-dev' }
        Read  = @{
            Errors = @{}
            Rows   = @{
                alerts = $rows
                plans  = @(@{ subscriptionId = $prod; plan = 'VirtualMachines'; tier = 'Standard'; subPlan = 'P2' }, @{ subscriptionId = $dev; plan = 'VirtualMachines'; tier = 'Free'; subPlan = '' })
            }
        }
    }
}
