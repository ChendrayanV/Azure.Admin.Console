# Get-AACFirewallRule

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Gets every Azure Firewall Policy rule - DNAT, network and application: a colour-coded Spectre.Console view at the prompt, PowerShell objects down a pipeline, and optional CSV and PDF exports.

## Syntax

```powershell
Get-AACFirewallRule [[-SubscriptionId] <string[]>] [[-FirewallPolicyName] <string[]>] [[-SourceAddress] <string[]>] [[-DestinationAddress] <string[]>] [[-Port] <string[]>] [[-Protocol] <string[]>] [[-Fqdn] <string[]>] [[-Action] <string[]>] [[-RuleName] <string[]>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging] [<CommonParameters>]
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

Exports, in any of those modes:
```text
  -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
              rule, list values joined with ", ")
  -PdfPath    a landscape A4 PDF: a summary of each policy, then every
              rule grouped by policy, rule collection group and rule
              collection, with Allow in green, Deny in red and DNAT
              in amber
```

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

## Examples

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

Shows the view and writes every rule to a CSV file and a PDF report.

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

The hub firewall policies only, on screen and as a PDF.

### Example 5

```powershell
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP
```

Which rules let 10.1.2.3 reach 10.0.0.4 on UDP 53 - allow and deny - in priority order.

### Example 6

```powershell
Get-AACFirewallRule -Action Allow -SourceAddress 0.0.0.0/0 -Port 3389, 22
```

Allow rules for RDP or SSH from any address.

### Example 7

```powershell
Get-AACFirewallRule -Fqdn www.contoso.com -Protocol Https -CsvPath .\contoso.csv
```

Application rules that cover www.contoso.com over HTTPS, also saved as a CSV file.

### Example 8

```powershell
$rules = Get-AACFirewallRule -NoDisplay
```

Keeps the rule objects in a variable, without showing the view.

### Example 9

```powershell
Get-AACFirewallRule | Export-Csv -Path .\rules.csv -NoTypeInformation -Delimiter ';'
```

Uses Export-Csv directly, for control over its options.

## Parameters

### -SubscriptionId

Only get policies in these subscriptions. Defaults to every
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

Only get policies whose name matches one of these wildcard patterns
(case-insensitive), e.g. 'fwpol-hub-\*'.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 1 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | Yes |

### -SourceAddress

Only rules whose source covers or overlaps one of these addresses:
IPs, CIDR prefixes or 'a-b' ranges, IPv4 or IPv6. The rule's IP
Groups count, and a '\*' source matches any address.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 2 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -DestinationAddress

Only rules whose destination covers or overlaps one of these
addresses, as for -SourceAddress.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 3 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Port

Only rules whose destination ports include one of these ports or
overlap one of these ranges ('443', '8000-8080'). For application
rules, the port of each protocol ('Https:443') counts.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 4 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Protocol

Only rules for one of these protocols: TCP, UDP, ICMP (network and
DNAT rules - a rule for 'Any' matches all), or Http, Https, Mssql
(application rules).

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 5 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Fqdn

Only rules for one of these host names - '\*.contoso.com' in a rule
covers 'www.contoso.com' - or whose FQDNs match one of these
wildcard patterns.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 6 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | Yes |

### -Action

Only rules in collections with one of these actions: Allow, Deny,
DNAT.

| | |
|---|---|
| Type | `String[]` |
| Accepted values | `Allow`, `Deny`, `DNAT` |
| Required | No |
| Position | 7 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -RuleName

Only rules whose name matches one of these wildcard patterns.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 8 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | Yes |

### -CsvPath

Also write the rules to this CSV file. An existing file is
overwritten; missing folders are created.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 9 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PdfPath

Also write the rules to this PDF file. An existing file is
overwritten; missing folders are created.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 10 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Title

The PDF's title. Defaults to 'Azure Firewall rules'.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 11 |
| Default value | `'Azure Firewall rules'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PassThru

Show the view and also return the rule objects.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -NoDisplay

Return the rule objects without showing the view.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -NoPaging

Show the whole view at once instead of a screen at a time.

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

AAC.FirewallRule (piped onward, or with -PassThru or -NoDisplay)
