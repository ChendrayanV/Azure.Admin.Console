# Resource export

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Export-AACResource`](../Export-AACResource.md)

`Export-AACResource` is the resource list you hand to someone else - a
spreadsheet for the owners, a PDF for an audit, an HTML report to filter in
the browser. One Azure Resource Graph query joins `resources` to
`resourcecontainers`, so every row has its subscription and management group
by name, not just an ID.

```powershell
Export-AACResource -CsvPath .\Resources.csv                                     # everything you can see
Export-AACResource -ManagementGroupId mg-landingzones -HtmlPath .\LZ.html -PdfPath .\LZ.pdf
Export-AACResource -SubscriptionId $sub -ResourceGroupName 'rg-app-*' -CsvPath .\App.csv
Export-AACResource -ResourceType 'microsoft.compute/virtualmachines' -NoDisplay | Select-Object Name, Location, Details
Export-AACResource -MissingTag CostCenter, Owner -CsvPath .\Untagged.csv        # tag governance
Export-AACResource -Tag @{ Environment = 'prod' } -Search sql
Export-AACResource -Filter "tostring(properties.provisioningState) != 'Succeeded'"
Export-AACResource -ResourceType 'microsoft.storage/storageaccounts' -Flatten -CsvPath .\Storage.csv
```

| Column | What it holds |
| --- | --- |
| `Name`, `ResourceType`, `Kind`, `Parent` | What it is; `Parent` names the server of a database, the vault of a secret |
| `ResourceGroup`, `Subscription`, `SubscriptionState` | Where it is, by name |
| `ManagementGroup`, `ManagementGroupPath` | The subscription's management group, and the path from the root (`Tenant Root Group > Contoso > Landing zones`) |
| `Location`, `Zones`, `Sku`, `Capacity` | Where it runs and how big it is |
| `Identity`, `ProvisioningState`, `PublicNetworkAccess`, `ManagedBy`, `Created` | How it is set up (`Created` when the type records it) |
| `Details` | The settings people look up, for about 25 types: a VM's size, OS, image and power state; a disk's size and state; a storage account's TLS, public access, shared key and network rules; a NIC's IP, VM and NSG; an App Service's plan, runtime and host; a SQL database's status and size; an AKS cluster's version and nodes; a key vault's soft delete, purge protection and RBAC... |
| `Tags`, `Tag: <key>` | All the tags on one line, and one column per tag key (`-TagColumn` picks them); keys that differ only in case are one tag |
| `ResourceGroupTags` | The resource group's tags, to see what a resource could inherit |
| `properties.*` | With `-Flatten`: every property, flattened (`properties.networkAcls.defaultAction`); lists of objects keep their first three items and a count |

Filters run in Resource Graph when they can, so only what you asked for
comes back: `-ResourceType`, `-ResourceGroupName` and `-Name` (exact; with
wildcards they run afterwards), `-Location`, `-Tag` (a value, or `'*'` for any)
and `-MissingTag`, and `-Filter` for a KQL condition of your own. `-Search`
then finds text anywhere in the name, type, group, subscription, location,
details, tags or ID. The subscriptions are read by up to four queries side by
side, each paged to the end.
