# Security posture

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACSecurityPosture`](../Get-AACSecurityPosture.md)

`Get-AACSecurityPosture` reads Microsoft Defender for Cloud and Azure Policy
with Azure Resource Graph (`securityresources`, `policyresources`), every
query at once. Reader or Security Reader is enough.

```powershell
Get-AACSecurityPosture                                                 # every section, every subscription
Get-AACSecurityPosture -Tag @{ Environment = 'Prod' } -HtmlPath .\Security.html
Get-AACSecurityPosture -Section Alerts, Plans                          # just the alerts and the Defender plans
Get-AACSecurityPosture -Section Compliance -Standard '*ISO*' -PdfPath .\ISO.pdf
Get-AACSecurityPosture -NoDisplay | Where-Object { $_.Section -eq 'Recommendation' -and $_.Severity -eq 'High' } | Group-Object Title
```

| Section           | What it shows                                                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Score`           | Each subscription's secure score - Defender's points, added up across subscriptions as Defender does - and the controls with the potential increase of fixing each |
| `Recommendations` | Every unhealthy recommendation on each resource: severity, the secure score control it belongs to, category, description, remediation steps and its portal page    |
| `Alerts`          | Active and in-progress security alerts: severity, intent, resource, age and the alert's page                                                                       |
| `Plans`           | Which Defender plans are on or off in each subscription                                                                                                            |
| `Compliance`      | Each regulatory standard's passed and failed controls; a failed control is traced to the resources failing the recommendations behind it                           |
| `Policy`          | Azure Policy compliance per assignment (display names, even for management group assignments), and every non-compliant resource with the policy and its effect     |

**One list of findings** (`AAC.SecurityFinding`), the same in the objects,
CSV, HTML and PDF: Section, Severity, Title, Category, Control, the
resource, State, Detail, the portal link and since when - most severe first.
`-ResourceGroupName` and `-Tag` narrow the findings to those resources (tag
values match exactly, not as substrings); scores, plans and standards are
per subscription. It tells you when Defender plans are off, because then an
empty alert list doesn't mean nothing happened.

For every policy state in detail - compliant ones too - use
`Get-AACPolicyState`; both commands read the same query.

`Get-AACInventory` and `Get-AACSecurityPosture` share their Defender queries
and objects: the inventory puts each node's score and findings in the tree,
and this command is the posture itself.
