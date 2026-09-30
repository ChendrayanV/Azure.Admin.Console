<#
    Made-up Microsoft Defender for Cloud and Azure Policy rows for the
    Contoso tenant, as Get-AACDefenderQuery's queries return them from Azure
    Resource Graph (hashtables), for SecurityPosture.Tests.ps1:

      sub-connectivity   secure score 38/50; Servers plan off; DDoS medium on
                         vnet-hub; ISO 27001 A.1 failed; a tag policy failing
      sub-corp-apps      secure score 18/50; Storage plan off; two High and a
                         Medium recommendation on the web VMs, a Low on the
                         storage account; a High alert on vm-web-01; the
                         cloud security benchmark's NS.1 failed (JIT, and a
                         manual check); an allowed-locations policy failing
#>
function Get-AACContosoSecurity {
    $connectivity = '11111111-1111-1111-1111-111111111111'
    $corp = '22222222-2222-2222-2222-222222222222'
    $id = { param($Sub, $Group, $Type, $Name) "/subscriptions/$Sub/resourcegroups/$Group/providers/$Type/$Name".ToLowerInvariant() }
    $vm1 = & $id $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-01'
    $vm2 = & $id $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-02'
    $storage = & $id $corp 'rg-data' 'Microsoft.Storage/storageAccounts' 'stordersdata'
    $vnet = & $id $connectivity 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub'
    $recommendation = {
        param($Key, $Resource, $Sub, $Name, $Severity, $Category = 'Compute')
        @{ key = $Key; resourceId = $Resource; subscriptionId = $Sub; name = $Name; severity = $Severity; impact = 'High'; effort = 'Low'; categories = $Category; cause = ''; description = "$Name - why it matters."; remediation = "Fix: $Name."; link = "portal.azure.com/#blade/Microsoft_Azure_Security/RecommendationsBlade/assessmentKey/$Key"; since = '2026-09-01T00:00:00Z' }
    }
    @{
        Ids                   = @{ Vm1 = $vm1; Vm2 = $vm2; Storage = $storage; Vnet = $vnet; Corp = $corp; Connectivity = $connectivity }
        subscriptions         = @(@{ subscriptionId = $connectivity; name = 'sub-connectivity' }, @{ subscriptionId = $corp; name = 'sub-corp-apps' })
        Scores                = @(@{ subscriptionId = $connectivity; current = 38.0; max = 50.0 }, @{ subscriptionId = $corp; current = 18.0; max = 50.0 })
        Controls              = @(
            @{ subscriptionId = $corp; control = 'Secure management ports'; current = 0.0; max = 8.0; healthy = 0; unhealthy = 2 }
            @{ subscriptionId = $corp; control = 'Remediate vulnerabilities'; current = 3.0; max = 6.0; healthy = 1; unhealthy = 1 }
            @{ subscriptionId = $connectivity; control = 'Enable DDoS protection'; current = 0.0; max = 2.0; healthy = 0; unhealthy = 1 }
        )
        ControlAssessments    = @(
            @{ control = 'Secure management ports'; key = 'a-jit' }
            @{ control = 'Remediate vulnerabilities'; key = 'a-vuln' }
            @{ control = 'Enable encryption at rest'; key = 'a-enc' }
            @{ control = 'Enable DDoS protection'; key = 'a-ddos' }
        )
        Recommendations       = @(
            & $recommendation 'a-jit' $vm1 $corp 'Management ports should be protected with just-in-time access' 'High' 'Networking'
            & $recommendation 'a-vuln' $vm1 $corp 'Machines should have vulnerability findings resolved' 'High'
            & $recommendation 'a-enc' $vm2 $corp 'Virtual machines should encrypt temp disks' 'Medium' 'Data'
            & $recommendation 'a-stor' $storage $corp 'Storage accounts should restrict network access' 'Low' 'Networking'
            & $recommendation 'a-ddos' $vnet $connectivity 'Azure DDoS Protection Standard should be enabled' 'Medium' 'Networking'
        )
        Alerts                = @(
            @{ id = 'alert-1'; subscriptionId = $corp; status = 'Active'; name = 'Suspicious login to a VM'; severity = 'High'; intent = 'InitialAccess'; alertType = 'VM_Login'; time = '2026-09-25T10:00:00Z'; description = 'A login from an unusual location.'; link = 'https://portal.azure.com/#blade/alert-1'; entity = 'vm-web-01'; resources = @(@{ AzureResourceId = $vm1; Type = 'AzureResource' }) }
            @{ id = 'alert-2'; subscriptionId = $connectivity; status = 'Active'; name = 'Traffic from a known malicious IP'; severity = 'Medium'; intent = 'Probing'; alertType = 'Net_MaliciousIP'; time = '2026-09-27T08:00:00Z'; description = 'Inbound traffic from a known malicious address.'; link = 'https://portal.azure.com/#blade/alert-2'; entity = 'hub-gateway'; resources = @() }
        )
        Plans                 = @(
            @{ subscriptionId = $corp; plan = 'VirtualMachines'; tier = 'Standard'; subPlan = 'P2' }
            @{ subscriptionId = $corp; plan = 'StorageAccounts'; tier = 'Free'; subPlan = '' }
            @{ subscriptionId = $corp; plan = 'KeyVaults'; tier = 'Standard'; subPlan = '' }
            @{ subscriptionId = $connectivity; plan = 'VirtualMachines'; tier = 'Free'; subPlan = '' }
        )
        Standards             = @(
            @{ subscriptionId = $corp; standard = 'Microsoft-cloud-security-benchmark'; state = 'Failed'; passed = 40; failed = 10; skipped = 2; unsupported = 5 }
            @{ subscriptionId = $connectivity; standard = 'ISO-27001-2013'; state = 'Failed'; passed = 20; failed = 5; skipped = 0; unsupported = 1 }
        )
        ComplianceControls    = @(
            @{ subscriptionId = $corp; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS.1'; description = 'Establish network segmentation boundaries'; state = 'Failed'; passed = 3; failed = 2; skipped = 0 }
            @{ subscriptionId = $corp; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS.2'; description = 'Secure cloud services with network controls'; state = 'Passed'; passed = 4; failed = 0; skipped = 0 }
            @{ subscriptionId = $connectivity; standard = 'ISO-27001-2013'; control = 'A.13.1.1'; description = 'Network controls'; state = 'Failed'; passed = 1; failed = 1; skipped = 0 }
        )
        ComplianceAssessments = @(
            @{ subscriptionId = $corp; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS.1'; key = 'a-jit'; description = 'Management ports should be protected with just-in-time access'; state = 'Failed'; failedResources = 1 }
            @{ subscriptionId = $corp; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS.1'; key = 'a-manual'; description = 'Review network segmentation (manual)'; state = 'Failed'; failedResources = 0 }
            @{ subscriptionId = $corp; standard = 'Microsoft-cloud-security-benchmark'; control = 'NS.2'; key = 'a-ok'; description = 'Something that passes'; state = 'Passed'; failedResources = 0 }
            @{ subscriptionId = $connectivity; standard = 'ISO-27001-2013'; control = 'A.13.1.1'; key = 'a-ddos'; description = 'Azure DDoS Protection Standard should be enabled'; state = 'Failed'; failedResources = 1 }
        )
        # Every policy state, as Get-AACPolicyStateQuery returns them: allowed
        # locations in sub-corp-apps (3 of 5 comply), required tags in
        # sub-connectivity (3 of 4).
        PolicyStates          = @(
            foreach ($entry in @(
                    @($corp, $storage, 'NonCompliant', 'allowed'), @($corp, $vm2, 'NonCompliant', 'allowed'), @($corp, $vm1, 'Compliant', 'allowed')
                    @($corp, (& $id $corp 'rg-app' 'Microsoft.KeyVault/vaults' 'kv-app'), 'Compliant', 'allowed'), @($corp, (& $id $corp 'rg-data' 'Microsoft.Sql/servers' 'sql-orders'), 'Compliant', 'allowed')
                    @($connectivity, $vnet, 'NonCompliant', 'tags'), @($connectivity, (& $id $connectivity 'rg-hub' 'Microsoft.Network/azureFirewalls' 'afw-hub'), 'Compliant', 'tags')
                    @($connectivity, (& $id $connectivity 'rg-hub' 'Microsoft.Network/bastionHosts' 'bas-hub'), 'Compliant', 'tags'), @($connectivity, (& $id $connectivity 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-afw'), 'Compliant', 'tags')
                )) {
                $allowed = $entry[3] -eq 'allowed'
                @{
                    subscriptionId = $entry[0]; resourceId = $entry[1]; resourceType = ''; resourceGroup = ($entry[1] -split '/')[4]; location = 'uksouth'; state = $entry[2]
                    assignmentId = $(if ($allowed) { '/providers/microsoft.management/managementgroups/mg-corp/providers/microsoft.authorization/policyassignments/allowed-locations' } else { "/subscriptions/$connectivity/providers/microsoft.authorization/policyassignments/require-tags" })
                    assignment = $(if ($allowed) { 'allowed-locations' } else { 'require-tags' }); assignmentScope = ''; definitionName = ''; definitionId = ''
                    policy = $(if ($allowed) { 'Allowed locations' } else { 'Require a tag on resources' }); setName = ''; policySet = ''; referenceId = ''
                    effect = $(if ($allowed) { 'deny' } else { 'audit' }); evaluated = '2026-09-20T00:00:00Z'
                }
            }
        )
        PolicyAssignments     = @(
            @{ assignmentId = '/providers/microsoft.management/managementgroups/mg-corp/providers/microsoft.authorization/policyassignments/allowed-locations'; name = 'allowed-locations'; displayName = 'Contoso allowed locations'; scope = '/providers/Microsoft.Management/managementGroups/mg-corp'; enforcement = 'Default' }
            @{ assignmentId = "/subscriptions/$connectivity/providers/microsoft.authorization/policyassignments/require-tags"; name = 'require-tags'; displayName = 'Contoso required tags'; scope = "/subscriptions/$connectivity"; enforcement = 'DoNotEnforce' }
        )
    }
}
