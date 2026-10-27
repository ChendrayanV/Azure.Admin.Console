<#
    Made-up Contoso workloads for the Architecture tests, and the landing zone
    management group they go into, as Azure Resource Graph returns it:

      orders-api   a business-critical web API: confidential data (ISO 27001),
                   read-heavy with an 80 ms target, bursty, RTO 30 minutes,
                   secrets for authentication, budget unknown
      reports      an internal batch workload: defaults almost everywhere
      chat         an AI (retrieval-augmented generation) workload in two
                   geographies, mission-critical

      mg-landingzones (under the Tenant Root Group): Allowed locations
      (northeurope, westeurope), Microsoft cloud security benchmark, and a
      Deny-public-IP assignment that isn't enforced.

    Returns @{ Orders; Reports; Chat (answers); LandingZone (Resource Graph
    rows by query name) }.
#>
function Get-AACContosoArchitecture {
    @{
        Orders      = [ordered]@{
            'BUS-01' = 'Web or API'; 'BUS-02' = 'Business-critical'; 'BUS-03' = 20000
            'REL-01' = 30; 'REL-04' = 'Yes'
            'SEC-01' = 'Confidential'; 'SEC-02' = @('ISO 27001'); 'SEC-03' = 'Inbound from the internet'; 'SEC-04' = 'Secrets'
            'PERF-01' = 'Read-heavy'; 'PERF-02' = 80; 'PERF-03' = 'Bursty'; 'DATA-01' = 'Relational'
            'COST-01' = '?'; 'OPS-01' = 'Azure DevOps'
        }
        Reports     = [ordered]@{ 'BUS-01' = 'Batch'; 'BUS-02' = 'Internal'; 'SEC-03' = 'None (internal only)'; 'COST-01' = 500; 'OPS-01' = 'GitHub Actions' }
        Chat        = [ordered]@{
            'BUS-01' = 'AI (retrieval-augmented generation)'; 'BUS-02' = 'Mission-critical'; 'PERF-04' = 'Several regions'; 'SEC-01' = 'Internal'
            'SEC-04' = 'Managed identity'; 'DATA-01' = 'Document'; 'COST-01' = 20000; 'OPS-01' = 'GitHub Actions'
        }
        LandingZone = @{
            group       = @(@{ id = '/providers/Microsoft.Management/managementGroups/mg-landingzones'; name = 'mg-landingzones'; displayName = 'Landing zones'; chain = @(@{ name = 'contoso' }) })
            assignments = @(
                @{ id = 'a1'; name = 'Allowed locations'; scope = '/providers/microsoft.management/managementgroups/contoso'; enforcement = 'Default'; definitionId = '/providers/microsoft.authorization/policydefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'; parameters = @{ listOfAllowedLocations = @{ value = @('northeurope', 'westeurope') } } }
                @{ id = 'a2'; name = 'Microsoft cloud security benchmark'; scope = '/providers/microsoft.management/managementgroups/contoso'; enforcement = 'Default'; definitionId = '/providers/microsoft.authorization/policysetdefinitions/1f3afdf9-d0c9-4c3d-847f-89da613e70a8'; parameters = @{} }
                @{ id = 'a3'; name = 'Deny public IP addresses'; scope = '/providers/microsoft.management/managementgroups/mg-landingzones'; enforcement = 'DoNotEnforce'; definitionId = '/providers/microsoft.authorization/policydefinitions/deny-pip'; parameters = @{} }
            )
        }
    }
}
