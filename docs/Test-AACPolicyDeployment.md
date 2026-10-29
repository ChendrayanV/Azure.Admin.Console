---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACPolicyDeployment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Test-AACPolicyDeployment
---

# Test-AACPolicyDeployment

## SYNOPSIS

Tests an ARM template or Bicep file against Azure Policy before it is deployed: what policy would refuse, audit or change, resource by resource, why, and the values it allows - for a pull request or a pipeline gate.

## SYNTAX

### __AllParameterSets

```
Test-AACPolicyDeployment [-TemplatePath] <string> [[-ParameterPath] <string>]
 [[-Parameter] <hashtable>] [-SubscriptionId] <string> [[-ResourceGroupName] <string>]
 [[-Location] <string>] [[-FailOn] <string>] [[-View] <string>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only: nothing is deployed. The template's resources are worked
out offline (parameters, variables and most template functions;
Bicep modules followed - Get-AACTemplateResource) and each body is
sent to Azure Policy's checkPolicyRestrictions for the resource
group (or subscription) it goes to, with audits included:

```text
  Blocked      a deny would refuse it - the field, the expected and
               the found value, and the values allowed
  Audited      it deploys, but is reported non-compliant
  Changed      modify or append would change it as it deploys
  Passes       nothing refuses, audits or changes it
  Not checked  Azure couldn't be asked
```

Policies that act on what exists after the deployment
(deployIfNotExists, auditIfNotExists, denyAction) are listed as
After deployment, so "Passes" isn't read as "fully compliant".

What can't be known before deploying (uniqueString(), reference(),
a parameter with no value) is left out of the body, never guessed,
and named on the resource - a policy that reads it isn't judged.

A .bicep file is compiled with the Bicep CLI (bicep build) when it is
on the PATH. -FailOn Deny (or Audit) ends with an error when a
resource would be refused (or audited), after the report is
written - for a pipeline.

Needs Reader where the resources go. checkPolicyRestrictions honours
the policy and exemptions assigned at the subscription, resource
group and above.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Test-AACPolicyDeployment -TemplatePath .\main.bicep -SubscriptionId $sub -ResourceGroupName 'rg-orders'
```

What Azure Policy would refuse, audit or change in the deployment, resource by resource.

### Example 2

```powershell
Test-AACPolicyDeployment -TemplatePath .\main.json -ParameterPath .\prod.parameters.json -SubscriptionId $sub -ResourceGroupName 'rg-orders' -FailOn Deny -HtmlPath .\policy-gate.html
A pipeline gate: a report for the run, and an error when policy would refuse a resource.
```

### Example 3

```powershell
Test-AACPolicyDeployment -TemplatePath .\main.json -SubscriptionId $sub -ResourceGroupName 'rg-new' -Location 'uksouth' -View Restriction -NoDisplay
```

For a resource group not created yet: the values policy allows for each resource's fields.

## PARAMETERS

### -CsvPath

Write the -View rows to this CSV file.

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

### -FailOn

None (the default), Deny or Audit: end with an error when a resource
would be refused - or, with Audit, refused or audited.

```yaml
Type: System.String
DefaultValue: "'None'"
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
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Location

The resource group's location, for resourceGroup().location - read
from Azure when the group exists.

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

### -Parameter

Parameter values, over those in -ParameterPath and the defaults.

```yaml
Type: System.Collections.Hashtable
DefaultValue: '@{}'
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

### -ParameterPath

An ARM parameters file (.json) for the template.

```yaml
Type: System.String
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
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

The resource group a resource-group template is deployed to. Leave
it out for a subscription template.

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

### -SubscriptionId

The subscription the template is deployed to.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TemplatePath

The ARM template (.json) or Bicep file (.bicep).

```yaml
Type: System.String
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure Policy deployment check'"
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

### -View

Resource, Policy, Restriction or Finding: what is returned and
written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Resource'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.PolicyDeploymentResource, AAC.EffectivePolicy, AAC.EffectivePolicyRestriction or AAC.EffectivePolicyFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACPolicyDeployment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
