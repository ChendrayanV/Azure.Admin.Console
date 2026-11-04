---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACAksAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACAksAssessment
---

# Invoke-AACAksAssessment

## SYNOPSIS

Assesses AKS clusters through every lens - current settings, the Well-Architected Framework, PSRule for Azure, Azure Policy for Kubernetes (consolidated by namespace, workload, policy and cluster), versions and upgrades, capacity, Advisor and Defender - with a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACAksAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-SuppressionFile] <string>]
 [[-PreviousPath] <string>] [[-Baseline] <string>] [[-ExcludeRule] <string[]>] [[-CsvPath] <string>]
 [[-PdfPath] <string>] [[-HtmlPath] <string>] [[-Title] <string>] [-IncludeSystemNamespace]
 [-IncludeConstraint] [-IncludeWorkload] [-SkipPSRule] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only (Reader is enough; -IncludeConstraint needs more, below),
REST only - no Az modules, no kubectl. For each cluster:

```text
  Current settings  every setting that matters, by area: general
                    (version, tier, support plan, power state),
                    upgrades (channels, maintenance windows),
                    identity and access (Entra ID, Azure RBAC, local
                    accounts, workload identity), networking
                    (plugin, dataplane, policy, outbound, CIDRs,
                    private cluster, authorized ranges), security
                    (Defender, Azure Policy, KMS, image cleaner, Key
                    Vault provider, node resource group lockdown),
                    monitoring (Container insights, Prometheus, cost
                    analysis, diagnostic settings), add-ons and the
                    autoscaler profile - and each node pool: size,
                    mode, OS, nodes, autoscale, zones, max pods,
                    versions, node image and its age, disks, Spot,
                    subnet, taints
  Well-Architected  about 50 checks across the five pillars -
                    Reliability (SLA tier, zones, system pool and its
                    taint, Spot, burstable sizes, version support,
                    maintenance, surge), Security (local accounts,
                    Kubernetes RBAC, Entra ID, Azure RBAC, API server
                    exposure, private API server, network policy,
                    Azure Policy, Defender, OIDC issuer, workload
                    identity, pod identity, user-assigned identity,
                    image cleaner, KMS, Key Vault provider, dashboard
                    add-on, Azure Linux, node public IPs, encryption
                    at host, managed identity, node images, lockdown;
                    with -IncludeConstraint, whether allowed images
                    and privileged containers are enforced),
                    Operational Excellence (upgrade channels,
                    Container insights, Prometheus, audit logs,
                    version drift, retired add-ons, managed ingress,
                    node resource group name), Cost Optimization
                    (autoscaler or node auto-provisioning, vertical
                    pod autoscaler, cost analysis) and Performance
                    Efficiency (ephemeral OS disks, OS disk size, VM
                    generation, kubenet, Cilium, KEDA, load balancer,
                    subnet IPs at full scale) - Pass or Fail, a score
                    per pillar. Several of these follow KubeBuddy's
                    AKS checks (github.com/KubeDeckio/KubeBuddy)
  PSRule for Azure  the Azure.AKS.* rules (unless -SkipPSRule), on
                    the cluster as Export-AzRuleData reads it -
                    -Baseline and -ExcludeRule as for Invoke-AACPSRule
  Azure Policy      the AKS Policy Compliance Toolkit's view
                    (github.com/sam-cogan/aks-policy-compliance-toolkit):
                    every non-compliant pod, service or network
                    policy, with its namespace and workload (inferred
                    from the pod's name), policy and effect - and the
                    same rolled up by namespace, by workload, by
                    policy and by cluster; the policies evaluated on
                    each cluster resource; the assignments
  Gatekeeper        with -IncludeConstraint: each constraint's
                    complete violation count from inside the cluster
                    (Azure Policy keeps 500 records per policy and
                    cluster), with AKS run command
  In the cluster    with -IncludeWorkload: what is running, read with
                    AKS run command - health (failing, pending and
                    restarting pods, nodes, services, volumes),
                    workload design (requests, limits, probes,
                    replicas, spread, disruption budgets), pod security
                    (privileged, host namespaces and paths, capabilities,
                    seccomp, root), namespaces (network policies, quotas,
                    limit ranges), RBAC (cluster-admin, wide access,
                    default service accounts) and network and storage -
                    many following KubeBuddy's checks
                    (github.com/KubeDeckio/KubeBuddy). Their failures
                    are findings, but not in the WAF score
  AKS Automatic     with -IncludeWorkload: what would stop these workloads
                    moving to a new AKS Automatic cluster, from Microsoft's
                    Deployment Safeguards and baseline Pod Security
                    Standards - Fix first (refused), Changed by Automatic
                    (admitted but altered) and Review
  Versions          the control plane's version and its support
                    (supported, long-term support, out of support),
                    the upgrades available, how far behind the
                    newest it is; each pool's version and node image,
                    and the newest node image
  Advisor, Defender the clusters' Advisor recommendations and
                    retirements, and Defender for Cloud's unhealthy
                    assessments
```

