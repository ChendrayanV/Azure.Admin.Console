---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACFirewallRule.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACFirewallRule
---

# Get-AACFirewallRule

## SYNOPSIS

Gets every Azure Firewall Policy rule - DNAT, network and application: a colour-coded Spectre.Console view at the prompt, PowerShell objects down a pipeline, and optional CSV, PDF and interactive HTML exports.

## SYNTAX

### __AllParameterSets

```
Get-AACFirewallRule [[-SubscriptionId] <string[]>] [[-FirewallPolicyName] <string[]>]
 [[-SourceAddress] <string[]>] [[-DestinationAddress] <string[]>] [[-Port] <string[]>]
 [[-Protocol] <string[]>] [[-Fqdn] <string[]>] [[-Action] <string[]>] [[-RuleName] <string[]>]
 [[-CsvPath] <string>] [[-PdfPath] <string>] [[-HtmlPath] <string>] [[-Title] <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the rules of every Azure Firewall Policy the signed-in account
can see (or only those in -SubscriptionId / -FirewallPolicyName) from
Azure Resource Graph, over REST with the Connect-AAC sign-in - no Az
modules needed. One object is returned per rule, sorted as the Azure
portal lists them: by policy, rule collection group priority, rule
collection priority, then the rule's position in its collection.
(Azure Firewall itself applies all DNAT rules first, then network,
then application rules, each in that priority order, and a base
policy's rules before the policy's own.)

IP Groups used as a source or destination are resolved to their names
and addresses, wherever in the tenant they live (one Resource Graph
query, no per-group calls). Each rule also carries its policy's base
(parent) policy and the firewalls the policy is attached to.

What you get depends on where the command runs:

```text
  at the prompt    a Spectre.Console view: the account and scope,
                   tiles with the number of rules, allow, deny and
                   DNAT rules, policies and collections, a table of
                   the policies, then one table per rule collection
                   in priority order - Allow collections bordered in
                   green, Deny in red, DNAT in orange - shown a
                   screen at a time
  piped onward     the AAC.FirewallRule objects, with no view
  -PassThru        the view and the objects
  -NoDisplay       the objects only (scripts, scheduled tasks)
```

PowerShell can't tell "$r = Get-AACFirewallRule" from a plain call,
so to keep the objects in a variable add -PassThru or -NoDisplay.

In the view, IP Groups are shown by name with their addresses under
them, and an Allow rule open to any source or destination has its
'\*' called out in yellow. When the view is longer than the terminal
it is paged: press any key for the next page, or A for the rest.

Exports:

```text
  -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
              rule, list values joined with ", ")
  -PdfPath    a landscape A4 PDF: a summary of each policy, then every
              rule grouped by policy, rule collection group and rule
              collection, with Allow in green, Deny in red and DNAT
              in amber
  -HtmlPath   a self-contained, interactive HTML report: clickable
              tiles and charts (by action, policy, rule collection,
              rule type) that filter a table of every rule, grouped
              by rule collection, with search, filters, sorting,
              Allow rules open to any address flagged, Azure portal
              links and a CSV download of what is shown
```

When any of -CsvPath, -PdfPath or -HtmlPath is given, the console
shows only the progress and the files written - the report is in
the files. Add -PassThru to get the objects as well.

Search: -SourceAddress, -DestinationAddress, -Port, -Protocol,
-Fqdn, -Action and -RuleName narrow the rules to those that match -
every filter given must match, and any one of a filter's values.
Addresses and ports match by containment, so the search answers
"which rules let this source reach that destination on this port?":
10.1.2.3 matches a rule for 10.1.0.0/16, for an IP Group holding it,
or for '\*'; a CIDR or 'a-b' range matches rules that overlap it; port
443 matches '443', '400-500' and '\*'. Service tags (e.g. AzureCloud)
aren't expanded, so they only match a search for them by -RuleName.

Only Firewall Policy rules are read. Classic rules configured
directly on a firewall (without a policy) are not included. Rules a
policy inherits from its base policy appear under the base policy.

PDF export needs Windows and PowerShell 7.4 or later; objects and
CSV work everywhere.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACFirewallRule
```

