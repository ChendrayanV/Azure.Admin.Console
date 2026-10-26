---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACFunctionAppAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACFunctionAppAssessment
---

# Invoke-AACFunctionAppAssessment

## SYNOPSIS

Assesses Azure Function Apps end to end - the app and its plan, how it is used, its functions and triggers, configuration, networking, deployment slots and deployment center, backups, Service Connector connections, the Well-Architected Framework, PSRule for Azure, Advisor and Defender, and the last week's Activity Log - with a Spectre.Console view, objects, and CSV, PDF and a tabbed HTML report.

## SYNTAX

### __AllParameterSets

```
Invoke-AACFunctionAppAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-TimeRange] <string>]
 [[-ActivityDays] <int>] [[-Baseline] <string>] [[-ExcludeRule] <string[]>] [[-View] <string>]
 [[-ThrottleLimit] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-SkipSettings] [-SkipPSRule] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, REST only (no Az modules). Reader is enough for all but
the app settings and connection strings, which need
Microsoft.Web/sites/config/list/action (Website Contributor, or a
custom role) - without it they are left out and said so. Setting
values are never shown or written: only their names and kinds.

For each function app (Windows, Linux, containers, Flex
Consumption; not Logic Apps Standard):

```text
  App and plan      hosting (Consumption, Flex Consumption, Elastic
                    Premium, Dedicated, App Service Environment,
                    Container Apps), SKU, instances, burst, zone
                    redundancy, the plan's CPU and memory
  Usage             executions, execution units (GB-seconds),
                    requests, 5xx and 4xx, error rate, response time,
                    memory - over -TimeRange - and, on Consumption,
                    an estimated monthly cost; idle apps
  Functions         every function, its trigger (HTTP with its auth
                    level, timer with its schedule, queue, Service
                    Bus, Event Hubs, Cosmos DB, blob, Event Grid...)
                    and bindings
  Runtime           Functions runtime, language and version against
                    its end of support, the .NET in-process model
  Configuration     every setting that matters, by area: general,
                    runtime, security, networking, scale, monitoring,
                    deployment; app settings by name and kind (Key
                    Vault reference, identity-based, key or
                    connection string, plain, platform)
  Networking        inbound (public, restricted, private endpoints,
                    public access off), SCM site rules, VNet
                    integration and route-all, outbound IPs, CORS
  Deployment        deployment center (GitHub Actions, Azure Repos,
                    external Git, zip deploy), recent deployments,
                    slots, run from package, basic publishing
                    credentials
  Backups           taken and their status, where the plan supports
                    them
  Connections       Service Connector connections, and the Key
                    Vaults, storage accounts, Service Bus / Event
                    Hubs and Cosmos DB accounts named in app settings
                    (names only) - with how each authenticates
  Activity Log      every management operation in the last
                    -ActivityDays: restarts, stops, configuration
                    changes, deployments, slot swaps, settings and
                    keys read - who, when, and whether it worked
  Well-Architected  about 30 checks across the five pillars, Pass,
                    Fail or N/A, a score per app and per pillar
  PSRule for Azure  the Azure.AppService.* and related rules on the
                    apps and plans (unless -SkipPSRule)
  Recommendations   Azure Advisor and Defender for Cloud
```

Every failed check and rule, recommendation and notable Activity Log
pattern is a finding with its severity, pillar, source and what to
do.

The HTML report has a tab for each audience - a service summary for
service delivery managers (health, usage, errors, changes, owner),
apps and plans for architects, configuration and networking for
administrators, security findings for IT security - an App selector
that filters every tab, and hover cards with each row's details.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACFunctionAppAssessment -HtmlPath .\Functions.html
```

Every function app you can see, assessed, as an interactive report.

### Example 2

```powershell
Invoke-AACFunctionAppAssessment -Name 'func-orders-*' -TimeRange 30d -HtmlPath .\Orders.html -PdfPath .\Orders.pdf
```

Some apps over a month: usage, cost, changes and findings.

### Example 3

```powershell
Invoke-AACFunctionAppAssessment -View Finding -NoDisplay | Where-Object Pillar -EQ 'Security'
```

The security findings, for IT security.

### Example 4

```powershell
Invoke-AACFunctionAppAssessment -View Activity -ActivityDays 30 -NoDisplay | Where-Object Kind -In 'Configuration change', 'Secrets or keys read'
```

Who changed the apps' configuration, or read their settings, in the last month.

### Example 5

```powershell
Invoke-AACFunctionAppAssessment -View Function -NoDisplay | Where-Object { $_.Trigger -eq 'http' -and $_.AuthLevel -eq 'anonymous' }
```

The anonymous HTTP functions.

## PARAMETERS

### -ActivityDays

How many days of the Activity Log to read (7 if not given; 1 to 90).

```yaml
Type: System.Int32
DefaultValue: 7
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

### -Baseline

The PSRule for Azure baseline (Azure.Default by default).

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

Write the -View rows to this CSV file.

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

Write the tabbed, interactive HTML report.

```yaml
Type: System.String
DefaultValue: None
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

### -ManagementGroupId

Only the apps under these management groups.

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

Only these apps; wildcards work, e.g. 'func-orders-\*'.

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

Return the rows without showing the view.

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

### -PassThru

Show the view and also return the rows.

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

Write a PDF report.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only the apps in these resource groups.

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

### -SkipSettings

Don't list app settings and connection strings.

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

Only the apps in these subscriptions.

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

### -ThrottleLimit

How many requests run at once (1 to 32; 12 by default).

```yaml
Type: System.Int32
DefaultValue: 12
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

### -TimeRange

The period usage and metrics cover: 1h, 4h, 12h, 1d, 3d, 7d (the
default), 14d or 30d.

```yaml
Type: System.String
DefaultValue: "'7d'"
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

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Function App assessment'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -View

What is returned and written to -CsvPath: App (default), Plan,
Function, Setting, AppSetting, Slot, Deployment, Network, Backup,
Connection, Activity, Check, PSRule, Recommendation or Finding.

```yaml
Type: System.String
DefaultValue: "'App'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.FunctionApp, AAC.FunctionAppPlan, AAC.FunctionAppFunction, AAC.FunctionAppSettingView, AAC.FunctionAppAppSetting, AAC.FunctionAppSlot, AAC.FunctionAppDeployment, AAC.FunctionAppNetwork, AAC.FunctionAppBackup, AAC.FunctionAppConnection, AAC.FunctionAppActivity, AAC.FunctionAppCheck, AAC.PSRuleResult, AAC.FunctionAppRecommendation or AAC.FunctionAppFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACFunctionAppAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
