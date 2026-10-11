---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSecurityAlert.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACSecurityAlert
---

# Get-AACSecurityAlert

## SYNOPSIS

Lists Microsoft Defender for Cloud's security alerts across your subscriptions - what was detected, on which resource, its MITRE ATT&CK tactics and techniques, the hosts, accounts and IP addresses involved, and what to do - open and most severe first, with the alerts that keep coming back called out.

## SYNTAX

### __AllParameterSets

```
Get-AACSecurityAlert [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-ResourceId] <string[]>] [[-Name] <string[]>]
 [[-AlertType] <string[]>] [[-Severity] <string[]>] [[-Status] <string[]>] [[-Tactic] <string[]>]
 [[-Days] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-Incident] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

The equivalent of Get-AzSecurityAlert (Az.Security), read for every
subscription in one Azure Resource Graph query rather than one
subscription and location at a time, and with more to filter on and
more in each alert:

```text
  Alert, Severity, Status   what Defender for Cloud detected
  Intent, Techniques        the MITRE ATT&CK tactics (kill-chain
                            stages) and technique IDs
  Resource                  the Azure resource it is about (type,
                            resource group, subscription), else the
                            compromised entity
  Hosts, Accounts,          the entities in the alert, each kind on
  IpAddresses, Entities     its own, ready to pivot on
  TimeGenerated, AgeDays    when, and how long ago
  Remediation               Defender's steps, as plain text
  ExtendedProperties        the alert's own details (a dictionary)
  Occurrences               how many alerts in the list share its
                            type and resource
  Incident                  a Defender incident (correlated alerts)
  AlertUrl                  the alert in the Azure portal
```

By default the open alerts (Active and In progress); -Status picks
others (-Name on its own reads every status, as Get-AzSecurityAlert
-Name does). -Severity, -Status and -Days are applied in Resource
Graph; the rest in PowerShell.

At the prompt: tiles, the alerts by severity, MITRE tactic (in
kill-chain order), day and resource, the alerts, and the recurring
ones - three or more of a type on one resource, to fix at the source
or tune with a suppression rule. Subscriptions with no Defender plan
on are pointed out: they raise no alerts, so an empty list there
proves nothing.

Read-only; Reader (or Security Reader) is enough. Changing an alert's
state is done in Defender for Cloud.

## EXAMPLES

### Example 1

```powershell
Get-AACSecurityAlert
```

The open alerts in every subscription you can see, most severe first.

### Example 2

```powershell
Get-AACSecurityAlert -Severity High -Days 7 -HtmlPath .\out\Alerts.html
```

This week's open High alerts, as an interactive HTML report.

### Example 3

```powershell
Get-AACSecurityAlert -Status Active, InProgress, Resolved, Dismissed -Days 90 -CsvPath .\out\Alerts.csv
```

Every alert of the last 90 days, whatever its state, to CSV.

### Example 4

```powershell
Get-AACSecurityAlert -Tactic CredentialAccess, LateralMovement -NoDisplay | Select-Object Alert, Resource, Accounts, IpAddresses
```

Who and where for the alerts that point to an attacker moving around.

### Example 5

```powershell
Get-AACSecurityAlert -NoDisplay | Where-Object IpAddresses -Match '203\.0\.113\.' | Group-Object Resource
```

Every resource an IP address range shows up against.

### Example 6

```powershell
Get-AACInventory -NoDisplay | Where-Object ResourceGroup -EQ 'rg-prod' | Get-AACSecurityAlert
```

The open alerts on the resources piped in.

### Example 7

```powershell
Get-AACSecurityAlert -Name '2517*' -NoDisplay | Select-Object -ExpandProperty ExtendedProperties
```

One alert by its name, whatever its state, with Defender's details.

## PARAMETERS

### -AlertType

Only alerts of these types (for example VM_SuspiciousLogin, or
'K8S_\*'); wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -CsvPath

Write the alerts to this CSV file.

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

### -Days

Only alerts generated in the last this many days.

```yaml
Type: System.Int32
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

### -HtmlPath

Write an interactive HTML report.

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

### -Incident

Only incidents: Defender's correlations of related alerts.

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

### -Name

Only alerts whose name (Get-AzSecurityAlert's -Name, the alert's
resource name) or display name matches; wildcards work. Without
-Status, every status is read.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -NoDisplay

Return the alerts without showing the view.

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

Show the view and also return the alerts.

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

Only alerts on resources in these resource groups.

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

### -ResourceId

Only alerts on these resources, or on anything under them (a
resource group or subscription ID works too). Takes ResourceId or Id
from the pipeline, so resources from Get-AACInventory, Get-AzResource
or Get-AzVM can be piped in.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- Id
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Severity

Only alerts of these severities (High, Medium, Low, Informational).

```yaml
Type: System.String[]
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

### -Status

Only alerts in these states (Active, InProgress, Resolved,
Dismissed). Default: Active and InProgress.

```yaml
Type: System.String[]
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

### -SubscriptionId

Only these subscriptions.

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

### -Tactic

Only alerts with one of these MITRE ATT&CK tactics (for example
InitialAccess, CredentialAccess, 'Lateral\*'); wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Defender for Cloud security alerts'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.SecurityAlert

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSecurityAlert.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
