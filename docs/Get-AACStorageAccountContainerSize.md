---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACStorageAccountContainerSize.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACStorageAccountContainerSize
---

# Get-AACStorageAccountContainerSize

## SYNOPSIS

How much is stored in every blob container of your storage accounts - blobs, bytes, access tiers and the largest blobs - with a Spectre.Console view, objects, and CSV and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACStorageAccountContainerSize [[-SubscriptionId] <string[]>] [[-ResourceGroupName] <string[]>]
 [[-StorageAccountName] <string[]>] [[-ContainerName] <string[]>] [[-AuthMode] <string>]
 [[-Top] <int>] [[-ThrottleLimit] <int>] [[-CsvPath] <string>] [[-BlobCsvPath] <string>]
 [[-HtmlPath] <string>] [[-Title] <string>] [-IncludeSnapshot] [-IncludeVersion] [-IncludeDeleted]
 [-IncludeBlob] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Finds the storage accounts with Azure Resource Graph, lists their
containers through Azure Resource Manager (Reader is enough), then
lists every blob of every container from the blob service itself and
adds them up. Without parameters it reads every storage account the
account can see.

Fast on large estates: the containers are read side by side - 16 at
a time by default (-ThrottleLimit), over pooled HTTPS connections -
each a page of 5,000 blobs at a time. Each page is read by a parser
compiled on first use (about 275,000 blobs a second), added up and
dropped as it arrives, so memory stays flat however many blobs there
are (unless -IncludeBlob or -BlobCsvPath keep every one). Throttling
is retried as Azure Storage asks.

Reading blobs needs data access, which Reader alone doesn't give.
-AuthMode picks how:

```text
  EntraId     (default) your Connect-AAC sign-in, with a token for
              Azure Storage - you need the Storage Blob Data Reader
              role (or Contributor or Owner of the data) on the
              account, its resource group or subscription
  AccountSas  a read-and-list account SAS for the blob service, valid
              for 4 hours, from Azure Resource Manager's
              listAccountSas - you need permission to list the
              account's keys (Contributor, Storage Account
              Contributor); not for accounts that don't allow shared
              key access. The SAS is kept in memory only, never shown
              or written.
  Auto        Entra ID first; the accounts that refuse it for want of
              a data role are then read with an account SAS
```

Accounts behind a firewall or private endpoint can only be read from
a network they allow; they are reported as such.

One row per container (AAC.StorageContainerSize): StorageAccount,
Container, Status (OK, Partial, Failed), BlobCount, Size (bytes, of
the current blobs) and SizeText, SizeHot, SizeCool, SizeCold,
SizeArchive and SizeNoTier (page, append and premium blobs),
Snapshots, Versions and DeletedBlobs with their sizes (when listed),
TotalSize (all of it), Directories (Data Lake Storage), LastModified
(the newest blob), PublicAccess, AuthMode, Error (with what to do),
ResourceGroup, SubscriptionName, Location, Kind, Sku, Url,
LargestBlobs (the -Top largest) and, with -IncludeBlob, Blobs (every
blob) - as AzureAdminConsole.StorageBlob objects: Name, Size,
SizeText, AccessTier, BlobType, Kind, LastModified. An account whose
containers couldn't be listed is one row with no Container and its
reason.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the size by access tier, the largest
                   containers as a chart, every account with its
                   containers as a tree (a size bar each), the
                   largest blobs and what couldn't be read - a page
                   at a time
  piped onward     the container rows, with no view
  -PassThru        the view and the rows
  -NoDisplay       the rows only
```

-CsvPath writes the container rows, -BlobCsvPath every blob listed.
-HtmlPath writes an interactive report: tiles, charts, and tables of
the accounts, containers and largest blobs - searchable, filterable
and downloadable as CSV. With any of them, the console shows only the
progress and the files written.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACStorageAccountContainerSize
```

Every container of every storage account you can see, with its size.

### Example 2

```powershell
Get-AACStorageAccountContainerSize -StorageAccountName 'stlogs*' -ContainerName 'insights-*' -AuthMode Auto
```

The insights containers of the 'stlogs' accounts, read with Entra ID or, where that is refused, an account SAS.

### Example 3

```powershell
Get-AACStorageAccountContainerSize -NoDisplay | Sort-Object Size -Descending | Select-Object -First 10 StorageAccount, Container, BlobCount, SizeText
```

The ten largest containers.

### Example 4

```powershell
Get-AACStorageAccountContainerSize -StorageAccountName 'stbackup01' -BlobCsvPath .\out\Blobs.csv -HtmlPath .\out\Storage.html
```

Every blob of one account to CSV, and an interactive HTML report.

### Example 5

```powershell
(Get-AACStorageAccountContainerSize -NoDisplay -Top 5).LargestBlobs | Sort-Object Size -Descending | Select-Object -First 20
```

The 20 largest blobs across every account.

## PARAMETERS

### -AuthMode

How blobs are read: EntraId (the default, needs a data role such as
Storage Blob Data Reader), AccountSas (a short-lived read-only
account SAS, needs permission to list keys) or Auto (Entra ID, then
an account SAS where Entra ID is refused).

```yaml
Type: System.String
DefaultValue: "'EntraId'"
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

### -BlobCsvPath

Write every blob listed to this CSV file (implies keeping them, as
-IncludeBlob does).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
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

### -ContainerName

Only these containers; wildcards work, e.g. 'backup-\*'.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -CsvPath

Write the container rows to this CSV file.

```yaml
Type: System.String
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

### -HtmlPath

Write an interactive HTML report to this file.

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

### -IncludeBlob

Keep every blob listed, on each row's Blobs property. Takes memory
in proportion to the number of blobs (a few hundred bytes each).

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

### -IncludeDeleted

List soft-deleted blobs too.

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

### -IncludeSnapshot

List blob snapshots too; they are counted and sized on their own.

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

### -IncludeVersion

List previous blob versions too (accounts with versioning).

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

### -NoDisplay

Return the rows without showing the view.

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

Show the whole view at once instead of a page at a time.

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

Show the view and also return the rows.

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

### -ResourceGroupName

Only storage accounts in these resource groups.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
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

### -StorageAccountName

Only these storage accounts; wildcards work, e.g. 'stlogs\*'.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

Only these subscriptions.

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

### -ThrottleLimit

How many containers to read at once (16; 1 to 64).

```yaml
Type: System.Int32
DefaultValue: 16
SupportsWildcards: false
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

### -Title

The HTML report's title.

```yaml
Type: System.String
DefaultValue: "'Storage account container sizes'"
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

### -Top

How many of the largest blobs to keep per container (10; 0 for none).

```yaml
Type: System.Int32
DefaultValue: 10
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.StorageContainerSize (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACStorageAccountContainerSize.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
