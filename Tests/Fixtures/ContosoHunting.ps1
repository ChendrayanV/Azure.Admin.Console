<#
    Made-up hunting query files, in the shape of the Azure-Sentinel repository,
    and a made-up workspace, for the Sentinel hunting query tests. Built so
    every path has something to find: a stub moved into a solution, a query in
    two packs, a query for no pack, a stub pointing outside the repository, a
    table with no data and a missing watchlist.

    Returns @{ WorkspaceId; ResourceId; Workspace; Files (repository path ->
    text); Listing (folder -> file names); Tables; Watchlists; Id (name -> the
    query's ID) }.
#>
$sub = '11111111-1111-1111-1111-111111111111'
$ws = "/subscriptions/$sub/resourceGroups/rg-contoso-sec/providers/Microsoft.OperationalInsights/workspaces/law-contoso-sentinel"
$id = @{
    BruteForce = 'aaaaaaaa-0000-4000-8000-000000000001'; Disabled = 'aaaaaaaa-0000-4000-8000-000000000002'; Mail = 'aaaaaaaa-0000-4000-8000-000000000003'
    Cloud = 'aaaaaaaa-0000-4000-8000-000000000004'; Consent = 'aaaaaaaa-0000-4000-8000-000000000005'; Both = 'aaaaaaaa-0000-4000-8000-000000000006'; Aws = 'aaaaaaaa-0000-4000-8000-000000000007'
}
$stub = {
    param([string] $Id, [string] $Name, [string] $Url)
    "id: $Id`nname: $Name`ndescription: |`n  'As part of content migration, this file is moved to new location. you can find here: $Url'`n"
}
$files = @{
    'Hunting Queries/SigninLogs/BruteForce.yaml'                            = @"
id: $($id.BruteForce.ToUpperInvariant())
name: Brute force on sign-ins
description: |
  'Many failed sign-ins
  followed by a success.'
description-detailed: |
  Not read.
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - SigninLogs
tactics:
  - CredentialAccess
  - InitialAccess
relevantTechniques:
  - T1110
query: |
  let starttime = todatetime('{{StartTimeISO}}');

  SigninLogs
    | where ResultType != 0
entityMappings:
  - entityType: Account
    fieldMappings:
      - identifier: FullName
        columnName: UserPrincipalName
version: 1.2.0
"@
    'Hunting Queries/SigninLogs/Disabled.yaml'                              = (& $stub 'bbbbbbbb-0000-4000-8000-000000000002' 'Disabled sign-ins (stub)' 'https://github.com/Azure/Azure-Sentinel/blob/master/Solutions/Cloud%20Identity/Hunting%20Queries/Disabled.yaml')
    'Solutions/Cloud Identity/Hunting Queries/Disabled.yaml'                = @"
id: $($id.Disabled)
name: Sign-ins to disabled accounts
description: 'Attempts to sign in to disabled accounts.'
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes: [AADNonInteractiveUserSignInLogs]
tactics: [InitialAccess]
relevantTechniques: [T1078]
query: |
  AADNonInteractiveUserSignInLogs | where ResultType == 50057
version: 1.0.0
"@
    'Hunting Queries/OfficeActivity/Mail.yaml'                              = (& $stub 'bbbbbbbb-0000-4000-8000-000000000003' 'Mail rule (stub)' 'https://github.com/Azure/Azure-Sentinel/blob/master/Solutions/Microsoft%20365/Hunting%20Queries/Mail.yaml')
    'Solutions/Microsoft 365/Hunting Queries/Mail.yaml'                     = "id: $($id.Mail)`r`nname: Mail redirect rule`r`ndescription: |`r`n  Mail redirected by a transport rule.`r`nrequiredDataConnectors:`r`n  - connectorId: Office365`r`n    dataTypes:`r`n      - OfficeActivity (Exchange)`r`ntactics:`r`n  - Collection`r`nquery: |`r`n  OfficeActivity`r`n  | where Operation == 'New-TransportRule'`r`n"
    'Hunting Queries/CloudAppEvents/Cloud.yaml'                             = @"
id: $($id.Cloud)
name: Cloud app policy change
description: A policy changed.
requiredDataConnectors:
  - connectorId: MicrosoftThreatProtection
    dataTypes:
      - CloudAppEvents
tactics:
  - DefenseEvasion
query: |
  CloudAppEvents | take 1
"@
    'Hunting Queries/AuditLogs/Consent.yaml'                                = @"
id: $($id.Consent)
name: Consent granted to a VIP
description: Admin consent for a VIP.
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - AuditLogs
tactics:
  - Persistence
query: |
  let vip = _GetWatchlist('VIPUsers') | project SearchKey;
  AuditLogs | where InitiatedBy in (vip)
"@
    'Hunting Queries/MultipleDataSources/Both.yaml'                         = @"
id: $($id.Both)
name: Sign-in then mailbox access
description: Across sign-ins and Exchange.
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - SigninLogs
  - connectorId: Office365
    dataTypes:
      - OfficeActivity
tactics:
  - Collection
query: |
  SigninLogs | join OfficeActivity on UserId
"@
    'Hunting Queries/MultipleDataSources/Aws.yaml'                          = @"
id: $($id.Aws)
name: AWS only
description: For no pack.
requiredDataConnectors:
  - connectorId: AWS
    dataTypes:
      - AWSCloudTrail
tactics:
  - Impact
query: |
  AWSCloudTrail | take 1
"@
    'Hunting Queries/MultipleDataSources/Elsewhere.yaml'                    = (& $stub 'bbbbbbbb-0000-4000-8000-000000000008' 'Points outside the repository' 'https://github.com/someone/other/blob/master/Evil.yaml')
    'Hunting Queries/MultipleDataSources/Climbing.yaml'                     = (& $stub 'bbbbbbbb-0000-4000-8000-000000000009' 'Climbs out of the repository' 'https://github.com/Azure/Azure-Sentinel/blob/master/../../other/Evil.yaml')
    # In another repository: for -YamlSource.
    'custom/Own.yaml'                                                       = @"
id: aaaaaaaa-0000-4000-8000-000000000010
name: Our own query
description: Written in-house.
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - SigninLogs
tactics:
  - Discovery
query: |
  SigninLogs | take 1
"@
    'custom/StubElsewhere.yaml'                                             = (& $stub 'bbbbbbbb-0000-4000-8000-000000000011' 'A stub outside Azure-Sentinel' 'https://github.com/Azure/Azure-Sentinel/blob/master/Solutions/Microsoft%20365/Hunting%20Queries/Mail.yaml')
    'custom/BadId.yaml'                                                     = "id: ../../../providers/Microsoft.Authorization/roleAssignments/x`nname: Tries to reach another resource`ndescription: d`nquery: |`n  SigninLogs`n"
}
$listing = @{
    SigninLogs          = @('BruteForce.yaml', 'Disabled.yaml', 'readme.md')
    OfficeActivity      = @('Mail.yaml')
    CloudAppEvents      = @('Cloud.yaml')
    AuditLogs           = @('Consent.yaml')
    MultipleDataSources = @('Both.yaml', 'Aws.yaml', 'Elsewhere.yaml', 'Climbing.yaml')
}
@{
    WorkspaceId = 'aaaaaaaa-bbbb-cccc-dddd-ffffffffffff'
    ResourceId  = $ws
    Workspace   = @{ id = $ws; name = 'law-contoso-sentinel'; location = 'uksouth'; properties = @{ customerId = 'aaaaaaaa-bbbb-cccc-dddd-ffffffffffff' } }
    Files       = $files
    Listing     = $listing
    Tables      = @('SigninLogs', 'AADNonInteractiveUserSignInLogs', 'OfficeActivity', 'AuditLogs', 'IntuneAuditLogs')
    Id          = $id
}
