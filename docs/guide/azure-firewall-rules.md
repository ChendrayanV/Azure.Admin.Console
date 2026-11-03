# Azure Firewall rules

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACFirewallRule`](../Get-AACFirewallRule.md)

`Get-AACFirewallRule` reads every Firewall Policy rule from Azure Resource
Graph. It returns output the same way as `Get-AACAdvisorRecommendation`:

- **At the prompt:** a console view.
- **Piped onward:** the objects, with no view.
- **`-PassThru`:** both. **`-NoDisplay`:** the objects only.
- **`-CsvPath`, `-PdfPath` and `-HtmlPath`:** the report is in the files,
  and the console shows only the progress.

The HTML report groups the rules by rule collection and flags Allow rules open
to any source or destination (`*`, `0.0.0.0/0`). Click the tile to list just
those rules.

```powershell
Get-AACFirewallRule                                          # the console view
Get-AACFirewallRule -CsvPath .\rules.csv -PdfPath .\rules.pdf -HtmlPath .\rules.html
Get-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' |
    Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' }
```

The view follows the policy hierarchy:

1. **Tiles** for the rules, allow, deny and DNAT counts, policies and rule collections.
2. **A policies table** with each policy's base policy, attached firewalls and rule counts.
3. **One section per policy**, with one table per rule collection in priority order:

```text
╭──── rcg-platform · 100 › Allow-Web · 200 · Filter · 2 rules   ALLOW ────╮   (green border)
│ Rule          │ Source             │ Destination        │ Protocols · ports │ Translation · TLS  │
│ web-out       │ 10.0.0.0/16        │ fqdn *.contoso.com │ Https:443         │ TLS inspection off │
│ application   │ ipg-spokes (IP     │                    │                   │                    │
│ rule          │ group)             │                    │                   │                    │
│               │ 10.1.0.0/16, …     │                    │                   │                    │
╰───────────────────────────────────────────────────────────────────────────────────────────────╯
╭──── rcg-platform · 100 › Block-Legacy · 300 · Filter · 1 rule   DENY ────╮   (red border)
```

In each table:

- The border and badge carry the collection's action: **Allow** in green, **Deny** in red, **DNAT** in orange.
- IP Groups show their addresses underneath.
- A `*` source or destination on an Allow rule is highlighted in yellow as `* (any)`.
- The last column shows the DNAT translation, or whether TLS inspection is on for application rules.
- Long output is paged; `-NoPaging` turns paging off.

## Searching rules

Search parameters narrow the rules. You can combine them, and each takes several values:

- **All given filters must match.** A rule appears only if it satisfies every search parameter you pass.
- **Any value of one filter will do.** `-Port 22, 3389` matches a rule for either port.

Addresses and ports match by containment, so a search answers "which rules
let this source reach that destination?":

| Parameter                               | Matches                                                                                                                                                |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-SourceAddress`, `-DestinationAddress` | An IP, CIDR or `a-b` range (IPv4 or IPv6). It matches rules that cover or overlap it, including through IP Groups, and a `*` rule matches any address. |
| `-Port`                                 | A port or range (`443`, `8000-8080`), overlapping the rule's ports. For application rules, each protocol's port counts.                                |
| `-Protocol`                             | `TCP`, `UDP` or `ICMP`, where a rule for `Any` matches all; or `Http`, `Https` or `Mssql` for application rules.                                       |
| `-Fqdn`                                 | A host name covered by the rule's FQDNs (`*.contoso.com` covers `www.contoso.com`), or a wildcard pattern.                                             |
| `-Action`, `-RuleName`                  | `Allow`, `Deny` or `DNAT`; a rule-name wildcard.                                                                                                       |

```powershell
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP
Get-AACFirewallRule -Action Allow -SourceAddress 0.0.0.0/0 -Port 3389, 22     # RDP/SSH open to any source
Get-AACFirewallRule -Fqdn www.contoso.com -Protocol Https -CsvPath .\contoso.csv
```

The results come back in priority order, allow and deny alike, so the first
match is the one Azure Firewall applies. Service tags (such as `AzureCloud`)
aren't expanded, so an address search doesn't match them.

The rules are listed in the order the Azure portal shows them. The CSV has one
row per rule, with the base policy and attached firewalls on every row. The
PDF groups rules by policy, rule collection group and collection, with the
same colours.
