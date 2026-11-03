# Network security groups

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACNetworkSecurityGroup`](../Get-AACNetworkSecurityGroup.md)

`Get-AACNetworkSecurityGroup` assesses network security groups the way an
auditor would. Without parameters it covers every NSG you can see.

```powershell
Get-AACNetworkSecurityGroup                                                  # every NSG
Get-AACNetworkSecurityGroup -SubscriptionId $sub -ResourceGroupName 'rg-network' -Name 'nsg-web', 'nsg-app'
Get-AACNetworkSecurityGroup -HtmlPath .\NSG.html -PdfPath .\NSG.pdf -CsvPath .\NSG-rules.csv
(Get-AACNetworkSecurityGroup -NoDisplay).Findings | Where-Object Severity -EQ 'High'
```

**What each NSG records**

| Area         | What's captured                                                                                                                                                                                                                        |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Metadata     | Name, resource ID, subscription, resource group, location, tags                                                                                                                                                                        |
| Associations | The subnets (VNet, prefix) and network interfaces (VM, private IP) it's applied to, and how many VMs it protects through either - charted as "VMs protected per NSG" to show how standard the perimeter is                             |
| Rules        | Every rule, custom and default, in the order Azure evaluates them: priority, direction, protocol, source, source port, destination, destination port and action. Application security groups are shown by name.                        |
| Telemetry    | Diagnostic settings (Log Analytics workspace, storage account, event hub; log categories), and flow logs with retention and Traffic Analytics. Either an NSG flow log or a virtual network flow log on its VNet, subnet or NIC counts. |

**Findings**, each with what to do:

| Severity | Finding                                                                                                                                                                                                                                         |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | An inbound Allow from `*`, `Internet` or `0.0.0.0/0` to every port, or to a management or database port (SSH, RDP, WinRM, SMB, SQL, Redis, …)                                                                                                   |
| Medium   | A wide port range open to the internet. An NSG on no subnet and no NIC. **A NIC NSG and its subnet's NSG that disagree:** Azure evaluates both, so if one allows what the other denies, the traffic is blocked. No flow log, or a disabled one. |
| Low      | ICMP from the internet. Everything allowed from the virtual network. **A shadowed rule:** an earlier rule covers it, so it never applies. Flow logs kept under 90 days. No diagnostic settings.                                                 |
| Info     | Flow logs without Traffic Analytics. Only an NSG flow log (NSG flow logs retire on 30 September 2027). Over 800 of the 1,000 rules an NSG can hold.                                                                                             |

**Output**

- **At the prompt:** tiles, the NSGs ordered by risk, the High and Medium
  findings, and, for up to three NSGs, each one in detail with its rules.
- **Objects:** `AAC.NetworkSecurityGroup`, carrying their rules, findings,
  associations and logging.
- **`-CsvPath`:** every rule, with its risk and finding.
- **`-HtmlPath`:** tables of NSGs, findings, rules, associations and logging,
  each with a CSV download.
- **`-PdfPath`:** a summary, the findings, and a page per NSG with its rules.
- **`-NoDiagnosticSetting`:** skips the diagnostic-settings calls (one per
  NSG).
