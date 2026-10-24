function Get-AACWafCatalog {
    <#
    .SYNOPSIS
        The Well-Architected checks Invoke-AACWafAssessment runs: each pillar's
        design principles, and the checks that test them against the shared
        Resource Graph read.
    .DESCRIPTION
        Returns @{ Principles; Checks; Overlaps }:
          Principles  ordered: pillar -> @(@{ Name; Link; Question }), in Microsoft
                      Learn's order - a principle with no check is shown as
                      not assessed (it needs a person to attest it)
          Checks      @{ Id; Pillar; Principle; Title; Severity (High, Medium,
                      Low); Type (the resource type it tests, lower case;
                      'microsoft.resources/subscriptions' for a subscription);
                      Applies (optional: { param($Row, $Context) } - $false
                      leaves the resource out); Test ({ param($Row, $Context) }
                      - $true passes, $false fails); Recommendation; Link }
          Overlaps    @{ Pattern; Checks } - an Advisor recommendation or
                      Defender assessment whose text matches Pattern (a
                      regular expression, any case) is the same finding as
                      those catalogue checks: on a resource they tested, it
                      is counted once, by the catalogue check

        $Context.At($Row, 'properties', 'x', ...) reads a value safely (exact
        key first, then any case); $Context.Backup is the set of protected
        resource IDs; $Context.Pricing[sub][plan] the Defender plan tier;
        $Context.SecureScore[sub] the secure score as a percentage;
        $C.Extensions[vm id] the VM's extension types; $C.Autoscale the
        resource IDs an enabled autoscale setting targets; $C.Slots[site id]
        how many deployment slots an app has; $C.TypeCount[sub][type] how
        many resources of a type a subscription has; $C.CostTag and
        $C.OwnerTag the tag names that count; $C.Now the time of the run.
        Advisor and Defender fold into checks of their own in
        ConvertTo-AACWafAssessment.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $learn = 'https://learn.microsoft.com/azure/well-architected'
    $principles = [ordered]@{
        Reliability = @(
            @{ Name = 'Design for business requirements'; Link = "$learn/reliability/principles#design-for-business-requirements" }
            @{ Name = 'Design for resilience'; Link = "$learn/reliability/principles#design-for-resilience" }
            @{ Name = 'Design for recovery'; Link = "$learn/reliability/principles#design-for-recovery" }
            @{ Name = 'Design for operations'; Link = "$learn/reliability/principles#design-for-operations" }
            @{ Name = 'Keep it simple'; Link = "$learn/reliability/principles#keep-it-simple" }
        )
        Security    = @(
            @{ Name = 'Plan your security readiness'; Link = "$learn/security/principles#plan-your-security-readiness" }
            @{ Name = 'Design to protect confidentiality'; Link = "$learn/security/principles#design-to-protect-confidentiality" }
            @{ Name = 'Design to protect integrity'; Link = "$learn/security/principles#design-to-protect-integrity" }
            @{ Name = 'Design to protect availability'; Link = "$learn/security/principles#design-to-protect-availability" }
            @{ Name = 'Sustain and evolve your security posture'; Link = "$learn/security/principles#sustain-and-evolve-your-security-posture" }
        )
        'Cost Optimization'      = @(
            @{ Name = 'Develop cost-management discipline'; Link = "$learn/cost-optimization/principles#develop-cost-management-discipline" }
            @{ Name = 'Design with a cost-efficiency mindset'; Link = "$learn/cost-optimization/principles#design-with-a-cost-efficiency-mindset" }
            @{ Name = 'Design for usage optimization'; Link = "$learn/cost-optimization/principles#design-for-usage-optimization" }
            @{ Name = 'Design for rate optimization'; Link = "$learn/cost-optimization/principles#design-for-rate-optimization" }
            @{ Name = 'Monitor and optimize over time'; Link = "$learn/cost-optimization/principles#monitor-and-optimize-over-time" }
        )
        'Operational Excellence' = @(
            @{ Name = 'Embrace DevOps culture'; Link = "$learn/operational-excellence/principles#embrace-devops-culture" }
            @{ Name = 'Establish development standards'; Link = "$learn/operational-excellence/principles#establish-development-standards" }
            @{ Name = 'Evolve operations with observability'; Link = "$learn/operational-excellence/principles#evolve-operations-with-observability" }
            @{ Name = 'Deploy with confidence'; Link = "$learn/operational-excellence/principles#deploy-with-confidence" }
            @{ Name = 'Automate for efficiency'; Link = "$learn/operational-excellence/principles#automate-for-efficiency" }
        )
        'Performance Efficiency' = @(
            @{ Name = 'Negotiate realistic performance targets'; Link = "$learn/performance-efficiency/principles#negotiate-realistic-performance-targets" }
            @{ Name = 'Design to meet capacity requirements'; Link = "$learn/performance-efficiency/principles#design-to-meet-capacity-requirements" }
            @{ Name = 'Achieve and sustain performance'; Link = "$learn/performance-efficiency/principles#achieve-and-sustain-performance" }
            @{ Name = 'Improve efficiency through optimization'; Link = "$learn/performance-efficiency/principles#improve-efficiency-through-optimization" }
        )
    }

    # The questionnaire: one question per principle, for what no API can test
    # (Export-AACWafQuestionnaire writes them; -AttestationPath reads the answers).
    $questions = @{
        'Design for business requirements'         = 'Have the availability, RTO and RPO targets been agreed with the business, and does the design meet them?'
        'Design for resilience'                    = 'Does the workload keep running through the loss of an instance, a zone - and a region, if required?'
        'Design for recovery'                      = 'Are backups and failover tested regularly against the recovery targets, with a documented recovery plan?'
        'Design for operations'                    = 'Do health probes, monitoring and alerts detect failures early, with runbooks for the response?'
        'Keep it simple'                           = 'Is the design as simple as the requirements allow, without components or dependencies it doesn''t need?'
        'Plan your security readiness'             = 'Is there a security baseline, a threat model and an owner, with security in the definition of done?'
        'Design to protect confidentiality'        = 'Is data classified, encrypted in transit and at rest, and reachable only over private or restricted networks?'
        'Design to protect integrity'              = 'Are identities least-privileged (managed identities, no shared secrets), and are code and configuration changes controlled?'
        'Design to protect availability'           = 'Are the public entry points protected from DDoS and abuse (WAF, rate limiting)?'
        'Sustain and evolve your security posture' = 'Are security findings reviewed and remediated on a schedule, and is incident response practised?'
        'Develop cost-management discipline'       = 'Does the workload have a budget, cost alerts and an accountable owner, with costs allocated by tag?'
        'Design with a cost-efficiency mindset'    = 'Were cost trade-offs weighed when choosing services, tiers and regions?'
        'Design for usage optimization'            = 'Are unused and idle resources removed, and non-production scaled down or shut off outside working hours?'
        'Design for rate optimization'             = 'Are reservations, savings plans and Azure Hybrid Benefit used for steady workloads?'
        'Monitor and optimize over time'           = 'Are costs and Advisor''s cost recommendations reviewed regularly against the forecast?'
        'Embrace DevOps culture'                   = 'Does the team own the workload end to end, with shared on-call, blameless reviews and time for operational work?'
        'Establish development standards'          = 'Are infrastructure and configuration defined as code, reviewed, and named and tagged to a standard?'
        'Evolve operations with observability'     = 'Are logs, metrics and traces collected centrally, with dashboards and actionable alerts?'
        'Deploy with confidence'                   = 'Are deployments automated through a pipeline, with tests, progressive exposure and a fast rollback?'
        'Automate for efficiency'                  = 'Are repetitive operations - patching, scaling, certificate renewal, remediation - automated?'
        'Negotiate realistic performance targets'  = 'Are performance targets (latency, throughput, concurrency) defined and agreed for the key user flows?'
        'Design to meet capacity requirements'     = 'Is capacity planned for expected and peak load, with autoscaling and load tests to prove it?'
        'Achieve and sustain performance'          = 'Is performance monitored against the targets in production, with regressions caught before release?'
        'Improve efficiency through optimization'  = 'Are hot paths, data access and caching reviewed and tuned regularly?'
    }
    foreach ($pillar in @($principles.Keys)) { foreach ($p in $principles[$pillar]) { $p.Question = $questions[$p.Name] } }

    # Small helpers the checks share, all through $C (the context).
    $true1 = { param($Value) [string]$Value -eq 'True' }
    $count = { param($Value) @($Value | Where-Object { $null -ne $_ -and [string]$_ -ne '' }).Count }
    $restricted = { param($Row, $C) [string](& $C.At $Row 'properties', 'publicNetworkAccess') -eq 'Disabled' -or [string](& $C.At $Row 'properties', 'networkAcls', 'defaultAction') -eq 'Deny' }
    $paidPlan = { param($Row, $C) [string](& $C.At $Row 'sku', 'tier') -notin 'Free', 'Shared', 'Basic', 'Dynamic', 'FlexConsumption', '' }
    $planOn = { param($Row, $C, [string] $Plan) $tiers = $C.Pricing[[string](& $C.At $Row 'subscriptionId')]; $tiers -and $tiers.Contains($Plan) -and $tiers[$Plan] -eq 'Standard' }
    $managementOpen = {
        # An inbound allow from anywhere to SSH (22) or RDP (3389).
        param($Row, $C)
        foreach ($rule in @(& $C.At $Row 'properties', 'securityRules')) {
            $r = & $C.At $rule 'properties'
            if ([string](& $C.At $r 'direction') -ne 'Inbound' -or [string](& $C.At $r 'access') -ne 'Allow') { continue }
            $sources = @(@(& $C.At $r 'sourceAddressPrefix') + @(& $C.At $r 'sourceAddressPrefixes') | Where-Object { $_ } | ForEach-Object { [string]$_ })
            if (-not @($sources | Where-Object { $_ -in '*', 'Internet', 'Any', '0.0.0.0/0' }).Count) { continue }
            foreach ($spec in @(@(& $C.At $r 'destinationPortRange') + @(& $C.At $r 'destinationPortRanges') | Where-Object { $_ } | ForEach-Object { [string]$_ })) {
                if ($spec -eq '*') { return $true }
                $low, $high = if ($spec -match '^(\d+)-(\d+)$') { [int]$Matches[1], [int]$Matches[2] } elseif ($spec -match '^\d+$') { [int]$spec, [int]$spec } else { 1, 0 }
                foreach ($port in 22, 3389) { if ($port -ge $low -and $port -le $high) { return $true } }
            }
        }
        $false
    }
    $hasTag = { param($Row, $C, [string[]] $Names) $tags = & $C.At $Row 'tags'; $tags -is [System.Collections.IDictionary] -and @($tags.Keys | Where-Object { $k = $_; @($Names | Where-Object { $k -eq $_ }).Count }).Count -gt 0 }
    $anyOfType = { param($Row, $C, [string[]] $Types) $counts = $C.TypeCount[[string](& $C.At $Row 'subscriptionId')]; $counts -and @($Types | Where-Object { $counts.Contains($_) -and $counts[$_] -gt 0 }).Count -gt 0 }
    $oldSeries = '^(Basic_A|Standard_A\d|Standard_D\d+$|Standard_DS\d+$|Standard_D\d+_v2|Standard_DS\d+_v2|Standard_F\d+$|Standard_G)'
    $re = "$learn/reliability"
    $check = {
        param($Id, $Pillar, $Principle, $Title, $Severity, $Type, $Test, $Recommendation, $Link, $Applies)
        @{ Id = $Id; Pillar = $Pillar; Principle = $Principle; Title = $Title; Severity = $Severity; Type = $Type; Test = $Test; Recommendation = $Recommendation; Link = $Link; Applies = $Applies }
    }

    $checks = @(
        # --- Reliability --------------------------------------------------------------------------------------
        & $check 'RE-01' 'Reliability' 'Design for resilience' 'VM in an availability zone, availability set or scale set' 'High' 'microsoft.compute/virtualmachines' {
            param($Row, $C) (& $count (& $C.At $Row 'zones')) -gt 0 -or (& $C.At $Row 'properties', 'availabilitySet', 'id') -or (& $C.At $Row 'properties', 'virtualMachineScaleSet', 'id')
        } 'Deploy the VM into an availability zone (or a scale set across zones), so one datacentre failing doesn''t take it down.' "$re/regions-availability-zones"
        & $check 'RE-02' 'Reliability' 'Design for recovery' 'VM backed up' 'High' 'microsoft.compute/virtualmachines' {
            param($Row, $C) $C.Backup.Contains([string](& $C.At $Row 'id'))
        } 'Protect the VM with Azure Backup in a Recovery Services vault, with a policy that meets the workload''s recovery point objective.' "$re/backups"
        & $check 'RE-03' 'Reliability' 'Keep it simple' 'VM uses managed disks' 'Medium' 'microsoft.compute/virtualmachines' {
            param($Row, $C) [bool](& $C.At $Row 'properties', 'storageProfile', 'osDisk', 'managedDisk')
        } 'Move the VM to managed disks: Azure handles the storage accounts, their limits and their resilience.' 'https://learn.microsoft.com/azure/virtual-machines/managed-disks-overview'
        & $check 'RE-04' 'Reliability' 'Design for resilience' 'Storage account zone- or geo-redundant' 'Medium' 'microsoft.storage/storageaccounts' {
            param($Row, $C) [string](& $C.At $Row 'sku', 'name') -match 'ZRS|GRS'
        } 'Use ZRS, GZRS or RA-GZRS so the data survives a zone (or region) outage.' 'https://learn.microsoft.com/azure/storage/common/storage-redundancy'
        & $check 'RE-05' 'Reliability' 'Design for resilience' 'SQL database zone-redundant' 'Medium' 'microsoft.sql/servers/databases' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'zoneRedundant')
        } 'Turn on zone redundancy (General Purpose, Business Critical, Premium or Hyperscale).' 'https://learn.microsoft.com/azure/azure-sql/database/high-availability-sla' {
            param($Row, $C) (& $C.At $Row 'name') -ne 'master' -and [string](& $C.At $Row 'sku', 'tier') -notin 'Basic', 'Standard', 'System'
        }
        & $check 'RE-06' 'Reliability' 'Design for recovery' 'SQL database backups geo-redundant' 'Low' 'microsoft.sql/servers/databases' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'currentBackupStorageRedundancy') -in 'Geo', 'GeoZone'
        } 'Store backups geo-redundantly, so a database can be restored in another region.' 'https://learn.microsoft.com/azure/azure-sql/database/automated-backups-overview' { param($Row, $C) (& $C.At $Row 'name') -ne 'master' }
        & $check 'RE-07' 'Reliability' 'Design for resilience' 'App Service plan zone-redundant' 'Medium' 'microsoft.web/serverfarms' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'zoneRedundant')
        } 'Make the plan zone-redundant (Premium v3 and up), so its instances spread across zones.' 'https://learn.microsoft.com/azure/reliability/reliability-app-service' $paidPlan
        & $check 'RE-08' 'Reliability' 'Design for resilience' 'App Service plan runs 2+ instances' 'Medium' 'microsoft.web/serverfarms' {
            param($Row, $C) [int](& $C.At $Row 'sku', 'capacity') -ge 2
        } 'Run at least two instances, so one restarting or failing doesn''t stop the apps.' 'https://learn.microsoft.com/azure/reliability/reliability-app-service' $paidPlan
        & $check 'RE-09' 'Reliability' 'Design for resilience' 'Load balancer is Standard (not Basic)' 'High' 'microsoft.network/loadbalancers' {
            param($Row, $C) [string](& $C.At $Row 'sku', 'name') -ne 'Basic'
        } 'Upgrade to a Standard load balancer: Basic is retired, has no SLA and no zone redundancy.' 'https://learn.microsoft.com/azure/load-balancer/load-balancer-basic-upgrade-guidance'
        & $check 'RE-10' 'Reliability' 'Design for operations' 'Load balancer has health probes' 'Medium' 'microsoft.network/loadbalancers' {
            param($Row, $C) (& $count (& $C.At $Row 'properties', 'probes')) -gt 0
        } 'Add a health probe to each rule, so traffic stops going to an instance that is down.' 'https://learn.microsoft.com/azure/load-balancer/load-balancer-custom-probe-overview' {
            param($Row, $C) (& $count (& $C.At $Row 'properties', 'loadBalancingRules')) -gt 0
        }
        & $check 'RE-11' 'Reliability' 'Design for resilience' 'Public IP is Standard (not Basic)' 'High' 'microsoft.network/publicipaddresses' {
            param($Row, $C) [string](& $C.At $Row 'sku', 'name') -ne 'Basic'
        } 'Upgrade to a Standard public IP: Basic is retired and not zone-redundant.' 'https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-basic-upgrade-guidance'
        & $check 'RE-12' 'Reliability' 'Design for resilience' 'AKS node pools span availability zones' 'High' 'microsoft.containerservice/managedclusters' {
            param($Row, $C) $pools = @(& $C.At $Row 'properties', 'agentPoolProfiles'); $pools.Count -and -not @($pools | Where-Object { (& $count (& $C.At $_ 'availabilityZones')) -lt 2 }).Count
        } 'Spread every node pool across two or more availability zones.' 'https://learn.microsoft.com/azure/aks/availability-zones'
        & $check 'RE-13' 'Reliability' 'Design for business requirements' 'AKS on a tier with an uptime SLA' 'Medium' 'microsoft.containerservice/managedclusters' {
            param($Row, $C) [string](& $C.At $Row 'sku', 'tier') -in 'Standard', 'Premium'
        } 'Use the Standard (or Premium) tier for production: the Free tier has no financially backed SLA for the API server.' 'https://learn.microsoft.com/azure/aks/free-standard-pricing-tiers'
        & $check 'RE-14' 'Reliability' 'Design for resilience' 'Application Gateway zone-redundant with 2+ instances' 'Medium' 'microsoft.network/applicationgateways' {
            param($Row, $C) (& $count (& $C.At $Row 'zones')) -ge 2 -and ([int](& $C.At $Row 'properties', 'autoscaleConfiguration', 'minCapacity') -ge 2 -or [int](& $C.At $Row 'properties', 'sku', 'capacity') -ge 2)
        } 'Deploy a v2 Application Gateway across zones, with a minimum of two instances.' 'https://learn.microsoft.com/azure/reliability/reliability-application-gateway-v2'
        & $check 'RE-15' 'Reliability' 'Design for resilience' 'Cosmos DB multi-region or zone-redundant' 'Medium' 'microsoft.documentdb/databaseaccounts' {
            param($Row, $C) $locations = @(& $C.At $Row 'properties', 'locations'); $locations.Count -gt 1 -or @($locations | Where-Object { & $true1 (& $C.At $_ 'isZoneRedundant') }).Count
        } 'Add a second region, or turn on zone redundancy in the account''s region.' 'https://learn.microsoft.com/azure/reliability/reliability-cosmos-db-nosql'
        & $check 'RE-16' 'Reliability' 'Design for recovery' 'Cosmos DB continuous backup' 'Low' 'microsoft.documentdb/databaseaccounts' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'backupPolicy', 'type') -eq 'Continuous'
        } 'Use continuous backup, for point-in-time restore.' 'https://learn.microsoft.com/azure/cosmos-db/continuous-backup-restore-introduction'
        & $check 'RE-17' 'Reliability' 'Design for recovery' 'Recovery Services vault geo-redundant' 'Medium' 'microsoft.recoveryservices/vaults' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'redundancySettings', 'standardTierStorageRedundancy') -eq 'GeoRedundant'
        } 'Use geo-redundant storage (with cross-region restore) so backups survive a regional outage.' 'https://learn.microsoft.com/azure/backup/backup-create-recovery-services-vault'
        & $check 'RE-18' 'Reliability' 'Design for recovery' 'Key Vault soft delete on' 'Medium' 'microsoft.keyvault/vaults' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'enableSoftDelete') -ne 'False'
        } 'Keep soft delete on, so a deleted vault, key or secret can be recovered.' 'https://learn.microsoft.com/azure/key-vault/general/soft-delete-overview'

        # --- Security -----------------------------------------------------------------------------------------
        & $check 'SE-01' 'Security' 'Plan your security readiness' 'Defender for Servers on' 'High' 'microsoft.resources/subscriptions' { param($Row, $C) & $planOn $Row $C 'VirtualMachines' } 'Turn on Microsoft Defender for Servers for the subscription.' 'https://learn.microsoft.com/azure/defender-for-cloud/plan-defender-for-servers' { param($Row, $C) $C.Pricing.Contains([string](& $C.At $Row 'subscriptionId')) }
        & $check 'SE-02' 'Security' 'Plan your security readiness' 'Defender for Storage on' 'Medium' 'microsoft.resources/subscriptions' { param($Row, $C) & $planOn $Row $C 'StorageAccounts' } 'Turn on Microsoft Defender for Storage for the subscription.' 'https://learn.microsoft.com/azure/defender-for-cloud/defender-for-storage-introduction' { param($Row, $C) $C.Pricing.Contains([string](& $C.At $Row 'subscriptionId')) }
        & $check 'SE-03' 'Security' 'Plan your security readiness' 'Defender CSPM on' 'Medium' 'microsoft.resources/subscriptions' { param($Row, $C) & $planOn $Row $C 'CloudPosture' } 'Turn on Defender Cloud Security Posture Management for attack paths and governance.' 'https://learn.microsoft.com/azure/defender-for-cloud/concept-cloud-security-posture-management' { param($Row, $C) $C.Pricing.Contains([string](& $C.At $Row 'subscriptionId')) }
        & $check 'SE-04' 'Security' 'Sustain and evolve your security posture' 'Secure score 70% or more' 'Medium' 'microsoft.resources/subscriptions' {
            param($Row, $C) $C.SecureScore[[string](& $C.At $Row 'subscriptionId')] -ge 70
        } 'Work through Defender for Cloud''s recommendations, highest impact first, to raise the secure score.' 'https://learn.microsoft.com/azure/defender-for-cloud/secure-score-security-controls' { param($Row, $C) $C.SecureScore.Contains([string](& $C.At $Row 'subscriptionId')) }
        & $check 'SE-05' 'Security' 'Design to protect confidentiality' 'Storage account accepts HTTPS only' 'High' 'microsoft.storage/storageaccounts' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'supportsHttpsTrafficOnly') -ne 'False'
        } 'Require secure transfer (HTTPS only).' 'https://learn.microsoft.com/azure/storage/common/storage-require-secure-transfer'
        & $check 'SE-06' 'Security' 'Design to protect confidentiality' 'Storage account requires TLS 1.2+' 'High' 'microsoft.storage/storageaccounts' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'minimumTlsVersion') -in 'TLS1_2', 'TLS1_3'
        } 'Set the minimum TLS version to 1.2.' 'https://learn.microsoft.com/azure/storage/common/transport-layer-security-configure-minimum-version'
        & $check 'SE-07' 'Security' 'Design to protect confidentiality' 'Storage account blocks anonymous blob access' 'High' 'microsoft.storage/storageaccounts' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'allowBlobPublicAccess') -ne 'True'
        } 'Turn off anonymous (public) blob access.' 'https://learn.microsoft.com/azure/storage/blobs/anonymous-read-access-prevent'
        & $check 'SE-08' 'Security' 'Design to protect integrity' 'Storage account shared keys off' 'Medium' 'microsoft.storage/storageaccounts' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'allowSharedKeyAccess') -eq 'False'
        } 'Turn off shared key access and use Microsoft Entra ID (RBAC) instead.' 'https://learn.microsoft.com/azure/storage/common/shared-key-authorization-prevent'
        & $check 'SE-09' 'Security' 'Design to protect confidentiality' 'Storage account network-restricted' 'Medium' 'microsoft.storage/storageaccounts' $restricted 'Disable public network access, or deny by default and allow only the networks that need it (or private endpoints).' 'https://learn.microsoft.com/azure/storage/common/storage-network-security'
        & $check 'SE-10' 'Security' 'Design to protect integrity' 'Key Vault purge protection on' 'Medium' 'microsoft.keyvault/vaults' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'enablePurgeProtection')
        } 'Turn on purge protection, so deleted keys and secrets can''t be purged before the retention period ends.' 'https://learn.microsoft.com/azure/key-vault/general/soft-delete-overview'
        & $check 'SE-11' 'Security' 'Design to protect integrity' 'Key Vault uses Azure RBAC' 'Low' 'microsoft.keyvault/vaults' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'enableRbacAuthorization')
        } 'Use the Azure RBAC permission model instead of access policies.' 'https://learn.microsoft.com/azure/key-vault/general/rbac-migration'
        & $check 'SE-12' 'Security' 'Design to protect confidentiality' 'Key Vault network-restricted' 'Medium' 'microsoft.keyvault/vaults' $restricted 'Disable public network access, or deny by default and use private endpoints.' 'https://learn.microsoft.com/azure/key-vault/general/network-security'
        & $check 'SE-13' 'Security' 'Design to protect confidentiality' 'SQL server public network access off' 'Medium' 'microsoft.sql/servers' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'publicNetworkAccess') -eq 'Disabled'
        } 'Disable public network access and connect through private endpoints.' 'https://learn.microsoft.com/azure/azure-sql/database/connectivity-settings'
        & $check 'SE-14' 'Security' 'Design to protect confidentiality' 'SQL server requires TLS 1.2+' 'High' 'microsoft.sql/servers' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'minimalTlsVersion') -in '1.2', '1.3'
        } 'Set the minimum TLS version to 1.2.' 'https://learn.microsoft.com/azure/azure-sql/database/connectivity-settings#minimal-tls-version'
        & $check 'SE-15' 'Security' 'Design to protect integrity' 'SQL server Microsoft Entra-only authentication' 'Medium' 'microsoft.sql/servers' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'administrators', 'azureADOnlyAuthentication')
        } 'Turn on Microsoft Entra-only authentication, so SQL logins with passwords can''t be used.' 'https://learn.microsoft.com/azure/azure-sql/database/authentication-azure-ad-only-authentication'
        & $check 'SE-16' 'Security' 'Design to protect confidentiality' 'App Service HTTPS only' 'High' 'microsoft.web/sites' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'httpsOnly')
        } 'Turn on HTTPS only, so HTTP requests are redirected to HTTPS.' 'https://learn.microsoft.com/azure/app-service/configure-ssl-bindings#enforce-https'
        & $check 'SE-17' 'Security' 'Design to protect integrity' 'App Service uses a managed identity' 'Low' 'microsoft.web/sites' {
            param($Row, $C) [string](& $C.At $Row 'identity', 'type') -notin '', 'None'
        } 'Give the app a managed identity and use it, not secrets, to reach other Azure services.' 'https://learn.microsoft.com/azure/app-service/overview-managed-identity'
        & $check 'SE-18' 'Security' 'Design to protect confidentiality' 'NSG blocks SSH and RDP from the internet' 'High' 'microsoft.network/networksecuritygroups' {
            param($Row, $C) -not (& $managementOpen $Row $C)
        } 'Remove inbound rules that allow 22 or 3389 from anywhere; use Azure Bastion or just-in-time VM access.' 'https://learn.microsoft.com/azure/bastion/bastion-overview'
        & $check 'SE-19' 'Security' 'Design to protect confidentiality' 'VM network interface without a public IP' 'Medium' 'microsoft.network/networkinterfaces' {
            param($Row, $C) -not @(@(& $C.At $Row 'properties', 'ipConfigurations') | Where-Object { & $C.At $_ 'properties', 'publicIPAddress', 'id' }).Count
        } 'Remove the public IP; reach the VM through Bastion, a VPN or a load balancer.' 'https://learn.microsoft.com/azure/well-architected/security/networking' { param($Row, $C) [bool](& $C.At $Row 'properties', 'virtualMachine', 'id') }
        & $check 'SE-20' 'Security' 'Design to protect confidentiality' 'VM encryption at host' 'Low' 'microsoft.compute/virtualmachines' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'securityProfile', 'encryptionAtHost')
        } 'Turn on encryption at host, so temp disks and caches are encrypted too.' 'https://learn.microsoft.com/azure/virtual-machines/disk-encryption-overview'
        & $check 'SE-21' 'Security' 'Design to protect integrity' 'Container registry admin user off' 'Medium' 'microsoft.containerregistry/registries' {
            param($Row, $C) -not (& $true1 (& $C.At $Row 'properties', 'adminUserEnabled'))
        } 'Turn off the admin user; pull and push with Microsoft Entra identities.' 'https://learn.microsoft.com/azure/container-registry/container-registry-authentication'
        & $check 'SE-22' 'Security' 'Design to protect integrity' 'AKS local accounts off' 'Medium' 'microsoft.containerservice/managedclusters' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'disableLocalAccounts')
        } 'Disable local accounts, so every sign-in goes through Microsoft Entra ID.' 'https://learn.microsoft.com/azure/aks/manage-local-accounts-managed-azure-ad'
        & $check 'SE-23' 'Security' 'Design to protect integrity' 'AKS integrated with Microsoft Entra ID' 'Medium' 'microsoft.containerservice/managedclusters' {
            param($Row, $C) [bool](& $C.At $Row 'properties', 'aadProfile')
        } 'Turn on Microsoft Entra integration with Azure RBAC for Kubernetes authorization.' 'https://learn.microsoft.com/azure/aks/enable-authentication-microsoft-entra-id'
        & $check 'SE-24' 'Security' 'Design to protect availability' 'Virtual network DDoS protection' 'Low' 'microsoft.network/virtualnetworks' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'enableDdosProtection')
        } 'Protect networks with public endpoints with Azure DDoS Network Protection.' 'https://learn.microsoft.com/azure/ddos-protection/ddos-protection-overview'
        & $check 'SE-25' 'Security' 'Design to protect availability' 'Application Gateway has a WAF' 'Medium' 'microsoft.network/applicationgateways' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'sku', 'tier') -match 'WAF' -or (& $C.At $Row 'properties', 'firewallPolicy', 'id')
        } 'Use the WAF v2 tier with a WAF policy in prevention mode.' 'https://learn.microsoft.com/azure/web-application-firewall/ag/ag-overview'

        # --- Cost Optimization --------------------------------------------------------------------------------
        & $check 'CO-01' 'Cost Optimization' 'Develop cost-management discipline' 'Resource tagged for cost allocation' 'Medium' 'microsoft.compute/virtualmachines' {
            param($Row, $C) & $hasTag $Row $C $C.CostTag
        } 'Tag resources with a cost centre, project or application (Azure Policy can require and inherit them) so costs can be allocated.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging'
        & $check 'CO-02' 'Cost Optimization' 'Develop cost-management discipline' 'Storage account tagged for cost allocation' 'Low' 'microsoft.storage/storageaccounts' {
            param($Row, $C) & $hasTag $Row $C $C.CostTag
        } 'Tag resources with a cost centre, project or application so costs can be allocated.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging'
        & $check 'CO-03' 'Cost Optimization' 'Design for usage optimization' 'Managed disk attached to something' 'Medium' 'microsoft.compute/disks' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'diskState') -ne 'Unattached'
        } 'Delete the unattached disk (snapshot it first if it may be needed): it is billed in full while unused.' 'https://learn.microsoft.com/azure/virtual-machines/disks-find-unattached-portal'
        & $check 'CO-04' 'Cost Optimization' 'Design for usage optimization' 'Public IP associated with something' 'Low' 'microsoft.network/publicipaddresses' {
            param($Row, $C) (& $C.At $Row 'properties', 'ipConfiguration', 'id') -or (& $C.At $Row 'properties', 'natGateway', 'id')
        } 'Delete the unassociated public IP: Standard public IPs are billed whether used or not.' 'https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-addresses'
        & $check 'CO-05' 'Cost Optimization' 'Design for usage optimization' 'VM not stopped while still billed' 'High' 'microsoft.compute/virtualmachines' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'extended', 'instanceView', 'powerState', 'code') -ne 'PowerState/stopped'
        } 'Deallocate the VM (Stop in the portal, or Stop-AzVM) - a VM stopped from inside the OS keeps billing for its compute.' 'https://learn.microsoft.com/azure/virtual-machines/states-billing'
        & $check 'CO-06' 'Cost Optimization' 'Design for usage optimization' 'App Service plan hosts apps' 'Medium' 'microsoft.web/serverfarms' {
            param($Row, $C) [int](& $C.At $Row 'properties', 'numberOfSites') -gt 0
        } 'Delete the empty plan, or move apps onto it: a plan is billed with no apps on it.' 'https://learn.microsoft.com/azure/app-service/overview-manage-costs' $paidPlan
        & $check 'CO-07' 'Cost Optimization' 'Design for usage optimization' 'Snapshot younger than 90 days' 'Low' 'microsoft.compute/snapshots' {
            param($Row, $C) $created = & $C.At $Row 'properties', 'timeCreated'; -not $created -or ([datetime]$created) -gt $C.Now.AddDays(-90)
        } 'Delete snapshots you no longer need, or keep backups in Azure Backup with a retention policy.' 'https://learn.microsoft.com/azure/virtual-machines/snapshot-copy-managed-disk'
        & $check 'CO-08' 'Cost Optimization' 'Design for rate optimization' 'Windows VM uses Azure Hybrid Benefit' 'Medium' 'microsoft.compute/virtualmachines' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'licenseType') -in 'Windows_Server', 'Windows_Client'
        } 'If you have Windows Server licences with Software Assurance, apply Azure Hybrid Benefit to pay only the base compute rate.' 'https://learn.microsoft.com/azure/virtual-machines/windows/hybrid-use-benefit-licensing' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'storageProfile', 'osDisk', 'osType') -eq 'Windows'
        }
        & $check 'CO-09' 'Cost Optimization' 'Design for rate optimization' 'SQL database uses Azure Hybrid Benefit' 'Low' 'microsoft.sql/servers/databases' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'licenseType') -eq 'BasePrice'
        } 'If you have SQL Server licences with Software Assurance, set the licence type to BasePrice (Azure Hybrid Benefit).' 'https://learn.microsoft.com/azure/azure-sql/azure-hybrid-benefit' {
            param($Row, $C) (& $C.At $Row 'name') -ne 'master' -and [string](& $C.At $Row 'properties', 'licenseType') -ne ''
        }
        & $check 'CO-10' 'Cost Optimization' 'Design with a cost-efficiency mindset' 'VM on a current-generation size' 'Low' 'microsoft.compute/virtualmachines' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'hardwareProfile', 'vmSize') -notmatch $oldSeries
        } 'Move to a current-generation size (v5 or later): newer series give more performance for the price.' 'https://learn.microsoft.com/azure/virtual-machines/sizes/overview'
        & $check 'CO-11' 'Cost Optimization' 'Develop cost-management discipline' 'Resource group tagged for cost allocation' 'Low' 'microsoft.resources/subscriptions/resourcegroups' {
            param($Row, $C) & $hasTag $Row $C $C.CostTag
        } 'Tag the resource group with a cost centre or project, and let resources inherit it with Azure Policy.' 'https://learn.microsoft.com/azure/cost-management-billing/costs/enable-tag-inheritance'

        # --- Operational Excellence -----------------------------------------------------------------------------
        & $check 'OE-01' 'Operational Excellence' 'Establish development standards' 'Resource group has owner and environment tags' 'Medium' 'microsoft.resources/subscriptions/resourcegroups' {
            param($Row, $C) (& $hasTag $Row $C $C.OwnerTag) -and (& $hasTag $Row $C @('Environment', 'Env'))
        } 'Tag every resource group with its owner and environment, and require the tags with Azure Policy.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging'
        & $check 'OE-02' 'Operational Excellence' 'Evolve operations with observability' 'VM has the Azure Monitor agent' 'Medium' 'microsoft.compute/virtualmachines' {
            param($Row, $C) @($C.Extensions[[string](& $C.At $Row 'id')] | Where-Object { $_ -in 'AzureMonitorWindowsAgent', 'AzureMonitorLinuxAgent' }).Count -gt 0
        } 'Install the Azure Monitor agent with a data collection rule, so the VM''s logs and performance counters reach Log Analytics.' 'https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-overview'
        & $check 'OE-03' 'Operational Excellence' 'Evolve operations with observability' 'VM boot diagnostics on' 'Low' 'microsoft.compute/virtualmachines' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'diagnosticsProfile', 'bootDiagnostics', 'enabled')
        } 'Turn on boot diagnostics (with managed storage), to troubleshoot a VM that won''t start.' 'https://learn.microsoft.com/azure/virtual-machines/boot-diagnostics'
        & $check 'OE-04' 'Operational Excellence' 'Evolve operations with observability' 'App Service connected to Application Insights' 'Medium' 'microsoft.web/sites' {
            param($Row, $C) $tags = & $C.At $Row 'tags'; $tags -is [System.Collections.IDictionary] -and @($tags.Keys | Where-Object { $_ -like 'hidden-link*app-insights-resource-id*' }).Count -gt 0
        } 'Connect the app to a workspace-based Application Insights resource for requests, failures and dependencies.' 'https://learn.microsoft.com/azure/azure-monitor/app/codeless-app-service'
        & $check 'OE-05' 'Operational Excellence' 'Evolve operations with observability' 'Subscription has alert rules' 'High' 'microsoft.resources/subscriptions' {
            param($Row, $C) & $anyOfType $Row $C @('microsoft.insights/metricalerts', 'microsoft.insights/scheduledqueryrules', 'microsoft.insights/activitylogalerts')
        } 'Create alert rules for the signals that matter (Azure Monitor baseline alerts are a start), routed to an action group.' 'https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview'
        & $check 'OE-06' 'Operational Excellence' 'Evolve operations with observability' 'Subscription has an action group' 'Medium' 'microsoft.resources/subscriptions' {
            param($Row, $C) & $anyOfType $Row $C @('microsoft.insights/actiongroups')
        } 'Create an action group (e-mail, Teams, ITSM) so alerts reach the people who act on them.' 'https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups'
        & $check 'OE-07' 'Operational Excellence' 'Deploy with confidence' 'Web app has a deployment slot' 'Low' 'microsoft.web/sites' {
            param($Row, $C) [int]$C.Slots[[string](& $C.At $Row 'id')] -gt 0
        } 'Deploy to a staging slot and swap, for zero-downtime releases and an instant rollback.' 'https://learn.microsoft.com/azure/app-service/deploy-staging-slots' {
            param($Row, $C) [string](& $C.At $Row 'kind') -notmatch 'functionapp|workflowapp'
        }
        & $check 'OE-08' 'Operational Excellence' 'Automate for efficiency' 'VM patched by the platform' 'Medium' 'microsoft.compute/virtualmachines' {
            param($Row, $C) $os = & $C.At $Row 'properties', 'osProfile'; $patch = if (& $C.At $os 'windowsConfiguration') { & $C.At $os 'windowsConfiguration', 'patchSettings' } else { & $C.At $os 'linuxConfiguration', 'patchSettings' }
            [string](& $C.At $patch 'patchMode') -eq 'AutomaticByPlatform' -or [string](& $C.At $patch 'assessmentMode') -eq 'AutomaticByPlatform'
        } 'Use Azure Update Manager: periodic assessment and platform-orchestrated patching on a maintenance schedule.' 'https://learn.microsoft.com/azure/update-manager/overview'
        & $check 'OE-09' 'Operational Excellence' 'Automate for efficiency' 'AKS automatic upgrades on' 'Medium' 'microsoft.containerservice/managedclusters' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'autoUpgradeProfile', 'upgradeChannel') -notin '', 'none'
        } 'Set an auto-upgrade channel (patch or stable) and a planned maintenance window.' 'https://learn.microsoft.com/azure/aks/auto-upgrade-cluster'

        # --- Performance Efficiency -----------------------------------------------------------------------------
        & $check 'PE-01' 'Performance Efficiency' 'Design to meet capacity requirements' 'App Service plan scales automatically' 'Medium' 'microsoft.web/serverfarms' {
            param($Row, $C) $C.Autoscale.Contains([string](& $C.At $Row 'id')) -or (& $true1 (& $C.At $Row 'properties', 'elasticScaleEnabled'))
        } 'Turn on autoscale (rules or automatic scaling), so the plan adds instances under load.' 'https://learn.microsoft.com/azure/app-service/manage-automatic-scaling' {
            param($Row, $C) [string](& $C.At $Row 'sku', 'tier') -notin 'Free', 'Shared', 'Basic', 'Dynamic', 'FlexConsumption', ''
        }
        & $check 'PE-02' 'Performance Efficiency' 'Design to meet capacity requirements' 'Scale set scales automatically' 'Medium' 'microsoft.compute/virtualmachinescalesets' {
            param($Row, $C) $C.Autoscale.Contains([string](& $C.At $Row 'id'))
        } 'Add an autoscale setting, so the scale set grows and shrinks with demand.' 'https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-autoscale-overview' {
            param($Row, $C) [string](& $C.At $Row 'tags', 'aks-managed-poolName') -eq ''
        }
        & $check 'PE-03' 'Performance Efficiency' 'Design to meet capacity requirements' 'AKS cluster autoscaler on' 'Medium' 'microsoft.containerservice/managedclusters' {
            param($Row, $C) @(@(& $C.At $Row 'properties', 'agentPoolProfiles') | Where-Object { & $true1 (& $C.At $_ 'enableAutoScaling') }).Count -gt 0
        } 'Turn on the cluster autoscaler on the node pools that run workloads.' 'https://learn.microsoft.com/azure/aks/cluster-autoscaler'
        & $check 'PE-04' 'Performance Efficiency' 'Design to meet capacity requirements' 'Application Gateway autoscales' 'Low' 'microsoft.network/applicationgateways' {
            param($Row, $C) [bool](& $C.At $Row 'properties', 'autoscaleConfiguration')
        } 'Use v2 with an autoscale configuration (minimum and maximum instances).' 'https://learn.microsoft.com/azure/application-gateway/application-gateway-autoscaling-zone-redundant'
        & $check 'PE-05' 'Performance Efficiency' 'Achieve and sustain performance' 'VM network interface has accelerated networking' 'Low' 'microsoft.network/networkinterfaces' {
            param($Row, $C) & $true1 (& $C.At $Row 'properties', 'enableAcceleratedNetworking')
        } 'Turn on accelerated networking (on sizes that support it) for lower latency and higher throughput.' 'https://learn.microsoft.com/azure/virtual-network/accelerated-networking-overview' { param($Row, $C) [bool](& $C.At $Row 'properties', 'virtualMachine', 'id') }
        & $check 'PE-06' 'Performance Efficiency' 'Achieve and sustain performance' 'VM OS disk is SSD' 'Medium' 'microsoft.compute/virtualmachines' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'storageProfile', 'osDisk', 'managedDisk', 'storageAccountType') -notmatch '^Standard_LRS$'
        } 'Use Premium SSD (or at least Standard SSD) for OS disks: Standard HDD has the lowest IOPS and no single-instance SLA.' 'https://learn.microsoft.com/azure/virtual-machines/disks-types'
        & $check 'PE-07' 'Performance Efficiency' 'Achieve and sustain performance' 'SQL database above the Basic tier' 'Low' 'microsoft.sql/servers/databases' {
            param($Row, $C) [string](& $C.At $Row 'sku', 'tier') -ne 'Basic'
        } 'Basic (5 DTUs) suits only tiny workloads: size production databases on vCore or Standard/Premium.' 'https://learn.microsoft.com/azure/azure-sql/database/service-tiers-sql-database-vcore' { param($Row, $C) (& $C.At $Row 'name') -ne 'master' }
        & $check 'PE-08' 'Performance Efficiency' 'Achieve and sustain performance' 'Azure Cache for Redis above Basic' 'Medium' 'microsoft.cache/redis' {
            param($Row, $C) [string](& $C.At $Row 'properties', 'sku', 'name') -ne 'Basic'
        } 'Basic is a single node with no SLA: use Standard or Premium for production.' 'https://learn.microsoft.com/azure/azure-cache-for-redis/cache-overview#service-tiers'
    )
    # The tests run later, elsewhere: bind them to the helpers above.
    foreach ($c in $checks) {
        $c.Test = $c.Test.GetNewClosure()
        if ($c.Applies) { $c.Applies = $c.Applies.GetNewClosure() }
    }
    # Advisor's and Defender's wording for what a catalogue check already
    # tests. Best effort, by text: extend it when a duplicate slips through.
    $overlaps = @(
        @{ Pattern = 'availability zone|availability set'; Checks = @('RE-01', 'RE-12', 'RE-14') }
        @{ Pattern = 'enable backup|backup should be enabled|azure backup'; Checks = @('RE-02') }
        @{ Pattern = 'managed disk'; Checks = @('RE-03') }
        @{ Pattern = 'zone.?redundant storage|geo.?redundant storage|storage account.*redundan|\b(zrs|grs|gzrs)\b'; Checks = @('RE-04') }
        @{ Pattern = 'sql.*zone.?redundan|zone.?redundan.*sql'; Checks = @('RE-05') }
        @{ Pattern = 'app service.*zone.?redundan|zone.?redundan.*app service'; Checks = @('RE-07') }
        @{ Pattern = 'scale out.*app service|app service.*(two|2|multiple) instances|more than one instance'; Checks = @('RE-08') }
        @{ Pattern = 'basic.*load balancer|load balancer.*basic|standard (sku )?load balancer'; Checks = @('RE-09') }
        @{ Pattern = 'health probe'; Checks = @('RE-10') }
        @{ Pattern = 'basic.*public ip|public ip.*basic|standard sku public ip'; Checks = @('RE-11') }
        @{ Pattern = 'uptime sla|standard tier.*(aks|kubernetes)|(aks|kubernetes).*standard tier'; Checks = @('RE-13') }
        @{ Pattern = 'cosmos.*(multi|additional|second).?region|cosmos.*zone'; Checks = @('RE-15') }
        @{ Pattern = 'continuous backup'; Checks = @('RE-16') }
        @{ Pattern = 'cross.?region restore|geo.?redundan.*vault|vault.*geo.?redundan'; Checks = @('RE-17') }
        @{ Pattern = 'key vault.*soft delete|soft delete.*key vault'; Checks = @('RE-18') }
        @{ Pattern = 'secure transfer|storage.*https'; Checks = @('SE-05') }
        @{ Pattern = 'storage.*tls|tls.*storage'; Checks = @('SE-06') }
        @{ Pattern = 'blob public access|anonymous.*(blob|read access)|public access should be disallowed'; Checks = @('SE-07') }
        @{ Pattern = 'shared key'; Checks = @('SE-08') }
        @{ Pattern = 'storage.*(private link|network access|virtual network rules|public network)'; Checks = @('SE-09') }
        @{ Pattern = 'purge protection|deletion protection'; Checks = @('SE-10') }
        @{ Pattern = 'key vault.*rbac|rbac permission model'; Checks = @('SE-11') }
        @{ Pattern = 'key vault.*(private link|public network|firewall)'; Checks = @('SE-12') }
        @{ Pattern = 'sql.*public network access'; Checks = @('SE-13') }
        @{ Pattern = 'sql.*tls'; Checks = @('SE-14') }
        @{ Pattern = '(entra|azure ad|azure active directory)[- ]only authentication'; Checks = @('SE-15') }
        @{ Pattern = '(app service|web app|function app|web application).*https'; Checks = @('SE-16') }
        @{ Pattern = 'managed identity.*(web app|app service|function)|(web app|app service|function app).*managed identity'; Checks = @('SE-17') }
        @{ Pattern = 'management ports|just-in-time|internet-facing virtual machines'; Checks = @('SE-18') }
        @{ Pattern = 'public ip.*virtual machine|virtual machine.*public ip'; Checks = @('SE-19') }
        @{ Pattern = 'encrypt temp disks|encryption at host'; Checks = @('SE-20') }
        @{ Pattern = 'container registr.*admin|admin (user|account).*container registr'; Checks = @('SE-21') }
        @{ Pattern = 'kubernetes.*local auth|local (accounts|authentication).*kubernetes|aks.*local account'; Checks = @('SE-22') }
        @{ Pattern = 'kubernetes.*(entra|azure ad|aad)|(entra|azure ad|aad).*kubernetes'; Checks = @('SE-23') }
        @{ Pattern = 'ddos'; Checks = @('SE-24') }
        @{ Pattern = 'web application firewall|\bwaf\b'; Checks = @('SE-25') }
        @{ Pattern = 'unassociated public ip|public ip addresses? (not|that are not) associated|delete .*public ip'; Checks = @('CO-04') }
        @{ Pattern = 'hybrid benefit'; Checks = @('CO-08', 'CO-09') }
        @{ Pattern = 'azure monitor agent'; Checks = @('OE-02') }
        @{ Pattern = 'boot diagnostics'; Checks = @('OE-03') }
        @{ Pattern = 'application insights'; Checks = @('OE-04') }
        @{ Pattern = 'deployment slot'; Checks = @('OE-07') }
        @{ Pattern = 'update manager|patch orchestration|periodically check for missing system updates'; Checks = @('OE-08') }
        @{ Pattern = 'auto.?upgrade'; Checks = @('OE-09') }
        @{ Pattern = 'cluster autoscaler'; Checks = @('PE-03') }
        @{ Pattern = 'autoscal'; Checks = @('PE-01', 'PE-02', 'PE-04') }
        @{ Pattern = 'accelerated networking'; Checks = @('PE-05') }
        @{ Pattern = 'premium (ssd|storage|disk)'; Checks = @('PE-06') }
        @{ Pattern = 'redis.*(standard|premium)|basic.*redis'; Checks = @('PE-08') }
    )
    @{ Principles = $principles; Checks = $checks; Overlaps = $overlaps }
}
