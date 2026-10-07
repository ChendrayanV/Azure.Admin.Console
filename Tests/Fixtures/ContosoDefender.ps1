<#
    A made-up Contoso tenant's Microsoft Defender for Cloud, as Resource Graph
    and the Defender for Cloud REST API return it, for the
    Invoke-AACDefenderAssessment tests.

      sub-prod (1111...)  Servers P2 (agentless scanning), Defender CSPM,
                          Resource Manager and Key Vault on; Storage off with
                          a storage account; secure score 60%; a Critical
                          attack path Internet -> vm1 -> st2; a High alert
                          (3 days old) and a Medium one (10 days); a security
                          contact; Defender for Cloud Apps off; a JIT port
                          open to any source; a suppression rule with no
                          expiry; an AWS connector
      sub-dev (2222...)   Servers P1, Storage, CSPM and Resource Manager off
                          (a storage account); secure score 90%; no security
                          contact; Defender for Endpoint off; the connectors
                          can't be read
#>
function Get-AACContosoDefender {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $vm1 = "/subscriptions/$prod/resourcegroups/rg-web/providers/microsoft.compute/virtualmachines/vm1"
    $vm2 = "/subscriptions/$prod/resourcegroups/rg-web/providers/microsoft.compute/virtualmachines/vm2"
    $st2 = "/subscriptions/$prod/resourcegroups/rg-data/providers/microsoft.storage/storageaccounts/st2"
    $st1 = "/subscriptions/$dev/resourcegroups/rg-dev/providers/microsoft.storage/storageaccounts/st1"
    $now = [datetime]::new(2026, 10, 6, 12, 0, 0, [System.DateTimeKind]::Utc)
    $ago = { param([int] $Days) $now.AddDays(-$Days).ToString('o') }
    $plan = { param([string] $Sub, [string] $Name, [string] $Tier, [string] $SubPlan = '', $Extensions = $null) @{ id = "/subscriptions/$Sub/providers/Microsoft.Security/pricings/$Name"; subscriptionId = $Sub; plan = $Name; tier = $Tier; subPlan = $SubPlan; since = '2026-01-01T00:00:00Z'; extensions = $Extensions } }
    $unhealthy = { param([string] $Key, [string] $Name, [string] $Severity, [string] $Sub, [string] $Id, [string] $Risk = '', $Factors = $null, [int] $Paths = 0) @{ id = "$Id/providers/microsoft.security/assessments/$Key"; key = $Key; resourceId = $Id; subscriptionId = $Sub; name = $Name; severity = $Severity; cause = ''; statusDescription = 'Found open ports'; link = "https://portal.azure.com/#blade/$Key"; since = (& $ago 20); firstEvaluated = (& $ago 40); riskLevel = $Risk; riskFactors = $Factors; attackPaths = $Paths; source = 'Azure' } }
    $inventory = { param([string] $Sub, [string] $Id, [int] $Unhealthy, [int] $High, [int] $Medium, [int] $Healthy) @{ id = $Id; resourceId = $Id; subscriptionId = $Sub; unhealthy = $Unhealthy; high = $High; medium = $Medium; low = 0; healthy = $Healthy; notApplicable = 0; source = 'Azure' } }
    $alert = { param([string] $Name, [string] $Severity, [string] $Status, [int] $Days, [string] $Id) @{ id = "/subscriptions/$prod/providers/Microsoft.Security/locations/westeurope/alerts/$Name"; subscriptionId = $prod; status = $Status; name = $Name; severity = $Severity; intent = 'InitialAccess'; techniques = @('T1078'); subTechniques = @('T1078.004'); alertType = "VM_$Name"; time = (& $ago $Days); start = (& $ago $Days); end = (& $ago $Days); description = "<b>$Name</b> detected."; remediation = @('Check the sign-ins.', 'Reset the password.'); link = 'https://portal.azure.com/#alert'; entity = 'vm1'; resources = @(@{ AzureResourceId = $Id; Type = 'AzureResource' }); product = 'Microsoft Defender for Servers'; isIncident = 'False' } }

    $rows = @{
        Plans                 = @(
            (& $plan $prod 'VirtualMachines' 'Standard' 'P2' @(@{ name = 'AgentlessVmScanning'; isEnabled = 'True' }, @{ name = 'MdeDesignatedSubscription'; isEnabled = 'False' }))
            (& $plan $prod 'StorageAccounts' 'Free'); (& $plan $prod 'CloudPosture' 'Standard'); (& $plan $prod 'Arm' 'Standard'); (& $plan $prod 'KeyVaults' 'Standard')
            (& $plan $dev 'VirtualMachines' 'Standard' 'P1'); (& $plan $dev 'StorageAccounts' 'Free'); (& $plan $dev 'CloudPosture' 'Free'); (& $plan $dev 'Arm' 'Free')
        )
        Scores                = @(@{ id = $prod; subscriptionId = $prod; current = 30; max = 50 }, @{ id = $dev; subscriptionId = $dev; current = 45; max = 50 })
        Controls              = @(
            @{ id = "$prod|Secure management ports"; subscriptionId = $prod; control = 'Secure management ports'; current = 4; max = 8; healthy = 1; unhealthy = 2 }
            @{ id = "$prod|Enable MFA"; subscriptionId = $prod; control = 'Enable MFA'; current = 0; max = 10; healthy = 0; unhealthy = 2 }
        )
        ControlAssessments    = @(@{ id = 'Secure management ports|k-ports'; control = 'Secure management ports'; key = 'k-ports' })
        RecommendationSummary = @(
            @{ id = 'k-ports'; key = 'k-ports'; unhealthy = 2; healthy = 1; notApplicable = 0; subscriptions = 1; name = 'Management ports should be closed on your virtual machines'; severity = 'High'; impact = 'High'; effort = 'Low'; categories = 'Networking'; threats = 'DataExfiltration'; description = '<p>Open ports&nbsp;invite attacks.</p>'; remediation = '1. Go to the VM<br>2. Close the port'; assessmentType = 'BuiltIn'; preview = 'False'; policyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/ports' }
            @{ id = 'k-storage'; key = 'k-storage'; unhealthy = 1; healthy = 3; notApplicable = 1; subscriptions = 1; name = 'Storage accounts should restrict network access'; severity = 'Medium'; impact = ''; effort = ''; categories = 'Data'; threats = ''; description = 'Restrict access.'; remediation = ''; assessmentType = 'BuiltIn'; preview = 'False'; policyDefinitionId = '' }
            @{ id = 'k-healthy'; key = 'k-healthy'; unhealthy = 0; healthy = 5; notApplicable = 0; subscriptions = 0; name = 'Something already healthy'; severity = 'Low'; impact = ''; effort = ''; categories = ''; threats = ''; description = ''; remediation = ''; assessmentType = 'BuiltIn'; preview = 'False'; policyDefinitionId = '' }
        )
        Unhealthy             = @(
            (& $unhealthy 'k-ports' 'Management ports should be closed on your virtual machines' 'High' $prod $vm2 'High')
            (& $unhealthy 'k-ports' 'Management ports should be closed on your virtual machines' 'High' $prod $vm1 'Critical' @('Internet exposure', 'Vulnerabilities') 1)
            (& $unhealthy 'k-storage' 'Storage accounts should restrict network access' 'Medium' $dev $st1)
        )
        InventorySummary      = @((& $inventory $prod $vm1 1 1 0 4), (& $inventory $prod $vm2 1 1 0 2), (& $inventory $prod $st2 0 0 0 3), (& $inventory $dev $st1 1 0 1 2))
        AttackPaths           = @(@{
                id = "/subscriptions/$prod/providers/Microsoft.Security/attackPaths/p1"; name = 'p1'; subscriptionId = $prod
                properties = @{
                    displayName = 'Internet exposed VM with high severity vulnerabilities has access to a storage account'; riskLevel = 'Critical'; riskFactors = @('Exposure', 'Sensitive data')
                    mitreTactics = @('Initial Access', 'Lateral Movement'); mitreTechniques = @('T1190'); attackStory = 'vm1 is reachable from the internet and can read st2.'; remediationSteps = @('Close port 22 on vm1.', 'Remove the VM identity''s access to st2.')
                    graphComponent = @{
                        entities    = @(
                            @{ entityInternalId = 'e2'; entityName = 'st2'; entityType = 'storageaccount'; entityIdentifiers = @{ azureResourceId = $st2 } }
                            @{ entityInternalId = 'e1'; entityName = 'vm1'; entityType = 'virtualmachine'; entityIdentifiers = @{ azureResourceId = $vm1 } }
                            @{ entityInternalId = 'e0'; entityName = 'Internet'; entityType = 'internet' }
                        )
                        connections = @(@{ sourceEntityInternalId = 'e1'; targetEntityInternalId = 'e2'; title = 'Has permission to' }, @{ sourceEntityInternalId = 'e0'; targetEntityInternalId = 'e1'; title = 'Is exposed to' })
                    }
                }
            })
        Alerts                = @((& $alert 'SuspiciousLogin' 'High' 'Active' 3 $vm1), (& $alert 'PortScan' 'Medium' 'Active' 10 $vm1), (& $alert 'OldThing' 'Low' 'Resolved' 20 $vm2))
        Vulnerabilities       = @(@{ id = "$vm1/providers/Microsoft.Security/assessments/k-vuln/subAssessments/v1"; subscriptionId = $prod; assessmentKey = 'k-ports'; resourceId = $vm1; name = 'OpenSSL buffer overflow'; severity = 'High'; category = 'Ubuntu'; impact = 'Remote code execution.'; remediation = 'Update OpenSSL.'; vulnerabilityId = '12345'; cve = @(@{ title = 'CVE-2026-1234'; link = 'https://nvd.nist.gov' }); cveId = ''; patchable = 'True'; image = ''; generated = (& $ago 2) })
        Standards             = @(@{ id = "$prod|mcsb"; subscriptionId = $prod; standard = 'Microsoft-cloud-security-benchmark'; state = 'Failed'; passed = 40; failed = 10; skipped = 2; unsupported = 5 })
        ComplianceControls    = @(
            @{ id = "$prod|mcsb|NS-1"; subscriptionId = $prod; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS-1'; description = 'Network segmentation'; state = 'Failed'; passed = 1; failed = 2; skipped = 0 }
            @{ id = "$prod|mcsb|NS-2"; subscriptionId = $prod; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS-2'; description = 'Private links'; state = 'Passed'; passed = 3; failed = 0; skipped = 0 }
        )
        ComplianceAssessments = @(@{ id = "$prod|mcsb|NS-1|k-ports"; subscriptionId = $prod; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS-1'; key = 'k-ports'; description = 'Management ports should be closed'; state = 'Failed'; failedResources = 2 })
    }
    $ok = { param($Items) @{ Status = 200; Body = @{ value = $Items }; Items = $Items; Error = '' } }
    $rest = @{
        Contacts    = @{
            $prod = (& $ok @(@{ name = 'default'; properties = @{ emails = 'secops@contoso.com'; isEnabled = $true; notificationsByRole = @{ state = 'On'; roles = @('Owner') }; notificationsSources = @(@{ sourceType = 'Alert'; minimalSeverity = 'Medium' }, @{ sourceType = 'AttackPath'; minimalRiskLevel = 'Critical' }) } }))
            $dev  = (& $ok @())
        }
        Settings    = @{
            $prod = (& $ok @(@{ name = 'WDATP'; kind = 'DataExportSettings'; properties = @{ enabled = $true } }, @{ name = 'MCAS'; kind = 'DataExportSettings'; properties = @{ enabled = $false } }))
            $dev  = (& $ok @(@{ name = 'WDATP'; kind = 'DataExportSettings'; properties = @{ enabled = $false } }))
        }
        Connectors  = @{
            $prod = (& $ok @(@{ id = "/subscriptions/$prod/resourceGroups/rg-sec/providers/Microsoft.Security/securityConnectors/aws-prod"; name = 'aws-prod'; location = 'westeurope'; properties = @{ environmentName = 'AWS'; hierarchyIdentifier = '123456789012'; offerings = @(@{ offeringType = 'CspmMonitorAws' }, @{ offeringType = 'DefenderForServersAws' }) } }))
            $dev  = @{ Status = 403; Body = $null; Items = $null; Error = 'The client does not have authorization.' }
        }
        Jit         = @{
            $prod = (& $ok @(@{ name = 'default'; properties = @{ virtualMachines = @(@{ id = $vm1; ports = @(@{ number = 22; protocol = '*'; allowedSourceAddressPrefix = '*'; maxRequestAccessDuration = 'PT3H' }) }) } }))
            $dev  = (& $ok @())
        }
        Suppression = @{
            $prod = (& $ok @(@{ name = 'dismiss-scanner'; properties = @{ alertType = 'VM_PortScan'; state = 'Enabled'; reason = 'FalsePositive'; comment = 'Our scanner'; expirationDateUtc = $null } }))
            $dev  = (& $ok @())
        }
    }
    @{ Rows = $rows; Rest = $rest; Names = @{ $prod = 'sub-prod'; $dev = 'sub-dev' }; Prod = $prod; Dev = $dev; Now = $now; Vm1 = $vm1 }
}
