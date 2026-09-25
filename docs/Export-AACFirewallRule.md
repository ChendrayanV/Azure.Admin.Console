# Export-AACFirewallRule

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Exports every Azure Firewall Policy rule - DNAT, network and application - as PowerShell objects, a CSV file and/or a PDF report.

## Syntax

```powershell
Export-AACFirewallRule [[-SubscriptionId] <string[]>] [[-FirewallPolicyName] <string[]>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [<CommonParameters>]
```

## Description

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

Output:
```text
  (no path)   the rules as AAC.FirewallRule objects, e.g. to filter
              with Where-Object or pipe to Export-Csv yourself
  -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
              rule, list values joined with ", ")
  -PdfPath    a landscape A4 PDF: a summary of each policy, then every
              rule grouped by policy, rule collection group and rule
              collection, with source, destination, protocols, ports
              and DNAT translation
```

With -CsvPath or -PdfPath the rule objects are only returned when
-PassThru is also given. Both paths can be used in one run.

Only Firewall Policy rules are exported. Classic rules configured
directly on a firewall (without a policy) are not included. Rules a
policy inherits from its base policy appear under the base policy.

PDF export needs Windows and PowerShell 7.4 or later (see
Export-AACPesterReport); objects and CSV work everywhere.

## Examples

### Example 1

```powershell
Connect-AAC
Export-AACFirewallRule -CsvPath .\out\FirewallRules.csv -PdfPath .\out\FirewallRules.pdf
```

Writes every Firewall Policy rule you can see to a CSV file and a PDF report.

### Example 2

```powershell
Export-AACFirewallRule -SubscriptionId '00000000-0000-0000-0000-000000000000' |
    Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' } |
    Format-Table FirewallPolicy, RuleCollection, RuleName, DestinationPorts
```

Lists allow rules open to any source in one subscription.

### Example 3

```powershell
Export-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' -PdfPath .\HubFirewall.pdf -Title 'Hub firewall rules'
A PDF of the hub firewall policies only.
```

### Example 4

```powershell
Export-AACFirewallRule | Export-Csv -Path .\rules.csv -NoTypeInformation -Delimiter ';'
```

Uses Export-Csv directly, for control over its options.

## Parameters

### -SubscriptionId

Only export policies in these subscriptions. Defaults to every
subscription the signed-in account can see. IP Groups and base
policies are resolved in every subscription either way.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 0 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -FirewallPolicyName

Only export policies whose name matches one of these wildcard
patterns (case-insensitive), e.g. 'fwpol-hub-\*'.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 1 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | Yes |

### -CsvPath

Write the rules to this CSV file. An existing file is overwritten;
missing folders are created.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 2 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PdfPath

Write the rules to this PDF file. An existing file is overwritten;
missing folders are created.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 3 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Title

The PDF's title. Defaults to 'Azure Firewall rules'.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 4 |
| Default value | `'Azure Firewall rules'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PassThru

With -CsvPath or -PdfPath, also return the rule objects.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### CommonParameters

This command supports the common parameters (`-Verbose`, `-ErrorAction`, `-WarningAction` and so on). See [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).

## Outputs

AAC.FirewallRule (without -CsvPath/-PdfPath, or with -PassThru)