Shows every Firewall Policy rule you can see, policy by policy.

### Example 2

```powershell
Get-AACFirewallRule -CsvPath .\out\FirewallRules.csv -PdfPath .\out\FirewallRules.pdf
```

Writes every rule to a CSV file and a PDF report; the console shows the progress and the files.

### Example 3

```powershell
Get-AACFirewallRule -SubscriptionId '00000000-0000-0000-0000-000000000000' |
    Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' } |
    Format-Table FirewallPolicy, RuleCollection, RuleName, DestinationPorts
```

Lists allow rules open to any source in one subscription.

### Example 4

```powershell
Get-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' -PdfPath .\HubFirewall.pdf -Title 'Hub firewall rules'
```

The hub firewall policies only, as a PDF.

### Example 5

```powershell
Get-AACFirewallRule -HtmlPath .\out\FirewallRules.html
```

Every rule in an interactive HTML report to search, filter and share.

### Example 6

```powershell
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP
```

Which rules let 10.1.2.3 reach 10.0.0.4 on UDP 53 - allow and deny - in priority order.

### Example 7

```powershell
Get-AACFirewallRule -Action Allow -SourceAddress 0.0.0.0/0 -Port 3389, 22
```

Allow rules for RDP or SSH from any address.

### Example 8

```powershell
Get-AACFirewallRule -Fqdn www.contoso.com -Protocol Https -CsvPath .\contoso.csv
```

Application rules that cover www.contoso.com over HTTPS, also saved as a CSV file.

### Example 9

```powershell
$rules = Get-AACFirewallRule -NoDisplay
```

Keeps the rule objects in a variable, without showing the view.

### Example 10

```powershell
Get-AACFirewallRule | Export-Csv -Path .\rules.csv -NoTypeInformation -Delimiter ';'
```

Uses Export-Csv directly, for control over its options.

## PARAMETERS

### -Action

Only rules in collections with one of these actions: Allow, Deny,
DNAT.

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

### -CsvPath

Also write the rules to this CSV file. An existing file is
overwritten; missing folders are created.

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

### -DestinationAddress

Only rules whose destination covers or overlaps one of these
addresses, as for -SourceAddress.

```yaml
Type: System.String[]
DefaultValue: None
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

### -FirewallPolicyName

Only get policies whose name matches one of these wildcard patterns
(case-insensitive), e.g. 'fwpol-hub-\*'.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -Fqdn

Only rules for one of these host names - '\*.contoso.com' in a rule
covers 'www.contoso.com' - or whose FQDNs match one of these
wildcard patterns.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

Also write an interactive HTML report to this file. An existing file
is overwritten; missing folders are created.

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

### -NoDisplay

Return the rule objects without showing the view.

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

Show the whole view at once instead of a screen at a time.

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

Show the view and also return the rule objects.

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

Also write the rules to this PDF file. An existing file is
overwritten; missing folders are created.

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

### -Port

Only rules whose destination ports include one of these ports or
overlap one of these ranges ('443', '8000-8080'). For application
rules, the port of each protocol ('Https:443') counts.

```yaml
Type: System.String[]
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

### -Protocol

Only rules for one of these protocols: TCP, UDP, ICMP (network and
DNAT rules - a rule for 'Any' matches all), or Http, Https, Mssql
(application rules).

```yaml
Type: System.String[]
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

### -RuleName

Only rules whose name matches one of these wildcard patterns.

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

### -SourceAddress

Only rules whose source covers or overlaps one of these addresses:
IPs, CIDR prefixes or 'a-b' ranges, IPv4 or IPv6. The rule's IP
Groups count, and a '\*' source matches any address.

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

Only get policies in these subscriptions. Defaults to every
subscription the signed-in account can see. IP Groups and base
policies are resolved in every subscription either way.

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

The PDF and HTML report's title. Defaults to 'Azure Firewall rules'.

```yaml
Type: System.String
DefaultValue: "'Azure Firewall rules'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.FirewallRule (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACFirewallRule.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
