function Get-AACArchitectureCatalog {
    <#
    .SYNOPSIS
        The architecture catalog: the probe questions, the components a
        design is built from, the cloud design patterns and the validation
        rules - one versioned set every Architecture command reads.
    .DESCRIPTION
        Returns @{ Version; Questions; Patterns; Rules; Pillars }.

          Questions  @{ Id; Category; Text; Help; Type (Choice, MultiChoice,
                     Number, Text); Choices; Default (a value, or a script
                     block over the answers so far); Pillar; Ask (a script
                     block: is the question asked, given the answers so far) }
          Patterns   @{ Id; Name; Link; Problem; Effect (pillar -> -2..+2);
                     Fit (script block over the answers -> @(@{ Points;
                     Reason })); Adds (component kinds the design gets) }
          Rules      @{ Id; Title; Pillar; Severity (Blocking, High, Medium,
                     Low); Scope (Design, or component kinds); Test (script
                     block -> $true when the design breaks the rule: param(
                     $Design, $Node, $Answers, $Context)); Policy (a built-in
                     policy's display name, resolved to its ID live); PSRule
                     (a PSRule for Azure rule); Advisor (an Advisor category);
                     Remediation; Link }

        The policy display names and PSRule rule names are references to
        check: Microsoft renames and versions them, so a catalog update
        verifies them against live data before it ships. The organisation's
        own rules come in as guardrails (Test-AACArchitectureDesign
        -GuardrailPath). Pattern links point to the Azure Architecture Center
        (learn.microsoft.com/azure/architecture/patterns), WAF links to the
        Well-Architected Framework.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $num = { param($Value, [double] $Default = 0) $n = 0.0; if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$n)) { $n } else { $Default } }
    $sensitive = { param($A) $A['SEC-01'] -in 'Confidential', 'Regulated' }
    $critical = { param($A) $A['BUS-02'] -in 'Mission-critical', 'Business-critical' }

    $questions = @(
        # --- Business --------------------------------------------------------------------------------------------
        @{ Id = 'BUS-01'; Category = 'Business'; Pillar = 'Operational Excellence'; Type = 'Choice'; Text = 'What kind of workload is this?'
            Help = 'Picks the starting reference architecture and the compute that fits it.'
            Choices = @('Web or API', 'Event-driven', 'Batch', 'Data and analytics', 'AI (retrieval-augmented generation)', 'Integration'); Default = 'Web or API' }
        @{ Id = 'BUS-02'; Category = 'Business'; Pillar = 'Reliability'; Type = 'Choice'; Text = 'How critical is it to the business?'
            Help = 'Sets how strictly the design is judged: the SLA, zones, regions and how much monitoring it needs.'
            Choices = @('Mission-critical', 'Business-critical', 'Internal', 'Sandbox'); Default = 'Business-critical' }
        @{ Id = 'BUS-03'; Category = 'Business'; Pillar = 'Performance Efficiency'; Type = 'Number'; Text = 'How many users (or requests a second) at peak in 12 months?'
            Help = 'Sizes the tiers and decides whether autoscale is required.'; Default = 1000 }
        # --- Reliability ----------------------------------------------------------------------------------------------
        @{ Id = 'REL-01'; Category = 'Reliability'; Pillar = 'Reliability'; Type = 'Number'; Text = 'Recovery time objective (RTO), in minutes?'
            Help = 'How long the workload may be down after a regional failure. Under 60 minutes needs a second region ready to take over.'
            Default = { param($A) switch ($A['BUS-02']) { 'Mission-critical' { 15 } 'Business-critical' { 240 } default { 1440 } } } }
        @{ Id = 'REL-02'; Category = 'Reliability'; Pillar = 'Reliability'; Type = 'Number'; Text = 'Recovery point objective (RPO), in minutes?'
            Help = 'How much data may be lost. Near zero needs synchronous or geo-replicated data stores.'
            Default = { param($A) switch ($A['BUS-02']) { 'Mission-critical' { 5 } 'Business-critical' { 60 } default { 1440 } } } }
        @{ Id = 'REL-03'; Category = 'Reliability'; Pillar = 'Reliability'; Type = 'Choice'; Text = 'Composite SLA target?'
            Help = '99.95% and above needs zone-redundant tiers; 99.99% needs more than one region.'
            Choices = @('99.9', '99.95', '99.99'); Default = { param($A) switch ($A['BUS-02']) { 'Mission-critical' { '99.99' } 'Business-critical' { '99.95' } default { '99.9' } } } }
        @{ Id = 'REL-04'; Category = 'Reliability'; Pillar = 'Reliability'; Type = 'Choice'; Text = 'Can the workload keep serving, degraded, when a dependency fails?'
            Help = 'Yes adds Circuit Breaker, Retry and Bulkhead so one failing dependency doesn''t take everything down.'; Choices = @('Yes', 'No'); Default = 'Yes' }
        # --- Security -------------------------------------------------------------------------------------------------
        @{ Id = 'SEC-01'; Category = 'Security'; Pillar = 'Security'; Type = 'Choice'; Text = 'How is the data classified?'
            Help = 'Confidential and regulated data get private endpoints, no public network access and customer-managed keys considered.'
            Choices = @('Public', 'Internal', 'Confidential', 'Regulated'); Default = 'Internal' }
        @{ Id = 'SEC-02'; Category = 'Security'; Pillar = 'Security'; Type = 'MultiChoice'; Text = 'Which regulatory frameworks apply?'
            Help = 'Each maps to a built-in Azure Policy initiative the design is checked against.'; Ask = $sensitive
            Choices = @('PCI DSS', 'HIPAA', 'ISO 27001', 'NIST SP 800-53', 'None'); Default = 'None' }
        @{ Id = 'SEC-03'; Category = 'Security'; Pillar = 'Security'; Type = 'Choice'; Text = 'How is it exposed to the internet?'
            Help = 'Inbound traffic goes through a web application firewall; outbound traffic through Azure Firewall.'
            Choices = @('None (internal only)', 'Inbound from the internet', 'Inbound and outbound'); Default = 'Inbound from the internet' }
        @{ Id = 'SEC-04'; Category = 'Security'; Pillar = 'Security'; Type = 'Choice'; Text = 'How does the workload authenticate to Azure services?'
            Help = 'Managed identities and workload identity federation have no secret to leak or rotate.'
            Choices = @('Managed identity', 'Workload identity federation', 'Secrets'); Default = 'Managed identity' }
        # --- Performance -----------------------------------------------------------------------------------------------
        @{ Id = 'PERF-01'; Category = 'Performance'; Pillar = 'Performance Efficiency'; Type = 'Choice'; Text = 'Is the workload read-heavy, balanced or write-heavy?'
            Help = 'Read-heavy workloads get a cache; very different read and write models suggest CQRS.'; Choices = @('Read-heavy', 'Balanced', 'Write-heavy'); Default = 'Balanced' }
        @{ Id = 'PERF-02'; Category = 'Performance'; Pillar = 'Performance Efficiency'; Type = 'Number'; Text = 'Response time target at the 95th percentile, in milliseconds?'
            Help = 'Under 100 ms usually needs a cache in front of the data store.'; Default = 500 }
        @{ Id = 'PERF-03'; Category = 'Performance'; Pillar = 'Performance Efficiency'; Type = 'Choice'; Text = 'Is the load steady, bursty or scheduled?'
            Help = 'Bursty load is levelled with a queue so the back end scales on its own terms.'; Choices = @('Steady', 'Bursty', 'Scheduled'); Default = 'Steady' }
        @{ Id = 'PERF-04'; Category = 'Performance'; Pillar = 'Performance Efficiency'; Type = 'Choice'; Text = 'Are the users in one geography or several?'
            Help = 'Several geographies get a global entry point (Front Door) and are checked against data residency.'; Choices = @('One region', 'Several regions'); Default = 'One region' }
        @{ Id = 'DATA-01'; Category = 'Performance'; Pillar = 'Performance Efficiency'; Type = 'Choice'; Text = 'What is the main data store?'
            Help = 'Picks the database: relational (Azure SQL), document (Cosmos DB), files (Storage) or none.'
            Choices = @('Relational', 'Document', 'Files and blobs', 'None'); Default = 'Relational' }
        # --- Cost -------------------------------------------------------------------------------------------------------
        @{ Id = 'COST-01'; Category = 'Cost'; Pillar = 'Cost Optimization'; Type = 'Number'; Text = 'Monthly budget, in your billing currency (0 if not set)?'
            Help = 'Becomes a Cost Management budget with alerts, and weighs cost in pattern selection.'; Default = 0 }
        @{ Id = 'COST-02'; Category = 'Cost'; Pillar = 'Cost Optimization'; Type = 'Choice'; Text = 'Is the steady-state baseline predictable for a year or more?'
            Help = 'A predictable baseline should be covered by reservations or a savings plan.'; Choices = @('Yes', 'No'); Default = 'No' }
        # --- Operations -------------------------------------------------------------------------------------------------
        @{ Id = 'OPS-01'; Category = 'Operations'; Pillar = 'Operational Excellence'; Type = 'Choice'; Text = 'How is it deployed?'
            Help = 'A pipeline gets a PSRule for Azure gate before deployment; manual deployment can''t be checked.'; Choices = @('GitHub Actions', 'Azure DevOps', 'Manual'); Default = 'Azure DevOps' }
        @{ Id = 'OPS-02'; Category = 'Operations'; Pillar = 'Operational Excellence'; Type = 'Choice'; Text = 'How much observability does it need?'
            Help = 'Full adds Application Insights (distributed tracing) and an alert baseline to the Log Analytics workspace.'; Choices = @('Basic', 'Full'); Default = { param($A) if (& $critical $A) { 'Full' } else { 'Basic' } } }
        @{ Id = 'OPS-03'; Category = 'Operations'; Pillar = 'Operational Excellence'; Type = 'Text'; Text = 'Which landing zone management group does it go into (blank for none)?'
            Help = 'Its inherited Azure Policy (allowed locations, Deny policies) is read live and checked at design time.'; Default = '' }
    )

    # The cloud design patterns (Azure Architecture Center), and when each fits.
    $base = 'https://learn.microsoft.com/azure/architecture/patterns'
    $patterns = @(
        @{ Id = 'cache-aside'; Name = 'Cache-Aside'; Link = "$base/cache-aside"; Problem = 'Repeated reads of the same data from a slower store.'
            Effect = @{ 'Performance Efficiency' = 2; 'Cost Optimization' = 1; Reliability = 0; Security = 0; 'Operational Excellence' = -1 }; Adds = @('cache')
            Fit = { param($A) @(if ($A['PERF-01'] -eq 'Read-heavy') { @{ Points = 3; Reason = 'read-heavy workload' } }; if ((& $num $A['PERF-02'] 500) -lt 100) { @{ Points = 3; Reason = "response target under 100 ms ($($A['PERF-02']) ms)" } }) } }
        @{ Id = 'queue-based-load-leveling'; Name = 'Queue-Based Load Leveling'; Link = "$base/queue-based-load-leveling"; Problem = 'Bursts of work that would overwhelm the back end.'
            Effect = @{ Reliability = 2; 'Performance Efficiency' = 1; 'Cost Optimization' = 1; Security = 0; 'Operational Excellence' = 0 }; Adds = @('queue')
            Fit = { param($A) @(if ($A['PERF-03'] -eq 'Bursty') { @{ Points = 4; Reason = 'bursty load' } }; if ($A['BUS-01'] -in 'Event-driven', 'Integration') { @{ Points = 2; Reason = "$($A['BUS-01']) workload" } }) } }
        @{ Id = 'competing-consumers'; Name = 'Competing Consumers'; Link = "$base/competing-consumers"; Problem = 'Messages arriving faster than one consumer can handle.'
            Effect = @{ 'Performance Efficiency' = 2; Reliability = 1; 'Cost Optimization' = 0; Security = 0; 'Operational Excellence' = 0 }; Adds = @('queue')
            Fit = { param($A) @(if ($A['PERF-03'] -eq 'Bursty' -and $A['BUS-01'] -in 'Event-driven', 'Batch', 'Integration') { @{ Points = 3; Reason = 'bursty message processing' } }) } }
        @{ Id = 'publisher-subscriber'; Name = 'Publisher-Subscriber'; Link = "$base/publisher-subscriber"; Problem = 'Several consumers that need the same events without coupling to the sender.'
            Effect = @{ 'Operational Excellence' = 1; 'Performance Efficiency' = 1; Reliability = 1; Security = 0; 'Cost Optimization' = 0 }; Adds = @('events')
            Fit = { param($A) @(if ($A['BUS-01'] -in 'Event-driven', 'Integration') { @{ Points = 4; Reason = "$($A['BUS-01']) workload" } }) } }
        @{ Id = 'claim-check'; Name = 'Claim Check'; Link = "$base/claim-check"; Problem = 'Large payloads that don''t fit (or cost too much) in a message.'
            Effect = @{ 'Cost Optimization' = 1; 'Performance Efficiency' = 1; Reliability = 0; Security = 0; 'Operational Excellence' = 0 }; Adds = @('storage')
            Fit = { param($A) @(if ($A['BUS-01'] -in 'Integration', 'Data and analytics' -and $A['DATA-01'] -eq 'Files and blobs') { @{ Points = 3; Reason = 'large files moving between services' } }) } }
        @{ Id = 'retry'; Name = 'Retry'; Link = "$base/retry"; Problem = 'Transient faults when calling a service or database.'
            Effect = @{ Reliability = 2; 'Performance Efficiency' = 0; 'Cost Optimization' = 0; Security = 0; 'Operational Excellence' = 0 }; Adds = @()
            Fit = { param($A) @(@{ Points = 2; Reason = 'every cloud workload meets transient faults' }) } }
        @{ Id = 'circuit-breaker'; Name = 'Circuit Breaker'; Link = "$base/circuit-breaker"; Problem = 'A failing dependency that callers keep waiting on.'
            Effect = @{ Reliability = 2; 'Performance Efficiency' = 1; 'Cost Optimization' = 0; Security = 0; 'Operational Excellence' = -1 }; Adds = @()
            Fit = { param($A) @(if ($A['REL-04'] -eq 'Yes') { @{ Points = 3; Reason = 'the workload can run degraded' } }; if (& $critical $A) { @{ Points = 2; Reason = "$($A['BUS-02'].ToLowerInvariant()) workload" } }) } }
        @{ Id = 'bulkhead'; Name = 'Bulkhead'; Link = "$base/bulkhead"; Problem = 'One noisy part of the system exhausting resources the rest need.'
            Effect = @{ Reliability = 2; 'Cost Optimization' = -1; 'Performance Efficiency' = 0; Security = 0; 'Operational Excellence' = 0 }; Adds = @()
            Fit = { param($A) @(if ($A['BUS-02'] -eq 'Mission-critical') { @{ Points = 3; Reason = 'mission-critical workload' } }; if ($A['REL-04'] -eq 'Yes') { @{ Points = 1; Reason = 'the workload can run degraded' } }) } }
        @{ Id = 'cqrs'; Name = 'CQRS'; Link = "$base/cqrs"; Problem = 'Read and write models that pull in different directions.'
            Effect = @{ 'Performance Efficiency' = 2; 'Operational Excellence' = -1; 'Cost Optimization' = -1; Reliability = 0; Security = 0 }; Adds = @()
            Fit = { param($A) @(if ($A['PERF-01'] -in 'Read-heavy', 'Write-heavy' -and (& $num $A['BUS-03'] 0) -ge 10000) { @{ Points = 3; Reason = "$($A['PERF-01'].ToLowerInvariant()) at scale ($($A['BUS-03']) at peak)" } }) } }
        @{ Id = 'gateway-offloading'; Name = 'Gateway Offloading'; Link = "$base/gateway-offloading"; Problem = 'TLS, the web application firewall and authentication repeated in every service.'
            Effect = @{ Security = 2; 'Operational Excellence' = 1; 'Performance Efficiency' = 0; Reliability = 0; 'Cost Optimization' = 0 }; Adds = @('gateway')
            Fit = { param($A) @(if ($A['SEC-03'] -ne 'None (internal only)') { @{ Points = 3; Reason = 'exposed to the internet' } }) } }
        @{ Id = 'valet-key'; Name = 'Valet Key'; Link = "$base/valet-key"; Problem = 'Clients uploading or downloading files through the application.'
            Effect = @{ Security = 1; 'Performance Efficiency' = 2; 'Cost Optimization' = 1; Reliability = 0; 'Operational Excellence' = 0 }; Adds = @('storage')
            Fit = { param($A) @(if ($A['DATA-01'] -eq 'Files and blobs' -and $A['SEC-03'] -ne 'None (internal only)') { @{ Points = 3; Reason = 'clients move files' } }) } }
        @{ Id = 'health-endpoint-monitoring'; Name = 'Health Endpoint Monitoring'; Link = "$base/health-endpoint-monitoring"; Problem = 'Knowing whether the application works, not only whether it runs.'
            Effect = @{ Reliability = 1; 'Operational Excellence' = 2; 'Performance Efficiency' = 0; Security = 0; 'Cost Optimization' = 0 }; Adds = @()
            Fit = { param($A) @(if (& $critical $A) { @{ Points = 3; Reason = 'load balancers and Front Door route on it' } }) } }
        @{ Id = 'deployment-stamp'; Name = 'Deployment Stamps'; Link = "$base/deployment-stamp"; Problem = 'Scaling past one deployment''s limits, or isolating tenants or regions.'
            Effect = @{ Reliability = 2; 'Performance Efficiency' = 2; 'Cost Optimization' = -2; 'Operational Excellence' = -1; Security = 0 }; Adds = @('second-region')
            Fit = { param($A) @(if ($A['BUS-02'] -eq 'Mission-critical') { @{ Points = 3; Reason = 'mission-critical workload' } }; if ((& $num $A['REL-01'] 1440) -lt 60) { @{ Points = 3; Reason = "RTO under an hour ($($A['REL-01']) min)" } }) } }
        @{ Id = 'geodes'; Name = 'Geode'; Link = "$base/geodes"; Problem = 'Users in several geographies who all need low latency and the workload to survive a region.'
            Effect = @{ Reliability = 2; 'Performance Efficiency' = 2; 'Cost Optimization' = -2; 'Operational Excellence' = -2; Security = 0 }; Adds = @('second-region', 'global-entry')
            Fit = { param($A) @(if ($A['PERF-04'] -eq 'Several regions') { @{ Points = 4; Reason = 'users in several geographies' } }; if ($A['REL-03'] -eq '99.99') { @{ Points = 2; Reason = '99.99% SLA' } }) } }
        @{ Id = 'throttling'; Name = 'Throttling'; Link = "$base/throttling"; Problem = 'Spikes or misbehaving clients exhausting capacity meant for everyone.'
            Effect = @{ Reliability = 1; 'Cost Optimization' = 1; 'Performance Efficiency' = 1; Security = 1; 'Operational Excellence' = 0 }; Adds = @('api-gateway')
            Fit = { param($A) @(if ($A['BUS-01'] -in 'Web or API', 'Integration' -and $A['SEC-03'] -ne 'None (internal only)' -and (& $num $A['BUS-03'] 0) -ge 5000) { @{ Points = 3; Reason = 'a public API at scale' } }) } }
    )

    # Validation rules. Test returns $true when the design breaks the rule.
    $waf = 'https://learn.microsoft.com/azure/well-architected'
    $isPaas = { param($Node) $Node.Kind -in 'database', 'cosmos', 'storage', 'keyvault', 'cache', 'queue', 'events', 'search', 'openai', 'datafactory', 'registry' }
    $rules = @(
        # --- Blocking: what an inherited Deny policy or a guardrail would refuse at deployment ----------------------------
        @{ Id = 'GOV-LOC-01'; Title = 'Region outside the allowed locations'; Pillar = 'Security'; Severity = 'Blocking'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $allowed = @($C['AllowedLocations'] | Where-Object { $_ }); $allowed.Count -and @($D.Regions | Where-Object { $allowed -notcontains $_ }).Count }
            Policy = 'Allowed locations'; PSRule = ''; Advisor = ''; Remediation = 'Deploy to a region the landing zone allows, or get the allowed locations changed (through the platform team) before deployment - Azure will deny it.'
            Link = 'https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies' }
        @{ Id = 'GRD-PUB-01'; Title = 'Public endpoint where the guardrails forbid one'; Pillar = 'Security'; Severity = 'Blocking'; Scope = '*'
            Test = { param($D, $N, $A, $C) $C.Guardrail['DenyPublicEndpoint'] -and (& $isPaas $N) -and $N.PublicAccess }
            Policy = ''; PSRule = ''; Advisor = ''; Remediation = 'Use a private endpoint and turn public network access off - the organisation''s guardrails deny public endpoints.'; Link = 'https://learn.microsoft.com/azure/private-link/private-endpoint-overview' }
        @{ Id = 'GRD-SKU-01'; Title = 'SKU the guardrails don''t allow'; Pillar = 'Cost Optimization'; Severity = 'Blocking'; Scope = '*'
            Test = { param($D, $N, $A, $C) $denied = @($C.Guardrail['DeniedSkus'] | Where-Object { $_ }); $denied.Count -and $N.Sku -and @($denied | Where-Object { $N.Sku -like $_ }).Count }
            Policy = ''; PSRule = ''; Advisor = ''; Remediation = 'Pick a SKU the guardrails allow.'; Link = "$waf/cost-optimization/" }
        @{ Id = 'GRD-TAG-01'; Title = 'Required tags missing'; Pillar = 'Operational Excellence'; Severity = 'Blocking'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $required = @($C.Guardrail['RequiredTags'] | Where-Object { $_ }); $required.Count -and @($required | Where-Object { -not $D.Tags.Contains($_) }).Count }
            Policy = 'Require a tag on resources'; PSRule = 'Azure.Resource.Tags'; Advisor = ''; Remediation = 'Add the required tags to the design (-Tag), so every resource is deployed with them.'; Link = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging' }
        # --- Reliability -----------------------------------------------------------------------------------------------
        @{ Id = 'REL-ZR-01'; Title = 'Not zone-redundant for the SLA asked'; Pillar = 'Reliability'; Severity = 'High'; Scope = @('app', 'functions', 'container', 'database', 'cosmos', 'storage', 'cache', 'gateway', 'firewall')
            Test = { param($D, $N, $A, $C) [double]$A['REL-03'] -ge 99.95 -and -not $N.ZoneRedundant }
            Policy = ''; PSRule = 'Azure.Redis.AvailabilityZone'; Advisor = 'HighAvailability'; Remediation = 'Use the zone-redundant SKU or setting, so a datacenter failure doesn''t take the tier down.'; Link = "$waf/reliability/regions-availability-zones" }
        @{ Id = 'REL-MR-01'; Title = 'One region for an RTO under an hour or a 99.99% SLA'; Pillar = 'Reliability'; Severity = 'High'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) ([double]$A['REL-01'] -lt 60 -or $A['REL-03'] -eq '99.99') -and @($D.Regions).Count -lt 2 }
            Policy = ''; PSRule = ''; Advisor = 'HighAvailability'; Remediation = 'Add a second region (-Region westeurope, northeurope) with replicated data, and Front Door to fail over - or relax the RTO or SLA with the business.'; Link = "$waf/reliability/disaster-recovery" }
        @{ Id = 'REL-PAT-01'; Title = 'No pattern for transient faults or failing dependencies'; Pillar = 'Reliability'; Severity = 'Medium'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) -not @($D.Patterns | Where-Object { $_ -in 'retry', 'circuit-breaker' }).Count }
            Policy = ''; PSRule = ''; Advisor = ''; Remediation = 'Use Retry (with backoff) on every call to a service, and Circuit Breaker on dependencies that can fail for a while.'; Link = "$base/retry" }
        # --- Security ----------------------------------------------------------------------------------------------------
        @{ Id = 'SEC-PE-01'; Title = 'Public network access to a data service for confidential data'; Pillar = 'Security'; Severity = 'High'; Scope = @('database', 'cosmos', 'storage', 'keyvault', 'cache', 'search', 'openai')
            Test = { param($D, $N, $A, $C) (& $sensitive $A) -and $N.PublicAccess }
            Policy = 'Storage accounts should disable public network access'; PSRule = 'Azure.Storage.Firewall'; Advisor = 'Security'; Remediation = 'Add a private endpoint in the spoke (and its private DNS zone in the hub), then disable public network access.'; Link = 'https://learn.microsoft.com/azure/private-link/private-endpoint-overview' }
        @{ Id = 'SEC-ID-01'; Title = 'Secrets instead of managed identities'; Pillar = 'Security'; Severity = 'High'; Scope = @('app', 'functions', 'container')
            Test = { param($D, $N, $A, $C) $N.Identity -eq 'Secrets' }
            Policy = 'App Service apps should use managed identity'; PSRule = 'Azure.AppService.ManagedIdentity'; Advisor = 'Security'; Remediation = 'Give the compute a managed identity (or workload identity federation for pipelines) and grant it roles on the services it calls - no secret to store, leak or rotate.'; Link = 'https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview' }
        @{ Id = 'SEC-KV-01'; Title = 'Key Vault without purge protection'; Pillar = 'Security'; Severity = 'High'; Scope = @('keyvault')
            Test = { param($D, $N, $A, $C) -not $N.Settings['PurgeProtection'] }
            Policy = 'Key vaults should have deletion protection enabled'; PSRule = 'Azure.KeyVault.PurgeProtect'; Advisor = 'Security'; Remediation = 'Enable soft delete and purge protection, so a deleted vault (and every key it holds) can be recovered.'; Link = 'https://learn.microsoft.com/azure/key-vault/general/soft-delete-overview' }
        @{ Id = 'SEC-TLS-01'; Title = 'TLS older than 1.2 allowed'; Pillar = 'Security'; Severity = 'Medium'; Scope = @('storage', 'app', 'functions', 'database', 'cache')
            Test = { param($D, $N, $A, $C) $tls = [string]$N.Settings['MinTls']; $tls -and [version]$tls -lt [version]'1.2' }
            Policy = 'Storage accounts should have the specified minimum TLS version'; PSRule = 'Azure.Storage.MinTLS'; Advisor = 'Security'; Remediation = 'Set the minimum TLS version to 1.2.'; Link = "$waf/security/encryption" }
        @{ Id = 'SEC-WAF-01'; Title = 'Exposed to the internet without a web application firewall'; Pillar = 'Security'; Severity = 'High'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $A['SEC-03'] -ne 'None (internal only)' -and -not @($D.Nodes | Where-Object { $_.Kind -eq 'gateway' -and $_.Settings['Waf'] }).Count }
            Policy = 'Web Application Firewall (WAF) should be enabled for Application Gateway'; PSRule = 'Azure.AppGw.UseWAF'; Advisor = 'Security'; Remediation = 'Put Front Door Premium (global) or Application Gateway WAF_v2 (regional) with a WAF policy in prevention mode in front of the application.'; Link = 'https://learn.microsoft.com/azure/web-application-firewall/overview' }
        @{ Id = 'SEC-EGR-01'; Title = 'Outbound internet traffic not inspected'; Pillar = 'Security'; Severity = 'Medium'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $A['SEC-03'] -eq 'Inbound and outbound' -and -not @($D.Nodes | Where-Object Kind -EQ 'firewall').Count }
            Policy = ''; PSRule = ''; Advisor = 'Security'; Remediation = 'Route outbound traffic through Azure Firewall in the hub (a route table on the spoke subnets).'; Link = 'https://learn.microsoft.com/azure/firewall/overview' }
        @{ Id = 'SEC-REG-01'; Title = 'Regulated data, but no compliance framework chosen'; Pillar = 'Security'; Severity = 'Medium'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $A['SEC-01'] -eq 'Regulated' -and @($A['SEC-02'] | Where-Object { $_ -and $_ -ne 'None' }).Count -eq 0 }
            Policy = ''; PSRule = ''; Advisor = ''; Remediation = 'Name the frameworks (PCI DSS, HIPAA, ISO 27001, NIST SP 800-53) so the matching Azure Policy initiatives are assigned and checked.'; Link = 'https://learn.microsoft.com/azure/governance/policy/samples/' }
        # --- Performance ---------------------------------------------------------------------------------------------------
        @{ Id = 'PERF-CACHE-01'; Title = 'A response target under 100 ms with no cache'; Pillar = 'Performance Efficiency'; Severity = 'Medium'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) [double]$A['PERF-02'] -lt 100 -and $A['DATA-01'] -ne 'None' -and -not @($D.Nodes | Where-Object Kind -EQ 'cache').Count }
            Policy = ''; PSRule = ''; Advisor = 'Performance'; Remediation = 'Add Azure Cache for Redis with the Cache-Aside pattern in front of the data store.'; Link = "$base/cache-aside" }
        @{ Id = 'PERF-QUE-01'; Title = 'Bursty load with no queue'; Pillar = 'Performance Efficiency'; Severity = 'Medium'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $A['PERF-03'] -eq 'Bursty' -and -not @($D.Nodes | Where-Object Kind -EQ 'queue').Count }
            Policy = ''; PSRule = ''; Advisor = 'Performance'; Remediation = 'Put a Service Bus queue between the front end and the workers (Queue-Based Load Leveling).'; Link = "$base/queue-based-load-leveling" }
        # --- Cost -----------------------------------------------------------------------------------------------------------
        @{ Id = 'COST-BUD-01'; Title = 'No budget'; Pillar = 'Cost Optimization'; Severity = 'Low'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) [double]$A['COST-01'] -le 0 }
            Policy = ''; PSRule = ''; Advisor = 'Cost'; Remediation = 'Agree a monthly budget with the workload''s owner; the design then gets a Cost Management budget with actual and forecast alerts.'; Link = "$waf/cost-optimization/" }
        @{ Id = 'COST-RI-01'; Title = 'A predictable baseline not covered by reservations or a savings plan'; Pillar = 'Cost Optimization'; Severity = 'Low'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $A['COST-02'] -eq 'Yes' -and -not $D.Commitment }
            Policy = ''; PSRule = ''; Advisor = 'Cost'; Remediation = 'Plan a reservation or savings plan for the baseline after the first month in production (-Commitment ReservedInstances or SavingsPlan).'; Link = 'https://learn.microsoft.com/azure/cost-management-billing/savings-plan/savings-plan-compute-overview' }
        # --- Operations -----------------------------------------------------------------------------------------------------
        @{ Id = 'OPS-GATE-01'; Title = 'Manual deployment - nothing checks the infrastructure before it is deployed'; Pillar = 'Operational Excellence'; Severity = 'Medium'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) $A['OPS-01'] -eq 'Manual' }
            Policy = ''; PSRule = ''; Advisor = 'OperationalExcellence'; Remediation = 'Deploy from a pipeline (GitHub Actions or Azure DevOps) with infrastructure as code and a PSRule for Azure gate (ps-rule-assert / PSRule task) before deployment.'; Link = "$waf/operational-excellence/infrastructure-as-code-design" }
        @{ Id = 'OPS-MON-01'; Title = 'Basic monitoring for a critical workload'; Pillar = 'Operational Excellence'; Severity = 'Medium'; Scope = 'Design'
            Test = { param($D, $N, $A, $C) (& $critical $A) -and $A['OPS-02'] -eq 'Basic' }
            Policy = ''; PSRule = ''; Advisor = 'OperationalExcellence'; Remediation = 'Add Application Insights (distributed tracing) and the Azure Monitor baseline alerts for each service.'; Link = "$waf/operational-excellence/observability" }
    )
    # The script blocks use the helpers above ($num, $sensitive, $isPaas...): bind them now, so they
    # still resolve when another function runs the block.
    foreach ($item in @($questions) + @($patterns) + @($rules)) {
        foreach ($key in 'Default', 'Ask', 'Fit', 'Test') { if ($item.Contains($key) -and $item[$key] -is [scriptblock]) { $item[$key] = $item[$key].GetNewClosure() } }
    }
    @{
        Version   = '2026.10.1'
        Pillars   = @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')
        Questions = $questions
        Patterns  = $patterns
        Rules     = $rules
    }
}
