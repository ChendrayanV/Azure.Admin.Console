# Diagnostic settings

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACDiagnosticSetting`](../Get-AACDiagnosticSetting.md)

`Get-AACDiagnosticSetting` finds the resources whose logs don't reach Log
Analytics. Read-only, in three steps:

1. **Every resource in scope**, with one KQL query (Azure Resource Graph), and
   the subscriptions for their activity log. A storage account's logs are set
   on its blob, file, queue and table services, which Resource Graph doesn't
   list: they are added.
2. **Which resources have logs**: Azure's own list of a resource's diagnostic
   categories (`diagnosticSettingsCategories`), read once per resource type and
   kind - not per resource.
3. **The diagnostic settings** of every resource that has logs (the
   [Diagnostic Settings - List](https://learn.microsoft.com/rest/api/monitor/diagnostic-settings/list)
   API, 2021-05-01-preview), 12 at a time (`-ThrottleLimit`).

```powershell
Get-AACDiagnosticSetting -SubscriptionId 00000000-0000-0000-0000-000000000000
Get-AACDiagnosticSetting -ManagementGroupId 'mg-landingzones' -ExpectedWorkspace 'law-central' -HtmlPath .\Diagnostics.html -PdfPath .\Diagnostics.pdf
Get-AACDiagnosticSetting -Status 'No setting' -CsvPath .\NoDiagnosticSetting.csv   # support logs, nothing configured
Get-AACDiagnosticSetting -NotExportedOnly -NoDisplay | Group-Object ResourceType | Sort-Object Count -Descending
Get-AACDiagnosticSetting -ResourceType 'microsoft.keyvault/vaults' -ExpandSetting -CsvPath .\KeyVaultSettings.csv
```

Each resource with logs gets a status, and a reason when its logs don't all
arrive:

| Status           | Meaning                                                                                                                                         |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Exported         | Every log category reaches a Log Analytics workspace - by name, or through a category group (`allLogs`, `audit`) it belongs to                  |
| Partial          | Some categories do; the missing ones are listed                                                                                                 |
| Not to workspace | Diagnostic settings exist, but none sends logs to a workspace that exists - storage or Event Hubs only, a deleted workspace, or nothing enabled |
| No setting       | No diagnostic setting at all                                                                                                                    |
| Unknown          | It couldn't be read (the error says why)                                                                                                        |

Misconfigurations, by severity: **High** - no diagnostic setting, activity log
not exported, no workspace destination, a workspace that doesn't exist;
**Medium** - log categories missing, a setting with nothing enabled, the same
category sent to a workspace twice (billed twice), a workspace other than
`-ExpectedWorkspace`; **Low** - a workspace in another region, the retired
retention policy still set.

The view shows coverage by resource type (least covered first), the
workspaces receiving logs, the misconfigurations with the resources they
affect, and every resource whose logs don't reach a workspace.
`-ExpandSetting` returns one row per diagnostic setting, flattened:
destinations, workspace (found, region), destination table (resource-specific
or AzureDiagnostics), storage account, event hub, log categories and groups
enabled and disabled, metrics, retention. A large estate means a call per
resource with logs: narrow it with `-SubscriptionId`, `-ManagementGroupId`,
`-ResourceGroupName` or `-ResourceType`.
