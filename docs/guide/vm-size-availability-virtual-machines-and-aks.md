# VM size availability (virtual machines and AKS)

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACSkuAvailability`](../Get-AACSkuAvailability.md)

`Get-AACSkuAvailability` answers "can I use this VM size here?" before you
deploy: for virtual machines, or for AKS node pools. It only reads - Reader
is enough, and nothing is created - over REST:

| Read                                                                                                                                     | From                                          |
| ---------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| The sizes offered in the region, their zones and capabilities, and what's restricted for your subscription (the region, or single zones) | `Microsoft.Compute/skus`                      |
| Each family's and the region's vCPU quota                                                                                                | `Microsoft.Compute/locations/{region}/usages` |
| Which physical zone each logical zone is (it differs between subscriptions)                                                              | the subscription's locations                  |
| An AKS cluster's region and node pools (`-ClusterName`)                                                                                  | Azure Resource Graph                          |

```powershell
Get-AACSkuAvailability -Location uksouth -Zone 1, 2, 3 -Series D, E               # D and E series usable in all three zones
Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -NodeCount 3      # a new 3-node, 3-zone pool on a cluster
Get-AACSkuAvailability -Service Aks -Location uksouth, ukwest -Architecture Arm64 -HtmlPath .\Skus.html
Get-AACSkuAvailability -Location westeurope -Zone 1, 2, 3 -NoDisplay |
    Where-Object { $_.Status -eq 'Available' -and $_.vCPUs -eq 4 -and $_.MemoryGB -ge 16 }
```

Each size gets a **status**, the first that applies, with the reason:

| Status            | Why                                                                              |
| ----------------- | -------------------------------------------------------------------------------- |
| `Restricted`      | Not offered to your subscription in the region (`NotAvailableForSubscription`)   |
| `NotSupported`    | `-Service Aks` (or `-ClusterName`): fewer than 2 vCPUs, which AKS can't use      |
| `ZoneUnavailable` | None of the `-Zone` zones can host it (not offered there, or restricted for you) |
| `Partial`         | Some of the `-Zone` zones can't                                                  |
| `NoQuota`         | The family's or the region's free vCPUs are fewer than vCPUs x `-NodeCount`      |
| `Available`       | Nothing stops it                                                                 |

For AKS it also notes sizes with less than 4 GB (user node pools only) and
burstable B-series sizes (not recommended for system node pools). With
`-ClusterName` the region and subscription are the cluster's, the sizes its
node pools use are marked, and each pool is shown with its size's status now
and the family's free vCPUs - whether it can scale out.

Narrow the sizes with `-Series` (the letters of the name: `D`, `E`, `NC`,
`DC`; wildcards allowed), `-Sku` (`Standard_D4s_v5`, `D4s_v5` or `*s_v5`) and
`-Architecture x64|Arm64`. Each row (`AAC.SkuAvailability`) has the size's
vCPUs, memory, zones (and the ones missing), family and regional free vCPUs,
architecture, ephemeral OS disk, accelerated networking, premium storage,
Spot, GPUs, data disks and Hyper-V generations.

The console shows tiles, the zone mapping, the vCPU quota (most used first),
the cluster's node pools and each size, usable first. The HTML report has a
donut of the statuses and charts that filter tables of sizes, quota, zones and
node pools; the PDF has the same. `-CsvPath` writes every size.

What no read can tell you is whether there's capacity at the moment you
deploy (`ZonalAllocationFailed` and similar); nothing here deploys to find
out. More services (disks, storage, SQL, PostgreSQL and MySQL flexible
server, App Service) will follow the same pattern.
