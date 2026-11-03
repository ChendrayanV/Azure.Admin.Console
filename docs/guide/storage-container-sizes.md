# Storage container sizes

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACStorageAccountContainerSize`](../Get-AACStorageAccountContainerSize.md)

`Get-AACStorageAccountContainerSize` adds up every blob in every container
of your storage accounts. It finds the accounts with Azure Resource Graph,
lists their containers through Azure Resource Manager (Reader is enough),
then lists the blobs from the blob service itself:

```powershell
Get-AACStorageAccountContainerSize                                                  # every account you can see
Get-AACStorageAccountContainerSize -StorageAccountName 'stlogs*' -ContainerName 'insights-*'
Get-AACStorageAccountContainerSize -AuthMode Auto -IncludeSnapshot -IncludeVersion -HtmlPath .\Storage.html
Get-AACStorageAccountContainerSize -StorageAccountName 'stbackup01' -BlobCsvPath .\Blobs.csv  # every blob, to CSV
Get-AACStorageAccountContainerSize -NoDisplay | Sort-Object Size -Descending | Select-Object -First 10
```

**Built for large estates.** The containers are read side by side, 16 at a
time by default (`-ThrottleLimit`, up to 64), over the module's pooled HTTPS
connections; each container's pages of 5,000 blobs follow each other. Each
page is read by a small parser compiled on first use (C#, through Add-Type:
about 275,000 blobs a second, no XML document) and added up as it arrives,
so memory stays flat however many blobs there are - unless `-IncludeBlob`
or `-BlobCsvPath` keep every one (a few hundred bytes a blob). Throttling is
retried as Azure Storage asks. The view ends with how many blobs were read a
second.

**Reading blobs needs data access**, which Reader alone doesn't give:

| `-AuthMode`         | Reads with                                                                                                                          | You need                                                                                                                       |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `EntraId` (default) | your `Connect-AAC` sign-in, with a token for Azure Storage                                                                          | Storage Blob Data Reader (or Contributor or Owner) on the account, resource group or subscription                              |
| `AccountSas`        | a read-and-list account SAS for the blob service, valid for 4 hours, from `listAccountSas` - kept in memory, never shown or written | permission to list the account's keys (Contributor, Storage Account Contributor), and shared key access allowed on the account |
| `Auto`              | Entra ID, then an account SAS for the accounts that refuse Entra ID for want of a data role                                         | either                                                                                                                         |

Accounts behind a firewall or private endpoint can be read only from a
network they allow. Whatever can't be read is listed with Azure Storage's
reason and what to do about it.

One row per container (`AAC.StorageContainerSize`): blobs, size and size per
tier (Hot, Cool, Cold, Archive, and no tier for page, append and premium
blobs), snapshots, previous versions and soft-deleted blobs with their
sizes (`-IncludeSnapshot`, `-IncludeVersion`, `-IncludeDeleted`), Data Lake
directories, the newest change, public access, status and error, and the
`-Top` largest blobs (10). The console view: tiles, the size by access tier,
the largest containers, every subscription, account and container as a tree
with a size bar coloured by its main tier, the largest blobs, and what
couldn't be read. `-HtmlPath` writes tables of the accounts, containers and
largest blobs with charts that filter them; `-CsvPath` the containers,
`-BlobCsvPath` every blob.
