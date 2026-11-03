---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACServiceBlueprint.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: New-AACServiceBlueprint
---

# New-AACServiceBlueprint

## SYNOPSIS

Plans the Azure services you name: what your tenant's Azure Policy allows, what PSRule for Azure says about a secure configuration, the alerts and resiliency guidance that go with them, the resources' names, and a diagram in draw.io, HTML or PDF.

## SYNTAX

### __AllParameterSets

```
New-AACServiceBlueprint [-Service] <string[]> [-SubscriptionId <string>]
 [-ManagementGroupId <string>] [-Region <string>] [-NamingConvention <string>] [-Workload <string>]
 [-Environment <string>] [-Instance <string>] [-Tag <IDictionary>] [-OutputFormat <string[]>]
 [-Path <string>] [-SkipPSRule] [-Title <string>] [-Force] [-Show] [-PassThru] [-NoDisplay]
 [-NoPaging] [-WhatIf] [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Name the services; nothing is deployed and nothing in Azure changes.
For each one the blueprint plans a secure starting configuration -
private, no shared keys or local authentication, TLS 1.2, a managed
identity, zone redundancy and soft delete where the service has them -
and checks it.

```text
  Naming      -NamingConvention filled in for each resource and checked
              against what Azure accepts for that type. A name that
              can't be used is reported, never shortened.
  Azure Policy  with -SubscriptionId: the policies in force for each
              type (Get-AACAssignedPolicy), the guardrails (allowed
              region and resource types, public network access) and
              Azure's own verdict on each planned resource
              (checkPolicyRestrictions). With -ManagementGroupId: what
              is assigned and the guardrails, no verdicts; Azure answers
              that question for a subscription. With neither: policy
              isn't read, no sign-in is needed, and the report says so.
  PSRule      PSRule for Azure's rules on each planned resource, as a
              deployment would present it. Rules about what a blueprint
              doesn't plan, such as an Event Hubs namespace's hubs, fail
              until you add it: they are a to-do list. The module's own
              naming rule is left out: -NamingConvention decides the
              names here. -SkipPSRule leaves PSRule out.

  Alerts      what Azure Monitor Baseline Alerts (AMBA) suggests for each
              type, as Get-AACAlertBaseline shows it.
  Resiliency  what the Azure Proactive Resiliency Library (APRL)
              recommends, as Get-AACResiliencyRecommendation shows it.
              Alerts and recommendations are suggestions, not results,
              so they don't change a resource's status.
```

Each resource is Blocked, Needs attention, Ready or Not fully checked.
Not checked is never reported as ready.

DeployIfNotExists and AuditIfNotExists policies look at other resources
after a deployment, so Azure gives no verdict on them beforehand. They
are listed on the Policies tab, not counted as passed or failed.

Services come from Azure's own list, the one behind the portal's New
support request page: tab completes them once you have run Connect-AAC,
and a resource type works too. That list says what a service's resource
types are, and nothing about how to configure one. So only FunctionApp
(with its plan), StorageAccount, EventHub and EventGrid, which have a
hand-checked secure configuration, get Azure Policy's verdict and PSRule.
Any other service is planned as its resource types, with the policies in
force, the guardrails, the alerts and the recommendations; it is never
better than Not fully checked, and its names aren't checked against
Azure's rules. Those four need no sign-in. A Function App needs a storage
account at run time: add StorageAccount, or you are told it is missing.

-OutputFormat writes to -Path. \<name\> is \<workload\>-\<env\>-blueprint:

```text
  DrawIo   <name>.drawio, editable, with a Legend page. An existing file
           isn't overwritten without -Force: it may hold your edits.
  Html     <name>.html, the diagram to pan, zoom and search, offline,
           and <name>-report.html, the tabbed report
  Pdf      <name>.pdf, the diagram (needs Microsoft Edge or Google
           Chrome), and <name>-report.pdf, the report
```

-Show opens what was written: the HTML page in your browser when there
is one, else the first file. Without -Path, the console view only.

## EXAMPLES

### Example 1

```powershell
New-AACServiceBlueprint -Service FunctionApp, StorageAccount, EventHub, EventGrid -Workload orders -Environment prod -SkipPSRule
```

The names and the resources, offline: no sign-in, no policy.

### Example 2

```powershell
Connect-AAC
New-AACServiceBlueprint -Service FunctionApp, StorageAccount -SubscriptionId $sub -Workload orders -Environment prod -Tag @{ CostCenter = 'cc-123' } -OutputFormat DrawIo, Html -Path .\out -Show
```

Checked against the subscription's policy and PSRule; the diagram and report open in the browser.

### Example 3

```powershell
New-AACServiceBlueprint -Service EventHub -ManagementGroupId 'mg-landingzones' -NamingConvention '{workload}-{type}-{env}' -Workload orders -OutputFormat Pdf -Path .\out
```

What a landing zone assigns for Event Hubs, with your own naming pattern, as PDFs.

### Example 4

```powershell
Connect-AAC
New-AACServiceBlueprint -Service 'Virtual Network', 'Key Vault' -SubscriptionId $sub -Workload orders -OutputFormat Html -Path .\out
```

Services without a secure configuration here: the policies in force, the alerts and the recommendations for their types.

### Example 5

```powershell
New-AACServiceBlueprint -Service StorageAccount -SubscriptionId $sub -NoDisplay | Where-Object Status -EQ 'Blocked'
```

In a script: whether anything would be refused.

## PARAMETERS

### -Confirm



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- cf
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

### -Environment

The {env} in the names (dev by default).

```yaml
Type: System.String
DefaultValue: "'dev'"
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

### -Force

Overwrite an existing .drawio file.

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

### -Instance

The {instance} in the names (01 by default).

```yaml
Type: System.String
DefaultValue: "'01'"
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

The management group they would go under: what is assigned, no verdicts.

```yaml
Type: System.String
DefaultValue: None
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

### -NamingConvention

The names' pattern, from {type} (the Cloud Adoption Framework's
abbreviation), {workload}, {env}, {region} (a short code) and {instance}.
'{type}-{workload}-{env}-{region}-{instance}' by default.

```yaml
Type: System.String
DefaultValue: "'{type}-{workload}-{env}-{region}-{instance}'"
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

### -NoDisplay

Return the planned resources without showing the view.

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

Show the whole view at once.

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

### -OutputFormat

DrawIo, Html, Pdf or several; tab completes them. DrawIo when -Path is
given without it.

```yaml
Type: System.String[]
DefaultValue: None
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

Show the view and also return the planned resources.

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

### -Path

The folder to write to.

```yaml
Type: System.String
DefaultValue: None
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

### -Region

The region (westeurope by default).

```yaml
Type: System.String
DefaultValue: "'westeurope'"
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

### -Service

The services, as Azure's list names them, or a resource type. Tab completes
them; spaces, hyphens and case don't matter. Part of a name works when
only one service fits. Without Connect-AAC: FunctionApp, StorageAccount,
EventHub and EventGrid.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Show

Open what was written.

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

The subscription the resources would go in. Gives Azure's verdict.

```yaml
Type: System.String
DefaultValue: None
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

### -Tag

Tags for every planned resource, so policies and rules that require
tags can pass: @{ CostCenter = 'cc-123' }.

```yaml
Type: System.Collections.IDictionary
DefaultValue: '@{}'
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

### -Title

The diagram's and report's title.

```yaml
Type: System.String
DefaultValue: None
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

### -WhatIf



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- wi
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

### -Workload

The {workload} in the names (app by default).

```yaml
Type: System.String
DefaultValue: "'app'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ServiceBlueprintComponent (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACServiceBlueprint.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