Every failed check and rule, recommendation and policy finding is a
finding, with its severity, pillar, source and what to do.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the clusters with their WAF scores, the
                   pillars, the High and Medium findings, policy
                   compliance by namespace, and - for up to three
                   clusters - each in detail, a page at a time
  piped onward     the AAC.AksCluster objects (each with its
                   NodePools, Settings, Checks, Findings, Upgrades
                   and PolicyViolations), with no view
  -PassThru        the view and the objects
  -NoDisplay       the objects only
```

-CsvPath (a folder) writes a CSV per table - and the non-compliant
workloads per namespace, as the toolkit exports them. -HtmlPath writes
an interactive report with every table; -PdfPath a PDF with a
section per cluster.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACAksAssessment
```

Every AKS cluster the account can see, assessed.

### Example 2

```powershell
Invoke-AACAksAssessment -Name 'aks-prod-*' -HtmlPath .\out\AKS.html -PdfPath .\out\AKS.pdf -CsvPath .\out\aks
```

The production clusters, with every report.

### Example 3

```powershell
Invoke-AACAksAssessment -ManagementGroupId 'mg-landingzones' -IncludeConstraint -NoDisplay | Select-Object -ExpandProperty PolicyViolations | Group-Object Namespace
```

Kubernetes policy violations by namespace, with Gatekeeper's complete counts - before moving policies from Audit to Deny.

### Example 4

```powershell
Invoke-AACAksAssessment -Name 'aks-prod-weu' -IncludeWorkload -HtmlPath .\out\AKS.html
```

Also what runs inside the cluster - health, probes, requests, pod security, RBAC - and whether it could move to AKS Automatic.

### Example 5

```powershell
(Invoke-AACAksAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -NoDisplay).Checks | Where-Object { $_.Status -eq 'Fail' -and $_.Pillar -eq 'Security' }
```

The failed Well-Architected security checks.

## PARAMETERS

### -Baseline

The PSRule for Azure baseline (Azure.Default by default), e.g.
Azure.GA_2024_12.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CsvPath

A folder to write a CSV per table to.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ExcludeRule

PSRule rules to leave out, by name or wildcard.

```yaml
Type: System.String[]
DefaultValue: '@()'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -HtmlPath

Write an interactive HTML report to this file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeConstraint

Read the Gatekeeper constraints' complete violation counts from
inside each cluster with AKS run command. Needs the
Microsoft.ContainerService/managedClusters/runCommand/action
permission (Azure Kubernetes Service Cluster Admin, Contributor) and
run command allowed on the cluster; it starts a short-lived pod in
the aks-command namespace.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeSystemNamespace

Keep kube-system, gatekeeper-system and the other system namespaces
in the policy compliance views (they are left out by default).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeWorkload

Read what is running inside each cluster with AKS run command, and assess
it. Needs the Microsoft.ContainerService/managedClusters/runCommand/action
permission and run command allowed on the cluster, and starts two
short-lived pods in the aks-command namespace. It changes nothing else. On
a cluster with Entra ID it reads what your account may see in Kubernetes:
what it may not read shows as Not checked. Secrets and ConfigMaps are not
read, and no environment variable's value leaves the cluster. Run command's
output stops at 512 kB: a check that didn't see everything says Not checked
rather than Pass. -IncludeSystemNamespace also takes in the system
namespaces.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ManagementGroupId

Only the clusters under these management groups.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

Only these clusters; wildcards work, e.g. 'aks-prod-\*'.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the objects without showing the view.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoPaging

Show the whole view at once instead of a page at a time.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Show the view and also return the objects.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PdfPath

Write a PDF report to this file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PreviousPath

A findings CSV from an earlier run (-CsvPath), or the folder holding its
findings.csv: each finding is then marked New or Open, and the report
lists what has been resolved.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only the clusters in these resource groups.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipPSRule

Don't run PSRule for Azure.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SubscriptionId

Only the clusters in these subscriptions.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SuppressionFile

A JSON file of findings you have reviewed and accepted. Each entry names a
finding by its FindingKey, or by source and rule (and a subject, wildcards
allowed), with the reason and, if you like, an expiry date:
[{ "key": "a1b2c3d4e5f60718", "reason": "Accepted risk", "expires": "2027-01-01" }].
They leave the counts and the findings, and the report lists them with
their reasons. An expired entry is reported and ignored; a file that can't
be understood stops the command.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'AKS cluster assessment'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.AksCluster (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACAksAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
