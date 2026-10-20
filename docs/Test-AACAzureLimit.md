---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACAzureLimit.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Test-AACAzureLimit
---

# Test-AACAzureLimit

## SYNOPSIS

Shows which scopes are close to an Azure limit - role assignments, custom roles, policy assignments, definitions, initiatives and exemptions, resource groups, tags, management group depth - before a deployment fails on one.

## SYNTAX

### __AllParameterSets

```
Test-AACAzureLimit [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-Status] <string[]>] [[-WarningPercent] <int>] [[-CriticalPercent] <int>]
 [[-Maximum] <hashtable>] [[-FailOnLimit] <string>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Counts, read-only and in Azure Resource Graph (so only the totals
come back, however large the tenant), what each scope uses of each
limit:

```text
  Tenant             custom roles (5,000), custom initiatives
                     (2,500), management groups (10,000) and their
                     depth (6 levels below the root)
  Management group   role assignments (500), policy assignments
                     (200), custom policy definitions (500),
                     custom initiatives (200), exemptions (1,000)
  Subscription       role assignments at or below it (4,000),
                     policy assignments, definitions, initiatives
                     and exemptions, resource groups (980), tags on
                     the subscription and the most on any resource
                     group or resource (50)
  Resource group     policy assignments and exemptions - listed
                     only when they reach the warning level
```

Each (AAC.AzureLimit) has its use, the maximum, the percentage, what
is left and - when it is close - what to do. Critical at
-CriticalPercent (95%) or more, Warning at -WarningPercent (80%).

The maximums are Microsoft's published limits; if one changes, or
support raised one for you, pass -Maximum with the new number.
Reader on the scope is enough; management groups count when one of
the subscriptions in scope sits under them.

## EXAMPLES

### Example 1

```powershell
Test-AACAzureLimit
```

Every limit in use across the tenant, the closest first.

### Example 2

```powershell
Test-AACAzureLimit -Status Critical, Warning -NoDisplay | Select-Object Limit, Scope, Used, Maximum, Percent
```

Only the limits that need attention, as objects.

### Example 3

```powershell
Test-AACAzureLimit -ManagementGroupId 'mg-landingzones' -FailOnLimit Warning
A pipeline gate: fails if anything under the landing zones is at 80% of a limit.
```

### Example 4

```powershell
Test-AACAzureLimit -Maximum @{ RoleAssignmentsPerSubscription = 6000 } -HtmlPath .\Limits.html
```

With a raised role assignment limit, as a report.

## PARAMETERS

### -CriticalPercent

Critical from this percentage of a limit. Default 95.

```yaml
Type: System.Int32
DefaultValue: 95
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

### -CsvPath

Write the limits to this CSV file.

```yaml
Type: System.String
DefaultValue: None
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

### -FailOnLimit

Stop with an error when any limit is Critical (or, with
-FailOnLimit Warning, at Warning) - a gate for a pipeline.

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

### -HtmlPath

Write an interactive HTML report.

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

### -ManagementGroupId

Only the subscriptions under these management groups (at any depth).

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

### -Maximum

Your own maximums, by limit name - for a limit support raised, or one
Microsoft changed: @{ RoleAssignmentsPerSubscription = 6000 }. The
names: RoleAssignmentsPerSubscription,
RoleAssignmentsPerManagementGroup, CustomRolesPerTenant,
PolicyAssignmentsPerScope, PolicyDefinitionsPerScope,
PolicySetDefinitionsPerScope, PolicySetDefinitionsPerTenant,
PolicyExemptionsPerScope, ResourceGroupsPerSubscription,
TagsPerSubscription, TagsPerResourceGroup, TagsPerResource,
ManagementGroupDepth, ManagementGroupsPerTenant.

```yaml
Type: System.Collections.Hashtable
DefaultValue: '@{}'
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

### -NoDisplay

Return the limits without showing the view.

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

Show the view and also return the limits.

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
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Status

Only these: Critical, Warning, OK.

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

### -SubscriptionId

Only these subscriptions (and the management groups above them).

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure limits'"
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

### -WarningPercent

Warning from this percentage of a limit. Default 80.

```yaml
Type: System.Int32
DefaultValue: 80
SupportsWildcards: false
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.AzureLimit

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACAzureLimit.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
